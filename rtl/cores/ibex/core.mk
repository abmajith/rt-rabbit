# Per-core build settings, included by the top-level and dv Makefiles.
CORE_MARCH       := rv32imc_zicsr
CORE_MABI        := ilp32
# Vendor code: keep warnings non-fatal; Ibex' own Verilator waivers are not used.
CORE_VERILATOR_FLAGS := -Wno-fatal
# Contract deviation: among the fast interrupt lines the LOWEST line wins
# (CV32E40P and the rabbit cores: the highest). Ibex has 15 fast lines
# (16..30); line 31 does not exist.
CORE_CFLAGS      := -DIRQ_FAST_LOW_LINE_FIRST
