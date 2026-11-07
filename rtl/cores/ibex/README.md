# ibex — lowRISC Ibex as a reference core

`third_party/ibex` (submodule, pinned commit), wrapped by `rabbit_cpu.sv` so
the SoC, the firmware and the scripts treat it exactly like the other cores.
Used for comparison (`../README.md`), not developed here.

Configuration: lowRISC's "small" Ibex — RV32IMC + Zicsr, 2 stages, fast
multiplier (MUL 3, MULH 4, DIV 37 cycles), flip-flop register file; no
writeback stage, branch-target ALU, icache, PMP, security features, CHERIoT;
of the Zc extensions only Zca (= C).

Deviations from the `rabbit_cpu` contract (all documented in the adapter):
- first fetch at `{boot_addr[31:8], 8'h80}`, vectored `mtvec` at
  `boot_addr[31:8]` → `boot_addr_i = MTVEC_ADDR`, BOOT_ADDR must be MTVEC_ADDR + 0x80;
- 15 fast interrupt lines (16..30), the **lowest** line wins
  (`CORE_CFLAGS := -DIRQ_FAST_LOW_LINE_FIRST`, the irq test expects it);
- no `irq_ack_o` / `irq_id_o` (tied to 0).

`files.f` was generated from Ibex's FuseSoC core files; after bumping the
submodule regenerate it as described in `tools/fusesoc_to_filelist.py`.
For synthesis, `tools/synth_sky130.sh` works around one construct in
`ibex_top.sv` that Yosys' slang frontend does not elaborate (a lint-only
signal); the vendor file is not changed.

```bash
make soc-sim CORE=ibex PROG=muldiv
tools/synth_sky130.sh ibex
```
