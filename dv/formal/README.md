# dv/formal — formal verification (planned)

- SymbiYosys properties for our own RTL first: OBI protocol (req held until
  gnt, exactly one rvalid per granted request), address decode, sim-control.
- Coprocessor-port handshake properties when the VPU lands (Y2).
- **riscv-formal** for rabbit5 (Y1 H2), via its RVFI port.
- Long term: bounded proofs of worst-case interrupt latency (see
  `docs/research/2026-11-04-soc-5yr-plan.md` §6).
