# tools/gls — fast gate-level verification (planned: Y3–Y4)

Goal: make post-synthesis / post-layout **gate-level simulation (GLS)** of the
rabbit SoC fast enough to run a real regression, not just one smoke test.

## Why this is a real contribution

- Verilator cannot do SDF-annotated (timing) simulation; Icarus can but is slow.
- Open GPU simulators exist and are reusable: **NVIDIA GEM** (Apache-2.0,
  netlist → GPU Boolean processor, zero-delay) and **Jacquard** (formerly
  ChipFlow/Loom: builds on GEM, adds Liberty delays, SDF, setup/hold checks,
  X-propagation, SKY130 / GF180 / IHP support, CUDA/HIP/Metal).
- **No published accuracy/speed comparison on a real post-layout RISC-V
  netlist was found.** That benchmark alone is publishable.
  (Details and sources: `docs/research/2026-11-04-soc-5yr-plan.md`, A.7–A.8.)

## Staged plan

| Stage | What | Hardware needed |
|---|---|---|
| 0 | `tools/regress`: run many cocotb tests in parallel processes (pytest-xdist or our own scheduler), merge results/coverage | any multi-core PC (this one has 22 cores) |
| 1 | Synthesize the SoC with Yosys → gate-level netlist; run the *same* firmware tests on it with Icarus and Verilator (zero-delay) | CPU |
| 2 | After LibreLane P&R: SDF-annotated GLS with Icarus = reference | CPU |
| 3 | Same netlist on Jacquard/GEM; compare against stage 2 (functional equivalence, timing-violation agreement, speed) | NVIDIA GPU (CUDA) or AMD (HIP) or Apple (Metal) |
| 4 | Extend: batched stimuli (many firmware images per GPU launch), coverage collection, automatic failure triage back to RTL signals | GPU |

Note: this machine has no `nvidia-smi`, so stages 3–4 need a GPU host
(lab workstation, cluster node, or a cloud GPU).
