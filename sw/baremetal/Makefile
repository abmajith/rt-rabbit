# Build a bare-metal program for one SoC configuration (configs/).
#   make PROG=hello                       -> build/cv32e40p/hello/hello.{elf,hex,dis}
#   make PROG=muldiv CONFIG=rabbit5_rv32i -> build/rabbit5_rv32i/muldiv/...
REPO  ?= $(abspath ../..)
PROG  ?= hello

include $(REPO)/mk/config.mk

CROSS ?= riscv64-unknown-elf-
CC     = $(CROSS)gcc
OBJCOPY= $(CROSS)objcopy
OBJDUMP= $(CROSS)objdump

COMMON = $(REPO)/sw/baremetal/common
OUT    = build/$(CONFIG)/$(PROG)

# CORE_CFLAGS (core.mk): defines that describe a core's documented deviations
CFLAGS  = $(CORE_CFLAGS) -march=$(CORE_MARCH) -mabi=$(CORE_MABI) -O2 -g -Wall -Wextra \
          -ffreestanding -fno-builtin -nostdlib -I$(COMMON)
LDFLAGS = -T $(COMMON)/link.ld -nostartfiles -nostdlib -Wl,--gc-sections -Wl,--no-warn-rwx-segments -lgcc

SRCS = $(COMMON)/crt0.S $(wildcard $(PROG)/*.c) $(wildcard $(PROG)/*.S)

all: $(OUT)/$(PROG).hex $(OUT)/$(PROG).dis

$(OUT)/$(PROG).elf: $(SRCS) $(COMMON)/link.ld $(COMMON)/rabbit_sim.h $(CONFIG_DEPS)
	@mkdir -p $(OUT)
	$(CC) $(CFLAGS) $(SRCS) -o $@ $(LDFLAGS)

# 32-bit little-endian words, one per line, starting at address 0 ($readmemh format)
$(OUT)/$(PROG).hex: $(OUT)/$(PROG).elf
	$(OBJCOPY) -O binary $< $(OUT)/$(PROG).bin
	python3 $(REPO)/tools/bin2hex.py $(OUT)/$(PROG).bin $@

$(OUT)/$(PROG).dis: $(OUT)/$(PROG).elf
	$(OBJDUMP) -d -S $< > $@

clean:
	rm -rf build

.PHONY: all clean
