# Chaos lab in Elastic: where chaos-lab (chaos-lab/ in this repo) records its runs, and the Kibana space with
# its command center dashboard.
#
# chaos-lab writes with the lab key (ELASTIC_API_KEY): its `logs-*-*` create_doc privilege covers these data
# streams. Everything is append-only (the key cannot update a document), so a run is a "started" document and
# a final one, a re-score adds a new scorecard, and the dashboard takes the latest per run (INLINE STATS).
#
#   logs-chaos.events-default       timeline: run.start, fault.inject, fault.rollback, run.end, traffic.*
#   logs-chaos.runs-default         run snapshots: status running -> completed / deviated / stopped ...
#   logs-chaos.signals-default      the detection scorecard, one document per expected signal per scoring
#   logs-chaos.experiments-default  the catalogue, re-sent on every run
#
# These are the ANSWER KEY for testing an agent (which fault, where, when). The lab key can write them but not
# read them: its read patterns (security.tf) match none of logs-chaos.*. Give an agent read access to a
# narrower or equal set and it never sees the answers. Do not widen the lab key's read to `logs-*`.
# The command center lives in its own Kibana space for the same reason.
locals {
  chaos_keyword = {
    type = "keyword"
  }
  chaos_common_fields = {
    "@timestamp" = {
      type = "date"
    }
    run_id     = local.chaos_keyword
    experiment = local.chaos_keyword
    title      = local.chaos_keyword
    fault      = local.chaos_keyword
    layer      = local.chaos_keyword
  }
  chaos_streams = {
    events = {
      retention   = "90d"
      description = "chaos-lab timeline: runs, injections, rollbacks, traffic"
      fields = {
        event = {
          properties = {
            action = local.chaos_keyword
          }
        }
        what    = local.chaos_keyword
        targets = local.chaos_keyword
        message = {
          type = "text"
        }
      }
    }
    runs = {
      retention   = "365d"
      description = "chaos-lab run snapshots (latest per run_id is current)"
      fields = {
        status = local.chaos_keyword
        started = {
          type = "date"
        }
        ended = {
          type = "date"
        }
        targets  = local.chaos_keyword
        injected = local.chaos_keyword
        expected = {
          type = "text"
        }
        hold_s = {
          type = "integer"
        }
        recovered = {
          type = "boolean"
        }
        recovery_s = {
          type = "float"
        }
        detected = {
          type = "integer"
        }
        total = {
          type = "integer"
        }
        detection_pct = {
          type = "float"
        }
      }
    }
    signals = {
      retention   = "365d"
      description = "chaos-lab detection scorecard (latest scored_at per run_id is current)"
      fields = {
        started = {
          type = "date"
        }
        scored_at = {
          type = "date"
        }
        signal = local.chaos_keyword
        label  = local.chaos_keyword
        detected = {
          type = "boolean"
        }
        ttd_s = {
          type = "float"
        }
        first_seen = {
          type = "date"
        }
      }
    }
    experiments = {
      retention   = "365d"
      description = "chaos-lab experiment catalogue (latest per experiment is current)"
      fields = {
        random = {
          type = "boolean"
        }
        blast_radius = {
          type = "integer"
        }
        signals = {
          type = "integer"
        }
        expected = {
          type = "text"
        }
      }
    }
  }
}

resource "elasticstack_elasticsearch_index_template" "chaos" {
  for_each = local.chaos_streams

  name              = "logs-chaos.${each.key}"
  index_patterns    = ["logs-chaos.${each.key}-*"]
  priority          = 500 # above the built-in logs-*-* template
  allow_auto_create = true

  data_stream {}

  template {
    mappings = jsonencode({
      dynamic    = false
      properties = merge(local.chaos_common_fields, each.value.fields)
    })
    lifecycle {
      data_retention = each.value.retention
    }
  }

  metadata = jsonencode({
    description = "${each.value.description} (answer key: the lab key can write but not read it)"
    managed_by  = "terraform: samurato/network-lab elastic/terraform"
  })
}

# ---- Kibana: its own space, so the answer key never sits next to the agent's dashboards
resource "elasticstack_kibana_space" "chaos" {
  space_id    = "chaos"
  name        = "Chaos lab"
  description = "chaos-lab runs, injections and detection scorecards (the answer key: keep agents out)"
}

locals {
  chaos_data_views = {
    chaos-events = {
      name  = "Chaos timeline"
      title = "logs-chaos.events-*"
    }
    chaos-runs = {
      name  = "Chaos runs"
      title = "logs-chaos.runs-*"
    }
    chaos-signals = {
      name  = "Chaos detection signals"
      title = "logs-chaos.signals-*"
    }
  }
}

resource "elasticstack_kibana_data_view" "chaos" {
  for_each = local.chaos_data_views

  space_id = elasticstack_kibana_space.chaos.space_id
  data_view = {
    id              = each.key
    name            = each.value.name
    title           = each.value.title
    time_field_name = "@timestamp"
  }
  depends_on = [elasticstack_elasticsearch_index_template.chaos]
}
