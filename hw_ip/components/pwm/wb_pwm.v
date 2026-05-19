// hw_ip/open_source_ip/wb_pwm.v
// A standard Open-Source Wishbone-attached PWM Peripheral

module wb_pwm (
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

    // Physical Peripheral Output Pins
    output reg         pwm_pad_o   // Output pin connected to the motor driver
);

    // Internal Memory-Mapped Registers
    // Reg 0 (Addr 2'b00): Control Register [0 = Enable Bit]
    // Reg 1 (Addr 2'b01): Period Count Register (Total width of PWM wave)
    // Reg 2 (Addr 2'b10): Duty Cycle Register (High-time width of PWM wave)
    reg [31:0] reg_ctrl;
    reg [31:0] reg_period;
    reg [31:0] reg_duty;

    // Internal Simulation Counter
    reg [31:0] pwm_counter;

    // --- Part A: Wishbone Bus Interface Logic ---
    wire bus_write_en = wb_cyc_i && wb_stb_i && wb_we_i && !wb_ack_o;
    wire bus_read_en  = wb_cyc_i && wb_stb_i && !wb_we_i && !wb_ack_o;

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            reg_ctrl   <= 32'd0;
            reg_period <= 32'd1000; // Default period fallback
            reg_duty   <= 32'd0;    // Default 0% speed
            wb_ack_o   <= 1'b0;
        end else begin
            wb_ack_o <= 1'b0;

            // Handle Writes from CPU
            if (bus_write_en) begin
                wb_ack_o <= 1'b1;
                case (wb_adr_i)
                    2'b00: reg_ctrl   <= wb_dat_i;
                    2'b01: reg_period <= wb_dat_i;
                    2'b10: reg_duty   <= wb_dat_i;
                    default: ;
                endcase
            end
            
            // Handle Reads from CPU
            else if (bus_read_en) begin
                wb_ack_o <= 1'b1;
                case (wb_adr_i)
                    2'b00: wb_dat_o <= reg_ctrl;
                    2'b01: wb_dat_o <= reg_period;
                    2'b10: wb_dat_o <= reg_duty;
                    default: wb_dat_o <= 32'd0;
                endcase
            end
        end
    end

    // --- Part B: Hardware PWM Signal Generation Core ---
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            pwm_counter <= 32'd0;
            pwm_pad_o   <= 1'b0;
        end else if (reg_ctrl[0]) begin // Only run if Enable bit (bit 0) is set to 1
            if (pwm_counter >= reg_period - 1) begin
                pwm_counter <= 32'd0;
            end else begin
                pwm_counter <= pwm_counter + 1;
            end

            // Assert output high if counter is under the duty value
            // Defensive Hardware Saturation Engine
            if (reg_duty == 32'd0) begin
                pwm_pad_o <= 1'b0; // Absolute 0% override
            end else if (reg_duty >= reg_period) begin
                pwm_pad_o <= 1'b1; // Absolute 100% saturation override
            end else begin
                pwm_pad_o <= (pwm_counter < reg_duty) ? 1'b1 : 1'b0; // Normal PWM
            end

        end else begin
            pwm_counter <= 32'd0;
            pwm_pad_o   <= 1'b0;
        end
    end

endmodule
