# Run riscv-formal on rabbit5.
#   make            riscv-formal checks + rabbit5 timing properties
#   make riscv-formal   only the riscv-formal checks (parallel)
#   make timing         only the timing properties
#   make generate   only (re)generate the .sby files
#   make check C=insn_add_ch0   run one check by name
REPO   ?= $(abspath ../../..)
RF_SRC := $(REPO)/third_party/riscv-formal
RTL    := $(REPO)/rtl/cores/rabbit5
BUILD  := build
# genchecks.py expects <riscv-formal>/cores/<core>/, so build a small mirror
MIRROR := $(BUILD)/riscv-formal
CORE_DIR := $(MIRROR)/cores/rabbit5
JOBS   ?= $(shell nproc)
FLAT   := $(BUILD)/rabbit5_flat.v
# slang is built into some Yosys builds and a plugin in others (OSS CAD Suite)
YOSYS_SLANG := $(shell yosys -p 'help read_slang' >/dev/null 2>&1 || echo -m slang)

SOURCES := $(addprefix $(RTL)/,rabbit5_pkg.sv rabbit5_decoder.sv rabbit5_alu.sv \
             rabbit5_regfile.sv rabbit5_csr.sv rabbit5_core.sv)

all: riscv-formal timing

riscv-formal: generate
	$(MAKE) -C $(CORE_DIR)/checks -j$(JOBS) -k
	@python3 summary.py $(CORE_DIR)/checks

# rabbit5's own timing properties (timing/rabbit5_timing_tb.sv)
timing: $(BUILD)/slang_load.ys
	cd timing && sby -f timing.sby

$(BUILD)/slang_load.ys:
	@mkdir -p $(BUILD)
	@if [ -n "$(YOSYS_SLANG)" ]; then echo "plugin -i slang" > $@; else echo "# slang is built in" > $@; fi

generate: $(CORE_DIR)/checks/makefile

# 1. rabbit5 is modern SystemVerilog; riscv-formal reads files with Yosys'
#    built-in parser, so convert once with the slang frontend.
$(FLAT): $(SOURCES)
	@mkdir -p $(BUILD)
	yosys $(YOSYS_SLANG) -q -p "read_slang $(SOURCES) --top rabbit5_core -DSYNTHESIS; \
	             hierarchy -top rabbit5_core; proc; flatten; opt_clean; \
	             write_verilog -noattr $@"

# 2. mirror + config, 3. generate one .sby per check
$(CORE_DIR)/checks/makefile: $(FLAT) checks.cfg wrapper.sv
	@mkdir -p $(MIRROR) $(CORE_DIR)
	cp $(FLAT) $(CORE_DIR)/
	ln -sfn $(RF_SRC)/checks $(MIRROR)/checks
	ln -sfn $(RF_SRC)/insns  $(MIRROR)/insns
	cp checks.cfg wrapper.sv $(CORE_DIR)/
	rm -rf $(CORE_DIR)/checks
	cd $(CORE_DIR) && python3 ../../checks/genchecks.py

# run a single check, e.g.  make check C=insn_add_ch0
check: generate
	$(MAKE) -C $(CORE_DIR)/checks $(C)
	@cat $(CORE_DIR)/checks/$(C)/status

clean:
	rm -rf $(BUILD) timing/timing_bmc timing/timing_cover timing/timing

.PHONY: all riscv-formal timing generate check clean
