// =============================================================================
// rabbit5_core — 5-stage in-order RV32IM pipeline (single hart)
// =============================================================================
//
//   cycle:   1    2    3    4    5    6
//   instr A  IF   ID   EX   MEM  WB
//   instr B       IF   ID   EX   MEM  WB
//
//   IF  : send pc to instruction memory
//   ID  : instruction word arrives; decode; read registers; detect load-use
//   EX  : ALU, branch decision, CSR access, traps        <- commit point
//   MEM : send load/store to data memory
//   WB  : load data arrives; write register; report to RVFI
//
// -----------------------------------------------------------------------------
// TIMING RULES (checked in dv/formal/rabbit/timing with CORE=rabbit5;
//               the numbers are declared in core.mk)
// -----------------------------------------------------------------------------
//   R1  One instruction retires per cycle, except:
//   R2  Load-use: if an instruction reads the register loaded by the load
//       directly before it, it waits exactly 1 cycle (1 bubble).
//   R3  Redirect: every change of control flow — taken branch, JAL, JALR,
//       MRET, any trap — is decided in EX and costs exactly 2 cycles
//       (2 bubbles). No branch prediction, so the cost never depends on history.
//   R4  Memory must answer in exactly 1 cycle (grant in the request cycle,
//       data the next cycle). This is the scratchpad-memory assumption from
//       FlexPRET/Patmos; the core never waits on memory.
//   R5  Nothing else ever stalls the pipeline, except WFI sleep (R7) and
//       the M extension (R8).
//   R6  Interrupts are taken in EX, on the instruction there, which does not
//       retire (it runs again after MRET); IF and ID are flushed as for any
//       redirect, MEM and WB are older and finish. The handler's first
//       instruction retires at most TIMING_IRQ_LATENCY cycles after an
//       enabled interrupt becomes pending (core.mk).
//   R7  WFI is a redirect to pc+4 (R3). If no enabled interrupt is pending,
//       fetch stops (core_sleep_o = 1) until one is; it restarts in the same
//       cycle the interrupt appears.
//   R8  MUL/MULH/MULHSU/MULHU stay 2 cycles in EX, DIV/DIVU/REM/REMU 34,
//       whatever the operands: they retire 1 or 33 cycles later than
//       another instruction would. IF and ID wait (no fetch meanwhile); MEM
//       and WB drain. An interrupt is still taken at once (R6): the
//       multiply or divide is abandoned and runs again after MRET.
//
// So the time between two consecutive retirements is 1, 2 (R2) or 3 (R3)
// cycles, plus 1 or 33 for M instructions (R8), and depends only on those
// two instructions, plus the cycles spent asleep, except around an
// interrupt (R6).
//
// Interrupts and WFI are the same as in rabbit3 (see rabbit3/README.md); only
// the stage that takes them differs (EX here, X there).
// -----------------------------------------------------------------------------
//
// This file is ONLY the pipeline: stage registers, hazards, forwarding.
// What an instruction does is in rtl/cores/rabbit_common/ (shared with rabbit3):
//   rabbit_decoder (ID), rabbit_regfile, rabbit_execute (EX, incl. CSRs/traps),
//   rabbit_rvfi (reporting). Compare with rabbit3_core.sv to see what two
//   extra stages cost and buy.
//
// Bus: OBI-style request/grant/rvalid, as in the rabbit_cpu contract.
// Verification port: RVFI (riscv-formal interface), always present; it costs
// nothing in synthesis when left unconnected.
// =============================================================================
module rabbit5_core
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

  // ===========================================================================
  // Pipeline registers
  // ===========================================================================
  // ID/EX: a decoded instruction plus the register values read in ID
  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] instr;
    decoded_t    dec;
    logic [31:0] rs1_val;   // EX may replace these by newer values (forwarding)
    logic [31:0] rs2_val;
  } ex_stage_t;

  ex_stage_t ex_q;      // ID/EX
  exec_t     mem_q;     // EX/MEM : result of rabbit_execute
  exec_t     wb_q;      // MEM/WB : same record, one stage later

  logic        redirect;       // EX changes control flow this cycle
  logic [31:0] redirect_pc;
  logic        stall;          // ID must wait one cycle (load-use)
  logic        ex_busy;        // EX holds an unfinished multiply/divide (R8)
  logic        id_hold;        // the instruction in ID stays there
  logic [31:0] wb_result;      // final register value of the instruction in WB

  // ===========================================================================
  // IF — instruction fetch
  // ===========================================================================
  // pc_q is the address requested *this* cycle. The memory answers next
  // cycle, when the instruction is in ID (rule R4).
  logic [31:0] pc_q;
  logic        sleep_q;        // WFI: fetch stopped (R7)
  logic        ex_sleep;       // the instruction in EX is a WFI that goes to sleep
  logic        wake;           // an enabled interrupt is pending
  logic        fetch;          // a fetch happens this cycle

  assign fetch        = fetch_enable_i && (!sleep_q || wake) && !ex_busy;
  assign instr_req_o  = fetch;
  assign instr_addr_o = pc_q;
  assign core_sleep_o = sleep_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)       pc_q <= BOOT_ADDR;
    else if (redirect) pc_q <= redirect_pc;   // R3
    else if (id_hold)  pc_q <= pc_q;          // R2: ask for the same word again (R8: no fetch)
    else if (fetch)    pc_q <= pc_q + 32'd4;
  end

  // WFI in EX: the redirect has already pointed pc_q at pc+4; just stop here
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)       sleep_q <= 1'b0;
    else if (ex_sleep) sleep_q <= 1'b1;
    else if (wake)     sleep_q <= 1'b0;
  end

  // ===========================================================================
  // ID — decode and register read
  // ===========================================================================
  // While ID waits (load-use stall, or EX busy with R8), the memory returns
  // another word or none at all, so the waiting instruction is kept in a
  // small holding register.
  logic        id_valid_q;
  logic [31:0] id_pc_q;
  logic        id_hold_q;
  logic [31:0] id_hold_instr_q;
  logic [31:0] id_instr;

  assign id_instr = id_hold_q ? id_hold_instr_q : instr_rdata_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      id_valid_q      <= 1'b0;
      id_hold_q       <= 1'b0;
      id_hold_instr_q <= '0;
      id_pc_q         <= '0;
    end else if (redirect) begin            // wrong-path instruction: drop it
      id_valid_q      <= 1'b0;
      id_hold_q       <= 1'b0;
    end else if (id_hold) begin             // keep the same instruction
      id_hold_q       <= 1'b1;
      id_hold_instr_q <= id_instr;
    end else begin                          // take the word requested this cycle
      id_valid_q      <= fetch;
      id_hold_q       <= 1'b0;
      id_pc_q         <= pc_q;
    end
  end

  decoded_t id_dec;
  rabbit_decoder u_decoder (.instr_i(id_instr), .dec_o(id_dec));

  // Register file: read in ID, written in WB (write-first bypass inside)
  logic [31:0] id_rs1_val, id_rs2_val;
  rabbit_regfile u_regfile (
    .clk_i,
    .raddr_a_i(id_dec.rs1), .rdata_a_o(id_rs1_val),
    .raddr_b_i(id_dec.rs2), .rdata_b_o(id_rs2_val),
    .we_i(wb_q.valid && wb_q.writes_rd), .waddr_i(wb_q.rd), .wdata_i(wb_result)
  );

  // Load-use hazard (rule R2): the load is in EX now, its data only exists
  // in WB, two cycles from now. Hold the dependent instruction for one cycle.
  logic load_use;
  assign load_use = id_valid_q && ex_q.valid && ex_q.dec.is_load && ex_q.dec.writes_rd &&
                    ((id_dec.uses_rs1 && id_dec.rs1 == ex_q.dec.rd) ||
                     (id_dec.uses_rs2 && id_dec.rs2 == ex_q.dec.rd));
  assign stall   = load_use && !redirect;   // a redirect throws the ID instruction away anyway
  assign id_hold = stall || ex_busy;

  // While EX is busy (R8) it keeps its instruction, but takes the operand
  // values it is using now: the older instructions it forwards from leave
  // MEM and WB meanwhile, and the operands must not change (rabbit_execute).
  logic [31:0] ex_rs1, ex_rs2;               // operands after forwarding
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)                  ex_q       <= '0;
    else if (redirect || stall)   ex_q.valid <= 1'b0;   // insert a bubble
    else if (ex_busy) begin
      ex_q.rs1_val <= ex_rs1;
      ex_q.rs2_val <= ex_rs2;
    end else begin
      ex_q.valid   <= id_valid_q;
      ex_q.pc      <= id_pc_q;
      ex_q.instr   <= id_instr;
      ex_q.dec     <= id_dec;
      ex_q.rs1_val <= id_rs1_val;
      ex_q.rs2_val <= id_rs2_val;
    end
  end

  // ===========================================================================
  // EX — forwarding + rabbit_execute
  // ===========================================================================
  // The values read in ID may be out of date: an older instruction that is
  // now in MEM or WB has not written the register file yet. Use the newest.
  // Priority: MEM (younger) over WB (older) over the value read in ID.
  // A load in MEM never needs forwarding here: R2 guarantees a bubble.
  function automatic logic [31:0] forward(input logic [4:0] r, input logic [31:0] id_val);
    if      (mem_q.valid && mem_q.writes_rd && !mem_q.is_load && mem_q.rd == r) return mem_q.result;
    else if (wb_q.valid  && wb_q.writes_rd  && wb_q.rd == r)                    return wb_result;
    else                                                                         return id_val;
  endfunction

  assign ex_rs1 = forward(ex_q.dec.rs1, ex_q.rs1_val);
  assign ex_rs2 = forward(ex_q.dec.rs2, ex_q.rs2_val);

  exec_t ex_res;
  rabbit_execute #(.MTVEC_RESET(MTVEC_ADDR), .HART_ID(HART_ID)) u_execute (
    .clk_i, .rst_ni,
    .valid_i      (ex_q.valid),
    .pc_i         (ex_q.pc),
    .instr_i      (ex_q.instr),
    .dec_i        (ex_q.dec),
    .rs1_i        (ex_rs1),
    .rs2_i        (ex_rs2),
    .res_o        (ex_res),
    .redirect_o   (redirect),
    .redirect_pc_o(redirect_pc),
    .busy_o       (ex_busy),
    .irq_i,
    .sleep_o      (ex_sleep),
    .wake_o       (wake)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) mem_q <= '0;
    else         mem_q <= ex_res;
  end

  // ===========================================================================
  // MEM — issue the data access (the answer arrives in WB, rule R4)
  // ===========================================================================
  assign data_req_o   = mem_q.valid && (mem_q.is_load || mem_q.is_store);
  assign data_we_o    = mem_q.is_store;
  assign data_addr_o  = {mem_q.addr[31:2], 2'b00};
  assign data_be_o    = mem_q.mem_be;
  assign data_wdata_o = mem_q.mem_wdata;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) wb_q <= '0;
    else         wb_q <= mem_q;
  end

  // ===========================================================================
  // WB — load data arrives, write the register file, report to RVFI
  // ===========================================================================
  assign wb_result = wb_q.is_load ? lsu_load_value(wb_q.funct3, wb_q.addr[1:0], data_rdata_i)
                                  : wb_q.result;

  rabbit_rvfi u_rvfi (
    .clk_i, .rst_ni,
    .retire_i(wb_q), .rd_wdata_i(wb_result), .mem_rdata_i(data_rdata_i),
    .rvfi_valid, .rvfi_order, .rvfi_insn, .rvfi_trap, .rvfi_halt, .rvfi_intr,
    .rvfi_mode, .rvfi_ixl, .rvfi_rs1_addr, .rvfi_rs2_addr, .rvfi_rs1_rdata,
    .rvfi_rs2_rdata, .rvfi_rd_addr, .rvfi_rd_wdata, .rvfi_pc_rdata, .rvfi_pc_wdata,
    .rvfi_mem_addr, .rvfi_mem_rmask, .rvfi_mem_wmask, .rvfi_mem_rdata, .rvfi_mem_wdata
  );

  // ===========================================================================
  // Simulation-only check of rule R4 (the memory contract)
  // ===========================================================================
`ifndef SYNTHESIS
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (rst_ni) begin
      if (instr_req_o && !instr_gnt_i) $error("rabbit5: instruction memory must grant immediately (rule R4)");
      if (data_req_o  && !data_gnt_i)  $error("rabbit5: data memory must grant immediately (rule R4)");
    end
  end
`endif

  // Inputs that are not used (kept so the port list matches rabbit_cpu)
  logic unused;
  assign unused = ^{instr_rvalid_i, data_rvalid_i};

endmodule
