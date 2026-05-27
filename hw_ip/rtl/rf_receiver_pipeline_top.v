`timescale 1ns/1ps

module rf_receiver_pipeline_top #(
    parameter [15:0] COMPILE_SOF = 16'hF53A,
    parameter [15:0] COMPILE_EOF = 16'h0AC5,
    parameter [15:0] MAX_PAYLOAD = 16'd512
)(
    // Wishbone Bus Secondary Interface
    input  wire        wb_clk,
    input  wire        wb_rst,
    input  wire [1:0]  wb_adr,
    input  wire [31:0] wb_dat_w,
    output wire [31:0] wb_dat_r,
    input  wire        wb_we,
    input  wire        wb_stb,
    input  wire        wb_cyc,
    output wire        wb_ack,

    // Asynchronous RF External Physical Pins
    input  wire        rf_clock,
    input  wire        rf_data,

    // DMA Storage / Hardware Outbound Interconnect
    output wire [15:0] dma_data_o,
    output wire        dma_write_strobe_o
);

    // --- Core Component Interconnect Wires ---
    wire        sync_serial;
    wire        sync_valid;
    
    wire [15:0] aligned_word;
    wire        word_valid;
    wire        sof_detected;
    wire        lock_status;
    wire        cfg_clear_lock;

    wire        frame_complete;
    wire [15:0] tracked_packet_idx;
    wire [15:0] tracked_data_type;
    wire        err_overflow;
    wire        err_length_mismatch;

    rf_cdc_synchronizer u_cdc (
        .clk            (wb_clk),
        .rst            (wb_rst),
        .rf_clock_i     (rf_clock),
        .rf_data_i      (rf_data),
        .rf_serial_o    (sync_serial),
        .rf_bit_valid_o (sync_valid)
    );

    rf_bit_aligner #(
        .SOF_MARKER(COMPILE_SOF)
    ) u_aligner (
        .clk              (wb_clk),
        .rst              (wb_rst),
        .cfg_clear_lock_i (cfg_clear_lock),
        .rf_serial_i      (sync_serial),
        .rf_bit_valid_i   (sync_valid),
        .aligned_word_o   (aligned_word),
        .word_valid_o     (word_valid),
        .sof_detected_o   (sof_detected),
        .lock_status_o    (lock_status)
    );

    rf_packet_framer #(
        .EOF_MARKER(COMPILE_EOF),
        .MAX_PAYLOAD(MAX_PAYLOAD)
    ) u_framer (
        .clk                     (wb_clk),
        .rst                     (wb_rst),
        .aligned_word_i          (aligned_word),
        .word_valid_i            (word_valid),
        .sof_detected_i          (sof_detected),
        .framer_hunting_window_o (), // Floating / internal telemetry monitoring
        .dma_data_o              (dma_data_o),
        .dma_write_strobe_o      (dma_write_strobe_o),
        .frame_complete_o        (frame_complete),
        .out_packet_idx          (tracked_packet_idx),
        .out_data_type           (tracked_data_type),
        .err_overflow_o          (err_overflow),
        .err_length_mismatch_o   (err_length_mismatch)
    );

    wb_rf_framer_ctrl #(
        .COMPILE_SOF(COMPILE_SOF),
        .COMPILE_EOF(COMPILE_EOF)
    ) u_wb_ctrl (
        .wb_clk_i               (wb_clk),
        .wb_rst_i               (wb_rst),
        .wb_adr_i               (wb_adr),
        .wb_dat_i               (wb_dat_w),
        .wb_dat_o               (wb_dat_r),
        .wb_we_i                (wb_we),
        .wb_stb_i               (wb_stb),
        .wb_cyc_i               (wb_cyc),
        .wb_ack_o               (wb_ack),
        .cfg_clear_lock_o       (cfg_clear_lock),
        .lock_status_i          (lock_status),
        .frame_complete_i       (frame_complete),
        .tracked_packet_idx_i   (tracked_packet_idx),
        .tracked_data_type_i    (tracked_data_type),
        .err_overflow_i         (err_overflow),
        .err_length_mismatch_i  (err_length_mismatch)
    );

endmodule