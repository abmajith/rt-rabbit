// =============================================================================
// rabbit5_regfile — 32 x 32-bit registers, 2 read ports, 1 write port
// =============================================================================
// x0 always reads as zero.
// "Write-first" bypass: if WB writes a register in the same cycle that ID
// reads it, ID sees the *new* value. This removes the WB->ID hazard, so the
// EX-stage forwarding only has to look at MEM and WB.
// =============================================================================
module rabbit5_regfile (
  input  logic        clk_i,
  input  logic [4:0]  raddr_a_i,
  output logic [31:0] rdata_a_o,
  input  logic [4:0]  raddr_b_i,
  output logic [31:0] rdata_b_o,
  input  logic        we_i,
  input  logic [4:0]  waddr_i,
  input  logic [31:0] wdata_i
);
  logic [31:0] regs [32];

  always_ff @(posedge clk_i)
    if (we_i && waddr_i != 5'd0) regs[waddr_i] <= wdata_i;

  function automatic logic [31:0] read(input logic [4:0] addr);
    if (addr == 5'd0)                return 32'b0;
    else if (we_i && waddr_i == addr) return wdata_i;    // bypass
    else                             return regs[addr];
  endfunction

  assign rdata_a_o = read(raddr_a_i);
  assign rdata_b_o = read(raddr_b_i);
endmodule
