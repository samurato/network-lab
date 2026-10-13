"""Link impairment with `containerlab tools netem` on fabric interfaces (never eth0, the management link)."""
from chaoslab import config, guard, state


def _argv(action: str, node: str, interface: str) -> list:
    return [config.lab("containerlab"), "tools", "netem", action, "-n", config.container(node), "-i", interface]


def impair(node: str, interfaces: list, loss=None, delay=None, jitter=None, rate=None, **_) -> str:
    """Chaos Toolkit action: loss (%), delay / jitter (e.g. 50ms) and rate (kbit) on each interface."""
    opts = []
    for flag, value in (("--loss", loss), ("--delay", delay), ("--jitter", jitter), ("--rate", rate)):
        if value is not None:
            opts += [flag, str(value)]
    if not opts:
        raise ValueError("netem: nothing to set")
    for interface in interfaces:
        guard.check_interface(node, interface)
    done = []
    with guard.lab_lock():
        for interface in interfaces:
            what = f"{node} {interface}: netem {' '.join(opts)}"
            state.register({"kind": "cmd", "argv": _argv("reset", node, interface)}, what)
            config.sh(_argv("set", node, interface) + opts)
            done.append(what)
    return "; ".join(done)


def show(node: str, **_) -> str:
    return config.sh([config.lab("containerlab"), "tools", "netem", "show", "-n", config.container(node)])
