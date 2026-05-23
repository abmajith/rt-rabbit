`timescale 1ns/1ps

module rf_bit_aligner (
    input  wire        sys_clk,       // Global FPGA system clock (100 MHz)
    input  wire        sys_rst,       // Global synchronous reset
    input  wire        clear_lock,    // Reset the framing lock from upper layers
    
    // Physical transceiver interface lines
    input  wire        rf_clk,        // Recovered clock from RF chip (~10 MHz)
    input  wire        rf_data,       // Raw stabilized serial bitstream from RF chip
    
    // Aligned parallel interface to our Command Parser
    output reg  [7:0]  rx_byte,       // Aligned 8-bit parallel byte output
    output reg         byte_valid     // High for exactly 1 sys_clk cycle when rx_byte is stable
);

    parameter [15:0] SYNC_WORD = 16'hF53A;

    reg [2:0] rf_clk_sync;
    reg [1:0] rf_data_sync;
    
    always @(posedge sys_clk) begin
        if (sys_rst) begin
            rf_clk_sync  <= 3'b0;
            rf_data_sync <= 2'b0;
        end else begin
            rf_clk_sync  <= {rf_clk_sync[1:0], rf_clk};
            rf_data_sync <= {rf_data_sync[0], rf_data};
        end
    end

    wire rf_clk_edge = (rf_clk_sync[1] && !rf_clk_sync[2]);
    wire sampled_bit = rf_data_sync[1];

    reg [15:0] bit_shifter;
    reg [2:0]  bit_counter;
    reg        frame_locked;

    always @(posedge sys_clk) begin
        if (sys_rst) begin
            bit_shifter  <= 16'h0;
            bit_counter  <= 3'b0;
            frame_locked <= 1'b0;
            rx_byte      <= 8'h0;
            byte_valid   <= 1'b0;
        end else begin
            byte_valid <= 1'b0; // Default strobe low

            if (clear_lock) begin
                frame_locked <= 1'b0; // Force break out of old transaction tracking
            end

            if (rf_clk_edge) begin
                bit_shifter <= {bit_shifter[14:0], sampled_bit};
                
                if (!frame_locked && !clear_lock) begin
                    if ({bit_shifter[14:0], sampled_bit} == SYNC_WORD) begin
                        frame_locked <= 1'b1;
                        bit_counter  <= 3'b0;
                    end
                end else if (frame_locked) begin
                    bit_counter <= bit_counter + 1'b1;
                    
                    if (bit_counter == 3'b111) begin
                        rx_byte    <= {bit_shifter[6:0], sampled_bit};
                        byte_valid <= 1'b1;
                    end
                end
            end
        end
    end

endmodule