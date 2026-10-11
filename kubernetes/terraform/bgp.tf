# BGP from every node to the switch on the other end of its /31 (the leaf, or wan1 for the tie-breaker).
# The switch side (peer, route-maps) is in network/: AVD for the leaves, FRR for the WAN.
resource "kubectl_manifest" "bgp_node" {
  for_each = local.nodes
  yaml_body = yamlencode({
    apiVersion = "cilium.io/v2"
    kind       = "CiliumBGPClusterConfig"
    metadata = {
      name = each.key
    }
    spec = {
      nodeSelector = {
        matchLabels = {
          "kubernetes.io/hostname" = each.key
        }
      }
      bgpInstances = [{
        name     = "fabric"
        localASN = each.value.asn
        peers = [{
          name        = each.value.peer
          peerASN     = each.value.peer_asn
          peerAddress = each.value.peer_ip
          peerConfigRef = {
            name = "fabric"
          }
        }]
      }]
    }
  })
  depends_on = [helm_release.cilium]
}

resource "kubectl_manifest" "bgp_peer_config" {
  yaml_body = yamlencode({
    apiVersion = "cilium.io/v2"
    kind       = "CiliumBGPPeerConfig"
    metadata = {
      name = "fabric"
    }
    spec = {
      timers = {
        holdTimeSeconds      = 9
        keepAliveTimeSeconds = 3
      }
      gracefulRestart = {
        enabled = true
      }
      families = [{
        afi  = "ipv4"
        safi = "unicast"
        advertisements = {
          matchLabels = {
            "netops.lab/advertise" = "fabric"
          }
        }
      }]
    }
  })
  depends_on = [helm_release.cilium]
}

# What every node announces: its pod /24, and the VIPs of LoadBalancer services it has a ready endpoint for
resource "kubectl_manifest" "bgp_advertise" {
  yaml_body = yamlencode({
    apiVersion = "cilium.io/v2"
    kind       = "CiliumBGPAdvertisement"
    metadata = {
      name = "fabric"
      labels = {
        "netops.lab/advertise" = "fabric"
      }
    }
    spec = {
      advertisements = [
        {
          advertisementType = "PodCIDR"
        },
        {
          advertisementType = "Service"
          service = {
            addresses = ["LoadBalancerIP"]
          }
          selector = { # every service (Cilium's idiom for "match all")
            matchExpressions = [{
              key      = "netops.lab/no-bgp"
              operator = "DoesNotExist"
            }]
          }
        },
      ]
    }
  })
  depends_on = [helm_release.cilium]
}

# Load-balancer address pools (kubernetes/cluster.yml).  "public" (192.0.2.0/24) is the only VIP range the
# border gateways hand to the WAN, and only services labelled netops.lab/exposure=public may use it;
# "internal" (10.99.0.0/24) is reachable inside the DCs only.
resource "kubectl_manifest" "lb_pool" {
  for_each = local.cluster.load_balancer_pools
  yaml_body = yamlencode({
    apiVersion = "cilium.io/v2"
    kind       = "CiliumLoadBalancerIPPool"
    metadata = {
      name = each.key
    }
    spec = merge(
      {
        blocks = [{
          cidr = each.value
        }]
      },
      each.key == "public" ? {
        serviceSelector = {
          matchLabels = {
            "netops.lab/exposure" = "public"
          }
        }
      } : {}
    )
  })
  depends_on = [helm_release.cilium]
}
