`timescale 1ns/1ps

module rf_packet_framer #(
    parameter [15:0] EOF_MARKER = 16'h0AC5,   // Compile-time fixed footer pattern
    parameter [15:0] MAX_PAYLOAD = 16'd512    // Defensive memory safety ceiling
)(
    input  wire        clk,                 // System clock domain
    input  wire        rst,                 // Synchronous Active-High Reset

    // Synced Word Interconnect from rf_bit_aligner
    input  wire [15:0] aligned_word_i,
    input  wire        word_valid_i,
    input  wire        sof_detected_i,

    // Control line feeding back to clear the Aligner Lock state machine if packet drops
    output reg         framer_hunting_window_o, // High when waiting for a brand new packet

    // Hardware Storage Engine / Wishbone DMA Allocator Drivers
    output reg  [15:0] dma_data_o,          // Routed payload word out to storage memory
    output reg         dma_write_strobe_o,  // High when dma_data_o contains a valid payload word
    output reg         frame_complete_o,    // Pulses high on perfect packet layout completion
    
    // Exposed Configuration Fields for Register Bus Mapping
    output reg  [15:0] out_packet_idx,      // Track current sequence index
    output reg  [15:0] out_data_type,       // Exposes current frame classification payload
    output reg         err_overflow_o,      
    output reg         err_length_mismatch_o
);

    // State Encoding
    localparam [2:0] STATE_IDLE     = 3'b000,
                     STATE_INDEX    = 3'b001,
                     STATE_TYPE     = 3'b010,
                     STATE_LENGTH   = 3'b011,
                     STATE_PAYLOAD  = 3'b100,
                     STATE_CRC      = 3'b101,
                     STATE_EOF      = 3'b110;

    reg [2:0]  current_state;
    reg [15:0] word_countdown;

    always @(posedge clk) begin
        if (rst) begin
            current_state          <= STATE_IDLE;
            word_countdown         <= 16'h0;
            out_packet_idx         <= 16'h0;
            out_data_type          <= 16'h0;
            dma_data_o             <= 16'h0;
            dma_write_strobe_o     <= 1'b0;
            frame_complete_o       <= 1'b0;
            err_overflow_o         <= 1'b0;
            err_length_mismatch_o  <= 1'b0;
            framer_hunting_window_o <= 1'b1;
        end else begin
            // Single-cycle automatic strobe defaults
            dma_write_strobe_o <= 1'b0;
            frame_complete_o   <= 1'b0;

            // State Machine transitions run strictly when the aligner serves a valid word
            if (word_valid_i || (sof_detected_i && current_state == STATE_IDLE)) begin
                case (current_state)
                    STATE_IDLE: begin
                        if (sof_detected_i) begin
                            framer_hunting_window_o <= 1'b0; // Lock the window: Blind the aligner to new SOFs!
                            current_state           <= STATE_INDEX;
                        end
                    end

                    STATE_INDEX: begin
                        out_packet_idx <= aligned_word_i;
                        current_state  <= STATE_TYPE;
                    end

                    STATE_TYPE: begin
                        out_data_type <= aligned_word_i; // Distinguish telemetry parameters dynamically
                        current_state <= STATE_LENGTH;
                    end

                    STATE_LENGTH: begin
                        if (aligned_word_i > MAX_PAYLOAD) begin
                            err_overflow_o          <= 1'b1;
                            framer_hunting_window_o <= 1'b1; // Escape and re-enable hunt
                            current_state           <= STATE_IDLE;
                        end else if (aligned_word_i == 16'h0) begin
                            current_state <= STATE_CRC;
                        end else begin
                            word_countdown <= aligned_word_i;
                            current_state  <= STATE_PAYLOAD;
                        end
                    end

                    STATE_PAYLOAD: begin
                        // Pass payload words directly to the DMA/storage buffer
                        dma_data_o         <= aligned_word_i;
                        dma_write_strobe_o <= 1'b1;
                        
                        if (word_countdown == 16'd1) begin
                            current_state <= STATE_CRC;
                        end else begin
                            word_countdown <= word_countdown - 1'b1;
                        end
                    end

                    STATE_CRC: begin
                        // Future implementation point: hook up inline CRC evaluation register check.
                        // For now, we skip past the single validation checksum word.
                        current_state <= STATE_EOF;
                    end

                    STATE_EOF: begin
                        framer_hunting_window_o <= 1'b1; // Re-open the aligner's hunting window for the next frame
                        if (aligned_word_i == EOF_MARKER) begin
                            frame_complete_o <= 1'b1; // Flag successful transaction complete
                        end else begin
                            err_length_mismatch_o <= 1'b1; // Packet structure boundary broken
                        end
                        current_state <= STATE_IDLE;
                    end

                    default: current_state <= STATE_IDLE;
                endcase
            end
        end
    end
    
endmodule
