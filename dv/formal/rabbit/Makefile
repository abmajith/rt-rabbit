# Formal verification of a rabbit core:  make CORE=rabbit3   (default rabbit5)
#   make                 riscv-formal checks + timing properties
#   make riscv-formal    only riscv-formal (parallel)
#   make timing          only the timing properties (timing/rabbit_timing_tb.sv)
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

all: riscv-formal timing

# ---- riscv-formal --------------------------------------------------------------
riscv-formal: generate
	$(MAKE) -C $(CORE_DIR)/checks -j$(JOBS) -k
	@python3 summary.py $(CORE_DIR)/checks

generate: $(CORE_DIR)/checks/makefile

# The cores are modern SystemVerilog; riscv-formal reads files with Yosys'
# built-in parser, so convert once with the slang frontend.
$(FLAT): $(SOURCES)
	@mkdir -p $(BUILD)
	yosys $(YOSYS_SLANG) -q -p "read_slang $(SOURCES) --top $(CORE)_core -DSYNTHESIS; \
	             hierarchy -top $(CORE)_core; proc; flatten; opt_clean; \
	             write_verilog -noattr $@"

$(CORE_DIR)/checks/makefile: $(FLAT) checks.cfg wrapper.sv
	@mkdir -p $(MIRROR) $(CORE_DIR)
	ln -sfn $(RF_SRC)/checks $(MIRROR)/checks
	ln -sfn $(RF_SRC)/insns  $(MIRROR)/insns
	cp $(FLAT) wrapper.sv $(CORE_DIR)/
	sed -e 's/@RABBIT_CORE@/$(CORE)_core/' checks.cfg > $(CORE_DIR)/checks.cfg
	rm -rf $(CORE_DIR)/checks
	cd $(CORE_DIR) && python3 ../../checks/genchecks.py

check: generate
	$(MAKE) -C $(CORE_DIR)/checks $(C)
	@cat $(CORE_DIR)/checks/$(C)/status

# ---- timing properties ------------------------------------------------------------
# Reads the SystemVerilog through slang directly (much faster to solve than
# the converted file). The core's timing model comes from its core.mk.
TIMING_DEFINES := -DSYNTHESIS -DRABBIT_CORE=$(CORE)_core \
                  -DFIRST_RETIRE=$(TIMING_FIRST_RETIRE) \
                  -DREDIRECT_GAP=$(TIMING_REDIRECT_GAP) \
                  -DLOADUSE_GAP=$(TIMING_LOADUSE_GAP)

timing: $(BUILD)/timing.sby
	cd $(BUILD) && sby -f timing.sby

$(BUILD)/timing.sby: timing/timing.sby.in timing/rabbit_timing_tb.sv $(SOURCES)
	@mkdir -p $(BUILD)
	@if [ -n "$(YOSYS_SLANG)" ]; then echo "plugin -i slang" > $(BUILD)/slang_load.ys; \
	 else echo "# slang is built in" > $(BUILD)/slang_load.ys; fi
	sed -e 's|@SOURCES@|$(notdir $(SOURCES)) rabbit_timing_tb.sv|' \
	    -e 's|@DEFINES@|$(TIMING_DEFINES)|' timing/timing.sby.in > $@
	printf '%s\n' $(SOURCES) $(abspath timing/rabbit_timing_tb.sv) $(abspath $(BUILD))/slang_load.ys >> $@

clean:
	rm -rf build

.PHONY: all riscv-formal generate check timing clean
