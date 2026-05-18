// hw_ip/components/telemetry/telemetry_tx.v
`timescale 1ns/1ps

module telemetry_tx #(
    parameter [15:0] MAX_COUNT = 16'd50000 // Default production ceiling
)(
    input wire          clk,
    input wire          rst,
    input wire [31:0]   tx_payload_data,
    output reg [31:0]   tx_raw_stream,
    output reg          tx_start_pulse
);

    reg [15:0] tx_timer_counter;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_timer_counter <= 16'h0;
            tx_raw_stream    <= 32'h0;
            tx_start_pulse   <= 1'b0;
        end else begin
            if (tx_timer_counter >= MAX_COUNT) begin
                tx_timer_counter <= 16'h0;
                tx_start_pulse   <= 1'b1;
                tx_raw_stream    <= tx_payload_data;
            end else begin
                tx_timer_counter <= tx_timer_counter + 1'b1;
                tx_start_pulse   <= 1'b0;
            end
        end
    end
endmodule