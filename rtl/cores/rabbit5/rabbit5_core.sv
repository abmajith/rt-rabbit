// =============================================================================
// rabbit5_core — 5-stage in-order RV32I pipeline (v0, single hart)
// =============================================================================
//
//   cycle:   1    2    3    4    5    6
//   instr A  IF   ID   EX   MEM  WB
//   instr B       IF   ID   EX   MEM  WB
//
//   IF  : send pc to instruction memory
//   ID  : instruction word arrives; decode; read registers; detect load-use
//   EX  : ALU, branch decision, CSR access, traps        <- commit point
//   MEM : send load/store to data memory
//   WB  : load data arrives; write register; report to RVFI
//
// -----------------------------------------------------------------------------
// TIMING RULES (the whole timing model of v0 — checked in dv/formal/rabbit5/timing)
// -----------------------------------------------------------------------------
//   R1  One instruction retires per cycle, except:
//   R2  Load-use: if an instruction reads the register loaded by the load
//       directly before it, it waits exactly 1 cycle (1 bubble).
//   R3  Redirect: every change of control flow — taken branch, JAL, JALR,
//       MRET, any trap — is decided in EX and costs exactly 2 cycles
//       (2 bubbles). No branch prediction, so the cost never depends on history.
//   R4  Memory must answer in exactly 1 cycle (grant in the request cycle,
//       data the next cycle). This is the scratchpad-memory assumption from
//       FlexPRET/Patmos; the core never waits on memory.
//   R5  Nothing else ever stalls the pipeline.
//
// So the time between two consecutive retirements is 1, 2 (R2) or 3 (R3)
// cycles and depends only on those two instructions.
// -----------------------------------------------------------------------------
//
// Bus: OBI-style request/grant/rvalid, as in the rabbit_cpu contract.
// Verification port: RVFI (riscv-formal interface), always present; it costs
// nothing in synthesis when left unconnected.
// =============================================================================
module rabbit5_core
  import rabbit5_pkg::*;
#(
  parameter logic [31:0] BOOT_ADDR  = 32'h0000_0080,
  parameter logic [31:0] MTVEC_ADDR = 32'h0000_0000,
  parameter logic [31:0] HART_ID    = 32'h0000_0000
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        fetch_enable_i,

  // instruction memory
  output logic        instr_req_o,
  input  logic        instr_gnt_i,
  input  logic        instr_rvalid_i,
  output logic [31:0] instr_addr_o,
  input  logic [31:0] instr_rdata_i,

  // data memory
  output logic        data_req_o,
  input  logic        data_gnt_i,
  input  logic        data_rvalid_i,
  output logic        data_we_o,
  output logic [ 3:0] data_be_o,
  output logic [31:0] data_addr_o,
  output logic [31:0] data_wdata_o,
  input  logic [31:0] data_rdata_i,

  input  logic [31:0] irq_i,          // not used in v0

  // RVFI: one record per retired instruction, valid in its WB cycle
  output logic        rvfi_valid,
  output logic [63:0] rvfi_order,
  output logic [31:0] rvfi_insn,
  output logic        rvfi_trap,
  output logic        rvfi_halt,
  output logic        rvfi_intr,
  output logic [ 1:0] rvfi_mode,
  output logic [ 1:0] rvfi_ixl,
  output logic [ 4:0] rvfi_rs1_addr,
  output logic [ 4:0] rvfi_rs2_addr,
  output logic [31:0] rvfi_rs1_rdata,
  output logic [31:0] rvfi_rs2_rdata,
  output logic [ 4:0] rvfi_rd_addr,
  output logic [31:0] rvfi_rd_wdata,
  output logic [31:0] rvfi_pc_rdata,
  output logic [31:0] rvfi_pc_wdata,
  output logic [31:0] rvfi_mem_addr,
  output logic [ 3:0] rvfi_mem_rmask,
  output logic [ 3:0] rvfi_mem_wmask,
  output logic [31:0] rvfi_mem_rdata,
  output logic [31:0] rvfi_mem_wdata
);

  // ===========================================================================
  // Pipeline registers. Each struct is "what this stage needs to know".
  // ===========================================================================

  // ID/EX
  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] instr;
    decoded_t    dec;
    logic [31:0] rs1_val;   // register values read in ID (EX may forward newer ones)
    logic [31:0] rs2_val;
  } ex_stage_t;

  // EX/MEM and MEM/WB (same content; WB additionally receives load data)
  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] instr;
    logic [31:0] next_pc;   // where the program goes after this instruction
    logic        trap;      // instruction trapped in EX: no side effects
    logic        writes_rd;
    logic [4:0]  rd;
    logic [31:0] result;    // ALU / link / CSR value (loads: filled in WB)
    logic        is_load;
    logic        is_store;
    logic [2:0]  funct3;    // load/store size and sign
    logic [31:0] addr;      // byte address of the load/store
    logic [31:0] store_data;
    logic [4:0]  rs1_addr;  // for RVFI only
    logic [4:0]  rs2_addr;
    logic [31:0] rs1_val;
    logic [31:0] rs2_val;
  } mem_stage_t;

  logic        redirect;       // EX changes control flow this cycle
  logic [31:0] redirect_pc;
  logic        stall;          // ID must wait one cycle (load-use)

  // ===========================================================================
  // IF — instruction fetch
  // ===========================================================================
  // pc_q is the address requested *this* cycle. The memory answers next
  // cycle, when the instruction is in ID (rule R4).
  logic [31:0] pc_q;

  assign instr_req_o  = fetch_enable_i;
  assign instr_addr_o = pc_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)              pc_q <= BOOT_ADDR;
    else if (redirect)        pc_q <= redirect_pc;   // R3
    else if (stall)           pc_q <= pc_q;          // R2: ask for the same word again
    else if (fetch_enable_i)  pc_q <= pc_q + 32'd4;
  end

  // ===========================================================================
  // ID — decode and register read
  // ===========================================================================
  // While ID is stalled, the memory is already returning the *next* word, so
  // the stalled instruction is kept in a small holding register.
  logic        id_valid_q;
  logic [31:0] id_pc_q;
  logic        id_hold_q;
  logic [31:0] id_hold_instr_q;
  logic [31:0] id_instr;

  assign id_instr = id_hold_q ? id_hold_instr_q : instr_rdata_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      id_valid_q      <= 1'b0;
      id_hold_q       <= 1'b0;
      id_hold_instr_q <= '0;
      id_pc_q         <= '0;
    end else if (redirect) begin            // wrong-path instruction: drop it
      id_valid_q      <= 1'b0;
      id_hold_q       <= 1'b0;
    end else if (stall) begin               // keep the same instruction
      id_hold_q       <= 1'b1;
      id_hold_instr_q <= id_instr;
    end else begin                          // take the word requested this cycle
      id_valid_q      <= fetch_enable_i;
      id_hold_q       <= 1'b0;
      id_pc_q         <= pc_q;
    end
  end

  decoded_t id_dec;
  rabbit5_decoder u_decoder (.instr_i(id_instr), .dec_o(id_dec));

  // Register file: read in ID, written in WB
  logic        rf_we;
  logic [4:0]  rf_waddr;
  logic [31:0] rf_wdata;
  logic [31:0] id_rs1_val, id_rs2_val;

  rabbit5_regfile u_regfile (
    .clk_i,
    .raddr_a_i(id_dec.rs1), .rdata_a_o(id_rs1_val),
    .raddr_b_i(id_dec.rs2), .rdata_b_o(id_rs2_val),
    .we_i(rf_we), .waddr_i(rf_waddr), .wdata_i(rf_wdata)
  );

  // ===========================================================================
  // EX — execute (ex_q is the ID/EX pipeline register)
  // ===========================================================================
  ex_stage_t  ex_q;
  mem_stage_t mem_q;   // EX/MEM
  mem_stage_t wb_q;    // MEM/WB
  logic [31:0] wb_result;

  // Load-use hazard (rule R2): the load is in EX now, its data only exists
  // in WB, two cycles from now. Hold the dependent instruction for one cycle.
  logic load_use;
  assign load_use = id_valid_q && ex_q.valid && ex_q.dec.is_load && ex_q.dec.writes_rd &&
                    ((id_dec.uses_rs1 && id_dec.rs1 == ex_q.dec.rd) ||
                     (id_dec.uses_rs2 && id_dec.rs2 == ex_q.dec.rd));
  assign stall = load_use && !redirect;   // a redirect throws the ID instruction away anyway

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)                  ex_q       <= '0;
    else if (redirect || stall)   ex_q.valid <= 1'b0;   // insert a bubble
    else begin
      ex_q.valid   <= id_valid_q;
      ex_q.pc      <= id_pc_q;
      ex_q.instr   <= id_instr;
      ex_q.dec     <= id_dec;
      ex_q.rs1_val <= id_rs1_val;
      ex_q.rs2_val <= id_rs2_val;
    end
  end

  // ---- forwarding: use the newest value of a register -----------------------
  // Priority: MEM (younger) over WB (older) over the value read in ID.
  // A load in MEM never needs forwarding here: R2 guarantees a bubble.
  function automatic logic [31:0] forward(input logic [4:0] r, input logic [31:0] id_val);
    if      (mem_q.valid && mem_q.writes_rd && !mem_q.is_load && mem_q.rd == r) return mem_q.result;
    else if (wb_q.valid  && wb_q.writes_rd  && wb_q.rd == r)                    return wb_result;
    else                                                                         return id_val;
  endfunction

  logic [31:0] rs1, rs2;
  assign rs1 = forward(ex_q.dec.rs1, ex_q.rs1_val);
  assign rs2 = forward(ex_q.dec.rs2, ex_q.rs2_val);

  // ---- ALU ------------------------------------------------------------------
  logic [31:0] alu_a, alu_b, alu_y;
  always_comb begin
    unique case (ex_q.dec.opa)
      OPA_RS1: alu_a = rs1;
      OPA_PC : alu_a = ex_q.pc;
      default: alu_a = 32'b0;
    endcase
    alu_b = (ex_q.dec.opb == OPB_RS2) ? rs2 : ex_q.dec.imm;
  end

  rabbit5_alu u_alu (.op_i(ex_q.dec.alu_op), .a_i(alu_a), .b_i(alu_b), .y_o(alu_y));

  // ---- branches and jumps -----------------------------------------------------
  logic        branch_cond;
  always_comb begin
    unique case (ex_q.dec.funct3)
      3'b000 : branch_cond = (rs1 == rs2);                     // BEQ
      3'b001 : branch_cond = (rs1 != rs2);                     // BNE
      3'b100 : branch_cond = ($signed(rs1) <  $signed(rs2));   // BLT
      3'b101 : branch_cond = ($signed(rs1) >= $signed(rs2));   // BGE
      3'b110 : branch_cond = (rs1 <  rs2);                     // BLTU
      3'b111 : branch_cond = (rs1 >= rs2);                     // BGEU
      default: branch_cond = 1'b0;
    endcase
  end

  logic        taken;
  logic [31:0] jump_target;
  assign taken       = ex_q.dec.is_jal || ex_q.dec.is_jalr || (ex_q.dec.is_branch && branch_cond);
  assign jump_target = ex_q.dec.is_jalr ? ((rs1 + ex_q.dec.imm) & ~32'd1)
                                        : (ex_q.pc + ex_q.dec.imm);

  // ---- exceptions (all detected here, in EX) -----------------------------------
  logic        csr_illegal;
  logic        target_misaligned, mem_misaligned;
  assign target_misaligned = taken && (jump_target[1:0] != 2'b00);
  always_comb begin
    unique case (ex_q.dec.funct3[1:0])
      2'b00  : mem_misaligned = 1'b0;                  // byte
      2'b01  : mem_misaligned = alu_y[0];              // half word
      default: mem_misaligned = (alu_y[1:0] != 2'b00); // word
    endcase
    mem_misaligned = mem_misaligned && (ex_q.dec.is_load || ex_q.dec.is_store);
  end

  logic        trap;
  logic [31:0] trap_cause, trap_tval;
  always_comb begin
    trap       = 1'b1;
    trap_tval  = 32'b0;
    if      (ex_q.dec.illegal || csr_illegal) begin trap_cause = CAUSE_ILLEGAL_INSN; trap_tval = ex_q.instr; end
    else if (ex_q.dec.is_ecall)               trap_cause = CAUSE_ECALL_M;
    else if (ex_q.dec.is_ebreak)              trap_cause = CAUSE_BREAKPOINT;
    else if (target_misaligned)       begin trap_cause = CAUSE_INSN_MISALIGNED; trap_tval = jump_target; end
    else if (mem_misaligned)          begin
      trap_cause = ex_q.dec.is_load ? CAUSE_LOAD_MISALIGNED : CAUSE_STORE_MISALIGNED;
      trap_tval  = alu_y;
    end
    else begin trap = 1'b0; trap_cause = 32'b0; end
    trap = trap && ex_q.valid;
  end

  // ---- CSRs -------------------------------------------------------------------
  logic [31:0] csr_rdata, mtvec, mepc;
  logic        csr_write_req;
  // CSRRW(I) always writes; CSRRS/CSRRC(I) write only if the rs1 field is not 0
  assign csr_write_req = (ex_q.dec.funct3[1:0] == 2'b01) || (ex_q.dec.rs1 != 5'd0);

  rabbit5_csr #(.MTVEC_RESET(MTVEC_ADDR), .HART_ID(HART_ID)) u_csr (
    .clk_i, .rst_ni,
    .csr_valid_i  (ex_q.valid && ex_q.dec.is_csr),
    .csr_addr_i   (ex_q.instr[31:20]),
    .csr_op_i     (ex_q.dec.funct3[1:0]),
    .csr_write_i  (csr_write_req),
    .csr_src_i    (ex_q.dec.funct3[2] ? ex_q.dec.imm : rs1),
    .csr_rdata_o  (csr_rdata),
    .csr_illegal_o(csr_illegal),
    .trap_i       (trap),
    .trap_cause_i (trap_cause),
    .trap_pc_i    (ex_q.pc),
    .trap_tval_i  (trap_tval),
    .mret_i       (ex_q.valid && ex_q.dec.is_mret),
    .instret_i    (ex_q.valid && !trap),
    .mtvec_o      (mtvec),
    .mepc_o       (mepc)
  );

  // ---- next pc and redirect (rule R3) -------------------------------------------
  logic [31:0] next_pc;
  always_comb begin
    if      (trap)             next_pc = mtvec;
    else if (ex_q.dec.is_mret) next_pc = mepc;
    else if (taken)            next_pc = jump_target;
    else                       next_pc = ex_q.pc + 32'd4;
  end
  assign redirect    = ex_q.valid && (trap || ex_q.dec.is_mret || taken);
  assign redirect_pc = next_pc;

  // ---- EX result ------------------------------------------------------------------
  logic [31:0] ex_result;
  always_comb begin
    unique case (ex_q.dec.res)
      RES_PC4: ex_result = ex_q.pc + 32'd4;
      RES_CSR: ex_result = csr_rdata;
      default: ex_result = alu_y;
    endcase
  end

  // ---- EX/MEM register --------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) mem_q <= '0;
    else begin
      mem_q.valid      <= ex_q.valid;
      mem_q.pc         <= ex_q.pc;
      mem_q.instr      <= ex_q.instr;
      mem_q.next_pc    <= next_pc;
      mem_q.trap       <= trap;
      mem_q.writes_rd  <= ex_q.dec.writes_rd && !trap;   // a trap has no side effects
      mem_q.rd         <= ex_q.dec.rd;
      mem_q.result     <= ex_result;
      mem_q.is_load    <= ex_q.dec.is_load  && !trap;
      mem_q.is_store   <= ex_q.dec.is_store && !trap;
      mem_q.funct3     <= ex_q.dec.funct3;
      mem_q.addr       <= alu_y;
      mem_q.store_data <= rs2;
      mem_q.rs1_addr   <= ex_q.dec.uses_rs1 ? ex_q.dec.rs1 : 5'd0;
      mem_q.rs2_addr   <= ex_q.dec.uses_rs2 ? ex_q.dec.rs2 : 5'd0;
      mem_q.rs1_val    <= ex_q.dec.uses_rs1 ? rs1 : 32'd0;
      mem_q.rs2_val    <= ex_q.dec.uses_rs2 ? rs2 : 32'd0;
    end
  end

  // ===========================================================================
  // MEM — issue the data access (answer arrives in WB, rule R4)
  // ===========================================================================
  // Byte enables for the 4 bytes of the addressed word
  function automatic logic [3:0] byte_mask(input logic [1:0] size, input logic [1:0] offset);
    unique case (size)
      2'b00  : return 4'b0001 << offset;   // byte
      2'b01  : return 4'b0011 << offset;   // half word
      default: return 4'b1111;             // word
    endcase
  endfunction

  logic [3:0] mem_mask;
  assign mem_mask = byte_mask(mem_q.funct3[1:0], mem_q.addr[1:0]);

  assign data_req_o   = mem_q.valid && (mem_q.is_load || mem_q.is_store);
  assign data_we_o    = mem_q.is_store;
  assign data_addr_o  = {mem_q.addr[31:2], 2'b00};
  assign data_be_o    = mem_mask;
  // replicate the store data so each byte lane carries the right byte
  always_comb begin
    unique case (mem_q.funct3[1:0])
      2'b00  : data_wdata_o = {4{mem_q.store_data[7:0]}};
      2'b01  : data_wdata_o = {2{mem_q.store_data[15:0]}};
      default: data_wdata_o = mem_q.store_data;
    endcase
  end

  // ---- MEM/WB register ----------------------------------------------------------------
  logic [3:0]  wb_mask;
  logic [31:0] wb_mem_wdata;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wb_q         <= '0;
      wb_mask      <= '0;
      wb_mem_wdata <= '0;
    end else begin
      wb_q.valid      <= mem_q.valid;
      wb_q.pc         <= mem_q.pc;
      wb_q.instr      <= mem_q.instr;
      wb_q.next_pc    <= mem_q.next_pc;
      wb_q.trap       <= mem_q.trap;
      wb_q.writes_rd  <= mem_q.writes_rd;
      wb_q.rd         <= mem_q.rd;
      wb_q.result     <= mem_q.result;
      wb_q.is_load    <= mem_q.is_load;
      wb_q.is_store   <= mem_q.is_store;
      wb_q.funct3     <= mem_q.funct3;
      wb_q.addr       <= mem_q.addr;
      wb_q.store_data <= mem_q.store_data;
      wb_q.rs1_addr   <= mem_q.rs1_addr;
      wb_q.rs2_addr   <= mem_q.rs2_addr;
      wb_q.rs1_val    <= mem_q.rs1_val;
      wb_q.rs2_val    <= mem_q.rs2_val;
      wb_mask         <= mem_mask;
      wb_mem_wdata    <= data_wdata_o;
    end
  end

  // ===========================================================================
  // WB — load data arrives, write the register file
  // ===========================================================================
  logic [31:0] load_shifted, load_value;
  assign load_shifted = data_rdata_i >> {wb_q.addr[1:0], 3'b000};
  always_comb begin
    unique case (wb_q.funct3)
      3'b000 : load_value = {{24{load_shifted[7]}},  load_shifted[7:0]};   // LB
      3'b001 : load_value = {{16{load_shifted[15]}}, load_shifted[15:0]};  // LH
      3'b100 : load_value = {24'b0, load_shifted[7:0]};                     // LBU
      3'b101 : load_value = {16'b0, load_shifted[15:0]};                    // LHU
      default: load_value = load_shifted;                                   // LW
    endcase
  end

  assign wb_result = wb_q.is_load ? load_value : wb_q.result;
  assign rf_we     = wb_q.valid && wb_q.writes_rd;
  assign rf_waddr  = wb_q.rd;
  assign rf_wdata  = wb_result;

  // ===========================================================================
  // RVFI — report each retired instruction to the formal checkers
  // ===========================================================================
  logic [63:0] order_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)         order_q <= '0;
    else if (wb_q.valid) order_q <= order_q + 64'd1;
  end

  assign rvfi_valid     = wb_q.valid;
  assign rvfi_order     = order_q;
  assign rvfi_insn      = wb_q.instr;
  assign rvfi_trap      = wb_q.trap;
  assign rvfi_halt      = 1'b0;
  assign rvfi_intr      = 1'b0;
  assign rvfi_mode      = 2'd3;          // machine mode
  assign rvfi_ixl       = 2'd1;          // 32-bit
  assign rvfi_rs1_addr  = wb_q.rs1_addr;
  assign rvfi_rs2_addr  = wb_q.rs2_addr;
  assign rvfi_rs1_rdata = wb_q.rs1_val;
  assign rvfi_rs2_rdata = wb_q.rs2_val;
  assign rvfi_rd_addr   = wb_q.writes_rd ? wb_q.rd : 5'd0;
  assign rvfi_rd_wdata  = wb_q.writes_rd ? wb_result : 32'd0;
  assign rvfi_pc_rdata  = wb_q.pc;
  assign rvfi_pc_wdata  = wb_q.next_pc;
  assign rvfi_mem_addr  = {wb_q.addr[31:2], 2'b00};
  assign rvfi_mem_rmask = wb_q.is_load  ? wb_mask : 4'b0;
  assign rvfi_mem_wmask = wb_q.is_store ? wb_mask : 4'b0;
  assign rvfi_mem_rdata = data_rdata_i;
  assign rvfi_mem_wdata = wb_q.is_store ? wb_mem_wdata : 32'd0;

  // ===========================================================================
  // Simulation-only check of rule R4 (the memory contract)
  // ===========================================================================
`ifndef SYNTHESIS
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (rst_ni) begin
      if (instr_req_o && !instr_gnt_i) $error("rabbit5: instruction memory must grant immediately (rule R4)");
      if (data_req_o  && !data_gnt_i)  $error("rabbit5: data memory must grant immediately (rule R4)");
    end
  end
`endif

  // Inputs that v0 does not use (kept so the port list matches rabbit_cpu)
  logic unused;
  assign unused = ^{instr_rvalid_i, data_rvalid_i, irq_i, wb_q.store_data};

endmodule
