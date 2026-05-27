`timescale 1ns/1ps

module rf_cdc_synchronizer (
    input  wire clk,             // system clock
    input  wire rst,             // Synchronous Active-High Reset
    
    // RF Transceiver Chip Pins
    input  wire rf_clock_i,      // Asynchronous bit clock
    input  wire rf_data_i,       // Asynchronous serial data line
    
    // Sys Domain Synchronized Outputs
    output reg  rf_serial_o,     // registered serial data bit
    output wire rf_bit_valid_o   // exactly high for one sys 'clk'
);

    // Three-stage shift registers for clock and data synchronization
    reg [2:0] rf_clk_sync;
    /* verilator lint_off UNUSEDSIGNAL */
    reg [2:0] rf_data_sync;
    /* verilator lint_on UNUSEDSIGNAL */

    // Internal edge signal to safely register data
    wire sample_pulse;

    always @(posedge clk) begin
        if (rst) begin
            rf_clk_sync  <= 3'b0;
            rf_data_sync <= 3'b0;
            rf_serial_o  <= 1'b0;
        end else begin
            rf_clk_sync  <= {rf_clk_sync[1:0],  rf_clock_i};
            rf_data_sync <= {rf_data_sync[1:0], rf_data_i};
            
            // Capture the stable data bit precisely on the synchronized rising edge
            if (sample_pulse) begin
                rf_serial_o <= rf_data_sync[1]; // stabilized stage 2nd data flip-flop
            end
        end
    end

    // Edge Detection: Rising Edge of RF clock
    assign sample_pulse   = (rf_clk_sync[1] && !rf_clk_sync[2]);
    assign rf_bit_valid_o = sample_pulse;

endmodule
