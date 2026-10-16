#!/usr/bin/env bash
# Health checks for the dual-DC EVPN Gateway lab.
#   automation/verify.sh [--wait SECONDS]   # --wait: retry until everything passes or the deadline hits
set -uo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--wait" ]]; then
  deadline=$((SECONDS + ${2:-300}))
  until "$0" >/dev/null 2>&1; do
    ((SECONDS < deadline)) || { echo "not converged after ${2:-300}s:"; exec "$0"; }
    sleep 10
  done
  exec "$0"
fi
TOPO=containerlab/netops.clab.yml
EOS_USER=${EOS_USER:-admin}; EOS_PASSWORD=${EOS_PASSWORD:-admin}
fail=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=1; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$*"; }   # worth a look, but does not fail the run
SC=generated/intended/structured_configs
mgmt() { yq -r ".topology.nodes.\"$1\".\"mgmt-ipv4\"" "$TOPO"; }
eapi() {  # eapi <node> <cmd>... -> JSON result array
  local node=$1; shift
  local cmds; cmds=$(printf '%s\n' "$@" | jq -R . | jq -sc .)
  curl -sk -u "$EOS_USER:$EOS_PASSWORD" "https://$(mgmt "$node")/command-api" -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"runCmds\",\"params\":{\"version\":1,\"cmds\":$cmds,\"format\":\"json\"},\"id\":1}" \
    | jq -c '.result'
}

echo "== OSPF underlay (eAPI) =="
for n in $(yq -r '.topology.nodes | to_entries[] | select(.value.kind=="arista_ceos") | .key' "$TOPO"); do
  want=$(yq '[.ethernet_interfaces[] | select(.ospf_area != null)] | length' "$SC/$n.yml")
  full=$(eapi "$n" "show ip ospf neighbor" | jq '[.[0].vrfs.default.instList[]?.ospfNeighborEntries[]? | select(.adjacencyState=="full")] | length')
  [[ $want -gt 0 && ${full:-0} -eq $want ]] && ok "$n $full/$want adjacencies full" || bad "$n ${full:-0}/$want adjacencies full"
done

echo "== BGP (EVPN overlay, WAN eBGP) =="
for n in $(yq -r '.topology.nodes | to_entries[] | select(.value.kind=="arista_ceos") | .key' "$TOPO"); do
  r=$(eapi "$n" "show ip bgp summary" "show bgp evpn summary")
  read -r up total < <(jq -r '[.[] | .vrfs.default.peers // {} | .[] | .peerState]
                          | "\(map(select(.=="Established")) | length) \(length)"' <<<"$r" 2>/dev/null)
  [[ ${total:-0} -gt 0 && $up -eq $total ]] && ok "$n $up/$total sessions established" || bad "$n ${up:-0}/${total:-0} sessions established"
done

echo "== WAN routers (FRR) =="
for n in $(yq -r '.topology.nodes | to_entries[] | select(.value.labels.role=="wan") | .key' "$TOPO"); do
  read -r up total < <(docker exec "clab-netops-$n" vtysh -c 'show bgp ipv4 unicast summary json' 2>/dev/null \
    | jq -r '[(.ipv4Unicast // .).peers[] | .state] | "\(map(select(.=="Established")) | length) \(length)"')
  [[ ${total:-0} -gt 0 && $up -eq $total ]] && ok "$n $up/$total established" || bad "$n ${up:-0}/${total:-0} established"
done

echo "== Multi-site isolation (leaves see only local VTEPs) =="
for n in dc1-leaf1 dc2-leaf1; do
  pool=$([[ $n == dc1-* ]] && echo '^10\.1\.1\.' || echo '^10\.2\.1\.')
  vteps=$(eapi "$n" "show vxlan vtep" | jq -r '.[0].interfaces.Vxlan1.vteps[]?' 2>/dev/null | sort -u)
  foreign=$(grep -vE "$pool" <<<"$vteps" | grep -v '^$' || true)
  [[ -n "$vteps" && -z "$foreign" ]] && ok "$n VTEPs: $(paste -sd' ' <<<"$vteps")" \
    || bad "$n VTEPs: $(paste -sd' ' <<<"$vteps") ${foreign:+(foreign: $(paste -sd' ' <<<"$foreign"))}"
done

echo "== Data plane (host pings) =="
ping_check() { docker exec "clab-netops-$1" ping -c3 -W1 -i0.2 "$2" >/dev/null 2>&1 \
  && ok "$1 -> $2 ($3)" || bad "$1 -> $2 ($3)"; }
ping_check dc1-web1     10.10.10.12 "DC1 L2 VLAN110 leaf1->leaf2"
ping_check dc1-web1     10.10.20.13 "DC1 L3 PROD (symmetric IRB)"
ping_check dc2-db1      10.20.30.12 "DC2 L2 VLAN130"
ping_check dc1-web1     10.20.30.11 "inter-DC L3 via EVPN gateways"
ping_check dc2-db2      10.10.20.14 "inter-DC L3 DC2 -> DC1"
ping_check dc1-stretch1 10.15.0.12  "inter-DC L2 stretch VLAN150"

echo "== VRF PROD: Kubernetes nodes on the leaves, WAN handoff on the border gateways =="
for n in $(yq -r '.topology.nodes | to_entries[] | select(.value.kind=="arista_ceos") | .key' "$TOPO"); do
  want=$(yq '[.router_bgp.vrfs[]? | select(.name=="PROD") | .neighbors[]?] | length' "$SC/$n.yml")
  [[ $want -gt 0 ]] || continue
  up=$(eapi "$n" "show ip bgp summary vrf PROD" | jq '[.[0].vrfs.PROD.peers // {} | .[] | select(.peerState=="Established")] | length')
  [[ ${up:-0} -eq $want ]] && ok "$n $up/$want VRF PROD sessions" || bad "$n ${up:-0}/$want VRF PROD sessions"
done
for n in $(yq -r '.topology.nodes | to_entries[] | select(.value.labels.role=="wan") | .key' "$TOPO"); do
  read -r up total < <(docker exec "clab-netops-$n" vtysh -c 'show bgp vrf PROD ipv4 unicast summary json' 2>/dev/null \
    | jq -r '[(.ipv4Unicast // .).peers[] | .state] | "\(map(select(.=="Established")) | length) \(length)"')
  [[ ${total:-0} -gt 0 && $up -eq $total ]] && ok "$n VRF PROD $up/$total established" || bad "$n VRF PROD ${up:-0}/${total:-0} established"
done

echo "== Kubernetes =="
K8S=generated/kubernetes.yml
kc() { KUBECONFIG=${NETOPS_KUBECONFIG:-$HOME/.kube/netops.yaml} "$HOME/.local/bin/kubectl" --request-timeout=10s "$@"; }
want=$(yq '.nodes | length' "$K8S")
ready=$(kc get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)
[[ $ready -eq $want ]] && ok "$ready/$want nodes Ready" || bad "$ready/$want nodes Ready"
for n in $(yq -r '.nodes | keys | .[]' "$K8S"); do   # node's pod /24 is in its leaf's (or WAN router's) table
  cidr=$(yq -r ".nodes.\"$n\".pod_cidr" "$K8S"); peer=$(yq -r ".nodes.\"$n\".peer" "$K8S")
  if [[ $(yq -r ".topology.nodes.\"$peer\".kind" "$TOPO") == arista_ceos ]]; then
    got=$(eapi "$peer" "show ip route vrf PROD $cidr" | jq -r ".[0].vrfs.PROD.routes.\"$cidr\".routeType // empty")
  else
    got=$(docker exec "clab-netops-$peer" vtysh -c "show ip route vrf PROD $cidr json" 2>/dev/null | jq -r ".\"$cidr\"[0].protocol // empty")
  fi
  [[ -n $got ]] && ok "$n pod CIDR $cidr announced to $peer" || bad "$n pod CIDR $cidr not in $peer VRF PROD"
done
web=$(kc -n prod get deploy web -o jsonpath='{.status.readyReplicas}/{.spec.replicas}' 2>/dev/null)
[[ -n $web && ${web%/*} == "${web#*/}" ]] && ok "web $web replicas ready" || bad "web ${web:-?} replicas ready"
http_check() { docker exec "clab-netops-$1" sh -c "wget -q -T 3 -O /dev/null $2 || curl -sf -m 3 -o /dev/null $2" 2>/dev/null \
  && ok "$1 -> $2 ($3)" || bad "$1 -> $2 ($3)"; }
http_check inet-k6  http://192.0.2.10/health "Internet user -> public VIP via the WAN"
http_check dc1-web1 http://10.99.0.10/health "DC1 host -> internal VIP"
http_check dc2-db1  http://10.99.0.10/health "DC2 host -> internal VIP"
docker exec clab-netops-attacker1 curl -sf -m 3 -o /dev/null http://10.99.0.10/health 2>/dev/null \
  && bad "attacker1 reaches the internal VIP (must not)" || ok "attacker1 cannot reach the internal VIP"

echo "== Telemetry =="
series=$(curl -s localhost:9464/metrics | grep -c '^gnmi_')
devices=$(curl -s localhost:9464/metrics | grep '^gnmi_' | grep -o 'source="[^"]*"' | sort -u | wc -l)
[[ $series -gt 0 ]] && ok "gnmic local tap (:9464) has $series gnmi series from $devices devices" \
  || bad "no gnmi series on the gnmic local tap (:9464)"

source automation/elastic-env.sh
if [[ -n ${ELASTIC_ES_URL:-} && -n ${ELASTIC_API_KEY:-} ]]; then
  echo "== Elastic (freshness, ES|QL) =="
  esql() {   # esql <query> -> first result row as CSV ("" when the data stream does not exist yet)
    curl -s -m 20 "$ELASTIC_ES_URL/_query?format=csv" -H "Authorization: ApiKey $ELASTIC_API_KEY" \
      -H 'content-type: application/json' -d "$(jq -nc --arg q "$1" '{query: $q}')" | sed -n 2p | tr -d '\r'
  }
  # Kafka sits between the collector and Elastic: the forwarders' consumer lag is how far Elastic is behind
  lag=$(docker exec clab-netops-kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
          --describe --group otelcol-elastic 2>/dev/null | awk '$6 ~ /^[0-9]+$/ {s += $6; n++} END {if (n) print s}')
  [[ -n $lag && $lag -lt 50000 ]] && ok "kafka: forwarders to Elastic are keeping up (consumer lag $lag messages)" \
    || bad "kafka: consumer group otelcol-elastic missing or behind (lag: ${lag:-none})"
  ceos=$(yq -r '[.topology.nodes[] | select(.kind=="arista_ceos")] | length' "$TOPO")
  IFS=, read -r docs devs < <(esql 'FROM metrics-gnmi.otel-* | WHERE @timestamp > NOW() - 2 minutes
    | STATS docs = COUNT(*), devices = COUNT_DISTINCT(host.name)')
  [[ ${devs:-0} -eq $ceos ]] && ok "metrics-gnmi: ${docs} docs from $devs/$ceos switches in the last 2 min" \
    || bad "metrics-gnmi: ${devs:-0}/$ceos switches sent data in the last 2 min"
  # state changes are sent on change only (a quiet fabric sends none), so: every switch has a state history.
  # History checks warn instead of failing: a fresh Elastic deployment has none yet, and waiting for one made
  # every deploy sit out --wait and end red although the network was fine. Live-data checks above still fail.
  IFS=, read -r docs devs < <(esql 'FROM logs-gnmi.state.otel-* | STATS docs = COUNT(*), devices = COUNT_DISTINCT(host.name)')
  [[ ${devs:-0} -eq $ceos ]] && ok "logs-gnmi.state: ${docs} state changes from $devs/$ceos switches (routes, BGP, ports, EVPN)" \
    || warn "logs-gnmi.state: ${devs:-0}/$ceos switches have state changes in Elastic (a quiet switch sends none until something changes, e.g. after moving to a new deployment)"
  n=$(esql 'FROM metrics-otelcol.otel-* | WHERE @timestamp > NOW() - 2 minutes | STATS n = COUNT(*)')
  [[ ${n:-0} -gt 0 ]] && ok "metrics-otelcol: collector health metrics arriving ($n docs in 2 min)" \
    || bad "metrics-otelcol: no collector health metrics in the last 2 min"
  n=$(esql 'FROM traces-*.otel-* | WHERE @timestamp > NOW() - 5 minutes AND service.name == "web" | STATS n = COUNT(*)')
  [[ ${n:-0} -gt 0 ]] && ok "traces: $n web spans in the last 5 min" || bad "traces: no web spans in the last 5 min"
  # Kubernetes, from the in-cluster EDOT collectors (kubernetes/terraform/observability.tf)
  k8s_nodes=$(yq -r '[.topology.nodes | to_entries[] | select(.key | test("-k8s-"))] | length' "$TOPO")
  IFS=, read -r docs nodes < <(esql 'FROM logs-k8s.container.otel-* | WHERE @timestamp > NOW() - 5 minutes
    | STATS docs = COUNT(*), nodes = COUNT_DISTINCT(host.name)')
  [[ ${docs:-0} -gt 0 ]] && ok "logs-k8s.container: $docs container log lines from ${nodes} node(s) in the last 5 min" \
    || bad "logs-k8s.container: no container logs in the last 5 min (otel-agent DaemonSet, namespace otel)"
  IFS=, read -r docs nodes < <(esql 'FROM metrics-k8s.kubelet.otel-* | WHERE @timestamp > NOW() - 2 minutes
    | STATS docs = COUNT(*), nodes = COUNT_DISTINCT(host.name)')
  [[ ${nodes:-0} -eq $k8s_nodes ]] && ok "metrics-k8s.kubelet: $docs docs from $nodes/$k8s_nodes nodes in the last 2 min" \
    || warn "metrics-k8s.kubelet: ${nodes:-0}/$k8s_nodes nodes visible in the last 2 min (if 0: the lab key may lack read on metrics-k8s.*, docs/elastic.md § 2)"
  n=$(esql 'FROM metrics-k8s.cluster.otel-* | WHERE @timestamp > NOW() - 2 minutes | STATS n = COUNT(*)')
  [[ ${n:-0} -gt 0 ]] && ok "metrics-k8s.cluster: cluster state arriving ($n docs in 2 min)" \
    || warn "metrics-k8s.cluster: no cluster state visible in the last 2 min (otel-cluster Deployment; or the lab key lacks read on metrics-k8s.*)"
  # events only come when something happens: their stream existing at all is the check
  n=$(esql 'FROM logs-k8s.events.otel-* | STATS n = COUNT(*)')
  [[ ${n:-0} -gt 0 ]] && ok "logs-k8s.events: $n Kubernetes events in Elastic" \
    || warn "logs-k8s.events: no Kubernetes events in Elastic yet (otel-cluster Deployment; none until something happens)"
fi
exit $fail
