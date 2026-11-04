# Getting started: run, simulate, understand

Everything below was run on 2026-11-04 with Verilator 5.038, cocotb 2.0,
riscv64-unknown-elf-gcc 13.2, uv 0.11.

## 0. One-time setup

```bash
git submodule update --init --recursive   # fetches third_party/cv32e40p @ v1.8.3
uv sync                                   # Python env: cocotb, pytest, pyyaml, ...
```

Tools needed on PATH: `verilator` (≥ 5.036 for cocotb 2.0), `riscv64-unknown-elf-gcc`,
`make`, `uv`. Easiest single install: the YosysHQ **OSS CAD Suite** (same as CI).

## 1. Run everything CI runs

```bash
make ci          # lint + SoC firmware sim + 10 hw_ip tests + rma_analysis examples
```

## 2. The first program on the CPU — read in this order

| Step | File | What to look at |
|---|---|---|
| 1 | `sw/baremetal/hello/main.c` | The C program: prints, self-checks, cycle count |
| 2 | `sw/baremetal/common/crt0.S` | Reset → stack → zero .bss → `main` → write exit code |
| 3 | `sw/baremetal/common/link.ld` | Vectors at 0x0, code at 0x80 (CPU boot address) |
| 4 | `sw/baremetal/build/hello/hello.dis` | The actual instructions (after `make firmware`) |
| 5 | `rtl/soc/rabbit_soc_sim.sv` | CPU + RAM + sim-control, address decode |
| 6 | `rtl/cores/cv32e40p/rabbit_cpu.sv` | How a vendor core is plugged into our contract |
| 7 | `dv/cocotb/soc/test_soc.py` | Testbench: clock, reset, console capture, pass/fail |

```bash
make soc-sim                 # CORE=cv32e40p PROG=hello by default
make soc-waves               # same, plus dv/cocotb/soc/dump.fst
gtkwave dv/cocotb/soc/dump.fst   # or: surfer dump.fst
```

Expected output (abridged):

```
fw| rt-rabbit: hello from rabbit_cpu
fw|   misa  = 0x40001104        <- RV32, extensions I, M, C
fw|   [ok]   mul     = 0x068c94ef
...
fw| RESULT: PASS
hello finished after 3450 cycles, exit code 0x00000000
```

Good signals to put in the waveform viewer first:
`u_cpu.instr_addr_o` (program counter as fetched), `u_cpu.data_addr_o`,
`u_cpu.data_we_o`, `putc_valid_o`, `exit_valid_o`.

## 3. Write your own program

```bash
mkdir sw/baremetal/myprog && cp sw/baremetal/hello/main.c sw/baremetal/myprog/
make soc-sim PROG=myprog
```

`main()` returning 0 = PASS. Any unexpected trap ends the test with exit code
`0xDEAD0000 | mcause` (e.g. `0xDEAD0002` = illegal instruction).

## 4. Prove the checker is not vacuous (verification habit)

```bash
RABBIT_MAX_CYCLES=100 make soc-sim     # must FAIL with TimeoutError, make exits non-zero
```

## 5. Existing hardware IP and analysis

```bash
make ip-test        # Wishbone PWM, QEI, telemetry, RF pipeline (cocotb)
make rma-smoke      # all rma_analysis/examples/*.yaml
uv run rma_analysis rma_analysis/examples/simple_robot.yaml --plot
```
