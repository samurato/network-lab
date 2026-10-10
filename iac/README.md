# iac/

| Path | Edited by | What |
|---|---|---|
| `intent/inventory.yml` | humans / agent | Arista devices, groups (DC, role), mgmt IPs |
| `intent/group_vars/FABRIC.yml` | humans / agent | fabric-wide: eAPI/gNMI, mgmt, users, DCI WAN links (`l3_edge`) |
| `intent/group_vars/DC*_{SPINES,LEAFS,BGWS}.yml` | humans / agent | ASNs, pools, EVPN gateway peers, VLAN filter tags |
| `intent/group_vars/NETWORK_SERVICES.yml` | humans / agent | tenants, VRFs, SVIs/VLANs (tags select leaves) |
| `intent/hosts.yml`, `intent/wan.yml` | humans / agent | workload hosts, FRR WAN routers |
| `build/` | `make build` only | AVD structured configs, EOS configs, fabric docs, FRR configs, lab inventory |
| `ansible/` | engineers | playbooks: `build.yml` (AVD), `site.yml` (plan/apply) |
| `tools/render.py` | engineers | `pre`: hosts -> AVD connected endpoints; `post`: AVD output -> lab wiring, bootstrap, telemetry |

Apply semantics: EOS devices get a **full config replace** over eAPI (`arista.avd.eos_config_deploy_eapi`);
FRR uses `frr-reload.py`; hosts converge their single data-plane NIC. Anything not in intent is removed.
