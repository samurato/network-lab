"""Steady state, measured directly on the lab (never through telemetry or Elastic): chaos-lab must not depend
on the system the agent is diagnosing from, and must not touch it."""
import concurrent.futures
import json
import logging
import subprocess
import time

from chaoslab import config, eos

log = logging.getLogger("chaostoolkit")


def web_success(client: str = None, url: str = None, attempts: int = None, **_) -> float:
    """Share of requests from an Internet user that got the real app (HTTP 200, no hijack marker)."""
    p = config.targets()["probes"]
    client, url, attempts = client or p["client"], url or p["url"], int(attempts or p["attempts"])
    ok = 0
    for _ in range(attempts):
        r = subprocess.run(["docker", "exec", config.container(client), "wget", "-q", "-O", "-", "-T", "3", url],
                           capture_output=True, text=True, timeout=10)
        if r.returncode == 0 and p["hijack_marker"] not in r.stdout:
            ok += 1
    return ok / attempts


def http_body(client: str = None, url: str = None, **_) -> str:
    """Evidence: what an Internet user gets back."""
    p = config.targets()["probes"]
    r = subprocess.run(["docker", "exec", config.container(client or p["client"]), "wget", "-q", "-O", "-",
                        "-T", "3", url or p["url"]], capture_output=True, text=True, timeout=10)
    return (r.stdout or r.stderr).strip()[:300]


def _eos_peers(node: str) -> dict:
    out = {}
    ipv4, evpn = eos.call(node, ["show ip bgp summary vrf all", "show bgp evpn summary"])
    for res, af in ((ipv4, "ipv4"), (evpn, "evpn")):
        for vrf, v in res.get("vrfs", {}).items():
            for peer, p in v.get("peers", {}).items():
                out[f"{node} {vrf} {af} {peer}"] = p.get("peerState")
    return out


def _frr_peers(node: str) -> dict:
    raw = config.sh(["docker", "exec", config.container(node), "vtysh", "-c", "show bgp vrf all summary json"])
    out = {}
    for vrf, afs in json.loads(raw).items():
        for af, v in afs.items():
            if isinstance(v, dict):
                for peer, p in v.get("peers", {}).items():
                    out[f"{node} {vrf} {af} {peer}"] = p.get("state")
    return out


def bgp_sessions() -> dict:
    t = config.targets()
    sessions = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        jobs = [pool.submit(_eos_peers, n) for n in t["eos"]] + [pool.submit(_frr_peers, n) for n in t["frr"]]
        for j in jobs:
            sessions.update(j.result())
    return sessions


def bgp_not_established(**_) -> int:
    """Number of BGP sessions (switches + WAN, every VRF and address family) not Established."""
    down = sorted(k for k, s in bgp_sessions().items() if s != "Established")
    for k in down:
        log.info(f"chaoslab: BGP not established: {k}")
    return len(down)


def web_unready(namespace: str = None, deployment: str = None, **_) -> int:
    """Desired minus ready replicas of the web deployment."""
    w = config.targets()["probes"]["web"]
    out = config.sh(config.kubectl_argv() + ["-n", namespace or w["namespace"], "get", "deploy",
                                            deployment or w["deployment"], "-o", "json"])
    d = json.loads(out)
    return int(d["spec"].get("replicas", 0)) - int(d["status"].get("readyReplicas", 0))


def steady_state(**_) -> int:
    """Chaos Toolkit probe: number of failing health checks (tolerance 0)."""
    p = config.targets()["probes"]
    failing = []
    share = web_success()
    if share < float(p["min_success"]):
        failing.append(f"web from the Internet {share:.0%} < {float(p['min_success']):.0%}")
    down = bgp_not_established()
    if down:
        failing.append(f"{down} BGP session(s) not established")
    unready = web_unready()
    if unready > 0:
        failing.append(f"{unready} web replica(s) not ready")
    for f in failing:
        log.info(f"chaoslab: steady state: {f}")
    if not failing:
        log.info("chaoslab: steady state: healthy")
    return len(failing)


def wait_recovered(timeout: int) -> tuple[bool, float]:
    """After rollback: poll the steady state until healthy or timeout."""
    start = time.time()
    while True:
        try:
            if steady_state() == 0:
                return True, round(time.time() - start, 1)
        except Exception as e:
            log.info(f"chaoslab: steady state check error: {e}")
        if time.time() - start > timeout:
            return False, round(time.time() - start, 1)
        time.sleep(15)
