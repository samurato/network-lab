"""Arista cEOS over eAPI (HTTPS on the management address).

Every change is preceded by a snapshot of the running config to flash; rollback is `configure replace` from that
snapshot, so the switch returns exactly to its pre-experiment config whatever the fault did.
"""
import os
import re
import time

import requests
import urllib3

from chaoslab import config, guard, state

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)   # cEOS uses a self-signed certificate


def call(node: str, cmds: list, fmt: str = "json", timeout: int = 60) -> list:
    host = config.targets()["eos"][node]
    body = {
        "jsonrpc": "2.0",
        "method": "runCmds",
        "params": {
            "version": 1,
            "cmds": ["enable"] + cmds,
            "format": fmt,
        },
        "id": "chaoslab",
    }
    auth = (os.environ.get("EOS_USER", "admin"), os.environ.get("EOS_PASSWORD", "admin"))
    r = requests.post(f"https://{host}/command-api", json=body, auth=auth, verify=False, timeout=timeout)
    r.raise_for_status()
    j = r.json()
    if "error" in j:
        raise RuntimeError(f"{node}: {j['error'].get('message')} {j['error'].get('data', '')}"[:500])
    return j["result"][1:]


def _snapshot(node: str, run_id: str, what: str) -> None:
    """Snapshot once per switch per run, and register the restore before any change is made."""
    snap = f"flash:chaos-{run_id}.cfg"
    if any(f["inverse"].get("node") == node and f["inverse"]["kind"] == "eos_restore" for f in state.active()):
        return
    call(node, [f"copy running-config {snap}"], fmt="text")
    state.register({"kind": "eos_restore", "node": node, "file": snap}, f"{node}: {what}")


def configure(node: str, commands: list, **_) -> str:
    """Chaos Toolkit action: apply config lines on a switch (rolled back by config replace)."""
    guard.check_eos_commands(node, commands)
    run = state.require_run()
    what = "; ".join(c.strip() for c in commands)
    with guard.lab_lock():
        _snapshot(node, run["run_id"], what)
        call(node, ["configure"] + commands + ["end"], fmt="text")
    return f"{node}: {what}"


def restore(node: str, file: str) -> None:
    call(node, [f"configure replace {file}", f"delete {file}"], fmt="text", timeout=120)


def bgp_asn(node: str) -> str:
    out = call(node, ["show running-config section router bgp"], fmt="text")[0]["output"]
    m = re.search(r"^router bgp (\S+)", out, re.M)
    if not m:
        raise RuntimeError(f"{node}: no router bgp")
    return m.group(1)


def bgp_flap(node: str, neighbor: str, down: int = 20, up: int = 40, cycles: int = 4, **_) -> str:
    """Chaos Toolkit action: shut / unshut a BGP neighbour in a loop (an unstable session)."""
    guard.check_prefix(neighbor)
    asn = bgp_asn(node)
    for i in range(int(cycles)):
        configure(node, [f"router bgp {asn}", f"neighbor {neighbor} shutdown"])
        time.sleep(int(down))
        configure(node, [f"router bgp {asn}", f"no neighbor {neighbor} shutdown"])
        if i < int(cycles) - 1:
            time.sleep(int(up))
    return f"{node}: neighbor {neighbor} flapped {cycles}x ({down}s down / {up}s up)"


def show(node: str, command: str, **_) -> str:
    """Chaos Toolkit probe: evidence for the journal (read-only)."""
    return call(node, [command], fmt="text")[0]["output"]
