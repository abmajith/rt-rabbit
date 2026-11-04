# sw/zephyr — Zephyr port (planned, Y1 H1)

Needs from the SoC first: machine timer (mtime/mtimecmp), UART, interrupts.
Then: an out-of-tree SoC + board definition (`soc/rabbit`, `boards/rabbit_sim`),
built with `west`, run on `rabbit_soc_sim` under Verilator and later on FPGA.
Measurements: Zephyr's zyclictest + the existing `rt_rabbit/zephyr-fw`, compared
with `rma_analysis` predictions.
