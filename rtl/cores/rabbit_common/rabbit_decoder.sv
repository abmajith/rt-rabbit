// =============================================================================
// rabbit_decoder — instruction bits -> decoded_t   (pure combinational)
// =============================================================================
// Supported: all of RV32I and RV32M, plus FENCE (a no-op) and WFI,
// ECALL, EBREAK, MRET and the six Zicsr instructions.
// Anything else sets `illegal`; the EX stage turns that into a trap.
// =============================================================================
module rabbit_decoder
  import rabbit_pkg::*;
(
  input  logic [31:0] instr_i,
  output decoded_t    dec_o
);

  // Instruction fields (names from the RISC-V spec)
  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;
  logic [4:0] rd, rs1, rs2;
  assign opcode = instr_i[6:0];
  assign rd     = instr_i[11:7];
  assign funct3 = instr_i[14:12];
  assign rs1    = instr_i[19:15];
  assign rs2    = instr_i[24:20];
  assign funct7 = instr_i[31:25];

  // The five immediate formats, already sign-extended
  logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
  assign imm_i = {{20{instr_i[31]}}, instr_i[31:20]};
  assign imm_s = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
  assign imm_b = {{19{instr_i[31]}}, instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
  assign imm_u = {instr_i[31:12], 12'b0};
  assign imm_j = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};

  always_comb begin
    // ---- defaults: a harmless no-op that reads and writes nothing ----------
    dec_o           = '0;
    dec_o.rs1       = rs1;
    dec_o.rs2       = rs2;
    dec_o.rd        = rd;
    dec_o.funct3    = funct3;
    dec_o.alu_op    = ALU_ADD;
    dec_o.opa       = OPA_RS1;
    dec_o.opb       = OPB_IMM;
    dec_o.res       = RES_ALU;
    dec_o.imm       = imm_i;

    unique case (opcode)
      OPC_LUI: begin               // rd = imm
        dec_o.writes_rd = 1'b1;
        dec_o.opa       = OPA_ZERO;
        dec_o.imm       = imm_u;
      end

      OPC_AUIPC: begin             // rd = pc + imm
        dec_o.writes_rd = 1'b1;
        dec_o.opa       = OPA_PC;
        dec_o.imm       = imm_u;
      end

      OPC_JAL: begin               // rd = pc + 4; pc = pc + imm
        dec_o.is_jal    = 1'b1;
        dec_o.writes_rd = 1'b1;
        dec_o.res       = RES_PC4;
        dec_o.imm       = imm_j;
      end

      OPC_JALR: begin              // rd = pc + 4; pc = (rs1 + imm) & ~1
        dec_o.is_jalr   = 1'b1;
        dec_o.uses_rs1  = 1'b1;
        dec_o.writes_rd = 1'b1;
        dec_o.res       = RES_PC4;
        dec_o.illegal   = (funct3 != 3'b000);
      end

      OPC_BRANCH: begin            // if (rs1 ? rs2) pc = pc + imm
        dec_o.is_branch = 1'b1;
        dec_o.uses_rs1  = 1'b1;
        dec_o.uses_rs2  = 1'b1;
        dec_o.imm       = imm_b;
        dec_o.illegal   = (funct3 == 3'b010) || (funct3 == 3'b011);
      end

      OPC_LOAD: begin              // rd = mem[rs1 + imm]
        dec_o.is_load   = 1'b1;
        dec_o.uses_rs1  = 1'b1;
        dec_o.writes_rd = 1'b1;
        dec_o.illegal   = (funct3 == 3'b011) || (funct3 == 3'b110) || (funct3 == 3'b111);
      end

      OPC_STORE: begin             // mem[rs1 + imm] = rs2
        dec_o.is_store  = 1'b1;
        dec_o.uses_rs1  = 1'b1;
        dec_o.uses_rs2  = 1'b1;
        dec_o.imm       = imm_s;
        dec_o.illegal   = (funct3[2] == 1'b1) || (funct3 == 3'b011);
      end

      OPC_OP_IMM: begin            // rd = rs1 op imm
        dec_o.uses_rs1  = 1'b1;
        dec_o.writes_rd = 1'b1;
        unique case (funct3)
          3'b000: dec_o.alu_op = ALU_ADD;
          3'b010: dec_o.alu_op = ALU_SLT;
          3'b011: dec_o.alu_op = ALU_SLTU;
          3'b100: dec_o.alu_op = ALU_XOR;
          3'b110: dec_o.alu_op = ALU_OR;
          3'b111: dec_o.alu_op = ALU_AND;
          3'b001: begin
            dec_o.alu_op  = ALU_SLL;
            dec_o.illegal = (funct7 != 7'b000_0000);
          end
          3'b101: begin
            dec_o.alu_op  = funct7[5] ? ALU_SRA : ALU_SRL;
            dec_o.illegal = (funct7 != 7'b000_0000) && (funct7 != 7'b010_0000);
          end
          default: ;
        endcase
      end

      OPC_OP: begin                // rd = rs1 op rs2
        dec_o.uses_rs1  = 1'b1;
        dec_o.uses_rs2  = 1'b1;
        dec_o.writes_rd = 1'b1;
        dec_o.opb       = OPB_RS2;
        unique case (funct3)
          3'b000: dec_o.alu_op = funct7[5] ? ALU_SUB : ALU_ADD;
          3'b001: dec_o.alu_op = ALU_SLL;
          3'b010: dec_o.alu_op = ALU_SLT;
          3'b011: dec_o.alu_op = ALU_SLTU;
          3'b100: dec_o.alu_op = ALU_XOR;
          3'b101: dec_o.alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
          3'b110: dec_o.alu_op = ALU_OR;
          3'b111: dec_o.alu_op = ALU_AND;
          default: ;
        endcase
        // M extension (funct7 = 0000001): all eight funct3 values exist
        if (funct7 == FUNCT7_MULDIV)
          dec_o.is_muldiv = 1'b1;
        // only ADD/SUB and SRL/SRA have a second encoding (funct7 = 0100000)
        else if (funct7 == 7'b010_0000)
          dec_o.illegal = (funct3 != 3'b000) && (funct3 != 3'b101);
        else
          dec_o.illegal = (funct7 != 7'b000_0000);
      end

      OPC_MISC_MEM: begin          // FENCE: no caches, no reordering -> no-op
        dec_o.illegal = (funct3 != 3'b000);
      end

      OPC_SYSTEM: begin
        if (funct3 == 3'b000) begin
          // ECALL / EBREAK / MRET / WFI: rd and rs1 fields must be zero
          unique case (instr_i[31:20])
            12'h000: dec_o.is_ecall  = 1'b1;
            12'h001: dec_o.is_ebreak = 1'b1;
            12'h302: dec_o.is_mret   = 1'b1;
            12'h105: dec_o.is_wfi    = 1'b1;    // sleep until an enabled interrupt is pending
            default: dec_o.illegal   = 1'b1;
          endcase
          if (rd != 5'd0 || rs1 != 5'd0) dec_o.illegal = 1'b1;
        end else if (funct3 == 3'b100) begin
          dec_o.illegal = 1'b1;
        end else begin
          // CSRRW/CSRRS/CSRRC (funct3[2]=0) and CSRRWI/CSRRSI/CSRRCI (funct3[2]=1).
          // For the I-forms the rs1 field is a 5-bit zero-extended immediate.
          dec_o.is_csr    = 1'b1;
          dec_o.writes_rd = 1'b1;
          dec_o.res       = RES_CSR;
          dec_o.uses_rs1  = !funct3[2];
          dec_o.imm       = {27'b0, rs1};
        end
      end

      default: dec_o.illegal = 1'b1;
    endcase

    // Compressed (16-bit) encodings are not supported
    if (instr_i[1:0] != 2'b11) dec_o.illegal = 1'b1;

    // Writing x0 is "no write" for every later stage
    if (rd == 5'd0) dec_o.writes_rd = 1'b0;

    // An illegal instruction reads and writes nothing
    if (dec_o.illegal) begin
      dec_o.uses_rs1  = 1'b0;
      dec_o.uses_rs2  = 1'b0;
      dec_o.writes_rd = 1'b0;
      dec_o.is_load   = 1'b0;
      dec_o.is_store  = 1'b0;
      dec_o.is_branch = 1'b0;
      dec_o.is_jal    = 1'b0;
      dec_o.is_jalr   = 1'b0;
      dec_o.is_csr    = 1'b0;
      dec_o.is_ecall  = 1'b0;
      dec_o.is_ebreak = 1'b0;
      dec_o.is_mret   = 1'b0;
      dec_o.is_wfi    = 1'b0;
      dec_o.is_muldiv = 1'b0;
    end
  end

endmodule
