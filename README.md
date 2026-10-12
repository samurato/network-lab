# netops-lab

A dual-data-centre **Arista EVPN-VXLAN multi-site** network, with a **Kubernetes cluster stretched across
both DCs**, Internet users and attackers behind a WAN, and streaming telemetry to Elastic. All of it is
built from this repository by infrastructure-as-code and kept in sync by GitOps.

It was built for the Auto-SRE hackathon. When something breaks at 3 AM, an AI agent reads the telemetry in
Elastic and fixes the network by opening a pull request against this repo, for an engineer to review.

## The whole system on one page

![netops-lab architecture: Git, infrastructure as code, the lab with WAN, two EVPN data centres and Kubernetes, observability and the agent loop](docs/images/architecture.svg)

How to read it, left to right:
1. **Git is the source of truth.** `network/` describes the switches and the WAN; `kubernetes/` describes the
   cluster and what runs in it.
2. **Infrastructure as code turns it into a running lab.**
   - AVD and `render.py` generate every config and the topology.
   - containerlab cables it, and Ansible pushes config changes.
   - Terraform builds everything inside Kubernetes.
3. **The lab itself.**
   - Two EVPN-VXLAN data centres, joined by EVPN gateways over an FRR WAN.
   - Kubernetes nodes plug into the leaves like servers and announce pod networks and VIPs over BGP.
   - Internet users and an attacker sit behind the WAN.
4. **Observability.** Every switch streams gNMI to an OTel Collector. Export to Elastic, where the Auto-SRE
   agent watches, is built but waits for an endpoint ([roadmap](docs/observability-roadmap.md)).
5. **The loop closes with a pull request.** CI plans it, an engineer approves, and the merge deploys it.

Each layer has its own detailed diagrams in [docs/architecture.md](docs/architecture.md).

| Layer | What runs | Built by |
|---|---|---|
| **Network** | 14 Arista cEOS switches (OSPF underlay, iBGP EVPN, EVPN gateways between DCs) + 2 FRR WAN routers | `network/` → AVD + `render.py` → containerlab / `make apply` |
| **Compute** | 6 k3s nodes, each on a routed /31 to a leaf; 3 control-plane nodes (DC1, DC2, WAN tie-breaker) | `kubernetes/cluster.yml` → `render.py` → containerlab |
| **Platform and apps** | Cilium (native routing, BGP to the leaves, load-balancer VIPs), the web app 2 + 2 across the DCs, iperf3 servers | `kubernetes/terraform/` → Terraform |
| **Traffic** | k6 users and a rate-capped attacker behind the WAN, link faults with netem | `network/wan.yml` |
| **Observability** | gNMI from every switch and the web app's traces → EDOT Collector → Elastic, plus a change event per deploy; the Elastic side is Terraform | `automation/telemetry/`, `containerlab/telemetry/`, `elastic/terraform/` |

The web app answers on **192.0.2.10** (public, from the WAN) and **10.99.0.10** (inside the DCs).

## Documentation

| Guide | For |
|---|---|
| [Architecture](docs/architecture.md) | the full design, with diagrams of every layer, design decisions and known gaps |
| [IP plan](docs/ip-plan.md) | every subnet, address, AS number and the VIP registry |
| [Network engineer's guide](docs/network-engineer-guide.md) | changing the fabric, routing and policy safely |
| [Streaming telemetry](docs/telemetry.md) | the gNMI → OTel Collector → Elastic pipeline, its data and its roadmap |
| [Observability roadmap](docs/observability-roadmap.md) | the step-by-step plan for end-to-end observability (network → Kubernetes → Cilium → app) |
| [Elastic](docs/elastic.md) | the Elastic project: settings and keys, collector profiles, data streams, dashboards, `elastic/terraform` |
| [DevOps guide](docs/devops-guide.md) | running the lab, CI/CD, Elastic export, traffic and faults, troubleshooting |
| [Cilium](docs/cilium.md) | the pod network: native routing, BGP to the leaves, VIPs, Hubble, troubleshooting |
| [Kubernetes guide](docs/kubernetes-guide.md) | operating the cluster: nodes, Cilium, BGP, VIP pools, upgrades |
| [Developer guide](docs/developer-guide.md) | deploying and exposing an app, step by step |

## The repository

```
network/        YOU EDIT: the switches and WAN: inventory, group_vars (routing, VLANs/VRFs, cabling,
                management, per-DC design + route policy), hosts.yml, wan.yml
kubernetes/     YOU EDIT: the cluster: cluster.yml (nodes, links, pod CIDRs, VIP pools),
                node/entrypoint.sh, terraform/ (Cilium, BGP, pools, apps)
docs/           design and guides
generated/      build output: EOS configs, fabric docs, Ansible inventory, Terraform input. Never edit.
containerlab/   build output: the deployable lab bundle (topology, startup configs, telemetry). Never edit
                except static/ and telemetry/otelcol/.
elastic/        YOU EDIT: everything inside the Elastic project (terraform/: templates, space, data views, dashboards)
automation/     tooling: render.py, Ansible playbooks/roles, lab + k8s helpers, verify.sh, CI scripts
.github/        workflows (plan, deploy, drift) and CODEOWNERS
Makefile        every command (make help)
```

## Quick start (on the lab host)

```bash
cd ~/hackathon/netops-lab
make up          # build, deploy network + k3s, Terraform the cluster, verify (~10 min)
make verify      # 60+ checks: OSPF, BGP/EVPN, isolation, pings, VRF handoff, k8s, VIPs, telemetry
make down        # destroy
```

| Command | Does |
|---|---|
| `make build` | `network/` + `kubernetes/` → `generated/` + `containerlab/` (offline, ~30 s) |
| `make plan` / `make apply` | network: per-device diff / push (EOS config replace, FRR reload) |
| `make k8s-plan` / `make k8s` | Kubernetes: Terraform plan / apply |
| `make up` / `make redeploy` / `make down` | deploy / wipe and redeploy / destroy the lab |
| `make verify` | all health checks |
| `make graph`, `make status` | live topology view, node list |
| `automation/lab cli <node>` | EOS CLI on a switch, `vtysh` on a WAN router |
| `automation/k8s kubectl …` | kubectl against the cluster |

Credentials: `EOS_USER` / `EOS_PASSWORD` (lab default admin/admin), `K3S_TOKEN` (default `netops-lab`).
Elastic: `automation/elastic.env` (git-ignored, see `elastic.env.example` and [docs/elastic.md](docs/elastic.md)).
`make elastic` applies `elastic/terraform/`.

## Making a change

1. Edit `network/` (switches) or `kubernetes/` (cluster and apps). The guides list which file holds what.
2. `make build`, then review `git diff generated/` (exact EOS lines).
3. `make plan` and/or `make k8s-plan`: see what would change on the running lab.
4. Open a pull request. CI posts the plan, a network reviewer approves, and the merge deploys and verifies.
