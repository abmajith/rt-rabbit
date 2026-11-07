// =============================================================================
// rabbit_pkg — types, constants and small helper functions shared by every
// rabbit core (rabbit3, rabbit5, ...)
// =============================================================================
// Everything here is "a fact about RISC-V" (opcodes, CSR numbers, cause codes)
// or a stage-independent helper. Nothing here knows how many pipeline stages a
// core has — that lives only in rabbitN_core.sv.
// =============================================================================
package rabbit_pkg;

  // ---------------------------------------------------------------------------
  // Configuration: which optional parts of the ISA a core has.
  //
  // Every rabbit core takes one parameter CFG of this type and hands it to the
  // blocks that need it. Its default, RABBIT_CFG, is set by the build:
  //
  //   configs/<name>.mk  (RV32M := 0)  ->  mk/config.mk  ->  -DRABBIT_RV32M=0
  //
  // These `RABBIT_* defines are read here and nowhere else in the RTL. A new
  // option (C, F, vector, debug, ...) is one more field, one more define, and
  // one more line in mk/config.mk (docs/dev: "adding a feature").
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic rv32m;   // M: MUL*, DIV*, REM* (rabbit_muldiv). 0: they trap as illegal
  } rabbit_cfg_t;

`ifndef RABBIT_RV32M
`define RABBIT_RV32M 1
`endif
  localparam rabbit_cfg_t RABBIT_CFG = '{rv32m: (`RABBIT_RV32M != 0)};

  // misa: MXL = 1 (32-bit), I always, M if configured
  function automatic logic [31:0] misa_value(rabbit_cfg_t cfg);
    return 32'h4000_0100 | (cfg.rv32m ? 32'h0000_1000 : 32'h0);
  endfunction

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

  // funct7 of OPC_OP that selects the M extension (MUL..REMU)
  localparam logic [6:0] FUNCT7_MULDIV = 7'b000_0001;

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
  // by rabbit_decoder.
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
    logic        is_wfi;
    logic        is_muldiv;   // M extension: MUL* / DIV* / REM* (funct3 says which)
  } decoded_t;

  // ---------------------------------------------------------------------------
  // Machine-mode CSRs implemented in v0 (addresses from the privileged spec)
  // ---------------------------------------------------------------------------
  localparam logic [11:0] CSR_MSTATUS  = 12'h300;
  localparam logic [11:0] CSR_MISA     = 12'h301;
  localparam logic [11:0] CSR_MIE      = 12'h304;
  localparam logic [11:0] CSR_MTVEC    = 12'h305;
  localparam logic [11:0] CSR_MSCRATCH = 12'h340;
  localparam logic [11:0] CSR_MEPC     = 12'h341;
  localparam logic [11:0] CSR_MCAUSE   = 12'h342;
  localparam logic [11:0] CSR_MTVAL    = 12'h343;
  localparam logic [11:0] CSR_MIP      = 12'h344;
  localparam logic [11:0] CSR_MCYCLE   = 12'hB00;
  localparam logic [11:0] CSR_MINSTRET = 12'hB02;
  localparam logic [11:0] CSR_MCYCLEH  = 12'hB80;
  localparam logic [11:0] CSR_MINSTRETH= 12'hB82;
  localparam logic [11:0] CSR_MHARTID  = 12'hF14;

  // misa: see misa_value() at the top (depends on the configuration)

  // ---------------------------------------------------------------------------
  // Interrupts. Line i of irq_i is bit i of mip and mie (RISC-V standard
  // layout, same as CV32E40P, so the same firmware runs on every core):
  //   3 = MSI (software), 7 = MTI (timer), 11 = MEI (external),
  //   16..31 = local / "fast" lines for robot peripherals (encoder, PWM, ...)
  // ---------------------------------------------------------------------------
  localparam logic [31:0] IRQ_MASK = 32'hFFFF_0888;

  // Which pending line is taken first (CV32E40P order):
  // 31 > 30 > ... > 16 > 11 (MEI) > 3 (MSI) > 7 (MTI)
  function automatic logic [4:0] irq_priority(input logic [31:0] pending);
    for (int i = 31; i >= 16; i--) if (pending[i]) return 5'(i);
    if (pending[11]) return 5'd11;
    if (pending[3])  return 5'd3;
    return 5'd7;     // also the answer when nothing is pending (unused then)
  endfunction

  // Where a trap goes. mtvec[0] selects the mode:
  //   0 = direct:   every trap jumps to the base
  //   1 = vectored: interrupt i jumps to base + 4*i, exceptions to the base
  function automatic logic [31:0] trap_target(input logic [31:0] mtvec,
                                              input logic        is_irq,
                                              input logic [4:0]  irq_id);
    logic [31:0] base;
    base = {mtvec[31:2], 2'b00};
    return (is_irq && mtvec[0]) ? base + {25'b0, irq_id, 2'b00} : base;
  endfunction

  // ---------------------------------------------------------------------------
  // exec_t: everything known about an instruction once it has been executed.
  // Produced by rabbit_execute, then simply carried to retirement:
  //   rabbit3: X -> W          rabbit5: EX -> MEM -> WB
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] instr;
    logic [31:0] next_pc;     // where the program goes after this instruction
    logic        trap;        // trapped: no register write, no memory access
    logic        intr;        // first instruction of an interrupt handler (RVFI)
    logic        writes_rd;
    logic [4:0]  rd;
    logic [31:0] result;      // ALU / link / CSR value (loads: replaced at retirement)
    logic        is_load;
    logic        is_store;
    logic [2:0]  funct3;      // load size and sign
    logic [31:0] addr;        // byte address of the load/store
    logic [3:0]  mem_be;      // byte enables within the addressed word
    logic [31:0] mem_wdata;   // store data, already placed on the right byte lanes
    logic [4:0]  rs1_addr;    // operands actually used (for RVFI only)
    logic [4:0]  rs2_addr;
    logic [31:0] rs1_val;
    logic [31:0] rs2_val;
  } exec_t;

  // ---------------------------------------------------------------------------
  // Helper functions (pure combinational)
  // ---------------------------------------------------------------------------

  // Branch condition for BEQ/BNE/BLT/BGE/BLTU/BGEU (funct3 selects)
  function automatic logic branch_taken(input logic [2:0] funct3,
                                        input logic [31:0] a, input logic [31:0] b);
    unique case (funct3)
      3'b000 : return a == b;                       // BEQ
      3'b001 : return a != b;                       // BNE
      3'b100 : return $signed(a) <  $signed(b);     // BLT
      3'b101 : return $signed(a) >= $signed(b);     // BGE
      3'b110 : return a <  b;                       // BLTU
      3'b111 : return a >= b;                       // BGEU
      default: return 1'b0;
    endcase
  endfunction

  // Load/store size from funct3[1:0]: 00 byte, 01 half word, 10 word
  function automatic logic lsu_misaligned(input logic [1:0] size, input logic [1:0] offset);
    unique case (size)
      2'b00  : return 1'b0;
      2'b01  : return offset[0];
      default: return offset != 2'b00;
    endcase
  endfunction

  function automatic logic [3:0] lsu_byte_enable(input logic [1:0] size, input logic [1:0] offset);
    unique case (size)
      2'b00  : return 4'b0001 << offset;
      2'b01  : return 4'b0011 << offset;
      default: return 4'b1111;
    endcase
  endfunction

  // Replicate store data so every byte lane carries the right byte
  function automatic logic [31:0] lsu_store_lanes(input logic [1:0] size, input logic [31:0] data);
    unique case (size)
      2'b00  : return {4{data[7:0]}};
      2'b01  : return {2{data[15:0]}};
      default: return data;
    endcase
  endfunction

  // Pick the loaded bytes out of the memory word and sign/zero-extend them
  function automatic logic [31:0] lsu_load_value(input logic [2:0] funct3, input logic [1:0] offset,
                                                 input logic [31:0] word);
    logic [31:0] w;
    w = word >> {offset, 3'b000};
    unique case (funct3)
      3'b000 : return {{24{w[7]}},  w[7:0]};    // LB
      3'b001 : return {{16{w[15]}}, w[15:0]};   // LH
      3'b100 : return {24'b0, w[7:0]};          // LBU
      3'b101 : return {16'b0, w[15:0]};         // LHU
      default: return w;                        // LW
    endcase
  endfunction

  // Exception cause codes (mcause)
  localparam logic [31:0] CAUSE_INSN_MISALIGNED  = 32'd0;
  localparam logic [31:0] CAUSE_ILLEGAL_INSN     = 32'd2;
  localparam logic [31:0] CAUSE_BREAKPOINT       = 32'd3;
  localparam logic [31:0] CAUSE_LOAD_MISALIGNED  = 32'd4;
  localparam logic [31:0] CAUSE_STORE_MISALIGNED = 32'd6;
  localparam logic [31:0] CAUSE_ECALL_M          = 32'd11;
  // interrupts: mcause = {1, 26'b0, line number}

endpackage
