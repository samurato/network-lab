# Kubernetes telemetry (docs/observability-roadmap.md Step 11): the EDOT Collector inside the cluster, sending OTLP
# to the lab gateway (otelcol, 172.20.20.250:4317) over each node's management interface, never across the fabric.
#
#   otel-agent    DaemonSet, one per node: kubelet stats (node, pod, container) and container logs, with k8s metadata
#   otel-cluster  Deployment, one replica: cluster state (node conditions, replicas, pod phases) and Kubernetes events
#
# In Elastic (templates: elastic/terraform/data-streams.tf):
#   metrics-k8s.kubelet.otel-default   metrics-k8s.cluster.otel-default
#   logs-k8s.container.otel-default    logs-k8s.events.otel-default
#
# Plain manifests, not the upstream Helm chart: its presets emit component names this EDOT version renamed
# (kubelet_stats, k8s_attributes, file_log, otlp_grpc). The image is the gateway's (generated/kubernetes.yml from
# automation/render.py), side-loaded into every node by nodes.tf.
locals {
  otel_namespace = "otel"
  otel_image     = local.intent.telemetry.collector_image

  otel_exporters = {
    otlp_grpc = {
      endpoint = local.intent.telemetry.gateway_otlp_grpc
      tls = {
        insecure = true
      }
      sending_queue = {
        enabled = true
      }
      retry_on_failure = {
        enabled = true
      }
    }
  }
  otel_common_processors = {
    memory_limiter = {
      check_interval         = "1s"
      limit_percentage       = 80
      spike_limit_percentage = 20
    }
    batch = {
      send_batch_size = 2000
      timeout         = "5s"
    }
  }
  otel_extensions = {
    health_check = {
      endpoint = "0.0.0.0:13133"
    }
  }

  # ---- per node: kubelet stats and container logs
  otel_agent_config = {
    receivers = {
      kubelet_stats = {
        collection_interval  = "30s"
        auth_type            = "serviceAccount"
        endpoint             = "https://$${env:K8S_NODE_IP}:10250"
        insecure_skip_verify = true
        metric_groups = [
          "node",
          "pod",
          "container",
        ]
      }
      file_log = {
        include = [
          "/var/log/pods/*/*/*.log",
        ]
        exclude = [
          "/var/log/pods/${local.otel_namespace}_*/*/*.log", # not our own logs: no feedback loop
        ]
        start_at          = "end"
        include_file_path = true
        include_file_name = false
        operators = [
          {
            type = "container" # CRI format; adds k8s.namespace.name, k8s.pod.name, k8s.container.name from the path
            id   = "container-parser"
          },
        ]
      }
    }
    processors = merge(local.otel_common_processors, {
      k8s_attributes = {
        auth_type   = "serviceAccount"
        passthrough = false
        filter = {
          node_from_env_var = "K8S_NODE_NAME"
        }
        extract = {
          metadata = [
            "k8s.namespace.name",
            "k8s.pod.name",
            "k8s.pod.uid",
            "k8s.node.name",
            "k8s.deployment.name",
            "k8s.daemonset.name",
            "k8s.statefulset.name",
            "k8s.container.name",
          ]
          labels = [
            {
              tag_name = "app"
              key      = "app"
              from     = "pod"
            },
          ]
        }
        pod_association = [
          {
            sources = [
              {
                from = "resource_attribute"
                name = "k8s.pod.uid"
              },
            ]
          },
          {
            sources = [
              {
                from = "resource_attribute"
                name = "k8s.pod.name"
              },
              {
                from = "resource_attribute"
                name = "k8s.namespace.name"
              },
            ]
          },
        ]
      }
      # data contract: host.name is the node, as it is the switch on the network telemetry
      "resource/node" = {
        attributes = [
          {
            key    = "host.name"
            value  = "$${env:K8S_NODE_NAME}"
            action = "upsert"
          },
          {
            key    = "k8s.node.name"
            value  = "$${env:K8S_NODE_NAME}"
            action = "insert"
          },
          {
            key    = "k8s.cluster.name"
            value  = local.cluster.name
            action = "upsert"
          },
        ]
      }
      "resource/kubelet" = {
        attributes = [
          {
            key    = "data_stream.dataset"
            value  = "k8s.kubelet"
            action = "upsert"
          },
        ]
      }
      "resource/container_logs" = {
        attributes = [
          {
            key    = "data_stream.dataset"
            value  = "k8s.container"
            action = "upsert"
          },
        ]
      }
    })
    exporters  = local.otel_exporters
    extensions = local.otel_extensions
    service = {
      extensions = [
        "health_check",
      ]
      pipelines = {
        metrics = {
          receivers = [
            "kubelet_stats",
          ]
          processors = [
            "memory_limiter",
            "k8s_attributes",
            "resource/node",
            "resource/kubelet",
            "batch",
          ]
          exporters = [
            "otlp_grpc",
          ]
        }
        logs = {
          receivers = [
            "file_log",
          ]
          processors = [
            "memory_limiter",
            "k8s_attributes",
            "resource/node",
            "resource/container_logs",
            "batch",
          ]
          exporters = [
            "otlp_grpc",
          ]
        }
      }
    }
  }

  # ---- once per cluster: cluster state and events
  otel_cluster_config = {
    receivers = {
      k8s_cluster = {
        collection_interval = "30s"
        auth_type           = "serviceAccount"
        node_conditions_to_report = [
          "Ready",
          "MemoryPressure",
          "DiskPressure",
          "PIDPressure",
        ]
        allocatable_types_to_report = [
          "cpu",
          "memory",
          "pods",
        ]
      }
      k8s_events = {
        auth_type = "serviceAccount"
      }
    }
    processors = merge(local.otel_common_processors, {
      "resource/cluster" = {
        attributes = [
          {
            key    = "k8s.cluster.name"
            value  = local.cluster.name
            action = "upsert"
          },
          {
            key    = "data_stream.dataset"
            value  = "k8s.cluster"
            action = "upsert"
          },
        ]
      }
      # data contract: an event's host.name is the node it happened on (the involved object's node), when it has one
      "transform/events_host" = {
        error_mode = "ignore"
        log_statements = [
          {
            context = "resource"
            statements = [
              "set(attributes[\"host.name\"], attributes[\"k8s.node.name\"]) where attributes[\"k8s.node.name\"] != nil",
            ]
          },
        ]
      }
      "resource/events" = {
        attributes = [
          {
            key    = "k8s.cluster.name"
            value  = local.cluster.name
            action = "upsert"
          },
          {
            key    = "data_stream.dataset"
            value  = "k8s.events"
            action = "upsert"
          },
        ]
      }
    })
    exporters  = local.otel_exporters
    extensions = local.otel_extensions
    service = {
      extensions = [
        "health_check",
      ]
      pipelines = {
        metrics = {
          receivers = [
            "k8s_cluster",
          ]
          processors = [
            "memory_limiter",
            "resource/cluster",
            "batch",
          ]
          exporters = [
            "otlp_grpc",
          ]
        }
        logs = {
          receivers = [
            "k8s_events",
          ]
          processors = [
            "memory_limiter",
            "transform/events_host",
            "resource/events",
            "batch",
          ]
          exporters = [
            "otlp_grpc",
          ]
        }
      }
    }
  }
}

resource "kubernetes_namespace_v1" "otel" {
  metadata {
    name = local.otel_namespace
  }
}

resource "kubernetes_service_account_v1" "otel" {
  metadata {
    name      = "otel-collector"
    namespace = kubernetes_namespace_v1.otel.metadata[0].name
  }
}

# Read-only: what kubelet_stats, k8s_attributes, k8s_cluster and k8s_events need, nothing more
resource "kubernetes_cluster_role_v1" "otel" {
  metadata {
    name = "otel-collector"
  }
  rule {
    api_groups = [""]
    resources = [
      "nodes",
      "nodes/stats",
      "nodes/proxy",
      "pods",
      "namespaces",
      "events",
      "services",
      "endpoints",
      "replicationcontrollers",
      "resourcequotas",
      "persistentvolumes",
      "persistentvolumeclaims",
    ]
    verbs = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources = [
      "replicasets",
      "deployments",
      "daemonsets",
      "statefulsets",
    ]
    verbs = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["batch"]
    resources = [
      "jobs",
      "cronjobs",
    ]
    verbs = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["autoscaling"]
    resources = [
      "horizontalpodautoscalers",
    ]
    verbs = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["events.k8s.io"]
    resources = [
      "events",
    ]
    verbs = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "otel" {
  metadata {
    name = "otel-collector"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.otel.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.otel.metadata[0].name
    namespace = kubernetes_namespace_v1.otel.metadata[0].name
  }
}

resource "kubernetes_config_map_v1" "otel" {
  for_each = {
    agent   = local.otel_agent_config
    cluster = local.otel_cluster_config
  }
  metadata {
    name      = "otel-${each.key}"
    namespace = kubernetes_namespace_v1.otel.metadata[0].name
  }
  data = {
    "config.yaml" = yamlencode(each.value)
  }
}

resource "kubernetes_daemon_set_v1" "otel_agent" {
  metadata {
    name      = "otel-agent"
    namespace = kubernetes_namespace_v1.otel.metadata[0].name
    labels = {
      app = "otel-agent"
    }
  }
  spec {
    selector {
      match_labels = {
        app = "otel-agent"
      }
    }
    template {
      metadata {
        labels = {
          app = "otel-agent"
        }
        annotations = { # a config change rolls the pods
          "netops.lab/config" = sha1(kubernetes_config_map_v1.otel["agent"].data["config.yaml"])
        }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.otel.metadata[0].name
        toleration { # every node, the WAN tie-breaker included
          operator = "Exists"
        }
        container {
          name              = "otel-agent"
          image             = local.otel_image
          image_pull_policy = "IfNotPresent" # side-loaded by nodes.tf
          args = [
            "--config",
            "/conf/config.yaml",
          ]
          env {
            name = "K8S_NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }
          env {
            name = "K8S_NODE_IP"
            value_from {
              field_ref {
                field_path = "status.hostIP"
              }
            }
          }
          security_context {
            run_as_user = 0 # reads /var/log/pods (root-owned)
          }
          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              memory = "512Mi"
            }
          }
          readiness_probe {
            http_get {
              path = "/"
              port = 13133
            }
            period_seconds = 10
          }
          volume_mount {
            name       = "config"
            mount_path = "/conf"
          }
          volume_mount {
            name       = "varlogpods"
            mount_path = "/var/log/pods"
            read_only  = true
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.otel["agent"].metadata[0].name
          }
        }
        volume {
          name = "varlogpods"
          host_path {
            path = "/var/log/pods"
          }
        }
      }
    }
  }
  depends_on = [
    terraform_data.image,
    kubernetes_cluster_role_binding_v1.otel,
  ]
}

resource "kubernetes_deployment_v1" "otel_cluster" {
  metadata {
    name      = "otel-cluster"
    namespace = kubernetes_namespace_v1.otel.metadata[0].name
    labels = {
      app = "otel-cluster"
    }
  }
  spec {
    replicas = 1 # one copy of cluster state and events, not one per node
    selector {
      match_labels = {
        app = "otel-cluster"
      }
    }
    template {
      metadata {
        labels = {
          app = "otel-cluster"
        }
        annotations = {
          "netops.lab/config" = sha1(kubernetes_config_map_v1.otel["cluster"].data["config.yaml"])
        }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.otel.metadata[0].name
        container {
          name              = "otel-cluster"
          image             = local.otel_image
          image_pull_policy = "IfNotPresent"
          args = [
            "--config",
            "/conf/config.yaml",
          ]
          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              memory = "512Mi"
            }
          }
          readiness_probe {
            http_get {
              path = "/"
              port = 13133
            }
            period_seconds = 10
          }
          volume_mount {
            name       = "config"
            mount_path = "/conf"
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.otel["cluster"].metadata[0].name
          }
        }
      }
    }
  }
  depends_on = [
    terraform_data.image,
    kubernetes_cluster_role_binding_v1.otel,
  ]
}
