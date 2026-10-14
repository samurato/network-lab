# The lab API key's privileges, as code.  Used by the collector (write telemetry), CI change events (write)
# and automation/verify.sh (read the lab's own data back); it cannot manage, delete or read anything else.
#
# Elasticsearch does not let an API key create another API key with privileges ("derived keys" must be
# empty), and on Serverless people sign in through Elastic Cloud, so Terraform cannot mint this key with the
# admin key.  Create it once in Kibana -> API keys with this role descriptor:
#   automation/elastic role    (prints it; paste into "Control security privileges")
# then put the encoded key in automation/elastic.env as ELASTIC_API_KEY.  Steps in docs/elastic.md.
locals {
  lab_key_role_descriptors = {
    netops_lab = {
      cluster = ["monitor"]
      indices = [
        {
          names      = ["logs-*-*", "metrics-*-*", "traces-*-*"]
          privileges = ["auto_configure", "create_doc"]
        },
        {
          # read stays narrow on purpose: chaos-lab's logs-chaos.* (the agent answer key, chaos.tf) must not match
          names      = ["metrics-gnmi.otel-*", "metrics-otelcol.otel-*", "metrics-k8s.*.otel-*", "traces-*.otel-*", "logs-*.otel-*", "logs-netops.*-*"]
          privileges = ["read", "view_index_metadata"]
        },
      ]
    }
  }
}

output "lab_api_key_role_descriptors" {
  description = "Role descriptor for the netops-lab API key (create it in Kibana -> API keys)"
  value       = jsonencode(local.lab_key_role_descriptors)
}
