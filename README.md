# netops-lab

Dual-DC **Arista EVPN-VXLAN multi-site** lab with streaming telemetry, managed end-to-end by GitOps.
Built for the Auto-SRE hackathon: the agent reads telemetry in Elastic and fixes the network by opening a PR here.

```
                 wan1 (FRR, AS64901) ══ wan2 (FRR, AS64902)          DCI underlay: eBGP
                  ║ ║            ║ ║
      ┌───────── dc1-bgw1/2 ─────────┐          ┌───────── dc2-bgw1/2 ─────────┐
      │  EVPN Gateways (AS65105/06)  │◄═ EVPN ═►│  EVPN Gateways (AS65205/06)  │  re-originate RT2/RT5,
      │           │                  │  domain  │           │                  │  next-hop-self
      │   dc1-spine1/2 (AS65100)     │  remote  │   dc2-spine1/2 (AS65200)     │
      │   │      │      │      │     │          │      │          │            │
      │ leaf1  leaf2  leaf3  leaf4   │          │    leaf1      leaf2          │
      │  web   web+str  app    app   │          │     db       db+stretch      │
      └──────────────────────────────┘          └──────────────────────────────┘
        DC1 EVPN domain (VTEPs 10.1.1.x)          DC2 EVPN domain (VTEPs 10.2.1.x)
```
VRF `PROD` (L3VNI 1000) spans both DCs through the gateways; VLAN 150 is stretched at L2.
Leaves only ever see their own DC's VTEPs (`make verify` checks this).

## Layout
```
iac/intent/       SOURCE OF TRUTH — edit here (humans and the Auto-SRE agent)
  inventory.yml     Arista devices, roles, mgmt IPs           (AVD)
  group_vars/       fabric, DCs, spines/leaves/BGWs, tenants   (AVD data model)
  hosts.yml         workload hosts -> leaf access ports
  wan.yml           FRR WAN routers
iac/build/        GENERATED + committed: AVD intended configs & docs, FRR configs, lab inventory
iac/ansible/      engine: AVD build, EOS config-replace over eAPI, FRR/host roles
iac/tools/        render.py (lab compiler), plan-report.sh, change-event.sh
iac/terraform/    cloud side (AWS hybrid VPN, Elastic) — phase 4
containerlab/     lab runtime: GENERATED topology + day-0 bootstrap, telemetry stack, verify.sh
.github/          GitOps: plan on PR, deploy on merge, drift every 15 min, CODEOWNERS
```

## Workflow
```
edit iac/intent  ->  make build  ->  commit (intent + iac/build + containerlab)  ->  PR
PR:     make check-build (AVD schema + generated files in sync) -> make plan (per-device diff, PR comment)
merge:  make apply (config-replace) -> verify -> change event -> Elastic
cron:   make plan against main -> drift issue if the network diverged
```

| Command | |
|---|---|
| `make build` | intent -> AVD configs/docs -> lab wiring, telemetry, inventory (offline) |
| `make up` / `make redeploy` | bring lab up from intent (redeploy = wipe first), apply, verify |
| `make plan` / `make apply` | per-device diff / converge (declarative: removes anything not in intent) |
| `make verify` | BGP + EVPN sessions, multi-site VTEP isolation, data plane, telemetry |
| `make down` | destroy the lab |

Credentials: `EOS_USER` / `EOS_PASSWORD` env (CI secrets); lab default admin/admin.
Elastic: `containerlab/telemetry/otelcol/elastic.env` (git-ignored) — see `elastic.env.example`.
