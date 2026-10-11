# Cilium: CNI with native routing (no overlay inside the fabric's VXLAN), BGP control plane, LB IPAM.
#   - pod IPs are real fabric addresses: every node announces its pod /24 to its leaf (bgp.tf)
#   - load-balancer VIPs come from the pools below and are announced only by nodes with a ready endpoint
#   - k3s keeps kube-proxy for Service forwarding; Cilium handles pods, BGP and VIP addressing
resource "helm_release" "cilium" {
  name       = "cilium"
  namespace  = "kube-system"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = local.cluster.cilium_version
  wait       = true
  timeout    = 900

  values = [yamlencode({
    ipam = {
      mode = "kubernetes" # pod CIDR per node from spec.podCIDR (nodes.tf)
    }
    routingMode           = "native"
    ipv4NativeRoutingCIDR = "10.0.0.0/8" # no masquerade inside the lab; the fabric routes pod IPs
    autoDirectNodeRoutes  = false        # nodes are on different /31s: the leaves route between them
    enableIPv4Masquerade  = true         # pods -> outside 10/8 (management, Internet) leave as the node
    kubeProxyReplacement  = false
    bgpControlPlane = {
      enabled = true
    }
    operator = {
      replicas = 1
    }
    hubble = {
      enabled = true
      relay = {
        enabled = false
      }
    }
  })]

  depends_on = [terraform_data.pod_cidr]
}
