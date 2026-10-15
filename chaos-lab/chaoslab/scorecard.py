"""Detection scorecard: after a run, did each expected signal reach Elastic, and how long after the fault?

Every experiment lists its signals under `extensions.chaoslab.detect` (detector name + arguments). A detector
returns the first time its signal appears in the fault window, or None. Time to detect (ttd_s) is measured from
the first injection. An undetected signal is an observability gap, not a failed run.

  python -m chaoslab.scorecard [run_id | last]      recompute and print (and store) a run's scorecard
"""
import datetime
import sys

from chaoslab import config, elastic, state

STATE_LOG = "logs-gnmi.state.otel-*"
METRICS = "metrics-gnmi.otel-*"
TRACES = "traces-*.otel-*"
K8S_EVENTS = "logs-k8s.events.otel-*"
WEB = 'service.name == "web" AND kind == "Server" AND NOT http.user_agent LIKE "kube-probe*"'


def _ts(s: str) -> datetime.datetime:
    return datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))


def _iso(t: datetime.datetime) -> str:
    return t.astimezone(datetime.UTC).isoformat().replace("+00:00", "Z")


def _first(query: str, start, end, **params):
    rows = elastic.esql(query, s=_iso(start), e=_iso(end), **params)
    return rows[0].get("t") if rows else None


def _state(where: str, start, end, **params):
    return _first(f"FROM {STATE_LOG} | WHERE @timestamp >= ?s AND @timestamp <= ?e AND {where} "
                  "| STATS t = MIN(@timestamp)", start, end, **params)


# ---------------------------------------------------------------- detectors (start, end, **args) -> iso or None
def port_down(start, end, device, interface):
    return _state('`subscription-name` == "if-state" AND state.oper_status == "DOWN" '
                  "AND host.name == ?d AND interface_name == ?i", start, end, d=device, i=interface)


def lldp_lost(start, end, device, interface):
    return _state('`subscription-name` == "lldp" AND op == "delete" AND host.name == ?d AND interface_name == ?i',
                  start, end, d=device, i=interface)


def bgp_down(start, end, device, peer=None):
    where = ('`subscription-name` == "bgp-state" AND host.name == ?d '
             'AND (op == "delete" OR state.session_state != "ESTABLISHED")')
    if peer:
        return _state(where + " AND `neighbor_neighbor-address` == ?p", start, end, d=device, p=peer)
    return _state(where, start, end, d=device)


def route_change(start, end, prefix, device=None):
    where = '`subscription-name` == "aft" AND `ipv4-entry_prefix` == ?p'
    if device:
        return _state(where + " AND host.name == ?d", start, end, p=prefix, d=device)
    return _state(where, start, end, p=prefix)


def routes_withdrawn(start, end, device=None):
    where = '`subscription-name` == "aft" AND op == "delete"'
    if device:
        return _state(where + " AND host.name == ?d", start, end, d=device)
    return _state(where, start, end)


def vni_change(start, end, device):
    return _state('`subscription-name` == "evpn" AND state.vni IS NOT NULL AND host.name == ?d', start, end, d=device)


def mtu(start, end, device, interface, value):
    return _first(f"FROM {METRICS} | WHERE @timestamp >= ?s AND @timestamp <= ?e AND host.name == ?d "
                  "AND interface_name == ?i AND net.if.ipv4_mtu == ?v | STATS t = MIN(@timestamp)",
                  start, end, d=device, i=interface, v=float(value))


def traffic_above(start, end, device, mbps):
    return _first(f"TS {METRICS} | WHERE @timestamp >= ?s AND @timestamp <= ?e AND host.name == ?d "
                  "| STATS bps = SUM(RATE(net.if.in_octets)) * 8 BY t = BUCKET(@timestamp, 1 minute) "
                  "| WHERE bps > ?b | STATS t = MIN(t)", start, end, d=device, b=float(mbps) * 1e6)


def _web_per_minute(start, end, node_prefix, stat):
    node = " AND k8s.node.name LIKE ?n" if node_prefix else ""
    q = (f"FROM {TRACES} | WHERE @timestamp >= ?s AND @timestamp <= ?e AND {WEB}{node} "
         f"| STATS v = {stat} BY t = BUCKET(@timestamp, 1 minute) | SORT t")
    params = {"n": node_prefix + "*"} if node_prefix else {}
    return [(r["t"], r["v"]) for r in elastic.esql(q, s=_iso(start), e=_iso(end), **params)]


def _baseline(start, node_prefix, stat):
    rows = _web_per_minute(start - datetime.timedelta(minutes=10), start, node_prefix, stat)
    vals = [v for _, v in rows if v is not None]
    return sorted(vals)[len(vals) // 2] if vals else None


def web_latency_up(start, end, factor=1.5, node_prefix=None):
    stat = "PERCENTILE(duration, 95)"
    base = _baseline(start, node_prefix, stat)
    if not base:
        return None
    for t, v in _web_per_minute(start, end, node_prefix, stat):
        if v and v > base * float(factor):
            return t
    return None


def web_requests_drop(start, end, factor=0.5, node_prefix=None):
    base = _baseline(start, node_prefix, "COUNT(*)")
    if not base:
        return None
    rows = dict(_web_per_minute(start, end, node_prefix, "COUNT(*)"))
    t = start.replace(second=0, microsecond=0)
    while t <= end - datetime.timedelta(minutes=1):     # a minute with no requests at all has no row
        v = rows.get(_iso(t).replace("Z", ".000Z"), 0)
        if v < base * float(factor):
            return _iso(t)
        t += datetime.timedelta(minutes=1)
    return None


def web_errors(start, end):
    for t, v in _web_per_minute(start, end, None, "SUM(CASE(http.status_code >= 500, 1, 0))"):
        if v:
            return t
    return None


def new_web_pod(start, end):
    q = f"FROM {TRACES} | WHERE @timestamp >= ?s AND @timestamp <= ?e AND service.name == \"web\" " \
        "| STATS t = MIN(@timestamp) BY container.id"
    before = {r["container.id"] for r in elastic.esql(q, s=_iso(start - datetime.timedelta(minutes=10)), e=_iso(start))}
    new = [r["t"] for r in elastic.esql(q, s=_iso(start), e=_iso(end)) if r["container.id"] not in before]
    return min(new) if new else None


def k8s_event(start, end, reason, namespace=None, object_prefix=None):
    """A Kubernetes event with this reason (e.g. ErrImageNeverPull, BackOff, ScalingReplicaSet)."""
    where, params = "k8s.event.reason == ?r", {"r": reason}
    if namespace:
        where += " AND attributes.k8s.namespace.name == ?n"
        params["n"] = namespace
    if object_prefix:
        where += " AND k8s.object.name LIKE ?o"
        params["o"] = object_prefix + "*"
    return _first(f"FROM {K8S_EVENTS} | WHERE @timestamp >= ?s AND @timestamp <= ?e AND {where} "
                  "| STATS t = MIN(@timestamp)", start, end, **params)


DETECTORS = {f.__name__: f for f in (port_down, lldp_lost, bgp_down, route_change, routes_withdrawn, vni_change,
                                     mtu, traffic_above, web_latency_up, web_requests_drop, web_errors, new_web_pod,
                                     k8s_event)}


def score(run: dict, detect: list) -> dict:
    """Evaluate every expected signal of a run; returns {detected, total, signals: [...]}"""
    if not run.get("injected"):
        return {"detected": 0, "total": 0, "signals": [], "note": "nothing was injected"}
    start = _ts(run["injected"][0]["at"])
    end = _ts(run.get("ended") or state.now())
    signals = []
    for d in detect:
        args = {k: v for k, v in d.items() if k not in ("signal", "label")}
        entry = {"signal": d["signal"], "label": d.get("label", d["signal"]), "args": args}
        try:
            t = DETECTORS[d["signal"]](start, end, **args)
            entry["first_seen"] = t
            entry["ttd_s"] = round(max(0.0, (_ts(t) - start).total_seconds()), 1) if t else None
        except Exception as e:
            entry["error"] = str(e)[:200]
        signals.append(entry)
    found = sum(1 for s in signals if s.get("first_seen"))
    return {"detected": found, "total": len(signals), "signals": signals, "scored_at": state.now()}


def detect_list(experiment_id: str) -> list:
    from chaoslab.cli import experiments
    exps = experiments()
    return exps[experiment_id][2].get("detect", []) if experiment_id in exps else []


def main() -> None:
    which = sys.argv[1] if len(sys.argv) > 1 else "last"
    runs = state.history(1000)
    run = runs[-1] if which == "last" and runs else next((r for r in runs if r["run_id"] == which), None)
    if not run:
        raise SystemExit(f"no run {which} in {config.STATE_DIR / 'runs.jsonl'}")
    sc = score(run, detect_list(run["experiment"]))
    state.set_scorecard(run["run_id"], sc)
    print(f"{run['run_id']}: {sc['detected']}/{sc['total']} expected signals reached Elastic")
    for s in sc["signals"]:
        mark = "seen" if s.get("first_seen") else ("ERROR" if s.get("error") else "MISSING")
        when = f"after {s['ttd_s']}s" if s.get("ttd_s") is not None else s.get("error", "")
        print(f"  {mark:8} {s['label']:55} {when}")


if __name__ == "__main__":
    main()
