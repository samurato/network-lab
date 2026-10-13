# chaos-lab: fault injection for the netops lab (Chaos Toolkit). Separate from the lab: own venv, own state.
VENV   ?= $(HOME)/.venvs/chaos
PY     := $(VENV)/bin/python
CLI    := PYTHONPATH=$(CURDIR) PYTHONDONTWRITEBYTECODE=1 $(PY) -m chaoslab.cli

.PHONY: help venv list validate test dry dry-all run random stop status

help:            ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

venv:            ## create the venv (~/.venvs/chaos) from requirements.txt
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install -q -r requirements.txt

list:            ## experiments, which are eligible for random mode, blast radius
	@$(CLI) list

validate:        ## Chaos Toolkit schema validation of every experiment
	@for f in experiments/*.yml; do PYTHONPATH=$(CURDIR) $(VENV)/bin/chaos --no-log-file validate $$f >/dev/null \
	  && echo "ok    $$f" || { echo "FAIL  $$f"; exit 1; }; done

test:            ## guard self-test (telemetry and management must be refused); changes nothing
	@PYTHONPATH=$(CURDIR) PYTHONDONTWRITEBYTECODE=1 $(PY) tests/test_guard.py

dry:             ## dry run EXP=<id>: guard + steady-state probes only, nothing injected
	@$(CLI) run $(EXP) --dry

dry-all:         ## dry run every experiment
	@for f in experiments/*.yml; do id=$$(basename $$f .yml); $(CLI) run $$id --dry || exit 1; done

run:             ## RUN EXP=<id> (injects the fault; hold: CHAOSLAB_HOLD, default 300 s)
	@$(CLI) run $(EXP)

random:          ## Chaos Monkey mode: run one random experiment marked random
	@$(CLI) random

stop:            ## kill switch: undo every active fault now
	@$(CLI) stop

status:          ## current run, active faults, recent runs
	@$(CLI) status
