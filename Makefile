# netops-lab — dual-DC Arista EVPN multi-site lab, GitOps-managed.
#   network/       what you edit: the network design (AVD inventory + group_vars, hosts.yml, wan.yml)
#   containerlab/  portable lab bundle, generated: `containerlab deploy -t netops.clab.yml` anywhere
#   generated/     AVD output, generated: full configs, docs, Ansible inventory — never edit
#   automation/    tooling: Ansible, render.py, lab helper, verify.sh, CI scripts
SHELL := /bin/bash
VENV  := $(HOME)/.venvs/netops/bin
PY    := $(VENV)/python
PLAYBOOK := cd automation && $(VENV)/ansible-playbook
LAB   := automation/lab
export EOS_USER ?= admin
export EOS_PASSWORD ?= admin
export ANSIBLE_COLLECTIONS_PATH ?= $(HOME)/.ansible/collections

# Elastic export (optional): automation/elastic.env (git-ignored) with ELASTIC_OTLP_ENDPOINT / ELASTIC_API_KEY
-include automation/elastic.env
export ELASTIC_OTLP_ENDPOINT ELASTIC_API_KEY
export OTELCOL_PROFILE := $(if $(ELASTIC_OTLP_ENDPOINT),elastic,local)

.PHONY: help build check-build up redeploy down plan apply verify status graph

help:                ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

build:               ## network/ -> AVD configs/docs -> containerlab/ bundle (offline)
	$(PY) automation/render.py pre
	$(PLAYBOOK) playbooks/build.yml
	$(PY) automation/render.py post

check-build: build   ## CI gate: committed generated files must match a fresh build
	@git diff --exit-code --stat -- generated containerlab \
	  || { echo "generated files are stale: run 'make build' and commit"; exit 1; }

up: build            ## deploy the lab from containerlab/ and verify
	$(LAB) up
	automation/verify.sh --wait 420

redeploy: build      ## wipe and redeploy the lab, then verify
	$(LAB) redeploy
	automation/verify.sh --wait 420

down:                ## destroy the lab
	$(LAB) down

plan:                ## per-device diff, running vs intended (changes nothing)
	$(PLAYBOOK) playbooks/site.yml --check --diff

apply:               ## push changed configs to the running lab (config replace / frr-reload)
	$(PLAYBOOK) playbooks/site.yml --diff

verify:              ## OSPF / BGP / EVPN / multi-site isolation / data plane / telemetry
	automation/verify.sh

status:              ## containerlab node list
	$(LAB) status

graph:               ## live topology view on http://<host>:50080
	$(LAB) graph
