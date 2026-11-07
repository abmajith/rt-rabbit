# =============================================================================
# mk/config.mk — turn a configuration name into everything a build needs
# =============================================================================
# Included by every Makefile that builds, simulates, proves or synthesizes a
# SoC. A configuration is one small file, configs/<CONFIG>.mk: which core, and
# which optional parts are switched on (see configs/README.md).
#
#   make soc-sim CONFIG=rabbit5_rv32i    any file in configs/
#   make soc-sim CORE=rabbit5            short form: CONFIG=rabbit5, the core's
#                                        default configuration
#
# After this file:
#   CONFIG          name, also the name of every build folder
#   CORE            rtl/cores/<CORE>/ (rabbit_cpu.sv, files.f, core.mk)
#   RV32M           1/0, and the other options below
#   CONFIG_DEFINES  the options as -D defines, for every tool that reads RTL
#                   (Verilator, Yosys/slang, SymbiYosys). They become the CFG
#                   parameter of the rabbit cores (rtl/cores/rabbit_common/rabbit_pkg.sv).
#   CONFIG_ISA      ISA string without Zicsr, e.g. rv32im (riscv-formal, -march)
#   + everything rtl/cores/<CORE>/core.mk sets (CORE_MARCH, TIMING_*, ...)
# =============================================================================
REPO ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

CONFIG ?= $(if $(CORE),$(CORE),cv32e40p)
CONFIG_FILE := $(REPO)/configs/$(CONFIG).mk
ifeq ($(wildcard $(CONFIG_FILE)),)
$(error CONFIG=$(CONFIG): there is no configs/$(CONFIG).mk. Available: $(sort $(basename $(notdir $(wildcard $(REPO)/configs/*.mk)))))
endif

# ---- options and their defaults --------------------------------------------
# The defaults are the full current specification; a configuration file only
# lists what differs. Options are set in configuration files, never on the
# command line: every build folder is named after CONFIG, so two builds with
# the same name must be the same hardware.
CONFIG_OPTIONS := RV32M
# RV32M: M extension (multiply / divide)
RV32M := 1

$(foreach o,$(CONFIG_OPTIONS),$(if $(filter command line environment,$(origin $(o))),\
  $(error $(o) is an option of a configuration: set it in configs/$(CONFIG).mk (or a new file there), not on the command line)))

include $(CONFIG_FILE)
ifeq ($(CONFIG_CORE),)
$(error configs/$(CONFIG).mk must set CONFIG_CORE)
endif
ifneq ($(filter command line environment,$(origin CORE)),)
ifneq ($(CORE),$(CONFIG_CORE))
$(error CORE=$(CORE) but configs/$(CONFIG).mk uses core $(CONFIG_CORE); give only CONFIG)
endif
endif
override CORE := $(CONFIG_CORE)

# strip: a comment after a value ("RV32M := 0  # ...") leaves trailing spaces
RV32M := $(strip $(RV32M))
$(if $(filter-out 0 1,$(RV32M)),$(error configs/$(CONFIG).mk: RV32M must be 0 or 1))

CONFIG_ISA     := rv32i$(if $(filter 1,$(RV32M)),m)
CONFIG_DEFINES := -DRABBIT_RV32M=$(RV32M)

include $(REPO)/rtl/cores/$(CORE)/core.mk

# A build depends on its configuration: editing it rebuilds what used it.
CONFIG_DEPS := $(CONFIG_FILE) $(REPO)/mk/config.mk $(REPO)/rtl/cores/$(CORE)/core.mk
