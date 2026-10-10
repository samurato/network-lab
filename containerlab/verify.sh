#!/usr/bin/env bash
# Health checks for the dual-DC EVPN Gateway lab.
#   containerlab/verify.sh [--wait SECONDS]   # --wait: retry until everything passes or the deadline hits
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
SC="$(dirname "$TOPO")/../iac/build/intended/structured_configs"
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

echo "== Telemetry =="
series=$(curl -s localhost:9464/metrics | grep -c '^gnmi_')
devices=$(curl -s localhost:9464/metrics | grep '^gnmi_' | grep -o 'source="[^"]*"' | sort -u | wc -l)
[[ $series -gt 0 ]] && ok "otelcol has $series gnmi series from $devices devices" || bad "no gnmi metrics at otelcol"
exit $fail
