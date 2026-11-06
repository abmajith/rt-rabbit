// =============================================================================
// rabbit timing properties (beyond riscv-formal) — one testbench, every core
// =============================================================================
// riscv-formal proves WHAT each instruction computes. These properties prove
// WHEN: they turn the "TIMING RULES" comment of a rabbit core into checked
// facts. They look only at the RVFI trace and the memory bus, so they treat the
// core as a black box.
//
// The core and its timing model come from rtl/cores/<core>/core.mk, passed in
// as macros by the Makefile:
//   RABBIT_CORE    module name             (rabbit3_core / rabbit5_core)
//   FIRST_RETIRE   cycle of the first retirement after reset (5 / 3)
//   REDIRECT_GAP   cycles between a redirecting instruction and the next (3 / 2)
//   LOADUSE_GAP    cycles between a load and an instruction using it    (2 / 1)
//
//   T1  exact timing model: the gap between two consecutive retirements is
//         REDIRECT_GAP  if the earlier instruction changed control flow
//                       (taken branch, JAL, JALR, MRET, trap)        [rule R3]
//         LOADUSE_GAP   if the later one reads the register the
//                       earlier one loaded (load-use)                [rule R2]
//         1             otherwise                                    [rule R1]
//   T2  the first instruction retires exactly FIRST_RETIRE cycles after reset
//   T3  a data-memory request happens exactly one cycle before the instruction
//       that made it retires, and never at any other time            [rule R4]
//
// The solver picks ANY instruction word and ANY load data every cycle.
//
// Ideas for properties to add next (robotics / real-time):
//   - bounded interrupt latency, once interrupts exist (M2)
//   - for the dual core (M4): core 0's T1 gaps never depend on core 1
// =============================================================================
module rabbit_timing_tb (
    input logic        clk,
    // Free inputs: the solver may choose ANY instruction word and ANY load
    // data in every cycle. They are top-level inputs on purpose: an
    // (* anyseq *) attribute is silently dropped by the slang frontend, and
    // the signal would become a "don't care" constant that the solver may
    // choose differently at every place it is used.
    input logic [31:0] instr_rdata,
    input logic [31:0] data_rdata
);
  localparam int FIRST_RETIRE = `FIRST_RETIRE;
  localparam int REDIRECT_GAP = `REDIRECT_GAP;
  localparam int LOADUSE_GAP  = `LOADUSE_GAP;

  // ---- reset for exactly the first cycle -------------------------------------
  logic rst_n = 1'b0;
  always_ff @(posedge clk) rst_n <= 1'b1;

  logic        data_req;
  logic        rvfi_valid, rvfi_trap;
  logic [31:0] rvfi_insn, rvfi_rs1_rdata, rvfi_rs2_rdata;
  logic [4:0]  rvfi_rs1_addr, rvfi_rs2_addr, rvfi_rd_addr;
  logic [3:0]  rvfi_mem_rmask, rvfi_mem_wmask;

  `RABBIT_CORE dut (
      .clk_i(clk), .rst_ni(rst_n), .fetch_enable_i(1'b1),
      .instr_req_o(), .instr_gnt_i(1'b1), .instr_rvalid_i(1'b1),
      .instr_addr_o(), .instr_rdata_i(instr_rdata),
      .data_req_o(data_req), .data_gnt_i(1'b1), .data_rvalid_i(1'b1),
      .data_we_o(), .data_be_o(), .data_addr_o(), .data_wdata_o(),
      .data_rdata_i(data_rdata),
      .irq_i(32'b0),
      .rvfi_valid(rvfi_valid), .rvfi_order(), .rvfi_insn(rvfi_insn),
      .rvfi_trap(rvfi_trap), .rvfi_halt(), .rvfi_intr(), .rvfi_mode(), .rvfi_ixl(),
      .rvfi_rs1_addr(rvfi_rs1_addr), .rvfi_rs2_addr(rvfi_rs2_addr),
      .rvfi_rs1_rdata(rvfi_rs1_rdata), .rvfi_rs2_rdata(rvfi_rs2_rdata),
      .rvfi_rd_addr(rvfi_rd_addr), .rvfi_rd_wdata(),
      .rvfi_pc_rdata(), .rvfi_pc_wdata(), .rvfi_mem_addr(),
      .rvfi_mem_rmask(rvfi_mem_rmask), .rvfi_mem_wmask(rvfi_mem_wmask),
      .rvfi_mem_rdata(), .rvfi_mem_wdata()
  );

  // ---- classify the instruction that retires now ------------------------------
  // (the ISA-level meaning only; nothing about how the core is built)
  logic [6:0] opcode;
  logic [2:0] funct3;
  assign opcode = rvfi_insn[6:0];
  assign funct3 = rvfi_insn[14:12];

  logic branch_taken;
  always_comb begin
    case (funct3)
      3'b000 : branch_taken = (rvfi_rs1_rdata == rvfi_rs2_rdata);
      3'b001 : branch_taken = (rvfi_rs1_rdata != rvfi_rs2_rdata);
      3'b100 : branch_taken = ($signed(rvfi_rs1_rdata) <  $signed(rvfi_rs2_rdata));
      3'b101 : branch_taken = ($signed(rvfi_rs1_rdata) >= $signed(rvfi_rs2_rdata));
      3'b110 : branch_taken = (rvfi_rs1_rdata <  rvfi_rs2_rdata);
      3'b111 : branch_taken = (rvfi_rs1_rdata >= rvfi_rs2_rdata);
      default: branch_taken = 1'b0;
    endcase
  end

  logic changes_flow, is_load;
  assign changes_flow = rvfi_trap
                     || opcode == 7'b1101111                         // JAL
                     || opcode == 7'b1100111                         // JALR
                     || rvfi_insn == 32'h3020_0073                   // MRET
                     || (opcode == 7'b1100011 && branch_taken);      // taken branch
  assign is_load = (opcode == 7'b0000011) && !rvfi_trap;

  // ---- remember the previous retirement --------------------------------------------
  logic       seen_one;       // at least one instruction has retired
  logic       prev_flow;      // previous instruction changed control flow
  logic       prev_load;      // previous instruction was a load ...
  logic [4:0] prev_rd;        // ... into this register (0 = none)
  int         gap;            // cycles since the previous retirement
  int         cycle;          // cycles since reset was released

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      seen_one <= 1'b0;
      gap      <= 0;
      cycle    <= 0;
    end else begin
      cycle <= cycle + 1;
      if (rvfi_valid) begin
        seen_one  <= 1'b1;
        prev_flow <= changes_flow;
        prev_load <= is_load;
        prev_rd   <= rvfi_rd_addr;
        gap       <= 1;
      end else begin
        gap <= gap + 1;
      end
    end
  end

  logic load_use;
  assign load_use = prev_load && prev_rd != 5'd0 &&
                    (rvfi_rs1_addr == prev_rd || rvfi_rs2_addr == prev_rd);

  int expected_gap;
  assign expected_gap = prev_flow ? REDIRECT_GAP : (load_use ? LOADUSE_GAP : 1);

  // ---- T1, T2 ------------------------------------------------------------------------
  always_comb begin
    if (rst_n && rvfi_valid) begin
      if (seen_one) assert (gap == expected_gap);          // T1
      else          assert (cycle == FIRST_RETIRE - 1);    // T2 (cycle counts from 0)
    end
    if (rst_n && !seen_one) assert (cycle < FIRST_RETIRE); // T2: nothing is late
  end

  // ---- T3: memory is used exactly one cycle before retirement ---------------------------
  logic data_req_q = 1'b0;
  always_ff @(posedge clk) data_req_q <= data_req;

  always_comb begin
    if (rst_n) assert (data_req_q == (rvfi_valid && (rvfi_mem_rmask != 0 || rvfi_mem_wmask != 0)));
  end

  // ---- throughput bounds ------------------------------------------------------------------
  // From T1 + T2: after the first retirement (cycle FIRST_RETIRE-1), one more
  // instruction retires every 1..REDIRECT_GAP cycles. So at cycle 19 between
  // MIN_AT_19 and MAX_AT_19 have retired (rabbit5: 6..16, rabbit3: 9..18).
  // Both extremes must be reachable (covers below).
  localparam int MAX_AT_19 = 19 - (FIRST_RETIRE - 1) + 1;
  localparam int MIN_AT_19 = (19 - (FIRST_RETIRE - 1)) / REDIRECT_GAP + 1;
  int retired;
  always_ff @(posedge clk) begin
    if (!rst_n)          retired <= 0;
    else if (rvfi_valid) retired <= retired + 1;
  end
  logic [31:0] retired_now;     // including an instruction retiring this cycle
  assign retired_now = retired + (rvfi_valid ? 1 : 0);

  // ---- non-vacuity: every case of T1 must really happen ------------------------------------
  always_comb begin
    if (rst_n && cycle == 19) begin
      cover (retired_now == MIN_AT_19);   // slowest possible: every instruction redirects
      cover (retired_now == MAX_AT_19);   // fastest possible: no bubbles at all
    end
    if (rst_n && rvfi_valid && seen_one) begin
      cover (gap == 1);
      cover (gap == LOADUSE_GAP && load_use);
      cover (gap == REDIRECT_GAP);
      cover (gap == REDIRECT_GAP && rvfi_trap);
    end
  end
endmodule
