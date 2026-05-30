`timescale 1ns / 1ps

module ip_ep (
  input wire clk,
  input wire rst,

  // configuration parameters (static settings)
  input wire [31:0] our_static_ip, // assigned ip to this node 
  
  // Inbound stream from the MAC Layer
  input wire [7:0] s_axis_tdata,
  input wire       s_axis_tvalid,
  input wire       s_axis_tlast,
  input wire       s_axis_tuser,  // High if mac detected an error

  // output stream to the UDP layer
  output reg [7:0] m_axis_tdata,
  output reg       m_axis_tvalid,
  output reg       m_axis_tlast,
  output reg       m_axis_tuser
);
  // Track our exact byte index within the incoming IP frame 
  reg [15:0]  byte_count;
  reg         packet_active;
  reg         ip_match;
  reg         is_udp;

  // byte index counter
  always @(posedge clk) begin
    if (rst) begin
      byte_count    <= 16'h0000;
      packet_active <= 1'b0;
    end else begin
      if (s_axis_tvalid) begin
        if (s_axis_tlast) begin
          byte_count    <= 16'h0000;
          packet_active <= 1'b0;
        end else begin
          packet_active <= 1'b1;
          byte_count    <= byte_count + 16'h0001;
        end
      end
    end
  end

  always @(posedge clk) begin
    if (rst || (s_axis_tvalid && s_axis_tlast)) begin
      ip_match <= 1'b1;
      is_udp   <= 1'b0;
    end else if (s_axis_tvalid) begin
      // 9th byte to decide udp,
      if (byte_count == 16'd9) begin
        is_udp <= (s_axis_tdata == 8'h11);
      end
      // 16 to 19 bytes verification of incoming ip address in the data stream
      if (byte_count == 16'd16) ip_match <= ip_match && (s_axis_tdata == our_static_ip[31:24]);
      if (byte_count == 16'd17) ip_match <= ip_match && (s_axis_tdata == our_static_ip[23:16]);
      if (byte_count == 16'd18) ip_match <= ip_match && (s_axis_tdata == our_static_ip[15:8]);
      if (byte_count == 16'd19) ip_match <= ip_match && (s_axis_tdata == our_static_ip[7:0]);
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
      m_axis_tvalid <= s_axis_tvalid;
      m_axis_tlast <= s_axis_tlast;

      if (s_axis_tvalid && byte_count == 0) begin
        m_axis_tuser <= 1'b0;
      end else if (s_axis_tlast) begin
        m_axis_tuser <= s_axis_tuser || (!ip_match) || (!is_udp);
      end
    end
  end
endmodule
