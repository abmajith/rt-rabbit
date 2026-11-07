# Per-core build settings, included by mk/config.mk after the configuration.
# Reference core in a fixed configuration: only the default options.
ifneq ($(RV32M),1)
$(error $(CORE) is a reference core in a fixed configuration (RV32IMC); RV32M cannot be 0)
endif
CONFIG_ISA       := rv32imc
CORE_MARCH       := rv32imc_zicsr
CORE_MABI        := ilp32
# Vendor code: keep warnings non-fatal; Ibex' own Verilator waivers are not used.
CORE_VERILATOR_FLAGS := -Wno-fatal
# Contract deviation: among the fast interrupt lines the LOWEST line wins
# (CV32E40P and the rabbit cores: the highest). Ibex has 15 fast lines
# (16..30); line 31 does not exist.
CORE_CFLAGS      := -DIRQ_FAST_LOW_LINE_FIRST
