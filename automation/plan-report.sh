#!/usr/bin/env bash
# Turn an ansible plan/apply log into a compact markdown report (PR comment / drift issue).
#   automation/plan-report.sh plan.log
set -euo pipefail
log=${1:?usage: plan-report.sh <ansible log>}
# a device "changes" only if a task changed ON it (not local "-> localhost" housekeeping)
changed=$(grep -oE '^changed: \[[a-z0-9-]+\]' "$log" | tr -d '[]' | awk '{print $2}' | sort -u || true)
failed=$(grep -E '^[a-z0-9-]+ +: ok=' "$log" | awk '$6 != "failed=0" {print $1}' | sort || true)
echo "### Network plan — \`$(git rev-parse --short HEAD 2>/dev/null || echo local)\`"
echo
if [[ -n "$failed" ]]; then echo "**Failed:** $(paste -sd' ' <<<"$failed")"; echo; fi
if [[ -z "$changed" ]]; then echo "No device changes."; exit 0; fi
echo "**Devices that change:** $(paste -sd' ' <<<"$changed")"
echo
echo '<details><summary>Per-device diff</summary>'
echo
echo '```diff'
# cEOS and FRR diff lines (plan-diff.sh); cap size for GitHub
"$(dirname "$0")/plan-diff.sh" "$log" | head -c 60000 || true
echo '```'
echo '</details>'
