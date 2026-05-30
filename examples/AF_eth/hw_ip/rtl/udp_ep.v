`timescale 1ns / 1ps

module udp_ep (
  input wire  clk,
  input wire  rst,

  // configuration parameter
  input wire [15:0] target_udp_port, 

  // Inbound stream from the IP layer
  input wire [7:0] s_axis_tdata,
  input wire       s_axis_tvalid,
  input wire       s_axis_tlast,
  input wire       s_axis_tuser,

  // Output appliation payload bytes only
  output reg [7:0]  m_axis_tdata,
  output reg        m_axis_tvalid,
  output reg        m_axis_tlast,
  output reg        m_axis_tuser
);
  // udp byte count
  reg [15:0] udp_byte_count;
  reg        port_match;
  wire       payload_zone;

  assign payload_zone = (udp_byte_count >= 16'd8);

  always @(posedge clk) begin
    if (rst) begin
      udp_byte_count <= 16'd0;
    end else begin
      if (s_axis_tvalid) begin
        if (s_axis_tlast) begin
          udp_byte_count <= 16'd0;
        end else begin
          udp_byte_count <= udp_byte_count + 16'd1;
        end
      end
    end
  end
  
  always @(posedge clk) begin
    if (rst || (s_axis_tvalid && s_axis_tlast)) begin
      port_match <= 1'b1;
    end else if (s_axis_tvalid) begin
      if (udp_byte_count == 16'd2) port_match <= port_match && (s_axis_tdata == target_udp_port[15:8]);
      if (udp_byte_count == 16'd3) port_match <= port_match && (s_axis_tdata == target_udp_port[7:0]);
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      m_axis_tdata  <= 8'h00;
      m_axis_tvalid <= 1'b0;
      m_axis_tlast  <= 1'b0;
      m_axis_tuser  <= 1'b0;
    end else begin
      m_axis_tdata <= s_axis_tdata;
      m_axis_tvalid <= s_axis_tvalid && payload_zone;
      m_axis_tlast <= s_axis_tlast;

      if (s_axis_tvalid && udp_byte_count == 0) begin
        m_axis_tuser <= 1'b0;
      end else if (s_axis_tlast) begin
        m_axis_tuser <= s_axis_tuser || (!port_match);
      end
    end
  end

endmodule
