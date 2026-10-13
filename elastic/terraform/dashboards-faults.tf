# Fault dashboards, for chaos runs and real incidents alike (telemetry only: the chaos answer key never comes here).
# Queries live in dashboards/queries.yml (lnk_*, imp_*), and some panels reuse the Fabric / Web / Pipeline ones.
#   Link failures   /s/netops/app/dashboards#/view/netops-links
#   Fault impact    /s/netops/app/dashboards#/view/netops-impact

resource "elasticstack_kibana_dashboard" "links" {
  space_id     = elasticstack_kibana_space.netops.space_id
  dashboard_id = "netops-links"
  title        = "NetOps · Link failures"
  description  = "Fabric links: which went down, both ends (LLDP), when and for how long, flaps, routes withdrawn, traffic moving to the surviving links (gNMI)"
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
  panels = [
    {
      type = "markdown"
      grid = {
        x = 0
        y = 0
        w = 48
        h = 3
      }
      config_json = jsonencode({
        content = "**Link failures**: port up/down events and LLDP from the gNMI state log (`logs-gnmi.state.otel-*`), counters from `metrics-gnmi.otel-*`. Each failed link shows as two rows, one per end; *far end* is the LLDP neighbour. Tiles marked *now* look at the last 2 minutes, everything else follows the time picker. Also: [Fabric health](/s/netops/app/dashboards#/view/netops-fabric) · [Link failures](/s/netops/app/dashboards#/view/netops-links) · [Fault impact](/s/netops/app/dashboards#/view/netops-impact) · [Web app](/s/netops/app/dashboards#/view/netops-web)"
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 3
        w = 12
        h = 6
      }
      config_json = jsonencode({
        type        = "metric"
        title       = "Ports down now"
        data_source = local.esql_source.lnk_down_now
        metrics = [
          {
            type   = "primary"
            column = "ports_down"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 12
        y = 3
        w = 12
        h = 6
      }
      config_json = jsonencode({
        type        = "metric"
        title       = "Port-down events"
        data_source = local.esql_source.lnk_down_events
        metrics = [
          {
            type   = "primary"
            column = "port_down_events"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 24
        y = 3
        w = 12
        h = 6
      }
      config_json = jsonencode({
        type        = "metric"
        title       = "Ports that flapped (carrier transitions)"
        data_source = local.esql_source.lnk_flapping
        metrics = [
          {
            type   = "primary"
            column = "ports_flapped"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 36
        y = 3
        w = 12
        h = 6
      }
      config_json = jsonencode({
        type        = "metric"
        title       = "Routes withdrawn"
        data_source = local.esql_source.lnk_withdrawn
        metrics = [
          {
            type   = "primary"
            column = "routes_withdrawn"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 9
        w = 24
        h = 12
      }
      config_json = jsonencode({
        type  = "xy"
        title = "Port events (DOWN / UP)"
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
              text    = "events"
              visible = true
            }
          }
        }
        layers = [
          {
            type        = "bar_stacked"
            data_source = local.esql_source.lnk_events_ts
            x = {
              column = "time"
            }
            y = [
              {
                column = "events"
              },
            ]
            breakdown_by = {
              column = "event"
            }
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 24
        y = 9
        w = 24
        h = 12
      }
      config_json = jsonencode({
        type  = "xy"
        title = "Ports down"
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
              text    = "ports"
              visible = true
            }
          }
        }
        layers = [
          {
            type        = "line"
            data_source = local.esql_source.lnk_ports_down_ts
            x = {
              column = "time"
            }
            y = [
              {
                column = "ports_down"
              },
            ]
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 21
        w = 48
        h = 12
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "Failed links (both ends; down_s = how long it was, or has been, down)"
        data_source = local.esql_source.lnk_failures
        rows = [
          {
            column = "device"
          },
          {
            column = "interface"
          },
          {
            column = "far_end"
          },
          {
            column = "state_now"
          },
          {
            column = "downs"
          },
          {
            column = "first_down"
          },
          {
            column = "last_up"
          },
          {
            column = "down_s"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 33
        w = 48
        h = 13
      }
      config_json = jsonencode({
        type  = "xy"
        title = "Traffic out per port, ports above 0.5 Mbps (traffic moving to the surviving links)"
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
              text    = "Mbps"
              visible = true
            }
          }
        }
        layers = [
          {
            type        = "line"
            data_source = local.esql_source.lnk_traffic
            x = {
              column = "time"
            }
            y = [
              {
                column = "mbps"
              },
            ]
            breakdown_by = {
              column = "port"
            }
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 46
        w = 24
        h = 12
      }
      config_json = jsonencode({
        type  = "xy"
        title = "Routes withdrawn per switch"
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
              text    = "routes"
              visible = true
            }
          }
        }
        layers = [
          {
            type        = "bar_stacked"
            data_source = local.esql_source.lnk_routes_withdrawn
            x = {
              column = "time"
            }
            y = [
              {
                column = "withdrawn"
              },
            ]
            breakdown_by = {
              column = "host.name"
            }
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 24
        y = 46
        w = 24
        h = 12
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "Errors, discards and flaps"
        data_source = local.esql_source.fab_errors
        rows = [
          {
            column = "device"
          },
          {
            column = "interface"
          },
          {
            column = "in_err"
          },
          {
            column = "out_err"
          },
          {
            column = "in_disc"
          },
          {
            column = "out_disc"
          },
          {
            column = "flaps"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 58
        w = 24
        h = 14
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "Port and LLDP events (newest first)"
        data_source = local.esql_source.lnk_event_log
        rows = [
          {
            column = "@timestamp"
          },
          {
            column = "host.name"
          },
          {
            column = "interface_name"
          },
          {
            column = "event"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 24
        y = 58
        w = 24
        h = 14
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "BGP session changes (newest first)"
        data_source = local.esql_source.lnk_bgp_changes
        rows = [
          {
            column = "@timestamp"
          },
          {
            column = "host.name"
          },
          {
            column = "network-instance_name"
          },
          {
            column = "neighbor_neighbor-address"
          },
          {
            column = "state.session_state"
          },
        ]
      })
    },
  ]
}

resource "elasticstack_kibana_dashboard" "impact" {
  space_id     = elasticstack_kibana_space.netops.space_id
  dashboard_id = "netops-impact"
  title        = "NetOps · Fault impact"
  description  = "One timeline across the layers for any fault: port, BGP, route and EVPN changes, traffic, web requests, latency and errors, deploys"
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
  panels = [
    {
      type = "markdown"
      grid = {
        x = 0
        y = 0
        w = 48
        h = 3
      }
      config_json = jsonencode({
        content = "**Fault impact**: every layer on one time axis, so the first symptom and what followed line up. Set the time picker to the fault window. Network from gNMI, app from the web pods' traces, deploys from `logs-netops.changes`. Also: [Fabric health](/s/netops/app/dashboards#/view/netops-fabric) · [Link failures](/s/netops/app/dashboards#/view/netops-links) · [Fault impact](/s/netops/app/dashboards#/view/netops-impact) · [Web app](/s/netops/app/dashboards#/view/netops-web)"
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 3
        w = 12
        h = 6
      }
      config_json = jsonencode({
        type        = "metric"
        title       = "Ports down now"
        data_source = local.esql_source.lnk_down_now
        metrics = [
          {
            type   = "primary"
            column = "ports_down"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 12
        y = 3
        w = 12
        h = 6
      }
      config_json = jsonencode({
        type        = "metric"
        title       = "BGP sessions not established now"
        data_source = local.esql_source.imp_bgp_down_now
        metrics = [
          {
            type   = "primary"
            column = "bgp_not_established"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 24
        y = 3
        w = 12
        h = 6
      }
      config_json = jsonencode({
        type        = "metric"
        title       = "Route changes (last 5 min)"
        data_source = local.esql_source.imp_route_changes_5m
        metrics = [
          {
            type   = "primary"
            column = "route_changes_5m"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 36
        y = 3
        w = 12
        h = 6
      }
      config_json = jsonencode({
        type        = "metric"
        title       = "Web 5xx error rate (%)"
        data_source = local.esql_source.web_err
        metrics = [
          {
            type   = "primary"
            column = "error_pct"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 9
        w = 48
        h = 11
      }
      config_json = jsonencode({
        type  = "xy"
        title = "Network state changes by type (state log)"
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
              text    = "events"
              visible = true
            }
          }
        }
        layers = [
          {
            type        = "bar_stacked"
            data_source = local.esql_source.imp_events_ts
            x = {
              column = "time"
            }
            y = [
              {
                column = "events"
              },
            ]
            breakdown_by = {
              column = "event"
            }
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 20
        w = 24
        h = 10
      }
      config_json = jsonencode({
        type  = "xy"
        title = "Ports down"
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
              text    = "ports"
              visible = true
            }
          }
        }
        layers = [
          {
            type        = "line"
            data_source = local.esql_source.lnk_ports_down_ts
            x = {
              column = "time"
            }
            y = [
              {
                column = "ports_down"
              },
            ]
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 24
        y = 20
        w = 24
        h = 10
      }
      config_json = jsonencode({
        type  = "xy"
        title = "BGP sessions not established"
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
              text    = "sessions"
              visible = true
            }
          }
        }
        layers = [
          {
            type        = "line"
            data_source = local.esql_source.imp_bgp_down_ts
            x = {
              column = "time"
            }
            y = [
              {
                column = "sessions_not_established"
              },
            ]
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 30
        w = 24
        h = 11
      }
      config_json = jsonencode({
        type  = "xy"
        title = "Route changes per switch"
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
              text    = "routes"
              visible = true
            }
          }
        }
        layers = [
          {
            type        = "line"
            data_source = local.esql_source.imp_route_changes_ts
            x = {
              column = "time"
            }
            y = [
              {
                column = "route_changes"
              },
            ]
            breakdown_by = {
              column = "host.name"
            }
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 24
        y = 30
        w = 24
        h = 11
      }
      config_json = jsonencode({
        type  = "xy"
        title = "Traffic in by switch (Mbps)"
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
              text    = "Mbps"
              visible = true
            }
          }
        }
        layers = [
          {
            type        = "area_stacked"
            data_source = local.esql_source.fab_traffic_by_device
            x = {
              column = "time"
            }
            y = [
              {
                column = "mbps"
              },
            ]
            breakdown_by = {
              column = "host.name"
            }
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 41
        w = 24
        h = 11
      }
      config_json = jsonencode({
        type  = "xy"
        title = "Web requests by Kubernetes node"
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
              text    = "requests"
              visible = true
            }
          }
        }
        layers = [
          {
            type        = "bar_stacked"
            data_source = local.esql_source.imp_web_rpm_ts
            x = {
              column = "time"
            }
            y = [
              {
                column = "requests"
              },
            ]
            breakdown_by = {
              column = "k8s.node.name"
            }
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 24
        y = 41
        w = 24
        h = 11
      }
      config_json = jsonencode({
        type  = "xy"
        title = "Web p95 latency (ms) and 5xx errors"
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
              text    = "ms / errors"
              visible = true
            }
          }
        }
        layers = [
          {
            type        = "line"
            data_source = local.esql_source.imp_web_ts
            x = {
              column = "time"
            }
            y = [
              {
                column = "p95_ms"
              },
              {
                column = "errors_5xx"
              },
            ]
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 52
        w = 48
        h = 14
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "What changed: routes, BGP, ports, VTEPs, MACs (newest first; op=delete is a withdraw / loss)"
        data_source = local.esql_source.fab_state_changes
        rows = [
          {
            column = "@timestamp"
          },
          {
            column = "host.name"
          },
          {
            column = "subscription-name"
          },
          {
            column = "op"
          },
          {
            column = "vrf"
          },
          {
            column = "object"
          },
          {
            column = "new_value"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 66
        w = 48
        h = 10
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "Deploys (GitOps change events)"
        data_source = local.esql_source.pipe_changes
        rows = [
          {
            column = "@timestamp"
          },
          {
            column = "git.message"
          },
          {
            column = "git.author"
          },
          {
            column = "event.outcome"
          },
          {
            column = "netops.changed_devices"
          },
          {
            column = "git.sha"
          },
        ]
      })
    },
  ]
}
