# Per-core build settings, included by the top-level and dv Makefiles.
CORE_MARCH       := rv32imc_zicsr
CORE_MABI        := ilp32
# Vendor code: keep warnings non-fatal.
CORE_VERILATOR_FLAGS := -Wno-fatal
# Contract deviation: among the fast interrupt lines 16..31 the LOWEST line
# wins (CV32E40P and the rabbit cores: the highest). sw/baremetal/irq expects it.
CORE_CFLAGS      := -DIRQ_FAST_LOW_LINE_FIRST
