"""Paths and the lab description (targets.yml)."""
import functools
import os
import pathlib
import subprocess

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
EXPERIMENTS = ROOT / "experiments"
STATE_DIR = pathlib.Path(os.path.expanduser(os.environ.get("CHAOSLAB_STATE", "~/clab-runs/chaos")))


@functools.cache
def targets() -> dict:
    return yaml.safe_load((ROOT / "targets.yml").read_text())


def lab(key: str) -> str:
    return os.path.expanduser(targets()["lab"][key])


def limit(key: str) -> int:
    return int(targets()["limits"][key])


def container(node: str) -> str:
    return targets()["lab"]["container_prefix"] + node


def hold_seconds() -> int:
    return int(os.environ.get("CHAOSLAB_HOLD", limit("default_hold_seconds")))


def dry() -> bool:
    return os.environ.get("CHAOSLAB_DRY") == "1"


def sh(argv: list, check: bool = True, timeout: int = 120, input: str = None) -> str:
    """Run a command, return stdout; raise with stderr on failure."""
    p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, input=input)
    if check and p.returncode != 0:
        raise RuntimeError(f"{' '.join(argv)}: rc={p.returncode} {p.stderr.strip() or p.stdout.strip()}")
    return p.stdout


def kubectl_argv() -> list:
    return [lab("kubectl"), "--kubeconfig", lab("kubeconfig")]
