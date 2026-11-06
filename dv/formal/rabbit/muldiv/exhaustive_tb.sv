// =============================================================================
// rabbit_muldiv — exhaustive simulation at W = 8 (proof by trying everything)
// =============================================================================
// Every op x every rs1 x every rs2 = 8 x 256 x 256 = 524 288 instructions, each
// checked against the RISC-V definition, and each must take exactly 2 (MUL*)
// or W+2 (DIV*) cycles. Every 7th instruction is first interrupted after a
// pseudo-random number of cycles (req drops for one cycle) and then restarted,
// as the pipeline does after MRET.
//
// SAT solvers are bad at multipliers (muldiv_tb.sv proves W = 6 formally);
// at 8 bits trying all inputs takes a second. Run:  make -C dv/formal/rabbit muldiv-sim
// =============================================================================
module exhaustive_tb;
  localparam int W = 8;

  logic         clk = 1'b0, rst_n = 1'b0;
  logic         req = 1'b0, done;
  logic [2:0]   op  = '0;
  logic [W-1:0] a   = '0, b = '0, result;

  rabbit_muldiv #(.W(W)) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .en_i(req), .req_i(req), .op_i(op), .a_i(a), .b_i(b),
    .done_o(done), .result_o(result)
  );

  always #5 clk = ~clk;

  function automatic logic [W-1:0] expected(input logic [2:0] o, input logic [W-1:0] x, y);
    logic signed [W:0]     ex, ey;
    logic signed [2*W+1:0] p;
    logic                  ovf;
    ex  = {o[1:0] != 2'b11 && x[W-1], x};
    ey  = {o[1:0] <= 2'b01 && y[W-1], y};
    p   = ex * ey;
    ovf = (x == {1'b1, {(W-1){1'b0}}}) && (y == '1);
    unique case (o)
      3'd0:          return p[W-1:0];
      3'd1, 3'd2,
      3'd3:          return p[2*W-1:W];
      3'd4:          return (y == 0) ? '1 : ovf ? x  : W'($signed(x) / $signed(y));
      3'd5:          return (y == 0) ? '1 : x / y;
      3'd6:          return (y == 0) ? x  : ovf ? '0 : W'($signed(x) % $signed(y));
      default:       return (y == 0) ? x  : x % y;
    endcase
  endfunction

  int errors = 0, runs = 0, kills = 0;
  int unsigned lfsr = 32'h1;

  initial begin
    @(posedge clk); #1 rst_n = 1'b1;
    for (int o = 0; o < 8; o++) begin
      for (int x = 0; x < 2**W; x++) begin
        for (int y = 0; y < 2**W; y++) begin
          automatic int cycles, want;
          automatic logic [W-1:0] got;
          op = 3'(o); a = W'(x); b = W'(y);
          want = op[2] ? W + 2 : 2;
          runs++;
          lfsr = lfsr ^ (lfsr << 13); lfsr = lfsr ^ (lfsr >> 17); lfsr = lfsr ^ (lfsr << 5);
          if (runs % 7 == 0) begin                  // interrupt it, then start again
            automatic int stop_after = int'(lfsr % unsigned'(want - 1)) + 1;
            req = 1'b1;
            repeat (stop_after) @(posedge clk);
            #1 req = 1'b0;
            @(posedge clk); #1;
            kills++;
          end
          // run to completion, checking the cycle where done_o is high
          req = 1'b1;
          cycles = 0;
          forever begin
            #3;                                     // settle (combinational outputs)
            cycles++;
            if (done) begin got = result; break; end
            @(posedge clk); #1;
            if (cycles > want) break;
          end
          @(posedge clk); #1 req = 1'b0;
          if (cycles != want || got !== expected(op, a, b)) begin
            if (errors < 10)
              $display("FAIL op=%0d a=%02x b=%02x got=%02x expected=%02x cycles=%0d (want %0d)",
                       op, a, b, got, expected(op, a, b), cycles, want);
            errors++;
          end
        end
      end
    end
    $display("muldiv exhaustive W=%0d: %0d instructions (%0d interrupted first), %0d errors",
             W, runs, kills, errors);
    $display("RESULT: %s", errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
