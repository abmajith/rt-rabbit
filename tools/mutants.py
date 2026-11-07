#!/usr/bin/env python3
"""Mutation tests: plant a known bug, check that verification catches it.

A check that never fails proves nothing. Each mutant below changes one line
of RTL in a throw-away copy of the repository (build/mutants/<name>/) and runs
the check that should catch it. The mutant is CAUGHT if that check fails.
The original tree is only read, never modified.

    tools/mutants.py              all mutants (about 30-60 min)
    tools/mutants.py --list       show them
    tools/mutants.py div0-sign r5-no-operand-refresh     selected ones
    tools/mutants.py --baseline   also run each check on the unmodified copy
                                  (it must PASS there, otherwise "caught"
                                  would mean nothing)
"""
import argparse
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
WORK = REPO / "build" / "mutants"

MULDIV = "rtl/cores/rabbit_common/rabbit_muldiv.sv"
EXECUTE = "rtl/cores/rabbit_common/rabbit_execute.sv"
R3 = "rtl/cores/rabbit3/rabbit3_core.sv"
R5 = "rtl/cores/rabbit5/rabbit5_core.sv"


def sby(task):
    """One task of the muldiv unit proof (exit code != 0 on FAIL)."""
    return {"cmd": ["sby", "-f", "muldiv.sby", task], "cwd": "dv/formal/rabbit/muldiv"}


def rvf(core, check):
    """One riscv-formal check; the verdict is read from its status file."""
    return {
        "cmd": ["make", f"CORE={core}", "check", f"C={check}"],
        "cwd": "dv/formal/rabbit",
        "status": f"dv/formal/rabbit/build/{core}/riscv-formal/cores/{core}/checks/{check}/status",
    }


MUTANTS = [
    # --- multiply/divide unit (seconds each) -----------------------------------
    dict(name="div0-sign", what="x/0: quotient sign fix-up not skipped",
         file=MULDIV, old="(a_neg != b_neg) && (b_i != '0)", new="(a_neg != b_neg)",
         check=sby("prove4")),
    dict(name="mulh-rs2-unsigned", what="MULH ignores the sign of rs2",
         file=MULDIV, old="assign b_signed = !op_i[1];", new="assign b_signed = 1'b0;",
         check=sby("bmc6")),
    dict(name="no-restart", what="an interrupted instruction does not restart",
         file=MULDIV, old="else if (!req_i || done_o)  cnt_q <= '0;",
         new="else if (done_o)  cnt_q <= '0;", check=sby("prove4")),
    dict(name="div-one-longer", what="divide takes one cycle more than declared",
         file=MULDIV, old="localparam int unsigned DIV_CYCLES = DIV_STEPS + 2;",
         new="localparam int unsigned DIV_CYCLES = DIV_STEPS + 3;", check=sby("lat32")),
    # --- pipelines (one riscv-formal check each, 1-15 min) ----------------------
    dict(name="intr-flag-lost", what="rvfi_intr cleared while an M instruction waits (the real bug found)",
         file=EXECUTE, old="else if (valid_i && !busy_o) intr_next_q <= 1'b0;",
         new="else if (valid_i) intr_next_q <= 1'b0;", check=rvf("rabbit5", "pc_fwd_ch0")),
    dict(name="r5-no-operand-refresh", what="rabbit5: EX does not keep the forwarded operands while it waits",
         file=R5, old="      ex_q.rs1_val <= ex_rs1;\n      ex_q.rs2_val <= ex_rs2;\n", new="",
         check=rvf("rabbit5", "reg_ch0")),
    dict(name="r3-fetch-while-busy", what="rabbit3: fetch continues while X waits",
         file=R3, old="assign fetch        = fetch_enable_i && (!sleep_q || wake) && !x_busy;",
         new="assign fetch        = fetch_enable_i && (!sleep_q || wake);",
         check=rvf("rabbit3", "pc_fwd_ch0")),
    dict(name="r3-no-hold-register", what="rabbit3: no instruction holding register while X waits",
         file=R3, old="assign x_instr = x_hold_q ? x_hold_instr_q : instr_rdata_i;",
         new="assign x_instr = instr_rdata_i;", check=rvf("rabbit3", "liveness_ch0")),
]


def make_copy(name):
    """Fresh copy of what the formal flows need, under build/mutants/<name>."""
    dst = (WORK / name).resolve()
    if WORK.resolve() not in dst.parents:            # never delete outside build/mutants
        sys.exit(f"refusing to use {dst}")
    if dst.exists():
        shutil.rmtree(dst)
    def ignore(folder, names):
        # build outputs only: build/, __pycache__/, and the SymbiYosys work
        # directories next to muldiv.sby (muldiv/, muldiv_<task>/), not the
        # testbench files muldiv_tb.sv / muldiv.sby
        skip = {"build", "__pycache__"}
        if Path(folder).name == "muldiv":
            skip |= {n for n in names
                     if (n == "muldiv" or n.startswith("muldiv_")) and (Path(folder) / n).is_dir()}
        return skip
    shutil.copytree(REPO / "rtl", dst / "rtl", ignore=ignore)
    shutil.copytree(REPO / "dv" / "formal" / "rabbit", dst / "dv" / "formal" / "rabbit", ignore=ignore)
    (dst / "third_party").mkdir()
    (dst / "third_party" / "riscv-formal").symlink_to(REPO / "third_party" / "riscv-formal")
    return dst


def run_check(root, check, log):
    """True if the check PASSES."""
    with open(log, "w") as f:
        rc = subprocess.run(check["cmd"], cwd=root / check["cwd"], stdout=f, stderr=subprocess.STDOUT).returncode
    if "status" in check:
        st = root / check["status"]
        return st.exists() and st.read_text().startswith("PASS")
    return rc == 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*", help="mutants to run (default: all)")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--baseline", action="store_true", help="also check the unmodified copy passes")
    args = ap.parse_args()

    if args.list:
        for m in MUTANTS:
            print(f"{m['name']:24} {m['what']}")
        return 0
    todo = [m for m in MUTANTS if not args.names or m["name"] in args.names]
    unknown = set(args.names) - {m["name"] for m in MUTANTS}
    if unknown:
        sys.exit(f"unknown mutant(s): {', '.join(sorted(unknown))} (see --list)")

    WORK.mkdir(parents=True, exist_ok=True)
    results = []
    for m in todo:
        t0 = time.time()
        root = make_copy(m["name"])
        base = None
        if args.baseline:
            base = run_check(root, m["check"], WORK / f"{m['name']}.baseline.log")
            make_copy(m["name"])                     # fresh copy for the mutant
        src = root / m["file"]
        text = src.read_text()
        if text.count(m["old"]) != 1:
            results.append((m, "NOT APPLIED (RTL changed?)", base, time.time() - t0))
            continue
        src.write_text(text.replace(m["old"], m["new"]))
        passed = run_check(root, m["check"], root / "mutant.log")
        verdict = "caught" if not passed else "MISSED"
        results.append((m, verdict, base, time.time() - t0))
        print(f"{m['name']:24} {verdict:8} ({time.time() - t0:5.0f} s)  log: {root / 'mutant.log'}", flush=True)

    print("\nmutant                   result    check                         baseline")
    bad = 0
    for m, verdict, base, _ in results:
        chk = " ".join(m["check"]["cmd"][-2:])
        b = "-" if base is None else ("pass" if base else "FAIL!")
        print(f"{m['name']:24} {verdict:9} {chk:29} {b}")
        bad += verdict != "caught" or base is False
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
