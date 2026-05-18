# hw_ip/sim/Makefile

SIM ?= verilator
TOPLEVEL_LANG = verilog

# Point to both your top-level structure and the imported open-source IP folder
VERILOG_SOURCES += $(shell pwd)/../rtl/rt_top.v
VERILOG_SOURCES += $(shell pwd)/../open_source_ip/wb_pwm.v
VERILOG_SOURCES += $(shell pwd)/../open_source_ip/wb_qei.v

# Define top-level verilog structural wrapper block target name
TOPLEVEL = rt_top

# FORCE VERILATOR TO ENABLE VCD TRACING
EXTRA_ARGS += --trace

# Define python testing module execution target name
MODULE ?= test_pwm_ip

# Enable visual value-change dump generation to review wave behaviors later
COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

include $(shell cocotb-config --makefiles)/Makefile.sim