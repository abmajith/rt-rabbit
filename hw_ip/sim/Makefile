SIM ?= verilator
TOPLEVEL_LANG = verilog

# Core include directories for your modular components
INC_DIRS += -I$(shell pwd)/../components/pwm
INC_DIRS += -I$(shell pwd)/../components/qei
INC_DIRS += -I$(shell pwd)/../components/telemetry
INC_DIRS += -I$(shell pwd)/../rtl


EXTRA_ARGS += --trace $(INC_DIRS) -Wno-fatal --bbox-sys
COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

TARGET ?= top

ifeq ($(TARGET), pwm_unit)
    TOPLEVEL = wb_pwm
    VERILOG_SOURCES = $(shell pwd)/../components/pwm/wb_pwm.v
    COCOTB_TEST_MODULES = test_pwm_ip
    
else ifeq ($(TARGET), qei_unit)
    TOPLEVEL = wb_qei
    VERILOG_SOURCES = $(shell pwd)/../components/qei/wb_qei.v
    COCOTB_TEST_MODULES = test_qei_ip

else ifeq ($(TARGET), telemetry_rx)
    TOPLEVEL = telemetry_rx
    VERILOG_SOURCES = $(shell pwd)/../components/telemetry/telemetry_rx.v
    COCOTB_TEST_MODULES = test_telemetry_rx

else ifeq ($(TARGET), telemetry_tx)
    COMPILE_ARGS += -GMAX_COUNT=100
    TOPLEVEL = telemetry_tx
    VERILOG_SOURCES = $(shell pwd)/../components/telemetry/telemetry_tx.v
    COCOTB_TEST_MODULES = test_telemetry_tx

else ifeq ($(TARGET), wb_telemetry)
    TOPLEVEL = wb_telemetry
    VERILOG_SOURCES = $(shell pwd)/../components/telemetry/telemetry_rx.v \
                      $(shell pwd)/../components/telemetry/telemetry_tx.v \
                      $(shell pwd)/../components/telemetry/wb_telemetry.v
    COCOTB_TEST_MODULES = test_wb_telemetry

else ifeq ($(TARGET), rf_cdc)
    TOPLEVEL            = rf_cdc_synchronizer
    VERILOG_SOURCES     = $(shell pwd)/../components/telemetry/rf_cdc_synchronizer.v
    COCOTB_TEST_MODULES = test_rf_cdc_synchronizer

else ifeq ($(TARGET), rf_bit_aligner)
    TOPLEVEL            = rf_bit_aligner
    VERILOG_SOURCES     = $(shell pwd)/../components/telemetry/rf_bit_aligner.v
    COCOTB_TEST_MODULES = test_rf_bit_aligner

else ifeq ($(TARGET), rf_packet_framer)
    TOPLEVEL = rf_packet_framer
    VERILOG_SOURCES = $(shell pwd)/../components/telemetry/rf_packet_framer.v
    COCOTB_TEST_MODULES = test_rf_packet_framer

else ifeq ($(TARGET), wb_rf_framer_ctrl)
    TOPLEVEL = wb_rf_framer_ctrl
    VERILOG_SOURCES = $(shell pwd)/../components/telemetry/wb_rf_framer_ctrl.v
    COCOTB_TEST_MODULES = test_wb_rf_framer_ctrl

else ifeq ($(TARGET), rf_receiver_pipeline)
    TOPLEVEL = rf_receiver_pipeline_top
    VERILOG_SOURCES = $(shell pwd)/../components/telemetry/wb_rf_framer_ctrl.v \
                      $(shell pwd)/../components/telemetry/rf_packet_framer.v  \
                      $(shell pwd)/../components/telemetry/rf_bit_aligner.v    \
                      $(shell pwd)/../components/telemetry/rf_cdc_synchronizer.v \
                      $(shell pwd)/../rtl/rf_receiver_pipeline_top.v
    COCOTB_TEST_MODULES = test_rf_receiver_pipeline

else ifeq ($(TARGET), telemetry_rf)
    # Target to verify our asynchronous-to-bus pipeline standalone
    TOPLEVEL = rt_telemetry_top
    VERILOG_SOURCES = $(shell pwd)/../components/telemetry/rf_bit_aligner.v \
                      $(shell pwd)/../components/telemetry/rf_packet_framer_buffer.v \
                      $(shell pwd)/../components/telemetry/rf_rx_fifo_master.v \
                      $(shell pwd)/../rtl/rt_telemetry_top.v
    COCOTB_TEST_MODULES = test_telemetry_top
else
    # Full top system integration including the new RF master pipeline blocks
    TOPLEVEL = rt_top_integrated
    VERILOG_SOURCES = $(shell pwd)/../rtl/rt_top_integrated.v \
                      $(shell pwd)/../components/pwm/wb_pwm.v \
                      $(shell pwd)/../components/qei/wb_qei.v \
                      $(shell pwd)/../components/telemetry/wb_telemetry.v \
                      $(shell pwd)/../components/telemetry/telemetry_tx.v \
                      $(shell pwd)/../components/telemetry/telemetry_rx.v \
                      $(shell pwd)/../components/telemetry/rf_bit_aligner.v \
                      $(shell pwd)/../components/telemetry/rf_packet_framer_buffer.v \
                      $(shell pwd)/../components/telemetry/rf_rx_fifo_master.v \
                      $(shell pwd)/../rtl/rt_telemetry_top.v
    COCOTB_TEST_MODULES = test_top_system
endif

include $(shell cocotb-config --makefiles)/Makefile.sim