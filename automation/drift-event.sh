#!/usr/bin/env bash
# Record one drift-check result in Elastic (logs-netops.drift-default) so the Auto-SRE agent can ask
# "does the running network match Git right now, and if not, which devices and how?" without GitHub.
# Same pattern as change-event.sh: always appends to ~/netops-drift.jsonl; sends when ELASTIC_ES_URL and
# ELASTIC_API_KEY are set.        automation/drift-event.sh <plan step outcome> plan.log
set -uo pipefail
step=${1:-unknown}; log=${2:-/dev/null}
here=$(dirname "$0")
changed=$(grep -oE '^changed: \[[a-z0-9-]+\]' "$log" 2>/dev/null | tr -d '[]' | awk '{print $2}' | sort -u | jq -R . | jq -sc .)
failed=$(grep -E '^[a-z0-9-]+ +: ok=' "$log" 2>/dev/null | awk '$6 != "failed=0" {print $1}' | sort -u | jq -R . | jq -sc .)
diff=$("$here/plan-diff.sh" "$log" | head -c 20000)
if [[ "$step" != success ]]; then outcome=plan_failed
elif [[ "$(jq length <<<"${changed:-[]}")" -gt 0 ]]; then outcome=drift
else outcome=in_sync; fi
event=$(jq -nc --arg ts "$(date -u +%FT%TZ)" --arg sha "$(git rev-parse HEAD)" --arg outcome "$outcome" \
  --argjson devices "${changed:-[]}" --argjson failed "${failed:-[]}" --arg diff "$diff" \
  '{"@timestamp":$ts, event:{kind:"state", category:["configuration"], type:["info"], outcome:$outcome},
    git:{sha:$sha},
    netops:{source:"gitops-drift", drift:{devices:$devices, device_count:($devices|length), failed_devices:$failed, diff:$diff}}}')
echo "$event" >> "$HOME/netops-drift.jsonl"
if [[ -n "${ELASTIC_ES_URL:-}" && -n "${ELASTIC_API_KEY:-}" ]]; then
  curl -sf -X POST "$ELASTIC_ES_URL/logs-netops.drift-default/_doc" -H "Authorization: ApiKey $ELASTIC_API_KEY" \
    -H 'content-type: application/json' -d "$event" >/dev/null && echo "drift result sent to Elastic" \
    || echo "WARN: could not send drift result to Elastic"
fi
echo "$event"
