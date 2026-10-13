"""Publish chaos-lab runs to Elastic for the Chaos command center dashboard (Kibana space "chaos").

  chaos-events       timeline: run.start, fault.inject, fault.rollback, run.end, traffic.start, traffic.stop
  chaos-runs         one document per run, updated as it progresses (status "running" while the fault is on)
  chaos-signals      one document per expected signal of a run (the detection scorecard)
  chaos-experiments  the catalogue

The local runs.jsonl stays the source of truth: publishing never blocks or fails a run, and
`python -m chaoslab.publish` (make publish) re-sends the catalogue and every recorded run.
"""
import logging

from chaoslab import elastic, state

log = logging.getLogger("chaostoolkit")
_warned = False


def _send(actions: list) -> None:
    global _warned
    if not elastic.can_write():
        if not _warned:
            log.info("chaoslab: no ELASTIC_CHAOS_API_KEY, not publishing to Elastic (see README: Elastic)")
            _warned = True
        return
    try:
        elastic.bulk(actions)
    except Exception as e:
        log.warning(f"chaoslab: publishing to Elastic failed (the run is unaffected): {e}")


def _run_fields(run: dict) -> dict:
    return {
        "run_id": run["run_id"],
        "experiment": run["experiment"],
        "title": run.get("title"),
        "fault": run.get("fault"),
        "layer": run.get("layer"),
    }


def event(action: str, run: dict | None = None, **fields) -> None:
    doc = {"@timestamp": state.now(), "event": {"action": action}, **(_run_fields(run) if run else {}), **fields}
    _send([({"create": {"_index": "chaos-events"}}, doc)])


def run_doc(run: dict) -> dict:
    sc = run.get("scorecard") or {}
    total = sc.get("total")
    return {
        "@timestamp": run["started"],
        **_run_fields(run),
        "status": run.get("status", "running"),
        "targets": run.get("targets", []),
        "injected": [i["what"] for i in run.get("injected", [])],
        "expected": run.get("expected", []),
        "hold_s": run.get("hold_seconds"),
        "ended": run.get("ended"),
        "recovered": run.get("recovered"),
        "recovery_s": run.get("recovery_seconds"),
        "detected": sc.get("detected"),
        "total": total,
        "detection_pct": round(100.0 * sc["detected"] / total, 1) if total else None,
    }


def signal_docs(run: dict) -> list:
    sc = run.get("scorecard") or {}
    out = []
    for i, s in enumerate(sc.get("signals", [])):
        out.append(({"index": {"_index": "chaos-signals", "_id": f"{run['run_id']}-{i}"}}, {
            "@timestamp": run["started"],
            **_run_fields(run),
            "signal": s["signal"],
            "label": s.get("label"),
            "detected": bool(s.get("first_seen")),
            "ttd_s": s.get("ttd_s"),
            "first_seen": s.get("first_seen"),
        }))
    return out


def run(run: dict) -> None:
    """Upsert the run and its scorecard rows."""
    _send([({"index": {"_index": "chaos-runs", "_id": run["run_id"]}}, run_doc(run))] + signal_docs(run))


def catalogue() -> None:
    from chaoslab.cli import experiments
    actions = []
    for eid, (_, exp, ext) in experiments().items():
        actions.append(({"index": {"_index": "chaos-experiments", "_id": eid}}, {
            "experiment": eid,
            "title": exp["title"],
            "layer": ext.get("layer"),
            "fault": ext.get("fault"),
            "random": bool(ext.get("random")),
            "blast_radius": ext.get("blast_radius", 1),
            "signals": len(ext.get("detect", [])),
            "expected": ext.get("expected", []),
        }))
    _send(actions)


def main() -> None:
    if not elastic.can_write():
        raise SystemExit("ELASTIC_CHAOS_API_KEY is not set (automation/elastic.env); see README: Elastic")
    catalogue()
    runs = state.history(100000)
    for r in runs:
        run(r)
    cur = state.current()
    if cur:
        run(cur)
    print(f"published the catalogue and {len(runs)} run(s){' + the run in progress' if cur else ''} to Elastic")


if __name__ == "__main__":
    main()
