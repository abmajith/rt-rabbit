SIM ?= verilator
TOPLEVEL_LANG ?= verilog

VERILOG_SOURCES += $(PWD)/../hw_ip/rtl/udp_ep.v

TOPLEVEL = udp_ep
MODULE = test_udp_ep

include $(shell cocotb-config --makefiles)/Makefile.sim
