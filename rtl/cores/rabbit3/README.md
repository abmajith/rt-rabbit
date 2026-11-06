# rabbit3 — 3-stage RV32I core (start here)

The smallest rabbit pipeline: **F | X | W**. It is built from exactly the same
blocks as rabbit5 (`../rabbit_common/`); only the pipeline file differs.
Read this core first, then rabbit5, and compare.

```
F ──► X ──────────────────────────────────► W
      decode, register read, execute,       load data arrives,
      data request (commit point)           register write, RVFI
```

## Learning path

| Step | Read | Ask yourself |
|---|---|---|
| 1 | `../rabbit_common/README.md` | which blocks exist and what each one does |
| 2 | `../rabbit_common/rabbit_pkg.sv` | what is in `decoded_t` and `exec_t`? |
| 3 | `rabbit3_core.sv` (≈200 lines) | how does one instruction move F → X → W? |
| 4 | `../rabbit_common/rabbit_regfile.sv` | why does the write-first bypass make forwarding unnecessary here? |
| 5 | `../rabbit_common/rabbit_execute.sv` | where are branches decided, where do traps come from? |
| 6 | `../rabbit5/rabbit5_core.sv` | what had to be *added* for two more stages: hold register, load-use stall, forwarding |
| 7 | interrupts: `rabbit_csr.sv` (mie, mip, enables) → `rabbit_execute.sv` (`irq_take`) → `rabbit3_core.sv` (`sleep_q`) | why can the interrupted instruction simply be dropped? (hint: X is the commit point) |
| 8 | `sw/baremetal/irq/main.c` | a timer-driven control loop with WFI, as a robot would run it |

Then run both and look at the difference:

```bash
make soc-sim   CORE=rabbit3            # hello: 3145 cycles
make soc-sim   CORE=rabbit5            # hello: 3958 cycles
make soc-sim   CORE=rabbit3 PROG=irq   # interrupt self-test (also rabbit5, cv32e40p)
make soc-waves CORE=rabbit3            # waveform: dv/cocotb/soc/dump.fst
make formal    CORE=rabbit3            # riscv-formal 45/45 + timing properties
make gls-smoke CORE=rabbit3            # same firmware on the gate netlist
```

## Timing rules (`rabbit3_core.sv`), proven by `dv/formal/rabbit/timing`

| | rabbit3 | rabbit5 |
|---|---|---|
| First instruction retires | cycle 3 | cycle 5 |
| Normal | 1 per cycle | 1 per cycle |
| Load followed by a user of the loaded register | **no penalty** | 1 bubble |
| Taken branch / jump / MRET / trap / WFI | **1 bubble** | 2 bubbles |
| Gap between two retirements | 1 or 2 (+ sleep) | 1, 2 or 3 |
| Interrupts (timer, external, 16 fast lines): worst-case latency, proven and reached | **4 cycles** | 7 cycles |
| WFI sleep (`core_sleep_o` for clock gating) | yes, fetch restarts in the cycle the interrupt appears | same |
| `hello` (RV32I, software mul/div) | 3145 cycles | 3958 cycles |
| Size (Yosys generic gates, incl. adapter) | 10.4 k cells | 11.5 k cells |
| Longest combinational path (qualitative) | memory → load align → register bypass → ALU → data address | one stage of that |

So rabbit3 needs fewer cycles, but each cycle must be longer. Which one is
faster in *time* is decided by the clock frequency each reaches on a real PDK
(sky130 / IHP) — a good first experiment with OpenROAD later.

## Interrupts (how they work in rabbit3)

```
irq_i ──► mip ──AND── mie ──► "wake" ──AND── mstatus.MIE ──► "pending"
  (lines)   (asking)  (allowed per line)  (ends WFI)  (global)      │
                                                                     ▼
      X stage: if a valid instruction is in X and an interrupt is pending,
      that instruction is NOT executed: mepc = its pc, mcause = line,
      MIE := 0, redirect to mtvec (+ 4*line in vectored mode).
      The instruction in W is older and finishes normally.
```

- Same line numbers, priorities and vector table as CV32E40P, so the same
  firmware (`sw/baremetal/irq`) runs on both — CV32E40P is the reference.
- Latency, counted from the cycle an enabled interrupt becomes pending to the
  cycle the handler's first instruction retires: 3 cycles normally, 4 if X
  holds a bubble (just after a jump) or the core was asleep. Proven by I1 in
  `dv/formal/rabbit/timing`; the cover shows 4 really happens.
- Lines are level-sensitive: the handler clears the source (write to the
  peripheral). `irq_ack_o` of the port contract is not used.
- The interrupt lines go into X without a register (lowest latency). In a
  real chip they must come from flip-flops in the same clock domain.

## What is shared, what is not

| | Shared (`rabbit_common`) | rabbit3 only |
|---|---|---|
| Decode, ALU, branch decision, CSRs, traps, next pc | ✔ `rabbit_execute`, `rabbit_decoder` | |
| Register file | ✔ `rabbit_regfile` | |
| RVFI reporting | ✔ `rabbit_rvfi` | |
| Load/store byte lanes and sign extension | ✔ functions in `rabbit_pkg` | |
| Fetch, when the PC moves, what is a bubble | | ✔ `rabbit3_core.sv` |
| Where the data request leaves (X) and the load data returns (W) | | ✔ |

## Things to try (exercises)

- Change one line so that a redirect is decided one stage later and watch the
  timing proof fail. Then update `core.mk` (`TIMING_REDIRECT_GAP`) and watch
  it pass again — the declared timing model is the spec.
- Remove the bypass in `rabbit_regfile.sv` (always return `regs[addr]`): which
  riscv-formal check fails, and why for rabbit3 *and* rabbit5?
