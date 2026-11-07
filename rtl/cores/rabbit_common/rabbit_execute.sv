// =============================================================================
// rabbit_execute — the execute stage logic, shared by every rabbit core
// =============================================================================
// Input : one decoded instruction and its two operand values. Getting the
//         *right* operand values (forwarding, stalls) is the pipeline's job,
//         not this module's.
// Output: an exec_t record (what the instruction did) and, if control flow
//         changes, a redirect.
//
// This is the commit point of every rabbit core: all exceptions are found
// here and all CSR state changes here. An instruction that leaves execute
// without a trap is guaranteed to retire.
//
// Interrupts are taken here too. If an enabled interrupt is pending while a
// valid instruction is in execute, that instruction is NOT executed: it does
// not retire (res_o.valid = 0), changes nothing, and its pc goes to mepc, so
// MRET will run it later. Everything older has already passed the commit
// point and simply finishes. The first instruction of the handler is marked
// res_o.intr = 1 (RVFI convention).
//
// WFI is executed as a jump to pc+4 (so nothing fetched after it runs) and
// asks the pipeline to sleep (sleep_o) unless an enabled interrupt is
// already pending. The pipeline stops fetching until wake_o.
//
// M extension (rabbit_muldiv, only if CFG.rv32m): a multiply takes 2 cycles in execute, a
// divide 34, whatever the operands. Until it is done, busy_o = 1: the
// pipeline must keep the instruction here, with the same operand values,
// and let nothing younger move. An interrupt ends the wait at once: the
// multiply/divide is abandoned and runs again after MRET, so the interrupt
// latency does not grow.
//
//   operands ─► ALU ─────────────► result / load-store address
//           └─► branch unit ─────► taken? target?
//           └─► CSR unit ────────► old CSR value, trap entry, MRET
//           └─► rabbit_muldiv ───► product / quotient (2 or 34 cycles)
//           └─► exception check ─► trap? cause?
//                                  └► next_pc, redirect
// =============================================================================
module rabbit_execute
  import rabbit_pkg::*;
#(
  parameter rabbit_cfg_t CFG         = RABBIT_CFG,
  parameter logic [31:0] MTVEC_RESET = 32'h0,
  parameter logic [31:0] HART_ID     = 32'h0
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        valid_i,
  input  logic [31:0] pc_i,
  input  logic [31:0] instr_i,
  input  decoded_t    dec_i,
  input  logic [31:0] rs1_i,         // operand values, already up to date
  input  logic [31:0] rs2_i,

  output exec_t       res_o,
  output logic        redirect_o,    // control flow changes: fetch from redirect_pc_o
  output logic [31:0] redirect_pc_o,
  output logic        busy_o,        // M instruction not finished: hold it in execute

  input  logic [31:0] irq_i,         // interrupt request lines (see rabbit_pkg)
  output logic        sleep_o,       // WFI executed: stop fetching ...
  output logic        wake_o         // ... until this is 1
);

  // ---- interrupt: replaces the instruction in execute -------------------------
  logic       irq_pending, irq_take;
  logic [4:0] irq_id;
  assign irq_take = valid_i && irq_pending;

  // RVFI: the next instruction that executes is the first one of the handler
  // (cleared when an instruction leaves execute: an M instruction may wait)
  logic intr_next_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)                 intr_next_q <= 1'b0;
    else if (irq_take)           intr_next_q <= 1'b1;
    else if (valid_i && !busy_o) intr_next_q <= 1'b0;
  end


  // ---- ALU ------------------------------------------------------------------
  logic [31:0] alu_a, alu_b, alu_y;
  always_comb begin
    unique case (dec_i.opa)
      OPA_RS1: alu_a = rs1_i;
      OPA_PC : alu_a = pc_i;
      default: alu_a = 32'b0;
    endcase
    alu_b = (dec_i.opb == OPB_RS2) ? rs2_i : dec_i.imm;
  end

  rabbit_alu u_alu (.op_i(dec_i.alu_op), .a_i(alu_a), .b_i(alu_b), .y_o(alu_y));

  // ---- branches and jumps -----------------------------------------------------
  logic        taken;
  logic [31:0] jump_target;
  assign taken       = dec_i.is_jal || dec_i.is_jalr ||
                       (dec_i.is_branch && branch_taken(dec_i.funct3, rs1_i, rs2_i));
  assign jump_target = dec_i.is_jalr ? ((rs1_i + dec_i.imm) & ~32'd1)
                                     : (pc_i + dec_i.imm);

  // ---- exceptions ---------------------------------------------------------------
  logic csr_illegal;
  logic target_misaligned, mem_misaligned;
  assign target_misaligned = taken && (jump_target[1:0] != 2'b00);
  assign mem_misaligned    = (dec_i.is_load || dec_i.is_store) &&
                             lsu_misaligned(dec_i.funct3[1:0], alu_y[1:0]);

  logic        trap;
  logic [31:0] trap_cause, trap_tval;
  always_comb begin
    trap      = 1'b1;
    trap_tval = 32'b0;
    if      (irq_pending)                  trap_cause = {1'b1, 26'b0, irq_id};
    else if (dec_i.illegal || csr_illegal) begin trap_cause = CAUSE_ILLEGAL_INSN; trap_tval = instr_i; end
    else if (dec_i.is_ecall)               trap_cause = CAUSE_ECALL_M;
    else if (dec_i.is_ebreak)              trap_cause = CAUSE_BREAKPOINT;
    else if (target_misaligned)    begin trap_cause = CAUSE_INSN_MISALIGNED; trap_tval = jump_target; end
    else if (mem_misaligned)       begin
      trap_cause = dec_i.is_load ? CAUSE_LOAD_MISALIGNED : CAUSE_STORE_MISALIGNED;
      trap_tval  = alu_y;
    end
    else begin trap = 1'b0; trap_cause = 32'b0; end
    trap = trap && valid_i;
  end

  // ---- M extension ---------------------------------------------------------------
  // Without M the decoder never sets is_muldiv, so md_req stays 0 and none of
  // this exists in the netlist.
  logic        md_req, md_done;
  logic [31:0] md_result;
  assign md_req = valid_i && dec_i.is_muldiv && !irq_pending;
  assign busy_o = md_req && !md_done;

  if (CFG.rv32m) begin : g_muldiv
`ifdef RABBIT_DIV_STEPS
    localparam int unsigned DIV_STEPS = `RABBIT_DIV_STEPS;   // formal only, see rabbit_muldiv
`else
    localparam int unsigned DIV_STEPS = 32;
`endif

    logic [31:0] md_value;
    rabbit_muldiv #(.W(32), .DIV_STEPS(DIV_STEPS)) u_muldiv (
      .clk_i, .rst_ni,
      .en_i    (valid_i && dec_i.is_muldiv),
      .req_i   (md_req),
      .op_i    (dec_i.funct3),
      .a_i     (rs1_i),
      .b_i     (rs2_i),
      .done_o  (md_done),
      .result_o(md_value)
    );

`ifdef RISCV_FORMAL_ALTOPS
    // riscv-formal cannot reason about real multiplication and division; with
    // ALTOPS it expects these stand-in results instead (same timing). The real
    // arithmetic is proven separately: dv/formal/rabbit/muldiv.
    always_comb begin
      unique case (dec_i.funct3)
        3'd0:    md_result = (rs1_i + rs2_i) ^ 32'h5876_063e;   // MUL
        3'd1:    md_result = (rs1_i + rs2_i) ^ 32'hf658_3fb7;   // MULH
        3'd2:    md_result = (rs1_i - rs2_i) ^ 32'hecfb_e137;   // MULHSU
        3'd3:    md_result = (rs1_i + rs2_i) ^ 32'h949c_e5e8;   // MULHU
        3'd4:    md_result = (rs1_i - rs2_i) ^ 32'h7f85_29ec;   // DIV
        3'd5:    md_result = (rs1_i - rs2_i) ^ 32'h10e8_fd70;   // DIVU
        3'd6:    md_result = (rs1_i - rs2_i) ^ 32'h8da6_8fa5;   // REM
        default: md_result = (rs1_i - rs2_i) ^ 32'h3138_d0e1;   // REMU
      endcase
    end
    logic unused_md;
    assign unused_md = ^md_value;
`else
    assign md_result = md_value;
`endif

`ifndef SYNTHESIS
    // The contract with the pipeline: the operands do not change while an M
    // instruction is held here (also proven in dv/formal/rabbit/timing, M0).
    logic        busy_q;
    logic [31:0] rs1_q, rs2_q;
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) busy_q <= 1'b0;
      else begin
        busy_q <= busy_o; rs1_q <= rs1_i; rs2_q <= rs2_i;
        if (busy_q && md_req && (rs1_i != rs1_q || rs2_i != rs2_q))
          $error("rabbit_execute: operands changed while a multiply/divide was held");
      end
    end
`endif
  end else begin : g_no_muldiv
    assign md_done   = 1'b1;
    assign md_result = 32'b0;
  end

  // ---- CSRs -------------------------------------------------------------------
  logic [31:0] csr_rdata, mtvec, mepc;
  logic        csr_write_req;
  // CSRRW(I) always writes; CSRRS/CSRRC(I) write only if the rs1 field is not 0
  assign csr_write_req = (dec_i.funct3[1:0] == 2'b01) || (dec_i.rs1 != 5'd0);

  rabbit_csr #(.CFG(CFG), .MTVEC_RESET(MTVEC_RESET), .HART_ID(HART_ID)) u_csr (
    .clk_i, .rst_ni,
    .csr_valid_i  (valid_i && dec_i.is_csr && !irq_pending),
    .csr_addr_i   (instr_i[31:20]),
    .csr_op_i     (dec_i.funct3[1:0]),
    .csr_write_i  (csr_write_req),
    .csr_src_i    (dec_i.funct3[2] ? dec_i.imm : rs1_i),
    .csr_rdata_o  (csr_rdata),
    .csr_illegal_o(csr_illegal),
    .trap_i       (trap),
    .trap_cause_i (trap_cause),
    .trap_pc_i    (pc_i),
    .trap_tval_i  (trap_tval),
    .mret_i       (valid_i && dec_i.is_mret && !trap),
    .instret_i    (valid_i && !trap && !busy_o),
    .irq_i,
    .irq_wake_o   (wake_o),
    .irq_pending_o(irq_pending),
    .irq_id_o     (irq_id),
    .mtvec_o      (mtvec),
    .mepc_o       (mepc)
  );

  // ---- next pc and redirect ------------------------------------------------------
  logic [31:0] next_pc;
  always_comb begin
    if      (trap)          next_pc = trap_target(mtvec, irq_take, irq_id);
    else if (dec_i.is_mret) next_pc = mepc;
    else if (taken)         next_pc = jump_target;
    else                    next_pc = pc_i + 32'd4;
  end
  assign redirect_o    = valid_i && (trap || dec_i.is_mret || taken || dec_i.is_wfi);
  assign redirect_pc_o = next_pc;

  // ---- WFI ----------------------------------------------------------------------
  assign sleep_o = valid_i && dec_i.is_wfi && !trap && !wake_o;

  // ---- the result record ------------------------------------------------------------
  always_comb begin
    res_o           = '0;
    res_o.valid     = valid_i && !irq_take && !busy_o;  // interrupted / not finished: no
    res_o.pc        = pc_i;
    res_o.instr     = instr_i;
    res_o.next_pc   = next_pc;
    res_o.trap      = trap;
    res_o.intr      = intr_next_q;
    res_o.writes_rd = dec_i.writes_rd && !trap;    // a trap has no side effects
    res_o.rd        = dec_i.rd;
    unique case (dec_i.res)
      RES_PC4: res_o.result = pc_i + 32'd4;
      RES_CSR: res_o.result = csr_rdata;
      default: res_o.result = dec_i.is_muldiv ? md_result : alu_y;
    endcase
    res_o.is_load   = dec_i.is_load  && !trap;
    res_o.is_store  = dec_i.is_store && !trap;
    res_o.funct3    = dec_i.funct3;
    res_o.addr      = alu_y;
    res_o.mem_be    = lsu_byte_enable(dec_i.funct3[1:0], alu_y[1:0]);
    res_o.mem_wdata = lsu_store_lanes(dec_i.funct3[1:0], rs2_i);
    res_o.rs1_addr  = dec_i.uses_rs1 ? dec_i.rs1 : 5'd0;
    res_o.rs2_addr  = dec_i.uses_rs2 ? dec_i.rs2 : 5'd0;
    res_o.rs1_val   = dec_i.uses_rs1 ? rs1_i : 32'd0;
    res_o.rs2_val   = dec_i.uses_rs2 ? rs2_i : 32'd0;
  end

endmodule
