`timescale 1ns/1ps

module wb_rf_framer_ctrl #(
    parameter [15:0] COMPILE_SOF = 16'hF53A,
    parameter [15:0] COMPILE_EOF = 16'h0AC5
)(
    // Wishbone Bus Interconnect Interface
    input  wire        wb_clk_i,
    input  wire        wb_rst_i,
    input  wire [1:0]  wb_adr_i,   
    
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] wb_dat_i,
    /* verilator lint_off UNUSEDSIGNAL */

    output reg  [31:0] wb_dat_o,
    input  wire        wb_we_i,
    input  wire        wb_stb_i,
    input  wire        wb_cyc_i,
    output reg         wb_ack_o,

    // Command out back to the PHY bit-aligner
    output reg         cfg_clear_lock_o,

    // Telemetry metric bindings coming directly from core blocks
    input  wire        lock_status_i,
    input  wire        frame_complete_i,
    input  wire [15:0] tracked_packet_idx_i,
    input  wire [15:0] tracked_data_type_i,
    input  wire        err_overflow_i,    
    input  wire        err_length_mismatch_i     
);
    // Bus activation monitor flag
    wire bus_select = wb_cyc_i && wb_stb_i;

    // tracking data packet frame locally
    reg sticky_overflow;
    reg sticky_mismatch;
    reg sticky_complete;

    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            wb_ack_o          <= 1'b0;
            wb_dat_o          <= 32'h0;
            cfg_clear_lock_o  <= 1'b0;
            sticky_overflow   <= 1'b0;
            sticky_mismatch   <= 1'b0;
            sticky_complete   <= 1'b0;
        end else begin
            wb_ack_o         <= 1'b0;
            cfg_clear_lock_o <= 1'b0; // Auto-clearing single cycle stroke behavior

            if (err_overflow_i)        sticky_overflow <= 1'b1;
            if (err_length_mismatch_i) sticky_mismatch <= 1'b1;
            if (frame_complete_i)      sticky_complete <= 1'b1;

            if (bus_select && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                
                if (wb_we_i) begin
                    case (wb_adr_i)
                        2'b11: begin
                            // Writing bit 0 triggers a pulse to manually clear lock
                            cfg_clear_lock_o <= wb_dat_i[0];
                            
                            // Clear diagnostic status logs when software writes a 1 to bit 1
                            if (wb_dat_i[1]) begin
                                sticky_overflow <= 1'b0;
                                sticky_mismatch <= 1'b0;
                                sticky_complete <= 1'b0;
                            end
                        end
                        default: ; // Other addresses are write protected (read-only markers/telemetry)
                    endcase
                end else begin
                    case (wb_adr_i)
                        // Offset 0: Pack both 16-bit compile markers cleanly into one 32-bit bus space
                        2'b00: wb_dat_o <= {COMPILE_EOF, COMPILE_SOF};
                        
                        // Offset 1: Pack dynamic index and type fields for low-overhead read transactions
                        2'b01: wb_dat_o <= {tracked_data_type_i, tracked_packet_idx_i};
                        
                        // Offset 2: System Telemetry Status Dashboard (Sticky Flags + Live Lock Bit)
                        2'b10: wb_dat_o <= {28'h0, sticky_complete, sticky_mismatch, sticky_overflow, lock_status_i};
                        
                        // Offset 3: Empty space for symmetry / loop-backs
                        2'b11: wb_dat_o <= 32'h0;
                    endcase
                end
            end
        end
    end

endmodule
