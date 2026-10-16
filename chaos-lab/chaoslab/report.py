"""Local HTML scorecard of every chaos-lab run: ~/clab-runs/chaos/report.html, built from runs.jsonl and the
experiment catalogue. It replaces a dashboard in Elastic on purpose: the ground truth never leaves this host,
so an agent reading Elastic can't learn that a fault was a test.

  make report        then open the file (scp it to your laptop, or `python3 -m http.server` in that folder)
"""
import collections
import html

from chaoslab import config, state


def _e(v) -> str:
    return html.escape("" if v is None else str(v))


def _table(head: list, rows: list) -> str:
    th = "".join(f"<th>{_e(h)}</th>" for h in head)
    tr = "".join("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>" for r in rows)
    return f"<table><thead><tr>{th}</tr></thead><tbody>{tr or '<tr><td>none</td></tr>'}</tbody></table>"


def _sc(run: dict) -> str:
    sc = run.get("scorecard") or {}
    return f"{sc['detected']}/{sc['total']}" if sc.get("total") else "–"


def build(runs: list, catalogue: dict) -> str:
    """catalogue: {id: (title, layer, random)}"""
    real = [r for r in runs if r.get("injected")]
    recovered = sum(1 for r in real if r.get("recovered"))
    seen = sum((r.get("scorecard") or {}).get("detected", 0) for r in real)
    total = sum((r.get("scorecard") or {}).get("total", 0) for r in real)
    ttds = sorted(s["ttd_s"] for r in real for s in (r.get("scorecard") or {}).get("signals", [])
                  if s.get("ttd_s") is not None)
    kpis = [("runs with a fault", len(real)), ("recovered", f"{recovered}/{len(real)}"),
            ("expected signals seen", f"{round(100 * seen / total)}%" if total else "–"),
            ("median time to detect", f"{ttds[len(ttds) // 2]} s" if ttds else "–")]

    run_rows = [[_e(r["run_id"]), _e(r["experiment"]), _e(r.get("title")), _e(r.get("started")),
                 _e(r.get("status")), _e(r.get("recovered")), _e(r.get("recovery_seconds")), _sc(r)]
                for r in reversed(runs)]

    latest = {}
    for r in real:
        latest[r["experiment"]] = r
    cover = [[_e(eid), _e(r.get("started")), _sc(r)] for eid, r in sorted(latest.items())]

    missing = collections.Counter()
    for r in real:
        for s in (r.get("scorecard") or {}).get("signals", []):
            if not s.get("first_seen"):
                missing[(r["experiment"], s.get("label", s["signal"]))] += 1
    gaps = [[_e(eid), _e(label), str(n)] for (eid, label), n in sorted(missing.items())]

    cat = [[_e(eid), _e(t), _e(layer), "yes" if rnd else "", str(sum(1 for r in real if r["experiment"] == eid))]
           for eid, (t, layer, rnd) in sorted(catalogue.items())]

    tiles = "".join(f'<div class="kpi"><b>{_e(v)}</b><span>{_e(k)}</span></div>' for k, v in kpis)
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>chaos-lab scorecard</title>
<style>
:root {{ --bg: #fff; --fg: #1d1d1f; --muted: #666; --line: #ddd; --tile: #f4f4f6; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg: #151517; --fg: #eee; --muted: #999; --line: #333; --tile: #222; }} }}
body {{ background: var(--bg); color: var(--fg); font: 14px/1.4 system-ui, sans-serif; margin: 0 auto;
       max-width: 1200px; padding: 16px; }}
h1 {{ font-size: 20px; }} h2 {{ font-size: 16px; margin-top: 28px; }}
.kpis {{ display: flex; flex-wrap: wrap; gap: 12px; }}
.kpi {{ background: var(--tile); border-radius: 8px; padding: 12px 16px; min-width: 150px; }}
.kpi b {{ display: block; font-size: 22px; }} .kpi span {{ color: var(--muted); }}
.wrap {{ overflow-x: auto; }}
table {{ border-collapse: collapse; width: 100%; }}
th, td {{ border-bottom: 1px solid var(--line); padding: 4px 8px; text-align: left; white-space: nowrap; }}
th {{ color: var(--muted); font-weight: 600; }}
</style></head><body>
<h1>chaos-lab scorecard</h1>
<p>Built {_e(state.now())} from {_e(config.STATE_DIR / "runs.jsonl")}. Local only: this is the ground truth.</p>
<div class="kpis">{tiles}</div>
<h2>Runs (newest first; signals = expected signals that reached Elastic)</h2>
<div class="wrap">{_table(["run", "experiment", "title", "started", "status", "recovered", "recovery s", "signals"], run_rows)}</div>
<h2>Coverage per experiment (latest run)</h2>
<div class="wrap">{_table(["experiment", "latest run", "signals"], cover)}</div>
<h2>Observability gaps: expected signals that never reached Elastic</h2>
<div class="wrap">{_table(["experiment", "signal", "runs missing it"], gaps)}</div>
<h2>Experiment catalogue</h2>
<div class="wrap">{_table(["id", "title", "layer", "random", "runs"], cat)}</div>
</body></html>
"""


def main() -> None:
    from chaoslab.cli import experiments
    catalogue = {eid: (exp.get("title"), ext.get("layer"), ext.get("random")) for eid, (_, exp, ext)
                 in experiments().items()}
    out = config.STATE_DIR / "report.html"
    out.write_text(build(state.history(100000), catalogue))
    print(f"report: {out}")


if __name__ == "__main__":
    main()
