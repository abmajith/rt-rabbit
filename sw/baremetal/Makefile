# Build a bare-metal program for the selected core.
#   make PROG=hello            -> build/hello/hello.{elf,hex,dis}
#   make PROG=hello CORE=ibex  (once an ibex adapter exists)
REPO  ?= $(abspath ../..)
CORE  ?= cv32e40p
PROG  ?= hello

include $(REPO)/rtl/cores/$(CORE)/core.mk

CROSS ?= riscv64-unknown-elf-
CC     = $(CROSS)gcc
OBJCOPY= $(CROSS)objcopy
OBJDUMP= $(CROSS)objdump

COMMON = $(REPO)/sw/baremetal/common
OUT    = build/$(PROG)

CFLAGS  = -march=$(CORE_MARCH) -mabi=$(CORE_MABI) -O2 -g -Wall -Wextra \
          -ffreestanding -fno-builtin -nostdlib -I$(COMMON)
LDFLAGS = -T $(COMMON)/link.ld -nostartfiles -nostdlib -Wl,--gc-sections -Wl,--no-warn-rwx-segments -lgcc

SRCS = $(COMMON)/crt0.S $(wildcard $(PROG)/*.c) $(wildcard $(PROG)/*.S)

all: $(OUT)/$(PROG).hex $(OUT)/$(PROG).dis

$(OUT)/$(PROG).elf: $(SRCS) $(COMMON)/link.ld $(COMMON)/rabbit_sim.h
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
