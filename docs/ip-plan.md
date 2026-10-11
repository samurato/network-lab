# IP plan and AS numbers

Every address in the lab, in one place. The **source** column says which file to change; everything else is
generated from it by `make build`.

**Numbering rule.** The second octet says where you are: `10.1x` is DC1, `10.2x` is DC2, `10.3x` is a WAN-side
site, and `10.255` is WAN transport. Documentation ranges (`192.0.2.0/24`, `198.51.100.0/24`,
`203.0.113.0/24`) stand in for public Internet addresses.

## AS numbers

| AS | Who | Source |
|---|---|---|
| 65100 | every DC1 switch (iBGP EVPN) | `network/group_vars/DC1.yml` |
| 65200 | every DC2 switch (iBGP EVPN) | `network/group_vars/DC2.yml` |
| 64901 / 64902 | wan1 / wan2 | `network/wan.yml` |
| 65101 | DC1 Kubernetes nodes | `kubernetes/cluster.yml` |
| 65201 | DC2 Kubernetes nodes | `kubernetes/cluster.yml` |
| 65301 | WAN-site Kubernetes node (tie-breaker) | `kubernetes/cluster.yml` |

## Fabric (underlay)

| Block | Use | Source |
|---|---|---|
| 10.1.0.0/24 | DC1 Loopback0 (router ID, EVPN peering): spines .1–.2, leaves .11–.14, BGWs .15–.16 | `DC1.yml` |
| 10.1.1.0/24 | DC1 Loopback1 (VTEP): leaves .11–.14, BGWs .15–.16 | `DC1.yml` |
| 10.1.255.0/24 | DC1 leaf/BGW ↔ spine /31s | `DC1.yml` |
| 10.2.0.0/24 | DC2 Loopback0: spines .1–.2, leaves .11–.12, BGWs .15–.16 | `DC2.yml` |
| 10.2.1.0/24 | DC2 Loopback1 (VTEP) | `DC2.yml` |
| 10.2.255.0/24 | DC2 leaf/BGW ↔ spine /31s | `DC2.yml` |
| 10.255.0.0/24 | BGW ↔ WAN /31s, underlay (.0–.15 used; the BGW takes the even address) | `FABRIC/cabling.yml` |
| 10.255.1.0/31 | wan1 ↔ wan2, underlay | `wan.yml` |
| 10.255.255.1 / .2 | wan1 / wan2 loopbacks | `wan.yml` |

BGW ↔ WAN links in detail (underlay; VRF PROD uses the same last octet in `10.255.10.0/24`):

| Link | BGW side | WAN side | VRF PROD (`.100` sub-interface) |
|---|---|---|---|
| dc1-bgw1 Ethernet3 ↔ wan1 eth1 | 10.255.0.0 | 10.255.0.1 | 10.255.10.0 / .1 |
| dc1-bgw2 Ethernet3 ↔ wan1 eth2 | 10.255.0.2 | 10.255.0.3 | 10.255.10.2 / .3 |
| dc2-bgw1 Ethernet3 ↔ wan1 eth3 | 10.255.0.4 | 10.255.0.5 | 10.255.10.4 / .5 |
| dc2-bgw2 Ethernet3 ↔ wan1 eth4 | 10.255.0.6 | 10.255.0.7 | 10.255.10.6 / .7 |
| dc1-bgw1 Ethernet4 ↔ wan2 eth1 | 10.255.0.8 | 10.255.0.9 | 10.255.10.8 / .9 |
| dc1-bgw2 Ethernet4 ↔ wan2 eth2 | 10.255.0.10 | 10.255.0.11 | 10.255.10.10 / .11 |
| dc2-bgw1 Ethernet4 ↔ wan2 eth3 | 10.255.0.12 | 10.255.0.13 | 10.255.10.12 / .13 |
| dc2-bgw2 Ethernet4 ↔ wan2 eth4 | 10.255.0.14 | 10.255.0.15 | 10.255.10.14 / .15 |
| wan1 eth5 ↔ wan2 eth5 | — | 10.255.1.0 / .1 | 10.255.11.0 / .1 |

## Tenant VRF PROD (L3 VNI 1000)

| Block | Use | Routed to the WAN? | Source |
|---|---|---|---|
| 10.10.10.0/24 | VLAN 110 WEB, DC1 (gateway .1) | yes | `FABRIC/vlans-vrfs.yml` |
| 10.10.20.0/24 | VLAN 120 APP, DC1 | yes | `FABRIC/vlans-vrfs.yml` |
| 10.10.30.0/24 | reserved: future DC1 database replica (VLAN 230) | **never** | `DC1.yml` route-map |
| 10.10.40.0/24 | DC1 Kubernetes node /31s | yes | `kubernetes/cluster.yml` |
| 10.11.0.0/16 | DC1 pods, one /24 per node | yes | `kubernetes/cluster.yml` |
| 10.15.0.0/24 | VLAN 150 STRETCH, both DCs (L2 stretched) | no | `FABRIC/vlans-vrfs.yml` |
| 10.20.30.0/24 | VLAN 130 DB, DC2; **10.20.30.10 = reserved DB VIP** | **never** | `FABRIC/vlans-vrfs.yml`, `DC2.yml` |
| 10.20.40.0/24 | DC2 Kubernetes node /31s | yes | `kubernetes/cluster.yml` |
| 10.21.0.0/16 | DC2 pods | yes | `kubernetes/cluster.yml` |
| 10.30.40.0/24 | WAN-site Kubernetes node /31s | — (it is on the WAN) | `kubernetes/cluster.yml` |
| 10.31.0.0/16 | WAN-site pods | — | `kubernetes/cluster.yml` |
| 10.43.0.0/16 | Kubernetes Services (ClusterIP); DNS 10.43.0.10 | not routed | `kubernetes/cluster.yml` |
| 10.99.0.0/24 | load-balancer VIPs, internal | **never** | `kubernetes/cluster.yml` |
| 192.0.2.0/24 | load-balancer VIPs, public | yes | `kubernetes/cluster.yml` |
| 198.51.100.0/24 | Internet users site behind wan2 (router .1) | — | `wan.yml` |
| 203.0.113.0/24 | attacker site behind wan1 (router .1) | — | `wan.yml` |

## Hosts and nodes

| Name | Data-plane IP | Attached to | Management IP |
|---|---|---|---|
| dc1-web1 / dc1-web2 | 10.10.10.11 / .12 (VLAN 110) | dc1-leaf1 / dc1-leaf2 Ethernet5 | dynamic |
| dc1-app1 / dc1-app2 | 10.10.20.13 / .14 (VLAN 120) | dc1-leaf3 / dc1-leaf4 Ethernet5 | dynamic |
| dc1-stretch1 | 10.15.0.11 (VLAN 150) | dc1-leaf2 Ethernet6 | dynamic |
| dc2-db1 / dc2-db2 | 10.20.30.11 / .12 (VLAN 130) | dc2-leaf1 / dc2-leaf2 Ethernet5 | dynamic |
| dc2-stretch1 | 10.15.0.12 (VLAN 150) | dc2-leaf2 Ethernet6 | dynamic |
| dc1-k8s-cp1 | 10.10.40.1/31, pods 10.11.0.0/24 | dc1-leaf1 Ethernet7 (10.10.40.0) | 172.20.20.61 |
| dc1-k8s-wk1 | 10.10.40.3/31, pods 10.11.1.0/24 | dc1-leaf3 Ethernet7 | 172.20.20.62 |
| dc1-k8s-wk2 | 10.10.40.5/31, pods 10.11.2.0/24 | dc1-leaf4 Ethernet7 | 172.20.20.63 |
| dc2-k8s-cp2 | 10.20.40.1/31, pods 10.21.0.0/24 | dc2-leaf1 Ethernet7 | 172.20.20.64 |
| dc2-k8s-wk3 | 10.20.40.3/31, pods 10.21.1.0/24 | dc2-leaf2 Ethernet7 | 172.20.20.65 |
| wan-k8s-cp3 | 10.30.40.1/31, pods 10.31.0.0/24 | wan1 eth6 (10.30.40.0) | 172.20.20.66 |
| inet-k6 | 198.51.100.11/24 | wan2 eth7 | dynamic (no default route) |
| attacker1 | 203.0.113.66/24 | wan1 eth7 | dynamic (no default route) |

## Management network (172.20.20.0/24, Docker network `clab-mgmt`)

| Address | Node |
|---|---|
| .1 | Docker gateway (the host) |
| .11–.18 | DC1: spine1, spine2, leaf1–leaf4, bgw1, bgw2 |
| .21–.26 | DC2: spine1, spine2, leaf1, leaf2, bgw1, bgw2 |
| .41 / .42 | wan1 / wan2 |
| .61–.66 | Kubernetes nodes (table above); API server `https://172.20.20.61:6443` |
| .250 | OTel Collector (OTLP 4317 gRPC / 4318 HTTP; host port 9464 = metrics) |
| .251 | gnmic |

## Load-balancer VIP registry

Pick the next free address when you expose a new app ([developer guide](developer-guide.md)), and add it here
in the same PR.

| VIP | Service | Pool |
|---|---|---|
| 192.0.2.10 | `prod/web-public` | public |
| 10.99.0.10 | `prod/web-internal` | internal |
