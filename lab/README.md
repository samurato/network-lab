# lab/ — the containerlab lab

```
lab               start/stop helper: up | down | redeploy | status | wait | cli <node> | graph | netem
verify.sh         health checks (make verify); --wait N retries until healthy
bootstrap.sh      one-time host setup (packages, gnmic, Ansible venv + AVD)
static/           files mounted into nodes: cEOS interface mapping, FRR daemons/vtysh.conf
telemetry/gnmic/  gnmic.base.yml (subscriptions); gnmic.env (secret, created by make)
telemetry/otelcol OTel Collector base config + Elastic layer; elastic.env (secret)
```

The topology itself (`netops.clab.yml`), the day-0 switch configs and the final gnmic config
are generated from `network/` into `generated/lab/`.

Pitfalls
- Never `docker restart` a switch or router: its links are lost. Use `lab/lab redeploy`.
- Always destroy with `lab/lab down` (it sets `CLAB_LABDIR_BASE`), not a bare `containerlab destroy`.
