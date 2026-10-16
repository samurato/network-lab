# The layered dashboards (netops space): one overview on top, then a dashboard per layer.
#   Overview            /s/netops/app/dashboards#/view/netops-overview      is anything wrong, and in which layer?
#   Web                 /s/netops/app/dashboards#/view/netops-web           the app: requests, errors, latency, runtime
#   Kubernetes          /s/netops/app/dashboards#/view/netops-kubernetes    nodes, workloads, pods, events, logs
#   Network             /s/netops/app/dashboards#/view/netops-fabric        the fabric (dashboards.tf)
#     Link failures     /s/netops/app/dashboards#/view/netops-links         (dashboards-faults.tf)
#     Routing & WAN     /s/netops/app/dashboards#/view/netops-routing       BGP by type, WAN (gNMI + BMP), routes
#   Telemetry pipeline  /s/netops/app/dashboards#/view/netops-pipeline      (dashboards.tf)
#   SLOs                /s/netops/app/slos                                   (slo.tf)
#
# Panels here are short specs turned into Kibana panels by local.layer_panels:
#   kind = "md"      text
#   kind = "metric"  q (query), col (primary column), optional sec + sec_label (secondary)
#   kind = "table"   q, cols
#   kind = "xy"      q, chart (line | bar_stacked | area_stacked), ys (columns), optional by (breakdown), y_title
# Every panel also has title and its grid: x, y, w, h (the dashboard is 48 wide).
locals {
  nav = join(" · ", [
    "[Overview](/s/netops/app/dashboards#/view/netops-overview)",
    "[Web](/s/netops/app/dashboards#/view/netops-web)",
    "[Kubernetes](/s/netops/app/dashboards#/view/netops-kubernetes)",
    "[Network](/s/netops/app/dashboards#/view/netops-fabric)",
    "[Link failures](/s/netops/app/dashboards#/view/netops-links)",
    "[Routing & WAN](/s/netops/app/dashboards#/view/netops-routing)",
    "[Telemetry pipeline](/s/netops/app/dashboards#/view/netops-pipeline)",
    "[SLOs](/s/netops/app/slos)",
  ])
  times = "Tiles and tables marked *now* show the last 2 minutes; charts follow the time picker. Times are in your browser's timezone."

  layer_specs = {
    overview = [
      { kind = "md", x = 0, y = 0, w = 48, h = 5, text = "**Overview**: one row per layer, worst first in the status table; open the layer's dashboard to see why. ${local.times}\n\n${local.nav}" },
      { kind = "table", x = 0, y = 5, w = 24, h = 7, title = "Layer status now (OK / DEGRADED / DOWN)", q = "ovr_status", cols = ["layer", "status", "detail"] },
      { kind = "table", x = 24, y = 5, w = 24, h = 7, title = "Service level objectives (error budget left)", q = "ovr_slo", cols = ["slo", "layer", "status", "sli_pct", "objective_pct", "budget_left_pct"] },
      { kind = "metric", x = 0, y = 12, w = 6, h = 5, title = "Web · requests / min", q = "web_rpm", col = "requests_per_min" },
      { kind = "metric", x = 6, y = 12, w = 6, h = 5, title = "Web · p95 ms", q = "web_p95", col = "p95_ms" },
      { kind = "metric", x = 12, y = 12, w = 6, h = 5, title = "Web · 5xx %", q = "web_err", col = "error_pct" },
      { kind = "metric", x = 18, y = 12, w = 6, h = 5, title = "Web · pods reporting", q = "web_pods", col = "pods" },
      { kind = "metric", x = 24, y = 12, w = 6, h = 5, title = "Kubernetes · nodes ready", q = "k8s_nodes_ready", col = "nodes_ready", sec = "nodes", sec_label = "of nodes" },
      { kind = "metric", x = 30, y = 12, w = 6, h = 5, title = "Kubernetes · web pods available", q = "k8s_web_avail", col = "web_available", sec = "web_desired", sec_label = "desired" },
      { kind = "metric", x = 36, y = 12, w = 6, h = 5, title = "Kubernetes · restarts (15 min)", q = "k8s_restarts_kpi", col = "restarts_15m" },
      { kind = "metric", x = 42, y = 12, w = 6, h = 5, title = "Kubernetes · pods not running", q = "k8s_pods_not_running", col = "pods_not_running", sec = "pods", sec_label = "of pods" },
      { kind = "metric", x = 0, y = 17, w = 6, h = 5, title = "Network · switches reporting", q = "fab_switches", col = "switches" },
      { kind = "metric", x = 6, y = 17, w = 6, h = 5, title = "Network · BGP established", q = "fab_bgp", col = "established", sec = "sessions", sec_label = "of sessions" },
      { kind = "metric", x = 12, y = 17, w = 6, h = 5, title = "Network · ports down", q = "fab_ports_down", col = "ports_down", sec = "ports", sec_label = "cabled ports" },
      { kind = "metric", x = 18, y = 17, w = 6, h = 5, title = "Network · fabric traffic (Mbps)", q = "fab_mbps", col = "fabric_mbps" },
      { kind = "metric", x = 24, y = 17, w = 6, h = 5, title = "Telemetry · gNMI docs / min", q = "pipe_docs_kpi", col = "docs_per_min" },
      { kind = "metric", x = 30, y = 17, w = 6, h = 5, title = "Telemetry · switches silent > 60 s", q = "pipe_stale_kpi", col = "stale_switches" },
      { kind = "metric", x = 36, y = 17, w = 6, h = 5, title = "Telemetry · export queue", q = "pipe_queue_kpi", col = "queue", sec = "capacity", sec_label = "capacity" },
      { kind = "metric", x = 42, y = 17, w = 6, h = 5, title = "Telemetry · Kafka lag (messages)", q = "pipe_kafka_lag_kpi", col = "kafka_lag" },
      { kind = "xy", x = 0, y = 22, w = 24, h = 10, title = "Web: requests and 5xx errors", q = "ovr_web_ts", chart = "line", ys = ["requests", "errors_5xx"], y_title = "requests" },
      { kind = "xy", x = 24, y = 22, w = 24, h = 10, title = "Web: p95 latency (ms)", q = "ovr_web_p95_ts", chart = "line", ys = ["p95_ms"], y_title = "ms" },
      { kind = "xy", x = 0, y = 32, w = 24, h = 10, title = "Kubernetes: web pods available and nodes ready", q = "ovr_k8s_ts", chart = "line", ys = ["web_pods_available", "nodes_ready"], y_title = "count" },
      { kind = "xy", x = 24, y = 32, w = 24, h = 10, title = "Network: BGP sessions not established and ports down", q = "ovr_net_ts", chart = "line", ys = ["bgp_not_established", "ports_down"], y_title = "count" },
      { kind = "xy", x = 0, y = 42, w = 24, h = 10, title = "Telemetry: collector sent to Elastic (per second)", q = "pipe_sent", chart = "line", ys = ["metric_points_per_s", "spans_per_s"], y_title = "per second" },
      { kind = "xy", x = 24, y = 42, w = 24, h = 10, title = "Telemetry: Kafka messages behind, per topic", q = "pipe_kafka_lag", chart = "line", ys = ["messages_behind"], by = "topic", y_title = "messages" },
      { kind = "table", x = 0, y = 52, w = 48, h = 14, title = "What changed: deploys, drift, BGP and port changes, Kubernetes warnings (newest first)", q = "ovr_changes", cols = ["@timestamp", "layer", "source", "what"] },
    ]

    web = [
      { kind = "md", x = 0, y = 0, w = 48, h = 5, text = "**Web**: the `web` app, server side: its traces (`traces-generic.otel-*`), runtime metrics and logs; kube-probe health checks are excluded from user traffic. One web pod runs per Kubernetes node, so the node names the pod. There is no user-side data: in a total outage requests drop to zero rather than turning into errors. ${local.times}\n\n${local.nav}" },
      { kind = "metric", x = 0, y = 5, w = 8, h = 6, title = "Requests / min (5 min)", q = "web_rpm", col = "requests_per_min" },
      { kind = "metric", x = 8, y = 5, w = 8, h = 6, title = "p95 latency ms (5 min)", q = "web_p95", col = "p95_ms" },
      { kind = "metric", x = 16, y = 5, w = 8, h = 6, title = "5xx error rate % (5 min)", q = "web_err", col = "error_pct" },
      { kind = "metric", x = 24, y = 5, w = 8, h = 6, title = "Requests in flight (now)", q = "web_active", col = "active_requests" },
      { kind = "metric", x = 32, y = 5, w = 8, h = 6, title = "Pods reporting (now)", q = "web_pods", col = "pods" },
      { kind = "metric", x = 40, y = 5, w = 8, h = 6, title = "Pods available (Kubernetes, now)", q = "k8s_web_avail", col = "web_available", sec = "web_desired", sec_label = "desired" },
      { kind = "xy", x = 0, y = 11, w = 24, h = 11, title = "Requests by status", q = "web_red_ts", chart = "bar_stacked", ys = ["requests"], by = "status", y_title = "requests" },
      { kind = "xy", x = 24, y = 11, w = 24, h = 11, title = "p95 latency by route (ms)", q = "web_lat_by_route", chart = "line", ys = ["p95_ms"], by = "http.route", y_title = "ms" },
      { kind = "xy", x = 0, y = 22, w = 24, h = 11, title = "Requests by data centre", q = "web_req_by_dc", chart = "area_stacked", ys = ["requests"], by = "dc", y_title = "requests" },
      { kind = "xy", x = 24, y = 22, w = 24, h = 11, title = "Requests by node (pod)", q = "web_req_by_node", chart = "line", ys = ["requests"], by = "k8s.node.name", y_title = "requests" },
      { kind = "xy", x = 0, y = 33, w = 24, h = 11, title = "p95 latency by node (ms)", q = "web_p95_by_node", chart = "line", ys = ["p95_ms"], by = "k8s.node.name", y_title = "ms" },
      { kind = "xy", x = 24, y = 33, w = 12, h = 11, title = "Python CPU % by node", q = "web_cpu_ts", chart = "line", ys = ["cpu_pct"], by = "k8s.node.name", y_title = "%" },
      { kind = "xy", x = 36, y = 33, w = 12, h = 11, title = "Python memory RSS (MB) by node", q = "web_mem_ts", chart = "line", ys = ["rss_mb"], by = "k8s.node.name", y_title = "MB" },
      { kind = "table", x = 0, y = 44, w = 24, h = 10, title = "Routes", q = "web_routes", cols = ["route", "method", "requests", "p50_ms", "p95_ms", "errors_5xx"] },
      { kind = "table", x = 24, y = 44, w = 24, h = 10, title = "Nodes (where the requests land)", q = "web_nodes", cols = ["node", "pods", "requests", "p95_ms"] },
      { kind = "table", x = 0, y = 54, w = 24, h = 12, title = "Slowest requests", q = "web_slowest", cols = ["@timestamp", "http.route", "http.status_code", "k8s.node.name", "ms", "trace.id"] },
      { kind = "table", x = 24, y = 54, w = 24, h = 12, title = "App errors in the logs (grouped)", q = "web_log_errors", cols = ["what", "lines", "last_seen"] },
    ]

    kubernetes = [
      { kind = "md", x = 0, y = 0, w = 48, h = 5, text = "**Kubernetes**: 6 nodes across DC1, DC2 and the WAN site (control plane cp1 DC1, cp2 DC2, cp3 WAN: etcd needs 2 of 3). State from `metrics-k8s.cluster`, usage from `metrics-k8s.kubelet`, events and container logs from `logs-k8s.*`. If the cluster state tiles go empty, the Kubernetes API itself is unreachable. ${local.times}\n\n${local.nav}" },
      { kind = "metric", x = 0, y = 5, w = 8, h = 6, title = "Nodes ready (now)", q = "k8s_nodes_ready", col = "nodes_ready", sec = "nodes", sec_label = "of nodes" },
      { kind = "metric", x = 8, y = 5, w = 8, h = 6, title = "Control plane ready (now)", q = "k8s_cp_ready", col = "control_plane_ready", sec = "control_plane", sec_label = "of control plane" },
      { kind = "metric", x = 16, y = 5, w = 8, h = 6, title = "Web pods available (now)", q = "k8s_web_avail", col = "web_available", sec = "web_desired", sec_label = "desired" },
      { kind = "metric", x = 24, y = 5, w = 8, h = 6, title = "Workloads short of replicas (now)", q = "k8s_workloads_short", col = "workloads_short", sec = "workloads", sec_label = "of workloads" },
      { kind = "metric", x = 32, y = 5, w = 8, h = 6, title = "Pods not running (now)", q = "k8s_pods_not_running", col = "pods_not_running", sec = "pods", sec_label = "of pods" },
      { kind = "metric", x = 40, y = 5, w = 8, h = 6, title = "Container restarts (15 min)", q = "k8s_restarts_kpi", col = "restarts_15m" },
      { kind = "table", x = 0, y = 11, w = 48, h = 8, title = "Nodes now (cpu % of allocatable, memory working set, filesystem used)", q = "k8s_nodes", cols = ["node", "dc", "role", "ready", "pressure", "cpu_pct", "mem_gb", "fs_pct"] },
      { kind = "xy", x = 0, y = 19, w = 24, h = 10, title = "CPU by node (cores)", q = "k8s_cpu_ts", chart = "line", ys = ["cpu_cores"], by = "k8s.node.name", y_title = "cores" },
      { kind = "xy", x = 24, y = 19, w = 24, h = 10, title = "Memory working set by node (GB)", q = "k8s_mem_ts", chart = "line", ys = ["mem_gb"], by = "k8s.node.name", y_title = "GB" },
      { kind = "xy", x = 0, y = 29, w = 24, h = 10, title = "Node network traffic (Mbps)", q = "k8s_net_ts", chart = "line", ys = ["mbps"], by = "k8s.node.name", y_title = "Mbps" },
      { kind = "xy", x = 24, y = 29, w = 24, h = 10, title = "Node network errors per second", q = "k8s_net_err_ts", chart = "line", ys = ["errors_per_s"], by = "k8s.node.name", y_title = "errors / s" },
      { kind = "xy", x = 0, y = 39, w = 24, h = 10, title = "Pods by phase", q = "k8s_pod_phase_ts", chart = "bar_stacked", ys = ["pods"], by = "phase", y_title = "pods" },
      { kind = "xy", x = 24, y = 39, w = 24, h = 10, title = "Kubernetes events by type and reason", q = "k8s_events_ts", chart = "bar_stacked", ys = ["events"], by = "event", y_title = "events" },
      { kind = "table", x = 0, y = 49, w = 24, h = 12, title = "Workloads now (desired vs ready)", q = "k8s_workloads", cols = ["namespace", "kind", "name", "desired", "ready", "ok"] },
      { kind = "table", x = 24, y = 49, w = 24, h = 12, title = "Container restarts (time picker)", q = "k8s_restarts", cols = ["namespace", "pod", "container", "restarts", "total"] },
      { kind = "xy", x = 0, y = 61, w = 48, h = 9, title = "Container log lines by namespace and level", q = "k8s_logs_ts", chart = "bar_stacked", ys = ["lines"], by = "stream", y_title = "lines" },
      { kind = "table", x = 0, y = 70, w = 24, h = 12, title = "Kubernetes events (newest first)", q = "k8s_events", cols = ["@timestamp", "severity_text", "k8s.event.reason", "k8s.namespace.name", "object", "body.text"] },
      { kind = "table", x = 24, y = 70, w = 24, h = 12, title = "Warnings and errors in container logs (newest first)", q = "k8s_log_errors", cols = ["@timestamp", "k8s.namespace.name", "k8s.pod.name", "body.text"] },
    ]

    routing = [
      { kind = "md", x = 0, y = 0, w = 48, h = 5, text = "**Routing & WAN**: BGP by session type from the switches (gNMI), the route log (AFT, `logs-gnmi.state`), and the WAN routers' own view over BMP (`logs-bgp.bmp`: wan1, wan2). Session types: *EVPN overlay* (loopbacks), *WAN underlay* (BGW to WAN, default VRF), *WAN VRF PROD*, *Kubernetes (Cilium)* (leaf to node, VRF PROD). ${local.times}\n\n${local.nav}" },
      { kind = "table", x = 0, y = 5, w = 16, h = 8, title = "BGP sessions by type (now)", q = "rte_bgp_by_type", cols = ["type", "established", "sessions", "ok"] },
      { kind = "xy", x = 16, y = 5, w = 32, h = 8, title = "BGP sessions not established, by type", q = "rte_bgp_type_ts", chart = "bar_stacked", ys = ["not_established"], by = "type", y_title = "sessions" },
      { kind = "table", x = 0, y = 13, w = 16, h = 11, title = "WAN sessions per border gateway (now)", q = "rte_wan_sessions", cols = ["bgw", "vrf", "peer", "state"] },
      { kind = "xy", x = 16, y = 13, w = 32, h = 11, title = "Prefixes received from the WAN, per border gateway and VRF", q = "rte_wan_prefixes_ts", chart = "line", ys = ["prefixes"], by = "bgw_vrf", y_title = "prefixes" },
      { kind = "xy", x = 0, y = 24, w = 24, h = 10, title = "Service VIPs learned from Kubernetes, per leaf", q = "rte_k8s_prefixes_ts", chart = "line", ys = ["vip_prefixes"], by = "host.name", y_title = "prefixes" },
      { kind = "xy", x = 24, y = 24, w = 24, h = 10, title = "OSPF LSAs per switch (underlay changes)", q = "rte_ospf_ts", chart = "line", ys = ["lsas"], by = "host.name", y_title = "LSAs" },
      { kind = "xy", x = 0, y = 34, w = 24, h = 10, title = "WAN routers: BGP updates and withdraws (BMP)", q = "rte_bmp_ts", chart = "bar_stacked", ys = ["messages"], by = "what", y_title = "messages" },
      { kind = "table", x = 24, y = 34, w = 24, h = 10, title = "WAN routers' best routes, latest change per prefix (BMP Loc-RIB, 24 h)", q = "rte_bmp_routes", cols = ["wan", "prefix", "in_table", "as_path", "origin_as", "last_seen"] },
      { kind = "table", x = 0, y = 44, w = 24, h = 12, title = "Fabric route changes for public prefixes (192.0.2/24, 198.51.100/24, 203.0.113/24)", q = "rte_aft_public", cols = ["@timestamp", "host.name", "network-instance_name", "op", "ipv4-entry_prefix", "state.origin_protocol"] },
      { kind = "table", x = 24, y = 44, w = 24, h = 12, title = "WAN BGP messages (BMP, newest first)", q = "rte_bmp_log", cols = ["@timestamp", "host.name", "log_type", "bmp_rib_type", "ip_prefix", "as_path", "peer_ip"] },
    ]

    # appended to the Telemetry pipeline dashboard (dashboards.tf), below its own panels
    pipeline_extra = [
      { kind = "metric", x = 0, y = 46, w = 12, h = 6, title = "Kafka consumer lag (messages, now)", q = "pipe_kafka_lag_kpi", col = "kafka_lag" },
      { kind = "xy", x = 12, y = 46, w = 36, h = 10, title = "Kafka messages behind, per topic", q = "pipe_kafka_lag", chart = "line", ys = ["messages_behind"], by = "topic", y_title = "messages" },
      { kind = "xy", x = 0, y = 56, w = 48, h = 10, title = "Documents per data stream", q = "pipe_docs_by_stream", chart = "bar_stacked", ys = ["docs"], by = "stream", y_title = "docs" },
    ]
  }

  layer_panels = {
    for d, specs in local.layer_specs : d => [
      for p in specs : {
        type = p.kind == "md" ? "markdown" : "vis"
        grid = {
          x = p.x
          y = p.y
          w = p.w
          h = p.h
        }
        config_json = (
          p.kind == "md" ? jsonencode({
            content = try(p.text, "")
          }) :
          p.kind == "metric" ? jsonencode({
            type        = "metric"
            title       = try(p.title, "")
            data_source = local.esql_source[try(p.q, "")]
            metrics = concat(
              [
                {
                  type   = "primary"
                  column = try(p.col, "")
                  label  = try(p.label, " ")
                },
              ],
              [
                for c in try([p.sec], []) : {
                  type   = "secondary"
                  column = c
                  label  = try(p.sec_label, c)
                }
              ],
            )
          }) :
          p.kind == "table" ? jsonencode({
            type        = "data_table"
            title       = try(p.title, "")
            data_source = local.esql_source[try(p.q, "")]
            rows        = [for c in try(p.cols, []) : { column = c }]
          }) :
          jsonencode({
            type  = "xy"
            title = try(p.title, "")
            legend = {
              visibility = "visible"
              position   = "right"
            }
            axis = {
              x = {
                scale = "temporal"
                title = {
                  text    = ""
                  visible = false
                }
              }
              y = {
                scale = "linear"
                title = {
                  text    = try(p.y_title, "")
                  visible = true
                }
              }
            }
            layers = [
              merge(
                {
                  type        = try(p.chart, "line")
                  data_source = local.esql_source[try(p.q, "")]
                  x = {
                    column = "time"
                  }
                  y = [for c in try(p.ys, []) : { column = c }]
                },
                { for k, v in { breakdown_by = try({ column = p.by }, null) } : k => v if v != null },
              ),
            ]
          })
        )
      }
    ]
  }
}

resource "elasticstack_kibana_dashboard" "overview" {
  space_id     = elasticstack_kibana_space.netops.space_id
  dashboard_id = "netops-overview"
  title        = "NetOps · Overview"
  description  = "One pane of glass: status per layer (web, Kubernetes, network, telemetry), SLOs, key numbers, one timeline across the layers, what changed"
  time_range = {
    from = "now-1h"
    to   = "now"
  }
  refresh_interval = {
    pause = false
    value = 30000
  }
  query = {
    language = "kql"
    text     = ""
  }
  panels = local.layer_panels.overview
}

resource "elasticstack_kibana_dashboard" "web" {
  space_id     = elasticstack_kibana_space.netops.space_id
  dashboard_id = "netops-web"
  title        = "NetOps · Web"
  description  = "The web app: requests by status, route, data centre and node; latency; runtime CPU and memory; slowest requests; app errors (traces, metrics, logs)"
  time_range = {
    from = "now-1h"
    to   = "now"
  }
  refresh_interval = {
    pause = false
    value = 30000
  }
  query = {
    language = "kql"
    text     = ""
  }
  panels = local.layer_panels.web
}

resource "elasticstack_kibana_dashboard" "kubernetes" {
  space_id     = elasticstack_kibana_space.netops.space_id
  dashboard_id = "netops-kubernetes"
  title        = "NetOps · Kubernetes"
  description  = "Nodes (ready, pressure, CPU, memory, disk, network), control plane, workloads desired vs ready, pod phases, restarts, events, container logs"
  time_range = {
    from = "now-1h"
    to   = "now"
  }
  refresh_interval = {
    pause = false
    value = 30000
  }
  query = {
    language = "kql"
    text     = ""
  }
  panels = local.layer_panels.kubernetes
}

resource "elasticstack_kibana_dashboard" "routing" {
  space_id     = elasticstack_kibana_space.netops.space_id
  dashboard_id = "netops-routing"
  title        = "NetOps · Routing & WAN"
  description  = "BGP sessions by type, WAN sessions and prefixes per border gateway, Kubernetes VIPs per leaf, OSPF, route changes for public prefixes, the WAN routers' view (BMP)"
  time_range = {
    from = "now-1h"
    to   = "now"
  }
  refresh_interval = {
    pause = false
    value = 30000
  }
  query = {
    language = "kql"
    text     = ""
  }
  panels = local.layer_panels.routing
}
