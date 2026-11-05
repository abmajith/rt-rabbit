# dv/formal — formal verification

## rabbit5 (working)

```bash
make formal                       # from the repo root: everything below (~35 s on 22 cores)
make -C dv/formal/rabbit5 riscv-formal
make -C dv/formal/rabbit5 timing
make -C dv/formal/rabbit5 check C=insn_add_ch0    # one check
```

| Part | What it proves | Files |
|---|---|---|
| **riscv-formal** (YosysHQ, submodule) | every RV32I instruction computes what the ISA says (37 checks), plus pipeline consistency: `reg` (forwarding), `pc_fwd`/`pc_bwd` (branches, flushes), `causal`, `unique`, `liveness`, `ill` | `rabbit5/checks.cfg`, `rabbit5/wrapper.sv` |
| **timing properties** (ours) | T1 exact retirement-gap model, T2 first retirement at cycle 5, T3 memory used exactly one cycle before retirement; covers prove every case and the 6..16 throughput bounds are reachable | `rabbit5/timing/` |

How it fits together:
1. rabbit5 is written in modern SystemVerilog. riscv-formal reads cores with
   Yosys' built-in parser, so the Makefile first converts the core with the
   **slang** frontend into one plain Verilog file (`build/rabbit5_flat.v`).
2. `genchecks.py` expects `<riscv-formal>/cores/<core>/`; the Makefile builds a
   small mirror in `build/` (symlinks to the submodule), so the submodule is
   never modified.
3. The timing proof reads the SystemVerilog directly through slang (≈10 s;
   the converted file made the solver ~60x slower).

Bounded proofs: all results hold for every instruction stream up to the
configured depth (12–20 cycles for riscv-formal, 24 for timing), not for
unbounded time.

Mutation results (to show the checks are not vacuous):
- forwarding priority MEM/WB swapped → only `reg_ch0` fails;
- stall on every EX dependency (not just loads) → timing T1 fails, riscv-formal passes.

## Planned

- CSR checks (`csrw`, `csrc_*`) when interrupts land (M2).
- SymbiYosys properties for the OBI bus and the SoC address decode.
- Dual core (M4): TDM arbiter bound (n+1 cycles) and per-core timing independence.
