# Everything inside the k3s cluster: pod CIDRs, Cilium (CNI + BGP + load balancers), apps, generators.
#
#   Input:  generated/kubernetes.yml  (kubernetes/cluster.yml with the fabric side resolved, by `make build`)
#   Run:    automation/k8s apply      (fetches the kubeconfig, keeps the state next to the running lab)
#
# The k3s nodes themselves are containerlab nodes (containerlab/netops.clab.yml): Terraform has no way
# to wire veth links into the cEOS fabric, so it starts where containerlab stops.

terraform {
  required_version = ">= 1.9"
  backend "local" {} # path set by automation/k8s: the state lives and dies with the lab
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.3"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    kubectl = { # CRs (Cilium BGP, IP pools): validated at apply, after Cilium made the CRDs
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}

variable "kubeconfig" {
  description = "kubeconfig for the lab cluster (written by automation/k8s kubeconfig)"
  type        = string
  default     = "~/.kube/netops.yaml"
}

locals {
  intent  = yamldecode(file("${path.module}/../../generated/kubernetes.yml"))
  cluster = local.intent.cluster
  nodes   = local.intent.nodes
  workers = { for name, n in local.nodes : name => n if n.workloads }
  zones   = toset([for n in values(local.workers) : n.zone])
}

provider "kubernetes" {
  config_path = pathexpand(var.kubeconfig)
}

provider "helm" {
  kubernetes = {
    config_path = pathexpand(var.kubeconfig)
  }
}

provider "kubectl" {
  config_path      = pathexpand(var.kubeconfig)
  load_config_file = true
}
