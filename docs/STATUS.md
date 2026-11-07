# Status (updated 2026-11-06)

## Works

| Item | Command | Result |
|---|---|---|
| CV32E40P (v1.8.3, RV32IMC) in `rabbit_soc_sim`, Verilator | `make soc-sim` | hello: 6/6 checks pass, 3447 cycles |
| Lint of our RTL (`-Wall`, vendor code excluded) | `make lint` | clean |
| hw_ip cocotb tests | `make ip-test` | 10 targets, 19 tests pass |
| rma_analysis examples | `make rma-smoke` | 11 run, 1 expected failure |
| GitHub Actions | `.github/workflows/ci.yml` (every PR, ~1 min jobs) + `deep-verify.yml` (on demand) | ci: lint, soc-sim (5 cores), ip-test, rma-smoke, muldiv exhaustive; deep-verify: formal, GLS, mutants |
| Interrupt self-test on CV32E40P (reference) | `make soc-sim PROG=irq` | PASS, 9095 cycles |
| Reference cores CVE2 and Ibex (pinned submodules, same firmware) | `make soc-sim CORE=cve2\|ibex PROG=...` | hello / irq / muldiv PASS; comparison table in `rtl/cores/README.md` |
| Reproduce everything | `tools/check_all.sh [quick gls formal synth mutants]` | all PASS (2026-11-07) |
| SoC configurations (`configs/`, `make configs`): core + options, one name per variant | `make <target> CONFIG=rabbit5_rv32i` | 7 configurations; quick, gls, formal all PASS (2026-11-07) |

## Own cores: rabbit3 and rabbit5 (shared blocks in rtl/cores/rabbit_common)

| Item | rabbit3 (3-stage) | rabbit5 (5-stage) |
|---|---|---|
| ISA | RV32IM + Zicsr | RV32IM + Zicsr |
| hello (`make soc-sim CORE=...`) | PASS, 2758 cycles | PASS, 3473 cycles |
| interrupts + WFI (`PROG=irq`, same test passes on cv32e40p) | PASS, 7448 cycles | PASS, 9025 cycles |
| M extension (`PROG=muldiv`, same test passes on cv32e40p) | PASS; MUL 2 cycles, DIV 34, data-independent | same |
| riscv-formal (`make formal CORE=...`, M via ALTOPS) | 53/53 | 53/53 |
| multiply/divide unit proof (`make -C dv/formal/rabbit muldiv`) | PASS: values for all inputs at 4/6/8 bits, latency at 32 bits | (shared) |
| timing properties T1–T4 + covers | PASS | PASS |
| interrupt properties I1–I4, sleep W0–W2; worst-case latency (tight) | PASS, 4 cycles | PASS, 7 cycles |
| gate-level smoke (`make gls-smoke CORE=...`) | PASS, same cycles (hello, irq, muldiv) | PASS, same cycles (hello, irq, muldiv) |
| size, sky130 (`synth -booth` + ABC; CV32E40P RV32IMC: 170.3 k µm²) | 114.9 k µm² | 126.5 k µm² |
| without M (`CONFIG=rabbit3_rv32i` / `rabbit5_rv32i`): size | 81.1 k µm² (−29 %) | 95.2 k µm² (−25 %) |
| without M: riscv-formal / timing + X1 (MUL/DIV trap) / gate level | 45/45 / PASS / PASS | 45/45 / PASS / PASS |
| without M: hello / muldiv (software multiply via libgcc) | 3147 / 62 724 cycles | 3960 / 75 013 cycles |

Next: int8 (and int4) SIMD dot product for quantized inference, riscv-formal
CSR checks, RISCOF compliance, then the dual-core TDM work (M4).
Learning path: `rtl/cores/rabbit3/README.md`.

## Known issues

- `hw_ip/sim` targets `telemetry_rf` and `top` need
  `components/telemetry/rf_packet_framer_buffer.v`, which is not on `main`
  (probably on `refactor_telemetry_mimo` or `dma_telemetry`). Excluded from CI.
- `rma_analysis`: FIFO same-priority policy raises `NotImplementedError`
  (`examples/fifo_same_priority_interference.yaml` is an expected failure in CI).
- Fixed in this branch: `rma_analysis/rt_multi_analysis.py` used an absolute
  import (`from resource_arbiter ...`), so the `rma_analysis` CLI crashed on start.
- `pyyaml` is only in the `dev` dependency group but the CLI needs it at run
  time. Works because `uv sync` installs dev by default; move it to
  `dependencies` before publishing the package.

## Y1 H1 checklist

- [x] Monorepo layout, `rabbit_cpu` core contract, CV32E40P adapter
- [x] Bare-metal toolchain flow (GCC → hex → $readmemh)
- [x] Firmware-driven cocotb SoC test
- [x] CI pipeline
- [x] Own core rabbit5 v0 with riscv-formal, timing properties, GLS smoke (2026-11-06)
- [x] Machine timer (mtime/mtimecmp) + interrupt test; rabbit3/rabbit5 interrupts + WFI with proven latency (2026-11-06)
- [x] M extension on rabbit3/rabbit5: fixed-latency multiply (2) / divide (34), interruptible, proven (2026-11-06)
- [ ] OBI→Wishbone bridge; attach PWM / QEI / telemetry to the CPU
- [ ] UART (needed for FPGA and Zephyr console)
- [ ] RISCOF + riscv-arch-test on CV32E40P (`dv/isa/`)
- [ ] Zephyr port: SoC + board definition, runs in Verilator (`sw/zephyr/`)
- [ ] FPGA: LiteX target with CV32E40P (`fpga/litex/`)
- [ ] Interrupt latency measured vs `rma_analysis` prediction
