// =============================================================================
// rabbit_rvfi — report each retired instruction on the RVFI port
// =============================================================================
// RVFI (RISC-V Formal Interface) is how riscv-formal and our timing properties
// see the core: one record per retired instruction, in program order.
// Every rabbit core retires from an exec_t record plus, for loads, the data
// that just came back from memory.
// =============================================================================
module rabbit_rvfi
  import rabbit_pkg::*;
(
  input  logic        clk_i,
  input  logic        rst_ni,

  input  exec_t       retire_i,      // the instruction retiring this cycle (if .valid)
  input  logic [31:0] rd_wdata_i,    // its final register value (load data for loads)
  input  logic [31:0] mem_rdata_i,   // the raw memory word (loads)

  output logic        rvfi_valid,
  output logic [63:0] rvfi_order,
  output logic [31:0] rvfi_insn,
  output logic        rvfi_trap,
  output logic        rvfi_halt,
  output logic        rvfi_intr,
  output logic [ 1:0] rvfi_mode,
  output logic [ 1:0] rvfi_ixl,
  output logic [ 4:0] rvfi_rs1_addr,
  output logic [ 4:0] rvfi_rs2_addr,
  output logic [31:0] rvfi_rs1_rdata,
  output logic [31:0] rvfi_rs2_rdata,
  output logic [ 4:0] rvfi_rd_addr,
  output logic [31:0] rvfi_rd_wdata,
  output logic [31:0] rvfi_pc_rdata,
  output logic [31:0] rvfi_pc_wdata,
  output logic [31:0] rvfi_mem_addr,
  output logic [ 3:0] rvfi_mem_rmask,
  output logic [ 3:0] rvfi_mem_wmask,
  output logic [31:0] rvfi_mem_rdata,
  output logic [31:0] rvfi_mem_wdata
);
  logic [63:0] order_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)             order_q <= '0;
    else if (retire_i.valid) order_q <= order_q + 64'd1;
  end

  assign rvfi_valid     = retire_i.valid;
  assign rvfi_order     = order_q;
  assign rvfi_insn      = retire_i.instr;
  assign rvfi_trap      = retire_i.trap;
  assign rvfi_halt      = 1'b0;
  assign rvfi_intr      = retire_i.intr;  // first instruction of an interrupt handler
  assign rvfi_mode      = 2'd3;          // machine mode
  assign rvfi_ixl       = 2'd1;          // 32-bit
  assign rvfi_rs1_addr  = retire_i.rs1_addr;
  assign rvfi_rs2_addr  = retire_i.rs2_addr;
  assign rvfi_rs1_rdata = retire_i.rs1_val;
  assign rvfi_rs2_rdata = retire_i.rs2_val;
  assign rvfi_rd_addr   = retire_i.writes_rd ? retire_i.rd : 5'd0;
  assign rvfi_rd_wdata  = retire_i.writes_rd ? rd_wdata_i  : 32'd0;
  assign rvfi_pc_rdata  = retire_i.pc;
  assign rvfi_pc_wdata  = retire_i.next_pc;
  assign rvfi_mem_addr  = {retire_i.addr[31:2], 2'b00};
  assign rvfi_mem_rmask = retire_i.is_load  ? retire_i.mem_be : 4'b0;
  assign rvfi_mem_wmask = retire_i.is_store ? retire_i.mem_be : 4'b0;
  assign rvfi_mem_rdata = mem_rdata_i;
  assign rvfi_mem_wdata = retire_i.is_store ? retire_i.mem_wdata : 32'd0;

  // result/funct3 are already folded into rd_wdata_i by the pipeline
  logic unused;
  assign unused = ^{retire_i.result, retire_i.funct3};
endmodule
