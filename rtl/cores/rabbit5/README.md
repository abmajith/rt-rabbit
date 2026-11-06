# rabbit5 — our own timing-predictable RV32IM core (v0)

A classic 5-stage, single-issue, in-order RV32IM pipeline written to be **read,
reviewed and modified**, with one research goal: *every instruction's timing is
known in advance and proven*. Plugs into the SoC through the same `rabbit_cpu`
contract as CV32E40P, so both run the same firmware and tests.

```
IF ──► ID ──► EX ──► MEM ──► WB
       │      │       │      └ load data arrives, register write, RVFI report
       │      │       └ data memory request
       │      └ ALU, branch decision, CSRs, traps  (commit point)
       └ decode, register read, load-use detection
```

## Status (2026-11-06)

| What | Result | Command |
|---|---|---|
| `hello` firmware in the SoC | PASS, 3471 cycles (RV32I: 3958; rabbit3: 2756, CV32E40P: 3450) | `make soc-sim CORE=rabbit5` |
| riscv-formal (45 instructions incl. M with ALTOPS + reg, pc_fwd, pc_bwd, causal, unique, liveness, ill, cover) | **53/53 PASS** | `make formal CORE=rabbit5` |
| M extension: multiply 2 cycles, divide 34, for any operands (R8, T1); unit proof of the arithmetic | PASS | `make formal CORE=rabbit5` |
| M self-test firmware (corner cases, random, timing, interrupt during divide) | PASS (same test on CV32E40P / rabbit3) | `make soc-sim CORE=rabbit5 PROG=muldiv` |
| Timing properties T1–T4 (ours, beyond riscv-formal) | PASS (BMC depth 24) + all covers reached | `make formal CORE=rabbit5` |
| Interrupts + WFI: properties I1–I4, W0–W2; latency ≤ **7 cycles** (tight) | PASS + all covers reached | `make formal CORE=rabbit5` |
| Interrupt self-test firmware (same as on CV32E40P / rabbit3) | PASS, 9025 cycles | `make soc-sim CORE=rabbit5 PROG=irq` |
| Gate-level smoke test (Yosys generic gates) | PASS, **same cycles** as RTL (hello 3471, irq 9025, muldiv) | `make gls-smoke CORE=rabbit5` |
| Verilator `-Wall` lint | clean | `make lint CORE=rabbit5` |
| Size, sky130 (`synth -booth` + ABC, core + adapter) | 126.5 k µm² (RV32I: 95.4 k; CV32E40P: 170.3 k) | see `../rabbit_common/README.md` |

> Correction (2026-11-06): the first version of the timing testbench declared
> its free inputs with `(* anyseq *)`, which the slang frontend silently
> ignores — the instruction stream became a "don't care" constant instead of a
> real input, so the first T1–T3 "PASS" was weaker than claimed. Found while
> bringing up rabbit3 (an impossible counterexample); fixed by making the free
> values top-level inputs, then re-proven and re-mutation-tested on both cores.

## Reading order

Read **rabbit3 first** (`../rabbit3/README.md`): same blocks, simpler pipeline.
Then:

| # | File | Lines | What to understand |
|---|---|---|---|
| 1 | `../rabbit_common/` (see its README) | ~800 | the shared blocks: decode, ALU, regfile, CSRs, `rabbit_execute`, RVFI |
| 2 | `rabbit5_core.sv` | ~280 | **the pipeline only** — start with the TIMING RULES header; compare with `rabbit3_core.sv` |
| 3 | `../../../dv/formal/rabbit/timing/rabbit_timing_tb.sv` | ~170 | the timing properties T1–T3 (same file for every core) |
| 4 | `../../../dv/formal/rabbit/wrapper.sv`, `checks.cfg` | | how riscv-formal sees the core |

## The timing model (rules R1–R7, in `rabbit5_core.sv`)

1. **R1** one instruction retires per cycle, except:
2. **R2** load-use: 1 bubble if an instruction reads the register loaded by the instruction just before it;
3. **R3** every redirect (taken branch, JAL, JALR, MRET, trap) is decided in EX: exactly 2 bubbles, no prediction;
4. **R4** memory grants immediately and answers after exactly 1 cycle (scratchpad assumption);
5. **R5** nothing else stalls, except WFI sleep;
6. **R6** an interrupt is taken in EX on the instruction there (it does not retire; MRET runs it later): latency ≤ 7 cycles;
7. **R7** WFI = redirect to pc+4, then sleep until an enabled interrupt is pending (`core_sleep_o`);
8. **R8** MUL* stay 2 cycles in EX, DIV*/REM* 34, whatever the operands; IF/ID wait (no fetch), MEM/WB drain. An interrupt abandons the multiply/divide (it runs again after MRET), so the 7-cycle latency holds.

Interrupt latency, counted from the cycle an enabled interrupt becomes pending
to the retirement of the handler's first instruction: 5 cycles if EX holds an
instruction, up to 7 if EX holds a redirect bubble or the core was asleep
(rabbit3: 3 / 4).

**Consequence (proven as T1):** the time between two consecutive retirements is
1, 2 or 3 cycles (+1 / +33 for M instructions) and depends only on those two
instructions. For a straight-line
or loop path you can compute the cycle count by hand — that is what makes WCET
analysis trivial for this core.

## Review checklist — what is worth a second pair of eyes

Design choices you may want to change:
- [ ] **Branches resolved in EX (2-cycle penalty).** Resolving JAL in ID would save 1 cycle on every call/jump but makes the timing rule depend on instruction type in two places. Trade-off: speed vs. simplicity of the timing model.
- [ ] **No branch prediction** — deliberate (predictors make timing history-dependent).
- [ ] **Load data arrives in WB, forwarded to EX from WB** — keeps the load-use penalty at 1.
- [ ] **All pipeline registers have an asynchronous reset** — costs area, removes X in simulation/GLS.
- [ ] **`minstret` counts at EX (commit point)**, so a CSR read sees all older instructions.
- [ ] Misaligned loads/stores **trap** (cause 4/6) rather than being split into two accesses.
- [ ] **M instructions wait in EX** (R8). While they wait, `ex_q` keeps the instruction but stores the *forwarded* operand values: the older instructions it forwarded from leave MEM/WB meanwhile, and the muldiv unit needs the same operands every cycle (proven: M0). Try removing those two lines and see which check fails.

Things to verify yourself (good first exercises):
- [ ] Draw the pipeline diagram for `lw x1,0(x2); add x3,x1,x1` and check it against a waveform (`make soc-waves CORE=rabbit5`).
- [ ] Find where `stall` and `redirect` interact (`assign stall = load_use && !redirect`) and convince yourself why the order matters.
- [ ] Break something on purpose (e.g. swap the MEM/WB priority in `forward()`) and watch which formal check fails (`make formal CORE=rabbit5`). We did this: only **`reg_ch0`** catches it — all 37 instruction checks still pass, because each instruction is correct *for the operands it was given*.

## Known limitations of v0

| Limitation | Planned |
|---|---|
| No debug module | later |
| Memory must be zero-wait (R4); no back-pressure | M4: TDM scratchpad arbiter → stall only in MEM (Patmos rule) |
| CSRs are not formally checked (riscv-formal `csrw`/`csrc_*` checks not enabled yet) | M2 |
| BMC proves properties up to a depth (24 cycles timing, 12–20 riscv-formal), not unbounded | try `mode prove` (k-induction) once stable |
| No C extension | not planned for the RT core (code size vs. fetch simplicity) |
| An interrupt during a divide throws away up to 33 cycles of work | count it once per interrupt in WCET analysis |
| Register file not reset (x1..x31 start as X in gate-level sim) | fine for software that initialises registers |

## Ideas for your own properties (robotics / real time)

- **Loop timing:** for a given loop body, cycles per iteration is constant — express as "the gap pattern between retirements of a repeated PC sequence is periodic".
- **Interrupt latency** is done (I1). Next step: a bound on the *whole* handler entry including the C prologue, or "two interrupts in a row: the second is never starved".
- **Memory slot predictability (T3 extended):** the data bus is used *only* in the cycle before retirement — the property the TDM arbiter of the dual core will rely on.
- **Dual core (M4):** core 0's T1 gaps are unchanged whatever core 1 executes.
