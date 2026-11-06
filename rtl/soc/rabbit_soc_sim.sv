// Minimal simulation SoC: rabbit_cpu + 64 KiB RAM + sim control block + timer.
// Core-agnostic: whichever rtl/cores/<CORE>/rabbit_cpu.sv is compiled is used.
//
// Memory map
//   0x0000_0000 - 0x0000_FFFF  RAM (vectors at 0x0, reset at 0x80)
//   0x1000_0000 - 0x1000_00FF  rabbit_sim_ctrl (PUTC / EXIT / CYCLE / IRQ)
//   0x2000_0000 - 0x2000_000F  rabbit_timer    (mtime / mtimecmp)
//
// Interrupt lines into the core:  irq_i (testbench) | sim_ctrl IRQ register
//                                  | timer on line 7 (MTI)
//
// Next steps (Y1 H1): add a Wishbone bridge and attach hw_ip/ (PWM, QEI,
// telemetry) and a UART.
module rabbit_soc_sim #(
    parameter int    RAM_WORDS = 16384,
    parameter string INIT_FILE = ""
) (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic [31:0] irq_i,          // driven by the testbench for IRQ tests

    output logic        putc_valid_o,
    output logic [ 7:0] putc_char_o,
    output logic        exit_valid_o,
    output logic [31:0] exit_code_o
);
  // ---- core <-> fabric -----------------------------------------------------
  logic        instr_req, instr_gnt, instr_rvalid;
  logic [31:0] instr_addr, instr_rdata;
  logic        data_req, data_gnt, data_rvalid, data_we;
  logic [ 3:0] data_be;
  logic [31:0] data_addr, data_wdata, data_rdata;
  logic [31:0] sim_irq, core_irq;   // interrupt lines (see "interrupts" below)
  logic        timer_irq;

  // A gate-level netlist has its parameters baked in at synthesis time
  // (the rabbit_cpu defaults: BOOT_ADDR = 0x80, MTVEC_ADDR = 0x0), so it
  // cannot be re-parameterised here.
`ifdef RABBIT_GLS
  rabbit_cpu u_cpu (
`else
  rabbit_cpu #(
      .BOOT_ADDR (32'h0000_0080),
      .MTVEC_ADDR(32'h0000_0000)
  ) u_cpu (
`endif
      .clk_i, .rst_ni,
      .fetch_enable_i(1'b1),
      .instr_req_o(instr_req), .instr_gnt_i(instr_gnt), .instr_rvalid_i(instr_rvalid),
      .instr_addr_o(instr_addr), .instr_rdata_i(instr_rdata),
      .data_req_o(data_req), .data_gnt_i(data_gnt), .data_rvalid_i(data_rvalid),
      .data_we_o(data_we), .data_be_o(data_be), .data_addr_o(data_addr),
      .data_wdata_o(data_wdata), .data_rdata_i(data_rdata),
      .irq_i(core_irq), .irq_ack_o(), .irq_id_o(),
      .debug_req_i(1'b0),
      .core_sleep_o()
  );

  // ---- data-side address decode -------------------------------------------
  wire sel_ram = (data_addr[31:28] == 4'h0);
  wire sel_sim = (data_addr[31:28] == 4'h1);
  wire sel_tmr = (data_addr[31:28] == 4'h2);

  logic        ram_gnt, ram_rvalid, sim_gnt, sim_rvalid, tmr_gnt, tmr_rvalid;
  logic [31:0] ram_rdata, sim_rdata, tmr_rdata;
  logic        err_rvalid;   // access to unmapped address: complete with 0

  assign data_gnt    = data_req;  // all slaves grant immediately
  assign data_rvalid = ram_rvalid | sim_rvalid | tmr_rvalid | err_rvalid;
  assign data_rdata  = ram_rvalid ? ram_rdata :
                       sim_rvalid ? sim_rdata :
                       tmr_rvalid ? tmr_rdata : 32'h0;

  always_ff @(posedge clk_i or negedge rst_ni)
    if (!rst_ni) err_rvalid <= 1'b0;
    else         err_rvalid <= data_req && !sel_ram && !sel_sim && !sel_tmr;

  // ---- interrupts ----------------------------------------------------------------
  assign core_irq = irq_i | sim_irq | {24'b0, timer_irq, 7'b0};

  rabbit_obi_ram #(.WORDS(RAM_WORDS), .INIT_FILE(INIT_FILE)) u_ram (
      .clk_i, .rst_ni,
      .a_req_i(instr_req), .a_gnt_o(instr_gnt), .a_rvalid_o(instr_rvalid),
      .a_addr_i(instr_addr), .a_rdata_o(instr_rdata),
      .b_req_i(data_req && sel_ram), .b_gnt_o(ram_gnt), .b_rvalid_o(ram_rvalid),
      .b_we_i(data_we), .b_be_i(data_be), .b_addr_i(data_addr),
      .b_wdata_i(data_wdata), .b_rdata_o(ram_rdata)
  );

  rabbit_sim_ctrl u_sim (
      .clk_i, .rst_ni,
      .req_i(data_req && sel_sim), .gnt_o(sim_gnt), .rvalid_o(sim_rvalid),
      .we_i(data_we), .addr_i(data_addr), .wdata_i(data_wdata), .rdata_o(sim_rdata),
      .putc_valid_o, .putc_char_o, .exit_valid_o, .exit_code_o,
      .irq_o(sim_irq)
  );

  rabbit_timer u_timer (
      .clk_i, .rst_ni,
      .req_i(data_req && sel_tmr), .gnt_o(tmr_gnt), .rvalid_o(tmr_rvalid),
      .we_i(data_we), .be_i(data_be), .addr_i(data_addr), .wdata_i(data_wdata),
      .rdata_o(tmr_rdata), .irq_o(timer_irq)
  );

  // Unused grant outputs (kept for future interconnect with back-pressure).
  logic unused;
  assign unused = ram_gnt ^ sim_gnt ^ tmr_gnt;
endmodule
