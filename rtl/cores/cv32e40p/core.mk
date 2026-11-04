# Per-core build settings, included by the top-level and dv Makefiles.
CORE_MARCH       := rv32imc_zicsr
CORE_MABI        := ilp32
# CV32E40P is lint-clean except for a few style warnings in vendor code.
CORE_VERILATOR_FLAGS := -Wno-fatal
