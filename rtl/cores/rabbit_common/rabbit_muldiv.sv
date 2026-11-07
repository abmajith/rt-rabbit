// =============================================================================
// rabbit_muldiv — RISC-V M extension: multiply and divide, fixed latency
// =============================================================================
// Used by rabbit_execute. The instruction stays in execute (the commit point)
// until done_o; the pipeline holds it there (rabbit_execute.busy_o).
//
// LATENCY never depends on the operand values (robot control loops need a
// worst case that is also the normal case, and the timing proof needs it):
//
//   MUL, MULH, MULHSU, MULHU   2 cycles in execute   (MUL_CYCLES)
//   DIV, DIVU, REM, REMU       W+2 cycles = 34       (DIV_CYCLES)
//                              (also for x/0 and the -2^31/-1 overflow)
//
// MULTIPLIER — one (W+1) x (H+1) signed multiplier, used twice (H = W/2):
//
//   A = rs1, sign- or zero-extended to W+1 bits
//   B = B_hi * 2^H + B_lo      B_lo = rs2[H-1:0] (always unsigned)
//                              B_hi = rs2[W-1:H] (signed for MUL/MULH)
//   cycle 1:  P0 = A * B_lo                       -> register p0_q
//   cycle 2:  P1 = A * B_hi + (P0 >>> H)          (the add is fused into the
//                                                  multiplier's adder tree)
//   A * B  =  {P1, P0[H-1:0]}      MUL = low W bits, MULH* = high W bits
//
//   Why this size: a full 33x33 multiplier is 1.75x the area and its delay
//   would be the core's longest path; Ibex' 17x17 MAC needs 3-4 cycles.
//   Measured on sky130 in docs: rtl/cores/rabbit_common/README.md.
//
// DIVIDER — restoring long division on the magnitudes, one bit per cycle:
//
//   cycle 1       : quo = |rs1|, rem = 0, keep rs2 and the signs
//   cycles 2..W+1 : {rem, quo} <<= 1; if rem >= |rs2|: rem -= |rs2|, quo[0] = 1
//   cycle W+2     : apply the signs, result out (done_o)
//
//   x/0 needs no special path: every subtraction of 0 succeeds, so the
//   quotient is all ones and the remainder is x, exactly what RISC-V asks for
//   (only the sign fix-up of the quotient is skipped for x/0).
//   -2^31 / -1 needs none either: |x| = 2^31 fits in W unsigned bits, and the
//   quotient 2^31 reinterpreted as signed is -2^31, as required.
//
// POWER (operand isolation): the multiplier and the negator see zeros unless
// an M instruction is in execute (en_i). Without this, the 33x17 multiplier
// would switch on the operands of every ADD, load, branch ... for nothing.
// en_i comes from decode only (not from the interrupt logic), so no path from
// the interrupt inputs runs through the multiplier.
//
// INTERRUPTS: if req_i drops before done_o (the instruction was interrupted),
// the unit forgets everything and is idle again in the next cycle. The
// instruction runs again from the start after MRET.
//
// The operands a_i / b_i must stay the same while the instruction is held in
// execute (both cores guarantee that).
//
// W is a parameter only so that dv/formal/rabbit/muldiv can prove the very
// same RTL correct for EVERY input at a small width (W = 8); the cores use 32.
// =============================================================================
module rabbit_muldiv #(
  parameter int unsigned W         = 32,
  // Division steps. Must be W for correct quotients. The pipeline-level
  // proofs (riscv-formal with ALTOPS, timing) use a smaller value so that a
  // divide fits in their proof depth: there the pipeline only sees done_o,
  // and the value is replaced anyway. The unit proof checks the real one.
  parameter int unsigned DIV_STEPS = W
) (
  input  logic         clk_i,
  input  logic         rst_ni,

  input  logic         en_i,      // an M instruction is in execute (power gating only)
  input  logic         req_i,     // ... and is not being interrupted: work on it
  input  logic [2:0]   op_i,      // funct3: 0 MUL 1 MULH 2 MULHSU 3 MULHU 4 DIV 5 DIVU 6 REM 7 REMU
  input  logic [W-1:0] a_i,       // rs1
  input  logic [W-1:0] b_i,       // rs2
  output logic         done_o,    // result_o is valid; the instruction may leave execute
  output logic [W-1:0] result_o
);
  localparam int unsigned H          = W / 2;
  localparam int unsigned P          = W + H + 2;    // width of one partial product
  localparam int unsigned DIV_CYCLES = DIV_STEPS + 2;
  localparam int unsigned CW         = $clog2(DIV_CYCLES);

  // ---- control: one cycle counter for both ------------------------------------
  // cnt_q = how many cycles this instruction has already spent in the unit
  logic [CW-1:0] cnt_q;
  logic          is_div, first;
  assign is_div = op_i[2];
  assign first  = (cnt_q == '0);
  assign done_o = req_i && (is_div ? (cnt_q == CW'(DIV_CYCLES - 1)) : (cnt_q == CW'(1)));

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)                cnt_q <= '0;
    else if (!req_i || done_o)  cnt_q <= '0;          // finished or interrupted
    else                        cnt_q <= cnt_q + 1'b1;
  end

  // ---- multiplier --------------------------------------------------------------
  logic a_signed, b_signed;
  assign a_signed = (op_i[1:0] != 2'b11);             // MUL, MULH, MULHSU
  assign b_signed = !op_i[1];                         // MUL, MULH

  logic signed [W:0]   mul_a;
  logic signed [H:0]   mul_b;
  logic signed [P-1:0] mul_c, mul_y;
  logic        [P-1:0] p0_q;

  logic mul_on, div_on;                               // operand isolation (POWER)
  assign mul_on = en_i && !is_div;
  assign div_on = en_i &&  is_div;

  assign mul_a = mul_on ? {a_signed && a_i[W-1], a_i} : '0;
  assign mul_b = !mul_on ? '0
               : first   ? {1'b0, b_i[H-1:0]} : {b_signed && b_i[W-1], b_i[W-1:H]};
  assign mul_c = first ? '0 : P'($signed(p0_q) >>> H);
  assign mul_y = mul_a * mul_b + mul_c;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)                       p0_q <= '0;
    else if (req_i && !is_div && first) p0_q <= mul_y;
  end

  logic [2*W-1:0] product;
  assign product = {mul_y[W+H-1:0], p0_q[H-1:0]};    // the full 2W-bit product (cycle 2)

  // ---- divider -------------------------------------------------------------------
  // Area: one W+1-bit adder for the steps, and ONE negator shared by the first
  // cycle (|rs1|) and the last (sign of the result). The divisor is kept as
  // it is; "rem - |div|" becomes "rem + div" when the divisor is negative.
  logic [W-1:0] rem_q, quo_q, div_q;
  logic         div_neg_q, quo_neg_q, rem_neg_q;
  logic         div_signed, a_neg, b_neg;
  logic [W:0]   rem_shift, rem_try;

  assign div_signed = !op_i[0];                       // DIV, REM
  assign a_neg      = div_signed && a_i[W-1];
  assign b_neg      = div_signed && b_i[W-1];

  // rem_try = rem_shift - |div|   (rem_try[W] = 1: the divisor does not fit)
  assign rem_shift  = {rem_q, quo_q[W-1]};
  assign rem_try    = div_neg_q ? rem_shift + {1'b1, div_q}
                                : rem_shift - {1'b0, div_q};

  // the shared negator: |rs1| in the first cycle, the signed result in the last
  logic         want_rem;
  logic [W-1:0] neg_in, neg_out;
  assign want_rem = op_i[1];                          // REM, REMU
  assign neg_in   = !div_on ? '0 : first ? a_i : (want_rem ? rem_q : quo_q);
  assign neg_out  = -neg_in;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rem_q <= '0; quo_q <= '0; div_q <= '0;
      div_neg_q <= 1'b0; quo_neg_q <= 1'b0; rem_neg_q <= 1'b0;
    end else if (req_i && is_div) begin
      if (first) begin
        rem_q     <= '0;
        quo_q     <= a_neg ? neg_out : a_i;           // |rs1|
        div_q     <= b_i;
        div_neg_q <= b_neg;
        quo_neg_q <= (a_neg != b_neg) && (b_i != '0); // x/0 = all ones, unsigned
        rem_neg_q <= a_neg;                           // remainder has the dividend's sign
      end else if (!done_o) begin
        rem_q <= rem_try[W] ? rem_shift[W-1:0] : rem_try[W-1:0];
        quo_q <= {quo_q[W-2:0], !rem_try[W]};
      end
    end
  end

  logic [W-1:0] div_result;
  assign div_result = (want_rem ? rem_neg_q : quo_neg_q) ? neg_out
                                                         : (want_rem ? rem_q : quo_q);

  // ---- result ----------------------------------------------------------------------
  always_comb begin
    unique case (op_i)
      3'd0:          result_o = product[W-1:0];       // MUL
      3'd1, 3'd2,
      3'd3:          result_o = product[2*W-1:W];     // MULH, MULHSU, MULHU
      default:       result_o = div_result;           // DIV, DIVU, REM, REMU
    endcase
  end

endmodule
