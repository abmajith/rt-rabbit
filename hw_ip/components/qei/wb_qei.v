// hw_ip/open_source_ip/wb_qei.v
// A Wishbone-attached Quadrature Encoder Interface for tracking motor positions

module wb_qei (
    input  wire        wb_clk_i,
    input  wire        wb_rst_i,
    input  wire [1:0]  wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output reg  [31:0] wb_dat_o,
    input  wire        wb_we_i,
    input  wire        wb_stb_i,
    input  wire        wb_cyc_i,
    output reg         wb_ack_o,

    // Encoder Hardware Inputs
    input  wire        enc_a,
    input  wire        enc_b
);

    // Registers:
    // Reg 0 (Addr 00): Position Count Register (Signed 32-bit position tracker)
    // Reg 1 (Addr 01): Reset/Control Register
    reg signed [31:0] position_count;

    // Synchronize and debounce encoder inputs to prevent metastability glitching
    reg [2:0] shift_a;
    reg [2:0] shift_b;
    
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            shift_a <= 3'b0;
            shift_b <= 3'b0;
        end else begin
            shift_a <= {shift_a[1:0], enc_a};
            shift_b <= {shift_b[1:0], enc_b};
        end
    end

    // Detect edges on synchronized inputs
    wire a_rose = (shift_a[2:1] == 2'b01);
    wire a_fell = (shift_a[2:1] == 2'b10);

    // --- Wishbone Interface read/write logic ---
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_ack_o       <= 1'b0;
            wb_dat_o       <= 32'd0;
            position_count <= 32'd0;
        end else begin
            wb_ack_o <= 1'b0;

            // Handle Position Counter Updates via Hardware Edges
            if (a_rose) begin
                if (shift_b[1]) position_count <= position_count - 1; // Counter-Clockwise
                else            position_count <= position_count + 1; // Clockwise
            end else if (a_fell) begin
                if (shift_b[1]) position_count <= position_count + 1; // Clockwise
                else            position_count <= position_count - 1; // Counter-Clockwise
            end

            // Handle Bus Interface Access overrides from CPU
            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                if (wb_we_i) begin
                    if (wb_adr_i == 2'b00) position_count <= wb_dat_i; // Clear or preset position
                end else begin
                    case (wb_adr_i)
                        2'b00:   wb_dat_o <= position_count;
                        default: wb_dat_o <= 32'd0;
                    endcase
                end
            end
        end
    end
endmodule