# dc1-spine1

## Table of Contents

- [Management](#management)
  - [Management Interfaces](#management-interfaces)
  - [Management API gNMI](#management-api-gnmi)
  - [Management API HTTP](#management-api-http)
- [Authentication](#authentication)
  - [Local Users](#local-users)
  - [Enable Password](#enable-password)
- [Spanning Tree](#spanning-tree)
  - [Spanning Tree Summary](#spanning-tree-summary)
  - [Spanning Tree Device Configuration](#spanning-tree-device-configuration)
- [Internal VLAN Allocation Policy](#internal-vlan-allocation-policy)
  - [Internal VLAN Allocation Policy Summary](#internal-vlan-allocation-policy-summary)
  - [Internal VLAN Allocation Policy Device Configuration](#internal-vlan-allocation-policy-device-configuration)
- [Interfaces](#interfaces)
  - [Ethernet Interfaces](#ethernet-interfaces)
  - [Loopback Interfaces](#loopback-interfaces)
- [Routing](#routing)
  - [Service Routing Protocols Model](#service-routing-protocols-model)
  - [IP Routing](#ip-routing)
  - [IPv6 Routing](#ipv6-routing)
  - [Static Routes](#static-routes)
  - [Router OSPF](#router-ospf)
  - [Router BGP](#router-bgp)
- [BFD](#bfd)
  - [Router BFD](#router-bfd)
- [VRF Instances](#vrf-instances)
  - [VRF Instances Summary](#vrf-instances-summary)
  - [VRF Instances Device Configuration](#vrf-instances-device-configuration)
- [EOS CLI Device Configuration](#eos-cli-device-configuration)

## Management

### Management Interfaces

#### Management Interfaces Summary

##### IPv4

| Management Interface | Description | Type | VRF | IP Address | Gateway |
| -------------------- | ----------- | ---- | --- | ---------- | ------- |
| Management1 | OOB_MANAGEMENT | oob | MGMT | 172.20.20.11/24 | 172.20.20.1 |

##### IPv6

| Management Interface | Description | Type | VRF | IPv6 Address | IPv6 Gateway | ND RA Disabled | ND RA RX Accept | ND Managed Config Flag | ND Other Config Flag | ND Cache | ND RA DNS Servers |
| -------------------- | ----------- | ---- | --- | ------------ | ------------ | -------------- | --------------- | ---------------------- | -------------------- | -------- | ----------------- |
| Management1 | OOB_MANAGEMENT | oob | MGMT | - | - | - | - | - | - | - | - |

#### Management Interfaces Device Configuration

```eos
!
interface Management1
   description OOB_MANAGEMENT
   no shutdown
   vrf MGMT
   ip address 172.20.20.11/24
```

### Management API gNMI

#### Management API gNMI Summary

| Transport | SSL Profile | VRF | Notification Timestamp | ACL | Port | Authorization Requests |
| --------- | ----------- | --- | ---------------------- | --- | ---- | ---------------------- |
| default | - | MGMT | last-change-time | - | 6030 | - |

Provider eos-native is configured.

#### Management API gNMI Device Configuration

```eos
!
management api gnmi
   transport grpc default
      vrf MGMT
   provider eos-native
```

### Management API HTTP

#### Management API HTTP Summary

| HTTP | HTTPS | UNIX-Socket | Default Services | Session Timeout |
| ---- | ----- | ----------- | ---------------- | --------------- |
| False | True | - | - | 1440 minutes |

#### Management API VRF Access

| VRF Name | IPv4 ACL | IPv6 ACL |
| -------- | -------- | -------- |
| MGMT | - | - |

#### Management API HTTP Device Configuration

```eos
!
management api http-commands
   protocol https
   no shutdown
   !
   vrf MGMT
      no shutdown
```

## Authentication

### Local Users

#### Local Users Summary

| User | Privilege | Role | Disabled | Shell |
| ---- | --------- | ---- | -------- | ----- |
| admin | 15 | network-admin | False | - |

#### Local Users Device Configuration

```eos
!
username admin privilege 15 role network-admin secret sha512 <removed>
```

### Enable Password

Enable password has been disabled

## Spanning Tree

### Spanning Tree Summary

STP mode: **none**

### Spanning Tree Device Configuration

```eos
!
spanning-tree mode none
```

## Internal VLAN Allocation Policy

### Internal VLAN Allocation Policy Summary

| Policy Allocation | Range Beginning | Range Ending |
| ----------------- | --------------- | ------------ |
| ascending | 1006 | 1199 |

### Internal VLAN Allocation Policy Device Configuration

```eos
!
vlan internal order ascending range 1006 1199
```

## Interfaces

### Ethernet Interfaces

#### Ethernet Interfaces Summary

##### L2

| Interface | Description | Mode | VLANs | Native VLAN | Trunk Group | Channel-Group |
| --------- | ----------- | ---- | ----- | ----------- | ----------- | ------------- |

*Inherited from Port-Channel Interface

##### IPv4

| Interface | Description | Channel Group | IP Address | VRF | MTU | Shutdown | ACL In | ACL Out |
| --------- | ----------- | ------------- | ---------- | --- | --- | -------- | ------ | ------- |
| Ethernet1 | P2P_dc1-leaf1_Ethernet1 | - | 10.1.255.0/31 | default | 9214 | False | - | - |
| Ethernet2 | P2P_dc1-leaf2_Ethernet1 | - | 10.1.255.4/31 | default | 9214 | False | - | - |
| Ethernet3 | P2P_dc1-leaf3_Ethernet1 | - | 10.1.255.8/31 | default | 9214 | False | - | - |
| Ethernet4 | P2P_dc1-leaf4_Ethernet1 | - | 10.1.255.12/31 | default | 9214 | False | - | - |
| Ethernet5 | P2P_dc1-bgw1_Ethernet1 | - | 10.1.255.16/31 | default | 9214 | False | - | - |
| Ethernet6 | P2P_dc1-bgw2_Ethernet1 | - | 10.1.255.20/31 | default | 9214 | False | - | - |

#### Ethernet Interfaces Device Configuration

```eos
!
interface Ethernet1
   description P2P_dc1-leaf1_Ethernet1
   no shutdown
   mtu 9214
   no switchport
   ip address 10.1.255.0/31
   ip ospf network point-to-point
   ip ospf area 0.0.0.0
!
interface Ethernet2
   description P2P_dc1-leaf2_Ethernet1
   no shutdown
   mtu 9214
   no switchport
   ip address 10.1.255.4/31
   ip ospf network point-to-point
   ip ospf area 0.0.0.0
!
interface Ethernet3
   description P2P_dc1-leaf3_Ethernet1
   no shutdown
   mtu 9214
   no switchport
   ip address 10.1.255.8/31
   ip ospf network point-to-point
   ip ospf area 0.0.0.0
!
interface Ethernet4
   description P2P_dc1-leaf4_Ethernet1
   no shutdown
   mtu 9214
   no switchport
   ip address 10.1.255.12/31
   ip ospf network point-to-point
   ip ospf area 0.0.0.0
!
interface Ethernet5
   description P2P_dc1-bgw1_Ethernet1
   no shutdown
   mtu 9214
   no switchport
   ip address 10.1.255.16/31
   ip ospf network point-to-point
   ip ospf area 0.0.0.0
!
interface Ethernet6
   description P2P_dc1-bgw2_Ethernet1
   no shutdown
   mtu 9214
   no switchport
   ip address 10.1.255.20/31
   ip ospf network point-to-point
   ip ospf area 0.0.0.0
```

### Loopback Interfaces

#### Loopback Interfaces Summary

##### IPv4

| Interface | Description | VRF | IP Address |
| --------- | ----------- | --- | ---------- |
| Loopback0 | ROUTER_ID | default | 10.1.0.1/32 |

##### IPv6

| Interface | Description | VRF | IPv6 Addresses |
| --------- | ----------- | --- | -------------- |
| Loopback0 | ROUTER_ID | default | - |

#### Loopback Interfaces Device Configuration

```eos
!
interface Loopback0
   description ROUTER_ID
   no shutdown
   ip address 10.1.0.1/32
   ip ospf area 0.0.0.0
```

## Routing

### Service Routing Protocols Model

Multi agent routing protocol model enabled

```eos
!
service routing protocols model multi-agent
```

### IP Routing

#### IP Routing Summary

| VRF | Routing Enabled |
| --- | --------------- |
| default | True |
| MGMT | False |

#### IP Routing Device Configuration

```eos
!
ip routing
no ip routing vrf MGMT
```

### IPv6 Routing

#### IPv6 Routing Summary

| VRF | Routing Enabled |
| --- | --------------- |
| default | False |
| MGMT | False |

### Static Routes

#### Static Routes Summary

| VRF | Destination Prefix | Next Hop IP | Exit interface | Administrative Distance | Tag | Route Name | Metric |
| --- | ------------------ | ----------- | -------------- | ----------------------- | --- | ---------- | ------ |
| MGMT | 0.0.0.0/0 | 172.20.20.1 | - | 1 | - | - | - |

#### Static Routes Device Configuration

```eos
!
ip route vrf MGMT 0.0.0.0/0 172.20.20.1
```

### Router OSPF

#### Router OSPF Summary

| Process ID | Router ID | Default Passive Interface | No Passive Interface | BFD | Max LSA | Default Information Originate | Log Adjacency Changes Detail | Auto Cost Reference Bandwidth | Maximum Paths | MPLS LDP Sync Default | Distribute List In |
| ---------- | --------- | ------------------------- | -------------------- | --- | ------- | ----------------------------- | ---------------------------- | ----------------------------- | ------------- | --------------------- | ------------------ |
| 100 | 10.1.0.1 | enabled | Ethernet1<br>Ethernet2<br>Ethernet3<br>Ethernet4<br>Ethernet5<br>Ethernet6 | disabled | 12000 | disabled | disabled | - | - | - | - |

#### OSPF Interfaces

| Interface | Area | Cost | Point To Point |
| -------- | -------- | -------- | -------- |
| Ethernet1 | 0.0.0.0 | - | True |
| Ethernet2 | 0.0.0.0 | - | True |
| Ethernet3 | 0.0.0.0 | - | True |
| Ethernet4 | 0.0.0.0 | - | True |
| Ethernet5 | 0.0.0.0 | - | True |
| Ethernet6 | 0.0.0.0 | - | True |
| Loopback0 | 0.0.0.0 | - | - |

#### Router OSPF Device Configuration

```eos
!
router ospf 100
   router-id 10.1.0.1
   passive-interface default
   no passive-interface Ethernet1
   no passive-interface Ethernet2
   no passive-interface Ethernet3
   no passive-interface Ethernet4
   no passive-interface Ethernet5
   no passive-interface Ethernet6
   max-lsa 12000
   graceful-restart
```

### Router BGP

ASN Notation: asplain

#### Router BGP Summary

| BGP AS | Router ID |
| ------ | --------- |
| 65100 | 10.1.0.1 |

| BGP AS | Cluster ID |
| ------ | --------- |
| 65100 | 10.1.0.1 |

| BGP Tuning |
| ---------- |
| no bgp default ipv4-unicast |
| maximum-paths 4 |

#### Router BGP Peer Groups

##### EVPN-OVERLAY-PEERS

| Settings | Value |
| -------- | ----- |
| Address Family | evpn |
| Remote AS | 65100 |
| Route Reflector Client | Yes |
| Source | Loopback0 |
| BFD | True |
| Send community | all |
| Maximum routes | 0 (no limit) |

#### BGP Neighbors

| Neighbor | Remote AS | VRF | Shutdown | Send-community | Maximum-routes | Maximum-accepted-routes | Maximum-advertised-routes | Allowas-in | BFD | RIB Pre-Policy Retain | Route-Reflector Client | Passive | TTL Max Hops |
| -------- | --------- | --- | -------- | -------------- | -------------- | ----------------------- | ------------------------- | ---------- | --- | --------------------- | ---------------------- | ------- | ------------ |
| 10.1.0.11 | Inherited from peer group EVPN-OVERLAY-PEERS | default | - | Inherited from peer group EVPN-OVERLAY-PEERS | Inherited from peer group EVPN-OVERLAY-PEERS | - | - | - | Inherited from peer group EVPN-OVERLAY-PEERS | - | Inherited from peer group EVPN-OVERLAY-PEERS | - | - |
| 10.1.0.12 | Inherited from peer group EVPN-OVERLAY-PEERS | default | - | Inherited from peer group EVPN-OVERLAY-PEERS | Inherited from peer group EVPN-OVERLAY-PEERS | - | - | - | Inherited from peer group EVPN-OVERLAY-PEERS | - | Inherited from peer group EVPN-OVERLAY-PEERS | - | - |
| 10.1.0.13 | Inherited from peer group EVPN-OVERLAY-PEERS | default | - | Inherited from peer group EVPN-OVERLAY-PEERS | Inherited from peer group EVPN-OVERLAY-PEERS | - | - | - | Inherited from peer group EVPN-OVERLAY-PEERS | - | Inherited from peer group EVPN-OVERLAY-PEERS | - | - |
| 10.1.0.14 | Inherited from peer group EVPN-OVERLAY-PEERS | default | - | Inherited from peer group EVPN-OVERLAY-PEERS | Inherited from peer group EVPN-OVERLAY-PEERS | - | - | - | Inherited from peer group EVPN-OVERLAY-PEERS | - | Inherited from peer group EVPN-OVERLAY-PEERS | - | - |
| 10.1.0.15 | Inherited from peer group EVPN-OVERLAY-PEERS | default | - | Inherited from peer group EVPN-OVERLAY-PEERS | Inherited from peer group EVPN-OVERLAY-PEERS | - | - | - | Inherited from peer group EVPN-OVERLAY-PEERS | - | Inherited from peer group EVPN-OVERLAY-PEERS | - | - |
| 10.1.0.16 | Inherited from peer group EVPN-OVERLAY-PEERS | default | - | Inherited from peer group EVPN-OVERLAY-PEERS | Inherited from peer group EVPN-OVERLAY-PEERS | - | - | - | Inherited from peer group EVPN-OVERLAY-PEERS | - | Inherited from peer group EVPN-OVERLAY-PEERS | - | - |

#### Router BGP EVPN Address Family

##### EVPN Peer Groups

| Peer Group | Activate | Route-map In | Route-map Out | Peer-tag In | Peer-tag Out | Encapsulation | Next-hop-self Source Interface |
| ---------- | -------- | ------------ | ------------- | ----------- | ------------ | ------------- | ------------------------------ |
| EVPN-OVERLAY-PEERS | True | - | - | - | - | default | - |

#### Router BGP Device Configuration

```eos
!
router bgp 65100
   router-id 10.1.0.1
   no bgp default ipv4-unicast
   bgp cluster-id 10.1.0.1
   maximum-paths 4
   neighbor EVPN-OVERLAY-PEERS peer group
   neighbor EVPN-OVERLAY-PEERS remote-as 65100
   neighbor EVPN-OVERLAY-PEERS update-source Loopback0
   neighbor EVPN-OVERLAY-PEERS bfd
   neighbor EVPN-OVERLAY-PEERS route-reflector-client
   neighbor EVPN-OVERLAY-PEERS send-community
   neighbor EVPN-OVERLAY-PEERS maximum-routes 0
   neighbor 10.1.0.11 peer group EVPN-OVERLAY-PEERS
   neighbor 10.1.0.11 description dc1-leaf1_Loopback0
   neighbor 10.1.0.12 peer group EVPN-OVERLAY-PEERS
   neighbor 10.1.0.12 description dc1-leaf2_Loopback0
   neighbor 10.1.0.13 peer group EVPN-OVERLAY-PEERS
   neighbor 10.1.0.13 description dc1-leaf3_Loopback0
   neighbor 10.1.0.14 peer group EVPN-OVERLAY-PEERS
   neighbor 10.1.0.14 description dc1-leaf4_Loopback0
   neighbor 10.1.0.15 peer group EVPN-OVERLAY-PEERS
   neighbor 10.1.0.15 description dc1-bgw1_Loopback0
   neighbor 10.1.0.16 peer group EVPN-OVERLAY-PEERS
   neighbor 10.1.0.16 description dc1-bgw2_Loopback0
   !
   address-family evpn
      neighbor EVPN-OVERLAY-PEERS activate
   !
   address-family ipv4
      no neighbor EVPN-OVERLAY-PEERS activate
```

## BFD

### Router BFD

#### Router BFD Multihop Summary

| Interval | Minimum RX | Multiplier |
| -------- | ---------- | ---------- |
| 300 | 300 | 3 |

#### Router BFD Device Configuration

```eos
!
router bfd
   multihop interval 300 min-rx 300 multiplier 3
```

## VRF Instances

### VRF Instances Summary

| VRF Name | IP Routing |
| -------- | ---------- |
| MGMT | disabled |

### VRF Instances Device Configuration

```eos
!
vrf instance MGMT
```

## EOS CLI Device Configuration

```eos
!
platform tfa
   personality arfa

```
