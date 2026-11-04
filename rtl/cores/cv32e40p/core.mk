# Per-core build settings, included by the top-level and dv Makefiles.
CORE_MARCH       := rv32imc_zicsr
CORE_MABI        := ilp32
# Vendor code: keep warnings non-fatal. COMBDLY: bhv/cv32e40p_sim_clock_gate.sv
# uses '<=' in a latch-style always_latch; Verilator >= 5.055 makes this an error.
CORE_VERILATOR_FLAGS := -Wno-fatal -Wno-COMBDLY
