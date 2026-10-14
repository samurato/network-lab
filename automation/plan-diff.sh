#!/usr/bin/env bash
# Per-device diff lines from an ansible plan/apply log, for both device kinds:
#   cEOS  `--- system:` config-replace diffs (+/- lines)
#   FRR   the frr_router "Show device diff" message (frr-reload --test: Lines To Delete / Lines To Add)
# Prints nothing (and exits 0) when there is no diff.   automation/plan-diff.sh plan.log
set -uo pipefail
log=${1:?usage: plan-diff.sh <ansible log>}
{
  awk '/^--- system:|^--- before/{show=($0 ~ /system:/)} show && /^(changed: |[+-])/' "$log" | grep -vE '^(\+\+\+|---) '
  awk '
    /^TASK \[/                                   { in_show = ($0 ~ /Show device diff/); host = "" }
    in_show && /^ok: \[[a-z0-9-]+\] => \{/       { match($0, /\[[a-z0-9-]+\]/); host = substr($0, RSTART + 1, RLENGTH - 2); print "changed: [" host "]"; next }
    in_show && host != "" && /^ +"/              { l = $0; sub(/^ *"/, "", l); sub(/",?$/, "", l)
                                                   if (l ~ /^=+$/ || l ~ /^msg": \[/) next
                                                   if (l ~ /^Lines To Delete/) { sign = "-"; next }
                                                   if (l ~ /^Lines To Add/)    { sign = "+"; next }
                                                   print sign " " l }
    in_show && /^}/                              { host = "" }
  ' "$log"
} || true
