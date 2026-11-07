// =============================================================================
// rabbit timing properties (beyond riscv-formal) — one testbench, every core
// =============================================================================
// riscv-formal proves WHAT each instruction computes. These properties prove
// WHEN: they turn the "TIMING RULES" comment of a rabbit core into checked
// facts. They look only at the RVFI trace and the memory bus, so they treat the
// core as a black box.
//
// The core and its timing model come from rtl/cores/<core>/core.mk, passed in
// as macros by the Makefile:
//   RABBIT_CORE    module name             (rabbit3_core / rabbit5_core)
//   FIRST_RETIRE   cycle of the first retirement after reset (5 / 3)
//   REDIRECT_GAP   cycles between a redirecting instruction and the next (3 / 2)
//   LOADUSE_GAP    cycles between a load and an instruction using it    (2 / 1)
//   IRQ_LATENCY    worst-case interrupt latency, 0 = no interrupts      (7 / 4)
//   COMMIT_TO_RETIRE  cycles from the commit stage to retirement        (2 / 1)
//   MUL_CYCLES     cycles a MUL* spends in the commit stage             (2 / 2)
//   RABBIT_DIV_STEPS  divider steps in this proof; a DIV* spends
//                  RABBIT_DIV_STEPS+2 cycles in the commit stage (see core.mk:
//                  the proof uses 2 steps, the real 32 are proven in muldiv/)
//   RABBIT_HAS_M   defined if the configuration has the M extension (RV32M = 1)
//
//   T1  exact timing model: the gap between two consecutive retirements is
//         REDIRECT_GAP  if the earlier instruction changed control flow
//                       (taken branch, JAL, JALR, MRET, trap)        [rule R3]
//         LOADUSE_GAP   if the later one reads the register the
//                       earlier one loaded (load-use)                [rule R2]
//         1             otherwise                                    [rule R1]
//       plus MUL_CYCLES-1 / DIV_CYCLES-1 if the later one is an M
//       instruction, whatever its operands                           [rule R8]
//   T2  the first instruction retires exactly FIRST_RETIRE cycles after reset
//       (plus the M extra cycles if it is an M instruction)
//   T3  a data-memory request happens exactly one cycle before the instruction
//       that made it retires, and never at any other time            [rule R4]
//   T4  after WFI sleep, the next instruction retires FIRST_RETIRE-1 cycles
//       after the last sleeping cycle, in which fetch restarts ("waking up is
//       like leaving reset": that cycle plays the role of cycle 0)
//
// Interrupts (only if the core declares IRQ_LATENCY > 0):
//   I1  bounded latency: an enabled interrupt that stays pending makes the
//       first handler instruction retire within IRQ_LATENCY cycles (plus
//       that instruction's own M extra cycles if it is a MUL/DIV: the
//       interrupt is *taken* within the bound, whatever the core was doing,
//       including in the middle of a divide)
//   I2  no spurious interrupts: an interrupt is only taken if one was pending
//       and enabled
//   I3  precise: mepc, as read by the handler, is the pc of the instruction
//       that should have run next (so MRET resumes the program exactly there)
//   I4  mcause, as read by the handler, says "interrupt" and names a line that
//       really was pending and enabled (in vectored mode: the line whose
//       vector the core jumped to)
//   I5  the handler starts at the right address: mtvec base (direct mode) or
//       base + 4*line for a requested line (vectored mode)
// M extension (the covers of M1 and R8 only if RABBIT_HAS_M):
//   M0  while an M instruction waits in the commit stage, its operand values
//       do not change (rabbit_muldiv relies on it; white-box: looks inside
//       rabbit_execute)
//   M1  an interrupt that arrives while an M instruction waits is taken
//       within the same IRQ_LATENCY bound (I1 covers it; cover below shows
//       it happens)
//   M2  while an M instruction waits, no instruction is fetched (power: a
//       divide costs no instruction-memory reads)
//   X1  without the M extension: every MUL/DIV/REM encoding traps (illegal
//       instruction) and writes nothing: the hardware is really absent
// Sleep (WFI), for power:
//   W0  the core only falls asleep when a WFI retires
//   W1  it wakes in the cycle after an enabled interrupt becomes pending
//   W2  while asleep nothing moves: no retirement, no data access, no fetch
//
// The solver picks ANY instruction word, ANY load data and ANY interrupt lines
// every cycle.
//
// Ideas for properties to add next (robotics / real-time):
//   - for the dual core (M4): core 0's T1 gaps never depend on core 1
// =============================================================================
module rabbit_timing_tb (
    input logic        clk,
    // Free inputs: the solver may choose ANY instruction word and ANY load
    // data in every cycle. They are top-level inputs on purpose: an
    // (* anyseq *) attribute is silently dropped by the slang frontend, and
    // the signal would become a "don't care" constant that the solver may
    // choose differently at every place it is used.
    input logic [31:0] instr_rdata,
    input logic [31:0] data_rdata,
    input logic [31:0] irq
);
  localparam int FIRST_RETIRE = `FIRST_RETIRE;
  localparam int REDIRECT_GAP = `REDIRECT_GAP;
  localparam int LOADUSE_GAP  = `LOADUSE_GAP;
  localparam int IRQ_LATENCY  = `IRQ_LATENCY;
  localparam int MUL_CYCLES   = `MUL_CYCLES;
  localparam int DIV_CYCLES   = `RABBIT_DIV_STEPS + 2;
`ifndef COMMIT_TO_RETIRE
`define COMMIT_TO_RETIRE 1
`endif
  // The spec model below learns about an instruction when it retires; the
  // core acted on it in its commit stage. D = the extra cycles beyond the one
  // the model already accounts for (rabbit3: 0, rabbit5: 1). Signals of the
  // core's "now" are delayed by D before being compared with the model.
  localparam int D = `COMMIT_TO_RETIRE - 1;
  localparam logic [31:0] IRQ_MASK = 32'hFFFF_0888;   // lines that exist

  // ---- reset for exactly the first cycle -------------------------------------
  logic rst_n = 1'b0;
  always_ff @(posedge clk) rst_n <= 1'b1;

  logic        data_req, instr_req, core_sleep;
  logic        rvfi_valid, rvfi_trap, rvfi_intr;
  logic [31:0] rvfi_insn, rvfi_rs1_rdata, rvfi_rs2_rdata, rvfi_rd_wdata, rvfi_pc_wdata, rvfi_pc_rdata;
  logic [4:0]  rvfi_rs1_addr, rvfi_rs2_addr, rvfi_rd_addr;
  logic [3:0]  rvfi_mem_rmask, rvfi_mem_wmask;

  `RABBIT_CORE dut (
      .clk_i(clk), .rst_ni(rst_n), .fetch_enable_i(1'b1),
      .instr_req_o(instr_req), .instr_gnt_i(1'b1), .instr_rvalid_i(1'b1),
      .instr_addr_o(), .instr_rdata_i(instr_rdata),
      .data_req_o(data_req), .data_gnt_i(1'b1), .data_rvalid_i(1'b1),
      .data_we_o(), .data_be_o(), .data_addr_o(), .data_wdata_o(),
      .data_rdata_i(data_rdata),
      .irq_i(irq), .core_sleep_o(core_sleep),
      .rvfi_valid(rvfi_valid), .rvfi_order(), .rvfi_insn(rvfi_insn),
      .rvfi_trap(rvfi_trap), .rvfi_halt(), .rvfi_intr(rvfi_intr), .rvfi_mode(), .rvfi_ixl(),
      .rvfi_rs1_addr(rvfi_rs1_addr), .rvfi_rs2_addr(rvfi_rs2_addr),
      .rvfi_rs1_rdata(rvfi_rs1_rdata), .rvfi_rs2_rdata(rvfi_rs2_rdata),
      .rvfi_rd_addr(rvfi_rd_addr), .rvfi_rd_wdata(rvfi_rd_wdata),
      .rvfi_pc_rdata(rvfi_pc_rdata), .rvfi_pc_wdata(rvfi_pc_wdata), .rvfi_mem_addr(),
      .rvfi_mem_rmask(rvfi_mem_rmask), .rvfi_mem_wmask(rvfi_mem_wmask),
      .rvfi_mem_rdata(), .rvfi_mem_wdata()
  );

  // ---- core signals delayed by D cycles (see D above) -------------------------
  logic [31:0] irq_hist   [4];
  logic        sleep_hist [4];
  always_ff @(posedge clk) begin
    irq_hist[0]   <= irq;        sleep_hist[0] <= core_sleep;
    for (int k = 1; k < 4; k++) begin
      irq_hist[k] <= irq_hist[k-1]; sleep_hist[k] <= sleep_hist[k-1];
    end
  end
  logic [31:0] irq_d;     // irq as the core saw it D cycles ago
  logic        sleep_d;   // core_sleep, D cycles ago
  assign irq_d   = (D == 0) ? irq        : irq_hist[D-1];
  assign sleep_d = (D == 0) ? core_sleep : sleep_hist[D-1];

  // ---- classify the instruction that retires now ------------------------------
  // (the ISA-level meaning only; nothing about how the core is built)
  logic [6:0] opcode;
  logic [2:0] funct3;
  assign opcode = rvfi_insn[6:0];
  assign funct3 = rvfi_insn[14:12];

  logic branch_taken;
  always_comb begin
    case (funct3)
      3'b000 : branch_taken = (rvfi_rs1_rdata == rvfi_rs2_rdata);
      3'b001 : branch_taken = (rvfi_rs1_rdata != rvfi_rs2_rdata);
      3'b100 : branch_taken = ($signed(rvfi_rs1_rdata) <  $signed(rvfi_rs2_rdata));
      3'b101 : branch_taken = ($signed(rvfi_rs1_rdata) >= $signed(rvfi_rs2_rdata));
      3'b110 : branch_taken = (rvfi_rs1_rdata <  rvfi_rs2_rdata);
      3'b111 : branch_taken = (rvfi_rs1_rdata >= rvfi_rs2_rdata);
      default: branch_taken = 1'b0;
    endcase
  end

  logic is_mret, is_wfi, changes_flow, is_load;
  assign is_mret = (rvfi_insn == 32'h3020_0073);
  assign is_wfi  = (rvfi_insn == 32'h1050_0073);
  assign changes_flow = rvfi_trap
                     || opcode == 7'b1101111                         // JAL
                     || opcode == 7'b1100111                         // JALR
                     || is_mret || is_wfi                            // WFI = jump to pc+4
                     || (opcode == 7'b1100011 && branch_taken);      // taken branch
  assign is_load = (opcode == 7'b0000011) && !rvfi_trap;

  // M extension: extra cycles in the commit stage (rule R8)
  logic is_m;
  int   m_extra;
  assign is_m    = (opcode == 7'b0110011) && (rvfi_insn[31:25] == 7'b0000001) && !rvfi_trap;
  assign m_extra = !is_m ? 0 : funct3[2] ? DIV_CYCLES - 1 : MUL_CYCLES - 1;

`ifndef RABBIT_HAS_M
  // X1: without M, the M encodings are illegal instructions
  logic m_encoding;
  assign m_encoding = (opcode == 7'b0110011) && (rvfi_insn[31:25] == 7'b0000001);
  always_comb begin
    if (rst_n && rvfi_valid && m_encoding)
      assert (rvfi_trap && rvfi_rd_addr == 5'd0 && rvfi_mem_wmask == 4'd0);   // X1
    if (rst_n && rvfi_valid && m_encoding) cover (!rvfi_intr);              // X1 happens
  end
`endif

  // CSR instructions (the ISA meaning: old value -> rd, then write)
  logic        is_csr, csr_writes;
  logic [11:0] csr_addr;
  logic [31:0] csr_src;
  assign is_csr     = (opcode == 7'b1110011) && (funct3[1:0] != 2'b00) && !rvfi_trap;
  assign csr_addr   = rvfi_insn[31:20];
  assign csr_src    = funct3[2] ? {27'b0, rvfi_insn[19:15]} : rvfi_rs1_rdata;
  assign csr_writes = is_csr && (funct3[1:0] == 2'b01 || rvfi_insn[19:15] != 5'd0);

  function automatic logic [31:0] csr_new(input logic [31:0] old);
    unique case (funct3[1:0])
      2'b01  : return csr_src;
      2'b10  : return old |  csr_src;
      default: return old & ~csr_src;
    endcase
  endfunction

  // ---- remember the previous retirement --------------------------------------------
  logic        seen_one;      // at least one instruction has retired
  logic        prev_flow;     // previous instruction changed control flow
  logic        prev_load;     // previous instruction was a load ...
  logic [4:0]  prev_rd;       // ... into this register (0 = none)
  logic [31:0] prev_pc_wdata; // ... and where the program went after it
  int          gap;           // cycles since the previous retirement
  int          cycle;         // cycles since reset was released
  logic        slept;         // the core slept since the previous retirement
  int          since_sleep;   // cycles since the last sleeping cycle, minus 1

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      seen_one    <= 1'b0;
      gap         <= 0;
      cycle       <= 0;
      slept       <= 1'b0;
      since_sleep <= 0;
    end else begin
      cycle       <= cycle + 1;
      since_sleep <= sleep_d ? 0 : since_sleep + 1;
      if (rvfi_valid) begin
        seen_one      <= 1'b1;
        prev_flow     <= changes_flow;
        prev_load     <= is_load;
        prev_rd       <= rvfi_rd_addr;
        prev_pc_wdata <= rvfi_pc_wdata;
        gap           <= 1;
        slept         <= sleep_d;
      end else begin
        gap   <= gap + 1;
        slept <= slept || sleep_d;
      end
    end
  end

  logic load_use;
  assign load_use = prev_load && prev_rd != 5'd0 &&
                    (rvfi_rs1_addr == prev_rd || rvfi_rs2_addr == prev_rd);

  int expected_gap;
  assign expected_gap = (prev_flow ? REDIRECT_GAP : (load_use ? LOADUSE_GAP : 1)) + m_extra;

  // ---- T1, T2, T4 --------------------------------------------------------------------
  // An interrupt removes an instruction from the pipeline; its timing is I1.
  always_comb begin
    if (rst_n && rvfi_valid && !rvfi_intr) begin
      if (!seen_one)  assert (cycle == FIRST_RETIRE - 1 + m_extra);   // T2 (cycle counts from 0)
      else if (slept) assert (since_sleep + 1 + D == FIRST_RETIRE - 1 + m_extra); // T4
      else            assert (gap == expected_gap);              // T1
    end
    if (rst_n && !seen_one) assert (cycle < FIRST_RETIRE + DIV_CYCLES - 1); // T2: nothing is late
  end

  // ---- T3: memory is used exactly one cycle before retirement ---------------------------
  logic data_req_q = 1'b0;
  always_ff @(posedge clk) data_req_q <= data_req;

  always_comb begin
    if (rst_n) assert (data_req_q == (rvfi_valid && (rvfi_mem_rmask != 0 || rvfi_mem_wmask != 0)));
  end

  // ---- M0: operands stay put while an M instruction waits ------------------------------
  logic        ex_busy_q = 1'b0;
  logic [31:0] ex_rs1_q, ex_rs2_q;
  always_ff @(posedge clk) begin
    ex_busy_q <= rst_n && dut.u_execute.busy_o;
    ex_rs1_q  <= dut.u_execute.rs1_i;
    ex_rs2_q  <= dut.u_execute.rs2_i;
  end
  always_comb begin
    if (rst_n && ex_busy_q && dut.u_execute.valid_i)
      assert (dut.u_execute.rs1_i == ex_rs1_q && dut.u_execute.rs2_i == ex_rs2_q);   // M0
    if (rst_n && dut.u_execute.busy_o) assert (!instr_req);                       // M2
  end

  // ---- interrupt-enable state: a spec model computed from RVFI only -------------------
  // m_* = state after every instruction that has retired before this cycle,
  // n_* = ... including the one retiring now. A core changes its CSRs in the
  // commit stage, COMMIT_TO_RETIRE cycles before retirement, so n_* is what
  // the core's commit stage saw D cycles ago (rabbit3: exactly now).
  logic        m_mie, m_mpie, n_mie, n_mpie;     // mstatus.MIE / MPIE
  logic [31:0] m_ie, n_ie;                       // the mie CSR
  logic [31:0] m_tvec, n_tvec;                   // mtvec (bit 0 = vectored)
  always_comb begin
    n_mie = m_mie; n_mpie = m_mpie; n_ie = m_ie; n_tvec = m_tvec;
    if (rvfi_valid) begin
      if (rvfi_intr) begin n_mpie = n_mie; n_mie = 1'b0; end  // entry came before it
      if (rvfi_trap) begin n_mpie = n_mie; n_mie = 1'b0; end
      else if (is_mret) begin n_mie = n_mpie; n_mpie = 1'b1; end
      else if (csr_writes && csr_addr == 12'h300) begin
        n_mie  = csr_new({24'b0, n_mpie, 3'b0, n_mie, 3'b0})[3];
        n_mpie = csr_new({24'b0, n_mpie, 3'b0, n_mie, 3'b0})[7];
      end
      else if (csr_writes && csr_addr == 12'h304) n_ie = csr_new(n_ie) & IRQ_MASK;
      else if (csr_writes && csr_addr == 12'h305) n_tvec = csr_new(n_tvec) & 32'hFFFF_FFFD;
    end
  end
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      m_mie <= 1'b0; m_mpie <= 1'b0; m_ie <= '0;
      m_tvec <= 32'h0000_0001;      // MTVEC_ADDR = 0 (core default), vectored
    end else begin
      m_mie <= n_mie; m_mpie <= n_mpie; m_ie <= n_ie; m_tvec <= n_tvec;
    end
  end

  // In the model's time frame (D cycles behind the core):
  logic [31:0] enabled_lines;   // lines asking AND allowed by mie
  logic        pend_en;         // ... and interrupts globally enabled
  assign enabled_lines = irq_d & n_ie & IRQ_MASK;
  assign pend_en       = rst_n && enabled_lines != 0 && n_mie;
  // While the core sleeps no instruction is in flight, so the model is exact
  // and the sleep checks use the core's own time frame:
  logic        wake_cond;       // an enabled line is asking now
  assign wake_cond     = rst_n && (irq & n_ie & IRQ_MASK) != 0;

  // ---- W0..W2: sleep --------------------------------------------------------------------
  logic sleep_q = 1'b0, sleep_d_q = 1'b0, wake_q = 1'b0;
  always_ff @(posedge clk) begin
    sleep_q <= core_sleep; sleep_d_q <= sleep_d; wake_q <= wake_cond;
  end
  always_comb begin
    if (rst_n) begin
      if (sleep_d && !sleep_d_q)    assert (rvfi_valid && is_wfi);         // W0
      if (sleep_q && wake_q)        assert (!core_sleep);                  // W1
      if (sleep_d && sleep_d_q)     assert (!rvfi_valid);                  // W2
      if (core_sleep && sleep_q)    assert (!data_req);                    // W2
      if (core_sleep && !wake_cond) assert (!instr_req);                   // W2
    end
  end

  generate if (IRQ_LATENCY > 0) begin : g_irq
    // ---- I1, I2: latency and no spurious interrupts ----------------------------------
    int          wait_cycles;   // consecutive cycles an enabled interrupt was pending
    logic        requested;     // ... at least one since the last interrupt
    logic [31:0] req_lines;     // which lines that were
    // An interrupt retiring ends the old request; a new one may already be
    // pending in the same cycle (a handler that re-enables interrupts at once).
    logic restart;
    assign restart = rvfi_valid && rvfi_intr;
    always_ff @(posedge clk) begin
      if (!rst_n) begin
        wait_cycles <= 0;
        requested   <= 1'b0;
        req_lines   <= '0;
      end else begin
        wait_cycles <= pend_en ? (restart ? 1 : wait_cycles + 1) : 0;
        requested   <= pend_en || (requested && !restart);
        req_lines   <= (pend_en ? enabled_lines : '0) | (restart ? '0 : req_lines);
      end
    end
    always_comb begin
      // I1: the handler's first instruction retires within IRQ_LATENCY, plus
      // its own M extra cycles if it is itself a MUL/DIV (it cannot be
      // interrupted: MIE = 0 in the handler). The second line bounds the
      // wait in every cycle, so an interrupt can never be ignored.
      if (rst_n && rvfi_valid && rvfi_intr) assert (wait_cycles + D <= IRQ_LATENCY + m_extra);
      if (rst_n) assert (wait_cycles + D <= IRQ_LATENCY + DIV_CYCLES - 1);
      if (rst_n && rvfi_valid && rvfi_intr) assert (requested);            // I2
    end

    // M1 (cover): an M instruction was waiting when the interrupt was taken
    logic m_busy_seen;
    always_ff @(posedge clk) begin
      if (!rst_n || (rvfi_valid && rvfi_intr)) m_busy_seen <= 1'b0;
      else if (ex_busy_q && dut.u_execute.irq_take) m_busy_seen <= 1'b1;   // was waiting, now interrupted
    end

    // ---- I5: where the handler starts --------------------------------------------------
    // m_tvec is mtvec as the core saw it when it took the interrupt: every
    // instruction retiring in between is older than the interrupted one.
    logic [31:0] tvec_base, vec_off;
    logic [4:0]  vec_line;      // vectored: the line whose vector was used
    assign tvec_base = {m_tvec[31:2], 2'b00};
    assign vec_off   = rvfi_pc_rdata - tvec_base;
    assign vec_line  = vec_off[6:2];
    always_comb begin
      if (rst_n && rvfi_valid && rvfi_intr) begin
        if (m_tvec[0]) assert (vec_off[31:7] == 0 && vec_off[1:0] == 0 &&   // I5
                               req_lines[vec_line]);
        else           assert (rvfi_pc_rdata == tvec_base);                   // I5
      end
    end
    logic [4:0] line_taken, line_now;   // vectored mode: line of the last interrupt
    logic       vectored_taken, vectored_now;
    assign line_now     = (rvfi_valid && rvfi_intr) ? vec_line : line_taken;
    assign vectored_now = (rvfi_valid && rvfi_intr) ? m_tvec[0] : vectored_taken;
    always_ff @(posedge clk) begin
      if (!rst_n) begin line_taken <= '0; vectored_taken <= 1'b0; end
      else begin line_taken <= line_now; vectored_taken <= vectored_now; end
    end

    // ---- I3, I4: what the handler reads from mepc / mcause ---------------------------
    logic        epc_valid, cause_valid;
    logic [31:0] epc_expect, cause_lines;
    logic        epc_v_now, cause_v_now;
    logic [31:0] epc_now, lines_now;
    assign epc_v_now   = (rvfi_valid && rvfi_intr) || epc_valid;
    assign epc_now     = (rvfi_valid && rvfi_intr) ? prev_pc_wdata : epc_expect;
    assign cause_v_now = (rvfi_valid && rvfi_intr) || cause_valid;
    assign lines_now   = (rvfi_valid && rvfi_intr) ? req_lines : cause_lines;
    always_ff @(posedge clk) begin
      if (!rst_n) begin
        epc_valid <= 1'b0; cause_valid <= 1'b0;
      end else if (rvfi_valid) begin
        epc_valid   <= epc_v_now   && !rvfi_trap && !(csr_writes && csr_addr == 12'h341);
        cause_valid <= cause_v_now && !rvfi_trap && !(csr_writes && csr_addr == 12'h342);
        epc_expect  <= epc_now;
        cause_lines <= lines_now;
      end
    end
    always_comb begin
      if (rst_n && rvfi_valid && is_csr && rvfi_rd_addr != 0) begin
        if (csr_addr == 12'h341 && epc_v_now)                              // I3
          assert (rvfi_rd_wdata == epc_now);
        if (csr_addr == 12'h342 && cause_v_now)                            // I4
          assert (rvfi_rd_wdata[31] && rvfi_rd_wdata[30:5] == 0 &&
                  lines_now[rvfi_rd_wdata[4:0]] &&
                  (!vectored_now || rvfi_rd_wdata[4:0] == line_now));
      end
    end

    // ---- non-vacuity ---------------------------------------------------------------------
    always_comb begin
      if (rst_n && rvfi_valid && rvfi_intr) begin
        cover (wait_cycles + D == IRQ_LATENCY && m_extra == 0);   // the bound is tight
        cover (wait_cycles + D == IRQ_LATENCY - 1);
        cover (slept);                            // WFI woken by the interrupt it takes
`ifdef RABBIT_HAS_M
        cover (m_busy_seen);                      // M1: interrupt while an M op waited
`endif
        cover (!m_tvec[0]);                       // direct mode is exercised too
        cover (m_tvec[0] && vec_line != 7);       // ... and a vector other than the timer's
      end
      if (rst_n && rvfi_valid && is_csr && rvfi_rd_addr != 0) begin
        cover (csr_addr == 12'h341 && epc_v_now);
        cover (csr_addr == 12'h342 && cause_v_now);
      end
      if (rst_n && rvfi_valid && !rvfi_intr) cover (slept);  // T4 happens
    end
  end endgenerate

  // ---- throughput bounds ------------------------------------------------------------------
  // From T1 + T2: after the first retirement (cycle FIRST_RETIRE-1), one more
  // instruction retires every 1..REDIRECT_GAP cycles. So at cycle 19 between
  // MIN_AT_19 and MAX_AT_19 have retired (rabbit5: 6..16, rabbit3: 9..18),
  // not counting M extra cycles and sleep.
  // Both extremes must be reachable (covers below).
  localparam int MAX_AT_19 = 19 - (FIRST_RETIRE - 1) + 1;
  localparam int MIN_AT_19 = (19 - (FIRST_RETIRE - 1)) / REDIRECT_GAP + 1;
  int retired;
  always_ff @(posedge clk) begin
    if (!rst_n)          retired <= 0;
    else if (rvfi_valid) retired <= retired + 1;
  end
  logic [31:0] retired_now;     // including an instruction retiring this cycle
  assign retired_now = retired + (rvfi_valid ? 1 : 0);

  // ---- non-vacuity: every case of T1 must really happen ------------------------------------
  always_comb begin
    if (rst_n && cycle == 19) begin
      cover (retired_now == MIN_AT_19);   // slowest possible: every instruction redirects
      cover (retired_now == MAX_AT_19);   // fastest possible: no bubbles at all
    end
    if (rst_n && rvfi_valid && seen_one) begin
      cover (gap == 1);
      cover (gap == LOADUSE_GAP && load_use);
      cover (gap == REDIRECT_GAP);
      cover (gap == REDIRECT_GAP && rvfi_trap);
`ifdef RABBIT_HAS_M
      cover (is_m && !funct3[2] && gap == MUL_CYCLES);       // R8: multiply
      cover (is_m &&  funct3[2] && gap == DIV_CYCLES);       // R8: divide
      cover (is_m && load_use);                              // R8 after load-use
`endif
    end
  end
endmodule
