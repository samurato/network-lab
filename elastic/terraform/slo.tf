# Service level objectives, native Kibana SLOs in the netops space (/s/netops/app/slos), one set per layer.
# Each SLO's tag names its layer; the Overview dashboard lists them all (ovr_slo, from the SLO summary index).
#
#   web         web-availability  requests that are not 5xx                       occurrences  99.5 %  7 days
#               web-latency       requests faster than 500 ms                      occurrences  99 %    7 days
#               web-serving       every minute serves at least 100 requests        timeslices   99 %    7 days
#   kubernetes  k8s-web-pods      every minute all desired web pods are available  timeslices   99 %    7 days
#               k8s-nodes-ready   every minute every node is Ready                 timeslices   99 %    7 days
#   network     net-bgp           every minute every BGP session is established    timeslices   99 %    7 days
#               net-switches      every minute all 14 switches stream telemetry    timeslices   99 %    7 days
#               net-ports         every minute no cabled fabric port is down       timeslices   99 %    7 days
#
# Counts follow the lab's intent (14 switches in network/, 4 web replicas in kubernetes/). Timeslice SLOs use
# 1-minute slices: telemetry samples every 30 s, so each slice holds at least two samples.
locals {
  web_traffic = "service.name : \"web\" and kind : \"Server\" and not http.user_agent : kube-probe*"

  slo_occurrences = {
    web-availability = {
      name        = "Web availability"
      description = "Share of web requests (kube-probe excluded) that are not 5xx"
      tag         = "web"
      good        = "http.status_code < 500"
      target      = 0.995
    }
    web-latency = {
      name        = "Web latency under 500 ms"
      description = "Share of web requests (kube-probe excluded) served in under 500 ms"
      tag         = "web"
      good        = "duration < 500000000"
      target      = 0.99
    }
  }

  slo_timeslices = {
    web-serving = {
      name        = "Web is serving traffic"
      description = "Minutes in which the web app served at least 100 requests (normal load is about 600 a minute)"
      tag         = "web"
      index       = "traces-generic.otel-*"
      filter      = local.web_traffic
      metrics = [
        {
          name        = "A"
          aggregation = "doc_count"
        },
      ]
      equation   = "A"
      comparator = "GTE"
      threshold  = 100
    }
    k8s-web-pods = {
      name        = "Web pods available"
      description = "Minutes in which every desired web replica is available"
      tag         = "kubernetes"
      index       = "metrics-k8s.cluster.otel-*"
      filter      = "k8s.deployment.name : \"web\" and k8s.namespace.name : \"prod\""
      metrics = [
        {
          name        = "A"
          aggregation = "min"
          field       = "k8s.deployment.available"
        },
        {
          name        = "B"
          aggregation = "max"
          field       = "k8s.deployment.desired"
        },
      ]
      equation   = "A / B"
      comparator = "GTE"
      threshold  = 1
    }
    k8s-nodes-ready = {
      name        = "Kubernetes nodes ready"
      description = "Minutes in which every Kubernetes node reports Ready"
      tag         = "kubernetes"
      index       = "metrics-k8s.cluster.otel-*"
      filter      = "k8s.node.condition_ready : *"
      metrics = [
        {
          name        = "A"
          aggregation = "min"
          field       = "k8s.node.condition_ready"
        },
      ]
      equation   = "A"
      comparator = "GTE"
      threshold  = 1
    }
    net-bgp = {
      name        = "BGP sessions established"
      description = "Minutes in which every BGP session on every switch (overlay, WAN, Kubernetes) is established"
      tag         = "network"
      index       = "metrics-gnmi.otel-*"
      filter      = "net.bgp.session_state : *"
      metrics = [
        {
          name        = "A"
          aggregation = "min"
          field       = "net.bgp.session_state"
        },
      ]
      equation   = "A"
      comparator = "GTE"
      threshold  = 6
    }
    net-switches = {
      name        = "Switches streaming telemetry"
      description = "Minutes in which all 14 switches send interface counters over gNMI"
      tag         = "network"
      index       = "metrics-gnmi.otel-*"
      filter      = "net.if.in_octets : *"
      metrics = [
        {
          name        = "A"
          aggregation = "cardinality"
          field       = "host.name"
        },
      ]
      equation   = "A"
      comparator = "GTE"
      threshold  = 14
    }
    net-ports = {
      name        = "Fabric ports up"
      description = "Minutes in which no cabled fabric port reports oper-status down"
      tag         = "network"
      index       = "metrics-gnmi.otel-*"
      filter      = "net.if.oper_status : 0"
      metrics = [
        {
          name        = "A"
          aggregation = "doc_count"
        },
      ]
      equation   = "A"
      comparator = "LTE"
      threshold  = 0
    }
  }
}

resource "elasticstack_kibana_slo" "occurrences" {
  for_each = local.slo_occurrences

  space_id         = elasticstack_kibana_space.netops.space_id
  slo_id           = "netops-${each.key}"
  name             = each.value.name
  description      = each.value.description
  tags             = [each.value.tag]
  budgeting_method = "occurrences"

  kql_custom_indicator {
    index           = "traces-generic.otel-*"
    timestamp_field = "@timestamp"
    filter          = local.web_traffic
    good            = each.value.good
    total           = ""
  }

  objective {
    target = each.value.target
  }

  time_window {
    duration = "7d"
    type     = "rolling"
  }
}

resource "elasticstack_kibana_slo" "timeslices" {
  for_each = local.slo_timeslices

  space_id         = elasticstack_kibana_space.netops.space_id
  slo_id           = "netops-${each.key}"
  name             = each.value.name
  description      = each.value.description
  tags             = [each.value.tag]
  budgeting_method = "timeslices"

  timeslice_metric_indicator {
    index           = each.value.index
    timestamp_field = "@timestamp"
    filter          = each.value.filter
    metric {
      equation   = each.value.equation
      comparator = each.value.comparator
      threshold  = each.value.threshold
      dynamic "metrics" {
        for_each = each.value.metrics
        content {
          name        = metrics.value.name
          aggregation = metrics.value.aggregation
          field       = try(metrics.value.field, null)
        }
      }
    }
  }

  objective {
    target           = 0.99
    timeslice_target = 0.99
    timeslice_window = "1m"
  }

  time_window {
    duration = "7d"
    type     = "rolling"
  }
}
