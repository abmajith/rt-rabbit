# Status (updated 2026-11-06)

## Works

| Item | Command | Result |
|---|---|---|
| CV32E40P (v1.8.3, RV32IMC) in `rabbit_soc_sim`, Verilator | `make soc-sim` | hello: 6/6 checks pass, 3450 cycles |
| Lint of our RTL (`-Wall`, vendor code excluded) | `make lint` | clean |
| hw_ip cocotb tests | `make ip-test` | 10 targets, 19 tests pass |
| rma_analysis examples | `make rma-smoke` | 11 run, 1 expected failure |
| GitHub Actions | `.github/workflows/ci.yml` | lint, soc-sim matrix, ip-test matrix, rma-smoke |

## rabbit5 (own core) — M0 done on branch `rabbit5-m0`

| Item | Command | Result |
|---|---|---|
| hello on rabbit5 (RV32I, 5-stage) | `make soc-sim CORE=rabbit5` | PASS, 3958 cycles |
| riscv-formal | `make formal` | 45/45 PASS |
| timing properties T1–T3 + covers | `make formal` | PASS (BMC 24) |
| gate-level smoke (Yosys generic netlist) | `make gls-smoke CORE=rabbit5` | PASS, same 3958 cycles |

Next (M1/M2): enable riscv-formal CSR checks, timer + external interrupt with a
proven entry-latency bound, RISCOF compliance, then the dual-core TDM work (M4).
Review guide: `rtl/cores/rabbit5/README.md`.

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
- [ ] Machine timer (mtime/mtimecmp) + interrupt test (irq_i already exposed)
- [ ] OBI→Wishbone bridge; attach PWM / QEI / telemetry to the CPU
- [ ] UART (needed for FPGA and Zephyr console)
- [ ] RISCOF + riscv-arch-test on CV32E40P (`dv/isa/`)
- [ ] Zephyr port: SoC + board definition, runs in Verilator (`sw/zephyr/`)
- [ ] FPGA: LiteX target with CV32E40P (`fpga/litex/`)
- [ ] Interrupt latency measured vs `rma_analysis` prediction
