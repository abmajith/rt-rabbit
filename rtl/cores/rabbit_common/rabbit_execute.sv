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
//   operands ─► ALU ─────────────► result / load-store address
//           └─► branch unit ─────► taken? target?
//           └─► CSR unit ────────► old CSR value, trap entry, MRET
//           └─► exception check ─► trap? cause?
//                                  └► next_pc, redirect
// =============================================================================
module rabbit_execute
  import rabbit_pkg::*;
#(
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
  output logic [31:0] redirect_pc_o
);

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
    if      (dec_i.illegal || csr_illegal) begin trap_cause = CAUSE_ILLEGAL_INSN; trap_tval = instr_i; end
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

  // ---- CSRs -------------------------------------------------------------------
  logic [31:0] csr_rdata, mtvec, mepc;
  logic        csr_write_req;
  // CSRRW(I) always writes; CSRRS/CSRRC(I) write only if the rs1 field is not 0
  assign csr_write_req = (dec_i.funct3[1:0] == 2'b01) || (dec_i.rs1 != 5'd0);

  rabbit_csr #(.MTVEC_RESET(MTVEC_RESET), .HART_ID(HART_ID)) u_csr (
    .clk_i, .rst_ni,
    .csr_valid_i  (valid_i && dec_i.is_csr),
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
    .mret_i       (valid_i && dec_i.is_mret),
    .instret_i    (valid_i && !trap),
    .mtvec_o      (mtvec),
    .mepc_o       (mepc)
  );

  // ---- next pc and redirect ------------------------------------------------------
  logic [31:0] next_pc;
  always_comb begin
    if      (trap)          next_pc = mtvec;
    else if (dec_i.is_mret) next_pc = mepc;
    else if (taken)         next_pc = jump_target;
    else                    next_pc = pc_i + 32'd4;
  end
  assign redirect_o    = valid_i && (trap || dec_i.is_mret || taken);
  assign redirect_pc_o = next_pc;

  // ---- the result record ------------------------------------------------------------
  always_comb begin
    res_o           = '0;
    res_o.valid     = valid_i;
    res_o.pc        = pc_i;
    res_o.instr     = instr_i;
    res_o.next_pc   = next_pc;
    res_o.trap      = trap;
    res_o.writes_rd = dec_i.writes_rd && !trap;    // a trap has no side effects
    res_o.rd        = dec_i.rd;
    unique case (dec_i.res)
      RES_PC4: res_o.result = pc_i + 32'd4;
      RES_CSR: res_o.result = csr_rdata;
      default: res_o.result = alu_y;
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
