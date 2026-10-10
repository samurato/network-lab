# netops-lab — dual-DC Arista EVPN multi-site lab, GitOps-managed.
#   iac/intent/     SOURCE OF TRUTH  (AVD inventory + group_vars, wan.yml, hosts.yml)
#   iac/build/      GENERATED, committed (AVD intended configs + docs, FRR configs, lab inventory)
#   containerlab/   lab runtime (GENERATED topology + bootstrap configs, telemetry stack, helpers)
SHELL := /bin/bash
VENV  := $(HOME)/.venvs/netops/bin
PY    := $(VENV)/python
PLAYBOOK := cd iac/ansible && $(VENV)/ansible-playbook
LAB   := containerlab/lab
OTELCOL := containerlab/telemetry/otelcol
export EOS_USER ?= admin
export EOS_PASSWORD ?= admin
export ANSIBLE_COLLECTIONS_PATH ?= $(HOME)/.ansible/collections

.PHONY: help build check-build up redeploy down plan apply verify status secrets graph

help:                ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

build:               ## intent -> AVD configs/docs -> lab wiring, telemetry, inventory (offline)
	$(PY) iac/tools/render.py pre
	$(PLAYBOOK) playbooks/build.yml
	$(PY) iac/tools/render.py post

check-build: build   ## CI gate: committed generated files must match a fresh build
	@git diff --exit-code --stat -- iac/build containerlab \
	  || { echo "generated files are stale: run 'make build' and commit"; exit 1; }

up: build secrets    ## bring the whole lab up from intent and verify
	$(LAB) up
	$(MAKE) apply
	containerlab/verify.sh --wait 420

redeploy: build secrets   ## wipe and rebuild from intent
	$(LAB) redeploy
	$(MAKE) apply
	containerlab/verify.sh --wait 420

down:                ## destroy the lab
	$(LAB) down

plan:                ## per-device diff of intent vs running (changes nothing)
	$(PLAYBOOK) playbooks/site.yml --check --diff

apply:               ## converge every device to intent (config-replace / frr-reload)
	$(PLAYBOOK) playbooks/site.yml --diff

verify:              ## BGP / EVPN / multi-site isolation / data plane / telemetry
	containerlab/verify.sh

status:              ## containerlab node list
	$(LAB) status

graph:               ## live interactive topology view on http://<host>:50080
	$(LAB) graph

secrets:             ## runtime secret files for lab containers (git-ignored)
	@printf 'GNMIC_USERNAME=%s\nGNMIC_PASSWORD=%s\n' "$$EOS_USER" "$$EOS_PASSWORD" > containerlab/telemetry/gnmic/gnmic.env
	@[ -f $(OTELCOL)/elastic.env ] || cp $(OTELCOL)/elastic.env.example $(OTELCOL)/elastic.env
	@if grep -qs '^ELASTIC_OTLP_ENDPOINT=..*' $(OTELCOL)/elastic.env; then \
	  cp $(OTELCOL)/elastic.yml $(OTELCOL)/extra.yml; echo "otelcol: exporting to Elastic"; \
	else echo '{}' > $(OTELCOL)/extra.yml; echo "otelcol: lab-local only (no Elastic endpoint)"; fi
