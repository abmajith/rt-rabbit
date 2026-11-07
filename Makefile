# rt-rabbit top-level entry points. Everything runs inside the uv environment.
#
#   make help           list targets
#   make configs        list the SoC configurations (configs/*.mk)
#   make soc-sim        run firmware PROG on the SoC CONFIG (default cv32e40p, hello)
#   make soc-waves      the same, and write a waveform (dump.fst)
#   make lint           Verilator lint of the SoC CONFIG
#   make formal         riscv-formal + timing properties (rabbit configurations)
#   make gls-smoke      synthesize CONFIG with Yosys, run firmware PROG on the netlist
#   make ip-test        run every hw_ip cocotb unit/integration test
#   make rma-smoke      run all rma_analysis example configs
#   make ci             everything CI runs (for the selected CONFIG)
#   make check-all      reproduce all rabbit checks (STAGES="quick gls formal synth mutants")
#
# CONFIG=<name> selects configs/<name>.mk; CORE=<core> is short for that core's
# default configuration (see configs/README.md).
REPO := $(abspath .)
export REPO
PROG ?= hello

include mk/config.mk

# hw_ip/sim targets known to pass on main. telemetry_rf and top need
# rf_packet_framer_buffer.v, which is not on main yet (see docs/STATUS.md).
IP_TARGETS := pwm_unit qei_unit telemetry_rx telemetry_tx wb_telemetry rf_cdc \
              rf_bit_aligner rf_packet_framer wb_rf_framer_ctrl rf_receiver_pipeline

# FIFO policy is not implemented yet in rma_analysis (raises NotImplementedError).
RMA_XFAIL := fifo_same_priority_interference.yaml

help:
	@sed -n '2,16p' Makefile | sed 's/^# \{0,1\}//'

configs:
	@for f in configs/*.mk; do printf '%-16s %s\n' "$$(basename $$f .mk)" "$$(head -1 $$f | sed 's/^# //')"; done

# For shell scripts (tools/, asic/): eval "$(make -s config-vars CONFIG=...)"
config-vars:
	@echo "CONFIG='$(CONFIG)' CORE='$(CORE)' CONFIG_ISA='$(CONFIG_ISA)' CONFIG_DEFINES='$(CONFIG_DEFINES)'"

sync:
	uv sync

firmware:
	$(MAKE) -C sw/baremetal PROG=$(PROG) CONFIG=$(CONFIG)

soc-sim: sync
	cd dv/cocotb/soc && uv run $(MAKE) CONFIG=$(CONFIG) PROG=$(PROG)

soc-waves: sync
	cd dv/cocotb/soc && uv run $(MAKE) CONFIG=$(CONFIG) PROG=$(PROG) WAVES=1
	@echo "waveform: dv/cocotb/soc/dump.fst  (open with gtkwave or surfer)"

ip-test: sync
	@set -e; for t in $(IP_TARGETS); do \
	  echo "=== hw_ip: $$t"; \
	  (cd hw_ip/sim && uv run $(MAKE) clean >/dev/null && uv run $(MAKE) TARGET=$$t) ; \
	done

LINT_FLAGS := --lint-only --top-module rabbit_soc_sim \
              -f rtl/cores/$(CORE)/files.f -f rtl/soc/files.f $(CORE_VERILATOR_FLAGS) $(CONFIG_DEFINES)
lint:
	verilator $(LINT_FLAGS)
	@# Strict (-Wall) check, but only fail on warnings in *our* RTL, not vendor cores.
	@! verilator $(LINT_FLAGS) -Wall -Wno-fatal -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY \
	  2>&1 | grep -E '%(Warning|Error)[^:]*: [^ ]*rtl/(soc|cores)/'
	@echo "lint: own RTL clean ($(CONFIG))"

rma-smoke: sync
	@set -e; for f in rma_analysis/examples/*.yaml; do \
	  case " $(RMA_XFAIL) " in *" $$(basename $$f) "*) echo "xfail $$f"; continue;; esac; \
	  uv run rma_analysis $$f >/dev/null && echo "ok    $$f"; \
	done

# ---- formal ---------------------------------------------------------------------
# formal works on our own cores; with a reference core CONFIG it runs rabbit5
FORMAL_CONFIG := $(if $(filter rabbit%,$(CORE)),$(CONFIG),rabbit5)
formal:
	$(MAKE) -C dv/formal/rabbit CONFIG=$(FORMAL_CONFIG)

# ---- gate-level smoke test: generic Yosys gates, zero delay ----------------------
# Catches RTL that simulates differently from what synthesizes (latches, X,
# initial values, simulation-only constructs) long before a real PDK flow.
# The configuration is baked into the netlist.
GLS_DIR := build/gls/$(CONFIG)
YOSYS_SLANG := $(shell yosys -p 'help read_slang' >/dev/null 2>&1 || echo -m slang)
gls-netlist: $(GLS_DIR)/rabbit_cpu_netlist.v
# every file in the core's files.f (incl. rabbit_common), not just rtl/cores/$(CORE)/
GLS_SOURCES := $(shell grep -v '^//' rtl/cores/$(CORE)/files.f | sed 's|$${REPO}|$(REPO)|')
$(GLS_DIR)/rabbit_cpu_netlist.v: $(GLS_SOURCES) rtl/cores/$(CORE)/files.f $(CONFIG_DEPS)
	@mkdir -p $(GLS_DIR)
	yosys $(YOSYS_SLANG) -q -l $(GLS_DIR)/synth.log -p "read_slang \
	    $$(grep -v '^//' rtl/cores/$(CORE)/files.f | sed 's|$${REPO}|$(REPO)|' | tr '\n' ' ') \
	    --top rabbit_cpu -DSYNTHESIS $(CONFIG_DEFINES); \
	  synth -top rabbit_cpu -flatten; tee -o $(GLS_DIR)/stat.txt stat; \
	  write_verilog -noattr $@"
	@grep -E '^ +[0-9]+ +cells' $(GLS_DIR)/stat.txt | head -1

gls-smoke: sync gls-netlist
	cd dv/cocotb/soc && uv run $(MAKE) CONFIG=$(CONFIG) PROG=$(PROG) GLS=1

ci: lint soc-sim ip-test rma-smoke

# Reproduce everything (see tools/check_all.sh; default stages: quick gls)
STAGES ?=
check-all:
	tools/check_all.sh $(STAGES)

clean:
	$(MAKE) -C sw/baremetal clean
	cd dv/cocotb/soc && rm -rf sim_build_* results.xml dump.fst
	rm -rf build dv/formal/rabbit/build
	cd hw_ip/sim && uv run $(MAKE) clean

.PHONY: help configs config-vars sync firmware soc-sim soc-waves ip-test lint rma-smoke formal \
        gls-netlist gls-smoke ci check-all clean
