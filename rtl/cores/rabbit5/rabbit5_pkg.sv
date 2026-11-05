// =============================================================================
// rabbit5_pkg — shared types for the rabbit5 core
// =============================================================================
// rabbit5 is a classic 5-stage, single-issue, in-order RV32I pipeline:
//
//     IF ──► ID ──► EX ──► MEM ──► WB
//
// Design goal: *timing you can reason about*. Every rule that decides how many
// cycles an instruction takes is listed in rabbit5_core.sv ("TIMING RULES") and
// is checked formally in dv/formal/rabbit5/timing/.
//
// Everything that is "a fact about RISC-V" (opcodes, CSR numbers, cause codes)
// lives here, so the pipeline file only contains pipeline logic.
// =============================================================================
package rabbit5_pkg;

  // ---------------------------------------------------------------------------
  // RV32I major opcodes (instruction bits [6:0])
  // ---------------------------------------------------------------------------
  localparam logic [6:0] OPC_LOAD     = 7'b000_0011;
  localparam logic [6:0] OPC_MISC_MEM = 7'b000_1111;  // FENCE
  localparam logic [6:0] OPC_OP_IMM   = 7'b001_0011;
  localparam logic [6:0] OPC_AUIPC    = 7'b001_0111;
  localparam logic [6:0] OPC_STORE    = 7'b010_0011;
  localparam logic [6:0] OPC_OP       = 7'b011_0011;
  localparam logic [6:0] OPC_LUI      = 7'b011_0111;
  localparam logic [6:0] OPC_BRANCH   = 7'b110_0011;
  localparam logic [6:0] OPC_JALR     = 7'b110_0111;
  localparam logic [6:0] OPC_JAL      = 7'b110_1111;
  localparam logic [6:0] OPC_SYSTEM   = 7'b111_0011;  // ECALL, EBREAK, MRET, WFI, CSR*

  // ---------------------------------------------------------------------------
  // ALU operations
  // ---------------------------------------------------------------------------
  typedef enum logic [3:0] {
    ALU_ADD, ALU_SUB,
    ALU_SLL, ALU_SRL, ALU_SRA,
    ALU_SLT, ALU_SLTU,
    ALU_XOR, ALU_OR, ALU_AND
  } alu_op_e;

  // Where the ALU's two operands come from
  typedef enum logic [1:0] { OPA_RS1, OPA_PC, OPA_ZERO } opa_sel_e;
  typedef enum logic       { OPB_RS2, OPB_IMM }          opb_sel_e;

  // What the EX stage hands on as the instruction's result
  typedef enum logic [1:0] {
    RES_ALU,   // arithmetic, LUI, AUIPC, address for loads/stores
    RES_PC4,   // JAL / JALR link value
    RES_CSR    // old CSR value for CSRRW/CSRRS/CSRRC(I)
  } res_sel_e;

  // ---------------------------------------------------------------------------
  // Decoded instruction: everything later stages need to know, produced once
  // by rabbit5_decoder in ID.
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic        illegal;     // not a supported instruction -> trap in EX
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;
    logic        uses_rs1;    // operand really read (for hazards and RVFI)
    logic        uses_rs2;
    logic        writes_rd;   // writes a register other than x0
    logic [31:0] imm;         // sign-extended immediate (zimm for CSR*I)
    alu_op_e     alu_op;
    opa_sel_e    opa;
    opb_sel_e    opb;
    res_sel_e    res;
    logic [2:0]  funct3;      // branch condition / memory size / CSR op
    logic        is_load;
    logic        is_store;
    logic        is_branch;
    logic        is_jal;
    logic        is_jalr;
    logic        is_csr;
    logic        is_ecall;
    logic        is_ebreak;
    logic        is_mret;
  } decoded_t;

  // ---------------------------------------------------------------------------
  // Machine-mode CSRs implemented in v0 (addresses from the privileged spec)
  // ---------------------------------------------------------------------------
  localparam logic [11:0] CSR_MSTATUS  = 12'h300;
  localparam logic [11:0] CSR_MISA     = 12'h301;
  localparam logic [11:0] CSR_MTVEC    = 12'h305;
  localparam logic [11:0] CSR_MSCRATCH = 12'h340;
  localparam logic [11:0] CSR_MEPC     = 12'h341;
  localparam logic [11:0] CSR_MCAUSE   = 12'h342;
  localparam logic [11:0] CSR_MTVAL    = 12'h343;
  localparam logic [11:0] CSR_MCYCLE   = 12'hB00;
  localparam logic [11:0] CSR_MINSTRET = 12'hB02;
  localparam logic [11:0] CSR_MCYCLEH  = 12'hB80;
  localparam logic [11:0] CSR_MINSTRETH= 12'hB82;
  localparam logic [11:0] CSR_MHARTID  = 12'hF14;

  // misa: MXL=1 (32-bit), extension I only
  localparam logic [31:0] MISA_VALUE = 32'h4000_0100;

  // Exception cause codes (mcause)
  localparam logic [31:0] CAUSE_INSN_MISALIGNED  = 32'd0;
  localparam logic [31:0] CAUSE_ILLEGAL_INSN     = 32'd2;
  localparam logic [31:0] CAUSE_BREAKPOINT       = 32'd3;
  localparam logic [31:0] CAUSE_LOAD_MISALIGNED  = 32'd4;
  localparam logic [31:0] CAUSE_STORE_MISALIGNED = 32'd6;
  localparam logic [31:0] CAUSE_ECALL_M          = 32'd11;

endpackage
