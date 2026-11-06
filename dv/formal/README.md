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
| **riscv-formal** (YosysHQ, submodule) | every RV32I instruction computes what the ISA says (37 checks), plus pipeline consistency: `reg` (forwarding/bypass), `pc_fwd`/`pc_bwd` (branches, flushes), `causal`, `unique`, `liveness`, `ill`, `cover`. The interrupt lines are free inputs, so all of this also holds with interrupts arriving at any time. | `rabbit/checks.cfg` (template), `rabbit/wrapper.sv` |
| **timing properties** (ours) | T1 exact retirement-gap model, T2 first retirement cycle, T3 memory used exactly one cycle before retirement, T4 wake-up from WFI; covers prove every case and the min/max throughput bounds are reachable | `rabbit/timing/rabbit_timing_tb.sv` |
| **interrupt + sleep properties** (ours, cores with `TIMING_IRQ_LATENCY` > 0) | I1 latency ≤ declared bound, I2 no spurious interrupt, I3 precise `mepc`, I4 correct `mcause`, I5 handler starts at the right vector; W0 sleep only after WFI, W1 wakes on an enabled interrupt, W2 nothing moves while asleep. All 32 interrupt lines free. | same file |

Each core **declares** its timing model in `rtl/cores/<core>/core.mk`
(`TIMING_FIRST_RETIRE`, `TIMING_REDIRECT_GAP`, `TIMING_LOADUSE_GAP`,
`TIMING_IRQ_LATENCY`, `TIMING_COMMIT_TO_RETIRE`); the same timing testbench
then proves the core matches its declaration.

The interrupt properties are checked against a small **spec model** inside the
testbench: it recomputes `mstatus.MIE/MPIE` and `mie` from the RVFI trace alone
(CSR writes, traps, MRET, interrupt entries), i.e. from what the ISA says, not
from the core's internal registers. Because a core changes CSRs in its commit
stage but reports at retirement, the testbench delays the core's interrupt and
sleep signals by `TIMING_COMMIT_TO_RETIRE - 1` cycles (rabbit3: 0, rabbit5: 1)
to compare like with like. Liveness is checked under the fairness
assumption "the core is not asleep" (`RISCV_FORMAL_FAIRNESS` in `wrapper.sv`);
that sleep ends when it must is W1.

| | rabbit3 | rabbit5 |
|---|---|---|
| riscv-formal (interrupt lines 7 and 16 free) | 45/45 PASS, ~3 min | 45/45 PASS, ~30 s |
| timing T1–T4, I1–I5, W0–W2 + 14 covers | PASS, ~15 min | PASS, ~18 min |
| proven worst-case interrupt latency (cover: reached) | 4 cycles | 7 cycles |

riscv-formal gets only two free interrupt lines: with all 32 free, rabbit3's
`reg` check ran > 20 min (with two: under 3 min). Which line fires does not
change what riscv-formal checks; lines, priorities' legality, vectors and
causes are covered with all 32 lines by I4/I5 and by the `irq` firmware test
(priority order, compared against CV32E40P).

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
| rabbit3 checked against IRQ_LATENCY=3 | I1 |
| interrupt: `mepc` = pc+4 instead of pc (not precise) | I3 (riscv-formal skips pc checks at `rvfi_intr`) |
| interrupt: per-line `mie` ignored | W2 |
| WFI wakes only if `mstatus.MIE` = 1 (spec: any enabled line) | W1 |
| fetch does not restart on wake (rabbit3 and rabbit5) | T4 |
| vectored `mtvec` ignored (always jump to the base) | I5 |
| rabbit5 checked against IRQ_LATENCY=6 | I1 |
| rabbit5: `stall = load_use` without `&& !redirect` | nothing — an *equivalent* mutant: every user of `stall` already gives `redirect` priority, so the term is redundant |

### Lesson learned: free inputs must be real inputs

`(* anyseq *)` on an internal signal is **silently ignored by the slang
frontend**; the signal becomes a constant `x`, which the solver may choose
differently at every place it is used — the decoder can then "see" a different
instruction than the pipeline register stores. The timing testbench therefore
takes the instruction word and load data as **top-level inputs**. The first
rabbit5 timing result (before 2026-11-06) had this flaw and was re-proven.

## Planned

- riscv-formal CSR checks (`csrw`, `csrc_*`): need the `rvfi_csr_*` ports.
- SymbiYosys properties for the OBI bus and the SoC address decode.
- Dual core (M4): TDM arbiter bound (n+1 cycles) and per-core timing independence.
