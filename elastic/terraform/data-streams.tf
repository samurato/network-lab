# Data streams the lab writes.  The collector's elasticsearch exporter (OTel-native mapping) routes every
# signal to <type>-<data_stream.dataset>.otel-<namespace>; base.yml sets the dataset per source.
# Elasticsearch ships the templates for metrics-*.otel-* etc.; each lab dataset gets its own template that
# reuses the built-in one as-is (read live, so an Elastic upgrade carries through) and adds a retention.
locals {
  metrics_datasets = {
    gnmi = {
      retention   = "7d"
      description = "cEOS fabric telemetry from gnmic: interfaces, BGP, LLDP, OSPF, memory, MTU (net.* names)"
    }
    otelcol = {
      retention   = "3d"
      description = "the lab collector's own metrics: accepted, refused, queued, failed"
    }
    "k8s.kubelet" = {
      retention   = "7d"
      description = "Kubernetes node, pod and container CPU, memory, network, filesystem (kubelet_stats, in-cluster EDOT agent)"
    }
    "k8s.cluster" = {
      retention   = "7d"
      description = "Kubernetes cluster state: node conditions, desired vs ready replicas, pod phases, restarts (k8s_cluster)"
    }
  }
  logs_datasets = {
    "gnmi.state" = {
      retention   = "30d"
      description = "cEOS state changes from gnmic: routes (AFT), BGP, LLDP, oper-status, VTEPs, VNIs, MACs"
    }
    "bgp.bmp" = {
      retention   = "30d"
      description = "BGP from the WAN routers (wan1, wan2) over BMP: updates, withdraws, peer state (pmbmpd)"
    }
    "k8s.events" = {
      retention   = "30d"
      description = "Kubernetes events: scheduling, pulls, probes, kills, evictions (k8s_events, in-cluster EDOT)"
    }
    "k8s.container" = {
      retention   = "7d"
      description = "Kubernetes container logs (file_log on /var/log/pods, with pod / deployment / node metadata)"
    }
  }
}

data "elasticstack_elasticsearch_index_template" "otel_metrics" {
  name = "metrics-otel@template"
}

resource "elasticstack_elasticsearch_index_template" "metrics" {
  for_each = local.metrics_datasets

  name                               = "metrics-${each.key}.otel"
  index_patterns                     = ["metrics-${each.key}.otel-*"]
  priority                           = data.elasticstack_elasticsearch_index_template.otel_metrics.priority + 30
  composed_of                        = data.elasticstack_elasticsearch_index_template.otel_metrics.composed_of
  ignore_missing_component_templates = data.elasticstack_elasticsearch_index_template.otel_metrics.ignore_missing_component_templates
  allow_auto_create                  = true

  data_stream {}

  template {
    settings = data.elasticstack_elasticsearch_index_template.otel_metrics.template.settings
    mappings = data.elasticstack_elasticsearch_index_template.otel_metrics.template.mappings
    lifecycle {
      data_retention = each.value.retention
    }
  }

  metadata = jsonencode({
    description = each.value.description
    managed_by  = "terraform: samurato/network-lab elastic/terraform"
  })
}

data "elasticstack_elasticsearch_index_template" "otel_logs" {
  name = "logs-otel@template"
}

resource "elasticstack_elasticsearch_index_template" "logs" {
  for_each = local.logs_datasets

  name                               = "logs-${each.key}.otel"
  index_patterns                     = ["logs-${each.key}.otel-*"]
  priority                           = data.elasticstack_elasticsearch_index_template.otel_logs.priority + 30
  composed_of                        = data.elasticstack_elasticsearch_index_template.otel_logs.composed_of
  ignore_missing_component_templates = data.elasticstack_elasticsearch_index_template.otel_logs.ignore_missing_component_templates
  allow_auto_create                  = true

  data_stream {}

  template {
    settings = data.elasticstack_elasticsearch_index_template.otel_logs.template.settings
    mappings = data.elasticstack_elasticsearch_index_template.otel_logs.template.mappings
    lifecycle {
      data_retention = each.value.retention
    }
  }

  metadata = jsonencode({
    description = each.value.description
    managed_by  = "terraform: samurato/network-lab elastic/terraform"
  })
}
