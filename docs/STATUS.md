# Status (updated 2026-11-04)

## Works

| Item | Command | Result |
|---|---|---|
| CV32E40P (v1.8.3, RV32IMC) in `rabbit_soc_sim`, Verilator | `make soc-sim` | hello: 6/6 checks pass, 3450 cycles |
| Lint of our RTL (`-Wall`, vendor code excluded) | `make lint` | clean |
| hw_ip cocotb tests | `make ip-test` | 10 targets, 19 tests pass |
| rma_analysis examples | `make rma-smoke` | 11 run, 1 expected failure |
| GitHub Actions | `.github/workflows/ci.yml` | lint, soc-sim matrix, ip-test matrix, rma-smoke |

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
- [ ] Machine timer (mtime/mtimecmp) + interrupt test (irq_i already exposed)
- [ ] OBI→Wishbone bridge; attach PWM / QEI / telemetry to the CPU
- [ ] UART (needed for FPGA and Zephyr console)
- [ ] RISCOF + riscv-arch-test on CV32E40P (`dv/isa/`)
- [ ] Zephyr port: SoC + board definition, runs in Verilator (`sw/zephyr/`)
- [ ] FPGA: LiteX target with CV32E40P (`fpga/litex/`)
- [ ] Interrupt latency measured vs `rma_analysis` prediction
