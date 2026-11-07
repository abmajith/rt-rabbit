# cve2 — OpenHW CVE2 (CV32E20) as a reference core

`third_party/cve2` (submodule, pinned commit), wrapped by `rabbit_cpu.sv`.
CVE2 is OpenHW's industrial-grade derivative of an early Ibex: 2 stages,
RV32IMC + Zicsr. Used for comparison (`../README.md`), not developed here.

Configuration: fast multiplier (MUL 3, MULH 4, DIV 37 cycles), no
X-interface, no extra performance counters (MHPMCounterNum = 0, as in the
Ibex adapter, so the area comparison is fair).

Deviations from the `rabbit_cpu` contract (documented in the adapter):
- first fetch AT `boot_addr`, vectored `mtvec` at `boot_addr[31:8]` →
  `boot_addr_i = BOOT_ADDR`, which must lie in MTVEC_ADDR's 256-byte block;
- fast interrupt lines 16..31: the **lowest** line wins
  (`CORE_CFLAGS := -DIRQ_FAST_LOW_LINE_FIRST`);
- no `irq_ack_o` / `irq_id_o` (tied to 0).

Bringing it up found a bug in **our** testbench: reset started low, so in
Verilator an asynchronous reset only acted at clock edges, and CVE2 gates its
own clock during reset — its privilege level stayed 0 (user mode) and the
first `csrr misa` trapped. `dv/cocotb/soc/test_soc.py` now gives reset a real
falling edge.

```bash
make soc-sim CORE=cve2 PROG=irq
tools/synth_sky130.sh cve2
```
