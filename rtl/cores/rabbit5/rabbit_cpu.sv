// rabbit_cpu adapter for rabbit5 (our own 5-stage RV32I core).
// See rtl/cores/README.md for the port contract. rabbit5 needs memories that
// grant immediately and answer one cycle later (rabbit5_core.sv, rule R4).
module rabbit_cpu #(
    parameter logic [31:0] BOOT_ADDR  = 32'h0000_0080,
    parameter logic [31:0] MTVEC_ADDR = 32'h0000_0000
) (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        fetch_enable_i,

    output logic        instr_req_o,
    input  logic        instr_gnt_i,
    input  logic        instr_rvalid_i,
    output logic [31:0] instr_addr_o,
    input  logic [31:0] instr_rdata_i,

    output logic        data_req_o,
    input  logic        data_gnt_i,
    input  logic        data_rvalid_i,
    output logic        data_we_o,
    output logic [ 3:0] data_be_o,
    output logic [31:0] data_addr_o,
    output logic [31:0] data_wdata_o,
    input  logic [31:0] data_rdata_i,

    input  logic [31:0] irq_i,
    output logic        irq_ack_o,
    output logic [ 4:0] irq_id_o,

    input  logic        debug_req_i,
    output logic        core_sleep_o
);
  rabbit5_core #(.BOOT_ADDR(BOOT_ADDR), .MTVEC_ADDR(MTVEC_ADDR)) u_core (
      .clk_i, .rst_ni, .fetch_enable_i,
      .instr_req_o, .instr_gnt_i, .instr_rvalid_i, .instr_addr_o, .instr_rdata_i,
      .data_req_o, .data_gnt_i, .data_rvalid_i, .data_we_o, .data_be_o,
      .data_addr_o, .data_wdata_o, .data_rdata_i,
      .irq_i,
      // RVFI is only used by formal and trace tools
      .rvfi_valid(), .rvfi_order(), .rvfi_insn(), .rvfi_trap(), .rvfi_halt(),
      .rvfi_intr(), .rvfi_mode(), .rvfi_ixl(), .rvfi_rs1_addr(), .rvfi_rs2_addr(),
      .rvfi_rs1_rdata(), .rvfi_rs2_rdata(), .rvfi_rd_addr(), .rvfi_rd_wdata(),
      .rvfi_pc_rdata(), .rvfi_pc_wdata(), .rvfi_mem_addr(), .rvfi_mem_rmask(),
      .rvfi_mem_wmask(), .rvfi_mem_rdata(), .rvfi_mem_wdata()
  );

  // v0 has no interrupts and no debug module
  assign irq_ack_o    = 1'b0;
  assign irq_id_o     = 5'd0;
  assign core_sleep_o = 1'b0;
  logic unused;
  assign unused = debug_req_i;
endmodule
