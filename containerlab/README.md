# containerlab/ — lab runtime

Nodes boot with a minimal **day-0 bootstrap** (`init-configs/`, generated: hostname, admin user, mgmt VRF,
eAPI, gNMI, multi-agent routing). Everything else is pushed by `iac/` on `make apply`.

```
lab               bring-up helper: up | down | redeploy | status | wait | cli <node> | graph | netem
netops.clab.yml   GENERATED from AVD output — nodes, mgmt IPs, cabling
init-configs/     GENERATED cEOS day-0 configs
static/frr/       FRR daemons + vtysh.conf (bind-mounted)
telemetry/gnmic/  gnmic.base.yml (hand-kept), GENERATED gnmic.yml + targets.yml, gnmic.env (secret)
telemetry/otelcol OTel Collector base + Elastic layer, elastic.env (secret)
verify.sh         health checks [--wait N]
bootstrap.sh      one-time host setup (packages, terraform, gnmic, Ansible venv + AVD requirements)
```

Pitfalls
- Never `docker restart` a lab node: its veth links are lost. Use `./lab redeploy`.
- Always destroy via `./lab down` (sets `CLAB_LABDIR_BASE`), never a bare `containerlab destroy`.
