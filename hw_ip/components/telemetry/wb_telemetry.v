// hw_ip/components/telemetry/wb_telemetry.v
`timescale 1ns/1ps

module wb_telemetry(
    // Wishbone Bus Standard Interconnect Inputs
    input wire          wb_clk_i,
    input wire          wb_rst_i,
    input wire [1:0]    wb_adr_i,   // Lower 2 bits sliced inside top-level wrapper
    input wire [31:0]   wb_dat_i,
    output reg [31:0]   wb_dat_o,
    input wire          wb_we_i,
    input wire          wb_cyc_i,
    input wire          wb_stb_i,
    output reg          wb_ack_o,

    // Transceiver Wire Harness
    input wire [31:0]   rx_channel_1,
    input wire [31:0]   rx_channel_2,
    input wire          rx_data_ready,
    output wire [31:0]  tx_raw_stream,
    output wire         tx_start_pulse
);
    // Internal Registers for Local Bus Communication
    reg [31:0] reg_tx_data;

    // Wires connected directly to Sub-Module Outputs
    wire [31:0] internal_voted_cmd;
    wire [1:0]  internal_rx_status;

    wire bus_select = wb_cyc_i && wb_stb_i;

    // -------------------------------------------------------------------------
    // STRUCTURAL SUB-MODULE INSTANTIATIONS
    // -------------------------------------------------------------------------
    telemetry_rx rx_inst (
        .clk           (wb_clk_i),
        .rst           (wb_rst_i),
        .rx_channel_1  (rx_channel_1),
        .rx_channel_2  (rx_channel_2),
        .rx_data_ready (rx_data_ready),
        .voted_cmd     (internal_voted_cmd),
        .status_flags  (internal_rx_status)
    );

    telemetry_tx tx_inst (
        .clk             (wb_clk_i),
        .rst             (wb_rst_i),
        .tx_payload_data (reg_tx_data),
        .tx_raw_stream   (tx_raw_stream),
        .tx_start_pulse  (tx_start_pulse)
    );

    // -------------------------------------------------------------------------
    // WISHBONE BUS CONTROLLER LOGIC
    // -------------------------------------------------------------------------
    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            wb_ack_o    <= 1'b0;
            reg_tx_data <= 32'h0;
            wb_dat_o    <= 32'h0;
        end else begin
            wb_ack_o <= 1'b0;
            
            if (bus_select && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                
                if (wb_we_i) begin
                    case (wb_adr_i)
                        2'b10: reg_tx_data <= wb_dat_i; // Write to Tx register offset (0x6)
                        default: begin end                // Safe defensive ignore fallback
                    endcase
                end else begin
                    case (wb_adr_i)
                        2'b01: wb_dat_o <= internal_voted_cmd;                     // Read from Rx register (0x5)
                        2'b10: wb_dat_o <= reg_tx_data;                            // Read from Tx register (0x6)
                        2'b11: wb_dat_o <= {30'h0, internal_rx_status};            // Read from Status register (0x7)
                        default: wb_dat_o <= 32'h0;
                    endcase
                end
            end
        end
    end

endmodule
