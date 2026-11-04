# dv/isa — ISA compliance and lockstep (planned, Y1 H1)

1. **RISCOF + riscv-arch-test** on CV32E40P (RV32IMC, Zicsr): a RISCOF plugin
   that builds each test with `sw/baremetal` conventions and runs it on
   `rabbit_soc_sim`; signature region dumped through `rabbit_sim_ctrl`.
   Reference model: Sail (preferred) or Spike.
2. **Lockstep**: add an optional RVFI trace port to the `rabbit_cpu` contract
   (CV32E40P has `bhv/cv32e40p_rvfi.sv`); compare every retired instruction
   against Spike. Same harness later checks rabbit5.
3. **Random instruction streams**: riscv-dv, or a small Python generator.
