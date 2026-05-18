// hw_ip/rtl/rt_top_integrated.v
module rt_top_integrated (
    input  wire        sys_clk,
    input  wire        sys_rst,
    
    // Shared Wishbone wires exposed to the simulation engine
    input  wire [2:0]  wb_adr,
    input  wire [31:0] wb_dat_w,
    output reg  [31:0] wb_dat_r,
    input  wire        wb_we,
    input  wire        wb_stb,
    input  wire        wb_cyc,
    output reg         wb_ack,

    // Real world system IO bindings
    output wire        motor_pwm_pin,
    input  wire        enc_a_pin,
    input  wire        enc_b_pin,
    
    // Telemetry Serial Pins
    input  wire        uart_rx,
    output wire        uart_tx
);

    // 1. Three-Way Address Decoders
    wire pwm_select       = (wb_adr[2:1] == 2'b00); // Address Space: 3'b000 - 3'b001
    wire qei_select       = (wb_adr[2:1] == 2'b10); // Address Space: 3'b100 - 3'b101
    wire telemetry_select = (wb_adr[2:1] == 2'b11); // Address Space: 3'b110 - 3'b111

    // Read buses and ACK signals from each peripheral
    wire [31:0] pwm_dat_r, qei_dat_r, tel_dat_r;
    wire        pwm_ack, qei_ack, tel_ack;

    // Local internal routing signals to satisfy telemetry application interfaces
    wire [31:0] tel_rx_ch1;
    wire [31:0] tel_rx_ch2;
    wire        tel_rx_ready;
    wire [31:0] tel_tx_stream;
    wire        tel_tx_pulse;

    // Loopback connection setup
    assign tel_rx_ch1    = tel_tx_stream;
    assign tel_rx_ch2    = 32'hDEADBEEF; 
    assign tel_rx_ready  = tel_tx_pulse;
    
    // 2. Orchestrate Shared Multiplexing Feedback to Master Bus
    always @(*) begin
        if (pwm_select) begin
            wb_dat_r = pwm_dat_r;
            wb_ack   = pwm_ack;
        end else if (qei_select) begin
            wb_dat_r = qei_dat_r;
            wb_ack   = qei_ack;
        end else if (telemetry_select) begin
            wb_dat_r = tel_dat_r;
            wb_ack   = tel_ack;
        end else begin
            wb_dat_r = 32'h00000000;
            wb_ack   = 1'b0;
        end
    end

    // Instance 1: Motor PWM Module
    wb_pwm motor_controller_inst (
        .wb_clk_i (sys_clk),
        .wb_rst_i (sys_rst),
        .wb_adr_i (wb_adr[1:0]), // FIX: Changed from [0] to [1:0]
        .wb_dat_i (wb_dat_w),
        .wb_dat_o (pwm_dat_r),
        .wb_we_i  (wb_we),
        .wb_stb_i (wb_stb && pwm_select),
        .wb_cyc_i (wb_cyc && pwm_select),
        .wb_ack_o (pwm_ack),
        .pwm_pad_o(motor_pwm_pin)
    );

    // Instance 2: Quadrature Position Encoder Module
    wb_qei position_tracker_inst (
        .wb_clk_i (sys_clk),
        .wb_rst_i (sys_rst),
        .wb_adr_i (wb_adr[1:0]), // FIX: Changed from [0] to [1:0]
        .wb_dat_i (wb_dat_w),
        .wb_dat_o (qei_dat_r),
        .wb_we_i  (wb_we),
        .wb_stb_i (wb_stb && qei_select),
        .wb_cyc_i (wb_cyc && qei_select),
        .wb_ack_o (qei_ack),
        .enc_a    (enc_a_pin),
        .enc_b    (enc_b_pin)
    );

    // Instance 3: Telemetry Subsystem Block
    wb_telemetry telemetry_inst (
        .wb_clk_i       (sys_clk),
        .wb_rst_i       (sys_rst),
        .wb_adr_i       (wb_adr[1:0]), // FIX: Changed from [0] to [1:0]
        .wb_dat_i       (wb_dat_w),
        .wb_dat_o       (tel_dat_r),
        .wb_we_i        (wb_we),
        .wb_stb_i       (wb_stb && telemetry_select),
        .wb_cyc_i       (wb_cyc && telemetry_select),
        .wb_ack_o       (tel_ack),
        
        .rx_channel_1   (tel_rx_ch1),
        .rx_channel_2   (tel_rx_ch2),
        .rx_data_ready  (tel_rx_ready),
        .tx_raw_stream  (tel_tx_stream),
        .tx_start_pulse (tel_tx_pulse)
    );

endmodule