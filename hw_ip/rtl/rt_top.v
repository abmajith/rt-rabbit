// hw_ip/rtl/rt_top.v


module rt_top (
    input  wire        sys_clk,
    input  wire        sys_rst,
    
    // Shared Wishbone wires exposed to the simulation engine
    input  wire [2:0]  wb_adr,
    input  wire [31:0] wb_dat_w,
    output reg  [31:0] wb_dat_r,
    input  wire        wb_we,
    input  wire        wb_stb,
    input  wire        wb_cyc,
    output wire        wb_ack,

    // Real world system IO bindings
    output wire        motor_pwm_pin,
    input  wire        enc_a_pin,
    input  wire        enc_b_pin
);

    // Peripheral Selection Decoders
    wire pwm_select = (wb_adr[2] == 1'b0);
    wire qei_select = (wb_adr[2] == 1'b1);

    wire [31:0] pwm_dat_r;
    wire [31:0] qei_dat_r;
    wire        pwm_ack;
    wire        qei_ack;

    // Orchestrate Shared Multiplexing Feedback to Master Bus
    assign wb_ack = pwm_select ? pwm_ack : qei_ack;
    always @(*) begin
        wb_dat_r = pwm_select ? pwm_dat_r : qei_dat_r;
    end

    // Instance 1: Motor PWM Module
    wb_pwm motor_controller_inst (
        .wb_clk_i (sys_clk),
        .wb_rst_i (sys_rst),
        .wb_adr_i (wb_adr[1:0]),
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
        .wb_adr_i (wb_adr[1:0]),
        .wb_dat_i (wb_dat_w),
        .wb_dat_o (qei_dat_r),
        .wb_we_i  (wb_we),
        .wb_stb_i (wb_stb && qei_select),
        .wb_cyc_i (wb_cyc && qei_select),
        .wb_ack_o (qei_ack),
        .enc_a    (enc_a_pin),
        .enc_b    (enc_b_pin)
    );

endmodule