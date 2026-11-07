# rabbit_common — blocks shared by every rabbit core

Everything an instruction *does* lives here. A rabbit core
(`../rabbit3/rabbit3_core.sv`, `../rabbit5/rabbit5_core.sv`) only decides
*when* things happen: pipeline registers, bubbles, stalls and forwarding.

| File | Kind | What it does |
|---|---|---|
| `rabbit_pkg.sv` | package | opcodes, CSR numbers, cause codes; `decoded_t` (output of decode) and `exec_t` (output of execute); helper functions for branches and load/store byte lanes |
| `rabbit_decoder.sv` | combinational | 32 instruction bits → `decoded_t`; marks unsupported encodings as illegal |
| `rabbit_alu.sv` | combinational | the ten RV32I ALU operations |
| `rabbit_regfile.sv` | state | 31 × 32-bit registers (x0 = 0), 2 read ports, 1 write port, write-first bypass |
| `rabbit_csr.sv` | state | machine-mode CSRs, counters, trap entry, MRET, interrupt enables (`mie`, `mip`, `mstatus.MIE`) and priority |
| `rabbit_muldiv.sv` | small state | M extension: multiply (2 cycles) and divide (34 cycles), fixed latency, abandoned on an interrupt |
| `rabbit_execute.sv` | combinational + CSR state | ALU operands, branch/jump decision, exceptions, interrupts, WFI, CSR access, M instructions (`busy_o`), next pc → `exec_t` + redirect |
| `rabbit_rvfi.sv` | small state | turns the retiring `exec_t` into the RVFI port used by formal verification |

```
            instruction word
                   │
            rabbit_decoder ──► decoded_t ──┐
                                           │      operand values (from the
            rabbit_regfile ──► rs1, rs2 ───┤◄──── pipeline: bypass / forwarding)
                                           ▼
                                    rabbit_execute ──► redirect, redirect_pc  (to fetch)
                                     (ALU, branch,         │
                                      CSR, traps)          ▼
                                                        exec_t ──► memory request
                                                           │       (from X or MEM)
                                                           ▼
                                               retirement: load data, regfile write,
                                               rabbit_rvfi
```

Rules for this directory:
- nothing here may know how many stages a core has;
- a change here affects every core → run `make formal CORE=rabbit3` **and**
  `make formal CORE=rabbit5` (CI does both).

## M extension (`rabbit_muldiv.sv`)

The instruction stays in execute (the commit point) until it is done; the
pipeline holds it there while `rabbit_execute.busy_o` is 1.

| Instructions | Cycles in execute | Depends on the operands? |
|---|---|---|
| MUL, MULH, MULHSU, MULHU | 2 | no |
| DIV, DIVU, REM, REMU | 34 (also x/0 and −2³¹/−1) | no |

- **Multiplier:** one 33×17 signed multiplier, used twice: rs1 × low half of
  rs2, then rs1 × high half of rs2 plus the first partial product (the add is
  fused into the multiplier's adder tree). Both MUL and MULH* take 2 cycles.
- **Divider:** restoring long division, one quotient bit per cycle, on the
  magnitudes; one adder for the steps and one negator shared by the first
  cycle (|rs1|) and the last (sign of the result). No early exit: robot
  control code needs the worst case to be the normal case.
- **Interrupts** are not delayed by a divide: the divide is abandoned and runs
  again after MRET (the proven interrupt latency stays 4 / 7 cycles). The
  price: each interrupt that hits a divide throws away up to 33 cycles, and
  interrupts that keep coming faster than ~34 cycles + handler time **starve**
  the divide (no progress guarantee). See the known limitation in
  `../rabbit3/README.md`.

### Why this design (measured on sky130, Yosys `synth -booth` + ABC, typical corner)

Combinational parts alone (delays without wires, for comparison only):

| Part | Area µm² | Delay |
|---|---|---|
| 32-bit adder (for scale) | 1 506 | 3.1 ns |
| full 33×33 multiplier (all of MUL/MULH* in one cycle) | 31 734 | 7.4 ns |
| **33×17 multiplier + fused add (ours)** | **20 366** | 6.9 ns |
| 17×17 multiply-add (Ibex "fast" style: MUL 3, MULH 4 cycles) | 11 549 | 5.3 ns |
| same full 33×33 without `-booth` | 47 405 | 7.8 ns |

Whole cores (core + adapter):

| Core | Area µm² | Longest path | `hello` cycles |
|---|---|---|---|
| rabbit3 RV32I | 81 064 | 10.0 ns | 3145 |
| **rabbit3 RV32IM** | **114 853** (+42 %) | 10.0–10.7 ns | **2758** |
| rabbit5 RV32I | 95 381 | 9.2 ns | 3958 |
| **rabbit5 RV32IM** | **126 549** (+33 %) | 9.0–9.5 ns | **3473** |
| CV32E40P RV32IMC (reference) | 170 298 | 6.9 ns | 3447 |
| Ibex "small" RV32IMC (reference) | 124 899 | 6.4 ns | 3984 |
| CVE2 RV32IMC (reference) | 128 964 | 6.5 ns | 3984 |

Full comparison (also M and interrupt timing): `../README.md`.

- The longest path does not go through the M unit: in every run it is
  instruction word → decode / trap logic → enable of the 64-bit `minstret` /
  `mcycle` counters (cheap to fix later by registering that enable). ABC's
  delay varies by about ±0.6 ns between runs of nearly identical RTL, hence
  the ranges; a real answer needs OpenROAD with wires — a later step.
- **Operand isolation** (power): unless an M instruction is in execute, the
  multiplier and the divider's negator see zeros, so they do not switch on
  the operands of every other instruction. Cost: ~100 µm² (0.1 %).
- `synth -booth` saves 25–33 % of multiplier area: use it for every real
  synthesis run.
- Half of each core's area is flip-flops (mostly the register file), so the
  M unit looks large next to the logic. It is the obvious place to save area
  later: the divider could reuse the multiplier's partial-product register,
  and the 33×17 multiplier could become the int8 dot-product unit (next step).

Verification: `dv/formal/rabbit/muldiv/` (values for every input at 4, 6 and
8 bits, exact latency at 32 bits), riscv-formal with ALTOPS for the pipeline,
`sw/baremetal/muldiv` on every core.
