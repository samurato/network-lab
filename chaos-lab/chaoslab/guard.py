"""Safety checks. Every driver calls these before it changes anything; the control calls preflight()."""
import contextlib
import fcntl
import ipaddress
import os
import re
import time

from chaoslab import config

PREFIX = re.compile(r"\b(\d{1,3}(?:\.\d{1,3}){3})(/\d{1,2})?\b")


class Refused(Exception):
    """A guard rule blocked the action."""


def _deny() -> dict:
    return config.targets()["deny"]


def known_nodes() -> set:
    t = config.targets()
    return set(t["eos"]) | set(t["frr"]) | set(t["linux"])


def check_node(node: str) -> None:
    if node in _deny()["nodes"]:
        raise Refused(f"{node} is part of the telemetry path: chaos-lab never touches it")
    if node not in known_nodes():
        raise Refused(f"{node} is not in targets.yml")


def check_interface(node: str, interface: str) -> None:
    check_node(node)
    for rx in _deny()["interfaces"]:
        if re.search(rx, interface):
            raise Refused(f"{node} {interface} is a management interface: telemetry and access run over it")


def check_prefix(text: str) -> None:
    """Refuse any address or prefix in text that overlaps a denied network (the management network)."""
    denied = [ipaddress.ip_network(p) for p in _deny()["prefixes"]]
    for addr, plen in PREFIX.findall(text):
        try:
            net = ipaddress.ip_network(addr + (plen or "/32"), strict=False)
        except ValueError:
            continue
        for d in denied:
            if net.overlaps(d):
                raise Refused(f"{net} overlaps {d} (management network)")


def check_eos_commands(node: str, commands: list) -> None:
    check_node(node)
    if node not in config.targets()["eos"]:
        raise Refused(f"{node} is not an EOS switch in targets.yml")
    for line in commands:
        for rx in _deny()["eos_config"]:
            if re.search(rx, line):
                raise Refused(f"{node}: config line '{line}' touches management/telemetry config")
        m = re.match(r"\s*interface\s+(\S+)", line)
        if m:
            check_interface(node, m.group(1))
        check_prefix(line)


def check_namespace(namespace: str) -> None:
    for rx in _deny()["namespaces"]:
        if re.search(rx, namespace):
            raise Refused(f"namespace {namespace} matches the deny list ({rx})")


def check_target(spec: str) -> None:
    """An experiment's declared target: 'node', 'node:interface' or 'k8s:<namespace>/...'."""
    if spec.startswith("k8s:"):
        check_namespace(spec[4:].split("/")[0])
        return
    node, _, interface = spec.partition(":")
    if interface:
        check_interface(node, interface)
    else:
        check_node(node)


def check_load() -> None:
    load = os.getloadavg()[0]
    if load > config.limit("max_load"):
        raise Refused(f"lab host load {load:.1f} is above {config.limit('max_load')}")


def lab_lock_free() -> bool:
    with open(config.lab("lock"), "a") as f:
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return False
        fcntl.flock(f, fcntl.LOCK_UN)
        return True


@contextlib.contextmanager
def lab_lock():
    """Hold the netops lab lock while changing the lab, so a deploy never runs in the middle of an injection."""
    with open(config.lab("lock"), "a") as f:
        deadline = time.time() + config.limit("lock_wait_seconds")
        while True:
            try:
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.time() > deadline:
                    raise Refused("the netops lab lock is held (a deploy is running); try again later")
                time.sleep(2)
        try:
            yield
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


def preflight(ext: dict, active: list) -> None:
    """Checks before an experiment starts (also in dry runs)."""
    if not ext or not ext.get("id"):
        raise Refused("experiment has no chaoslab extension with an id")
    for spec in ext.get("targets", []):
        check_target(spec)
    if active:
        raise Refused(f"{len(active)} fault(s) still active from an earlier run: `make stop` first")
    check_load()
    if not lab_lock_free():
        raise Refused("the netops lab lock is held (a deploy is running)")
