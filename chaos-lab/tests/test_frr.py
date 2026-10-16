"""vtysh output check: real errors fail an injection, the 'no changes' note does not.
Run: make test (no lab changes)."""
import sys

from chaoslab import frr

NOTE = "% Configuration applied with notes:\nNo changes found to be committed!\n"
CASES = [
    ("empty", "", False),
    ("no-changes note", NOTE, False),
    ("unknown command", "% Unknown command: netwrk 192.0.2.10/32\n", True),
    ("note plus error", NOTE + "% Invalid input detected\n", True),
]

failed = 0
for name, out, want in CASES:
    got = bool(frr.errors(out))
    print(f"{'ok  ' if got == want else 'FAIL'} {name}: error={got}")
    failed += got != want

# Rollback after a redeploy already removed the fault: nothing left, so "already gone" is a success.
HIJACK = ["vrf PROD", "ip route 192.0.2.10/32 203.0.113.66", "exit-vrf", "router bgp 64901 vrf PROD",
          "address-family ipv4 unicast", "network 192.0.2.10/32"]
CLEAN = "vrf PROD\n ip route 0.0.0.0/0 203.0.113.1\nexit-vrf\nrouter bgp 64901 vrf PROD\n address-family ipv4 unicast\n  network 198.51.100.0/24\n"
LEFT = CLEAN + "  network 192.0.2.10/32\n"
for name, running, want in [("fault already gone", CLEAN, []), ("fault still there", LEFT, ["network 192.0.2.10/32"])]:
    got = frr.still_present(HIJACK, running)
    print(f"{'ok  ' if got == want else 'FAIL'} {name}: still={got}")
    failed += got != want
sys.exit(1 if failed else 0)
