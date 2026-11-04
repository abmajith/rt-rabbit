// rabbit_cpu adapter for OpenHW CV32E40P (third_party/cv32e40p, tag cv32e40p_v1.8.3)
// Configuration: RV32IMC + Zicsr, no PULP extensions, no FPU.
// See rtl/cores/README.md for the port contract.
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

  cv32e40p_top #(
      .COREV_PULP      (0),
      .COREV_CLUSTER   (0),
      .FPU             (0),
      .ZFINX           (0),
      .NUM_MHPMCOUNTERS(1)
  ) u_core (
      .clk_i              (clk_i),
      .rst_ni             (rst_ni),
      .pulp_clock_en_i    (1'b1),
      .scan_cg_en_i       (1'b0),

      .boot_addr_i        (BOOT_ADDR),
      .mtvec_addr_i       (MTVEC_ADDR),
      .dm_halt_addr_i     (32'h0),     // no debug module yet
      .hart_id_i          (32'h0),
      .dm_exception_addr_i(32'h0),

      .instr_req_o        (instr_req_o),
      .instr_gnt_i        (instr_gnt_i),
      .instr_rvalid_i     (instr_rvalid_i),
      .instr_addr_o       (instr_addr_o),
      .instr_rdata_i      (instr_rdata_i),

      .data_req_o         (data_req_o),
      .data_gnt_i         (data_gnt_i),
      .data_rvalid_i      (data_rvalid_i),
      .data_we_o          (data_we_o),
      .data_be_o          (data_be_o),
      .data_addr_o        (data_addr_o),
      .data_wdata_o       (data_wdata_o),
      .data_rdata_i       (data_rdata_i),

      .irq_i              (irq_i),
      .irq_ack_o          (irq_ack_o),
      .irq_id_o           (irq_id_o),

      .debug_req_i        (debug_req_i),
      .debug_havereset_o  (),
      .debug_running_o    (),
      .debug_halted_o     (),

      .fetch_enable_i     (fetch_enable_i),
      .core_sleep_o       (core_sleep_o)
  );

endmodule
