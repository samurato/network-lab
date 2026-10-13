"""Chaos Toolkit experiment control: guard before, rollback safety net + recovery check + ground truth after.

Order inside `chaos run`: before_experiment_control -> steady state -> method (inject, hold) -> steady state
-> rollbacks -> after_experiment_control.
"""
import logging

from chaoslib.exceptions import InterruptExecution

from chaoslab import config, elastic, guard, probes, publish, scorecard, state, watchdog

log = logging.getLogger("chaostoolkit")


def extension(experiment: dict) -> dict:
    for e in experiment.get("extensions", []):
        if e.get("name") == "chaoslab":
            return e
    return {}


def before_experiment_control(context: dict, **kwargs) -> None:
    ext = extension(context)
    try:
        guard.preflight(ext, state.active())
    except guard.Refused as e:
        raise InterruptExecution(f"chaoslab guard: {e}")
    if config.dry():
        log.info(f"chaoslab: dry run of {ext['id']}: guard passed, nothing will be injected")
        return
    if state.current():
        raise InterruptExecution("chaoslab guard: another run is in progress (`make status`)")
    run = state.start_run(ext, context.get("title", ""))
    deadline = run["hold_seconds"] + int(ext.get("extra_seconds", 0)) + 180
    state.set_watchdog(watchdog.arm(run["run_id"], deadline))
    publish.catalogue()
    publish.run(run)
    publish.event("run.start", run, targets=run["targets"], message=run["title"])
    log.info(f"chaoslab: run {run['run_id']} started; watchdog rolls back after {deadline}s if still active")


def after_experiment_control(context: dict, state: dict = None, **kwargs) -> None:
    from chaoslab import state as st     # `state` is the journal here (Chaos Toolkit's argument name)
    run = st.current()
    if config.dry() or not run:
        return
    try:
        st.rollback()                     # safety net: no-op if the experiment's rollbacks already ran
    except Exception as e:
        log.error(f"chaoslab: {e}")
    watchdog.disarm(run.get("watchdog_pid"))
    recovered, seconds = probes.wait_recovered(config.limit("recovery_seconds"))
    status = (state or {}).get("status", "unknown")
    if (state or {}).get("deviated"):
        status = "deviated"
    sc = None
    if elastic.available():               # read-only: did the expected signals reach Elastic?
        try:
            sc = scorecard.score(dict(run, ended=st.now()), extension(context).get("detect", []))
            log.info(f"chaoslab: scorecard {sc['detected']}/{sc['total']} expected signals reached Elastic")
        except Exception as e:
            log.error(f"chaoslab: scorecard failed: {e}")
    st.finish_run(status, recovered, seconds, scorecard=sc)
    if recovered:
        log.info(f"chaoslab: lab healthy again {seconds}s after rollback")
    else:
        log.error("chaoslab: FAILED-TO-RECOVER: the lab is not healthy after rollback; check `make status`, "
                  "then the netops lab (`make verify`, and `make redeploy` there if needed)")
