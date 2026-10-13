# Applications in namespace prod.
#
#   web        the colleague's app (chaos2cure/web), spread over DC1 and DC2, behind two VIPs:
#                192.0.2.10  public    -> Internet users / k6 via the WAN
#                10.99.0.10  internal  -> inside the DCs
#              externalTrafficPolicy Local: a node announces a VIP only while it runs a ready web pod,
#              so a DC with no healthy pods drops out of BGP and traffic shifts to the other DC.
#   db         reserved name for the future database (DB VIP 10.20.30.10): a Service with no backends yet
#   iperf3-*   one iperf3 server per DC, targets for east-west / DCI load tests
locals {
  otlp_endpoint = "http://172.20.20.250:4318" # lab otelcol (containerlab management network)
  web_vips = {
    public   = "192.0.2.10"
    internal = "10.99.0.10"
  }
}

resource "kubernetes_namespace_v1" "prod" {
  metadata {
    name = "prod"
  }
  depends_on = [helm_release.cilium]
}

# Shared counters for the web app (distinct visitors as a HyperLogLog per 5 s slot, request counts).
# Volatile on purpose: nothing is persisted, and the app falls back to per-pod counting if it is gone.
resource "kubernetes_deployment_v1" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace_v1.prod.metadata[0].name
    labels = {
      app = "redis"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "redis"
      }
    }
    template {
      metadata {
        labels = {
          app = "redis"
        }
      }
      spec {
        node_selector = {
          "topology.kubernetes.io/zone" = "dc1"
        }
        container {
          name  = "redis"
          image = "redis:8.10.2-alpine"
          args  = ["--save", "", "--appendonly", "no"]
          port {
            container_port = 6379
          }
          readiness_probe {
            tcp_socket {
              port = 6379
            }
            period_seconds = 5
          }
          resources {
            requests = {
              cpu    = "20m"
              memory = "32Mi"
            }
            limits = {
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
  depends_on = [kubernetes_namespace_v1.prod]
}

resource "kubernetes_service_v1" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace_v1.prod.metadata[0].name
  }
  spec {
    selector = {
      app = "redis"
    }
    port {
      port        = 6379
      target_port = 6379
    }
  }
  depends_on = [kubernetes_deployment_v1.redis]
}

resource "kubernetes_deployment_v1" "web" {
  metadata {
    name      = "web"
    namespace = kubernetes_namespace_v1.prod.metadata[0].name
    labels = {
      app = "web"
    }
  }
  spec {
    replicas = 4
    selector {
      match_labels = {
        app = "web"
      }
    }
    template {
      metadata {
        labels = {
          app = "web"
        }
      }
      spec {
        affinity {
          node_affinity { # workload zones only: the WAN tie-breaker zone must not count as a spread domain
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = "topology.kubernetes.io/zone"
                  operator = "In"
                  values   = sort(tolist(local.zones))
                }
              }
            }
          }
        }
        # match_label_keys makes each constraint count only pods of the same ReplicaSet revision. Without it
        # the old pods (still counted during a rolling update) skew the result, and the scheduler never
        # rebalances afterwards: a roll left 3 pods in DC1 and 1 in DC2.
        topology_spread_constraint { # even split across the DCs
          max_skew           = 1
          topology_key       = "topology.kubernetes.io/zone"
          when_unsatisfiable = "DoNotSchedule"
          match_label_keys   = ["pod-template-hash"]
          label_selector {
            match_labels = {
              app = "web"
            }
          }
        }
        topology_spread_constraint { # and across nodes inside a DC: hard, or both pods of a DC land on one node
          max_skew           = 1
          topology_key       = "kubernetes.io/hostname"
          when_unsatisfiable = "DoNotSchedule"
          match_label_keys   = ["pod-template-hash"]
          label_selector {
            match_labels = {
              app = "web"
            }
          }
        }
        container {
          name              = "web"
          image             = "chaos2cure/web:3"
          image_pull_policy = "Never" # loaded into the nodes by nodes.tf
          port {
            name           = "http"
            container_port = 80
          }
          env {
            name  = "REDIS_URL" # visitors and request rate are shared by all pods through this
            value = "redis://redis.prod:6379"
          }
          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          env {
            name  = "OTEL_SERVICE_NAME"
            value = "web"
          }
          env {
            name  = "OTEL_EXPORTER_OTLP_PROTOCOL"
            value = "http/protobuf"
          }
          env {
            name  = "OTEL_EXPORTER_OTLP_ENDPOINT"
            value = local.otlp_endpoint
          }
          env {
            name = "K8S_NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }
          env {
            name  = "OTEL_RESOURCE_ATTRIBUTES"
            value = "k8s.node.name=$(K8S_NODE_NAME),k8s.namespace.name=prod"
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            period_seconds = 5
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            period_seconds    = 10
            failure_threshold = 6
          }
          resources {
            requests = {
              cpu    = "50m"
              memory = "96Mi"
            }
            limits = {
              memory = "384Mi"
            }
          }
        }
      }
    }
  }
  depends_on = [terraform_data.image, kubernetes_service_v1.redis]
}

resource "kubernetes_pod_disruption_budget_v1" "web" {
  metadata {
    name      = "web"
    namespace = kubernetes_namespace_v1.prod.metadata[0].name
  }
  spec {
    min_available = 2
    selector {
      match_labels = {
        app = "web"
      }
    }
  }
}

resource "kubernetes_service_v1" "web" {
  for_each = local.web_vips
  metadata {
    name      = "web-${each.key}"
    namespace = kubernetes_namespace_v1.prod.metadata[0].name
    labels = {
      "netops.lab/exposure" = each.key
    }
    annotations = {
      "lbipam.cilium.io/ips" = each.value
    }
  }
  spec {
    type                    = "LoadBalancer"
    external_traffic_policy = "Local"
    selector = {
      app = "web"
    }
    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }
  }
  wait_for_load_balancer = true
  depends_on             = [kubectl_manifest.lb_pool]
}

# Placeholder for the database: the name resolves today, the backend (DB VIP 10.20.30.10 on VLAN 130,
# DC2) gets attached when the database exists — no app or address changes then.
resource "kubernetes_service_v1" "db" {
  metadata {
    name      = "db"
    namespace = kubernetes_namespace_v1.prod.metadata[0].name
    annotations = {
      "netops.lab/reserved-backend" = "10.20.30.10:5432"
    }
  }
  spec {
    port {
      name = "postgres"
      port = 5432
    }
  }
}

# iperf3 servers, one per DC: `kubectl -n prod exec deploy/iperf3-dc1 -- iperf3 -c iperf3-dc2 -t 30`
resource "kubernetes_deployment_v1" "iperf3" {
  for_each = local.zones
  metadata {
    name      = "iperf3-${each.key}"
    namespace = kubernetes_namespace_v1.prod.metadata[0].name
    labels = {
      app = "iperf3-${each.key}"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "iperf3-${each.key}"
      }
    }
    template {
      metadata {
        labels = {
          app = "iperf3-${each.key}"
        }
      }
      spec {
        node_selector = {
          "topology.kubernetes.io/zone" = each.key
        }
        container {
          name    = "iperf3"
          image   = "nicolaka/netshoot:v0.15"
          command = ["iperf3", "-s"]
          port {
            container_port = 5201
          }
          resources {
            requests = {
              cpu = "10m"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "iperf3" {
  for_each = local.zones
  metadata {
    name      = "iperf3-${each.key}"
    namespace = kubernetes_namespace_v1.prod.metadata[0].name
  }
  spec {
    selector = {
      app = "iperf3-${each.key}"
    }
    port {
      port = 5201
    }
  }
  depends_on = [kubernetes_deployment_v1.iperf3]
}

output "web_vips" {
  value = {
    for k, s in kubernetes_service_v1.web : k => s.status[0].load_balancer[0].ingress[0].ip
  }
}
