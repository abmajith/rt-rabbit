# Formal verification of a rabbit core:  make CORE=rabbit3   (default rabbit5)
#   make                 riscv-formal checks + timing properties + muldiv
#   make riscv-formal    only riscv-formal (parallel)
#   make timing          only the timing properties (timing/rabbit_timing_tb.sv)
#   make muldiv          only the multiply/divide unit proof (muldiv/, any core)
#   make muldiv-sim      ... its exhaustive 8-bit simulation part
#   make check C=insn_add_ch0   one riscv-formal check
REPO   ?= $(abspath ../../..)
CORE   ?= rabbit5
JOBS   ?= $(shell nproc)
RF_SRC := $(REPO)/third_party/riscv-formal

include $(REPO)/rtl/cores/$(CORE)/core.mk

# all SystemVerilog sources of the core except the rabbit_cpu adapter
SOURCES := $(shell grep -v '^//' $(REPO)/rtl/cores/$(CORE)/files.f | grep -v rabbit_cpu.sv | sed 's|$${REPO}|$(REPO)|')

BUILD    := build/$(CORE)
FLAT     := $(BUILD)/core_flat.v
# genchecks.py expects <riscv-formal>/cores/<core>/, so build a small mirror
MIRROR   := $(BUILD)/riscv-formal
CORE_DIR := $(MIRROR)/cores/$(CORE)

# slang is built into some Yosys builds and a plugin in others (OSS CAD Suite)
YOSYS_SLANG := $(shell yosys -p 'help read_slang' >/dev/null 2>&1 || echo -m slang)

all: riscv-formal timing muldiv

# ---- riscv-formal --------------------------------------------------------------
riscv-formal: generate
	$(MAKE) -C $(CORE_DIR)/checks -j$(JOBS) -k
	@python3 summary.py $(CORE_DIR)/checks

generate: $(CORE_DIR)/checks/makefile

# The cores are modern SystemVerilog; riscv-formal reads files with Yosys'
# built-in parser, so convert once with the slang frontend.
# M extension: riscv-formal checks MUL/DIV with stand-in results (ALTOPS) and
# a short divider (FORMAL_DIV_STEPS); the real arithmetic is the muldiv proof.
FORMAL_DEFINES := -DSYNTHESIS -DRISCV_FORMAL_ALTOPS -DRABBIT_DIV_STEPS=$(FORMAL_DIV_STEPS)
$(FLAT): $(SOURCES) $(REPO)/rtl/cores/$(CORE)/core.mk
	@mkdir -p $(BUILD)
	yosys $(YOSYS_SLANG) -q -p "read_slang $(SOURCES) --top $(CORE)_core $(FORMAL_DEFINES); \
	             hierarchy -top $(CORE)_core; proc; flatten; opt_clean; \
	             write_verilog -noattr $@"

$(CORE_DIR)/checks/makefile: $(FLAT) checks.cfg wrapper.sv $(REPO)/rtl/cores/$(CORE)/core.mk
	@mkdir -p $(MIRROR) $(CORE_DIR)
	ln -sfn $(RF_SRC)/checks $(MIRROR)/checks
	ln -sfn $(RF_SRC)/insns  $(MIRROR)/insns
	cp $(FLAT) wrapper.sv $(CORE_DIR)/
	sed -e 's/@RABBIT_CORE@/$(CORE)_core/' \
	    -e 's/@LIVENESS_DEPTH@/$(FORMAL_LIVENESS_DEPTH)/' \
	    -e 's/@RABBIT_IRQ_DEFINE@/$(if $(filter-out 0,$(TIMING_IRQ_LATENCY)),`define RABBIT_HAS_IRQ)/' \
	    checks.cfg > $(CORE_DIR)/checks.cfg
	rm -rf $(CORE_DIR)/checks
	cd $(CORE_DIR) && python3 ../../checks/genchecks.py

check: generate
	$(MAKE) -C $(CORE_DIR)/checks $(C)
	@cat $(CORE_DIR)/checks/$(C)/status

# ---- timing properties ------------------------------------------------------------
# Reads the SystemVerilog through slang directly (much faster to solve than
# the converted file). The core's timing model comes from its core.mk.
TIMING_DEFINES := -DSYNTHESIS -DRISCV_FORMAL_ALTOPS -DRABBIT_CORE=$(CORE)_core \
                  -DFIRST_RETIRE=$(TIMING_FIRST_RETIRE) \
                  -DREDIRECT_GAP=$(TIMING_REDIRECT_GAP) \
                  -DLOADUSE_GAP=$(TIMING_LOADUSE_GAP) \
                  -DIRQ_LATENCY=$(TIMING_IRQ_LATENCY) \
                  -DCOMMIT_TO_RETIRE=$(TIMING_COMMIT_TO_RETIRE) \
                  -DMUL_CYCLES=$(TIMING_MUL_CYCLES) \
                  -DRABBIT_DIV_STEPS=$(FORMAL_DIV_STEPS)

timing: $(BUILD)/timing.sby
	cd $(BUILD) && sby -f timing.sby

$(BUILD)/timing.sby: timing/timing.sby.in timing/rabbit_timing_tb.sv $(SOURCES) $(REPO)/rtl/cores/$(CORE)/core.mk
	@mkdir -p $(BUILD)
	@if [ -n "$(YOSYS_SLANG)" ]; then echo "plugin -i slang" > $(BUILD)/slang_load.ys; \
	 else echo "# slang is built in" > $(BUILD)/slang_load.ys; fi
	sed -e 's|@SOURCES@|$(notdir $(SOURCES)) rabbit_timing_tb.sv|' \
	    -e 's|@DEFINES@|$(TIMING_DEFINES)|' timing/timing.sby.in > $@
	printf '%s\n' $(SOURCES) $(abspath timing/rabbit_timing_tb.sv) $(abspath $(BUILD))/slang_load.ys >> $@

# ---- multiply/divide unit (shared by every rabbit core) -------------------------------
# muldiv:     formal (muldiv/muldiv.sby): values for every input at W = 4 / 6,
#             exact latency at W = 32
# muldiv-sim: every input at W = 8 in Verilator (muldiv/exhaustive_tb.sv)
MULDIV_RTL := $(REPO)/rtl/cores/rabbit_common/rabbit_muldiv.sv
muldiv: muldiv-sim
	cd muldiv && sby -f muldiv.sby

muldiv-sim:
	@mkdir -p build/muldiv
	verilator --binary --timing -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-PROCASSINIT \
	  --top-module exhaustive_tb -Mdir build/muldiv -o exhaustive \
	  $(MULDIV_RTL) muldiv/exhaustive_tb.sv > build/muldiv/build.log
	build/muldiv/exhaustive | tee build/muldiv/run.log | grep -E 'FAIL|exhaustive|RESULT'
	@grep -q 'RESULT: PASS' build/muldiv/run.log

clean:
	rm -rf build muldiv/muldiv_*/ muldiv/muldiv/

.PHONY: all riscv-formal generate check timing muldiv muldiv-sim clean
