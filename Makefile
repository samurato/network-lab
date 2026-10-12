# netops-lab — dual-DC Arista EVPN multi-site lab, GitOps-managed.
#   network/       what you edit: the network design (AVD inventory + group_vars, hosts.yml, wan.yml)
#   kubernetes/    what you edit: the k3s cluster (cluster.yml) and everything inside it (terraform/)
#   containerlab/  portable lab bundle, generated: `containerlab deploy -t netops.clab.yml` anywhere
#   generated/     AVD output, generated: full configs, docs, Ansible inventory — never edit
#   elastic/       what you edit: everything inside the Elastic project (terraform/)
#   automation/    tooling: Ansible, render.py, lab helper, verify.sh, CI scripts
SHELL := /bin/bash
VENV  := $(HOME)/.venvs/netops/bin
PY    := $(VENV)/python
PLAYBOOK := cd automation && $(VENV)/ansible-playbook
LAB   := automation/lab
LOCKED := $(LAB) locked bash -c   # one job at a time against the lab (see automation/lab)
export EOS_USER ?= admin
export EOS_PASSWORD ?= admin
export ANSIBLE_COLLECTIONS_PATH ?= $(HOME)/.ansible/collections

# Elastic (optional): settings in the git-ignored automation/elastic.env, or the environment (CI secrets).
# automation/lab, automation/elastic and automation/verify.sh read them via automation/elastic-env.sh;
# the collector profile follows them (local / elastic / elastic-otlp), see docs/elastic.md.

.PHONY: help build check-build up redeploy down sync plan apply verify status graph k8s k8s-plan elastic elastic-plan

help:                ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

build:               ## network/ -> AVD configs/docs -> containerlab/ bundle (offline)
	$(PY) automation/render.py pre
	$(PLAYBOOK) playbooks/build.yml
	$(PY) automation/render.py post

check-build: build   ## CI gate: committed generated files must match a fresh build
	@git diff --exit-code --stat -- generated containerlab \
	  || { echo "generated files are stale: run 'make build' and commit"; exit 1; }

up: build            ## deploy the lab from containerlab/, bring up Kubernetes, verify
	$(LAB) up
	automation/k8s apply
	automation/verify.sh --wait 420

redeploy: build      ## wipe and redeploy the lab, then Kubernetes, then verify
	$(LAB) redeploy
	automation/k8s apply
	automation/verify.sh --wait 420

down:                ## destroy the lab
	$(LAB) down

sync:                ## refresh the running lab's bundle (configs, telemetry, scripts) from containerlab/
	$(LAB) sync

plan:                ## per-device diff, running vs intended (changes nothing)
	@mkdir -p -m 775 generated/config_backup   # as AVD wants it, else every plan shows a local "change"
	$(LOCKED) '$(PLAYBOOK) playbooks/site.yml --check --diff'

apply:               ## push changed configs to the running lab (config replace / frr-reload)
	@mkdir -p -m 775 generated/config_backup
	$(LOCKED) '$(LAB) sync && $(PLAYBOOK) playbooks/site.yml --diff'

k8s:                 ## Kubernetes: terraform apply (pod CIDRs, Cilium, BGP, LB pools, apps)
	automation/k8s apply

k8s-plan:            ## Kubernetes: terraform plan (changes nothing)
	automation/k8s plan

elastic:             ## Elastic: terraform apply (data stream templates, lab API key, Kibana space, data views)
	automation/elastic apply

elastic-plan:        ## Elastic: terraform plan (changes nothing)
	automation/elastic plan

verify:              ## OSPF / BGP / EVPN / multi-site / data plane / Kubernetes / telemetry
	automation/verify.sh

status:              ## containerlab node list
	$(LAB) status

graph:               ## live topology view on http://<host>:50080
	$(LAB) graph
