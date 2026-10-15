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
sys.exit(1 if failed else 0)
