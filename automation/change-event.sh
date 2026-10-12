#!/usr/bin/env bash
# Record a deployment as a change event — what changed, when, by which commit — so the
# Auto-SRE agent can line changes up with symptoms.  Ships to Elastic (logs-netops.changes)
# when ELASTIC_ES_URL/ELASTIC_API_KEY are set, and always appends to ~/netops-changes.jsonl.
#   automation/change-event.sh <status> [apply.log]
set -uo pipefail
status=${1:-unknown}; log=${2:-/dev/null}
source "$(dirname "$0")/elastic-env.sh"   # CI: repository secrets; lab host: automation/elastic.env
devices=$(grep -E '^[a-z0-9-]+ +: ok=' "$log" 2>/dev/null | awk '$4 != "changed=0" {print $1}' | jq -R . | jq -sc .)
event=$(jq -nc --arg ts "$(date -u +%FT%TZ)" --arg sha "$(git rev-parse HEAD)" \
  --arg msg "$(git log -1 --pretty=%s)" --arg author "$(git log -1 --pretty=%an)" \
  --arg status "$status" --argjson devices "${devices:-[]}" \
  '{"@timestamp":$ts, event:{kind:"event", category:["configuration"], type:["change"], outcome:$status},
    git:{sha:$sha, message:$msg, author:$author}, netops:{changed_devices:$devices, source:"gitops-deploy"}}')
echo "$event" >> "$HOME/netops-changes.jsonl"
if [[ -n "${ELASTIC_ES_URL:-}" && -n "${ELASTIC_API_KEY:-}" ]]; then
  curl -sf -X POST "$ELASTIC_ES_URL/logs-netops.changes-default/_doc" -H "Authorization: ApiKey $ELASTIC_API_KEY" \
    -H 'content-type: application/json' -d "$event" >/dev/null && echo "change event sent to Elastic" \
    || echo "WARN: could not send change event to Elastic"
fi
echo "$event"
