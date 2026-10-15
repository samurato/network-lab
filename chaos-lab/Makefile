# chaos-lab: fault injection for the netops lab (Chaos Toolkit). Separate from the lab: own venv, own state.
VENV   ?= $(HOME)/.venvs/chaos
PY     := $(VENV)/bin/python
CLI    := PYTHONPATH=$(CURDIR) PYTHONDONTWRITEBYTECODE=1 $(PY) -m chaoslab.cli
TRAFFIC := PYTHONPATH=$(CURDIR) PYTHONDONTWRITEBYTECODE=1 $(PY) -m chaoslab.traffic
PROFILE ?=

# PUBLISH=0 keeps everything local: no runs, events or catalogue to Elastic (the scorecard still reads it)
ifdef PUBLISH
export CHAOSLAB_PUBLISH := $(PUBLISH)
endif

.PHONY: help venv list validate test dry dry-all run random stop status traffic-start traffic-dry traffic-stop traffic-status score publish

help:            ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-15s %s\n", $$1, $$2}'

venv:            ## create the venv (~/.venvs/chaos) from requirements.txt
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install -q -r requirements.txt

list:            ## experiments, which are eligible for random mode, blast radius
	@$(CLI) list

validate:        ## Chaos Toolkit schema validation of every experiment
	@for f in experiments/*.yml; do PYTHONPATH=$(CURDIR) $(VENV)/bin/chaos --no-log-file validate $$f >/dev/null 2>&1 \
	  && echo "ok    $$f" || { echo "FAIL  $$f"; exit 1; }; done

test:            ## guard self-test (telemetry and management must be refused); changes nothing
	@PYTHONPATH=$(CURDIR) PYTHONDONTWRITEBYTECODE=1 $(PY) tests/test_guard.py
	@PYTHONPATH=$(CURDIR) PYTHONDONTWRITEBYTECODE=1 $(PY) tests/test_publish.py

dry:             ## dry run EXP=<id>: guard + steady-state probes only, nothing injected
	@$(CLI) run $(EXP) --dry

dry-all:         ## dry run every experiment
	@for f in experiments/*.yml; do id=$$(basename $$f .yml); $(CLI) run $$id --dry || exit 1; done

run:             ## RUN EXP=<id> (injects the fault; hold: CHAOSLAB_HOLD, default 300 s; PUBLISH=0: nothing to Elastic)
	@$(CLI) run $(EXP)

random:          ## Chaos Monkey mode: run one random experiment marked random
	@$(CLI) random

stop:            ## kill switch: undo every active fault now
	@$(CLI) stop

status:          ## current run, active faults, recent runs
	@$(CLI) status

traffic-start:   ## background traffic (traffic.yml); PROFILE="web east-west same-vlan stretched", default all
	@$(TRAFFIC) start $(PROFILE)

traffic-dry:     ## show what traffic-start would run, start nothing
	@$(TRAFFIC) start $(PROFILE) --dry

traffic-stop:    ## stop every background traffic process (faults are left alone: that is `make stop`)
	@$(TRAFFIC) stop

traffic-status:  ## running generators + host-to-host ping matrix (loss / latency)
	@$(TRAFFIC) status


score:           ## detection scorecard of RUN=<run_id> (default: the last run): did the signals reach Elastic?
	@PYTHONPATH=$(CURDIR) PYTHONDONTWRITEBYTECODE=1 $(PY) -m chaoslab.scorecard $(or $(RUN),last)

publish:         ## send the catalogue and every recorded run to Elastic (Chaos command center); safe to repeat
	@PYTHONPATH=$(CURDIR) PYTHONDONTWRITEBYTECODE=1 $(PY) -m chaoslab.publish
