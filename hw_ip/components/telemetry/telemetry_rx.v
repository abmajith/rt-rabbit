`timescale 1ns/1ps

module telemetry_rx #(
    parameter MAX_SKEW_DELAY = 32
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [1:0]  mimo_mode_i,
    input  wire [31:0] rx_channel_1,
    input  wire        rx_ch1_ready,
    input  wire [31:0] rx_channel_2,
    input  wire        rx_ch2_ready,
    output reg  [31:0] voted_cmd,
    output reg         voted_cmd_valid,
    output reg  [3:0]  status_flags
);

    // Data storage and valid tracking flags
    reg [31:0] ch1_data;
    reg [31:0] ch2_data;
    reg        ch1_valid_data;
    reg        ch2_valid_data;

    // Edge-detection to protect against chatter/re-triggers
    reg ch1_ready_d, ch2_ready_d;
    wire ch1_pulse  = rx_ch1_ready && !ch1_ready_d;
    wire blue_pulse = rx_ch2_ready && !ch2_ready_d;

    // Window Watchdog Timer
    reg [5:0] timer;
    reg       timer_active;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ch1_ready_d     <= 1'b0;
            ch2_ready_d     <= 1'b0;
            ch1_data        <= 32'h0;
            ch2_data        <= 32'h0;
            ch1_valid_data  <= 1'b0;
            ch2_valid_data  <= 1'b0;
            timer           <= 6'd0;
            timer_active    <= 1'b0;
            voted_cmd       <= 32'h0;
            voted_cmd_valid <= 1'b0;
            status_flags    <= 4'b0000;
        end else begin
            // Update edge detection registers
            ch1_ready_d <= rx_ch1_ready;
            ch2_ready_d <= rx_ch2_ready;

            // Default strobe low
            voted_cmd_valid <= 1'b0;

            // Capture incoming channel pulses with chatter protection
            if (ch1_pulse && !ch1_valid_data) begin
                ch1_data       <= rx_channel_1;
                ch1_valid_data <= 1'b1;
            end
            if (blue_pulse && !ch2_valid_data) begin
                ch2_data       <= rx_channel_2;
                ch2_valid_data <= 1'b1;
            end

            //  Manage Skew Window Timer
            if (!timer_active) begin
                if ((ch1_pulse && !ch2_valid_data) || (blue_pulse && !ch1_valid_data)) begin
                    timer        <= 6'd0;
                    timer_active <= 1'b1;
                end
            end else begin
                timer <= timer + 1'b1;
            end


            // 4. Combined Evaluation Logic (Look ahead includes current cycle captures)
            if ((ch1_valid_data || ch1_pulse) && (ch2_valid_data || blue_pulse)) begin
                // Pull data from register if already captured, otherwise peek at the input wire
                if ((ch1_valid_data ? ch1_data : rx_channel_1) == (ch2_valid_data ? ch2_data : rx_channel_2)) begin
                    voted_cmd       <= ch1_valid_data ? ch1_data : rx_channel_1;
                    voted_cmd_valid <= 1'b1;
                    status_flags    <= 4'b0011; // Match found
                end else begin
                    status_flags    <= 4'b1100; // Payload Data Contradiction
                end

                // Clean reset of staging registers
                ch1_valid_data <= 1'b0;
                ch2_valid_data <= 1'b0;
                timer_active   <= 1'b0;
                timer          <= 6'd0;

            end else if (timer_active && (timer >= MAX_SKEW_DELAY)) begin
                // Watchdog Timeout Evaluation Phase
                case (mimo_mode_i)
                    2'b01: begin // Fallback to Channel 1
                        if (ch1_valid_data) begin
                            voted_cmd       <= ch1_data;
                            voted_cmd_valid <= 1'b1;
                            status_flags    <= 4'b0101;
                        end else begin
                            status_flags    <= 4'b1010; // Timeout: missing Ch1
                        end
                    end
                    2'b10: begin // Fallback to Channel 2
                        if (ch2_valid_data) begin
                            voted_cmd       <= ch2_data;
                            voted_cmd_valid <= 1'b1;
                            status_flags    <= 4'b0110;
                        end else begin
                            status_flags    <= 4'b1001; // Timeout: missing Ch2
                        end
                    end
                    default: begin // Mode 0: Drop single-channel packets
                        status_flags    <= 4'b1000; // Timeout status flag
                    end
                endcase

                // Clean reset of staging registers
                ch1_valid_data <= 1'b0;
                ch2_valid_data <= 1'b0;
                timer_active   <= 1'b0;
                timer          <= 6'd0;
            end
        end
    end
endmodule
