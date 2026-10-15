"""Publishing switch: PUBLISH=0 sends nothing, and a run started that way is never sent later.
Run: make test (no lab changes, nothing sent: Elastic is replaced by a recorder)."""
import os
import sys

from chaoslab import elastic, publish

sent = []
elastic.can_write = lambda: True
elastic.bulk = lambda actions: sent.extend(actions)
RUN = {"run_id": "t", "experiment": "net-11", "started": "2026-01-01T00:00:00Z", "layer": "network"}


def case(name, env, run, want):
    sent.clear()
    os.environ["CHAOSLAB_PUBLISH"] = env
    publish.event("run.start", run)
    if run:
        publish.run(run)
    got = bool(sent)
    print(f"{'ok  ' if got == want else 'FAIL'} {name}: sent={got}")
    return got != want


failed = sum([
    case("default (on)", "", dict(RUN), True),
    case("PUBLISH=0", "0", dict(RUN), False),
    case("PUBLISH=off, no run (traffic events)", "off", None, False),
    case("local-only run, publishing on again", "1", {**RUN, "publish": False}, False),
])
sys.exit(1 if failed else 0)
