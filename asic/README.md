# asic — open silicon

- `orfs/`: place and route of every core with OpenROAD (real timing, area,
  power on sky130 / IHP SG13G2). See `orfs/README.md`.

- Y1 H2: first Tiny Tapeout tile on IHP 130 nm (a peripheral or small core) to
  learn LibreLane end to end.
- Y4: full MCU SoC on an IHP or sky130 (ChipFoundry) shuttle.
- Keep RTL PDK-portable (no vendor macros in core logic; SRAMs behind a wrapper).
Shuttle landscape as of 2026 (Efabless closed; Tiny Tapeout on IHP; sky130 via ChipFoundry): see the research notes kept outside the repo.
