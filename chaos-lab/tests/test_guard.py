"""Guard self-test: the telemetry path and management plane must be refused; normal targets must pass.
Run: make test (no lab changes)."""
import sys

from chaoslab import eos, guard, k8s

REFUSED = [
    ("node otelcol", lambda: guard.check_node("otelcol")),
    ("node gnmic", lambda: guard.check_node("gnmic")),
    ("node kafka", lambda: guard.check_node("kafka")),
    ("unknown node", lambda: guard.check_node("dc9-leaf9")),
    ("eth0", lambda: guard.check_interface("dc1-k8s-wk2", "eth0")),
    ("Management1", lambda: guard.check_interface("dc1-leaf1", "Management1")),
    ("Ma1", lambda: guard.check_interface("dc1-leaf1", "Ma1")),
    ("mgmt prefix", lambda: guard.check_prefix("ip route 172.20.20.0/25 Null0")),
    ("mgmt host", lambda: guard.check_prefix("network 172.20.20.250/32")),
    ("management api", lambda: guard.check_eos_commands("dc1-leaf1", ["management api gnmi", "shutdown"])),
    ("mgmt interface cfg", lambda: guard.check_eos_commands("dc1-leaf1", ["interface Management1", "shutdown"])),
    ("MGMT vrf", lambda: guard.check_eos_commands("dc1-leaf1", ["ip route vrf MGMT 0.0.0.0/0 Null0"])),
    ("logging", lambda: guard.check_eos_commands("dc1-leaf1", ["logging host 10.0.0.1"])),
    ("eos on frr node", lambda: guard.check_eos_commands("wan1", ["interface eth1"])),
    ("target otelcol", lambda: guard.check_target("otelcol")),
    ("target mgmt if", lambda: guard.check_target("dc1-spine1:eth0")),
    ("namespace", lambda: guard.check_namespace("observability")),
]

ALLOWED = [
    ("leaf uplink", lambda: guard.check_eos_commands("dc1-leaf1", ["interface Ethernet1", "shutdown"])),
    ("fabric veth", lambda: guard.check_interface("dc1-spine2", "eth3")),
    ("hijack prefix", lambda: guard.check_prefix("ip route 192.0.2.10/32 203.0.113.66")),
    ("k8s target", lambda: guard.check_target("k8s:prod/web")),
    ("frr node", lambda: guard.check_node("wan1")),
    ("bgw wan bgp shut", lambda: guard.check_eos_commands("dc1-bgw1", [
        "router bgp 65100", "neighbor WAN-PEERS shutdown", "vrf PROD", "neighbor 10.255.10.1 shutdown"])),
    ("k8s scratch ns", lambda: guard.check_namespace(k8s.SCRATCH_NS)),
]

# Names that show up in telemetry (switch config, Kubernetes) must not say chaos: the agent is tested blind.
NEUTRAL = [
    ("eos snapshot prefix", eos.SNAPSHOT_PREFIX),
    ("k8s scratch namespace", k8s.SCRATCH_NS),
]


def main() -> None:
    bad = 0
    for name, fn in REFUSED:
        try:
            fn()
            print(f"FAIL  {name}: not refused")
            bad += 1
        except guard.Refused as e:
            print(f"ok    {name}: refused ({e})")
    for name, fn in ALLOWED:
        try:
            fn()
            print(f"ok    {name}: allowed")
        except guard.Refused as e:
            print(f"FAIL  {name}: refused ({e})")
            bad += 1
    for name, value in NEUTRAL:
        if "chaos" in value.lower():
            print(f"FAIL  {name}: '{value}' gives the test away")
            bad += 1
        else:
            print(f"ok    {name}: neutral ({value})")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
