# End-to-end observability: step-by-step build guide

This guide builds full-stack observability for the lab, ending in Elastic:

- datacenter devices: interfaces, protocols and routes;
- the WAN;
- Kubernetes and Cilium;
- the web app.

It is the data foundation for a future Auto-SRE agent. The agent itself is out of scope here.

Work through the steps in order. Each step is one small PR. When its **Done when** check passes, tick the box and move on.

Rules for every step:

- Elastic is the only backend. Prometheus `:9464` (on gnmic) stays only as a local debug tap.
- Terraform wherever it fits.
- Plain block YAML.
- No secrets in git.
- Edit only the source folders (`network/`, `kubernetes/`, `automation/`, `elastic/`), then run `make build` and commit the generated output.

Background: [telemetry.md](telemetry.md) describes what runs today; the design rationale is in [telemetry.md § Roadmap](telemetry.md).

---

## Where we are (2026-10-12)

| Works | Missing |
|---|---|
| gnmic → EDOT Collector → Elastic: interface counters, oper-status, BGP state and prefixes, LLDP, CPU and memory, in `metrics-gnmi.otel-default` | Route tables (OpenConfig AFT), OSPF, EVPN/VXLAN, syslog, FRR WAN, hosts |
| The `web` pods' traces, metrics and logs reach Elastic (`traces-generic.otel-default`) | Kubernetes, Cilium, Hubble |
| `change-event.sh` writes ECS change events to `logs-netops.changes-default` | Context indices (topology, IP map, intent), alert rules, SLOs, dashboards |
| `elastic/terraform/`: data stream templates, Kibana space `netops`, data views | Flows: cEOS was seen to send no sFlow samples, so this needs a test or host-side sampling |
| `make verify` checks freshness in Elastic with ES\|QL | |

The Elastic project is **Serverless, Elasticsearch type** (no Managed OTLP endpoint, no Observability apps).
The collector writes straight to Elasticsearch and is ready for a Managed OTLP endpoint
([elastic.md § 9](elastic.md#9-moving-to-a-managed-otlp-endpoint-later)). Steps 14 and 16 need an
Observability project for Synthetics and SLOs.

---

## Step 0 – Prerequisites (before writing code)

- [x] Elastic details: Serverless Elasticsearch project 9.6 in `ap-southeast-2`; Elasticsearch and Kibana
  endpoints; an admin API key.
- [x] Put them in the git-ignored `automation/elastic.env` on the host (`ELASTIC_ES_URL`, `ELASTIC_KIBANA_URL`,
  `ELASTIC_TF_API_KEY`). See [elastic.md § First-time setup](elastic.md#3-first-time-setup).
- [ ] Create the restricted lab key (`automation/elastic role`, then Kibana → API keys) and put it in
  `ELASTIC_API_KEY`.
- [ ] Copy the CI settings into the repository secrets (owner): `automation/elastic gh-secrets`.
- [x] Start every step from the latest `main` on a new branch:
  ```sh
  git switch main && git pull && git switch -c <branch>
  ```

**Done when:** `make verify` passes its `== Elastic ==` section with the lab key, and a CI deploy logs
`collector profile: elastic`.

---

## Phase P0 – Foundation: get today's data into Elastic

### Step 1 – Collector accepts traces and logs (fixes the web 404)
- [x] `containerlab/telemetry/otelcol/base.yml`: `traces` and `logs` pipelines next to `metrics`;
  `memory_limiter`; the collector's own metrics scraped into `metrics-otelcol`; `data_stream.dataset` per source.
- [x] Profiles: `elastic.yml` (`elasticsearch` exporter straight to Elasticsearch, disk queue) and
  `elastic-otlp.yml` (OTLP to a Managed OTLP endpoint, for later).
- [x] `automation/render.py`: the **EDOT Collector** image, pinned (`9.5.5`). The EDOT Collector has no
  Prometheus exporter, so the local `:9464` debug tap moved to a gnmic Prometheus output.

**Done when:** the web pods log no more `404`, and their spans are in Elastic.

### Step 2 – CI keeps the Elastic export on
- [x] `automation/lab` chooses the collector profile from the Elastic settings every time it copies the bundle
  (also in CI's `converge`), writes the URL and key into files only the collector reads, and restarts a
  telemetry node when its files change. One loader, `automation/elastic-env.sh`, serves the lab helper,
  Terraform, `verify.sh` and `change-event.sh`.
- [x] `.github/workflows/deploy.yml`: passes `ELASTIC_ES_URL`, `ELASTIC_OTLP_ENDPOINT` and `ELASTIC_API_KEY`
  from the secrets.

**Done when:**
- a CI deploy logs `collector profile: elastic`;
- `logs-netops.changes-default` has the deploy event.

### Step 3 – Elastic managed as code
- [x] `elastic/terraform/` with the `elastic/elasticstack` provider; state in
  `~/.local/share/netops/terraform-elastic.tfstate` (outlives the lab). `make elastic` / `make elastic-plan`
  via `automation/elastic`.
- [x] Index templates for `metrics-gnmi.otel-*` (TSDS, 7 days) and `metrics-otelcol.otel-*` (3 days), reusing
  Elastic's built-in OTel template.
- [x] The lab key's privileges as code (`security.tf`). The key itself is made in Kibana: an API key can't
  create another key with privileges.
- [x] Kibana space `netops` and data views.
- [ ] Downsampling to 1 minute: not available with Serverless retention settings; revisit if the project changes.

**Done when:** `make elastic-plan` shows no changes on a second run. ✔

### Step 4 – Verification checks Elastic, not the local tap
- [x] `automation/verify.sh`: ES|QL checks that all 14 switches sent data in the last 2 minutes, that the
  collector's own metrics arrive, and that web spans arrive. The `:9464` check stays.

**Done when:** `make verify` shows PASS for Elastic freshness.

---

## Phase P1 – Network depth: routes, protocols, events

### Step 5 – Switch-side config (AVD)
- [ ] `network/group_vars/FABRIC/management.yml`:
  - enable the OpenConfig route-table models: `management api models` → `provider aft` with `ipv4-unicast` and `ipv6-unicast`, via `custom_structured_configuration_eos_cli` or the AVD key;
  - `logging host 172.20.20.250` in VRF MGMT;
  - sFlow: **test first on one leaf.** cEOS in containers was seen to send no sFlow samples
    ([architecture.md § Known gaps](architecture.md#12-known-gaps)). Enable it (sample 1:100, destination
    the goflow2 IP, source Management1) and check the sample counters in `show sflow`. Roll it out only if
    samples appear; otherwise Step 10 uses host-side sampling.
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
- [ ] Sources: cEOS sFlow if Step 5's test showed samples. Otherwise sample on the lab host instead:
  `hsflowd` or `pmacctd` watching the lab's veth links, which sees every hop without the switches' help.
- [ ] `automation/render.py`: add a `goflow2` node on `clab-mgmt` with a fixed IP. It writes JSON to a bind-mounted file, which the collector reads with `filelog` into `logs-sflow.flows`.

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
| 2026-10-12 | 0–4 | `obs-p0-elastic-foundation` | EDOT Collector writing straight to Elasticsearch (Serverless Elasticsearch project, no Managed OTLP); profile `elastic-otlp` ready; `elastic/terraform`; verify via ES\|QL. Lab key and CI secrets still to be created by the owner |
