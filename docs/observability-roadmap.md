# End-to-end observability: step-by-step build guide

This guide builds full-stack observability for the lab, ending in Elastic:

- datacenter devices: interfaces, protocols and routes;
- the WAN;
- Kubernetes and Cilium;
- the web app.

It is the data foundation for a future Auto-SRE agent. The agent itself is out of scope here.

Work through the steps in order. Each step is one small PR. When its **Done when** check passes, tick the box and move on.

Rules for every step:

- Elastic is the only backend. Prometheus `:9464` stays only as a local debug tap.
- Terraform wherever it fits.
- Plain block YAML.
- No secrets in git.
- Edit only the source folders (`network/`, `kubernetes/`, `automation/`, `elastic/`), then run `make build` and commit the generated output.

Background: [telemetry.md](telemetry.md) describes what runs today; the design rationale is in [telemetry.md § Roadmap](telemetry.md).

---

## Where we are (2026-10-11)

| Works | Missing |
|---|---|
| gnmic → otelcol: interface counters, oper-status, BGP state and prefixes, LLDP, CPU and memory | Nothing reaches Elastic: CI has no `ELASTIC_OTLP_ENDPOINT` |
| `change-event.sh` writes ECS change events | The secrets `ELASTIC_ES_URL` and `ELASTIC_API_KEY` are not set, so events stay in `~/netops-changes.jsonl` |
| The `web` pods send OTLP traces | **otelcol has no traces pipeline, so the export fails with `404`** |
| Hubble enabled in Cilium | Nothing from k8s or Cilium is collected |
| | Route tables (OpenConfig AFT), OSPF, EVPN/VXLAN, syslog, sFlow, FRR WAN, hosts, context indices, alert rules |

---

## Step 0 – Prerequisites (before writing code)

- [ ] Get from the Elastic owner:
  - the deployment type and version (assumed: Elastic Cloud 9.x on AWS);
  - the **Managed OTLP endpoint** URL;
  - the Elasticsearch URL;
  - an API key for ingest;
  - an API key for Terraform (management).
- [ ] Put them in the git-ignored `automation/elastic.env` on the host:
  ```sh
  ELASTIC_OTLP_ENDPOINT=https://<id>.ingest.<region>.aws.elastic.cloud:443
  ELASTIC_ES_URL=https://<id>.es.<region>.aws.elastic.cloud
  ELASTIC_API_KEY=<ingest key>
  ```
- [ ] Add the same three values as GitHub secrets (you need repo admin rights for this):
  ```sh
  gh secret set ELASTIC_OTLP_ENDPOINT
  gh secret set ELASTIC_ES_URL
  gh secret set ELASTIC_API_KEY
  ```
- [ ] Start every step from the latest `main` on a new branch:
  ```sh
  git switch main && git pull && git switch -c <branch>
  ```

**Done when:** `curl -s -H "Authorization: ApiKey $ELASTIC_API_KEY" "$ELASTIC_ES_URL"` returns the cluster info.

---

## Phase P0 – Foundation: get today's data into Elastic

### Step 1 – Collector accepts traces and logs (fixes the web 404)
- [ ] `containerlab/telemetry/otelcol/base.yml`:
  - add `traces` and `logs` pipelines, both fed by the `otlp` receiver;
  - add the `memory_limiter` processor;
  - turn on the collector's own metrics (`service.telemetry.metrics`).
- [ ] `elastic.yml`: send all three pipelines to `otlp_http/elastic`.
- [ ] `automation/render.py` (the `nodes["otelcol"]` block): switch the image to the **EDOT Collector**, Elastic's OTel distribution, and pin its version.

**Done when:**
- `kubectl -n prod logs deploy/web` shows no more `404`;
- the `debug` exporter prints spans.

### Step 2 – CI keeps the Elastic export on
- [ ] `.github/workflows/deploy.yml` and `drift.yml`: pass `ELASTIC_OTLP_ENDPOINT`, `ELASTIC_API_KEY` and `ELASTIC_ES_URL` from the secrets. The `Makefile` then picks `OTELCOL_PROFILE=elastic` automatically.

**Done when:**
- after a CI deploy, `docker inspect clab-netops-otelcol` shows the `elastic.yml` profile;
- `logs-netops.changes-default` has the deploy event.

### Step 3 – Elastic managed as code
- [ ] New folder `elastic/terraform/` using the `elastic/elasticstack` provider, with state on the host like the k8s state.
- [ ] Create:
  - index templates and lifecycle settings (TSDS for `metrics-gnmi.*`: 7 days raw, then downsampled to 1 minute);
  - one API key per signal (least privilege);
  - the Kibana space.
- [ ] Add `make elastic` (plan and apply), following the pattern of `automation/k8s`.

**Done when:** `make elastic` shows no changes on a second run.

### Step 4 – Verification checks Elastic, not the local tap
- [ ] `automation/verify.sh`: add an ES|QL check of document count and newest `@timestamp` per data stream (`metrics-gnmi*`, `traces-*`). Keep the `:9464` check as the fallback when there is no Elastic.

**Done when:** `make verify` shows PASS for Elastic freshness.

---

## Phase P1 – Network depth: routes, protocols, events

### Step 5 – Switch-side config (AVD)
- [ ] `network/group_vars/FABRIC/management.yml`:
  - enable the OpenConfig route-table models: `management api models` → `provider aft` with `ipv4-unicast` and `ipv6-unicast`, via `custom_structured_configuration_eos_cli` or the AVD key;
  - `logging host 172.20.20.250` in VRF MGMT;
  - `sflow` (sample 1:100, destination the goflow2 IP, source Management1). It is used in Step 10, so enabling it now is harmless.
- [ ] `make build && make plan`: check the diff is only these lines, then merge. The deploy applies it.

**Done when:** `gnmic get --path '/network-instances/network-instance[name=default]/afts/ipv4-unicast'` returns routes.

### Step 6 – gnmic subscriptions
In `automation/telemetry/gnmic.base.yml`:
- [ ] **Add:**
  - AFT routes and next-hops for each VRF (on change);
  - OSPF neighbours (`eos_native:/Sysdb/routing/ospf/status`, on change);
  - EVPN/VXLAN: VTEPs, VNIs, MAC counts (30s);
  - sub-interface IPv4 MTU (300s).
- [ ] **Drop:** per-core CPU. Keep only the average.
- [ ] **Rename:** to short names (`net.if.in.octets`, `net.bgp.session_state`, …) in the existing `event-starlark` processor, keeping the original path as an attribute.
- [ ] **Second output:** route, BGP, OSPF and LLDP *changes* go as JSON events to a file, which the collector reads with its `filelog` receiver into `logs-gnmi.state`.

**Done when:**
- ES|QL on `logs-gnmi.state` shows a route withdraw/add when you shut a leaf uplink;
- series count is under 2.5k.

### Step 7 – Syslog receiver and FRR WAN telemetry
- [ ] Collector: add the `syslog` receiver (UDP 514) → `logs-syslog.otel-*`.
- [ ] FRR (`wan1.conf`, `wan2.conf` render path): `log syslog`, forwarded to the collector.
- [ ] Add a `frr_exporter` sidecar per WAN router, scraped by the collector's `prometheus` receiver → `metrics-frr.otel-*`.

**Done when:** `%BGP` and `%LINEPROTO` events from cEOS, and FRR BGP logs, appear in Elastic within 15 seconds.

---

## Phase P2 – Context and change: make the data joinable

### Step 8 – Source of truth exported to lookup indices
- [ ] `automation/render.py` writes NDJSON from the source-of-truth data it already parses into `generated/elastic/`:

  | Index | Built from |
  |---|---|
  | `net-devices` | name, role, DC, ASN, loopback |
  | `net-links` | `cabling.yml` + `cluster.yml` node links |
  | `net-ip-map` | interface IPs, /31s, pod CIDRs and VIPs (`ip_range`) → device, interface, VRF, k8s node |
  | `net-intent` | expected BGP peers, interfaces that should be up, MTU, from the AVD structured config |

- [ ] `elastic/terraform/`: create these as lookup-mode indices.
- [ ] Deploy workflow: bulk-load the NDJSON after apply (replace the contents on each merge).

**Done when:** an ES|QL `LOOKUP JOIN` from `metrics-gnmi*` on device + interface returns `peer_device`.

### Step 9 – Drift results into Elastic
- [ ] `drift.yml`: send each run's result (in sync, or which devices drifted) to `logs-netops.drift`, reusing the pattern in `change-event.sh`.

**Done when:** a drift run is visible in Elastic every 15 minutes.

---

## Phase P3 – Flows

### Step 10 – sFlow → goflow2 → Elastic
- [ ] `automation/render.py`: add a `goflow2` node on `clab-mgmt` with a fixed IP. It writes JSON to a bind-mounted file, which the collector reads with `filelog` into `logs-sflow.flows`.
- [ ] FRR and Linux hosts: add `hsflowd` where it's cheap (optional).

**Done when:** during `iperf3 -c iperf3-dc2`, the top talker in Elastic is the iperf pod IP, seen on every hop of the path.

---

## Phase P4 – Kubernetes and Cilium

### Step 11 – EDOT in the cluster
- [ ] New `kubernetes/terraform/observability.tf`: a `helm_release` for Elastic's OpenTelemetry kube-stack chart, pinned. It runs:
  - a DaemonSet: kubeletstats, filelog for container logs, OTLP;
  - a cluster collector: k8s_cluster metrics, k8s events.
- [ ] It exports to the lab gateway `172.20.20.250` over eth0 (the management network), not across the fabric.
- [ ] Point the `web` app's `OTEL_EXPORTER_OTLP_ENDPOINT` (in `apps.tf`) at the node-local collector.

**Done when:** `kubectl delete pod` on a web pod shows up in `logs-k8s.events` within 15 seconds.

### Step 12 – Cilium and Hubble
- [ ] `kubernetes/terraform/cilium.tf`:
  - turn on `prometheus.enabled`, `operator.prometheus` and `hubble.metrics` (dns, drop, tcp, flow, port-distribution);
  - turn on the `hubble.export` flow-log file. Relay stays off.
- [ ] The collector scrapes the Cilium agent, operator and BGP metrics, and tails the Hubble flow file into `logs-hubble.flows`.

**Done when:** an ES|QL query lists Hubble drop reasons, and Cilium's BGP session state to the leaves is visible.

### Step 13 – Lab containers
- [ ] Collector on the lab host: add the `docker_stats` receiver. This needs the Docker socket mounted read-only. It covers the 8 hosts, k6, gnmic and every lab container.

**Done when:** each `clab-netops-*` container has CPU, memory and network metrics.

---

## Phase P5 – Apps and user experience

### Step 14 – App signals and synthetic checks
- [ ] Web app logs flow through the k8s filelog (Step 11), with trace IDs, into `logs-app.otel-*`.
- [ ] k6 (`inet-k6`): turn on its OTel output to the gateway.
- [ ] Elastic Synthetics **private location**: a container on the Internet side of the WAN. HTTP monitors for `192.0.2.10` and `10.99.0.10`, defined in `elastic/terraform/`.

**Done when:** the Synthetics monitors are green, and a slow trace can be followed to its pod, node and leaf.

---

## Phase P6 – Derived layer (agent-ready data, no agent logic)

### Step 15 – Latest-state views
- [ ] Elastic transforms in `elastic/terraform/`:
  - `net-state-latest`: one document per device + interface + peer;
  - `net-routes-latest`: one document per device + VRF + prefix, with an `ip_range` field for longest-prefix match.

**Done when:** a single query returns the current state of `dc1-leaf1` interfaces and routes.

### Step 16 – Rules, SLOs, ML jobs and dashboards (all in Terraform)
- [ ] ES|QL rules:
  - intent vs. actual (via `net-intent`);
  - BGP or OSPF not established;
  - interface errors above 0;
  - utilisation above 80%;
  - no data from a source in 60 seconds.
- [ ] SLOs: web availability and latency.
- [ ] ML anomaly detection jobs: interface errors and utilisation; trace latency.
- [ ] Dashboards: fabric, WAN, k8s/Cilium, and an app → network drill-down.

**Done when:** every fault drill below raises its alert.

---

## Final acceptance (the end-to-end test)

1. [ ] Fresh clone, then `make down && make up`: everything comes back without manual steps. Then `make elastic` reports no changes.
2. [ ] Freshness: every data stream and every source is newer than 2× its interval.
3. [ ] Join chain: web trace → pod IP → `net-ip-map` → node → leaf port → interface counters → route path → sFlow hops.
4. [ ] Fault drills. Each must give a signal in Elastic within 60 seconds and recover after the fault is cleared:

   | Drill | Expected |
   |---|---|
   | Shut a leaf uplink | oper-status 0, routes change, syslog event, rule fires |
   | Stop a BGP peer | FSM drop on both sides (leaf gNMI and Cilium) |
   | Delete a web pod | k8s event, VIP route withdrawn, traffic goes to the other DC |
   | iperf load on the DCI | utilisation rule fires, sFlow top talker is the iperf pod |
   | Lower the MTU on a DCI link | intent-vs-actual rule fires, web latency SLO burns |
   | A bad config PR is merged | the change event lines up with when the symptoms started |

## Progress log
| Date | Step | PR | Notes |
|---|---|---|---|
| | | | |
