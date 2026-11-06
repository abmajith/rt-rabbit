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

Then run both and look at the difference:

```bash
make soc-sim   CORE=rabbit3            # hello: 3145 cycles
make soc-sim   CORE=rabbit5            # hello: 3958 cycles
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
| Taken branch / jump / MRET / trap | **1 bubble** | 2 bubbles |
| Gap between two retirements | 1 or 2 | 1, 2 or 3 |
| `hello` (RV32I, software mul/div) | 3145 cycles | 3958 cycles |
| Size (Yosys generic gates, incl. adapter) | 10.3 k cells | 11.1 k cells |
| Longest combinational path (qualitative) | memory → load align → register bypass → ALU → data address | one stage of that |

So rabbit3 needs fewer cycles, but each cycle must be longer. Which one is
faster in *time* is decided by the clock frequency each reaches on a real PDK
(sky130 / IHP) — a good first experiment with OpenROAD later.

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
