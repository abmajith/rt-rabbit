// rabbit_cpu adapter for lowRISC Ibex (third_party/ibex, pinned commit).
// Configuration: "small" Ibex as documented by lowRISC - RV32IMC + Zicsr,
// 2-stage, fast multiplier (RV32MFast), flip-flop register file, no
// writeback stage, no branch target ALU, no icache, no PMP, no security
// features (SecureIbex = 0), CHERIoT off, only Zca of the Zc extensions.
// See rtl/cores/README.md for the port contract.
//
// Differences from the contract (documented, not hidden):
// - Ibex fetches its first instruction at {boot_addr[31:8], 8'h80} and puts
//   the vectored mtvec at boot_addr[31:8]: so boot_addr_i = MTVEC_ADDR, and
//   BOOT_ADDR must be MTVEC_ADDR + 0x80 (the contract defaults are).
// - 15 fast interrupt lines (16..30); line 31 is ignored. Among them the
//   lowest line has the highest priority.
// - irq_ack_o / irq_id_o do not exist on Ibex: tied to 0.
module rabbit_cpu
  import ibex_pkg::*;
#(
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

  if (MTVEC_ADDR[7:0] != 8'h00 || BOOT_ADDR != MTVEC_ADDR + 32'h80) begin : g_bad_addr
    $error("ibex adapter: needs MTVEC_ADDR 256-byte aligned and BOOT_ADDR = MTVEC_ADDR + 0x80");
  end

  assign irq_ack_o = 1'b0;
  assign irq_id_o  = '0;

  logic unused_irq31;
  assign unused_irq31 = irq_i[31];

  ibex_top #(
      .RV32M          (RV32MFast),
      .RV32B          (RV32BNone),
      .RV32ZC         (RV32Zca),
      .RegFile        (RegFileFF),
      .BranchTargetALU(1'b0),
      .WritebackStage (1'b0),
      .ICache         (1'b0),
      .BranchPredictor(1'b0),
      .DbgTriggerEn   (1'b0),
      .SecureIbex     (1'b0),
      .PMPEnable      (1'b0),
      .MHPMCounterNum (0)
  ) u_core (
      .clk_i                  (clk_i),
      .rst_ni                 (rst_ni),
      .test_en_i              (1'b0),
      .ram_cfg_icache_tag_i   ('0),
      .ram_cfg_icache_tag_o   (),
      .ram_cfg_icache_data_i  ('0),
      .ram_cfg_icache_data_o  (),
      .cheriot_enable_i       (IbexMuBiOff),

      .hart_id_i              (32'h0),
      .boot_addr_i            (MTVEC_ADDR),
      .trvk_heap_base_addr_i  (32'h0),

      .instr_req_o            (instr_req_o),
      .instr_gnt_i            (instr_gnt_i),
      .instr_rvalid_i         (instr_rvalid_i),
      .instr_addr_o           (instr_addr_o),
      .instr_rdata_i          (instr_rdata_i),
      .instr_rdata_intg_i     ('0),
      .instr_err_i            (1'b0),

      .data_req_o             (data_req_o),
      .data_gnt_i             (data_gnt_i),
      .data_rvalid_i          (data_rvalid_i),
      .data_we_o              (data_we_o),
      .data_be_o              (data_be_o),
      .data_addr_o            (data_addr_o),
      .data_wdata_o           (data_wdata_o),
      .data_wdata_intg_o      (),
      .data_tag_o             (),
      .data_rdata_i           (data_rdata_i),
      .data_rdata_intg_i      ('0),
      .data_tag_i             (1'b0),
      .data_err_i             (1'b0),

      .trvk_revbm_req_o       (),
      .trvk_revbm_gnt_i       (1'b0),
      .trvk_revbm_rvalid_i    (1'b0),
      .trvk_revbm_addr_o      (),
      .trvk_revbm_rdata_i     ('0),
      .trvk_revbm_rdata_intg_i('0),
      .trvk_revbm_err_i       (1'b0),

      .irq_software_i         (irq_i[3]),
      .irq_timer_i            (irq_i[7]),
      .irq_external_i         (irq_i[11]),
      .irq_fast_i             (irq_i[30:16]),
      .irq_nm_i               (1'b0),

      .scramble_key_valid_i   (1'b0),
      .scramble_key_i         ('0),
      .scramble_nonce_i       ('0),
      .scramble_req_o         (),

      .debug_req_i            (debug_req_i),
      .crash_dump_o           (),
      .double_fault_seen_o    (),

      .fetch_enable_i         (fetch_enable_i ? IbexMuBiOn : IbexMuBiOff),
      .mcounteren_writable_i  (IbexMuBiOn),
      .alert_minor_o          (),
      .alert_major_internal_o (),
      .alert_major_bus_o      (),
      .core_sleep_o           (core_sleep_o),

      // lockstep / scan test (SecureIbex = 0: unused)
      .scan_rst_ni            (1'b1),
      .lockstep_cmp_en_o      (),
      .data_req_shadow_o      (),
      .data_we_shadow_o       (),
      .data_be_shadow_o       (),
      .data_addr_shadow_o     (),
      .data_wdata_shadow_o    (),
      .data_wdata_intg_shadow_o(),
      .instr_req_shadow_o     (),
      .instr_addr_shadow_o    ()
  );

endmodule
