# kubernetes/ — the k3s cluster across both DCs

Everything about the Kubernetes infrastructure lives here. The switches it plugs into are in `../network/`.

```
cluster.yml       SOURCE OF TRUTH: nodes, the leaf (or WAN router) port each plugs into, its /31,
                  BGP AS, pod CIDR, management IP; cluster CIDRs and load-balancer VIP pools
node/entrypoint.sh  k3s node entrypoint: addresses the fabric link, prepares cgroups/bpffs, starts k3s
terraform/        everything inside the cluster, applied with `make k8s`
  main.tf           providers, reads ../../generated/kubernetes.yml
  nodes.tf          per-node pod CIDRs, loads lab-built images (chaos2cure/web) into the nodes
  cilium.tf         Cilium: native routing, BGP control plane, LB IPAM
  bgp.tf            per-node BGP session to its switch, what nodes announce, VIP pools
  apps.tf           namespace prod: web (+ VIPs), reserved db Service, iperf3 servers
```

## How it fits together

1. `make build` reads `cluster.yml` and generates
   - the switch side: leaf port + /31 + eBGP peer per node (AVD), the tie-breaker's port on wan1 (FRR);
   - the k3s nodes in `containerlab/netops.clab.yml` (node IP pinned to the fabric link);
   - `generated/kubernetes.yml`: `cluster.yml` plus each node's peer IP and AS, for Terraform.
2. `make up` / `make redeploy` start the nodes (containerlab), then `make k8s` (Terraform) installs Cilium,
   sets the BGP sessions and pools, and deploys the apps.

| I want to… | Do |
|---|---|
| add or move a node, change addressing or VIP pools | edit `cluster.yml`, `make build`, `make redeploy` |
| change an app, add one | edit `terraform/apps.tf`, `make k8s-plan`, `make k8s` |
| change Cilium or BGP behaviour | edit `terraform/cilium.tf` / `bgp.tf`, `make k8s-plan`, `make k8s` |
| change what the switches accept from the nodes | `RM-K8S-IN` / `PL-K8S-IN` in `../network/group_vars/DC1.yml`, `DC2.yml` |
| run kubectl | `automation/k8s kubectl get pods -A` (kubeconfig: `~/.kube/netops.yaml`) |

Terraform state is kept in the running lab's directory (`~/clab-runs/clab-netops/`) and goes away with
`make down`; provider binaries are cached in `~/.cache/netops/`.
