#!/usr/bin/env python3
"""Print PASS/FAIL per riscv-formal check and exit non-zero on any failure."""
import sys
from pathlib import Path

root = Path(sys.argv[1])
results = {}
for d in sorted(p for p in root.iterdir() if p.is_dir()):
    status = d / "status"
    results[d.name] = status.read_text().split()[0] if status.exists() else "MISSING"

bad = {k: v for k, v in results.items() if v not in ("PASS",)}
print(f"riscv-formal: {len(results) - len(bad)}/{len(results)} checks PASS")
for k, v in bad.items():
    print(f"  {v:8s} {k}   (trace: {root / k / 'engine_0'})")
sys.exit(1 if bad else 0)
