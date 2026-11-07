# cocotb + Verilator: run a firmware image on rabbit_soc_sim, one SoC configuration.
#   uv run make                              # CONFIG=cv32e40p, PROG=hello
#   uv run make CONFIG=rabbit5_rv32i PROG=muldiv
#   uv run make PROG=hello WAVES=1           # also dump dump.fst for GTKWave/Surfer
REPO ?= $(abspath ../../..)
export REPO
PROG ?= hello

include $(REPO)/mk/config.mk

FIRMWARE := $(REPO)/sw/baremetal/build/$(CONFIG)/$(PROG)/$(PROG).hex
export RABBIT_FIRMWARE := $(FIRMWARE)
export RABBIT_PROG := $(PROG)

SIM            ?= verilator
TOPLEVEL_LANG   = verilog
TOPLEVEL        = rabbit_soc_sim
COCOTB_TEST_MODULES = test_soc
SIM_BUILD      ?= sim_build_$(CONFIG)

# Sources come from the per-core and SoC file lists (${REPO} is expanded by Verilator).
# GLS=1 replaces the core RTL by its gate-level netlist (see `make gls-netlist`).
VERILOG_SOURCES =
ifeq ($(GLS),1)
NETLIST    ?= $(REPO)/build/gls/$(CONFIG)/rabbit_cpu_netlist.v
EXTRA_ARGS += $(NETLIST) -Wno-fatal -DRABBIT_GLS
SIM_BUILD   = sim_build_$(CONFIG)_gls
else
EXTRA_ARGS += -f $(REPO)/rtl/cores/$(CORE)/files.f $(CORE_VERILATOR_FLAGS) $(CONFIG_DEFINES)
endif
EXTRA_ARGS += -f $(REPO)/rtl/soc/files.f -DRABBIT_QUIET
ifeq ($(WAVES),1)
# Build with tracing, switch it on at run time, and keep a separate build dir
# (a traced model is slower, so the normal build stays trace-free).
EXTRA_ARGS += --trace-fst --trace-structs
SIM_ARGS   += --trace
SIM_BUILD   = sim_build_$(CONFIG)_waves
endif
# extra Verilator options, e.g. --trace-underscore for the energy flow (asic/orfs/energy.sh)
EXTRA_ARGS += $(VERILATOR_EXTRA)
PLUSARGS   += +firmware=$(FIRMWARE)

# The sources are passed with -f, which cocotb cannot see: list them as
# dependencies so that editing any RTL file rebuilds the simulator.
expand_f = $(shell grep -v '^//' $(1) | sed 's|$${REPO}|$(REPO)|')
CUSTOM_COMPILE_DEPS += $(call expand_f,$(REPO)/rtl/soc/files.f)
ifeq ($(GLS),1)
CUSTOM_COMPILE_DEPS += $(NETLIST)
else
CUSTOM_COMPILE_DEPS += $(filter %.sv %.v,$(call expand_f,$(REPO)/rtl/cores/$(CORE)/files.f)) $(CONFIG_DEPS)
endif

COCOTB_HDL_TIMEUNIT      = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

include $(shell cocotb-config --makefiles)/Makefile.sim

# Always rebuild the firmware before simulating.
sim: firmware
firmware:
	$(MAKE) -C $(REPO)/sw/baremetal PROG=$(PROG) CONFIG=$(CONFIG)
.PHONY: firmware
