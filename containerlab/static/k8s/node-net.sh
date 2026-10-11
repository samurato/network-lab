# k3s node entrypoint: address the fabric link and route the lab over it, then start k3s with the given args.
# NODE_LINK (10.10.40.1/31), NODE_GW (the leaf) and FABRIC_ROUTES come from the topology (network/kubernetes.yml).
set -eu
until ip link show eth1 >/dev/null 2>&1; do sleep 1; done      # containerlab plugs links after start
ip link set eth1 mtu 1500 up                                   # match the leaf's L3 port MTU
ip address replace "$NODE_LINK" dev eth1
for prefix in $FABRIC_ROUTES; do
  ip route replace "$prefix" via "$NODE_GW" dev eth1
done
# cgroup v2: the kubelet nests cgroups under the container's root cgroup, which must hold no processes.
# k3s only evacuates it when it is PID 1 (here it is this script), so do it first, as k3d's entrypoint does.
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  mkdir -p /sys/fs/cgroup/init
  xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || :
  sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers > /sys/fs/cgroup/cgroup.subtree_control
fi
# k3s exits on a failed join (e.g. the first server not up yet).  Retry here: the container must never
# exit, a restart would drop its containerlab link.
while true; do
  /bin/k3s "$@" && break
  echo "node-net: k3s exited ($?), retrying in 10s" >&2
  sleep 10
done
