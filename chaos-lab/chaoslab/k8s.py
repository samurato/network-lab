"""Kubernetes faults through kubectl from outside the cluster. Nothing is installed in the cluster: a fault is
either self-healing (pod delete), undone by an inverse (uncordon, scale back, the previous image), or a transient
object in a throwaway namespace that rollback deletes. Names visible in Kubernetes telemetry are neutral: nothing
says chaos."""
import json
import random
import subprocess

from chaoslab import config, guard, state

SCRATCH_NS = "batch-jobs"     # throwaway namespace for transient pods (k8s-05); rollback deletes it


def kubectl(*args, input: str = None, check: bool = True) -> str:
    return config.sh(config.kubectl_argv() + list(args), input=input, check=check)


def _pods(namespace: str, selector: str, nodes: list = None) -> list:
    items = json.loads(kubectl("-n", namespace, "get", "pods", "-l", selector, "-o", "json"))["items"]
    pods = [(p["metadata"]["name"], p["spec"].get("nodeName")) for p in items
            if p["metadata"].get("deletionTimestamp") is None]
    if nodes:
        pods = [p for p in pods if p[1] in nodes]
    return pods


def delete_pods(namespace: str, selector: str, count: int = 1, nodes: list = None, **_) -> str:
    """Chaos Toolkit action: delete `count` random matching pods (0 = all), optionally only on `nodes`."""
    guard.check_namespace(namespace)
    for n in nodes or []:
        guard.check_node(n)
    pods = _pods(namespace, selector, nodes)
    if not pods:
        raise RuntimeError(f"no pods match {namespace}/{selector} on {nodes or 'any node'}")
    chosen = pods if int(count) == 0 else random.sample(pods, min(int(count), len(pods)))
    names = [p[0] for p in chosen]
    what = f"delete pods {namespace}/{','.join(names)} (on {','.join(sorted({p[1] for p in chosen}))})"
    state.register({"kind": "note"}, what)
    kubectl("-n", namespace, "delete", "pod", "--wait=false", *names)
    return what


def cordon(nodes: list, **_) -> str:
    """Chaos Toolkit action: cordon nodes (no new pods there); rollback uncordons."""
    for n in nodes:
        guard.check_node(n)
    for n in nodes:
        state.register({"kind": "cmd", "argv": config.kubectl_argv() + ["uncordon", n]}, f"cordon {n}")
        kubectl("cordon", n)
    return f"cordoned {', '.join(nodes)}"


def scale(namespace: str, deployment: str, replicas: int, **_) -> str:
    """Chaos Toolkit action: scale a deployment; rollback restores the replica count it had."""
    guard.check_namespace(namespace)
    before = kubectl("-n", namespace, "get", "deploy", deployment, "-o", "jsonpath={.spec.replicas}").strip()
    what = f"scale {namespace}/{deployment} {before} -> {replicas}"
    state.register({"kind": "cmd", "argv": config.kubectl_argv() + [
        "-n", namespace, "scale", "deploy", deployment, f"--replicas={before}"]}, what)
    kubectl("-n", namespace, "scale", "deploy", deployment, f"--replicas={replicas}")
    return what


def set_image(namespace: str, deployment: str, image: str, container: str = None, strategy: str = None,
              **_) -> str:
    """Chaos Toolkit action: a bad deploy, a container image that cannot run (optionally with a new rollout
    strategy, e.g. Recreate, so no old pod survives). Rollback puts back the exact previous image and strategy:
    the pod template matches the old ReplicaSet again, which scales back up; then waits for the rollout."""
    guard.check_namespace(namespace)
    d = json.loads(kubectl("-n", namespace, "get", "deploy", deployment, "-o", "json"))
    containers = d["spec"]["template"]["spec"]["containers"]
    c = next((c for c in containers if c["name"] == container), None) if container else containers[0]
    if c is None:
        raise RuntimeError(f"{namespace}/{deployment} has no container {container}")
    before = {
        "spec": {
            "strategy": d["spec"].get("strategy", {}),
            "template": {"spec": {"containers": [{"name": c["name"], "image": c["image"]}]}},
        },
    }
    fault = {"spec": {"template": {"spec": {"containers": [{"name": c["name"], "image": image}]}}}}
    if strategy:
        fault["spec"]["strategy"] = {"type": strategy, "rollingUpdate": None}
    what = f"set image {namespace}/{deployment} {c['name']} {c['image']} -> {image}" + \
           (f", strategy {strategy}" if strategy else "")
    k = config.kubectl_argv() + ["-n", namespace]
    state.register({"kind": "cmds", "timeout": 240, "argvs": [
        k + ["patch", "deploy", deployment, "--type", "strategic", "-p", json.dumps(before)],
        k + ["rollout", "status", "deploy", deployment, "--timeout=180s"],
    ]}, what)
    kubectl("-n", namespace, "patch", "deploy", deployment, "--type", "strategic", "-p", json.dumps(fault))
    return what


def show(namespace: str, what: str = "pods", selector: str = None, **_) -> str:
    """Chaos Toolkit probe: evidence for the journal (read-only kubectl get)."""
    return kubectl("-n", namespace, "get", what, "-o", "wide", *(["-l", selector] if selector else []), check=False)


def stress(node: str, cpus: int = 4, memory_mb: int = 1024, image: str = "nicolaka/netshoot:v0.15", **_) -> str:
    """Chaos Toolkit action: a noisy neighbour pinned to `node` (CPU burn + memory), in a throwaway namespace."""
    guard.check_node(node)
    code = (
        "import multiprocessing, time\n"
        "def burn():\n"
        "    while True:\n"
        "        pass\n"
        f"for _ in range({int(cpus)}):\n"
        "    multiprocessing.Process(target=burn).start()\n"
        f"hog = bytearray({int(memory_mb)} * 1024 * 1024)\n"
        "time.sleep(10 ** 7)\n"
    )
    manifest = {
        "apiVersion": "v1",
        "kind": "List",
        "items": [
            {"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": SCRATCH_NS}},
            {
                "apiVersion": "v1",
                "kind": "Pod",
                "metadata": {"name": "report-worker", "namespace": SCRATCH_NS, "labels": {"app": "report-worker"}},
                "spec": {
                    "nodeName": node,
                    "restartPolicy": "Never",
                    "terminationGracePeriodSeconds": 0,
                    "containers": [
                        {
                            "name": "worker",
                            "image": image,
                            "imagePullPolicy": "IfNotPresent",
                            "command": ["python3", "-c", code],
                            "resources": {
                                "limits": {
                                    "cpu": str(int(cpus)),
                                    "memory": f"{int(memory_mb) + 256}Mi",
                                },
                            },
                        },
                    ],
                },
            },
        ],
    }
    what = f"stress pod {SCRATCH_NS}/report-worker on {node}: {cpus} CPUs, {memory_mb} MiB"
    state.register({"kind": "cmd", "argv": config.kubectl_argv() + [
        "delete", "namespace", SCRATCH_NS, "--wait=false", "--ignore-not-found"]}, what)
    kubectl("apply", "-f", "-", input=json.dumps(manifest))
    return what


def exec_background(namespace: str, target: str, command: list, stop: list, **_) -> str:
    """Chaos Toolkit action: start a command in an existing pod (e.g. an iperf3 client) without waiting;
    rollback runs `stop` in the same pod."""
    guard.check_namespace(namespace)
    what = f"{namespace}/{target}: {' '.join(command)}"
    state.register({"kind": "cmd", "argv": config.kubectl_argv() + [
        "-n", namespace, "exec", target, "--"] + stop}, what)
    log = open(config.STATE_DIR / "background.log", "a")
    subprocess.Popen(config.kubectl_argv() + ["-n", namespace, "exec", target, "--"] + command,
                     stdout=log, stderr=log, stdin=subprocess.DEVNULL, start_new_session=True)
    return what
