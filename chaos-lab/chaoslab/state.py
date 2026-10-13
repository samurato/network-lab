"""Run state on local disk (~/clab-runs/chaos): the current run, its active faults (each with the inverse that
undoes it) and the ground-truth log. Ground truth never leaves this host: it is the answer key for scoring
an agent later, so the agent must not be able to read it.

  current.json   the run in progress (id, experiment, watchdog pid)
  active.json    registered faults, oldest first; rollback() undoes them newest first
  runs.jsonl     one line per finished run: what was broken, where, when, and whether it recovered
"""
import contextlib
import datetime
import fcntl
import json
import logging
import time

from chaoslab import config, guard

log = logging.getLogger("chaostoolkit")


def _path(name: str):
    config.STATE_DIR.mkdir(parents=True, exist_ok=True)
    return config.STATE_DIR / name


@contextlib.contextmanager
def _locked():
    with open(_path(".state.lock"), "a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


def _read(name: str, default):
    p = _path(name)
    return json.loads(p.read_text()) if p.exists() else default


def _write(name: str, data) -> None:
    p = _path(name)
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2))
    tmp.replace(p)


def now() -> str:
    return datetime.datetime.now(datetime.UTC).isoformat(timespec="seconds")


def current() -> dict | None:
    return _read("current.json", None)


def active() -> list:
    return _read("active.json", [])


def require_run() -> dict:
    run = current()
    if not run:
        raise guard.Refused("no chaos-lab run in progress: start experiments with `make run EXP=...`")
    return run


def start_run(ext: dict, title: str) -> dict:
    run = {
        "run_id": datetime.datetime.now(datetime.UTC).strftime("%Y%m%dT%H%M%SZ") + "-" + ext["id"],
        "experiment": ext["id"],
        "title": title,
        "fault": ext.get("fault"),
        "layer": ext.get("layer"),
        "targets": ext.get("targets", []),
        "expected": ext.get("expected", []),
        "blast_radius": int(ext.get("blast_radius", 1)),
        "hold_seconds": config.hold_seconds(),
        "started": now(),
        "injected": [],
    }
    with _locked():
        _write("current.json", run)
    return run


def set_watchdog(pid: int) -> None:
    with _locked():
        run = current()
        run["watchdog_pid"] = pid
        _write("current.json", run)


def register(inverse: dict, what: str) -> None:
    """Record how to undo a fault BEFORE it is made, so a crash mid-injection can still be rolled back."""
    with _locked():
        run = current()
        if not run:
            raise guard.Refused("no chaos-lab run in progress")
        faults = _read("active.json", [])
        if len(faults) >= run["blast_radius"]:
            raise guard.Refused(f"blast radius {run['blast_radius']} reached: refusing '{what}'")
        faults.append({"run_id": run["run_id"], "what": what, "at": now(), "inverse": inverse})
        _write("active.json", faults)
        run["injected"].append({"what": what, "at": now()})
        _write("current.json", run)
    log.info(f"chaoslab: injecting {what}")
    from chaoslab import publish
    publish.event("fault.inject", run, what=what)


def run_inverse(inverse: dict) -> None:
    kind = inverse["kind"]
    if kind == "eos_restore":
        from chaoslab import eos
        eos.restore(inverse["node"], inverse["file"])
    elif kind == "cmd":
        config.sh(inverse["argv"], timeout=inverse.get("timeout", 120))
    elif kind == "note":                 # self-healing fault (pod delete): nothing to undo
        pass
    else:
        raise ValueError(f"unknown inverse kind {kind}")


def rollback(**_) -> list:
    """Chaos Toolkit action (and `make stop`, the watchdog): undo every active fault, newest first."""
    with _locked():
        faults = _read("active.json", [])
    if not faults:
        return []
    done, failed = [], []
    with guard.lab_lock():
        for f in reversed(faults):
            try:
                run_inverse(f["inverse"])
                done.append(f["what"])
                log.info(f"chaoslab: rolled back {f['what']}")
                from chaoslab import publish
                publish.event("fault.rollback", current(), what=f["what"])
            except Exception as e:  # keep going: undo as much as possible, keep what failed for a retry
                failed.append(f)
                log.error(f"chaoslab: rollback of {f['what']} failed: {e}")
    with _locked():
        _write("active.json", list(reversed(failed)))
    if failed:
        raise RuntimeError(f"{len(failed)} rollback(s) failed, still active: `make status`, then `make stop`")
    return done


def hold(seconds=None, **_) -> str:
    """The fault window: the agent diagnoses while this runs."""
    s = int(seconds or config.hold_seconds())
    log.info(f"chaoslab: holding the fault for {s}s")
    time.sleep(s)
    return f"held {s}s"


def finish_run(status: str, recovered: bool | None = None, recovery_seconds: float | None = None,
               journal: str | None = None, scorecard: dict | None = None) -> dict | None:
    with _locked():
        run = current()
        if not run:
            return None
        run.pop("watchdog_pid", None)
        run.update({
            "ended": now(),
            "status": status,
            "recovered": recovered,
            "recovery_seconds": recovery_seconds,
            "still_active": len(_read("active.json", [])),
            "journal": journal,
            "scorecard": scorecard,
        })
        with open(_path("runs.jsonl"), "a") as f:
            f.write(json.dumps(run) + "\n")
        _path("current.json").unlink(missing_ok=True)
    from chaoslab import publish
    publish.run(run)
    publish.event("run.end", run, message=f"{status}; recovered={recovered} in {recovery_seconds}s")
    return run


def set_scorecard(run_id: str, scorecard: dict) -> None:
    """Store a (re)computed scorecard on a finished run."""
    with _locked():
        p = _path("runs.jsonl")
        runs = [json.loads(line) for line in p.read_text().splitlines()] if p.exists() else []
        for r in runs:
            if r["run_id"] == run_id:
                r["scorecard"] = scorecard
        tmp = p.with_suffix(".tmp")
        tmp.write_text("".join(json.dumps(r) + "\n" for r in runs))
        tmp.replace(p)
    from chaoslab import publish
    for r in runs:
        if r["run_id"] == run_id:
            publish.run(r)


def history(n: int = 10) -> list:
    p = _path("runs.jsonl")
    if not p.exists():
        return []
    return [json.loads(line) for line in p.read_text().splitlines()[-n:]]
