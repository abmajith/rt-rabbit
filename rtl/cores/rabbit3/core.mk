# Per-core build settings, included by mk/config.mk after the configuration
# (configs/<CONFIG>.mk): CONFIG_ISA and the options are already known here.
CORE_MARCH       := $(CONFIG_ISA)_zicsr
CORE_MABI        := ilp32
# Our own RTL: no warning suppressions.
CORE_VERILATOR_FLAGS :=

# Timing model of this core (rabbit3_core.sv, TIMING RULES). The formal
# timing properties in dv/formal/rabbit/timing check the core against these.
TIMING_FIRST_RETIRE := 3
TIMING_REDIRECT_GAP := 2
TIMING_LOADUSE_GAP  := 1
# Worst-case cycles from "an enabled interrupt is pending" to the retirement
# of the first handler instruction (rule R6). 0 = no interrupts.
TIMING_IRQ_LATENCY  := 4
# Cycles from the commit stage (X) to retirement (W). The timing testbench
# uses it to line up its RVFI-based spec model with the core.
TIMING_COMMIT_TO_RETIRE := 1
# M extension (rule R8, only with RV32M = 1): cycles an instruction spends in X, for any
# operands. FORMAL_DIV_STEPS is the divider's step count used by the
# pipeline-level proofs (a 34-cycle divide does not fit in their depth); the
# real 32 steps are proven in dv/formal/rabbit/muldiv (L1).
TIMING_MUL_CYCLES   := 2
TIMING_DIV_CYCLES   := 34
FORMAL_DIV_STEPS    := 2
# riscv-formal liveness: the check cycle (window = depth - 8). An interrupted
# divide plus a handler that starts with a divide needs a long window;
# measured: 16 fails (a real longer gap), 18 passes.
# Without M the window of the original RV32I proof (15) is enough.
FORMAL_LIVENESS_DEPTH := $(if $(filter 1,$(RV32M)),20,15)
