"""Dead man's switch: a detached process that rolls the run back at its deadline if it is still active, so a
killed or hung runner never leaves a fault behind.

  python -m chaoslab.watchdog <run_id> <seconds>
"""
import logging
import os
import signal
import subprocess
import sys
import time

from chaoslab import config


def arm(run_id: str, seconds: int) -> int:
    config.STATE_DIR.mkdir(parents=True, exist_ok=True)
    out = open(config.STATE_DIR / "watchdog.log", "a")
    env = dict(os.environ, PYTHONPATH=str(config.ROOT))
    p = subprocess.Popen([sys.executable, "-m", "chaoslab.watchdog", run_id, str(seconds)],
                         stdin=subprocess.DEVNULL, stdout=out, stderr=out, env=env, cwd=str(config.ROOT),
                         start_new_session=True)     # own session: survives Ctrl-C and the runner being killed
    return p.pid


def disarm(pid) -> None:
    if not pid:
        return
    try:
        os.kill(int(pid), signal.SIGTERM)
    except ProcessLookupError:
        pass


def main(run_id: str, seconds: int) -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s watchdog %(message)s")
    time.sleep(seconds)
    from chaoslab import state
    run = state.current()
    if not run or run["run_id"] != run_id:
        return
    logging.info(f"{run_id}: deadline reached with the run still active, rolling back")
    try:
        state.rollback()
    finally:
        state.finish_run("watchdog-rollback")


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]))
