`timescale 1ns/1ps

module telemetry_phy_test_wrap #(
    parameter [15:0] SOF_MARKER  = 16'hF53A,
    parameter [15:0] EOF_MARKER  = 16'h0AC5,
    parameter [15:0] MAX_PAYLOAD = 16'd512
)(
    input  wire        clk,
    input  wire        rst,
    
    // Raw Asynchronous Frontend Pins
    input  wire        rf_clock_i,
    input  wire        rf_data_i,
    
    // Framer Outputs to monitor inside C++
    output wire [15:0] dma_data_o,
    output wire        dma_write_strobe_o,
    output wire        frame_complete_o,
    output wire [15:0] out_packet_idx,
    output wire [15:0] out_data_type,
    
    // Exposing the error pins so Verilator stops complaining and our C++ can track them
    output wire        err_overflow_o,
    output wire        err_length_mismatch_o,
    output wire        lock_status_o
);

    // Interconnect Signals
    wire        w_rf_serial;
    wire        w_rf_bit_valid;
    wire [15:0] w_aligned_word;
    wire        w_word_valid;
    wire        w_sof_detected;
    
    /* verilator lint_off UNUSEDSIGNAL */
    wire        w_hunting_window; // Disabled for now until we add the port to your aligner
    /* verilator lint_on UNUSEDSIGNAL */

    // 1. Clock Domain Crossing Synchronizer
    rf_cdc_synchronizer u_cdc (
        .clk             (clk),
        .rst             (rst),
        .rf_clock_i      (rf_clock_i),
        .rf_data_i       (rf_data_i),
        .rf_serial_o     (w_rf_serial),
        .rf_bit_valid_o  (w_rf_bit_valid)
    );

    // 2. Physical Bit Aligner Core
    rf_bit_aligner #(
        .SOF_MARKER(SOF_MARKER)
    ) u_aligner (
        .clk                     (clk),
        .rst                     (rst),
        .cfg_clear_lock_i        (1'b0),
        .rf_serial_i             (w_rf_serial),
        .rf_bit_valid_i          (w_rf_bit_valid),
        .aligned_word_o          (w_aligned_word),
        .word_valid_o            (w_word_valid),
        .sof_detected_o          (w_sof_detected),
        .lock_status_o           (lock_status_o) // Connected straight to top-level output port
    );

    // 3. Protocol Packet Framer Machine
    rf_packet_framer #(
        .EOF_MARKER(EOF_MARKER),
        .MAX_PAYLOAD(MAX_PAYLOAD)
    ) u_framer (
        .clk                     (clk),
        .rst                     (rst),
        .aligned_word_i          (w_aligned_word),
        .word_valid_i            (w_word_valid),
        .sof_detected_i          (w_sof_detected),
        .framer_hunting_window_o (w_hunting_window),
        .dma_data_o              (dma_data_o),
        .dma_write_strobe_o      (dma_write_strobe_o),
        .frame_complete_o        (frame_complete_o),
        .out_packet_idx          (out_packet_idx),
        .out_data_type           (out_data_type),
        .err_overflow_o          (err_overflow_o),        // Fixed: Connected missing pin
        .err_length_mismatch_o   (err_length_mismatch_o)  // Fixed: Connected missing pin
    );

endmodule
