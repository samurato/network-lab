"""FRR WAN routers: vtysh through docker exec. The experiment gives the config and its exact undo."""
from chaoslab import config, guard, state

# vtysh prints this pair when a context line (exit-vrf, end) commits nothing: a note, not an error
_BENIGN = {"% Configuration applied with notes:", "No changes found to be committed!"}


def _vtysh(node: str, lines: list) -> list:
    argv = ["docker", "exec", config.container(node), "vtysh", "-c", "configure terminal"]
    for line in lines:
        argv += ["-c", line]
    return argv


def errors(out: str) -> list:
    """vtysh reports config errors on stdout with rc 0, as lines starting with '%'."""
    lines = [line.strip() for line in out.splitlines()]
    return [line for line in lines if line.startswith("%") and line not in _BENIGN]


# Lines that only open or close a config context; everything else is config the fault added.
_CONTEXT = ("vrf ", "exit", "end", "router ", "address-family ")


def fault_lines(lines: list) -> list:
    return [line.strip() for line in lines if not line.strip().startswith(_CONTEXT)]


def still_present(lines: list, running: str) -> list:
    """The fault's lines still in the running config (indentation ignored)."""
    have = {line.strip() for line in running.splitlines()}
    return [line for line in fault_lines(lines) if line in have]


def undo(node: str, argv: list, lines: list) -> str:
    """Rollback of configure(): replay the undo. If it fails because the config is already gone (a GitOps
    redeploy fixed the fault first, as it should), that is a successful rollback, checked against the
    running config, not assumed."""
    out = config.sh(argv, check=False)
    left = still_present(lines, show(node, "show running-config"))
    if left:
        raise RuntimeError(f"{node}: undo failed and still configured: {'; '.join(left)}: {out.strip()[:300]}")
    return "undone" if not errors(out) else "already gone"


def configure(node: str, lines: list, undo: list, **_) -> str:
    """Chaos Toolkit action: apply FRR config lines; `undo` is registered first and replayed on rollback."""
    guard.check_node(node)
    if node not in config.targets()["frr"]:
        raise guard.Refused(f"{node} is not an FRR router in targets.yml")
    for line in lines + undo:
        guard.check_prefix(line)
    what = "; ".join(line.strip() for line in lines)
    with guard.lab_lock():
        state.register({"kind": "frr_undo", "node": node, "argv": _vtysh(node, undo), "lines": lines},
                       f"{node}: {what}")
        out = config.sh(_vtysh(node, lines))
    if errors(out):
        raise RuntimeError(f"{node}: {out.strip()}")
    return f"{node}: {what}"


def show(node: str, command: str, **_) -> str:
    """Chaos Toolkit probe: evidence for the journal (read-only)."""
    return config.sh(["docker", "exec", config.container(node), "vtysh", "-c", command])
