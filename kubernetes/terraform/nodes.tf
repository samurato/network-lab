# Per-node pod CIDRs from kubernetes/cluster.yml (DC1 10.11.x, DC2 10.21.x, WAN 10.31.x).
# k3s runs with allocate-node-cidrs=false, so nothing else assigns them; Cilium (ipam: kubernetes) waits
# for spec.podCIDR before a node gets pod networking.  spec.podCIDR is set-once: a change needs a redeploy.
resource "terraform_data" "pod_cidr" {
  for_each = local.nodes
  input    = each.value.pod_cidr

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = pathexpand(var.kubeconfig)
    }
    command = <<-EOT
      kubectl wait --for=create node/${each.key} --timeout=600s
      current=$(kubectl get node ${each.key} -o jsonpath='{.spec.podCIDR}')
      if [ -z "$current" ]; then
        kubectl patch node ${each.key} --type merge \
          -p '{"spec":{"podCIDR":"${each.value.pod_cidr}","podCIDRs":["${each.value.pod_cidr}"]}}'
      elif [ "$current" != "${each.value.pod_cidr}" ]; then
        echo "${each.key} already has pod CIDR $current (want ${each.value.pod_cidr}): redeploy the lab" >&2
        exit 1
      fi
    EOT
  }
}

# Lab-built images that exist only in the host's Docker (e.g. the web app): copy them into each workload
# node's containerd.  Re-runs when the image changes in Docker.
locals {
  local_images = ["chaos2cure/web:1"]
}

data "external" "image_id" {
  for_each = toset(local.local_images)
  program  = ["sh", "-c", "docker image inspect --format '{\"id\":\"{{.Id}}\"}' ${each.key}"]
}

resource "terraform_data" "image" {
  for_each = {
    for pair in setproduct(keys(local.workers), local.local_images) : "${pair[0]}/${pair[1]}" => {
      node  = pair[0]
      image = pair[1]
    }
  }
  input = data.external.image_id[each.value.image].result.id

  # A node's containerd only exists once its k3s is up: on a fresh deploy the later nodes are still joining.
  depends_on = [terraform_data.pod_cidr]

  provisioner "local-exec" {
    command = <<-EOT
      c=${local.nodes[each.value.node].container}
      sock=/run/k3s/containerd/containerd.sock
      i=0
      until docker exec $c test -S $sock; do
        i=$((i + 1)); [ $i -le 120 ] || { echo "$c: containerd never came up" >&2; exit 1; }
        sleep 5
      done
      docker save ${each.value.image} | docker exec -i $c ctr --address $sock -n k8s.io images import -
    EOT
  }
}
