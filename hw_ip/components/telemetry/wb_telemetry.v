`timescale 1ns/1ps

module wb_telemetry(
    // Wishbone Bus Interface Signals
    input  wire        wb_clk_i,   // System Clock
    input  wire        wb_rst_i,   // Synchronous Reset (Active High)
    input  wire [1:0]  wb_adr_i,   // Address lines (Register selection)
    input  wire [31:0] wb_dat_i,   // Data input from CPU/Bus Master
    output reg  [31:0] wb_dat_o,   // Data output back to CPU
    input  wire        wb_we_i,    // Write Enable (1 = Write, 0 = Read)
    input  wire        wb_stb_i,   // Strobe (Indicates valid cycle phase)
    input  wire        wb_cyc_i,   // Cycle (Indicates active bus transaction)
    output reg         wb_ack_o,   // Acknowledge (Handshake back to CPU)

    // Transceiver Wire Harness
    input wire [31:0]   rx_channel_1,
    input wire          rx_ch1_ready,
    input wire [31:0]   rx_channel_2,
    input wire          rx_ch2_ready,
    output wire [31:0]  tx_raw_stream,
    output wire         tx_start_pulse
);

    // Internal Registers for Local Bus Configuration
    reg [31:0] reg_tx_data;
    reg [1:0]  reg_mimo_mode; // Software controls fallback mode via address 2'b00

    // Captured command buffering register to hold output steady for Wishbone reads
    reg [31:0] reg_voted_cmd_cache;

    // Sticky status register to capture single-cycle hardware events for slow CPUs
    reg        reg_voted_valid_sticky;

    // Sub-Module Interconnect Wires
    wire [31:0] internal_voted_cmd;
    wire        internal_voted_valid;
    wire [3:0]  internal_rx_status; // Widened to 4 bits to match the updated telemetry_rx

    wire bus_select = wb_cyc_i && wb_stb_i;

    // -------------------------------------------------------------------------
    // STRUCTURAL SUB-MODULE INSTANTIATIONS
    // -------------------------------------------------------------------------
    telemetry_rx rx_inst (
        .clk             (wb_clk_i),
        .rst             (wb_rst_i),
        .mimo_mode_i     (reg_mimo_mode),
        .rx_channel_1    (rx_channel_1),
        .rx_ch1_ready    (rx_ch1_ready),
        .rx_channel_2    (rx_channel_2),
        .rx_ch2_ready    (rx_ch2_ready),
        .voted_cmd       (internal_voted_cmd),
        .voted_cmd_valid (internal_voted_valid),
        .status_flags    (internal_rx_status)
    );

    telemetry_tx tx_inst (
        .clk             (wb_clk_i),
        .rst             (wb_rst_i),
        .tx_payload_data (reg_tx_data),
        .tx_raw_stream   (tx_raw_stream),
        .tx_start_pulse  (tx_start_pulse)
    );

    // -------------------------------------------------------------------------
    // DATA AND STATUS CACHING LAYER
    // -------------------------------------------------------------------------
    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            reg_voted_cmd_cache    <= 32'h0;
            reg_voted_valid_sticky <= 1'b0;
        end else begin
            // Cache the voted payload when the pulse arrives
            if (internal_voted_valid) begin
                reg_voted_cmd_cache <= internal_voted_cmd;
            end

            // Sticky valid flag management
            if (internal_voted_valid) begin
                reg_voted_valid_sticky <= 1'b1; // Set by hardware
            end else if (bus_select && !wb_we_i && (wb_adr_i == 2'b11) && wb_ack_o) begin
                reg_voted_valid_sticky <= 1'b0; // Clear on valid Read Acknowledge
            end
        end
    end

    // -------------------------------------------------------------------------
    // WISHBONE BUS CONTROLLER LOGIC
    // -------------------------------------------------------------------------
    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            wb_ack_o      <= 1'b0;
            reg_tx_data   <= 32'h0;
            reg_mimo_mode <= 2'b00; // Defaults to Strict Spatial Majority Mode
            wb_dat_o      <= 32'h0;
        end else begin
            wb_ack_o <= 1'b0; // Single-cycle standard strobe acknowledge
            
            if (bus_select && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                
                if (wb_we_i) begin
                    case (wb_adr_i)
                        2'b00: reg_mimo_mode <= wb_dat_i[1:0]; // Write to Mode Register
                        2'b10: reg_tx_data   <= wb_dat_i;      // Write to Tx Register
                        default: ; // Safe fallback drop
                    endcase
                end else begin
                    case (wb_adr_i)
                        2'b00: wb_dat_o <= {30'h0, reg_mimo_mode};
                        2'b01: wb_dat_o <= reg_voted_cmd_cache;
                        2'b10: wb_dat_o <= reg_tx_data;
                        // Combines validation strobe status and voting diagnostic vectors
                        2'b11: wb_dat_o <= {27'h0, reg_voted_valid_sticky, internal_rx_status};
                        default: wb_dat_o <= 32'h0;
                    endcase
                end
            end
        end
    end

endmodule
