# Per-core build settings, included by mk/config.mk after the configuration.
# Reference core in a fixed configuration: only the default options.
ifneq ($(RV32M),1)
$(error $(CORE) is a reference core in a fixed configuration (RV32IMC); RV32M cannot be 0)
endif
CONFIG_ISA       := rv32imc
CORE_MARCH       := rv32imc_zicsr
CORE_MABI        := ilp32
# Vendor code: keep warnings non-fatal. COMBDLY: bhv/cv32e40p_sim_clock_gate.sv
# uses '<=' in a latch-style always_latch; Verilator >= 5.055 makes this an error.
CORE_VERILATOR_FLAGS := -Wno-fatal -Wno-COMBDLY
