// =============================================================================
// rabbit_muldiv — unit proof: the arithmetic and the fixed latency
// =============================================================================
// riscv-formal cannot check multiplication or division (it uses stand-in
// results, ALTOPS). This proof checks the real arithmetic on the very same
// RTL, at widths where the solver can try EVERY input (muldiv.sby):
//
//   A1  the result equals the RISC-V definition (x/0 and overflow included)
//   L1  done_o comes exactly 2 (MUL*) / W+2 (DIV*) cycles after the
//       instruction arrived, never earlier, never later
//   for every op, every pair of operands and ANY interrupt pattern (req_i
//   may drop in any cycle; the instruction then starts again from scratch)
//
//   W = 4   A1 + L1, for histories of any length (PDR, unbounded)
//   W = 6   A1 + L1, all histories up to 20 cycles (BMC)
//   W = 8   A1 + L1, all 524 288 instructions in simulation (exhaustive_tb.sv)
//   W = 32  L1, for histories of any length (PDR); A1 only in simulation
//           (sw/baremetal/muldiv: corner cases + random operands, every core)
//
// rabbit_muldiv is written for any even W, and its structure (two half
// multiplies, one quotient bit per step) is the same at every width. SAT
// solvers cannot prove 32-bit multipliers equal (they blow up beyond ~8 bits);
// see dv/formal/README.md.
// =============================================================================
module muldiv_tb (
    input logic           clk,
    // free inputs, chosen by the solver every cycle (see timing tb for why
    // they are ports and not (* anyseq *) signals)
    input logic           en,     // an M instruction is in execute ...
    input logic           req,    // ... and is not being interrupted
    input logic [2:0]     op,
    input logic [`W-1:0]  a,
    input logic [`W-1:0]  b
);
  localparam int W = `W;

  logic rst_n = 1'b0;
  always_ff @(posedge clk) rst_n <= 1'b1;

  logic         done;
  logic [W-1:0] result;
  rabbit_muldiv #(.W(W)) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .en_i(en), .req_i(req), .op_i(op), .a_i(a), .b_i(b),
    .done_o(done), .result_o(result)
  );

  // ---- the contract with the pipeline: an instruction that is still being
  //      worked on keeps its op and operands (it may be dropped: req = 0) ----
  logic         held;
  logic [2:0]   op_q;
  logic [W-1:0] a_q, b_q;
  always_ff @(posedge clk) begin
    held <= rst_n && req && !done;
    op_q <= op; a_q <= a; b_q <= b;
  end
  always_comb if (rst_n && held && req) assume (op == op_q && a == a_q && b == b_q);
  always_comb assume (en || !req);   // the pipeline never asks without an M instruction

  // ---- L1: exact latency ----------------------------------------------------
  int n;      // cycles the current instruction has already spent in the unit
  always_ff @(posedge clk) begin
    if (!rst_n || !req || done) n <= 0;
    else                        n <= n + 1;
  end
  always_comb if (rst_n && req) assert (done == (n == (op[2] ? W + 1 : 1)));   // L1
  always_comb if (rst_n && !req) assert (!done);

`ifdef CHECK_VALUES
  // ---- A1: the RISC-V definition ------------------------------------------------
  // one (W+1) x (W+1) signed product; the op decides how a and b are extended
  logic signed [W:0]     ea, eb;
  logic signed [2*W+1:0] p;
  assign ea = {op[1:0] != 2'b11 && a[W-1], a};    // rs1 signed: MUL, MULH, MULHSU
  assign eb = {op[1:0] <= 2'b01 && b[W-1], b};    // rs2 signed: MUL, MULH
  assign p  = ea * eb;

  localparam logic [W-1:0] ONES = '1;
  localparam logic [W-1:0] MIN  = {1'b1, {(W-1){1'b0}}};
  logic overflow;
  assign overflow = (a == MIN) && (b == ONES);

  logic [W-1:0] expected;
  always_comb begin
    unique case (op)
      3'd0: expected = p[W-1:0];                             // MUL
      3'd1, 3'd2,
      3'd3: expected = p[2*W-1:W];                           // MULH, MULHSU, MULHU
      3'd4: expected = (b == 0) ? ONES : overflow ? MIN :    // DIV
                       W'($signed(a) / $signed(b));
      3'd5: expected = (b == 0) ? ONES : a / b;              // DIVU
      3'd6: expected = (b == 0) ? a : overflow ? '0 :        // REM
                       W'($signed(a) % $signed(b));
      default: expected = (b == 0) ? a : a % b;              // REMU
    endcase
  end
  always_comb if (rst_n && done) assert (result == expected);                    // A1
`endif

  // ---- non-vacuity ----------------------------------------------------------------
  always_comb begin
    if (rst_n && done) begin
      cover (op == 3'd4 && b == 0);                 // x / 0
      cover (op == 3'd6 && a == {1'b1, {(W-1){1'b0}}} && b == '1);  // overflow
      cover (op == 3'd1 && a[W-1] && b[W-1]);       // negative x negative
    end
    if (rst_n && held && !req) cover (op_q[2]);     // a divide is interrupted ...
  end
endmodule
