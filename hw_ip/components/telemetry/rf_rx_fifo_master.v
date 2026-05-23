`timescale 1ns/1ps

module rf_rx_fifo_master (
    // System Clock Domain
    input  wire        sys_clk,
    input  wire        sys_rst,

    // Wishbone Master Interface (To write directly to System Memory)
    output reg  [31:0] wb_adr_o,
    output reg  [31:0] wb_dat_o,
    output reg         wb_we_o,
    output reg         wb_stb_o,
    output reg         wb_cyc_o,
    input  wire        wb_ack_i,
    input  wire        wb_err_i,

    // Hardware Interface from the Packet Framer
    input  wire [31:0] packet_data_i,     
    input  wire        packet_valid_i,    
    
    // System Notifications
    output reg         irq_packet_ready,   // Normal execution interrupt
    output reg         bus_timeout_err     // Critical diagnostic error flag out to logging
);

    // Internal Configuration Parameters
    parameter [31:0] BUFFER_BASE_ADDR = 32'h0000_2000;
    parameter [3:0]  TIMEOUT_LIMIT    = 4'd15; // Max clock cycles to wait for an ACK

    // State Machine Definitions
    localparam STATE_IDLE        = 2'b00;
    localparam STATE_REQ_BUS     = 2'b01;
    localparam STATE_BURST_WRITE = 2'b10;
    localparam STATE_NOTIFY_CPU  = 2'b11;

    reg [1:0]  master_fsm;
    reg [31:0] data_buffer_reg;
    reg [3:0]  timeout_counter; // Tracks unresponsive bus clock cycles

    always @(posedge sys_clk) begin
        if (sys_rst) begin
            wb_adr_o         <= 32'h0;
            wb_dat_o         <= 32'h0;
            wb_we_o          <= 1'b0;
            wb_stb_o         <= 1'b0;
            wb_cyc_o         <= 1'b0;
            irq_packet_ready <= 1'b0;
            bus_timeout_err  <= 1'b0;
            data_buffer_reg  <= 32'h0;
            timeout_counter  <= 4'd0;
            master_fsm       <= STATE_IDLE;
        end else begin
            irq_packet_ready <= 1'b0; // Auto-clear pulse

            case (master_fsm)
                
                STATE_IDLE: begin
                    timeout_counter <= 4'd0;
                    if (packet_valid_i) begin
                        data_buffer_reg <= packet_data_i;
                        master_fsm      <= STATE_REQ_BUS;
                    end
                end

                STATE_REQ_BUS: begin
                    wb_cyc_o   <= 1'b1;
                    wb_stb_o   <= 1'b1;
                    wb_we_o    <= 1'b1;
                    wb_adr_o   <= BUFFER_BASE_ADDR;
                    wb_dat_o   <= data_buffer_reg;
                    master_fsm <= STATE_BURST_WRITE;
                end

                STATE_BURST_WRITE: begin
                    if (wb_ack_i) begin
                        wb_cyc_o   <= 1'b0;
                        wb_stb_o   <= 1'b0;
                        wb_we_o    <= 1'b0;
                        master_fsm <= STATE_NOTIFY_CPU;
                    end else if (wb_err_i) begin
                        wb_cyc_o   <= 1'b0;
                        wb_stb_o   <= 1'b0;
                        wb_we_o    <= 1'b0;
                        master_fsm <= STATE_IDLE; 
                    end else begin
                        // Neither ACK nor ERR occurred! Tick the safety timer
                        timeout_counter <= timeout_counter + 1'b1;
                        
                        if (timeout_counter == TIMEOUT_LIMIT) begin
                            // CRITICAL TIMEOUT: Forcefully abort and drop bus request signals
                            wb_cyc_o        <= 1'b0;
                            wb_stb_o        <= 1'b0;
                            wb_we_o         <= 1'b0;
                            bus_timeout_err <= 1'b1; // Raise hardware fault flag for diagnostics
                            master_fsm      <= STATE_IDLE;
                        end
                    end
                end

                STATE_NOTIFY_CPU: begin
                    irq_packet_ready <= 1'b1;
                    master_fsm       <= STATE_IDLE;
                end

                default: master_fsm <= STATE_IDLE;
            endcase
        end
    end

endmodule