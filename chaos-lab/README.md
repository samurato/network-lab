# chaos-lab

Chaos engineering for the [netops lab](../README.md): the switch fabric, the WAN, Kubernetes and the web app. It breaks things on purpose so that an LLM agent, reading only Elastic, can be tested on diagnosing the fault and proposing the fix.

chaos-lab lives in this repo but is **separate infrastructure**:
- it is self-contained in this folder, with its own Makefile, venv (`~/.venvs/chaos`) and state (`~/clab-runs/chaos`); nothing outside the folder uses it, and the top-level Makefile doesn't call it;
- it installs nothing in the lab or the cluster;
- it reaches the lab from outside, the way an operator would: eAPI on the switches' management addresses, `docker exec vtysh` on the WAN routers, `containerlab tools netem` on fabric links, and kubectl.

| | |
|---|---|
| Framework | [Chaos Toolkit](https://chaostoolkit.org): each experiment is a YAML file with a steady-state hypothesis, a method (inject, hold) and rollbacks, and every run writes a JSON journal |
| Drivers | `chaoslab/`: small Python modules the experiments call |
| Health checks | Measured directly on the lab: HTTP from an Internet user, BGP state on every router, web replicas ready. They **never** read Elastic or telemetry. |
| Ground truth | `~/clab-runs/chaos/runs.jsonl` on the host, also appended to Elastic's `logs-chaos.*` data streams for the Chaos command center, using the lab key. It is the answer key for scoring an agent: the lab key can write `logs-chaos.*` but not read it, and it sits in its own Kibana space. |
| Scorecard | After each run, chaos-lab checks Elastic (read-only ES\|QL) for every signal the experiment should produce, and records whether it arrived and how fast. A missing signal is an observability gap. |

**Why not Chaos Monkey:**
- It only terminates instances, and it needs Spinnaker.
- Killing a containerlab node drops its links, so the lab doesn't recover cleanly.
- Its idea, a random fault from a safe set, is `make random` here.

**Why not Chaos Mesh or Litmus:** they install operators and privileged DaemonSets into the cluster, and this lab keeps chaos outside it.

## Quick start (on the lab host)

```sh
cd ~/hackathon/netops-lab/chaos-lab      # every chaos command runs from this folder
make venv                       # once
make test                       # guard self-test, changes nothing
make list                       # the catalogue
make dry EXP=net-01             # guard + health checks only, nothing injected
make run EXP=net-01             # inject, hold 5 min, roll back, check recovery
CHAOSLAB_HOLD=600 make run EXP=hij-01    # a longer fault window
make random                     # Chaos Monkey mode: one random experiment marked "random"
make status                     # current run, active faults, recent runs
make stop                       # kill switch: undo every active fault now
```

`EOS_USER` / `EOS_PASSWORD` set the switch credentials. The lab default is admin / admin.

## Background traffic

Out of the box the lab carries only k6's 5 req/s to the public VIP, so most faults have little to disrupt. `traffic.yml` defines bounded profiles, about 120 Mbit/s in total, started inside existing containers. Nothing is installed.

| Profile | Flows | Path | Makes visible |
|---|---|---|---|
| `web` | A second k6 in inet-k6, 20 iterations/s (40 req/s) | WAN → BGWs → fabric → web pods | hij-01/03, net-03, net-05, k8s-* |
| `east-west` | iperf3 dc1-app1 → dc2-db1, dc1-app2 → dc2-db2, 20 Mbit/s each way | Routed in VRF PROD across the DCI | net-01, net-06, net-09, hij-02 |
| `same-vlan` | iperf3 dc1-web1 ↔ dc1-web2, 10 Mbit/s | VLAN 110 over VXLAN, leaf1 ↔ leaf2 | net-07, net-01 |
| `stretched` | iperf3 dc1-stretch1 ↔ dc2-stretch1, 10 Mbit/s | VLAN 150, layer 2 across the DCI | net-04 (MTU) |

```sh
make traffic-dry                         # what would start
make traffic-start                       # all profiles (or PROFILE="web east-west")
make traffic-status                      # running generators + host-to-host ping matrix (loss / ms)
make traffic-stop
```

Each generator restarts itself after a fault breaks its connection. All of them carry the marker `chaoslab-traffic`, and `traffic-stop` kills only those processes. Traffic isn't a fault: `make stop` leaves it running and it doesn't count towards a blast radius. iperf3 uses port 5299, so the iperf3 pods and net-08 keep 5201.

The traffic shows up in Elastic as interface counters (every 10 s) and web traces. The ping matrix is for you; the hosts don't send telemetry.

A typical session: `make traffic-start`, then `CHAOSLAB_HOLD=180 make run EXP=net-01`, then `make traffic-status` during the hold, then `make traffic-stop`.

## Dashboards in Elastic

| Dashboard | Space | Shows |
|---|---|---|
| **Chaos · Command center** | Chaos lab (`/s/chaos/app/dashboards#/view/chaos-command-center`) | The fault in progress, every run with its outcome and recovery, the scorecard, coverage per experiment, observability gaps, time to detect, and the chaos timeline |
| **NetOps · Fault impact** | NetOps | Any fault's symptoms across ports, BGP, routes, EVPN, traffic, web requests, latency and errors, and deploys, on one time axis |
| **NetOps · Link failures** | NetOps | Each failed link with both ends (LLDP), when, how long, flaps, errors, routes withdrawn, and traffic moving to the surviving links |

The NetOps dashboards show only telemetry, which is what an agent sees. The command center lives in its own space because it holds the answers. To investigate a run, read its time window from the command center, then open Fault impact with that time range.

The dashboards are Terraform in `elastic/terraform/` (`dashboards-chaos.tf`, `dashboards-faults.tf`, `chaos.tf`), applied with `make elastic` at the repo root.

**Publishing** uses the lab key, `ELASTIC_ES_URL` and `ELASTIC_API_KEY` from the git-ignored `automation/elastic.env`, so there's nothing to set up. Every run publishes as it goes. `make publish` sends the catalogue and any earlier runs.

The lab key can write `logs-chaos.*` but not read it, so an agent with that key can't see the answers. Keep it that way: don't widen the lab key's read privileges to `logs-*` (`elastic/terraform/security.tf`).

| Command | Does |
|---|---|
| `make score [RUN=<run_id>]` | Recompute a run's scorecard (default: the last run) |
| `make publish` | Send the catalogue and every recorded run to Elastic again (safe to repeat) |

## Catalogue

### Network: the top 10 killers

| ID | Random | Fault | How |
|---|---|---|---|
| net-01 | yes | Leaf uplink down | eAPI: `shutdown` dc1-leaf1 Ethernet1 |
| net-02 | yes | BGP session flapping (EVPN overlay) | eAPI: neighbour shut / unshut, 4 cycles |
| net-03 | yes | Bad route policy: public VIPs not accepted from Kubernetes in DC1 | eAPI: `no seq 30` in PL-K8S-IN on dc1-leaf1/3/4 |
| net-04 | | MTU mismatch on a DCI link | eAPI: `mtu 1400` on dc1-bgw1 Ethernet3 |
| net-05 | yes | Gray failure: 5% loss, 50 ± 20 ms | netem on dc1-leaf3 eth1 |
| net-06 | yes | OSPF adjacency lost (authentication mismatch) | eAPI on dc1-leaf3 Ethernet1 |
| net-07 | | VXLAN VNI mismatch | eAPI: VLAN 110 → VNI 19110 on dc1-leaf2 |
| net-08 | yes | DCI congestion | iperf3 DC1 → DC2 pods, 4 × 100 Mbit/s |
| net-09 | | Spine isolated, interfaces still up | netem 100% loss on all of dc1-spine2's fabric links |
| net-10 | | DNS outage (the network is fine) | CoreDNS scaled to 0 |

### WAN route hijacks

| ID | Fault | Why it works |
|---|---|---|
| hij-01 | wan1 originates the public VIP 192.0.2.10/32 and attacker1 serves a fake page | The WAN has no origin validation, and a one-hop path beats the BGWs' two-hop path. Users get HTTP 200 from the wrong server. |
| hij-02 | wan1 originates dc2-bgw1's loopback 10.2.0.15/32 into Null0 | The BGWs' WAN-PEERS underlay has no inbound filter, so DC1's multi-site EVPN to dc2-bgw1 is black-holed |
| hij-03 | wan1 announces an Internet user's /32 with a forged origin (AS 64902 prepended) | PL-WAN-PROD-IN accepts `198.51.100.0/24 le 32`, so replies go to attacker1: requests arrive, responses vanish |

### Kubernetes and the app

| ID | Random | Fault | How |
|---|---|---|---|
| k8s-01 | yes | Web pod killed | kubectl delete one pod |
| k8s-02 | | Web capacity lost in DC1 | Cordon the DC1 nodes and delete the DC1 web pods (replacements stay Pending) |
| k8s-03 | yes | Node cut off from the fabric | netem 100% loss on dc1-k8s-wk2 eth1 (management untouched) |
| k8s-04 | yes | Cilium agent restart: the node's BGP session to its leaf resets | Delete the Cilium pod on dc1-k8s-wk1 |
| k8s-05 | | Noisy neighbour | A throwaway CPU and memory stress pod on dc1-k8s-wk1 |

Each experiment's `extensions.expected` lists the symptoms the telemetry should show, which is the basis for scoring an agent.

## Safety rules (enforced in `chaoslab/guard.py`)

- **Telemetry is off limits:**
  - refused nodes: gnmic, otelcol, kafka;
  - refused interfaces: management ones (`eth0`, `Management*`);
  - refused addresses: anything in 172.20.20.0/24;
  - refused switch config: `management`, `username`, `aaa`, `daemon`, `logging`, `MGMT`;
  - refused namespaces: those matching otel, elastic, observability or monitoring.
  
  Faults touch only fabric data-plane links and routing config, so streaming carries on throughout. `make test` proves the refusals.
- **No container lifecycle actions** on lab nodes: no `docker restart`, kill or stop. They drop containerlab links.
- **One run at a time.** A new run is refused while any fault is still active.
- **Blast radius.** Each experiment declares how many faults it may make, and anything beyond that is refused.
- **Lab lock.** A run is refused while a netops deploy holds `~/clab-runs/.netops.lock`. The lock is taken for inject and rollback only, not during the hold, so drift detection still sees the fault.
- **Undo first.** Every fault registers its undo *before* it is made:
  - switches: a config snapshot to flash, restored with `configure replace`;
  - WAN routers: exact undo lines;
  - netem: reset;
  - Kubernetes: uncordon, scale back, or delete the `chaos` namespace.
- **Rollback always runs** (`--rollback-strategy always`), and the end-of-run control rolls back again as a safety net.
- **Watchdog.** A detached process rolls the run back at hold + 180 s if it is still active, so killing the runner never leaves a fault behind. `make stop` undoes everything immediately.
- **Recovery check.** After rollback, the health checks must pass within 300 s, or the run is recorded as not recovered. Fixing the lab after that (`make verify`, then `make redeploy` in netops-lab) is a human decision.
- **Host load.** A run is refused when the lab host's load average is above 48.

## What a run leaves behind

| Path | Content |
|---|---|
| `~/clab-runs/chaos/runs.jsonl` | One line per run: id, fault, targets, expected symptoms, what was injected and when, end, status, whether it recovered and how fast, and the scorecard |
| Elastic `logs-chaos.*` | The same runs, the scorecard rows, a timeline of injections and rollbacks, and the catalogue (Chaos command center). Append-only: a run is a start snapshot plus a final one |
| `~/clab-runs/chaos/journals/` | The Chaos Toolkit journal for each run, including evidence probe output such as the hijacked route |
| `~/clab-runs/chaos/logs/` | Run logs |
| GitHub `drift` issue | A switch or WAN change shows up as drift within 15 min: a realistic operational signal |

## Layout

```
targets.yml           the lab as chaos-lab sees it (switches, WAN, linux nodes, probes) + the deny list
traffic.yml           background traffic profiles
chaoslab/
  control.py          Chaos Toolkit control: guard, run start, watchdog, rollback safety net, recovery check
  guard.py            safety rules
  state.py            active faults + their undo, ground truth, hold, rollback
  scorecard.py        detection scorecard: did each expected signal reach Elastic, and how fast
  publish.py          runs, scorecards and the timeline to Elastic (logs-chaos.*)
  elastic.py          Elastic client (lab key): appends to logs-chaos.* only, reads telemetry with ES|QL
  watchdog.py         dead man's switch
  eos.py frr.py netem.py k8s.py attacker.py     fault drivers
  probes.py           health checks and evidence (direct, never via telemetry)
  cli.py              list / run / random / stop / status
  traffic.py          background traffic: start / stop / status (ping matrix)
experiments/*.yml     one experiment per fault
tests/test_guard.py   guard self-test
```

### Adding an experiment
1. Copy the closest file in `experiments/`.
2. Give it a new `id`, `targets`, `blast_radius` and `expected` symptoms, plus the inject actions (driver calls).
3. Run `make validate`, then `make dry EXP=<id>`.
4. Set `random: true` only if the lab recovers from it automatically and it is safe to run unattended.
