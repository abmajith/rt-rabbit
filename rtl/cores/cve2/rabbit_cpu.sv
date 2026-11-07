// rabbit_cpu adapter for OpenHW CVE2 (third_party/cve2, pinned commit; the
// "CV32E20": Ibex-derived 2-stage RV32IMC core).
// Configuration: RV32IMC + Zicsr, fast multiplier (RV32MFast), no X-interface,
// no extra performance counters (MHPMCounterNum = 0).
// See rtl/cores/README.md for the port contract.
//
// Differences from the contract (documented, not hidden):
// - CVE2 starts fetching AT boot_addr and puts the vectored mtvec at
//   boot_addr[31:8]; with the contract defaults (BOOT_ADDR 0x80, MTVEC 0x0)
//   both line up. Other combinations are rejected below.
// - fast interrupts 16..31: the lowest line has the highest priority.
// - irq_ack_o / irq_id_o do not exist on CVE2: tied to 0.
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

  if (MTVEC_ADDR[7:0] != 8'h00 || BOOT_ADDR[31:8] != MTVEC_ADDR[31:8]) begin : g_bad_addr
    $error("cve2 adapter: needs MTVEC_ADDR 256-byte aligned and BOOT_ADDR in the same 256-byte block");
  end

  assign irq_ack_o = 1'b0;
  assign irq_id_o  = '0;

  cve2_top #(
      .MHPMCounterNum(0),                  // as in the Ibex adapter (fair area comparison)
      .RV32M         (cve2_pkg::RV32MFast),
      .XInterface    (1'b0)
  ) u_core (
      .clk_i              (clk_i),
      .rst_ni             (rst_ni),
      .test_en_i          (1'b0),
      .ram_cfg_i          ('0),

      .hart_id_i          (32'h0),
      .boot_addr_i        (BOOT_ADDR),

      .instr_req_o        (instr_req_o),
      .instr_gnt_i        (instr_gnt_i),
      .instr_rvalid_i     (instr_rvalid_i),
      .instr_addr_o       (instr_addr_o),
      .instr_rdata_i      (instr_rdata_i),
      .instr_err_i        (1'b0),

      .data_req_o         (data_req_o),
      .data_gnt_i         (data_gnt_i),
      .data_rvalid_i      (data_rvalid_i),
      .data_we_o          (data_we_o),
      .data_be_o          (data_be_o),
      .data_addr_o        (data_addr_o),
      .data_wdata_o       (data_wdata_o),
      .data_rdata_i       (data_rdata_i),
      .data_err_i         (1'b0),

      .x_issue_valid_o    (),
      .x_issue_ready_i    (1'b0),
      .x_issue_req_o      (),
      .x_issue_resp_i     ('0),
      .x_register_o       (),
      .x_commit_valid_o   (),
      .x_commit_o         (),
      .x_result_valid_i   (1'b0),
      .x_result_ready_o   (),
      .x_result_i         ('0),

      .irq_software_i     (irq_i[3]),
      .irq_timer_i        (irq_i[7]),
      .irq_external_i     (irq_i[11]),
      .irq_fast_i         (irq_i[31:16]),
      .irq_nm_i           (1'b0),

      .debug_req_i        (debug_req_i),
      .debug_halted_o     (),
      .dm_halt_addr_i     (32'h0),     // no debug module yet
      .dm_exception_addr_i(32'h0),
      .crash_dump_o       (),

      .fetch_enable_i     (fetch_enable_i),
      .core_sleep_o       (core_sleep_o)
  );

endmodule
