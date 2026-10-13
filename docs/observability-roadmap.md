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

## Where we are (2026-10-13)

| Works | Missing |
|---|---|
| gnmic → EDOT Collector → Kafka → Elastic: interface counters, oper-status, MTU, BGP state and prefixes, OSPF LSA count, LLDP, memory, in `metrics-gnmi.otel-default` (short `net.*` names, about 1,900 series) | OSPF neighbour state (not in cEOS gNMI), syslog, FRR WAN, hosts |
| Every route, BGP, port, LLDP, VTEP, VNI and MAC change in `logs-gnmi.state.otel-default` | |
| The `web` pods' traces, metrics and logs reach Elastic (`traces-generic.otel-default`) | Kubernetes, Cilium, Hubble |
| `change-event.sh` writes ECS change events to `logs-netops.changes-default` | Context indices (topology, IP map, intent), alert rules, SLOs, dashboards |
| `elastic/terraform/`: data stream templates, Kibana space `netops`, data views, dashboards | Flows: cEOS sFlow works (step 5 test on dc1-leaf1); no flow collector yet (step 10) |
| Switches: OpenConfig route tables (AFT) on, clock Australia/Sydney, sFlow test on dc1-leaf1 | Switch syslog: configured, but rsyslog inside cEOS crash-loops on this host, so nothing is sent (step 7) |
| `make verify` checks freshness in Elastic with ES\|QL | |

**Lab status:** running since 2026-10-13 (brought back with `make up` for Step 6, redeployed for the new telemetry
binds; `make verify` 0 FAIL). Telemetry reaches Elastic through a Kafka buffer (24 h). **Next:** Step 7 (syslog and FRR WAN telemetry).

The Elastic project is **Serverless, Elasticsearch type** (no Managed OTLP endpoint, no Observability apps).
The collector writes straight to Elasticsearch and is ready for a Managed OTLP endpoint
([elastic.md § 10](elastic.md#10-moving-to-a-managed-otlp-endpoint-later)). Steps 14 and 16 need an
Observability project for Synthetics and SLOs.

---

## Step 0 – Prerequisites (before writing code)

- [x] Elastic details: Serverless Elasticsearch project 9.6 in `ap-southeast-2`; Elasticsearch and Kibana
  endpoints; an admin API key.
- [x] Put them in the git-ignored `automation/elastic.env` on the host (`ELASTIC_ES_URL`, `ELASTIC_KIBANA_URL`,
  `ELASTIC_TF_API_KEY`). See [elastic.md § First-time setup](elastic.md#3-first-time-setup).
- [x] Create the restricted lab key (`automation/elastic role`, then Kibana → API keys) and put it in
  `ELASTIC_API_KEY`.
- [x] Copy the CI settings into the repository secrets (owner): `automation/elastic gh-secrets`.
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
- [x] `network/group_vars/FABRIC/management.yml`:
  - OpenConfig route tables: `management api models` → `provider aft` → `ipv4-unicast`, `ipv6-unicast`, in
    `custom_structured_configuration_eos_cli` (AVD doesn't model it);
  - syslog (`logging_settings`): `logging vrf MGMT host 172.20.20.250 514`, RFC 5424, high-resolution
    timestamps, trap informational;
  - `timezone: Australia/Sydney` (asked for 2026-10-12). `render.py` reuses it for every Linux node by
    mounting `/usr/share/zoneinfo/Australia/Sydney` as `/etc/localtime`.
- [x] sFlow test on dc1-leaf1 (`network/group_vars/DC1.yml`): sample 1:100, polling 30 s, to
  `172.20.20.250:6343` in VRF MGMT. **Result: cEOS 4.36.2F does send sFlow.** Hardware samples count up in
  `show sflow`, and sFlow v5 datagrams reach 172.20.20.250. The earlier "no samples" note is out of date;
  Step 10 uses the switches.
- [x] Checked on a redeployed lab from the branch: `make verify` 0 FAIL.

**Done when:** `gnmic get --path '/network-instances/network-instance[name=default]/afts/ipv4-unicast'` returns routes. ✔
(dc1-leaf1: default VRF and VRF PROD both return entries.)

**Found:** rsyslog inside cEOS crash-loops on this host (`rsyslog.service ... status=1/FAILURE`, thousands of
restarts). A fresh cEOS with no logging config does the same, so it is not caused by this change; but no
switch syslog reaches the collector. See Step 7.

### Step 6 – gnmic subscriptions
In `automation/telemetry/gnmic.base.yml`:
- [x] **Add:**
  - AFT routes, next-hop groups and next hops for each VRF, IPv4 and IPv6 (on change; state stream only);
  - EVPN/VXLAN: remote VTEPs (`eos_native:/Sysdb/vxlan/remoteVtepHwConfig`), VNI mappings (`arista-vxlan`),
    MAC table (`eos_native:/Smash/bridging/status/smashFdbStatus`), on change, state stream only;
  - sub-interface IPv4 MTU (300 s) → `net.if.ipv4_mtu`;
  - OSPF: **neighbour state is not available over gNMI on cEOS 4.36** (OpenConfig `ospfv2` is config only, the
    EOS-native status has no neighbour table). Instead: the LSA count (`net.ospf.lsa_count`, 30 s) and OSPF routes
    in the AFT state documents, where a lost adjacency shows as withdrawn routes;
  - MAC counts are an ES|QL aggregation over the MAC state documents, not a metric.
- [x] **Drop:** CPU entirely, not just per core. cEOS reports the lab host's 64 cores for every switch, so there is no
  switch CPU to average; per-switch CPU comes from container stats (Step 12). Also dropped:
  `counters/last-update`, and BGP `best-paths`, `best-ecmp-paths`, `received-pre-policy` (series budget).
- [x] **Rename:** short names (`net.if.in_octets`, `net.bgp.session_state`, `net.bgp.prefixes.received`, …) in the
  `names` Starlark processor; anything not in the catalogue is dropped. Notes:
  - `in` is an ES|QL keyword, so `net.if.in.octets` would need backticks everywhere: names use `in_` / `out_`;
  - the original gNMI path is **not** a per-datapoint attribute: gnmic sends several values per event and tags
    are per event, so a path attribute would split every TSDS document into one per metric. The path of every
    name is in the catalogue ([telemetry.md § Metrics](telemetry.md#metrics)); `subscription-name` stays on each
    datapoint;
  - naming decided 2026-10-13: short custom `net.*` names and gnmic's key names, over the OpenTelemetry
    hardware conventions (`hw.network.io` + `network.io.direction`). Data streams and templates follow
    Elastic's convention (`<type>-<dataset>.otel-<namespace>`, built-in OTel templates).
- [x] **Second output:** route, BGP, LLDP, port, VTEP, VNI and MAC *changes* as JSON lines in
  `telemetry/state/gnmi-state.json` (a folder both containers bind; gnmic runs as the collector's uid). The
  collector's `file_log` receiver reads it into `logs-gnmi.state.otel-default` (logsdb, 30 days, Terraform
  template). One document per change, `op` = `update` / `delete`, the device's change time as `@timestamp`.
  (The EDOT Collector has no TCP log receiver, hence the file.)
- [x] **Found and fixed on the way:**
  - gnmic 0.49's target file loader re-subscribed every switch every 30 s (it saw each target as changed), so
    the switches resent all their routes and MACs: about 16,000 state lines a minute. Targets are now written into
    `gnmic.yml`; quiet fabric: about 20 lines a minute;
  - the Elasticsearch exporter's default queue (10 requests, 10 s flush) moved about 33 documents a second and
    made `file_log` drop lines when full (the first drill was lost that way). The `elastic` profile now sizes the
    queue in items (200,000), blocks instead of dropping, flushes every second; `file_log` retries on push-back.
    A 190,000-document backlog cleared in under 20 s.
- [x] Dashboard: *Fabric health* has a state-changes table; data view *Fabric state changes (gnmic)*;
  `make verify` checks that every switch has state documents.

**Done when:**
- ES|QL on `logs-gnmi.state` shows a route withdraw/add when you shut a leaf uplink. ✔ Drill 2026-10-13 09:14 UTC,
  dc1-leaf1 Ethernet1 shut for 30 s: Ethernet1 `DOWN` (09:14:01.519), routes re-pointed from the two-spine ECMP group
  to one next-hop group and the link's /31 withdrawn on dc1-leaf1 and its neighbours (`op` = `delete`), LLDP
  neighbour removed, then `UP` (09:14:31.871), LLDP `dc1-spine1` back, BGP 10.1.0.1 `ACTIVE` → `ESTABLISHED`.
  Gap: cEOS streamed the BGP recovery but not the session's drop; the drop is only in the 30 s
  `net.bgp.session_state` samples;
- series count is under 2.5k. ✔ 1,897 (was about 3,600).

### Step 7 – Syslog receiver and FRR WAN telemetry
- [ ] Collector: add the `syslog` receiver (UDP 514) → `logs-syslog.otel-*`.
- [ ] FRR (`wan1.conf`, `wan2.conf` render path): `log syslog`, forwarded to the collector.
- [ ] Add a `frr_exporter` sidecar per WAN router, scraped by the collector's `prometheus` receiver → `metrics-frr.otel-*`.

**Blocked for cEOS:** rsyslog crash-loops inside cEOS on this host (Step 5), so the switches send no syslog
yet. FRR and Linux syslog are not affected. Until cEOS rsyslog is fixed, switch events come from gNMI on-change
state (oper-status, BGP session state), which already reaches Elastic. The EDOT Collector has no `syslog`
receiver: use `filebeatreceiver` with a `syslog` / `udp` input, and `location: Australia/Sydney` for
RFC 3164 senders.

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
- [ ] Sources: cEOS sFlow (Step 5's test showed samples). Move the sFlow config from dc1-leaf1 to the fabric
  (`sflow_settings` + `fabric_sflow`), pointed at goflow2. Host-side sampling (`hsflowd` / `pmacctd` on the veth
  links) stays an option for the WAN and hosts.
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
- [ ] Dashboards: fabric, WAN, k8s/Cilium, and an app → network drill-down. *Started early (2026-10-12): fabric,
  web app and pipeline dashboards in `elastic/terraform/dashboards.tf`; WAN, k8s/Cilium and the drill-down come
  with their data.*

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
| 2026-10-13 | Kafka buffer | (this PR) | Kafka (`apache/kafka:3.9.1`, one KRaft broker, 172.20.20.252) between the collector and Elastic: receive pipelines → `kafka/out` → topics → `kafka/elastic` → `elasticsearch/elastic`, offsets committed after Elastic accepted. Outage test: Elastic unreachable 3½ min, lag 113 messages, drained in ~50 s, no gap. `make verify` checks the consumer lag (67 PASS) |
| 2026-10-13 | 6 | #12 | gnmic: AFT routes, EVPN/VXLAN, MTU, OSPF LSA count; CPU dropped; short `net.*` names; state changes → `logs-gnmi.state` via a shared file and `file_log`. 1,897 series (was ~3,600). Found: no OSPF neighbour state over gNMI on cEOS 4.36; `in` is an ES\|QL keyword; logsdb hides a record-level `host.name` (moved to the resource); gnmic file loader re-subscribing every 30 s (removed); exporter queue too small (sized). Withdraw drill passed. `make verify` 0 FAIL |
| 2026-10-13 | – | – | Lab shut down. Next: Step 6. Open: cEOS rsyslog crash loop (step 7), leftover `metrics-prometheusreceiver.otel-default` data stream from the first test |
| 2026-10-13 | 5 + timezone | #10 | AFT on, syslog configured (blocked by cEOS rsyslog loop), sFlow works on cEOS (dc1-leaf1 test), Australia/Sydney on every device. CI deploy verified: topology redeploy, collector profile `elastic`, change event in Elastic, `make verify` 0 FAIL |
| 2026-10-12 | 16 (part) | #9 | Dashboards as code: Fabric health, Web app, Pipeline & changes (ES\|QL panels, `config_json` in the Kibana API shape) |
| 2026-10-12 | 0–4 | #7, #8 | EDOT Collector writing straight to Elasticsearch (Serverless Elasticsearch project, no Managed OTLP); profile `elastic-otlp` ready; `elastic/terraform`; verify via ES\|QL. Lab key (`netops-lab`) and CI secrets created by the owner the same day |
