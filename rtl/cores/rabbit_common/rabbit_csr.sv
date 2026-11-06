// =============================================================================
// rabbit_csr — machine-mode CSRs, trap state and the interrupt controller
// =============================================================================
// All CSR reads/writes and all trap bookkeeping happen for the instruction in
// EX. EX is the "commit point": nothing after EX can trap, so an instruction
// that leaves EX without a trap is guaranteed to retire.
//
// Implemented: mstatus (MIE, MPIE; MPP fixed to M), misa, mie, mip,
// mtvec (direct or vectored), mscratch, mepc, mcause, mtval, mcycle[h],
// minstret[h], mhartid.
// Any other address -> illegal instruction (reported back to EX).
//
// Interrupts — two levels of "enable", as in the RISC-V spec:
//   mip[i]        line i is asking            (= irq_i[i], read-only)
//   mie[i]        line i is allowed           (per-line enable, software)
//   mstatus.MIE   interrupts are allowed now  (global; cleared on trap entry)
//
//   irq_wake_o    = some line is asking AND allowed   -> ends WFI sleep
//   irq_pending_o = irq_wake_o AND mstatus.MIE        -> take an interrupt
//
// The interrupt lines are NOT registered here: an irq_i edge can be taken in
// the same cycle (lowest latency). The source must therefore be a flip-flop
// in the clock domain of the core (the rabbit_timer and peripherals are).
// =============================================================================
module rabbit_csr
  import rabbit_pkg::*;
#(
  parameter logic [31:0] MTVEC_RESET = 32'h0,
  parameter logic [31:0] HART_ID     = 32'h0
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // CSR instruction in EX
  input  logic        csr_valid_i,   // a CSR instruction is executing (and not trapping for another reason)
  input  logic [11:0] csr_addr_i,
  input  logic [1:0]  csr_op_i,      // funct3[1:0]: 01 = write, 10 = set, 11 = clear
  input  logic        csr_write_i,   // the instruction asks to write (RS/RC with x0/0 do not)
  input  logic [31:0] csr_src_i,     // rs1 value or zero-extended immediate
  output logic [31:0] csr_rdata_o,   // old value -> rd
  output logic        csr_illegal_o, // unknown CSR, or write to a read-only CSR

  // Trap / return from trap
  input  logic        trap_i,
  input  logic [31:0] trap_cause_i,
  input  logic [31:0] trap_pc_i,
  input  logic [31:0] trap_tval_i,
  input  logic        mret_i,

  // Counting
  input  logic        instret_i,     // an instruction committed in EX this cycle

  // Interrupts
  input  logic [31:0] irq_i,         // level-sensitive request lines
  output logic        irq_wake_o,    // an enabled line is asking (wakes WFI)
  output logic        irq_pending_o, // ... and interrupts are globally enabled
  output logic [ 4:0] irq_id_o,      // the line to take (see irq_priority)

  output logic [31:0] mtvec_o,
  output logic [31:0] mepc_o
);
  logic        mstatus_mie_q, mstatus_mpie_q;
  logic [31:0] mie_q;                // per-line enables (only IRQ_MASK bits exist)
  logic [31:0] mtvec_q, mscratch_q, mepc_q, mcause_q, mtval_q;
  logic [63:0] mcycle_q, minstret_q;

  // ---- interrupt requests ------------------------------------------------------
  logic [31:0] mip, enabled;
  assign mip           = irq_i & IRQ_MASK;
  assign enabled       = mip & mie_q;
  assign irq_wake_o    = |enabled;
  assign irq_pending_o = irq_wake_o && mstatus_mie_q;
  assign irq_id_o      = irq_priority(enabled);

  // ---- read side ------------------------------------------------------------
  logic known;
  always_comb begin
    known       = 1'b1;
    csr_rdata_o = 32'b0;
    unique case (csr_addr_i)
      CSR_MSTATUS  : csr_rdata_o = {19'b0, 2'b11, 3'b0, mstatus_mpie_q, 3'b0, mstatus_mie_q, 3'b0};
      CSR_MISA     : csr_rdata_o = MISA_VALUE;
      CSR_MIE      : csr_rdata_o = mie_q;
      CSR_MIP      : csr_rdata_o = mip;
      CSR_MTVEC    : csr_rdata_o = mtvec_q;
      CSR_MSCRATCH : csr_rdata_o = mscratch_q;
      CSR_MEPC     : csr_rdata_o = mepc_q;
      CSR_MCAUSE   : csr_rdata_o = mcause_q;
      CSR_MTVAL    : csr_rdata_o = mtval_q;
      CSR_MCYCLE   : csr_rdata_o = mcycle_q[31:0];
      CSR_MCYCLEH  : csr_rdata_o = mcycle_q[63:32];
      CSR_MINSTRET : csr_rdata_o = minstret_q[31:0];
      CSR_MINSTRETH: csr_rdata_o = minstret_q[63:32];
      CSR_MHARTID  : csr_rdata_o = HART_ID;
      default      : known       = 1'b0;
    endcase
  end

  // CSR addresses 0xCxx..0xFxx (top two bits = 11) are read-only by definition.
  logic read_only;
  assign read_only     = (csr_addr_i[11:10] == 2'b11);
  assign csr_illegal_o = csr_valid_i && (!known || (read_only && csr_write_i));

  // ---- write side -------------------------------------------------------------
  logic [31:0] wdata;
  always_comb begin
    unique case (csr_op_i)
      2'b01  : wdata = csr_src_i;                 // CSRRW(I)
      2'b10  : wdata = csr_rdata_o |  csr_src_i;  // CSRRS(I)
      2'b11  : wdata = csr_rdata_o & ~csr_src_i;  // CSRRC(I)
      default: wdata = csr_rdata_o;
    endcase
  end

  logic we;
  assign we = csr_valid_i && csr_write_i && !csr_illegal_o;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mstatus_mie_q  <= 1'b0;        // interrupts start disabled
      mstatus_mpie_q <= 1'b0;
      mie_q      <= '0;
      mtvec_q    <= {MTVEC_RESET[31:2], 2'b01};   // vectored, like CV32E40P
      mscratch_q <= '0;
      mepc_q     <= '0;
      mcause_q   <= '0;
      mtval_q    <= '0;
      mcycle_q   <= '0;
      minstret_q <= '0;
    end else begin
      // free-running counters (an explicit write below takes priority)
      mcycle_q <= mcycle_q + 64'd1;
      if (instret_i) minstret_q <= minstret_q + 64'd1;

      if (trap_i) begin
        mepc_q   <= trap_pc_i;
        mcause_q <= trap_cause_i;
        mtval_q  <= trap_tval_i;
        mstatus_mpie_q <= mstatus_mie_q;   // remember, then block nesting
        mstatus_mie_q  <= 1'b0;
      end else if (mret_i) begin
        mstatus_mie_q  <= mstatus_mpie_q;
        mstatus_mpie_q <= 1'b1;
      end else if (we) begin
        unique case (csr_addr_i)
          CSR_MSTATUS  : begin mstatus_mie_q <= wdata[3]; mstatus_mpie_q <= wdata[7]; end
          CSR_MIE      : mie_q      <= wdata & IRQ_MASK;
          CSR_MTVEC    : mtvec_q    <= {wdata[31:2], 1'b0, wdata[0]};  // mode 0 or 1
          CSR_MSCRATCH : mscratch_q <= wdata;
          CSR_MEPC     : mepc_q     <= {wdata[31:2], 2'b00};   // IALIGN = 32
          CSR_MCAUSE   : mcause_q   <= wdata;
          CSR_MTVAL    : mtval_q    <= wdata;
          CSR_MCYCLE   : mcycle_q[31:0]    <= wdata;
          CSR_MCYCLEH  : mcycle_q[63:32]   <= wdata;
          CSR_MINSTRET : minstret_q[31:0]  <= wdata;
          CSR_MINSTRETH: minstret_q[63:32] <= wdata;
          default      : ;   // misa, mip, mhartid: writes ignored
        endcase
      end
    end
  end

  assign mtvec_o = mtvec_q;
  assign mepc_o  = mepc_q;
endmodule
