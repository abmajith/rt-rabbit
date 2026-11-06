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
# Worst-case cycles from "an enabled interrupt is pending" to the retirement
# of the first handler instruction (rule R6). 0 = no interrupts.
TIMING_IRQ_LATENCY  := 7
# Cycles from the commit stage (EX) to retirement (WB). The timing testbench
# uses it to line up its RVFI-based spec model with the core.
TIMING_COMMIT_TO_RETIRE := 2
