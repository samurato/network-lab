# Chaos lab in Elastic: where chaos-lab (chaos-lab/ in this repo) records its runs, and the Kibana space with
# its command center dashboard.
#
# These indices are the ANSWER KEY for testing an agent (which fault, where, when), so they are kept apart:
#   - names chaos-* match none of the lab key's patterns (security.tf), so the lab key, and an agent given the
#     same kind of key, cannot read them;
#   - their own Kibana space (chaos), separate from the netops space the agent's dashboards live in.
# Give an agent a key without chaos-* and it never sees the answers.
#
# chaos-lab writes with its own key (ELASTIC_CHAOS_API_KEY in automation/elastic.env): write chaos-*, read the
# telemetry its scorecard checks. Like the lab key, it is created once in Kibana from the role descriptor below:
#   automation/elastic chaos-role
locals {
  chaos_key_role_descriptors = {
    chaos_lab = {
      cluster = ["monitor"]
      indices = [
        {
          names      = ["chaos-*"]
          privileges = ["auto_configure", "create_doc", "index", "read", "view_index_metadata"]
        },
        {
          names      = ["metrics-gnmi.otel-*", "logs-gnmi.state.otel-*", "traces-*.otel-*"]
          privileges = ["read", "view_index_metadata"]
        },
      ]
    }
  }
  chaos_keyword = {
    type = "keyword"
  }
  chaos_run_fields = {
    run_id     = local.chaos_keyword
    experiment = local.chaos_keyword
    title = {
      type = "keyword"
    }
    fault  = local.chaos_keyword
    layer  = local.chaos_keyword
    status = local.chaos_keyword
  }
}

output "chaos_api_key_role_descriptors" {
  description = "Role descriptor for the chaos-lab API key (create it in Kibana -> API keys)"
  value       = jsonencode(local.chaos_key_role_descriptors)
}

# ---- timeline: run start/end, every injection and rollback, traffic start/stop (append-only)
resource "elasticstack_elasticsearch_index_template" "chaos_events" {
  name              = "chaos-events"
  index_patterns    = ["chaos-events*"]
  priority          = 500
  allow_auto_create = true

  data_stream {}

  template {
    mappings = jsonencode({
      properties = merge(local.chaos_run_fields, {
        "@timestamp" = {
          type = "date"
        }
        event = {
          properties = {
            action = local.chaos_keyword
          }
        }
        what = {
          type = "keyword"
        }
        targets = local.chaos_keyword
        message = {
          type = "text"
        }
      })
    })
    lifecycle {
      data_retention = "90d"
    }
  }

  metadata = jsonencode({
    description = "chaos-lab timeline: runs, injections, rollbacks, traffic (answer key: not readable by the lab key)"
    managed_by  = "terraform: samurato/network-lab elastic/terraform"
  })
}

# ---- one document per run (updated as it progresses), one per expected signal, one per experiment
resource "elasticstack_elasticsearch_index" "chaos_runs" {
  name                = "chaos-runs"
  deletion_protection = false
  mappings = jsonencode({
    properties = merge(local.chaos_run_fields, {
      "@timestamp" = {
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
    })
  })
}

resource "elasticstack_elasticsearch_index" "chaos_signals" {
  name                = "chaos-signals"
  deletion_protection = false
  mappings = jsonencode({
    properties = merge(local.chaos_run_fields, {
      "@timestamp" = {
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
    })
  })
}

resource "elasticstack_elasticsearch_index" "chaos_experiments" {
  name                = "chaos-experiments"
  deletion_protection = false
  mappings = jsonencode({
    properties = {
      experiment = local.chaos_keyword
      title      = local.chaos_keyword
      layer      = local.chaos_keyword
      fault      = local.chaos_keyword
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
      title = "chaos-events"
    }
    chaos-runs = {
      name  = "Chaos runs"
      title = "chaos-runs"
    }
    chaos-signals = {
      name  = "Chaos detection signals"
      title = "chaos-signals"
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
  depends_on = [
    elasticstack_elasticsearch_index_template.chaos_events,
    elasticstack_elasticsearch_index.chaos_runs,
    elasticstack_elasticsearch_index.chaos_signals,
  ]
}
