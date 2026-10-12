# Everything inside the Elastic project for the lab: data stream templates, the lab API key,
# the Kibana space and data views.  Later steps add lookup indices, transforms, rules, SLOs, dashboards.
#
#   Run:    automation/elastic plan | apply   (make elastic-plan / make elastic)
#   Auth:   ELASTIC_ES_URL, ELASTIC_KIBANA_URL, ELASTIC_TF_API_KEY from automation/elastic.env; the wrapper
#           hands them to the provider as ELASTICSEARCH_* / KIBANA_* environment variables.
#   State:  ~/.local/share/netops/terraform-elastic.tfstate on the lab host (holds the lab API key: mode 600)

terraform {
  required_version = ">= 1.9"
  backend "local" {} # path set by automation/elastic: Elastic outlives the lab, so does the state
  required_providers {
    elasticstack = {
      source  = "elastic/elasticstack"
      version = "~> 0.16"
    }
  }
}

provider "elasticstack" {
  elasticsearch {}
  kibana {}
}
