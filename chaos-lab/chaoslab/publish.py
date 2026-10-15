"""Publish chaos-lab runs to Elastic for the Chaos command center dashboard (Kibana space "chaos"), with the
lab key. Append-only data streams; the dashboard takes the latest document per run:

  logs-chaos.events-default       timeline: run.start, fault.inject, fault.rollback, run.end, traffic.*
  logs-chaos.runs-default         a run snapshot at start (status "running") and at the end
  logs-chaos.signals-default      the detection scorecard: one document per expected signal per scoring
  logs-chaos.experiments-default  the catalogue

The local runs.jsonl stays the source of truth: publishing never blocks or fails a run, and
`python -m chaoslab.publish` (make publish) re-sends the catalogue and every recorded run.

Publishing off (make run EXP=... PUBLISH=0, or elastic.publish: false in targets.yml): nothing is sent.
A run started that way is kept local for good: it is marked "publish": false, so a later rollback by the
watchdog, a re-score or `make publish` never sends it either.
"""
import datetime
import logging
import os

from chaoslab import config, elastic, state

log = logging.getLogger("chaostoolkit")
_warned = False
EVENTS = "logs-chaos.events-default"
RUNS = "logs-chaos.runs-default"
SIGNALS = "logs-chaos.signals-default"
EXPERIMENTS = "logs-chaos.experiments-default"


def enabled() -> bool:
    """CHAOSLAB_PUBLISH (set by make's PUBLISH=0/1) wins over elastic.publish in targets.yml (default on)."""
    env = os.environ.get("CHAOSLAB_PUBLISH", "")
    if env:
        return env.lower() not in ("0", "no", "false", "off")
    return bool(config.targets()["elastic"].get("publish", True))


def _send(actions: list, run: dict | None = None) -> None:
    global _warned
    if not enabled() or (run and run.get("publish") is False):
        if not _warned:
            log.info("chaoslab: publishing to Elastic is off, this run stays local (runs.jsonl)")
            _warned = True
        return
    if not elastic.can_write():
        if not _warned:
            log.info("chaoslab: no Elastic URL / API key, not publishing to Elastic")
            _warned = True
        return
    try:
        elastic.bulk(actions)
    except Exception as e:
        log.warning(f"chaoslab: publishing to Elastic failed (the run is unaffected): {e}")


def _layer(experiment: str) -> str | None:
    from chaoslab.cli import experiments
    e = experiments().get(experiment)
    return e[2].get("layer") if e else None


def _run_fields(run: dict) -> dict:
    return {
        "run_id": run["run_id"],
        "experiment": run["experiment"],
        "title": run.get("title"),
        "fault": run.get("fault"),
        "layer": run.get("layer") or _layer(run["experiment"]),   # runs recorded before layer was kept
    }


def event(action: str, run: dict | None = None, **fields) -> None:
    doc = {"@timestamp": state.now(), "event": {"action": action}, **(_run_fields(run) if run else {}), **fields}
    _send([({"create": {"_index": EVENTS}}, doc)], run)


def run_doc(run: dict, batch: str) -> dict:
    sc = run.get("scorecard") or {}
    total = sc.get("total")
    return {
        "@timestamp": batch,
        "started": run["started"],
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


def _batch_time() -> str:
    """One timestamp (ms) for every document of a publish: the dashboard keeps the latest batch per run."""
    return datetime.datetime.now(datetime.UTC).isoformat(timespec="milliseconds")


def signal_docs(run: dict, batch: str) -> list:
    sc = run.get("scorecard") or {}
    out = []
    for s in sc.get("signals", []):
        out.append(({"create": {"_index": SIGNALS}}, {
            "@timestamp": batch,
            "started": run["started"],
            "scored_at": sc.get("scored_at") or state.now(),
            **_run_fields(run),
            "signal": s["signal"],
            "label": s.get("label"),
            "detected": bool(s.get("first_seen")),
            "ttd_s": s.get("ttd_s"),
            "first_seen": s.get("first_seen"),
        }))
    return out


def run(run: dict) -> None:
    """Append a snapshot of the run, and its scorecard rows."""
    batch = _batch_time()
    _send([({"create": {"_index": RUNS}}, run_doc(run, batch))] + signal_docs(run, batch), run)


def catalogue() -> None:
    from chaoslab.cli import experiments
    actions, batch = [], _batch_time()
    for eid, (_, exp, ext) in experiments().items():
        actions.append(({"create": {"_index": EXPERIMENTS}}, {
            "@timestamp": batch,
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
    if not enabled():
        raise SystemExit("publishing to Elastic is off (PUBLISH=0 or elastic.publish: false in targets.yml)")
    if not elastic.can_write():
        raise SystemExit("no Elastic URL / API key (ELASTIC_ES_URL, ELASTIC_API_KEY in automation/elastic.env)")
    catalogue()
    everything = state.history(100000)
    runs = [r for r in everything if r.get("publish") is not False]
    for r in runs:
        run(r)
    cur = state.current()
    if cur:
        run(cur)
    event("catalogue.published", message=f"{len(runs)} run(s) re-sent")
    local = len(everything) - len(runs)
    print(f"published the catalogue and {len(runs)} run(s){' + the run in progress' if cur and cur.get('publish') is not False else ''}"
          f" to Elastic{f'; {local} local-only run(s) not sent' if local else ''}")


if __name__ == "__main__":
    main()
