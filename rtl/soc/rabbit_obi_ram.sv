// Dual-port OBI RAM for simulation and FPGA block-RAM inference.
//  - Port A: instruction fetch (read only)
//  - Port B: data (read/write, byte enables)
// Timing: grant in the same cycle as req, rvalid exactly one cycle later.
// Contents are loaded from a hex file of 32-bit words ($readmemh) given by the
// +firmware=<file> plusarg (simulation) or the INIT_FILE parameter (FPGA).
module rabbit_obi_ram #(
    parameter int    WORDS     = 16384,   // 64 KiB
    parameter string INIT_FILE = ""
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic        a_req_i,
    output logic        a_gnt_o,
    output logic        a_rvalid_o,
    input  logic [31:0] a_addr_i,
    output logic [31:0] a_rdata_o,

    input  logic        b_req_i,
    output logic        b_gnt_o,
    output logic        b_rvalid_o,
    input  logic        b_we_i,
    input  logic [ 3:0] b_be_i,
    input  logic [31:0] b_addr_i,
    input  logic [31:0] b_wdata_i,
    output logic [31:0] b_rdata_o
);
  localparam int AW = $clog2(WORDS);

  logic [31:0] mem [WORDS];

  initial begin
    string fw;
    if ($value$plusargs("firmware=%s", fw)) begin
      $display("[rabbit_obi_ram] loading %s", fw);
      $readmemh(fw, mem);
    end else if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end
  end

  wire [AW-1:0] a_idx = a_addr_i[AW+1:2];
  wire [AW-1:0] b_idx = b_addr_i[AW+1:2];

  assign a_gnt_o = a_req_i;
  assign b_gnt_o = b_req_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      a_rvalid_o <= 1'b0;
      b_rvalid_o <= 1'b0;
    end else begin
      a_rvalid_o <= a_req_i;
      b_rvalid_o <= b_req_i;
    end
  end

  always_ff @(posedge clk_i) begin
    if (a_req_i) a_rdata_o <= mem[a_idx];
    if (b_req_i) begin
      if (b_we_i) begin
        for (int i = 0; i < 4; i++)
          if (b_be_i[i]) mem[b_idx][8*i+:8] <= b_wdata_i[8*i+:8];
      end
      b_rdata_o <= mem[b_idx];
    end
  end
endmodule
