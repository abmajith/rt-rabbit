# CPU cores: the `rabbit_cpu` contract

Everything above this directory (SoC, testbenches, firmware, FPGA, ASIC) talks to
**one** module name, `rabbit_cpu`, with **one** fixed port list. Each core we
support lives in its own sub-directory and provides:

| File | Purpose |
|---|---|
| `rabbit_cpu.sv` | Adapter: instantiates the real core and maps it onto the contract below |
| `files.f` | Verilator/Yosys file list (paths relative to the repo root via the `${REPO}` environment variable) |
| `core.mk` | Make fragment: `CORE_MARCH`, `CORE_MABI`, extra simulator flags |

Select a core with `make CORE=<dir-name> ...` (default: `cv32e40p`).
Only one `rabbit_cpu` is compiled per build, so no `ifdef` soup is needed.

## Port contract (v0)

```systemverilog
module rabbit_cpu #(
  parameter logic [31:0] BOOT_ADDR  = 32'h0000_0080,  // first instruction fetched
  parameter logic [31:0] MTVEC_ADDR = 32'h0000_0000   // trap vector base (256-B aligned)
)(
  input  logic        clk_i, rst_ni, fetch_enable_i,
  // Instruction fetch: OBI-style (req/gnt address phase, rvalid response phase)
  output logic        instr_req_o,   input  logic        instr_gnt_i,
  input  logic        instr_rvalid_i,output logic [31:0] instr_addr_o,
  input  logic [31:0] instr_rdata_i,
  // Data: OBI-style
  output logic        data_req_o,    input  logic        data_gnt_i,
  input  logic        data_rvalid_i, output logic        data_we_o,
  output logic [3:0]  data_be_o,     output logic [31:0] data_addr_o,
  output logic [31:0] data_wdata_o,  input  logic [31:0] data_rdata_i,
  // Interrupts (RISC-V standard layout: 3=MSI, 7=MTI, 11=MEI, 16..31=fast/local)
  input  logic [31:0] irq_i,         output logic        irq_ack_o,
  output logic [4:0]  irq_id_o,
  input  logic        debug_req_i,
  output logic        core_sleep_o
);
```

Why OBI? It is the native bus of CV32E40P, Ibex and CVE4 cores. Wishbone
(our `hw_ip/` peripherals) and AXI/LiteX buses are bridged *outside* the core
adapter, in `rtl/soc/`.

## Planned adapters

| Dir | Core | Status | Notes |
|---|---|---|---|
| `cv32e40p/` | OpenHW CV32E40P v1.8.3 (RV32IMC, 4-stage) | **working** | Baseline for Y1 |
| `ibex/` | lowRISC Ibex | planned | Same OBI-like bus, 2/3-stage; good for area comparison |
| `cv32e40x/` | OpenHW CV32E40X | planned | Brings CV-X-IF for the vector/NN coprocessor |
| `rabbit5/` | Our own 5-stage, timing-predictable core | Y1 H2 | Grows out of `verilog-riscV32I-machine` |

The contract will grow (v1) with an optional **coprocessor port** (CV-X-IF
style) and an optional **RVFI trace port** for lockstep checking against Spike/Sail.
Cores that lack a feature tie the outputs off; the SoC checks capabilities at
elaboration time.
