`timescale 1ns / 1ps

module eth_mac_1g(
  input wire gmii_rx_clk,   // Driven by PHY  
  input wire rx_rst,        // Active high synchronous reset

  // Physical Media interface (From External Phy Board pins)
  input wire [7:0] gmii_rxd,   // Raw Rx Data line 
  input wire       gmii_rx_dv, // Rx Data valid flag
  input wire       gmii_rx_er, // Rx error flag (from line corruption)
  
  // user application (AXI-Stream Master out)
  output reg [7:0]  m_axis_tdata, // aligned packet data byte
  output reg        m_axis_tvalid,// Asserted during valid payload byte
  output reg        m_axis_tlast, // pulsed high on the final pcket byte
  output reg        m_axis_tuser  // Error flag (1 = packet bad/CRC fail)
);
  // internal fsm code 
  localparam STATE_IDLE     = 2'b00;
  localparam STATE_PREAMBLE = 2'b01;
  localparam STATE_PAYLOAD  = 2'b10;

  reg [1:0] current_state, next_state;

  // current state latches
  always @(posedge gmii_rx_clk) begin
    if (rx_rst) begin
      current_state <= STATE_IDLE;
    end else begin
      current_state <= next_state;
    end
  end

  always @(*) begin
    next_state = current_state;
    case (current_state)
      STATE_IDLE: begin
        if (gmii_rx_dv && gmii_rxd == 8'h55) begin
          next_state = STATE_PREAMBLE;
        end
      end
      STATE_PREAMBLE: begin
        if (!gmii_rx_dv) begin
          next_state = STATE_IDLE;
        end else if (gmii_rxd == 8'hD5) begin
          next_state = STATE_PAYLOAD;
        end
      end
      STATE_PAYLOAD: begin 
        if (!gmii_rx_dv) begin
          next_state = STATE_IDLE;
        end
      end
      default: next_state = STATE_IDLE;
    endcase
  end
  
  reg gmii_rx_dv_reg;
  reg [7:0] gmii_rxd_reg;
  reg gmii_rx_er_reg;

  always @(posedge gmii_rx_clk) begin
    gmii_rx_dv_reg <= gmii_rx_dv;
    gmii_rxd_reg   <= gmii_rxd;
    gmii_rx_er_reg <= gmii_rx_er;

    if (rx_rst) begin
      m_axis_tdata <= 8'h00;
      m_axis_tvalid <= 1'b0;
      m_axis_tlast <= 1'b0;
      m_axis_tuser <= 1'b0;
    end else begin
      case (current_state)
        STATE_PAYLOAD: begin
          m_axis_tdata <= gmii_rxd_reg;
          m_axis_tvalid <= gmii_rx_dv_reg;
          m_axis_tuser <= gmii_rx_er_reg;
          m_axis_tlast <= gmii_rx_dv_reg && !gmii_rx_dv;
        end 
        default: begin 
          m_axis_tdata  <= 8'h00;
          m_axis_tvalid <= 1'b0;
          m_axis_tlast  <= 1'b0;
          m_axis_tuser  <= 1'b0;
        end 
      endcase
    end
  end
endmodule
