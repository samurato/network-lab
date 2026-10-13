# Chaos command center dashboard (Chaos lab space). Indices, space and key: chaos.tf. Queries: chaos_* in
# dashboards/queries.yml.   /s/chaos/app/dashboards#/view/chaos-command-center

resource "elasticstack_kibana_dashboard" "chaos" {
  space_id     = elasticstack_kibana_space.chaos.space_id
  dashboard_id = "chaos-command-center"
  title        = "Chaos · Command center"
  description  = "chaos-lab runs: the fault in progress, every run's outcome and recovery, and whether each expected signal reached Elastic (the detection scorecard)"
  time_range = {
    from = "now-7d"
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
        content = "**Chaos command center**: what chaos-lab broke, when, whether the lab recovered, and whether each expected signal reached Elastic and how fast (`logs-chaos.*`). This space is the answer key: agents get no access to it. Runs start from the lab host (`make run EXP=...` in chaos-lab); `make stop` there undoes every fault. To see a run's symptoms, open [Fault impact](/s/netops/app/dashboards#/view/netops-impact) or [Link failures](/s/netops/app/dashboards#/view/netops-links) in the NetOps space with the run's time window."
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
        title       = "Faults active now"
        data_source = local.esql_source.chaos_active
        metrics = [
          {
            type   = "primary"
            column = "active_faults"
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
        title       = "Runs (time picker)"
        data_source = local.esql_source.chaos_runs_kpi
        metrics = [
          {
            type   = "primary"
            column = "runs"
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
        title       = "Expected signals that reached Elastic (%)"
        data_source = local.esql_source.chaos_detect_pct
        metrics = [
          {
            type   = "primary"
            column = "detected_pct"
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
        title       = "Median time to detect (s)"
        data_source = local.esql_source.chaos_ttd
        metrics = [
          {
            type   = "primary"
            column = "median_ttd_s"
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
        h = 6
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "Fault in progress"
        data_source = local.esql_source.chaos_now
        rows = [
          {
            column = "started"
          },
          {
            column = "experiment"
          },
          {
            column = "title"
          },
          {
            column = "fault"
          },
          {
            column = "targets"
          },
          {
            column = "injected"
          },
          {
            column = "hold_s"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 15
        w = 48
        h = 14
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "Runs (newest first; signals = expected signals seen in Elastic)"
        data_source = local.esql_source.chaos_runs
        rows = [
          {
            column = "started"
          },
          {
            column = "experiment"
          },
          {
            column = "title"
          },
          {
            column = "status"
          },
          {
            column = "recovered"
          },
          {
            column = "recovery_s"
          },
          {
            column = "signals"
          },
          {
            column = "ended"
          },
          {
            column = "run_id"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 29
        w = 24
        h = 11
      }
      config_json = jsonencode({
        type  = "xy"
        title = "Chaos timeline (runs, injections, rollbacks, traffic)"
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
            data_source = local.esql_source.chaos_events_ts
            x = {
              column = "time"
            }
            y = [
              {
                column = "events"
              },
            ]
            breakdown_by = {
              column = "event.action"
            }
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 24
        y = 29
        w = 24
        h = 11
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "Coverage per experiment (latest run)"
        data_source = local.esql_source.chaos_coverage
        rows = [
          {
            column = "experiment"
          },
          {
            column = "layer"
          },
          {
            column = "coverage_pct"
          },
          {
            column = "detected"
          },
          {
            column = "total"
          },
          {
            column = "runs"
          },
          {
            column = "last_run"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 40
        w = 24
        h = 13
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "Observability gaps: expected signals that never reached Elastic"
        data_source = local.esql_source.chaos_gaps
        rows = [
          {
            column = "experiment"
          },
          {
            column = "label"
          },
          {
            column = "missed"
          },
          {
            column = "last_missed"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 24
        y = 40
        w = 24
        h = 13
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "Time to detect per signal (s)"
        data_source = local.esql_source.chaos_ttd_by_signal
        rows = [
          {
            column = "experiment"
          },
          {
            column = "label"
          },
          {
            column = "runs"
          },
          {
            column = "avg_ttd_s"
          },
          {
            column = "max_ttd_s"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 0
        y = 53
        w = 24
        h = 14
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "Experiment catalogue"
        data_source = local.esql_source.chaos_catalogue
        rows = [
          {
            column = "experiment"
          },
          {
            column = "layer"
          },
          {
            column = "title"
          },
          {
            column = "random"
          },
          {
            column = "blast_radius"
          },
          {
            column = "signals"
          },
        ]
      })
    },
    {
      type = "vis"
      grid = {
        x = 24
        y = 53
        w = 24
        h = 14
      }
      config_json = jsonencode({
        type        = "data_table"
        title       = "Chaos event log (newest first)"
        data_source = local.esql_source.chaos_event_log
        rows = [
          {
            column = "@timestamp"
          },
          {
            column = "event.action"
          },
          {
            column = "experiment"
          },
          {
            column = "what"
          },
          {
            column = "message"
          },
        ]
      })
    },
  ]
}
