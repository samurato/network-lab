#!/usr/bin/env python3
"""Run every dashboard query (elastic/terraform/dashboards/queries.yml) against Elastic, read-only, with the lab
key: catches ES|QL errors and unknown fields before `automation/elastic apply`.

  automation/elastic queries [name-prefix ...]     e.g. `automation/elastic queries k8s_ ovr_`

Time-picker queries get ?_tstart / ?_tend = the last hour.  Prints rows returned per query; exit 1 on any error.
"""
import datetime
import json
import os
import pathlib
import sys
import urllib.request

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
QUERIES = ROOT / "elastic/terraform/dashboards/queries.yml"


def esql(url: str, key: str, query: str) -> tuple:
    body = {"query": query}
    if "?_tstart" in query or "?_tend" in query:
        end = datetime.datetime.now(datetime.UTC)
        start = end - datetime.timedelta(hours=1)
        body["params"] = [{"_tstart": start.isoformat()}, {"_tend": end.isoformat()}]
    req = urllib.request.Request(f"{url.rstrip('/')}/_query", data=json.dumps(body).encode(), method="POST",
                                 headers={"Authorization": f"ApiKey {key}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            j = json.load(r)
        return len(j.get("values", [])), [c["name"] for c in j.get("columns", [])], j.get("values", [])[:3]
    except urllib.error.HTTPError as e:
        reason = json.loads(e.read() or b"{}").get("error", {}).get("reason", str(e))
        raise RuntimeError(reason.replace("\n", " ")[:400]) from None


def main() -> int:
    url, key = os.environ.get("ELASTIC_ES_URL"), os.environ.get("ELASTIC_API_KEY")
    if not (url and key):
        print("ELASTIC_ES_URL / ELASTIC_API_KEY are not set (automation/elastic.env)", file=sys.stderr)
        return 1
    prefixes = sys.argv[1:]
    verbose = os.environ.get("VERBOSE") == "1"
    failed = 0
    for name, query in yaml.safe_load(QUERIES.read_text()).items():
        if prefixes and not name.startswith(tuple(prefixes)):
            continue
        try:
            n, cols, sample = esql(url, key, query)
            print(f"ok    {name:28} {n:4} rows  {', '.join(cols)}")
            if verbose:
                for row in sample:
                    print(f"        {row}")
        except RuntimeError as e:
            failed += 1
            print(f"FAIL  {name:28} {e}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
