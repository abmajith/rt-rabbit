# Per-core build settings, included by the top-level and dv Makefiles.
CORE_MARCH       := rv32i_zicsr
CORE_MABI        := ilp32
# Our own RTL: no warning suppressions.
CORE_VERILATOR_FLAGS :=

# Timing model of this core (rabbit5_core.sv, TIMING RULES). The formal
# timing properties in dv/formal/rabbit/timing check the core against these.
TIMING_FIRST_RETIRE := 5
TIMING_REDIRECT_GAP := 3
TIMING_LOADUSE_GAP  := 2
