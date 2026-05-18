# hw_ip/sim/Makefile
SIM ?= verilator
TOPLEVEL_LANG = verilog

# Core include directories for your modular components
INC_DIRS += -I$(shell pwd)/../components/pwm
INC_DIRS += -I$(shell pwd)/../components/qei
INC_DIRS += -I$(shell pwd)/../components/telemetry

# --- DUAL LAYER VERIFICATION SWITCH ---
# Usage: 
#   uv run make TARGET=qei      --> Unit Level Verification
#   uv run make TARGET=telemetry --> Unit Level Verification
#   uv run make                  --> Top Level System Integration Verification
TARGET ?= top

ifeq ($(TARGET), pwm)
	TOPLEVEL = wb_pwm
	VERILOG_SOURCES = $(shell pwd)/../components/pwm/wb_pwm.v
	MODULE = test_pwm_ip
else ifeq ($(TARGET), qei)
	TOPLEVEL = wb_qei
	VERILOG_SOURCES = $(shell pwd)/../components/qei/wb_qei.v
	MODULE = test_qei_ip
else ifeq ($(TARGET), telemetry_rx)
	TOPLEVEL = telemetry_rx
	VERILOG_SOURCES = $(shell pwd)/../components/telemetry/telemetry_rx.v
	MODULE = test_telemetry_rx
else ifeq ($(TARGET), telemetry_tx)
	TOPLEVEL = telemetry_tx
	VERILOG_SOURCES = $(shell pwd)/../components/telemetry/telemetry_tx.v
	MODULE = test_telemetry_tx
else ifeq ($(TARGET), telemetry)
	TOPLEVEL = wb_telemetry
	VERILOG_SOURCES = $(shell pwd)/../components/telemetry/telemetry_rx.v \
	                  $(shell pwd)/../components/telemetry/telemetry_tx.v \
	                  $(shell pwd)/../components/telemetry/wb_telemetry.v
	MODULE = test_telemetry_ip
else
	TOPLEVEL = rt_top_integrated
    VERILOG_SOURCES = $(shell pwd)/../rtl/rt_top_integrated.v \
                      $(shell pwd)/../components/pwm/wb_pwm.v \
                      $(shell pwd)/../components/qei/wb_qei.v \
                      $(shell pwd)/../components/telemetry/wb_telemetry.v \
                      $(shell pwd)/../components/telemetry/telemetry_tx.v \
                      $(shell pwd)/../components/telemetry/telemetry_rx.v
    MODULE = test_top_system
endif

EXTRA_ARGS += --trace $(INC_DIRS)
COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

include $(shell cocotb-config --makefiles)/Makefile.sim