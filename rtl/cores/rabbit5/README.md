# rabbit5 — our own timing-predictable RV32I core (v0)

A classic 5-stage, single-issue, in-order RV32I pipeline written to be **read,
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
| `hello` firmware in the SoC | PASS, 3958 cycles (CV32E40P: 3450, it has HW mul/div) | `make soc-sim CORE=rabbit5` |
| riscv-formal (37 instructions + reg, pc_fwd, pc_bwd, causal, unique, liveness, ill, cover) | **45/45 PASS** | `make formal` |
| Timing properties T1–T3 (ours, beyond riscv-formal) | PASS (BMC depth 24) + all covers reached | `make formal` |
| Gate-level smoke test (Yosys generic gates) | PASS, **same 3958 cycles** as RTL | `make gls-smoke CORE=rabbit5` |
| Verilator `-Wall` lint | clean | `make lint CORE=rabbit5` |
| Size (Yosys generic synthesis, core + adapter) | ≈ 10.9 k cells | `make gls-netlist CORE=rabbit5` |

Whole formal suite: ~35 s on a 22-core machine.

## Reading order (≈ 1,000 lines of RTL, comments included)

| # | File | Lines | What to understand |
|---|---|---|---|
| 1 | `rabbit5_pkg.sv` | ~110 | opcodes, ALU ops, the `decoded_t` struct, CSR numbers |
| 2 | `rabbit5_alu.sv` | ~30 | nothing surprising — good warm-up |
| 3 | `rabbit5_decoder.sv` | ~200 | 32 bits → `decoded_t`; what counts as *illegal* |
| 4 | `rabbit5_regfile.sv` | ~35 | why the write-first bypass removes one hazard |
| 5 | `rabbit5_core.sv` | ~500 | **the pipeline** — start with the TIMING RULES header |
| 6 | `rabbit5_csr.sv` | ~130 | machine-mode CSRs, trap entry, MRET |
| 7 | `../../../dv/formal/rabbit5/timing/rabbit5_timing_tb.sv` | ~170 | the timing properties T1–T3 |
| 8 | `../../../dv/formal/rabbit5/wrapper.sv`, `checks.cfg` | | how riscv-formal sees the core |

## The timing model (rules R1–R5, in `rabbit5_core.sv`)

1. **R1** one instruction retires per cycle, except:
2. **R2** load-use: 1 bubble if an instruction reads the register loaded by the instruction just before it;
3. **R3** every redirect (taken branch, JAL, JALR, MRET, trap) is decided in EX: exactly 2 bubbles, no prediction;
4. **R4** memory grants immediately and answers after exactly 1 cycle (scratchpad assumption);
5. **R5** nothing else stalls.

**Consequence (proven as T1):** the time between two consecutive retirements is
1, 2 or 3 cycles and depends only on those two instructions. For a straight-line
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

Things to verify yourself (good first exercises):
- [ ] Draw the pipeline diagram for `lw x1,0(x2); add x3,x1,x1` and check it against a waveform (`make soc-waves CORE=rabbit5`).
- [ ] Find where `stall` and `redirect` interact (`assign stall = load_use && !redirect`) and convince yourself why the order matters.
- [ ] Break something on purpose (e.g. swap the MEM/WB priority in `forward()`) and watch which formal check fails. We did this: only **`reg_ch0`** catches it — all 37 instruction checks still pass, because each instruction is correct *for the operands it was given*.

## Known limitations of v0

| Limitation | Planned |
|---|---|
| No interrupts (`irq_i` ignored), no debug module | M2: timer + external IRQ with a **bounded, proven** entry latency |
| Memory must be zero-wait (R4); no back-pressure | M4: TDM scratchpad arbiter → stall only in MEM (Patmos rule) |
| CSRs are not formally checked (riscv-formal `csrw`/`csrc_*` checks not enabled yet) | M2 |
| BMC proves properties up to a depth (24 cycles timing, 12–20 riscv-formal), not unbounded | try `mode prove` (k-induction) once stable |
| No M/C extensions (software mul/div) | later; a single-cycle multiplier keeps R1 intact |
| Register file not reset (x1..x31 start as X in gate-level sim) | fine for software that initialises registers |

## Ideas for your own properties (robotics / real time)

- **Loop timing:** for a given loop body, cycles per iteration is constant — express as "the gap pattern between retirements of a repeated PC sequence is periodic".
- **Interrupt latency (after M2):** from `irq_i` rising to the first handler instruction retiring ≤ K cycles, for all program states.
- **Memory slot predictability (T3 extended):** the data bus is used *only* in the cycle before retirement — the property the TDM arbiter of the dual core will rely on.
- **Dual core (M4):** core 0's T1 gaps are unchanged whatever core 1 executes.
