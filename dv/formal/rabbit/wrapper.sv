// riscv-formal wrapper for the rabbit cores (RABBIT_CORE is set by the Makefile).
//
// The solver may choose ANY instruction word and ANY load data in every
// cycle (`rvformal_rand_reg). That is what makes the checks exhaustive: every
// instruction sequence up to the check depth is covered, not just programs we
// thought of.
//
// The interrupt lines are free too: an interrupt may arrive in any cycle, so
// every check also covers "this instruction was interrupted" (the core reports
// the handler's first instruction with rvfi_intr; riscv-formal then skips the
// pc continuity check for it). Only two lines are free here - the timer (7)
// and one fast line (16): which line fires does not matter to these checks,
// and all 32 free lines made the `reg` check ~10x slower (>20 min). Line
// priority, vectors and causes are checked with all 32 lines free in
// timing/rabbit_timing_tb.sv (I4, I5) and by the irq firmware test.
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
    (* keep *) `rvformal_rand_reg [31:0] irq;
    (* keep *) wire        core_sleep;

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

        .irq_i          (irq),
        .core_sleep_o   (core_sleep),

        `RVFI_CONN32
    );

    always @* assume ((irq & ~32'h0001_0080) == 0);

`ifdef RISCV_FORMAL_FAIRNESS
    // Liveness ("the next instruction always retires") does not hold while the
    // core sleeps in WFI waiting for an interrupt that never comes - that is
    // allowed. That sleep ends when it must is proven in timing/ (property W1).
    always @* if (!reset) assume (!core_sleep);
`endif
endmodule
