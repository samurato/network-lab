#!/usr/bin/env bash
# Keep chaos-lab out of everything the SRE agent can read (docs/elastic.md, "The SRE agent").
#   automation/isolation-check.sh [base-ref]
#     - with a base ref (a PR): fail if the change mixes chaos-lab/ with lab paths
#     - always: fail if the knowledge-base docs or the Elastic Terraform mention chaos-lab
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0

if [[ -n ${1:-} ]]; then
  files=$(git diff --name-only "$1...HEAD")
  chaos=$(grep -c '^chaos-lab/' <<<"$files")
  lab=$(grep -vc '^chaos-lab/' <<<"$files")
  if (( chaos > 0 && lab > 0 )); then
    echo "FAIL: this change touches chaos-lab/ and lab paths; split it into two PRs"
    fail=1
  fi
fi

# docs/ and generated/ feed the agent's knowledge base; elastic/ builds what it can see in Kibana
hits=$(git grep -niE 'chaos|fault injection' -- docs generated elastic network | grep -vi 'chaos2cure')
if [[ -n $hits ]]; then
  echo "FAIL: chaos-lab is mentioned where the SRE agent can read it:"
  echo "$hits"
  fail=1
fi

(( fail == 0 )) && echo "isolation OK"
exit $fail
