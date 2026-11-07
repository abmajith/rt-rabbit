#!/usr/bin/env python3
"""Summarise an ORFS run of one core: minimum clock period per path class.

The constraint gives the memory 20 % of the period on each side (see
constraint.sdc), so a path from an input to a register (or a register to an
output) has 0.8 T available, an input-to-output path 0.6 T, a register-to-
register path T. From the worst slack s at the target period T the smallest
period that path class allows is about T - s / share.
    asic/orfs/summary.py <work dir> <core> <period ns> [platform]
"""
import os, re, subprocess, sys
from pathlib import Path

work, core, period = Path(sys.argv[1]).resolve(), sys.argv[2], float(sys.argv[3])
platform = sys.argv[4] if len(sys.argv) > 4 else "sky130hd"
repo = Path(__file__).resolve().parents[2]
image = os.environ.get("ORFS_IMAGE", "openroad/orfs@sha256:8b4f3942318d740ea1f73f4f895bbac150b32e41eb3b7baf7722adec6538bbcf")
libs = {"sky130hd": "/OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib",
        "ihp-sg13g2": "/OpenROAD-flow-scripts/flow/platforms/ihp-sg13g2/lib/sg13g2_stdcell_typ_1p20V_25C.lib"}

cmd = ["docker", "run", "--rm", "-u", f"{os.getuid()}:{os.getgid()}", "-v", f"{repo}:{repo}",
       "-e", f"WORK={work}", "-e", f"CORE={core}", "-e", f"PLATFORM={platform}", "-e", f"LIB={libs[platform]}",
       image, "bash", "-c",
       f"cd /OpenROAD-flow-scripts && source env.sh >/dev/null 2>&1; openroad -no_init -exit {repo}/asic/orfs/summary.tcl"]
p = subprocess.run(cmd, capture_output=True, text=True)
out = p.stdout + p.stderr
(work / "summary.log").write_text(out)
r = dict(re.findall(r"^RESULT (\S+)\s+(\S+)$", out, re.M))
if "r2r" not in r:
    sys.exit(f"{core}: no results, see {work / 'summary.log'}")

m = re.search(r"^Total\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)", out, re.M)   # report_power: internal switching leakage total (W)
if m:
    r["power_w"] = m.group(4)
share = {"r2r": 1.0, "in2reg": 0.8, "reg2out": 0.8, "in2out": 0.6}
tmin = {k: (period - float(r[k]) / share[k]) if r.get(k, "none") != "none" else None for k in share}
worst = max(v for v in tmin.values() if v is not None)
limit = max((k for k in tmin if tmin[k] is not None), key=lambda k: tmin[k])
fmt = lambda v: "   -  " if v is None else f"{v:6.2f}"
print(f"{core:9} area {float(r['area']):9.0f} um2  min period (ns): "
      + "  ".join(f"{k} {fmt(tmin[k])}" for k in share)
      + f"  => {worst:5.2f} ns ({1000 / worst:5.1f} MHz, limited by {limit})"
      + (f"  power(vectorless) {float(r['power_w']) * 1e3:.2f} mW" if "power_w" in r else ""))
