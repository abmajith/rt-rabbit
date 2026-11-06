// Machine timer (RISC-V "mtime / mtimecmp", as in a CLINT). OBI slave.
// Register map, base 0x2000_0000:
//   0x00  MTIME_LO     RW   64-bit counter, +1 every clock cycle
//   0x04  MTIME_HI     RW
//   0x08  MTIMECMP_LO  RW   compare value (reset: all ones = never)
//   0x0C  MTIMECMP_HI  RW
// irq_o (the timer interrupt, MTI = line 7) is 1 while mtime >= mtimecmp.
// The handler clears it by writing a later mtimecmp.
//
// irq_o comes from a flip-flop, as the rabbit cores require (rabbit_csr.sv).
// It is one cycle behind the comparison; the robot's control loop sees a
// fixed, known delay, which is what matters for real time.
module rabbit_timer (
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic        req_i,
    output logic        gnt_o,
    output logic        rvalid_o,
    input  logic        we_i,
    input  logic [ 3:0] be_i,
    input  logic [31:0] addr_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,

    output logic        irq_o
);
  logic [63:0] mtime_q, mtimecmp_q;

  assign gnt_o = req_i;

  // byte-enable merge of a write into one 32-bit half
  function automatic logic [31:0] merge(input logic [31:0] old, input logic [31:0] new_v,
                                        input logic [3:0] be);
    for (int b = 0; b < 4; b++) if (be[b]) old[8*b +: 8] = new_v[8*b +: 8];
    return old;
  endfunction

  logic wr;
  assign wr = req_i && we_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mtime_q    <= '0;
      mtimecmp_q <= '1;
      rvalid_o   <= 1'b0;
      rdata_o    <= '0;
      irq_o      <= 1'b0;
    end else begin
      mtime_q <= mtime_q + 64'd1;
      if (wr) begin
        unique case (addr_i[3:2])
          2'd0: mtime_q[31:0]     <= merge(mtime_q[31:0],     wdata_i, be_i);
          2'd1: mtime_q[63:32]    <= merge(mtime_q[63:32],    wdata_i, be_i);
          2'd2: mtimecmp_q[31:0]  <= merge(mtimecmp_q[31:0],  wdata_i, be_i);
          2'd3: mtimecmp_q[63:32] <= merge(mtimecmp_q[63:32], wdata_i, be_i);
        endcase
      end
      rvalid_o <= req_i;
      if (req_i && !we_i) begin
        unique case (addr_i[3:2])
          2'd0: rdata_o <= mtime_q[31:0];
          2'd1: rdata_o <= mtime_q[63:32];
          2'd2: rdata_o <= mtimecmp_q[31:0];
          2'd3: rdata_o <= mtimecmp_q[63:32];
        endcase
      end
      irq_o <= (mtime_q >= mtimecmp_q);
    end
  end
endmodule
