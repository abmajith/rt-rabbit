`timescale 1ns/1ps

module rf_bit_aligner #(
    parameter [15:0] SOF_MARKER = 16'hF53A  // Compile-time fixed synchronization pattern
)(
    input  wire        clk,             // High-speed bit sampling clock
    input  wire        rst,             // Synchronous Active-High Reset

    // Control / Reset Inputs from Wishbone Bus
    input  wire        cfg_clear_lock_i, // Force-unlock alignment manually

    // Raw RF Serial Interface
    input  wire        rf_serial_i,      // Serial bit-stream input from RF front-end
    input  wire        rf_bit_valid_i,   // Strobe indicating stable bit on rf_serial_i

    // Deserialized Output Interface (Aligned Data Stream)
    output reg  [15:0] aligned_word_o,   // Aligned 16-bit word output
    output reg         word_valid_o,     // High for exactly 1 cycle when word is valid
    output reg         sof_detected_o,   // Single-cycle pulse on initial SOF boundary lock
    output reg         lock_status_o     // High when bit-grid alignment is locked
);

    // Sliding window register to hunt for the preamble/SOF marker
    /* verilator lint_off UNUSEDSIGNAL */
    reg [15:0] bit_shift_reg;
    /* verilator lint_on UNUSEDSIGNAL */

    // Accumulation register for gathering the next aligned word payload
    /* verilator lint_off UNUSEDSIGNAL */
    reg [15:0] data_accum_reg;
    /* verilator lint_on UNUSEDSIGNAL */

    // Bit grid counter tracking deserialization boundary alignment
    reg [3:0]  bit_counter;

    always @(posedge clk) begin
        if (rst || cfg_clear_lock_i) begin
            bit_shift_reg   <= 16'h0;
            data_accum_reg  <= 16'h0;
            bit_counter     <= 4'd0;
            aligned_word_o  <= 16'h0;
            word_valid_o    <= 1'b0;
            sof_detected_o  <= 1'b0;
            lock_status_o   <= 1'b0;
        end else begin
            // Automatic single-cycle defaults
            word_valid_o    <= 1'b0;
            sof_detected_o  <= 1'b0;

            if (rf_bit_valid_i) begin
                // Continuously slide incoming bits into the hunting window
                bit_shift_reg <= {bit_shift_reg[14:0], rf_serial_i};

                if (!lock_status_o) begin
                    // STATE: HUNTING FOR LOCK
                    // Look-ahead matching logic optimized by the synthesizer
                    if ({bit_shift_reg[14:0], rf_serial_i} == SOF_MARKER) begin
                        lock_status_o  <= 1'b1;
                        sof_detected_o <= 1'b1;
                        bit_counter    <= 4'd0; // Freeze the bit grid boundary instantly
                    end
                end else begin
                    // STATE: ALIGNED & LOCKED
                    // Gather the next serial bits into the parallel register
                    data_accum_reg <= {data_accum_reg[14:0], rf_serial_i};
                    
                    if (bit_counter == 4'd15) begin
                        bit_counter    <= 4'd0;
                        aligned_word_o <= {data_accum_reg[14:0], rf_serial_i};
                        word_valid_o   <= 1'b1; // Aligned parallel word is ready for the framer
                    end else begin
                        bit_counter <= bit_counter + 1'b1;
                    end
                end
            end
        end
    end

endmodule
