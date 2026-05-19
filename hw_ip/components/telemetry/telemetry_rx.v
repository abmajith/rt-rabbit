// hw_ip/components/telemetry/telemetry_rx.v
`timescale 1ns/1ps

module telemetry_rx (
    input wire          clk,
    input wire          rst,
    input wire [31:0]   rx_channel_1,
    input wire [31:0]   rx_channel_2,
    input wire          rx_data_ready,
    output reg [31:0]   voted_cmd,
    output reg [1:0]    status_flags // [0]: Link Alive, [1]: Voter Error
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            voted_cmd    <= 32'h0;
            status_flags <= 2'b00;
        end else if (rx_data_ready) begin
            if (rx_channel_1 == rx_channel_2) begin
                voted_cmd       <= rx_channel_1;
                status_flags[0] <= 1'b1;  // Link Alive
                status_flags[1] <= 1'b0;  // No Error
            end else begin
                status_flags[1] <= 1'b1;  // Critical Spatial Misalignment Detected!
            end
        end
    end
endmodule
