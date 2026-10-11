# Architecture

This is the design of the whole lab, from the switch fabric up: the network, the Kubernetes cluster on top
of it, the traffic that runs through it, how telemetry leaves it, and how infrastructure-as-code and
GitOps keep all of it in sync with this repository.

| Section | What it covers |
|---|---|
| [1. The big picture](#1-the-big-picture) | every layer on one page |
| [2. Physical topology](#2-physical-topology) | nodes and cabling |
| [3. Routing design](#3-routing-design) | OSPF underlay, iBGP EVPN overlay, multi-site gateways, WAN |
| [4. Tenant VRF PROD and the WAN handoff](#4-tenant-vrf-prod-and-the-wan-handoff) | VLANs, VNIs, VRF-lite to the WAN, route policy |
| [5. Kubernetes on the fabric](#5-kubernetes-on-the-fabric) | k3s nodes, Cilium, BGP to the leaves, load balancers |
| [6. A request end to end](#6-a-request-end-to-end) | packet walk: Internet user → VIP → pod |
| [7. Traffic generators](#7-traffic-generators) | k6, attacker, iperf3 |
| [8. Telemetry](#8-telemetry) | gNMI → OpenTelemetry → Elastic |
| [9. Infrastructure as code](#9-infrastructure-as-code) | which tool owns what, the build pipeline |
| [10. GitOps](#10-gitops) | PR → plan → merge → deploy → verify |
| [11. Design decisions](#11-design-decisions) | why it is built this way |
| [12. Known gaps](#12-known-gaps) | what is not done yet |

Addresses and AS numbers are collected in [ip-plan.md](ip-plan.md).

---

## 1. The big picture

![The whole system on one page](images/architecture.svg)

The same flow, as tool → output:

```mermaid
flowchart TB
  subgraph SRC["Git: source of truth"]
    NET["network/<br/>switches, VLANs, VRFs,<br/>WAN, servers (YAML)"]
    K8SSRC["kubernetes/<br/>cluster.yml, node entrypoint,<br/>terraform/ (Cilium, BGP, apps)"]
  end

  subgraph BUILD["make build (offline)"]
    RENDER["automation/render.py"]
    AVD["Arista AVD<br/>(Ansible)"]
    OUT["generated/  +  containerlab/<br/>EOS configs, FRR configs,<br/>topology, docs"]
  end

  subgraph LAB["Running lab (containerlab)"]
    WAN["WAN: wan1, wan2 (FRR)<br/>Internet users, attacker"]
    DC1["DC1 fabric<br/>Arista cEOS, AS 65100"]
    DC2["DC2 fabric<br/>Arista cEOS, AS 65200"]
    K8S["k3s cluster<br/>6 nodes, Cilium, web app"]
    TEL["gnmic + OTel Collector"]
  end

  subgraph CLOUD["Elastic Cloud (AWS)"]
    ES["Elastic<br/>metrics, logs, change events"]
    AGENT["Auto-SRE agent"]
  end

  NET --> RENDER
  K8SSRC --> RENDER
  RENDER --> AVD --> OUT
  OUT -- "containerlab deploy / make apply" --> DC1 & DC2 & WAN
  OUT -- "containerlab deploy" --> K8S
  K8SSRC -- "Terraform: make k8s" --> K8S
  DC1 & DC2 -- "gNMI streaming" --> TEL
  K8S -. "OTLP (app)" .-> TEL
  TEL -- "OTLP" --> ES
  ES --> AGENT
  AGENT -- "pull request with the fix" --> SRC
```

Four layers, each owned by one tool:

| Layer | What | Owned by |
|---|---|---|
| Network | 14 Arista cEOS switches in two EVPN-VXLAN data centres, 2 FRR WAN routers | `network/` → AVD + `render.py` → containerlab, `make apply` |
| Compute | k3s Kubernetes cluster, nodes plugged into leaves like servers | `kubernetes/cluster.yml` → `render.py` → containerlab |
| Platform and apps | Cilium (pod network, BGP, load balancers), the web app, test servers | `kubernetes/terraform/` → Terraform |
| Observability | gNMI from every switch to an OTel Collector, exported to Elastic | `automation/telemetry/`, `containerlab/telemetry/` |

---

## 2. Physical topology

Every box is a container on one Linux host. Links are veth pairs created by containerlab; the switch
side of each link is a real EOS `EthernetN` interface.

```mermaid
flowchart TB
  subgraph INET["WAN-side sites"]
    K6["inet-k6<br/>198.51.100.11<br/>k6 load"]
    ATK["attacker1<br/>203.0.113.66<br/>nping / iperf3"]
    CP3["wan-k8s-cp3<br/>k3s control plane<br/>tie-breaker"]
  end

  subgraph WANR["WAN / DCI transport (FRR)"]
    WAN1["wan1<br/>AS 64901"]
    WAN2["wan2<br/>AS 64902"]
  end

  subgraph DC1["DC1: AS 65100"]
    D1B1["dc1-bgw1"]
    D1B2["dc1-bgw2"]
    D1S1["dc1-spine1"]
    D1S2["dc1-spine2"]
    D1L1["dc1-leaf1"]
    D1L2["dc1-leaf2"]
    D1L3["dc1-leaf3"]
    D1L4["dc1-leaf4"]
    D1H["dc1-web1 / dc1-web2<br/>dc1-app1 / dc1-app2<br/>dc1-stretch1"]
    D1K["dc1-k8s-cp1 (leaf1)<br/>dc1-k8s-wk1 (leaf3)<br/>dc1-k8s-wk2 (leaf4)"]
  end

  subgraph DC2["DC2: AS 65200"]
    D2B1["dc2-bgw1"]
    D2B2["dc2-bgw2"]
    D2S1["dc2-spine1"]
    D2S2["dc2-spine2"]
    D2L1["dc2-leaf1"]
    D2L2["dc2-leaf2"]
    D2H["dc2-db1 / dc2-db2<br/>dc2-stretch1"]
    D2K["dc2-k8s-cp2 (leaf1)<br/>dc2-k8s-wk3 (leaf2)"]
  end

  K6 --- WAN2
  ATK --- WAN1
  CP3 --- WAN1
  WAN1 === WAN2
  WAN1 --- D1B1 & D1B2 & D2B1 & D2B2
  WAN2 --- D1B1 & D1B2 & D2B1 & D2B2
  D1B1 & D1B2 --- D1S1 & D1S2
  D1S1 & D1S2 --- D1L1 & D1L2 & D1L3 & D1L4
  D1L1 & D1L2 & D1L3 & D1L4 --- D1H
  D1L1 & D1L3 & D1L4 --- D1K
  D2B1 & D2B2 --- D2S1 & D2S2
  D2S1 & D2S2 --- D2L1 & D2L2
  D2L1 & D2L2 --- D2H
  D2L1 & D2L2 --- D2K
```

| Port convention | |
|---|---|
| Leaf / BGW `Ethernet1-2` | uplinks to spine1, spine2 |
| Spine `Ethernet1-8` | downlinks to leaves and BGWs |
| BGW `Ethernet3` / `Ethernet4` | to wan1 / wan2 (underlay); `Ethernet3.100` / `Ethernet4.100` = VRF PROD |
| Leaf `Ethernet5-6` | servers (VLAN access ports) |
| Leaf `Ethernet7` | Kubernetes node (routed /31 in VRF PROD) |
| WAN `eth1-4` | to the four BGWs; `eth5` wan1↔wan2; `eth6` tie-breaker (wan1); `eth7` edge site |
| Every node `eth0` / `Management1` | management network 172.20.20.0/24 (not part of the data plane) |

The live view of this diagram: open `containerlab/netops.clab.yml` in VS Code with the Containerlab
extension (TopoViewer), or run `make graph`.

---

## 3. Routing design

```mermaid
flowchart LR
  subgraph DC1["DC1 (AS 65100)"]
    direction TB
    L1["leaves<br/>VTEP 10.1.1.x"] -- "OSPF area 0<br/>+ iBGP EVPN" --> S1["spines<br/>route reflectors"]
    S1 -- "iBGP EVPN" --> G1["border gateways<br/>EVPN gateway"]
  end
  subgraph DC2["DC2 (AS 65200)"]
    direction TB
    G2["border gateways<br/>EVPN gateway"] -- "iBGP EVPN" --> S2["spines<br/>route reflectors"]
    S2 -- "OSPF area 0<br/>+ iBGP EVPN" --> L2["leaves<br/>VTEP 10.2.1.x"]
  end
  G1 -- "eBGP IPv4: BGW loopbacks only" --> W["wan1 / wan2"]
  W -- "eBGP IPv4" --> G2
  G1 <-. "eBGP EVPN multihop<br/>domain remote, I-ES" .-> G2
```

| Layer | Protocol | Details |
|---|---|---|
| Underlay inside a DC | OSPF process 100, area 0 | point-to-point /31 links + Loopback0 (router ID) + Loopback1 (VTEP) |
| Overlay inside a DC | iBGP EVPN, one AS per DC | spines are route reflectors for leaves and BGWs |
| BGW ↔ WAN | eBGP IPv4 | carries only the BGW loopbacks, so the two DCs' gateways can reach each other |
| BGW ↔ remote BGW | eBGP EVPN multihop | EVPN Gateway ("multi-site"): routes are re-originated with next-hop-self |
| Stretched L2 safety | RFC 9014 Interconnect ES | both gateways of a DC share one I-ESI; DF election lets one forward BUM per VLAN |

The result: **every leaf only ever sees VTEPs of its own DC**. DC2's routes arrive at a DC1 leaf with a DC1
gateway as next hop. `make verify` checks this ("Multi-site isolation").

Where it is configured: `network/group_vars/FABRIC/routing.yml` (protocols), `network/group_vars/DC1.yml` /
`DC2.yml` (AS, pools, gateways), `network/group_vars/FABRIC/cabling.yml` (BGW ↔ WAN links),
`network/wan.yml` (WAN routers).

---

## 4. Tenant VRF PROD and the WAN handoff

One tenant VRF, `PROD` (L3 VNI 1000), spans both DCs. VLANs are L2 VNIs `10000 + VLAN`.

| VLAN | Name | Subnet / anycast gateway | Where |
|---|---|---|---|
| 110 | WEB | 10.10.10.1/24 | DC1 leaf1, leaf2 |
| 120 | APP | 10.10.20.1/24 | DC1 leaf3, leaf4 |
| 130 | DB | 10.20.30.1/24 | DC2 leaf1, leaf2 (reserved for the database) |
| 150 | STRETCH | 10.15.0.1/24 | DC1 leaf2 + DC2 leaf2, stretched across DCs |

Besides VLANs, VRF PROD has **routed attachments** generated from other source files:

- **Kubernetes nodes:** each one is a routed `/31` on a leaf's `Ethernet7`, with an eBGP session in VRF PROD
  (from `kubernetes/cluster.yml`).
- **The WAN handoff (VRF-lite):** every BGW ↔ WAN link carries an 802.1Q sub-interface `.100` in VRF PROD
  with an eBGP session. The WAN routers have a matching Linux VRF `PROD`. This is how WAN-side sites (the
  Kubernetes tie-breaker, Internet users, the attacker) reach the DCs.

Because DC2 prefixes are now reachable two ways from DC1 (EVPN through the gateways, or VRF-lite through
the WAN), route policy on the BGWs decides:

```mermaid
flowchart LR
  subgraph BGW["DC1 border gateway, VRF PROD"]
    OUT["RM-WAN-PROD-OUT<br/>permit: own DC subnets 10.10/16,<br/>own pods 10.11/16, public VIPs 192.0.2/24<br/>AND as-path ^$ or ^65101$<br/>deny: DB range 10.10.30/24"]
    IN["RM-WAN-PROD-IN<br/>permit only WAN sites:<br/>10.30/16, 10.31/16,<br/>198.51.100/24, 203.0.113/24"]
  end
  BGW -- "advertise" --> OUT --> WAN["wan1 / wan2 VRF PROD"]
  WAN -- "receive" --> IN --> BGW
```

- A DC only hands the WAN **its own** prefixes (the AS-path check stops DC1 re-advertising DC2's routes).
  DC1 ↔ DC2 traffic therefore always stays on EVPN.
- **Internal VIPs (10.99.0.0/24) and the database range never leave the DCs.** Only public VIPs do.
- Leaves accept from a Kubernetes node only its pod /24 and /32 VIPs (`RM-K8S-IN`) and send it nothing
  (`RM-K8S-OUT`; nodes use a static route to the leaf).

The route-maps are readable YAML in `network/group_vars/DC1.yml` / `DC2.yml` (`structured_config`), so a
bad policy change is a reviewable diff, and so is the fix.

---

## 5. Kubernetes on the fabric

```mermaid
flowchart TB
  subgraph CP["Control plane: 3 k3s servers, embedded etcd"]
    CP1["dc1-k8s-cp1<br/>10.10.40.1"]
    CP2["dc2-k8s-cp2<br/>10.20.40.1"]
    CP3["wan-k8s-cp3<br/>10.30.40.1<br/>tie-breaker, no workloads"]
  end
  subgraph W["Workers (cp1 and cp2 run workloads too)"]
    WK1["dc1-k8s-wk1<br/>10.10.40.3"]
    WK2["dc1-k8s-wk2<br/>10.10.40.5"]
    WK3["dc2-k8s-wk3<br/>10.20.40.3"]
  end
  CP1 <-. "etcd raft" .-> CP2
  CP2 <-. "etcd raft" .-> CP3
  CP3 <-. "etcd raft" .-> CP1
  CP1 -- "eBGP 65101 ↔ 65100" --> L11["dc1-leaf1"]
  WK1 -- "eBGP 65101 ↔ 65100" --> L13["dc1-leaf3"]
  WK2 -- "eBGP 65101 ↔ 65100" --> L14["dc1-leaf4"]
  CP2 -- "eBGP 65201 ↔ 65200" --> L21["dc2-leaf1"]
  WK3 -- "eBGP 65201 ↔ 65200" --> L22["dc2-leaf2"]
  CP3 -- "eBGP 65301 ↔ 64901" --> W1["wan1"]
```

| Piece | Design |
|---|---|
| Distribution | k3s v1.36 (single binary), each node a containerlab node |
| Node networking | `eth1` = routed /31 to its switch; the node IP is pinned to it (`--node-ip`), so all node-to-node and pod traffic crosses the fabric. `eth0` (management) is only for image pulls and telemetry |
| Control plane | 3 servers: one per DC plus a tie-breaker on the WAN. Losing a whole DC still leaves 2 of 3 etcd members |
| Pod network | Cilium, **native routing** (no overlay inside the fabric's VXLAN). Each node owns a fixed pod /24 and announces it to its switch over eBGP |
| Pod CIDRs | per node, from `cluster.yml`: DC1 `10.11.x.0/24`, DC2 `10.21.x.0/24`, WAN `10.31.0.0/24`. Set by Terraform; k3s's own allocation is off |
| Services | ClusterIP range 10.43.0.0/16 (cluster-internal, not routed); kube-proxy forwards |
| Load balancers | Cilium LB IPAM hands out VIPs from two pools; Cilium BGP announces each VIP as a /32 **only from nodes with a ready endpoint** (`externalTrafficPolicy: Local`) |
| VIP pools | `internal` 10.99.0.0/24 (inside the DCs only), `public` 192.0.2.0/24 (also to the WAN; only for services labelled `netops.lab/exposure=public`) |

Failover is plain BGP: if every web pod in DC1 dies, DC1's nodes withdraw the VIP, the DC1 leaves and
gateways lose the route, and the WAN only sees DC2's path.

What runs in the cluster today (namespace `prod`):

| Workload | Exposure |
|---|---|
| `web`: the colleague's app `chaos2cure/web:1`, 4 replicas spread 2 + 2 over the DCs | `web-public` 192.0.2.10:80, `web-internal` 10.99.0.10:80 |
| `iperf3-dc1`, `iperf3-dc2`: one iperf3 server per DC | ClusterIP `iperf3-dc1.prod`, `iperf3-dc2.prod` port 5201 |
| `db`: reserved Service, no backend yet | `db.prod` 5432, future backend VIP 10.20.30.10 |

---

## 6. A request end to end

```mermaid
sequenceDiagram
  autonumber
  participant U as inet-k6<br/>198.51.100.11
  participant W2 as wan2<br/>VRF PROD
  participant G as dc1-bgw1<br/>Ethernet4.100
  participant L as dc1-leaf4<br/>VRF PROD
  participant N as dc1-k8s-wk2<br/>10.10.40.5
  participant P as web pod<br/>10.11.2.x
  U->>W2: GET http://192.0.2.10/
  Note over W2: 192.0.2.10/32 learned from 4 BGWs,<br/>ECMP (AS path 65100 65101 / 65200 65201)
  W2->>G: VRF-lite, 802.1Q 100
  Note over G: EVPN type-5 route to 192.0.2.10/32<br/>from the leaves whose node announces it
  G->>L: VXLAN, L3 VNI 1000
  L->>N: Ethernet7, routed /31 (eBGP from the node)
  N->>P: kube-proxy DNAT to the local pod
  P-->>N: response
  N-->>L: source 192.0.2.10, destination 198.51.100.11
  L-->>G: VXLAN, L3 VNI 1000
  G-->>W2: VRF-lite
  W2-->>U: 200 OK
```

Every hop on this path has a unique, routed IP address, and every switch on it streams interface
counters and BGP state, so a problem at any hop is visible in the telemetry.

---

## 7. Traffic generators

| Generator | Where | Default behaviour | Configured in |
|---|---|---|---|
| k6 | `inet-k6` behind wan2, 198.51.100.11 | always on: 5 iterations/s to `http://192.0.2.10`, each `GET /` + `GET /api/products` (10 req/s) | `network/wan.yml` (`TARGET`, `RPS`), `containerlab/static/generators/baseline.js` |
| nping, iperf3, curl, mtr | `attacker1` behind wan1, 203.0.113.66 | idle; run on demand. Uplink capped at 20 Mbit/s by `tc`; no Internet egress | `network/wan.yml` (`rate_limit`) |
| iperf3 servers | pods `iperf3-dc1`, `iperf3-dc2` | listening; drive DC1 ↔ DC2 load across the DCI | `kubernetes/terraform/apps.tf` |
| fault injection | any link | `automation/lab netem …` (containerlab netem: delay, loss, jitter, rate) | — |

Examples are in the [DevOps guide](devops-guide.md#traffic-and-faults).

---

## 8. Telemetry

The full reference (data model, operating, gaps, roadmap) is the [streaming telemetry guide](telemetry.md).

```mermaid
flowchart LR
  SW["14 cEOS switches<br/>gNMI :6030"] -- "subscribe" --> GN["gnmic<br/>172.20.20.251"]
  GN -- "OTLP gRPC :4317" --> OC["OTel Collector<br/>172.20.20.250"]
  APP["web pods"] -. "OTLP HTTP :4318<br/>(traces: see known gaps)" .-> OC
  OC -- "profile elastic:<br/>OTLP HTTP + disk queue" --> ES["Elastic Cloud<br/>managed OTLP"]
  OC -- "always" --> PR["localhost:9464/metrics<br/>(local sanity check)"]
  CI["deploy workflow"] -- "change event" --> ESC["logs-netops.changes"]
  ESC --- ES
```

| Subscription | Paths | Mode |
|---|---|---|
| `if-counters` | `/interfaces/interface/state/counters` | sample 10 s |
| `if-state` | `/interfaces/interface/state/oper-status` (UP = 1) | on change |
| `bgp-state` | BGP neighbor `session-state` (IDLE 1 … ESTABLISHED 6) | on change |
| `bgp-prefixes` | BGP neighbor AFI/SAFI prefix counts | sample 30 s |
| `platform` | CPU utilisation, memory | sample 30 s |
| `lldp` | neighbor system name and port | on change |

- **Metric names** are prefixed `gnmi_`. Every series has the resource attributes `source` / `device`,
  `site`, `role`, `vendor`, `lab=netops`.
- Interface series for unused ports are dropped at gnmic, using a per-device filter generated by `make build`.
- **Export to Elastic** happens when `automation/elastic.env` (git-ignored) holds `ELASTIC_OTLP_ENDPOINT`
  and `ELASTIC_API_KEY`. `make up` / `make redeploy` then start the collector with the `elastic` profile.
- **Change events:** every deploy records one (commit, author, changed devices, outcome) to
  `~/netops-changes.jsonl` and, when configured, to Elastic `logs-netops.changes`. The agent can then line
  up "what changed" with "when symptoms started".

---

## 9. Infrastructure as code

```mermaid
flowchart TB
  subgraph EDIT["You edit"]
    A1["network/inventory.yml<br/>network/group_vars/**"]
    A2["network/hosts.yml"]
    A3["network/wan.yml"]
    A4["kubernetes/cluster.yml"]
    A5["kubernetes/terraform/*.tf"]
  end
  subgraph PRE["render.py pre"]
    P1["generated/connected_endpoints.yml"]
    P2["generated/network_services.yml<br/>tenants + k8s/WAN VRF attachments"]
  end
  subgraph AVDB["AVD (ansible-playbook build.yml)"]
    B1["generated/intended/configs/*.cfg"]
    B2["generated/documentation/"]
  end
  subgraph POST["render.py post"]
    C1["containerlab/netops.clab.yml"]
    C2["containerlab/configs/*.cfg, *.conf, *.netdev.sh"]
    C3["containerlab/telemetry/gnmic/"]
    C4["generated/kubernetes.yml"]
    C5["generated/lab-inventory.yml"]
  end
  A2 --> P1
  A1 & A3 & A4 --> P2
  A1 & P1 & P2 --> AVDB
  B1 --> POST
  A3 & A4 --> POST
  C1 & C2 -- "containerlab deploy" --> LAB["running lab"]
  B1 -- "make apply (eAPI config replace)" --> LAB
  C2 & C5 -- "make apply (frr-reload)" --> LAB
  C4 & A5 -- "make k8s (Terraform)" --> LAB
```

| Tool | Owns | Why this tool |
|---|---|---|
| **Arista AVD** | EOS configs for all 14 switches, fabric docs | vendor-maintained EVPN design engine with schema validation |
| **render.py** | glue: AVD inputs from `hosts.yml` / `cluster.yml` / `wan.yml`, FRR configs, the containerlab topology, gnmic targets, Terraform input | one place that derives every cross-tool fact (a node's /31 appears on the leaf, in the topology and in Terraform from one line) |
| **containerlab** | containers and veth cabling | the only tool that can wire links into cEOS; Terraform has no provider for it |
| **Ansible** | `make plan` / `make apply` to running devices | eAPI config-replace for EOS, `frr-reload` for FRR, idempotent host addressing |
| **Terraform** | everything inside Kubernetes: pod CIDRs, Cilium (Helm), BGP and LB pools (CRDs), apps, image loading | declarative state, plan/apply, providers for Kubernetes and Helm |

Build rules:
- `generated/` and `containerlab/` are **committed outputs**. CI fails a PR if they differ from a fresh `make build`.
- `make build` is offline and touches no device.
- Terraform state lives with the running lab (`~/clab-runs/clab-netops/terraform-kubernetes.tfstate`), so
  it is discarded with `make down` and a fresh lab gets a fresh state.

---

## 10. GitOps

```mermaid
sequenceDiagram
  autonumber
  actor Dev as Engineer or Auto-SRE agent
  participant GH as GitHub
  participant R as Self-hosted runner<br/>(lab host)
  participant Lab as Running lab
  participant E as Elastic
  Dev->>GH: pull request (edit network/ or kubernetes/)
  GH->>R: workflow "plan"
  R->>R: make check-build (AVD schema + generated files committed)
  R->>Lab: make plan (per-device diff, read-only)
  R->>GH: plan posted as PR comment
  Dev->>GH: review + approve (CODEOWNERS), merge
  GH->>R: workflow "deploy"
  R->>Lab: redeploy if the topology changed
  R->>Lab: make apply (EOS config replace, FRR reload, hosts)
  R->>Lab: automation/k8s apply (Terraform)
  R->>Lab: automation/verify.sh
  R->>E: change event (commit, devices, outcome)
  loop every 15 minutes
    GH->>R: workflow "drift"
    R->>Lab: make plan against main
    R->>GH: open or update a "drift" issue if anything differs
  end
```

Workflows live in `.github/workflows/` (`plan.yml`, `deploy.yml`, `drift.yml`) and run on a self-hosted
runner labelled `netops-lab` on the lab host. Secrets: `EOS_USER`, `EOS_PASSWORD` (set);
`ELASTIC_ES_URL`, `ELASTIC_API_KEY` (optional, not set yet, so change events stay in `~/netops-changes.jsonl`).

---

## 11. Design decisions

| Decision | Alternatives | Why |
|---|---|---|
| All-Arista fabric with AVD | multi-vendor (SR Linux + cEOS) | one well-supported EVPN design engine; configs are generated, not hand-written |
| OSPF underlay + iBGP EVPN, one AS per DC | eBGP underlay | simpler per-DC AS story for humans and the agent; route reflectors on spines |
| EVPN Gateway (multi-site) with I-ES | flat EVPN across the WAN | leaves see only local VTEPs; failure domains stay per DC; stretched L2 is loop-safe |
| VRF-lite handoff to the WAN | extend EVPN to the WAN routers | FRR WAN stays simple; route policy is explicit and testable at one place (BGWs) |
| k3s in containerlab | kind, k3d, VMs | lightest real Kubernetes; nodes cable into leaves exactly like servers |
| Cilium native routing + BGP | flannel VXLAN + MetalLB | no VXLAN-in-VXLAN; pod IPs are real fabric routes, so flows and probes see pods |
| 3 control-plane nodes incl. a WAN tie-breaker | 2 + 1 in the DCs | either DC can fail without losing etcd quorum |
| `externalTrafficPolicy: Local` | Cluster | the VIP follows healthy pods; DC failover is visible in BGP |
| Terraform for in-cluster objects | Helm CLI / kubectl apply / k3s auto-deploy | user requirement: Terraform wherever possible; plan/apply and state |
| Single gnmic, no clustering | gnmic cluster + Consul | one host, so clustering added churn without adding resilience |
| linux nodes `restart-policy: "no"` | containerlab 0.80 default `always` | a Docker restart creates a new network namespace and silently drops the node's links |

---

## 12. Known gaps

| Gap | Impact | Next step |
|---|---|---|
| Elastic endpoint and API key not configured yet | telemetry stays in the lab (`localhost:9464/metrics`); a CI redeploy also comes back without Elastic | `automation/elastic.env` + repository secrets: [observability roadmap](observability-roadmap.md) steps 0–2 |
| OTel Collector has a metrics pipeline only | the web app's trace export fails with HTTP 404 (seen in the pod logs) | add `traces` and `logs` pipelines: [roadmap](observability-roadmap.md) step 1 |
| No routing-table telemetry | OpenConfig AFT and BGP RIB paths return empty (only `provider eos-native` is enabled) | enable `provider aft`: [roadmap](observability-roadmap.md) steps 5–6 |
| No Kubernetes, Cilium or Hubble telemetry | node, pod and Cilium health not visible | [roadmap](observability-roadmap.md) steps 11–12 |
| No flow data (cEOS sends no sFlow samples) | no per-flow reachability analysis yet | host-side sampling (pmacctd / hsflowd) → Elastic: [roadmap](observability-roadmap.md) step 10 |
| No synthetic ping-mesh | reachability only via `make verify` | `icmp_check` probes → OTLP (designed, not built) |
| WAN routers hash ECMP on L3 only | one client (k6) always lands in the same DC | `net.ipv4.fib_multipath_hash_policy=1` on wan1/wan2 |
| Occasional VIP request timeouts were seen once | not reproduced on re-test (40/40 OK) | watch `make verify`; investigate if it recurs |
| Repo is public and the runner is self-hosted | a fork PR could run code on the lab host | mitigated: workflows from fork PRs need approval; keep it that way (or make the repo private) |
