# rt-rabbit 🐇

An open, verifiable **real-time RISC-V SoC** for robotics: RTL → verification →
FPGA → open-source ASIC, evaluated with Zephyr and real-time Linux, with a
vector / quantized-NN block. Five-year plan:
[`docs/research/2026-11-04-soc-5yr-plan.md`](docs/research/2026-11-04-soc-5yr-plan.md).

Baseline CPU: **OpenHW CV32E40P** (RV32IMC). Every layer above the CPU talks to
a core-agnostic `rabbit_cpu` contract, so other cores (Ibex, CV32E40X, our own
5-stage core) plug in the same way: [`rtl/cores/README.md`](rtl/cores/README.md).

## Quick start

```bash
git clone --recursive git@github.com:abmajith/rt-rabbit.git && cd rt-rabbit
uv sync
make soc-sim     # run sw/baremetal/hello on CV32E40P in Verilator
make ci          # everything CI runs
```

Walkthrough: [`docs/GETTING_STARTED.md`](docs/GETTING_STARTED.md) ·
Status and known issues: [`docs/STATUS.md`](docs/STATUS.md)

## Layout

| Path | Contents |
|---|---|
| `rtl/cores/` | `rabbit_cpu` adapters, one directory per core |
| `rtl/soc/` | SoC top, RAM, simulation control |
| `hw_ip/` | Wishbone peripherals: PWM, QEI, telemetry, RF pipeline + cocotb tests |
| `dv/` | Verification: `cocotb/` (SoC tests), `isa/`, `formal/` |
| `sw/` | `baremetal/` programs, `zephyr/` port |
| `fpga/`, `asic/` | FPGA (LiteX) and open-silicon flows |
| `tools/` | Build helpers; `gls/` fast gate-level verification (GPU) |
| `rma_analysis/` | Rate-monotonic / MSRP schedulability analysis (`uv run rma_analysis <yaml>`) |
| `rt_rabbit/zephyr-fw/` | Zephyr control firmware |
| `third_party/` | Git submodules (CV32E40P) |
| `docs/` | Plan, research, status |
