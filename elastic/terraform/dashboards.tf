# Dashboards in the netops Kibana space, as code.  Every chart is an ES|QL Lens panel; the queries live in
# dashboards/queries.yml (one place to read and test them: automation/elastic queries).  The dashboard map and
# the newer layer dashboards (Overview, Web, Kubernetes, Routing & WAN) are in dashboards-layers.tf.
#
# Panels use `config_json` in the Kibana Dashboards API shape ({type, title, data_source, ...}): provider 0.16's
# typed chart blocks send fields this Serverless Kibana rejects.  Kibana fills in every style default.
#   Network              /s/netops/app/dashboards#/view/netops-fabric
#   Telemetry pipeline   /s/netops/app/dashboards#/view/netops-pipeline
locals {
  esql_source = {
    for name, query in yamldecode(file("${path.module}/dashboards/queries.yml")) :
    name => {
      type  = "esql"
      query = trimspace(query)
    }
  }
}

resource "elasticstack_kibana_dashboard" "fabric" {
  space_id     = elasticstack_kibana_space.netops.space_id
  dashboard_id = "netops-fabric"
  title        = "NetOps · Network"
  description  = "cEOS fabric: switches reporting, BGP, ports, traffic, errors, LLDP, state changes (gNMI)"
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
        content = "**Network**: the 14 cEOS switches over gNMI (`metrics-gnmi.otel-*`, state changes in `logs-gnmi.state.otel-*`). Drill down: Link failures, Routing & WAN. ${local.times}\n\n${local.nav}"
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
        title       = "Switches reporting"
        data_source = local.esql_source.fab_switches
        metrics = [
          {
            type   = "primary"
            column = "switches"
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
        title       = "BGP sessions established"
        data_source = local.esql_source.fab_bgp
        metrics = [
          {
            type   = "primary"
            column = "established"
          },
          {
            type   = "secondary"
            column = "sessions"
            label  = "of sessions"
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
        title       = "Ports down"
        data_source = local.esql_source.fab_ports_down
        metrics = [
          {
            type   = "primary"
            column = "ports_down"
          },
          {
            type   = "secondary"
            column = "ports"
            label  = "cabled ports"
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
        title       = "Fabric traffic in (Mbps)"
        data_source = local.esql_source.fab_mbps
        metrics = [
          {
            type   = "primary"
            column = "fabric_mbps"
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
        h = 13
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
        x = 24
        y = 9
        w = 24
        h = 13
      }
      config_json = jsonencode({
        type  = "xy"
        title = "BGP prefixes received by switch"
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
              text    = "prefixes"
              visible = true
            }
          }
        }
        layers = [
          {
            type        = "line"
            data_source = local.esql_source.fab_bgp_prefixes
            x = {
              column = "time"
            }
            y = [
              {
                column = "prefixes"
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
        y = 22
        w = 24
        h = 10
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "BGP sessions not established"
        data_source = local.esql_source.fab_bgp_not_up
        rows = [
          {
            column = "device"
          },
          {
            column = "vrf"
          },
          {
            column = "peer"
          },
          {
            column = "fsm"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 24
        y = 22
        w = 24
        h = 10
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "Ports down"
        data_source = local.esql_source.fab_ports_down_tbl
        rows = [
          {
            column = "device"
          },
          {
            column = "interface"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 32
        w = 24
        h = 14
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "Busiest ports (last 5 min)"
        data_source = local.esql_source.fab_top_ports
        rows = [
          {
            column = "device"
          },
          {
            column = "interface"
          },
        ]
        metrics = [
          {
            column = "in_mbps"
          },
          {
            column = "out_mbps"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 24
        y = 32
        w = 24
        h = 14
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "Errors, discards and flaps (time picker)"
        data_source = local.esql_source.fab_errors
        rows = [
          {
            column = "device"
          },
          {
            column = "interface"
          },
        ]
        metrics = [
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
        y = 46
        w = 48
        h = 14
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "LLDP neighbours (actual cabling)"
        data_source = local.esql_source.fab_lldp
        rows = [
          {
            column = "device"
          },
          {
            column = "interface"
          },
          {
            column = "neighbour"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 60
        w = 48
        h = 16
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "State changes: routes, BGP, ports, VTEPs, MACs (newest first; op=delete is a withdraw / loss)"
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
  ]
}

resource "elasticstack_kibana_dashboard" "pipeline" {
  space_id     = elasticstack_kibana_space.netops.space_id
  dashboard_id = "netops-pipeline"
  title        = "NetOps · Telemetry pipeline"
  description  = "telemetry freshness, collector throughput and queue, GitOps change events"
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
  panels = concat([
    {
      type = "markdown"
      grid = {
        x = 0
        y = 0
        w = 48
        h = 3
      }
      config_json = jsonencode({
        content = "**Telemetry pipeline**: is the data fresh, is the collector and Kafka keeping up, what was deployed. ${local.times}\n\n${local.nav}"
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
        title       = "gNMI docs per minute"
        data_source = local.esql_source.pipe_docs_kpi
        metrics = [
          {
            type   = "primary"
            column = "docs_per_min"
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
        title       = "Switches silent > 60 s"
        data_source = local.esql_source.pipe_stale_kpi
        metrics = [
          {
            type   = "primary"
            column = "stale_switches"
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
        title       = "Collector export queue"
        data_source = local.esql_source.pipe_queue_kpi
        metrics = [
          {
            type   = "primary"
            column = "queue"
          },
          {
            type   = "secondary"
            column = "capacity"
            label  = "capacity"
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
        title       = "Deploys (24 h)"
        data_source = local.esql_source.pipe_changes_kpi
        metrics = [
          {
            type   = "primary"
            column = "deploys_24h"
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
        h = 13
      }
      config_json = jsonencode({
        type  = "xy"
        title = "gNMI docs by switch"
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
              text    = "docs"
              visible = true
            }
          }
        }
        layers = [
          {
            type        = "bar_stacked"
            data_source = local.esql_source.pipe_docs
            x = {
              column = "time"
            }
            y = [
              {
                column = "docs"
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
        y = 9
        w = 24
        h = 13
      }
      config_json = jsonencode({
        type  = "xy"
        title = "Collector sent to Elastic (per second)"
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
              text    = "per second"
              visible = true
            }
          }
        }
        layers = [
          {
            type        = "line"
            data_source = local.esql_source.pipe_sent
            x = {
              column = "time"
            }
            y = [
              {
                column = "metric_points_per_s"
              },
              {
                column = "spans_per_s"
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
        y = 22
        w = 24
        h = 12
      }
      config_json = jsonencode({
        type  = "xy"
        title = "Collector export queue"
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
              text    = "batches"
              visible = true
            }
          }
        }
        layers = [
          {
            type        = "line"
            data_source = local.esql_source.pipe_queue
            x = {
              column = "time"
            }
            y = [
              {
                column = "queue"
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
        y = 22
        w = 24
        h = 12
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "Last data per switch"
        data_source = local.esql_source.pipe_last_seen
        rows = [
          {
            column = "device"
          },
          {
            column = "last_seen"
          },
        ]
        metrics = [
          {
            column = "age_s"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 34
        w = 48
        h = 12
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "Change events (GitOps deploys)"
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
  ], local.layer_panels.pipeline_extra)
}
