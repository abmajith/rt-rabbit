// Simulation control peripheral (OBI slave). Register map, base 0x1000_0000:
//   0x00  PUTC   W  : low byte is printed to the simulator console
//   0x04  EXIT   W  : ends the test; written value is the exit code (0 = pass)
//   0x08  CYCLE  R  : free-running 32-bit cycle counter (for latency measurement)
//   0x0C  IRQ    RW : drives interrupt lines irq_o (bit i -> core line i), so
//                     firmware can raise "external" interrupts to test itself
// The cocotb testbench watches putc_valid_o / exit_valid_o.
module rabbit_sim_ctrl (
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic        req_i,
    output logic        gnt_o,
    output logic        rvalid_o,
    input  logic        we_i,
    input  logic [31:0] addr_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,

    output logic        putc_valid_o,
    output logic [ 7:0] putc_char_o,
    output logic        exit_valid_o,
    output logic [31:0] exit_code_o,
    output logic [31:0] irq_o
);
  logic [31:0] cycle_q;

  assign gnt_o = req_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rvalid_o     <= 1'b0;
      rdata_o      <= '0;
      putc_valid_o <= 1'b0;
      putc_char_o  <= '0;
      exit_valid_o <= 1'b0;
      exit_code_o  <= '0;
      cycle_q      <= '0;
      irq_o        <= '0;
    end else begin
      cycle_q      <= cycle_q + 1;
      rvalid_o     <= req_i;
      putc_valid_o <= 1'b0;
      if (req_i && we_i) begin
        unique case (addr_i[7:0])
          8'h00: begin
            putc_valid_o <= 1'b1;
            putc_char_o  <= wdata_i[7:0];
`ifndef RABBIT_QUIET
            $write("%c", wdata_i[7:0]);
`endif
          end
          8'h04: begin
            exit_valid_o <= 1'b1;
            exit_code_o  <= wdata_i;
          end
          8'h0C: irq_o <= wdata_i;
          default: ;
        endcase
      end
      if (req_i && !we_i) begin
        unique case (addr_i[7:0])
          8'h08  : rdata_o <= cycle_q;
          8'h0C  : rdata_o <= irq_o;
          default: rdata_o <= 32'h0;
        endcase
      end
    end
  end
endmodule
