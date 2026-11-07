# asic/orfs — place and route with OpenROAD (real timing, area, power)

`tools/synth_sky130.sh` gives quick numbers from Yosys + ABC, without wires.
This flow runs the whole physical design with OpenROAD-flow-scripts (ORFS):
synthesis, floorplan, placement, clock tree, routing, then OpenSTA on the
routed design with extracted wire parasitics.

```bash
asic/orfs/run.sh rabbit5                 # sky130hd, 8 ns target, ~11 min
asic/orfs/run.sh ibex ihp-sg13g2 8       # other PDK / period
asic/orfs/energy.sh rabbit5 hello        # energy of a program on the routed core, ~15 min
```

Needs Docker; the image `openroad/orfs` is pinned by digest in `run.sh` (about
6.5 GB, pulled on first use). Nothing is installed on the machine. Results:
`build/orfs/<platform>/<core>_<period>ns/` — reports, logs, the layout (`6_final.gds`)
and pictures (`reports/.../final_*.webp`, incl. the worst path).

How it works:
1. our Yosys + slang converts the core (`rtl/cores/<core>/files.f`, with the
   workarounds in `tools/core_sources.sh`) into one plain Verilog file, so
   every core gets the same front end;
2. ORFS runs with `config.mk` written by `run.sh` and `constraint.sdc` (same
   for every core: memory gets 20 % of the period on each side);
3. `summary.py` asks OpenSTA for the worst slack per path class and turns it
   into a minimum period: register→register gets the full period T,
   input→register and register→output 0.8 T, input→output 0.6 T.

## Results (sky130hd typical corner, 8 ns target, 2026-11-07)

| Core | Fmax | limited by | area µm² | `hello` cycles | `hello` time |
|---|---|---|---|---|---|
| rabbit3 | 97.8 MHz | input → output (memory → decode → ALU → address) | 157 660 | 2758 | 28.2 µs |
| rabbit5 | 109.0 MHz | input → register | 162 144 | 3473 | 31.9 µs |
| CV32E40P | 106.0 MHz | register → output | 227 311 | 3447 | 32.5 µs |
| Ibex (small) | 101.9 MHz | register → output | 163 428 | 3984 | 39.1 µs |
| CVE2 | 100.5 MHz | register → output | 169 224 | 3984 | 39.7 µs |

- With wires every core lands near 100 MHz. ABC alone (`tools/synth_sky130.sh`)
  had put Ibex/CVE2/CV32E40P ~1.5x ahead: it ignores wires and the I/O paths.
- rabbit3's worst register path runs through the multiplier (register file
  read → 33x17 multiplier → partial-product register, 9.4 ns); its overall
  limit is the memory-to-memory path that defines a 3-stage core.
- All cores miss 8 ns, so the tool upsizes and buffers: the areas include
  that timing repair.

Relaxed target (12 ns): the tool repairs only what it must, so this run gives
area without aggressive timing repair (its Fmax numbers mean nothing):

| Core | area µm² | power, vectorless (placeholder) |
|---|---|---|
| rabbit3 | 143 561 | 15.5 mW |
| Ibex (small) | 144 368 | 18.5 mW |
| CVE2 | 149 313 | 19.7 mW |
| rabbit5 | 149 933 | 17.3 mW |
| CV32E40P | 201 990 | 17.0 mW |
- Power printed by `summary.py` is *vectorless* (default switching activity),
  a placeholder; the real numbers come from `energy.sh` below.

## Energy (real switching activity, `energy.sh`)

`energy.sh` rebuilds every sky130 cell of the routed netlist from its logic
function in the cell library (Yosys `read_liberty`), runs the program on it in
the normal SoC testbench (it must still PASS: a post-layout functional check),
records every wire, and lets OpenSTA compute power from that activity with
the layout's wire capacitances. All pins get their activity from the
simulation (only antenna diodes, which have no logic, do not).

`hello`, sky130hd typical corner, 100 MHz, routed at 8 ns (2026-11-07):

| Core | cycles | power | energy | per cycle | registers / logic / clock tree |
|---|---|---|---|---|---|
| rabbit3 | 2758 | 22.5 mW | **621 nJ** | 225 pJ | 7.4 / 8.0 / 7.1 mW |
| rabbit5 | 3473 | 23.7 mW | 823 nJ | 237 pJ | 8.9 / 6.2 / 8.6 mW |
| Ibex (small) | 3984 | 22.1 mW | 881 nJ | 221 pJ | 8.1 / 5.5 / 8.6 mW |
| CV32E40P | 3447 | 26.7 mW | 920 nJ | 267 pJ | 9.0 / 7.3 / 10.5 mW |
| CVE2 | 3984 | 23.3 mW | 928 nJ | 233 pJ | 8.0 / 6.5 / 8.9 mW |

What it does and does not say:
- Per cycle all five cores cost about the same (221-267 pJ); rabbit3 uses the
  least energy for the program because it needs the fewest cycles.
- About two thirds of every core's power is the clock tree plus the
  flip-flops, clocked every cycle whether their value changes or not. Clock
  gating of the register file and pipeline registers is the obvious lever.
- The memories are NOT included (the SoC RAM is a simulation model). A real
  chip spends a lot on SRAM reads; cores that fetch less gain more there.
- One small program is not a benchmark; a control-loop workload is next.
