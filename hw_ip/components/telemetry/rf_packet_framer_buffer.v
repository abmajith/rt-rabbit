`timescale 1ns/1ps

module rf_packet_framer_buffer (
    input  wire        sys_clk,
    input  wire        sys_rst,

    // Interface coming from rf_bit_aligner
    input  wire [7:0]  rx_byte,
    input  wire        byte_valid,
    output reg         clear_lock,       // Forces bit-aligner to reset after transaction

    // Interface going out to rf_rx_fifo_master
    output reg  [31:0] packet_data_o,    // Reassembled 32-bit payload data word
    output reg         packet_valid_o    // Strobe verifying clean CRC check pass
);

    // State Encoding
    localparam STATE_IDLE      = 3'b000;
    localparam STATE_LEN       = 3'b001;
    localparam STATE_OPCODE    = 3'b010;
    localparam STATE_PAYLOAD   = 3'b011;
    localparam STATE_CRC       = 3'b100;
    localparam STATE_VALIDATE  = 3'b101;

    reg [2:0]  framer_state;
    reg [7:0]  expected_len;
    reg [7:0]  byte_counter;
    reg [15:0] crc_accum;
    
    // Internal payload assembly registers
    reg [7:0]  captured_opcode;
    reg [23:0] captured_payload;
    reg [15:0] received_crc;

    // CCITT CRC-16 Polynomial Function (X^16 + X^12 + X^5 + 1)
    function [15:0] next_crc;
        input [7:0]  data;
        input [15:0] current_crc;
        reg   [15:0] crc;
        integer i;
        begin
            crc = current_crc;
            for (i = 0; i < 8; i = i + 1) begin
                if ((data[7-i] ^ crc[15]) == 1'b1)
                    crc = {crc[14:0], 1'b0} ^ 16'h1021;
                else
                    crc = {crc[14:0], 1'b0};
            end
            next_crc = crc;
        end
    endfunction

    always @(posedge sys_clk) begin
        if (sys_rst) begin
            framer_state     <= STATE_IDLE;
            clear_lock       <= 1'b0;
            packet_data_o    <= 32'h0;
            packet_valid_o   <= 1'b0;
            expected_len     <= 8'h0;
            byte_counter     <= 8'h0;
            crc_accum        <= 16'hFFFF;
            captured_opcode  <= 8'h0;
            captured_payload <= 24'h0;
            received_crc     <= 16'h0;
        end else begin
            packet_valid_o <= 1'b0;
            clear_lock     <= 1'b0;

            if (byte_valid) begin
                // Update running hardware CRC accumulator for every incoming data byte
                if (framer_state != STATE_CRC)
                    crc_accum <= next_crc(rx_byte, crc_accum);

                case (framer_state)
                    
                    STATE_IDLE: begin
                        crc_accum    <= next_crc(rx_byte, 16'hFFFF); // Reset CRC with first byte
                        expected_len <= rx_byte;
                        framer_state <= STATE_OPCODE;
                    end

                    STATE_OPCODE: begin
                        captured_opcode <= rx_byte;
                        byte_counter    <= 8'd1;
                        // For this specification, we assume a 3-byte payload structure (Opcode + 3 Bytes Data = 32-bit Word)
                        framer_state    <= STATE_PAYLOAD;
                    end

                    STATE_PAYLOAD: begin
                        captured_payload <= {captured_payload[15:0], rx_byte};
                        byte_counter     <= byte_counter + 1'b1;
                        if (byte_counter == expected_len - 1'b1) begin
                            byte_counter <= 8'd0;
                            framer_state <= STATE_CRC;
                        end
                    end

                    STATE_CRC: begin
                        received_crc <= {received_crc[7:0], rx_byte};
                        byte_counter <= byte_counter + 1'b1;
                        if (byte_counter == 8'd1) begin
                            framer_state <= STATE_VALIDATE;
                        end
                    end

                    default: framer_state <= STATE_IDLE;
                endcase
            end else if (framer_state == STATE_VALIDATE) begin
                // Verify if calculated CRC matches over-the-air signature
                if (crc_accum == received_crc) begin
                    packet_data_o  <= {captured_opcode, captured_payload};
                    packet_valid_o <= 1'b1; // Trigger Wishbone Master transaction engine
                end
                
                // Force transaction cycle transition and reset sync window
                clear_lock   <= 1'b1; 
                framer_state <= STATE_IDLE;
            end
        end
    end
endmodule