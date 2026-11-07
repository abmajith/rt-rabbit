# asic/orfs — place and route with OpenROAD (real timing, area, power)

`tools/synth_sky130.sh` gives quick numbers from Yosys + ABC, without wires.
This flow runs the whole physical design with OpenROAD-flow-scripts (ORFS):
synthesis, floorplan, placement, clock tree, routing, then OpenSTA on the
routed design with extracted wire parasitics.

```bash
asic/orfs/run.sh rabbit5                 # sky130hd, 8 ns target, ~11 min
asic/orfs/run.sh ibex ihp-sg13g2 8       # other PDK / period
```

Needs Docker; the image `openroad/orfs` is pinned by digest in `run.sh` (about
6.5 GB, pulled on first use). Nothing is installed on the machine. Results:
`build/orfs/<platform>/<core>/` — reports, logs, the layout (`6_final.gds`)
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
  that timing repair. Area and power at a relaxed period are the next run.
- Power printed by `summary.py` is *vectorless* (default switching activity),
  a placeholder until activity from a gate-level simulation is used.
