# cocotb + Verilator: run a firmware image on rabbit_soc_sim with the selected core.
#   uv run make                      # core=cv32e40p, prog=hello
#   uv run make PROG=hello WAVES=1   # also dump dump.fst for GTKWave/Surfer
REPO ?= $(abspath ../../..)
export REPO
CORE ?= cv32e40p
PROG ?= hello

include $(REPO)/rtl/cores/$(CORE)/core.mk

FIRMWARE := $(REPO)/sw/baremetal/build/$(PROG)/$(PROG).hex
export RABBIT_FIRMWARE := $(FIRMWARE)
export RABBIT_PROG := $(PROG)

SIM            ?= verilator
TOPLEVEL_LANG   = verilog
TOPLEVEL        = rabbit_soc_sim
COCOTB_TEST_MODULES = test_soc
SIM_BUILD      ?= sim_build_$(CORE)

# Sources come from the per-core and SoC file lists (${REPO} is expanded by Verilator).
VERILOG_SOURCES =
EXTRA_ARGS += -f $(REPO)/rtl/cores/$(CORE)/files.f -f $(REPO)/rtl/soc/files.f
EXTRA_ARGS += $(CORE_VERILATOR_FLAGS) -DRABBIT_QUIET
ifeq ($(WAVES),1)
# Build with tracing, switch it on at run time, and keep a separate build dir
# (a traced model is slower, so the normal build stays trace-free).
EXTRA_ARGS += --trace-fst --trace-structs
SIM_ARGS   += --trace
SIM_BUILD   = sim_build_$(CORE)_waves
endif
PLUSARGS   += +firmware=$(FIRMWARE)

COCOTB_HDL_TIMEUNIT      = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

include $(shell cocotb-config --makefiles)/Makefile.sim

# Always rebuild the firmware before simulating.
sim: firmware
firmware:
	$(MAKE) -C $(REPO)/sw/baremetal PROG=$(PROG) CORE=$(CORE)
.PHONY: firmware
