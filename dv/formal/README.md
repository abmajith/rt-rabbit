# dv/formal — formal verification

## rabbit cores (rabbit3, rabbit5)

One flow for every rabbit core, selected with `CORE=`:

```bash
make formal CORE=rabbit3                       # from the repo root: everything below
make -C dv/formal/rabbit CORE=rabbit5 riscv-formal
make -C dv/formal/rabbit CORE=rabbit5 timing
make -C dv/formal/rabbit CORE=rabbit3 check C=insn_add_ch0    # one check
```

| Part | What it proves | Files |
|---|---|---|
| **riscv-formal** (YosysHQ, submodule) | every RV32I instruction computes what the ISA says (37 checks), plus pipeline consistency: `reg` (forwarding/bypass), `pc_fwd`/`pc_bwd` (branches, flushes), `causal`, `unique`, `liveness`, `ill`, `cover` | `rabbit/checks.cfg` (template), `rabbit/wrapper.sv` |
| **timing properties** (ours) | T1 exact retirement-gap model, T2 first retirement cycle, T3 memory used exactly one cycle before retirement; covers prove every case and the min/max throughput bounds are reachable | `rabbit/timing/rabbit_timing_tb.sv` |

Each core **declares** its timing model in `rtl/cores/<core>/core.mk`
(`TIMING_FIRST_RETIRE`, `TIMING_REDIRECT_GAP`, `TIMING_LOADUSE_GAP`); the same
timing testbench then proves the core matches its declaration.

| | rabbit3 | rabbit5 |
|---|---|---|
| riscv-formal | 45/45 PASS | 45/45 PASS |
| timing T1–T3 + covers | PASS | PASS |
| wall time, 22 cores | ~4 min (`reg`, `pc_fwd`, `pc_bwd` dominate) | ~30 s |

rabbit3 is *harder* to prove: its single X stage contains memory → bypass →
execute → data address as one cycle of logic, and the cross-instruction checks
(`reg`, `pc_fwd`, `pc_bwd`) must reason through all of it at every step.

How it fits together:
1. The cores are modern SystemVerilog. riscv-formal reads cores with Yosys'
   built-in parser, so the Makefile first converts the core with the **slang**
   frontend into one plain Verilog file (`build/<core>/core_flat.v`).
2. `genchecks.py` expects `<riscv-formal>/cores/<core>/`; the Makefile builds a
   small mirror in `build/<core>/` (symlinks to the submodule), so the
   submodule is never modified.
3. The timing proof reads the SystemVerilog directly through slang (≈10 s;
   the converted file made the solver ~60x slower).

Bounded proofs: all results hold for every instruction stream up to the
configured depth (12–20 cycles for riscv-formal, 24 for timing), not for
unbounded time.

### Mutation results (the checks are not vacuous)

| Planted bug | Caught by |
|---|---|
| rabbit5: forwarding priority MEM/WB swapped | only riscv-formal `reg_ch0` |
| rabbit5: stall on every EX dependency (not only loads) | timing T1 (riscv-formal passes) |
| rabbit3 checked against REDIRECT_GAP=3 / LOADUSE_GAP=2 | timing T1 + covers |
| rabbit5 checked against LOADUSE_GAP=1 | timing T1 + covers |

### Lesson learned: free inputs must be real inputs

`(* anyseq *)` on an internal signal is **silently ignored by the slang
frontend**; the signal becomes a constant `x`, which the solver may choose
differently at every place it is used — the decoder can then "see" a different
instruction than the pipeline register stores. The timing testbench therefore
takes the instruction word and load data as **top-level inputs**. The first
rabbit5 timing result (before 2026-11-06) had this flaw and was re-proven.

## Planned

- CSR checks (`csrw`, `csrc_*`) when interrupts land (M2).
- SymbiYosys properties for the OBI bus and the SoC address decode.
- Dual core (M4): TDM arbiter bound (n+1 cycles) and per-core timing independence.
