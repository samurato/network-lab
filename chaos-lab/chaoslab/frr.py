"""FRR WAN routers: vtysh through docker exec. The experiment gives the config and its exact undo."""
from chaoslab import config, guard, state


def _vtysh(node: str, lines: list) -> list:
    argv = ["docker", "exec", config.container(node), "vtysh", "-c", "configure terminal"]
    for line in lines:
        argv += ["-c", line]
    return argv


def configure(node: str, lines: list, undo: list, **_) -> str:
    """Chaos Toolkit action: apply FRR config lines; `undo` is registered first and replayed on rollback."""
    guard.check_node(node)
    if node not in config.targets()["frr"]:
        raise guard.Refused(f"{node} is not an FRR router in targets.yml")
    for line in lines + undo:
        guard.check_prefix(line)
    what = "; ".join(line.strip() for line in lines)
    with guard.lab_lock():
        state.register({"kind": "cmd", "argv": _vtysh(node, undo)}, f"{node}: {what}")
        out = config.sh(_vtysh(node, lines))
    if "% " in out:                       # vtysh reports config errors on stdout with rc 0
        raise RuntimeError(f"{node}: {out.strip()}")
    return f"{node}: {what}"


def show(node: str, command: str, **_) -> str:
    """Chaos Toolkit probe: evidence for the journal (read-only)."""
    return config.sh(["docker", "exec", config.container(node), "vtysh", "-c", command])
