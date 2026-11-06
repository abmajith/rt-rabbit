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
| `rabbit_execute.sv` | combinational + CSR state | ALU operands, branch/jump decision, exceptions, interrupts, WFI, CSR access, next pc → `exec_t` + redirect |
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
