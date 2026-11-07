# rt-rabbit 🐇

An open, verifiable **real-time RISC-V SoC** for robotics: RTL → verification →
FPGA → open-source ASIC, evaluated with Zephyr and real-time Linux, with a
vector / quantized-NN block. Five-year plan and research notes are kept
outside the repository.

CPUs: **rabbit3** / **rabbit5**, our own timing-predictable 3- and 5-stage RV32IM cores
([`rtl/cores/rabbit5/README.md`](rtl/cores/rabbit5/README.md)), and **OpenHW
CV32E40P** (RV32IMC) as reference. Every layer above the CPU talks to a
core-agnostic `rabbit_cpu` contract, so cores plug in the same way:
[`rtl/cores/README.md`](rtl/cores/README.md).

## Quick start

```bash
git clone --recursive git@github.com:abmajith/rt-rabbit.git && cd rt-rabbit
uv sync
make soc-sim                 # run sw/baremetal/hello on CV32E40P in Verilator
make soc-sim CORE=rabbit5    # ... on our own core (also rabbit3; PROG=irq, PROG=muldiv)
make formal                  # riscv-formal + timing + muldiv proofs for rabbit5 (~25 min)
make gls-smoke CORE=rabbit5  # same firmware on the synthesized gate netlist
make ci                      # lint + simulation tests
```

### Reproduce every result

`tools/check_all.sh` (or `make check-all STAGES="..."`) reruns every check
behind the numbers in the docs and prints a PASS/FAIL summary:

| Stage | What | Time |
|---|---|---|
| `quick` | lint, `hello` / `irq` / `muldiv` firmware on rabbit3, rabbit5, CV32E40P, CVE2, Ibex; exhaustive 8-bit muldiv simulation | ~2 min |
| `gls` | the same firmware on the gate-level netlists | ~10 min |
| `formal` | riscv-formal, timing properties, muldiv unit proof, both rabbit cores | ~60 min |
| `synth` | sky130 area / delay table of all five cores (`tools/synth_sky130.sh`, needs the PDK) | ~2 min |
| `mutants` | plants known bugs in a copy and checks each is caught (`tools/mutants.py`) | ~30–60 min |

Default is `quick gls`; `tools/check_all.sh all` runs everything. Tools
needed: OSS CAD Suite (yosys + slang, sby, boolector, verilator),
`riscv64-unknown-elf-gcc`, `uv`.

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
| `tools/` | Build helpers; `check_all.sh`, `synth_sky130.sh`, `mutants.py` (reproduce results); `gls/` fast gate-level verification (GPU) |
| `rma_analysis/` | Rate-monotonic / MSRP schedulability analysis (`uv run rma_analysis <yaml>`) |
| `rt_rabbit/zephyr-fw/` | Zephyr control firmware |
| `third_party/` | Git submodules (CV32E40P) |
| `docs/` | Plan, research, status |
