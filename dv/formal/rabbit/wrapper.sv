// riscv-formal wrapper for the rabbit cores (RABBIT_CORE is set by the Makefile).
//
// The solver may choose ANY instruction word and ANY load data in every
// cycle (`rvformal_rand_reg). That is what makes the checks exhaustive: every
// instruction sequence up to the check depth is covered, not just programs we
// thought of.
//
// Memory contract (rule R4 of every rabbit core): requests are granted immediately and the
// answer comes one cycle later. We model exactly that and nothing more.
module rvfi_wrapper (
    input clock,
    input reset,
    `RVFI_OUTPUTS
);
    (* keep *) `rvformal_rand_reg [31:0] instr_rdata;
    (* keep *) `rvformal_rand_reg [31:0] data_rdata;

    (* keep *) wire        instr_req;
    (* keep *) wire [31:0] instr_addr;
    (* keep *) wire        data_req;
    (* keep *) wire        data_we;
    (* keep *) wire [ 3:0] data_be;
    (* keep *) wire [31:0] data_addr;
    (* keep *) wire [31:0] data_wdata;

    `RABBIT_CORE uut (
        .clk_i          (clock),
        .rst_ni         (!reset),
        .fetch_enable_i (1'b1),

        .instr_req_o    (instr_req),
        .instr_gnt_i    (1'b1),
        .instr_rvalid_i (1'b1),
        .instr_addr_o   (instr_addr),
        .instr_rdata_i  (instr_rdata),

        .data_req_o     (data_req),
        .data_gnt_i     (1'b1),
        .data_rvalid_i  (1'b1),
        .data_we_o      (data_we),
        .data_be_o      (data_be),
        .data_addr_o    (data_addr),
        .data_wdata_o   (data_wdata),
        .data_rdata_i   (data_rdata),

        .irq_i          (32'b0),

        `RVFI_CONN32
    );
endmodule
