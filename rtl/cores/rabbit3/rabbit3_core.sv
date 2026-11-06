// =============================================================================
// rabbit3_core — 3-stage in-order RV32IM pipeline (single hart)
// =============================================================================
// START HERE to learn the rabbit pipelines; then read rabbit5_core.sv.
//
//   cycle:   1    2    3    4
//   instr A  F    X    W
//   instr B       F    X    W
//
//   F : send pc to instruction memory
//   X : instruction word arrives; decode; read registers; execute;
//       send load/store to data memory                  <- commit point
//   W : load data arrives; write register; report to RVFI
//
// Why there is no forwarding logic and no load-use stall:
//   The only older instruction an instruction in X can depend on is the one in
//   W. W writes the register file in the same cycle in which X reads it, and
//   the register file passes the new value straight through ("write-first
//   bypass", rabbit_regfile.sv). That new value already includes load data,
//   because the data memory answers at the start of W.
//
// What the extra stages of rabbit5 buy instead: a shorter clock period. In
// rabbit3 one cycle must fit  memory -> load align -> register bypass -> ALU
// -> data address  (in rabbit5 that path is cut into separate stages).
//
// -----------------------------------------------------------------------------
// TIMING RULES (checked in dv/formal/rabbit/timing with CORE=rabbit3)
// -----------------------------------------------------------------------------
//   R1  One instruction retires per cycle, except:
//   R2  Load-use costs nothing (see above).
//   R3  Redirect (taken branch, JAL, JALR, MRET, any trap) is decided in X
//       and costs exactly 1 cycle (1 bubble).
//   R4  Memory must answer in exactly 1 cycle (grant in the request cycle,
//       data the next cycle).
//   R5  Nothing else ever stalls the pipeline, except WFI sleep (R7) and
//       the M extension (R8).
//   R6  Interrupts are taken in X, on the instruction there, which does not
//       retire (it runs again after MRET). The handler's first instruction
//       retires at most TIMING_IRQ_LATENCY cycles after an enabled interrupt
//       becomes pending (core.mk).
//   R7  WFI is a redirect to pc+4 (R3). If no enabled interrupt is pending,
//       fetch stops (core_sleep_o = 1) until one is; it restarts in the same
//       cycle the interrupt appears.
//   R8  MUL/MULH/MULHSU/MULHU stay 2 cycles in X, DIV/DIVU/REM/REMU 34,
//       whatever the operands: they retire 1 or 33 cycles later than
//       another instruction would. Fetch stops meanwhile (no wasted memory
//       reads). An interrupt is still taken at once (R6): the multiply or
//       divide is abandoned and runs again after MRET.
//
// So the time between two consecutive retirements is 1 or 2 cycles, plus 1
// or 33 for M instructions (R8), plus the cycles spent asleep, except around
// an interrupt (R6).
// -----------------------------------------------------------------------------
//
// What an instruction does lives in rtl/cores/rabbit_common/ (shared with
// rabbit5): rabbit_decoder, rabbit_regfile, rabbit_execute, rabbit_rvfi.
// This file is ONLY the pipeline.
// =============================================================================
module rabbit3_core
  import rabbit_pkg::*;
#(
  parameter logic [31:0] BOOT_ADDR  = 32'h0000_0080,
  parameter logic [31:0] MTVEC_ADDR = 32'h0000_0000,
  parameter logic [31:0] HART_ID    = 32'h0000_0000
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        fetch_enable_i,

  // instruction memory
  output logic        instr_req_o,
  input  logic        instr_gnt_i,
  input  logic        instr_rvalid_i,
  output logic [31:0] instr_addr_o,
  input  logic [31:0] instr_rdata_i,

  // data memory
  output logic        data_req_o,
  input  logic        data_gnt_i,
  input  logic        data_rvalid_i,
  output logic        data_we_o,
  output logic [ 3:0] data_be_o,
  output logic [31:0] data_addr_o,
  output logic [31:0] data_wdata_o,
  input  logic [31:0] data_rdata_i,

  input  logic [31:0] irq_i,          // interrupt lines: bit i = mip[i]
  output logic        core_sleep_o,   // asleep after WFI (fetch stopped)

  // RVFI: one record per retired instruction, valid in its WB cycle
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

  exec_t       w_q;            // X/W pipeline register: the executed instruction
  logic [31:0] w_result;       // its final register value (load data for loads)
  logic        redirect;
  logic [31:0] redirect_pc;

  // ===========================================================================
  // F — instruction fetch
  // ===========================================================================
  logic [31:0] pc_q;           // address requested this cycle
  logic        sleep_q;        // WFI: fetch stopped (R7)
  logic        x_sleep;        // the instruction in X is a WFI that goes to sleep
  logic        wake;           // an enabled interrupt is pending
  logic        fetch;          // a fetch happens this cycle
  logic        x_busy;         // X holds an unfinished multiply/divide (R8)

  assign fetch        = fetch_enable_i && (!sleep_q || wake) && !x_busy;
  assign instr_req_o  = fetch;
  assign instr_addr_o = pc_q;
  assign core_sleep_o = sleep_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)       pc_q <= BOOT_ADDR;
    else if (redirect) pc_q <= redirect_pc;   // R3
    else if (fetch)    pc_q <= pc_q + 32'd4;
  end

  // WFI in X: the redirect has already pointed pc_q at pc+4; just stop here
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)      sleep_q <= 1'b0;
    else if (x_sleep) sleep_q <= 1'b1;
    else if (wake)    sleep_q <= 1'b0;
  end

  // ===========================================================================
  // X — decode, register read, execute, data request
  // ===========================================================================
  logic        x_valid_q;      // the word arriving now is a real instruction
  logic [31:0] x_pc_q;         // ... fetched from this address
  // While X is held (R8) no new word arrives, so the instruction is kept in
  // a small holding register (32 flip-flops; same idea as rabbit5's ID).
  logic        x_hold_q;
  logic [31:0] x_hold_instr_q;
  logic [31:0] x_instr;

  assign x_instr = x_hold_q ? x_hold_instr_q : instr_rdata_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      x_valid_q      <= 1'b0;
      x_pc_q         <= '0;
      x_hold_q       <= 1'b0;
      x_hold_instr_q <= '0;
    end else if (redirect) begin            // the word in flight is wrong-path
      x_valid_q      <= 1'b0;
      x_hold_q       <= 1'b0;
    end else if (x_busy) begin              // keep the same instruction (R8)
      x_hold_q       <= 1'b1;
      x_hold_instr_q <= x_instr;
    end else begin
      x_valid_q      <= fetch;
      x_pc_q         <= pc_q;
      x_hold_q       <= 1'b0;
    end
  end

  decoded_t x_dec;
  rabbit_decoder u_decoder (.instr_i(x_instr), .dec_o(x_dec));

  // Register file: read in X, written in W. The write-first bypass inside
  // is this core's entire forwarding network. While X is held (R8), the
  // older instruction in W writes its result in the first cycle (bypass) and
  // W then holds bubbles, so the operand values read here stay the same.
  logic [31:0] x_rs1_val, x_rs2_val;
  rabbit_regfile u_regfile (
    .clk_i,
    .raddr_a_i(x_dec.rs1), .rdata_a_o(x_rs1_val),
    .raddr_b_i(x_dec.rs2), .rdata_b_o(x_rs2_val),
    .we_i(w_q.valid && w_q.writes_rd), .waddr_i(w_q.rd), .wdata_i(w_result)
  );

  exec_t x_res;
  rabbit_execute #(.MTVEC_RESET(MTVEC_ADDR), .HART_ID(HART_ID)) u_execute (
    .clk_i, .rst_ni,
    .valid_i      (x_valid_q),
    .pc_i         (x_pc_q),
    .instr_i      (x_instr),
    .dec_i        (x_dec),
    .rs1_i        (x_rs1_val),
    .rs2_i        (x_rs2_val),
    .res_o        (x_res),
    .redirect_o   (redirect),
    .redirect_pc_o(redirect_pc),
    .busy_o       (x_busy),
    .irq_i,
    .sleep_o      (x_sleep),
    .wake_o       (wake)
  );

  // the data access leaves directly from X; the answer arrives in W (rule R4)
  assign data_req_o   = x_res.valid && (x_res.is_load || x_res.is_store);
  assign data_we_o    = x_res.is_store;
  assign data_addr_o  = {x_res.addr[31:2], 2'b00};
  assign data_be_o    = x_res.mem_be;
  assign data_wdata_o = x_res.mem_wdata;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) w_q <= '0;
    else         w_q <= x_res;
  end

  // ===========================================================================
  // W — load data arrives, write the register file, report to RVFI
  // ===========================================================================
  assign w_result = w_q.is_load ? lsu_load_value(w_q.funct3, w_q.addr[1:0], data_rdata_i)
                                : w_q.result;

  rabbit_rvfi u_rvfi (
    .clk_i, .rst_ni,
    .retire_i(w_q), .rd_wdata_i(w_result), .mem_rdata_i(data_rdata_i),
    .rvfi_valid, .rvfi_order, .rvfi_insn, .rvfi_trap, .rvfi_halt, .rvfi_intr,
    .rvfi_mode, .rvfi_ixl, .rvfi_rs1_addr, .rvfi_rs2_addr, .rvfi_rs1_rdata,
    .rvfi_rs2_rdata, .rvfi_rd_addr, .rvfi_rd_wdata, .rvfi_pc_rdata, .rvfi_pc_wdata,
    .rvfi_mem_addr, .rvfi_mem_rmask, .rvfi_mem_wmask, .rvfi_mem_rdata, .rvfi_mem_wdata
  );

`ifndef SYNTHESIS
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (rst_ni) begin
      if (instr_req_o && !instr_gnt_i) $error("rabbit3: instruction memory must grant immediately (rule R4)");
      if (data_req_o  && !data_gnt_i)  $error("rabbit3: data memory must grant immediately (rule R4)");
    end
  end
`endif

  logic unused;
  assign unused = ^{instr_rvalid_i, data_rvalid_i};

endmodule
