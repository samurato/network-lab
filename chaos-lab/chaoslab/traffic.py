"""Background traffic generators (traffic.yml), started inside existing lab containers with docker exec.

  python -m chaoslab.traffic start [profile ...] [--dry]
  python -m chaoslab.traffic stop
  python -m chaoslab.traffic status

Each generator runs in a shell loop that restarts it after a fault breaks the connection, and every process
carries the marker in its command line, so stop kills exactly these processes and nothing else.
"""
import concurrent.futures
import json
import re
import subprocess
import sys

import yaml

from chaoslab import config, guard


def spec() -> dict:
    return yaml.safe_load((config.ROOT / "traffic.yml").read_text())


def _loop(marker: str, command: str) -> str:
    return f": {marker}; while true; do {command}; sleep 3; done"


def commands(profiles: list) -> list:
    """(node, shell command) to start, servers first."""
    s = spec()
    marker, port = s["marker"], s["iperf_port"]
    unknown = [p for p in profiles if p not in s["profiles"]]
    if unknown:
        raise SystemExit(f"unknown profile(s) {unknown}; known: {', '.join(s['profiles'])}")
    servers, clients = [], []
    for name in profiles:
        prof = s["profiles"][name]
        for f in prof.get("iperf", []):
            ip = s["hosts"][f["server"]]
            servers.append((f["server"], _loop(marker, f"iperf3 -s -p {port} -1 -T {marker}")))
            clients.append((f["client"], _loop(
                marker, f"iperf3 -c {ip} -p {port} -b {f['rate']} -t 0 --bidir -T {marker} >/dev/null 2>&1")))
        if "k6" in prof:
            k = prof["k6"]
            clients.append((k["node"], _loop(
                marker, f"RPS={k['rps']} k6 run --quiet --summary-mode=disabled --no-usage-report "
                        f"--tag run={marker} /generators/baseline.js >/dev/null 2>&1")))
    return servers + clients


def _check(node: str, command: str) -> None:
    guard.check_node(node)
    guard.check_prefix(command)


def running() -> dict:
    """node -> number of marked processes."""
    s = spec()
    nodes = set(s["hosts"]) | {p["k6"]["node"] for p in s["profiles"].values() if "k6" in p}
    out = {}
    for n in sorted(nodes):
        r = subprocess.run(["docker", "exec", config.container(n), "sh", "-c",
                            f"pgrep -f '{s['marker'][:-1]}[{s['marker'][-1]}]' | wc -l"],
                           capture_output=True, text=True, timeout=15)
        c = int(r.stdout.strip() or 0)
        if c:
            out[n] = c
    return out


def start(profiles: list, dry: bool = False) -> None:
    cmds = commands(profiles)
    for node, cmd in cmds:
        _check(node, cmd)
    if not dry:
        guard.check_load()
        busy = running()
        if busy:
            raise SystemExit(f"traffic already running on {', '.join(busy)}: `make traffic-stop` first")
    for node, cmd in cmds:
        print(f"{'would start' if dry else 'start'}  {node:14} {cmd.split('; ', 1)[1]}")
        if not dry:
            config.sh(["docker", "exec", "-d", config.container(node), "sh", "-c", cmd])
    if not dry:
        print(f"traffic running: {', '.join(profiles)}. Stop with `make traffic-stop`.")


def stop() -> None:
    s = spec()
    pattern = f"{s['marker'][:-1]}[{s['marker'][-1]}]"     # the [x] keeps pkill's own shell from matching
    busy = running()
    for n in busy:
        subprocess.run(["docker", "exec", config.container(n), "sh", "-c", f"pkill -f '{pattern}'; true"],
                       capture_output=True, timeout=15)
        print(f"stopped {busy[n]} process(es) on {n}")
    if not busy:
        print("no traffic running")


def _ping(src: str, dst_ip: str) -> tuple:
    r = subprocess.run(["docker", "exec", config.container(src), "ping", "-c", "5", "-i", "0.2", "-W", "1", dst_ip],
                       capture_output=True, text=True, timeout=20)
    if "No such container" in r.stderr:
        return ("down", "-")
    loss = re.search(r"(\d+(?:\.\d+)?)% packet loss", r.stdout)
    avg = re.search(r"= [\d.]+/([\d.]+)/", r.stdout)
    return (loss.group(1) + "%" if loss else "?", avg.group(1) if avg else "-")


def status() -> None:
    s = spec()
    busy = running()
    print("traffic processes:", json.dumps(busy) if busy else "none")
    hosts = s["hosts"]
    pairs = [(a, b) for a in hosts for b in hosts if a != b]
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        res = dict(zip(pairs, pool.map(lambda p: _ping(p[0], hosts[p[1]]), pairs)))
    print("\nping matrix (loss / avg ms), 5 pings each:")
    names = list(hosts)
    print(" " * 14 + "".join(f"{n:>14}" for n in names))
    for a in names:
        row = "".join(f"{'-':>14}" if a == b else f"{res[(a, b)][0] + ' ' + res[(a, b)][1]:>14}" for b in names)
        print(f"{a:14}{row}")


def main() -> None:
    args = sys.argv[1:]
    dry = "--dry" in args
    args = [a for a in args if a != "--dry"]
    if not args:
        raise SystemExit(__doc__)
    if args[0] == "start":
        start(args[1:] or list(spec()["profiles"]), dry)
    elif args[0] == "stop":
        stop()
    elif args[0] == "status":
        status()
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
