"""Self-test of the local scorecard report: builds from sample runs, escapes text. Changes nothing."""
from chaoslab import report

runs = [
    {"run_id": "r1", "experiment": "net-01", "title": "<b>x</b>", "started": "2026-10-16T00:00:00Z",
     "status": "completed", "recovered": True, "recovery_seconds": 3.0, "injected": [{"what": "a"}],
     "scorecard": {"detected": 1, "total": 2, "signals": [
         {"signal": "port_down", "label": "port down", "first_seen": "t", "ttd_s": 4.0},
         {"signal": "bgp_down", "label": "bgp down", "first_seen": None, "ttd_s": None}]}},
    {"run_id": "r2", "experiment": "net-02", "title": "dry", "status": "completed"},
]
page = report.build(runs, {"net-01": ("uplink down", "network", True), "net-02": ("flap", "network", True)})
assert "<b>x</b>" not in page and "&lt;b&gt;x&lt;/b&gt;" in page, "titles must be escaped"
assert "1/2" in page and "50%" in page and "4.0 s" in page
assert "bgp down" in page, "missing signal listed as a gap"
assert "1/1" in page, "recovered counts runs with a fault only"
print("report: ok")
