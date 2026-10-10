# FABRIC

## Table of Contents

- [Fabric Switches and Management IP](#fabric-switches-and-management-ip)
  - [Fabric Switches with inband Management IP](#fabric-switches-with-inband-management-ip)
- [Fabric Topology](#fabric-topology)
- [Fabric IP Allocation](#fabric-ip-allocation)
  - [Fabric Point-To-Point Links](#fabric-point-to-point-links)
  - [Point-To-Point Links Node Allocation](#point-to-point-links-node-allocation)
  - [Loopback Interfaces (BGP EVPN Peering)](#loopback-interfaces-bgp-evpn-peering)
  - [Loopback0 Interfaces Node Allocation](#loopback0-interfaces-node-allocation)
  - [VTEP Loopback VXLAN Tunnel Source Interfaces (VTEPs Only)](#vtep-loopback-vxlan-tunnel-source-interfaces-vteps-only)
  - [VTEP Loopback Node allocation](#vtep-loopback-node-allocation)

## Fabric Switches and Management IP

| POD | Type | Node | Management IP | Platform | Provisioned in CloudVision | Serial Number |
| --- | ---- | ---- | ------------- | -------- | -------------------------- | ------------- |
| DC1 | l3leaf | dc1-bgw1 | 172.20.20.17/24 | cEOSLab | Provisioned | - |
| DC1 | l3leaf | dc1-bgw2 | 172.20.20.18/24 | cEOSLab | Provisioned | - |
| DC1 | l3leaf | dc1-leaf1 | 172.20.20.13/24 | cEOSLab | Provisioned | - |
| DC1 | l3leaf | dc1-leaf2 | 172.20.20.14/24 | cEOSLab | Provisioned | - |
| DC1 | l3leaf | dc1-leaf3 | 172.20.20.15/24 | cEOSLab | Provisioned | - |
| DC1 | l3leaf | dc1-leaf4 | 172.20.20.16/24 | cEOSLab | Provisioned | - |
| DC1 | spine | dc1-spine1 | 172.20.20.11/24 | cEOSLab | Provisioned | - |
| DC1 | spine | dc1-spine2 | 172.20.20.12/24 | cEOSLab | Provisioned | - |
| DC2 | l3leaf | dc2-bgw1 | 172.20.20.25/24 | cEOSLab | Provisioned | - |
| DC2 | l3leaf | dc2-bgw2 | 172.20.20.26/24 | cEOSLab | Provisioned | - |
| DC2 | l3leaf | dc2-leaf1 | 172.20.20.23/24 | cEOSLab | Provisioned | - |
| DC2 | l3leaf | dc2-leaf2 | 172.20.20.24/24 | cEOSLab | Provisioned | - |
| DC2 | spine | dc2-spine1 | 172.20.20.21/24 | cEOSLab | Provisioned | - |
| DC2 | spine | dc2-spine2 | 172.20.20.22/24 | cEOSLab | Provisioned | - |

> Provision status is based on Ansible inventory declaration and do not represent real status from CloudVision.

### Fabric Switches with inband Management IP

| POD | Type | Node | Management IP | Inband Interface |
| --- | ---- | ---- | ------------- | ---------------- |

## Fabric Topology

| Type | Node | Node Interface | Peer Type | Peer Node | Peer Interface |
| ---- | ---- | -------------- | --------- | --------- | -------------- |
| l3leaf | dc1-bgw1 | Ethernet1 | spine | dc1-spine1 | Ethernet5 |
| l3leaf | dc1-bgw1 | Ethernet2 | spine | dc1-spine2 | Ethernet5 |
| l3leaf | dc1-bgw2 | Ethernet1 | spine | dc1-spine1 | Ethernet6 |
| l3leaf | dc1-bgw2 | Ethernet2 | spine | dc1-spine2 | Ethernet6 |
| l3leaf | dc1-leaf1 | Ethernet1 | spine | dc1-spine1 | Ethernet1 |
| l3leaf | dc1-leaf1 | Ethernet2 | spine | dc1-spine2 | Ethernet1 |
| l3leaf | dc1-leaf2 | Ethernet1 | spine | dc1-spine1 | Ethernet2 |
| l3leaf | dc1-leaf2 | Ethernet2 | spine | dc1-spine2 | Ethernet2 |
| l3leaf | dc1-leaf3 | Ethernet1 | spine | dc1-spine1 | Ethernet3 |
| l3leaf | dc1-leaf3 | Ethernet2 | spine | dc1-spine2 | Ethernet3 |
| l3leaf | dc1-leaf4 | Ethernet1 | spine | dc1-spine1 | Ethernet4 |
| l3leaf | dc1-leaf4 | Ethernet2 | spine | dc1-spine2 | Ethernet4 |
| l3leaf | dc2-bgw1 | Ethernet1 | spine | dc2-spine1 | Ethernet5 |
| l3leaf | dc2-bgw1 | Ethernet2 | spine | dc2-spine2 | Ethernet5 |
| l3leaf | dc2-bgw2 | Ethernet1 | spine | dc2-spine1 | Ethernet6 |
| l3leaf | dc2-bgw2 | Ethernet2 | spine | dc2-spine2 | Ethernet6 |
| l3leaf | dc2-leaf1 | Ethernet1 | spine | dc2-spine1 | Ethernet1 |
| l3leaf | dc2-leaf1 | Ethernet2 | spine | dc2-spine2 | Ethernet1 |
| l3leaf | dc2-leaf2 | Ethernet1 | spine | dc2-spine1 | Ethernet2 |
| l3leaf | dc2-leaf2 | Ethernet2 | spine | dc2-spine2 | Ethernet2 |

## Fabric IP Allocation

### Fabric Point-To-Point Links

| Uplink IPv4 Pool | Available Addresses | Assigned addresses | Assigned Address % |
| ---------------- | ------------------- | ------------------ | ------------------ |
| 10.1.255.0/24 | 256 | 24 | 9.38 % |
| 10.2.255.0/24 | 256 | 16 | 6.25 % |

### Point-To-Point Links Node Allocation

| Node | Node Interface | Node IP Address | Peer Node | Peer Interface | Peer IP Address |
| ---- | -------------- | --------------- | --------- | -------------- | --------------- |
| dc1-bgw1 | Ethernet1 | 10.1.255.17/31 | dc1-spine1 | Ethernet5 | 10.1.255.16/31 |
| dc1-bgw1 | Ethernet2 | 10.1.255.19/31 | dc1-spine2 | Ethernet5 | 10.1.255.18/31 |
| dc1-bgw2 | Ethernet1 | 10.1.255.21/31 | dc1-spine1 | Ethernet6 | 10.1.255.20/31 |
| dc1-bgw2 | Ethernet2 | 10.1.255.23/31 | dc1-spine2 | Ethernet6 | 10.1.255.22/31 |
| dc1-leaf1 | Ethernet1 | 10.1.255.1/31 | dc1-spine1 | Ethernet1 | 10.1.255.0/31 |
| dc1-leaf1 | Ethernet2 | 10.1.255.3/31 | dc1-spine2 | Ethernet1 | 10.1.255.2/31 |
| dc1-leaf2 | Ethernet1 | 10.1.255.5/31 | dc1-spine1 | Ethernet2 | 10.1.255.4/31 |
| dc1-leaf2 | Ethernet2 | 10.1.255.7/31 | dc1-spine2 | Ethernet2 | 10.1.255.6/31 |
| dc1-leaf3 | Ethernet1 | 10.1.255.9/31 | dc1-spine1 | Ethernet3 | 10.1.255.8/31 |
| dc1-leaf3 | Ethernet2 | 10.1.255.11/31 | dc1-spine2 | Ethernet3 | 10.1.255.10/31 |
| dc1-leaf4 | Ethernet1 | 10.1.255.13/31 | dc1-spine1 | Ethernet4 | 10.1.255.12/31 |
| dc1-leaf4 | Ethernet2 | 10.1.255.15/31 | dc1-spine2 | Ethernet4 | 10.1.255.14/31 |
| dc2-bgw1 | Ethernet1 | 10.2.255.17/31 | dc2-spine1 | Ethernet5 | 10.2.255.16/31 |
| dc2-bgw1 | Ethernet2 | 10.2.255.19/31 | dc2-spine2 | Ethernet5 | 10.2.255.18/31 |
| dc2-bgw2 | Ethernet1 | 10.2.255.21/31 | dc2-spine1 | Ethernet6 | 10.2.255.20/31 |
| dc2-bgw2 | Ethernet2 | 10.2.255.23/31 | dc2-spine2 | Ethernet6 | 10.2.255.22/31 |
| dc2-leaf1 | Ethernet1 | 10.2.255.1/31 | dc2-spine1 | Ethernet1 | 10.2.255.0/31 |
| dc2-leaf1 | Ethernet2 | 10.2.255.3/31 | dc2-spine2 | Ethernet1 | 10.2.255.2/31 |
| dc2-leaf2 | Ethernet1 | 10.2.255.5/31 | dc2-spine1 | Ethernet2 | 10.2.255.4/31 |
| dc2-leaf2 | Ethernet2 | 10.2.255.7/31 | dc2-spine2 | Ethernet2 | 10.2.255.6/31 |

### Loopback Interfaces (BGP EVPN Peering)

| Loopback Pool | Available Addresses | Assigned addresses | Assigned Address % |
| ------------- | ------------------- | ------------------ | ------------------ |
| 10.1.0.0/24 | 256 | 8 | 3.13 % |
| 10.2.0.0/24 | 256 | 6 | 2.35 % |

### Loopback0 Interfaces Node Allocation

| POD | Node | Loopback0 |
| --- | ---- | --------- |
| DC1 | dc1-bgw1 | 10.1.0.15/32 |
| DC1 | dc1-bgw2 | 10.1.0.16/32 |
| DC1 | dc1-leaf1 | 10.1.0.11/32 |
| DC1 | dc1-leaf2 | 10.1.0.12/32 |
| DC1 | dc1-leaf3 | 10.1.0.13/32 |
| DC1 | dc1-leaf4 | 10.1.0.14/32 |
| DC1 | dc1-spine1 | 10.1.0.1/32 |
| DC1 | dc1-spine2 | 10.1.0.2/32 |
| DC2 | dc2-bgw1 | 10.2.0.15/32 |
| DC2 | dc2-bgw2 | 10.2.0.16/32 |
| DC2 | dc2-leaf1 | 10.2.0.11/32 |
| DC2 | dc2-leaf2 | 10.2.0.12/32 |
| DC2 | dc2-spine1 | 10.2.0.1/32 |
| DC2 | dc2-spine2 | 10.2.0.2/32 |

### VTEP Loopback VXLAN Tunnel Source Interfaces (VTEPs Only)

| VTEP Loopback Pool | Available Addresses | Assigned addresses | Assigned Address % |
| ------------------ | ------------------- | ------------------ | ------------------ |
| 10.1.1.0/24 | 256 | 6 | 2.35 % |
| 10.2.1.0/24 | 256 | 4 | 1.57 % |

### VTEP Loopback Node allocation

| POD | Node | Loopback1 |
| --- | ---- | --------- |
| DC1 | dc1-bgw1 | 10.1.1.15/32 |
| DC1 | dc1-bgw2 | 10.1.1.16/32 |
| DC1 | dc1-leaf1 | 10.1.1.11/32 |
| DC1 | dc1-leaf2 | 10.1.1.12/32 |
| DC1 | dc1-leaf3 | 10.1.1.13/32 |
| DC1 | dc1-leaf4 | 10.1.1.14/32 |
| DC2 | dc2-bgw1 | 10.2.1.15/32 |
| DC2 | dc2-bgw2 | 10.2.1.16/32 |
| DC2 | dc2-leaf1 | 10.2.1.11/32 |
| DC2 | dc2-leaf2 | 10.2.1.12/32 |
