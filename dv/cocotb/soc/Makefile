# cocotb + Verilator: run a firmware image on rabbit_soc_sim with the selected core.
#   uv run make                      # core=cv32e40p, prog=hello
#   uv run make PROG=hello WAVES=1   # also dump dump.fst for GTKWave/Surfer
REPO ?= $(abspath ../../..)
export REPO
CORE ?= cv32e40p
PROG ?= hello

include $(REPO)/rtl/cores/$(CORE)/core.mk

FIRMWARE := $(REPO)/sw/baremetal/build/$(CORE)/$(PROG)/$(PROG).hex
export RABBIT_FIRMWARE := $(FIRMWARE)
export RABBIT_PROG := $(PROG)

SIM            ?= verilator
TOPLEVEL_LANG   = verilog
TOPLEVEL        = rabbit_soc_sim
COCOTB_TEST_MODULES = test_soc
SIM_BUILD      ?= sim_build_$(CORE)

# Sources come from the per-core and SoC file lists (${REPO} is expanded by Verilator).
# GLS=1 replaces the core RTL by its gate-level netlist (see `make gls-netlist`).
VERILOG_SOURCES =
ifeq ($(GLS),1)
NETLIST    := $(REPO)/build/gls/$(CORE)/rabbit_cpu_netlist.v
EXTRA_ARGS += $(NETLIST) -Wno-fatal -DRABBIT_GLS
SIM_BUILD   = sim_build_$(CORE)_gls
else
EXTRA_ARGS += -f $(REPO)/rtl/cores/$(CORE)/files.f $(CORE_VERILATOR_FLAGS)
endif
EXTRA_ARGS += -f $(REPO)/rtl/soc/files.f -DRABBIT_QUIET
ifeq ($(WAVES),1)
# Build with tracing, switch it on at run time, and keep a separate build dir
# (a traced model is slower, so the normal build stays trace-free).
EXTRA_ARGS += --trace-fst --trace-structs
SIM_ARGS   += --trace
SIM_BUILD   = sim_build_$(CORE)_waves
endif
PLUSARGS   += +firmware=$(FIRMWARE)

# The sources are passed with -f, which cocotb cannot see: list them as
# dependencies so that editing any RTL file rebuilds the simulator.
expand_f = $(shell grep -v '^//' $(1) | sed 's|$${REPO}|$(REPO)|')
CUSTOM_COMPILE_DEPS += $(call expand_f,$(REPO)/rtl/soc/files.f)
ifeq ($(GLS),1)
CUSTOM_COMPILE_DEPS += $(NETLIST)
else
CUSTOM_COMPILE_DEPS += $(filter %.sv %.v,$(call expand_f,$(REPO)/rtl/cores/$(CORE)/files.f))
endif

COCOTB_HDL_TIMEUNIT      = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

include $(shell cocotb-config --makefiles)/Makefile.sim

# Always rebuild the firmware before simulating.
sim: firmware
firmware:
	$(MAKE) -C $(REPO)/sw/baremetal PROG=$(PROG) CORE=$(CORE)
.PHONY: firmware
