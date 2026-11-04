# fpga/litex — FPGA targets (planned, Y1 H1)

Two paths, both keep `rabbit_cpu` as the single CPU contract:
1. **LiteX** with `--cpu-type=cv32e40p` (supported upstream; BIOS boots in
   `litex_sim`) to get UART/DRAM/Ethernet quickly.
2. Our own `rabbit_soc` top on the board for full control of timing.
Board choice is open: an ECP5 board keeps the flow fully open (Yosys + nextpnr).
