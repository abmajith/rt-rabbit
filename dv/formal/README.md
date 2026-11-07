# dv/formal — formal verification

## rabbit cores (rabbit3, rabbit5)

One flow for every rabbit configuration (`configs/`), selected with
`CONFIG=` (`CORE=rabbit3` is short for `CONFIG=rabbit3`):

```bash
make formal CORE=rabbit3                       # from the repo root: everything below
make formal CONFIG=rabbit3_rv32i               # the same core without M (proves MUL/DIV trap: X1)
make -C dv/formal/rabbit CORE=rabbit5 riscv-formal
make -C dv/formal/rabbit CORE=rabbit5 timing
make -C dv/formal/rabbit muldiv                               # multiply/divide unit (any core)
make -C dv/formal/rabbit CORE=rabbit3 check C=insn_add_ch0    # one check
```

| Part | What it proves | Files |
|---|---|---|
| **riscv-formal** (YosysHQ, submodule) | every RV32IM instruction computes what the ISA says (45 checks; MUL/DIV with ALTOPS stand-in results, see below), plus pipeline consistency: `reg` (forwarding/bypass), `pc_fwd`/`pc_bwd` (branches, flushes), `causal`, `unique`, `liveness`, `ill`, `cover`. The interrupt lines are free inputs, so all of this also holds with interrupts arriving at any time. | `rabbit/checks.cfg` (template), `rabbit/wrapper.sv` |
| **timing properties** (ours) | T1 exact retirement-gap model, T2 first retirement cycle, T3 memory used exactly one cycle before retirement, T4 wake-up from WFI; covers prove every case and the min/max throughput bounds are reachable | `rabbit/timing/rabbit_timing_tb.sv` |
| **M extension properties** (ours) | T1/T2 include R8 (MUL* exactly +1 cycle, DIV* exactly +DIV_CYCLES−1, whatever the operands); M0 operands do not change while an M instruction waits; M1 (cover) an interrupt is taken while one waits; M2 no instruction fetch while one waits | `rabbit/timing/rabbit_timing_tb.sv` |
| **multiply/divide unit** (ours) | A1 every result equals the RISC-V definition, L1 exact latency, under any interrupt pattern: every input at W = 4 (unbounded, PDR) and W = 6 (BMC 20), all 524 288 instructions at W = 8 (exhaustive simulation), latency at W = 32 (unbounded) | `rabbit/muldiv/` |
| **interrupt + sleep properties** (ours, cores with `TIMING_IRQ_LATENCY` > 0) | I1 latency ≤ declared bound (+ the M extra cycles if the handler's first instruction is itself MUL/DIV), I2 no spurious interrupt, I3 precise `mepc`, I4 correct `mcause`, I5 handler starts at the right vector; W0 sleep only after WFI, W1 wakes on an enabled interrupt, W2 nothing moves while asleep. All 32 interrupt lines free. | same file |

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
| riscv-formal RV32IM (interrupt lines 7 and 16 free) | 53/53 PASS, ~10 min | 53/53 PASS, ~1 min |
| timing T1–T4, I1–I5, W0–W2, M0–M2 + covers | PASS, ~35 min | PASS, ~22 min |
| muldiv unit proof + exhaustive 8-bit simulation (shared) | PASS, ~1 min | (same) |
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
configured depth (12–26 cycles for riscv-formal, 24 for timing), not for
unbounded time (except the muldiv tasks run with PDR, which are unbounded).

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
| muldiv: x/0 sign rule removed | unit proof A1 (W = 4) + exhaustive simulation |
| muldiv: MULH ignores the sign of rs2 | unit proof A1 (W = 6) + exhaustive simulation |
| muldiv: no restart after an interrupt | unit proof L1 + exhaustive simulation |
| muldiv: divide one cycle longer | unit proof L1 (W = 32) |
| `rvfi_intr` cleared while an M instruction waits (real bug, fixed) | riscv-formal `pc_fwd` |
| rabbit5: forwarded operands not stored while EX waits | M0 + riscv-formal `reg` |
| rabbit3: fetch continues while an M instruction waits | M2 + riscv-formal `pc_fwd` |
| rabbit3: no instruction holding register while X waits | M0 + riscv-formal `liveness` |

### M extension: how multiply and divide are verified

SAT/SMT solvers cannot prove two different 32-bit multipliers equal (the
problem blows up beyond ~8 bits: boolector needed > 10 min to reach step 14
at W = 8). So the work is split:

1. **riscv-formal with ALTOPS** checks everything *around* the arithmetic:
   decode, operand forwarding, the pipeline holding the instruction, register
   write-back, interrupts during a wait. With `RISCV_FORMAL_ALTOPS` the core
   returns stand-in results ((rs1 ± rs2) XOR a constant) with the same timing.
   The real multiplier is then unused and optimised away, so the proofs stay
   fast. A divide takes 34 cycles, which does not fit the proof depth, so
   these proofs use a 2-step divider (`FORMAL_DIV_STEPS`, `core.mk`): the
   pipeline only ever sees `busy`/`done`, never the step count.
2. **The unit proof** (`muldiv/`) checks the real arithmetic and the real
   latency on the very same RTL, which is written for any width W. Exact
   latency (34 cycles at 32 bits) is a counter property and is proven at full
   width, for any length of history.
3. **Simulation**: `sw/baremetal/muldiv` runs corner cases and random 32-bit
   operands on every core, and checks that the timing does not depend on the
   data.

Found by this flow while adding M: the "first instruction of the handler"
flag (`rvfi_intr`) was lost when that instruction was itself a multiply or
divide (pc_fwd); the liveness window had to grow because an interrupted
divide followed by a handler that starts with a divide is legal but slow;
and I1 had to say what latency means when the handler's first instruction
is itself a MUL/DIV (it is *taken* within the bound, then runs normally).

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
