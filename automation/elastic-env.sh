# Elastic settings for lab tooling (sourced by automation/lab, automation/elastic, automation/verify.sh).
# CI passes them as environment variables from repository secrets; on the lab host they live in the
# git-ignored automation/elastic.env.  Variables already set in the environment win over the file.
#   ELASTIC_ES_URL         Elasticsearch endpoint (collector profile `elastic`, change events, verify)
#   ELASTIC_OTLP_ENDPOINT  Managed OTLP endpoint (profile `elastic-otlp`; optional, wins over ELASTIC_ES_URL)
#   ELASTIC_API_KEY        lab key: write telemetry, read it back for verify (made by elastic/terraform)
#   ELASTIC_KIBANA_URL     Kibana endpoint (Terraform only)
#   ELASTIC_TF_API_KEY     admin key for Terraform (lab host only, never in CI)
load_elastic_env() {
  local file k v
  file=${NETOPS_ELASTIC_ENV:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/elastic.env}
  [[ -f $file ]] || return 0
  while IFS='=' read -r k v; do
    [[ $k =~ ^ELASTIC_[A-Z_]+$ ]] || continue
    v=${v%\"}; v=${v#\"}; v=${v%\'}; v=${v#\'}
    [[ -n ${!k:-} ]] || export "$k=$v"
  done < "$file"
}
load_elastic_env
