"""chaos-lab command line (the Makefile wraps it).

  python -m chaoslab.cli list
  python -m chaoslab.cli run <id> [--dry]
  python -m chaoslab.cli random [--dry]      Chaos Monkey mode: one random experiment marked `random: true`
  python -m chaoslab.cli monkey <count> <gap> [--dry]
                                             Chaos Monkey campaign: <count> random experiments one after another,
                                             <gap> seconds (+-50%) between them; stops at the first that fails to recover
  python -m chaoslab.cli stop                undo every active fault now
  python -m chaoslab.cli status
"""
import datetime
import json
import os
import random
import subprocess
import sys
import time

import yaml

from chaoslab import config, guard, state, watchdog
from chaoslab.control import extension


def experiments() -> dict:
    out = {}
    for f in sorted(config.EXPERIMENTS.glob("*.yml")):
        exp = yaml.safe_load(f.read_text())
        ext = extension(exp)
        out[ext["id"]] = (f, exp, ext)
    return out


def cmd_list() -> None:
    print(f"{'id':8} {'random':6} {'blast':5}  title")
    for eid, (_, exp, ext) in experiments().items():
        print(f"{eid:8} {'yes' if ext.get('random') else '':6} {ext.get('blast_radius', 1):<5}  {exp['title']}")


def _chaos(eid: str, dry: bool) -> tuple:
    """The `chaos run` command line and environment for one experiment."""
    exps = experiments()
    if eid not in exps:
        sys.exit(f"unknown experiment {eid}; `make list`")
    path = exps[eid][0]
    stamp = datetime.datetime.now(datetime.UTC).strftime("%Y%m%dT%H%M%SZ")
    for d in ("journals", "logs"):
        (config.STATE_DIR / d).mkdir(parents=True, exist_ok=True)
    suffix = "-dry" if dry else ""
    argv = [os.path.join(os.path.dirname(sys.executable), "chaos"),
            "--log-file", str(config.STATE_DIR / "logs" / f"{stamp}-{eid}{suffix}.log"),
            "run",
            "--journal-path", str(config.STATE_DIR / "journals" / f"{stamp}-{eid}{suffix}.json"),
            "--rollback-strategy", "always"]
    env = dict(os.environ, PYTHONPATH=str(config.ROOT), PYTHONDONTWRITEBYTECODE="1")
    if dry:
        argv += ["--dry", "actions"]
        env["CHAOSLAB_DRY"] = "1"
    argv.append(str(path))
    print(f"chaos-lab: {'dry run' if dry else 'RUN'} {eid}: {exps[eid][1]['title']}", flush=True)
    return argv, env


def cmd_run(eid: str, dry: bool) -> None:
    argv, env = _chaos(eid, dry)
    os.execve(argv[0], argv, env)


def _eligible() -> list:
    return [eid for eid, (_, _, ext) in experiments().items() if ext.get("random")]


def cmd_random(dry: bool) -> None:
    eligible = _eligible()
    eid = random.choice(eligible)
    print(f"chaos-lab: random pick from {len(eligible)} eligible experiments", flush=True)
    cmd_run(eid, dry)


def _wait_for_lab(limit: int = 600) -> None:
    """Start only when no run is active and no deploy or drift check holds the lab lock."""
    deadline = time.time() + limit
    while state.current() or state.active() or not guard.lab_lock_free():
        if time.time() > deadline:
            sys.exit("chaos-lab monkey: the lab stayed busy (a run, an active fault or the lab lock); stopping")
        time.sleep(10)


def cmd_monkey(count: int, gap: int, dry: bool) -> None:
    eligible, last, done = _eligible(), None, []
    print(f"chaos-lab monkey: {count} random experiments from {len(eligible)} eligible, ~{gap}s apart", flush=True)
    for n in range(1, count + 1):
        _wait_for_lab()
        eid = random.choice([e for e in eligible if e != last] or eligible)   # never the same twice in a row
        print(f"\nchaos-lab monkey: {n}/{count}", flush=True)
        argv, env = _chaos(eid, dry)
        subprocess.run(argv, env=env)       # deviated exits non-zero: that is a finding, not a monkey failure
        last = eid
        if not dry:
            r = (state.history(1) or [{}])[-1]
            done.append(f"{r.get('run_id', eid):34} {r.get('status', '?'):10} recovered={r.get('recovered')}"
                        f" in {r.get('recovery_seconds')}s")
            if r.get("recovered") is False or r.get("still_active") or state.active():
                print("chaos-lab monkey: the lab did not recover; stopping (`make status`, `make stop`)", flush=True)
                break
        if n < count:
            pause = int(gap * random.uniform(0.5, 1.5))
            print(f"chaos-lab monkey: next fault in {pause}s", flush=True)
            time.sleep(pause)
    print("\nchaos-lab monkey: done", *done, sep="\n  ")


def cmd_stop() -> None:
    run = state.current()
    if run:
        watchdog.disarm(run.get("watchdog_pid"))
    done = state.rollback()
    for what in done:
        print(f"rolled back: {what}")
    if run:
        state.finish_run("stopped")
    print("chaos-lab: nothing active" if not state.active() else "chaos-lab: some faults are still active")


def cmd_status() -> None:
    run = state.current()
    print("current run:", json.dumps(run, indent=2) if run else "none")
    act = state.active()
    print(f"active faults: {len(act)}")
    for f in act:
        print(f"  {f['at']}  {f['what']}")
    print("recent runs:")
    for r in state.history(5):
        print(f"  {r['run_id']:40} {r.get('status', ''):18} recovered={r.get('recovered')}"
              f" in {r.get('recovery_seconds')}s")


def main() -> None:
    args = sys.argv[1:]
    dry = "--dry" in args
    args = [a for a in args if a != "--dry"]
    if not args or args[0] == "list":
        cmd_list()
    elif args[0] == "run" and len(args) == 2:
        cmd_run(args[1], dry)
    elif args[0] == "random":
        cmd_random(dry)
    elif args[0] == "monkey" and len(args) == 3:
        cmd_monkey(int(args[1]), int(args[2]), dry)
    elif args[0] == "stop":
        cmd_stop()
    elif args[0] == "status":
        cmd_status()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
