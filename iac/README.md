# iac/

| Path | Edited by | What |
|---|---|---|
| `intent/inventory.yml` | humans / agent | switches by DC and role (`type`), mgmt IPs |
| `intent/group_vars/FABRIC/*.yml` | humans / agent | shared by both DCs: `routing`, `vlans-vrfs`, `cabling`, `management`, `ansible` |
| `intent/group_vars/DC1.yml`, `DC2.yml` | humans / agent | one DC each: AS, IP pools, spines, leaves, border gateways (EVPN gateway, WAN eBGP) |
| `intent/hosts.yml`, `intent/wan.yml` | humans / agent | workload hosts, FRR WAN routers |
| `build/` | `make build` only | AVD structured configs, EOS configs, fabric docs, FRR configs, lab inventory |
| `ansible/` | engineers | playbooks: `build.yml` (AVD), `site.yml` (plan/apply) |
| `tools/render.py` | engineers | `pre`: hosts -> AVD connected endpoints; `post`: AVD output -> lab wiring, bootstrap, telemetry |

Apply semantics: EOS devices get a **full config replace** over eAPI (`arista.avd.eos_config_deploy_eapi`);
FRR uses `frr-reload.py`; hosts converge their single data-plane NIC. Anything not in intent is removed.
