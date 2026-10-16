# API key privileges, as code.
#
# Elasticsearch does not let an API key create another API key with privileges ("derived keys" must be
# empty), and on Serverless people sign in through Elastic Cloud, so Terraform cannot mint these keys with the
# admin key.  Create each once in Kibana -> API keys, pasting its role descriptor into "Control security
# privileges" (steps in docs/elastic.md):
#   automation/elastic role       the lab key (ELASTIC_API_KEY): collector, CI change events, verify.sh
#   automation/elastic sre-role   the SRE agent's key: read-only, the lab's telemetry and knowledge base
#
# Both are allow-lists of the lab's own data streams, never `logs-*`: anything else in the project (other
# teams' data, the agent's own conversation traces) stays out of reach.
locals {
  # what the lab sends: the collector writes <type>-<dataset>.otel-<namespace>, CI writes logs-netops.*
  lab_write_streams = ["metrics-*.otel-*", "traces-*.otel-*", "logs-*.otel-*", "logs-netops.*-*"]

  lab_key_role_descriptors = {
    netops_lab = {
      cluster = ["monitor"]
      indices = [
        {
          names      = local.lab_write_streams
          privileges = ["auto_configure", "create_doc"]
        },
        {
          names      = ["metrics-gnmi.otel-*", "metrics-otelcol.otel-*", "metrics-k8s.*.otel-*", "traces-*.otel-*", "logs-*.otel-*", "logs-netops.*-*"]
          privileges = ["read", "view_index_metadata"]
        },
      ]
    }
  }

  # The SRE agent (Kibana Agent Builder) runs with its caller's privileges: call it with this key or a user
  # with this role, never as an admin.  traces-generic, not traces-*: traces-agent_builder holds the agent's
  # own conversations.
  sre_agent_role_descriptors = {
    sre_agent = {
      cluster = ["monitor"]
      indices = [
        {
          names = [
            "metrics-*.otel-*",
            "traces-generic.otel-*",
            "logs-gnmi.*.otel-*",
            "logs-bgp.*.otel-*",
            "logs-k8s.*.otel-*",
            "logs-netops.*-*",
            "kb-*",
          ]
          privileges = ["read", "view_index_metadata"]
        },
      ]
      applications = [
        {
          application = "kibana-.kibana"
          privileges = [
            "feature_agentBuilder.read",
            "feature_actions.read",
            "feature_discover_v2.read",
            "feature_dashboard_v2.read",
          ]
          resources = [
            "space:default",
            "space:${elasticstack_kibana_space.netops.space_id}",
          ]
        },
      ]
    }
  }
}

output "lab_api_key_role_descriptors" {
  description = "Role descriptor for the netops-lab API key (create it in Kibana -> API keys)"
  value       = jsonencode(local.lab_key_role_descriptors)
}

output "sre_agent_role_descriptors" {
  description = "Role descriptor for the SRE agent's API key (create it in Kibana -> API keys)"
  value       = jsonencode(local.sre_agent_role_descriptors)
}
