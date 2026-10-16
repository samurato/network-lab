# Kibana: one space for the lab, with data views for what the lab sends.
resource "elasticstack_kibana_space" "netops" {
  space_id    = "netops"
  name        = "NetOps lab"
  description = "Dual-DC EVPN lab (samurato/network-lab): fabric, WAN, Kubernetes and app telemetry"
}

locals {
  data_views = {
    netops-gnmi = {
      name  = "Fabric telemetry (gnmic)"
      title = "metrics-gnmi.otel-*"
    }
    netops-state = {
      name  = "Fabric state changes (gnmic)"
      title = "logs-gnmi.state.otel-*"
    }
    netops-traces = {
      name  = "App traces"
      title = "traces-generic.otel-*"
    }
    netops-changes = {
      name  = "Change events (GitOps deploys)"
      title = "logs-netops.changes-*"
    }
    netops-bmp = {
      name  = "WAN BGP (BMP from wan1, wan2)"
      title = "logs-bgp.bmp.otel-*"
    }
    netops-k8s-metrics = {
      name  = "Kubernetes metrics"
      title = "metrics-k8s.*.otel-*"
    }
    netops-k8s-logs = {
      name  = "Kubernetes events and container logs"
      title = "logs-k8s.*.otel-*"
    }
    netops-drift = {
      name  = "Drift checks"
      title = "logs-netops.drift-*"
    }
    netops-otelcol = {
      name  = "Lab collector health"
      title = "metrics-otelcol.otel-*"
    }
  }
}

resource "elasticstack_kibana_data_view" "lab" {
  for_each = local.data_views

  space_id = elasticstack_kibana_space.netops.space_id
  data_view = {
    id              = each.key
    name            = each.value.name
    title           = each.value.title
    time_field_name = "@timestamp"
  }
}
