`timescale 1ns/1ps

module rt_telemetry_top #(
    parameter [31:0] BUFFER_BASE_ADDR = 32'h0000_2000,
    parameter [3:0]  TIMEOUT_LIMIT    = 4'd15
)(
    input  wire        sys_clk,
    input  wire        sys_rst,

    // Wishbone Master Interface
    output wire [31:0] wb_adr_o,
    output wire [31:0] wb_dat_o,
    output wire        wb_we_o,
    output wire        wb_stb_o,
    output wire        wb_cyc_o,
    input  wire        wb_ack_i,
    input  wire        wb_err_i,

    // RF Physical Transceiver Pins
    input  wire        rf_clk,
    input  wire        rf_data,

    // Control/Status Outputs
    output wire        irq_packet_ready,
    output wire        bus_timeout_err
);

    // Internal Signal Interconnect Routing Wires
    wire [7:0]  aligner_rx_byte;
    wire        aligner_byte_valid;
    wire        framer_clear_lock;
    wire [31:0] framer_packet_data;
    wire        framer_packet_valid;

    // Stage 1: Asynchronous Bit-to-Byte Alignment & Synchronizer Engine
    rf_bit_aligner u_bit_aligner (
        .sys_clk    (sys_clk),
        .sys_rst    (sys_rst),
        .clear_lock (framer_clear_lock),
        .rf_clk     (rf_clk),
        .rf_data    (rf_data),
        .rx_byte    (aligner_rx_byte),
        .byte_valid (aligner_byte_valid)
    );

    // Stage 2: Framer, Word Assembler, and Streaming CRC-16 Engine
    rf_packet_framer_buffer u_framer_buffer (
        .sys_clk        (sys_clk),
        .sys_rst        (sys_rst),
        .rx_byte        (aligner_rx_byte),
        .byte_valid     (aligner_byte_valid),
        .clear_lock     (framer_clear_lock),
        .packet_data_o  (framer_packet_data),
        .packet_valid_o (framer_packet_valid)
    );

    // Stage 3: Automated Wishbone Master Interface with Safety Counter
    rf_rx_fifo_master #(
        .BUFFER_BASE_ADDR(BUFFER_BASE_ADDR),
        .TIMEOUT_LIMIT(TIMEOUT_LIMIT)
    ) u_fifo_master (
        .sys_clk          (sys_clk),
        .sys_rst          (sys_rst),
        .wb_adr_o         (wb_adr_o),
        .wb_dat_o         (wb_dat_o),
        .wb_we_o          (wb_we_o),
        .wb_stb_o         (wb_stb_o),
        .wb_cyc_o         (wb_cyc_o),
        .wb_ack_i         (wb_ack_i),
        .wb_err_i         (wb_err_i),
        .packet_data_i    (framer_packet_data),
        .packet_valid_i   (framer_packet_valid),
        .irq_packet_ready (irq_packet_ready),
        .bus_timeout_err  (bus_timeout_err)
    );

endmodule