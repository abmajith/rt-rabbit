// A Wishbone-attached Quadrature Encoder Interface for tracking motor positions
module wb_qei (
    // Wishbone Bus Interface Signals
    input  wire        wb_clk_i,   // System Clock
    input  wire        wb_rst_i,   // Synchronous Reset (Active High)
    input  wire [1:0]  wb_adr_i,   // Address lines (Register selection)
    input  wire [31:0] wb_dat_i,   // Data input from CPU/Bus Master
    output reg  [31:0] wb_dat_o,   // Data output back to CPU
    input  wire        wb_we_i,    // Write Enable (1 = Write, 0 = Read)
    input  wire        wb_stb_i,   // Strobe (Indicates valid cycle phase)
    input  wire        wb_cyc_i,   // Cycle (Indicates active bus transaction)
    output reg         wb_ack_o,   // Acknowledge (Handshake back to CPU)

    // Encoder Hardware Inputs
    input  wire        enc_a,
    input  wire        enc_b
);

    // Internal Memory-Mapped Registers
    // Reg 0 (Addr 2'b00): Position Count Register (Signed 32-bit position tracker)
    // Reg 1 (Addr 2'b01): Control Register (Reserved for configuration)
    reg signed [31:0] reg_position;
    reg        [31:0] reg_ctrl;

    // Synchronize and debounce encoder inputs to prevent metastability glitching
    reg [2:0] shift_a;
    /* verilator lint_off UNUSEDSIGNAL */
    reg [2:0] shift_b;
    /* verilator lint_on UNUSEDSIGNAL */
    
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

    // --- Wishbone Bus Interface Logic ---
    wire bus_write_en = wb_cyc_i && wb_stb_i && wb_we_i && !wb_ack_o;
    wire bus_read_en  = wb_cyc_i && wb_stb_i && !wb_we_i && !wb_ack_o;

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            reg_ctrl <= 32'd0;
            wb_ack_o <= 1'b0;
            wb_dat_o <= 32'd0;
        end else begin
            wb_ack_o <= 1'b0;

            // Handle Writes from CPU
            if (bus_write_en) begin
                wb_ack_o <= 1'b1;
                case (wb_adr_i)
                    2'b01:   reg_ctrl   <= wb_dat_i;
                    default: ; // Reg 0 (position) handled in hardware core
                endcase
            end
            
            // Handle Reads from CPU
            else if (bus_read_en) begin
                wb_ack_o <= 1'b1;
                case (wb_adr_i)
                    2'b00:   wb_dat_o <= reg_position;
                    2'b01:   wb_dat_o <= reg_ctrl;
                    default: wb_dat_o <= 32'd0;
                endcase
            end
        end
    end
    
    // --- Hardware Quadrature Core (Isolated tracking engine) ---
    wire cpu_override_position = bus_write_en && (wb_adr_i == 2'b00);


    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            reg_position <= 32'd0;
        end else if (cpu_override_position) begin
            // Explicit Priority: CPU write commands overwrite hardware transitions
            reg_position <= wb_dat_i;
        end else begin
            // Process hardware quadrature movement natively without bus interference
            if (a_rose) begin
                if (shift_b[1]) reg_position <= reg_position - 32'sd1; // Counter-Clockwise
                else            reg_position <= reg_position + 32'sd1; // Clockwise
            end else if (a_fell) begin
                if (shift_b[1]) reg_position <= reg_position + 32'sd1; // Clockwise
                else            reg_position <= reg_position - 32'sd1; // Counter-Clockwise
            end
        end
    end

endmodule
