`timescale 1ns/1ps

module rf_cdc_synchronizer (
    input  wire clk,             // High-speed internal system clock (e.g., 50MHz - 100MHz)
    input  wire rst,             // Synchronous Active-High Reset
    
    // Raw Asynchronous Pins directly from the RF Transceiver Chip
    input  wire rf_clock_i,      // Asynchronous bit clock from RF hardware (e.g., 500kHz)
    input  wire rf_data_i,       // Asynchronous serial data line from RF hardware
    
    // Clean Synchronized Outputs matching the system clk domain
    output reg  rf_serial_o,     // Safely registered serial data bit
    output wire rf_bit_valid_o   // Pulses high for exactly 1 cycle of system 'clk'
);

    // Three-stage shift registers for clock and data synchronization
    reg [2:0] rf_clk_sync;
    /* verilator lint_off UNUSEDSIGNAL */
    reg [2:0] rf_data_sync;
    /* verilator lint_on UNUSEDSIGNAL */

    // Internal edge signal to safely register data without a combinational loop
    wire sample_pulse;

    always @(posedge clk) begin
        if (rst) begin
            rf_clk_sync  <= 3'b0;
            rf_data_sync <= 3'b0;
            rf_serial_o  <= 1'b0;
        end else begin
            // Shift the external asynchronous inputs into our fast system clock flip-flops
            rf_clk_sync  <= {rf_clk_sync[1:0],  rf_clock_i};
            rf_data_sync <= {rf_data_sync[1:0], rf_data_i};
            
            // Capture the stable data bit precisely on the synchronized rising edge
            if (sample_pulse) begin
                rf_serial_o <= rf_data_sync[1]; // Index 1 represents the stabilized stage 2 flip-flop
            end
        end
    end

    // Edge Detection: Trigger a valid pulse exactly when stage 1 is High and stage 2 is Low.
    // Isolate a single clock cycle pulse right on the rising edge of the stabilized RF clock
    assign sample_pulse   = (rf_clk_sync[1] && !rf_clk_sync[2]);
    assign rf_bit_valid_o = sample_pulse;

endmodule
