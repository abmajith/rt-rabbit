# rt-rabbit top-level entry points. Everything runs inside the uv environment.
#
#   make help           list targets
#   make soc-sim        run firmware PROG on the SoC with CORE (default cv32e40p/hello)
#   make ip-test        run every hw_ip cocotb unit/integration test
#   make lint           Verilator lint of the SoC
#   make rma-smoke      run all rma_analysis example configs
#   make formal         riscv-formal + timing properties (CORE=rabbit3|rabbit5)
#   make gls-smoke      synthesize the core with Yosys, run firmware on the netlist
#   make ci             everything CI runs
REPO := $(abspath .)
export REPO
CORE ?= cv32e40p
PROG ?= hello

# hw_ip/sim targets known to pass on main. telemetry_rf and top need
# rf_packet_framer_buffer.v, which is not on main yet (see docs/STATUS.md).
IP_TARGETS := pwm_unit qei_unit telemetry_rx telemetry_tx wb_telemetry rf_cdc \
              rf_bit_aligner rf_packet_framer wb_rf_framer_ctrl rf_receiver_pipeline

# FIFO policy is not implemented yet in rma_analysis (raises NotImplementedError).
RMA_XFAIL := fifo_same_priority_interference.yaml

help:
	@sed -n '2,11p' Makefile | sed 's/^# //'

sync:
	uv sync

firmware:
	$(MAKE) -C sw/baremetal PROG=$(PROG) CORE=$(CORE)

soc-sim: sync
	cd dv/cocotb/soc && uv run $(MAKE) CORE=$(CORE) PROG=$(PROG)

soc-waves: sync
	cd dv/cocotb/soc && uv run $(MAKE) CORE=$(CORE) PROG=$(PROG) WAVES=1
	@echo "waveform: dv/cocotb/soc/dump.fst  (open with gtkwave or surfer)"

ip-test: sync
	@set -e; for t in $(IP_TARGETS); do \
	  echo "=== hw_ip: $$t"; \
	  (cd hw_ip/sim && uv run $(MAKE) clean >/dev/null && uv run $(MAKE) TARGET=$$t) ; \
	done

lint:
	verilator --lint-only --top-module rabbit_soc_sim \
	  -f rtl/cores/$(CORE)/files.f -f rtl/soc/files.f \
	  $$(sed -n 's/^CORE_VERILATOR_FLAGS *:= *//p' rtl/cores/$(CORE)/core.mk)
	@# Strict (-Wall) check, but only fail on warnings in *our* RTL, not vendor cores.
	@! verilator --lint-only -Wall -Wno-fatal -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY \
	  --top-module rabbit_soc_sim -f rtl/cores/$(CORE)/files.f -f rtl/soc/files.f \
	  $$(sed -n 's/^CORE_VERILATOR_FLAGS *:= *//p' rtl/cores/$(CORE)/core.mk) \
	  2>&1 | grep -E '%(Warning|Error)[^:]*: [^ ]*rtl/(soc|cores)/'
	@echo "lint: own RTL clean"

rma-smoke: sync
	@set -e; for f in rma_analysis/examples/*.yaml; do \
	  case " $(RMA_XFAIL) " in *" $$(basename $$f) "*) echo "xfail $$f"; continue;; esac; \
	  uv run rma_analysis $$f >/dev/null && echo "ok    $$f"; \
	done

# ---- formal (rabbit5) ---------------------------------------------------------
# formal works on our own cores; with the default CORE (cv32e40p) it runs rabbit5
FORMAL_CORE := $(if $(filter rabbit%,$(CORE)),$(CORE),rabbit5)
formal:
	$(MAKE) -C dv/formal/rabbit CORE=$(FORMAL_CORE)

# ---- gate-level smoke test: generic Yosys gates, zero delay ----------------------
# Catches RTL that simulates differently from what synthesizes (latches, X,
# initial values, simulation-only constructs) long before a real PDK flow.
GLS_DIR := build/gls/$(CORE)
YOSYS_SLANG := $(shell yosys -p 'help read_slang' >/dev/null 2>&1 || echo -m slang)
gls-netlist: $(GLS_DIR)/rabbit_cpu_netlist.v
$(GLS_DIR)/rabbit_cpu_netlist.v: $(wildcard rtl/cores/$(CORE)/*.sv)
	@mkdir -p $(GLS_DIR)
	yosys $(YOSYS_SLANG) -q -l $(GLS_DIR)/synth.log -p "read_slang \
	    $$(grep -v '^//' rtl/cores/$(CORE)/files.f | sed 's|$${REPO}|$(REPO)|' | tr '\n' ' ') \
	    --top rabbit_cpu -DSYNTHESIS; \
	  synth -top rabbit_cpu -flatten; tee -o $(GLS_DIR)/stat.txt stat; \
	  write_verilog -noattr $@"
	@grep -E '^ +[0-9]+ +cells' $(GLS_DIR)/stat.txt | head -1

gls-smoke: sync gls-netlist
	cd dv/cocotb/soc && uv run $(MAKE) CORE=$(CORE) PROG=$(PROG) GLS=1

ci: lint soc-sim ip-test rma-smoke

clean:
	$(MAKE) -C sw/baremetal clean
	cd dv/cocotb/soc && rm -rf sim_build_* results.xml dump.fst
	rm -rf build dv/formal/rabbit/build
	cd hw_ip/sim && uv run $(MAKE) clean

.PHONY: help sync firmware soc-sim soc-waves ip-test lint rma-smoke formal gls-netlist gls-smoke ci clean
