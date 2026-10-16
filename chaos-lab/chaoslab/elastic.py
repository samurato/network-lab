"""Read-only Elastic client for chaos-lab, with the lab key: ES|QL over the telemetry, for the detection
scorecard. chaos-lab never writes to Elastic (runs, scorecards and ground truth stay in ~/clab-runs/chaos), so
nothing in the project tells an agent that a fault is a test. Nothing here touches the telemetry pipeline:
gnmic, the collector and Kafka are not involved.

Credentials, environment first, then the git-ignored automation/elastic.env, then the copy the lab bundle holds
for the collector (never in git):
  ELASTIC_ES_URL     Elasticsearch endpoint
  ELASTIC_API_KEY    the lab key
"""
import functools
import json
import os
import re

import requests

from chaoslab import config


@functools.cache
def _settings() -> dict:
    s = {}
    path = (config.ROOT / config.targets()["elastic"]["env_file"]).resolve()
    if path.exists():
        for line in path.read_text().splitlines():
            m = re.match(r"^(ELASTIC_[A-Z_]+)=(.*)$", line.strip())
            if m:
                s[m.group(1)] = m.group(2).strip().strip("'\"")
    for k, v in os.environ.items():
        if k.startswith("ELASTIC_") and v:
            s[k] = v
    bundle = os.path.expanduser(config.targets()["elastic"]["secrets_dir"])
    for name, key in (("es_url", "BUNDLE_ES_URL"), ("api_key", "BUNDLE_API_KEY")):
        try:
            with open(os.path.join(bundle, name)) as f:
                s[key] = f.read().strip()
        except OSError:
            pass
    return s


def _url() -> str:
    s = _settings()
    url = s.get("ELASTIC_ES_URL") or s.get("BUNDLE_ES_URL")
    if not url:
        raise RuntimeError("no Elasticsearch URL (ELASTIC_ES_URL)")
    return url.rstrip("/")


def available() -> bool:
    s = _settings()
    return bool((s.get("ELASTIC_API_KEY") or s.get("BUNDLE_API_KEY"))
                and (s.get("ELASTIC_ES_URL") or s.get("BUNDLE_ES_URL")))



def _headers() -> dict:
    s = _settings()
    key = s.get("ELASTIC_API_KEY") or s.get("BUNDLE_API_KEY")
    if not key:
        raise RuntimeError("no Elastic API key (ELASTIC_API_KEY)")
    return {"Authorization": f"ApiKey {key}"}


def esql(query: str, **params) -> list[dict]:
    body = {"query": query}
    if params:
        body["params"] = [{k: v} for k, v in params.items()]
    r = requests.post(f"{_url()}/_query", json=body, headers=_headers(), timeout=60)
    if r.status_code != 200:
        raise RuntimeError(f"ES|QL {r.status_code}: {r.json().get('error', {}).get('reason', r.text)[:300]}")
    j = r.json()
    cols = [c["name"] for c in j["columns"]]
    return [dict(zip(cols, row)) for row in j["values"]]

