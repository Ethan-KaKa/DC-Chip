REPO_ROOT ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
AM_ROOT := $(REPO_ROOT)/sw/am
BUILD_DIR ?= $(REPO_ROOT)/build/sw
DEMO_BUILD_DIR := $(BUILD_DIR)/demo

RISCV_GCC ?= $(shell which riscv64-unknown-elf-gcc 2>/dev/null || which riscv64-linux-gnu-gcc 2>/dev/null || echo riscv64-linux-gnu-gcc)
RISCV_OBJDUMP ?= $(shell which riscv64-unknown-elf-objdump 2>/dev/null || which riscv64-linux-gnu-objdump 2>/dev/null || echo riscv64-linux-gnu-objdump)
RISCV_OBJCOPY ?= $(shell which riscv64-unknown-elf-objcopy 2>/dev/null || which riscv64-linux-gnu-objcopy 2>/dev/null || echo riscv64-linux-gnu-objcopy)
PYTHON ?= python3

AM_INC_DIR := $(AM_ROOT)/include
AM_LDSCRIPT := $(AM_ROOT)/scripts/link.ld
CHECK_ISA := $(PYTHON) $(REPO_ROOT)/scripts/check_isa_subset.py
DEMO := uart_led_demo
DEMO_DIR := $(DEMO_BUILD_DIR)/$(DEMO)
AM_OBJS := $(BUILD_DIR)/am/start.S.o $(BUILD_DIR)/am/trm.c.o \
	$(BUILD_DIR)/am/klib.c.o $(BUILD_DIR)/am/ioe.c.o
AM_SRCS := $(wildcard $(AM_ROOT)/src/*) $(wildcard $(AM_ROOT)/include/*)

CFLAGS := -march=rv32e -mabi=ilp32e -mstrict-align -nostdlib \
	-fno-pic -fno-pie -static -mcmodel=medlow \
	-fno-asynchronous-unwind-tables -fno-builtin -fno-stack-protector \
	-O2 -Wall -Wextra -Wno-main -I$(AM_INC_DIR)
LDFLAGS := -nostdlib -static -mcmodel=medlow -T $(AM_LDSCRIPT) \
	-Wl,--gc-sections -Wl,--build-id=none -lgcc

TARGET := $(DEMO_DIR)/$(DEMO).inst.bin

.PHONY: all build clean $(DEMO)
all build $(DEMO): $(TARGET)

$(AM_OBJS): $(AM_SRCS)
	@$(MAKE) -C $(AM_ROOT) BUILD_DIR=$(BUILD_DIR)

$(DEMO_DIR)/$(DEMO).elf: $(REPO_ROOT)/sw/demo/$(DEMO)/$(DEMO).c $(AM_OBJS)
	@mkdir -p $(dir $@)
	$(RISCV_GCC) $(CFLAGS) $< $(AM_OBJS) $(LDFLAGS) -o $@

$(DEMO_DIR)/$(DEMO).txt: $(DEMO_DIR)/$(DEMO).elf
	$(RISCV_OBJDUMP) -d $< > $@
	$(CHECK_ISA) $@

$(TARGET): $(DEMO_DIR)/$(DEMO).txt
	$(RISCV_OBJCOPY) -S -O binary -j .text $(DEMO_DIR)/$(DEMO).elf $@
	$(RISCV_OBJCOPY) -S -O binary -j .rodata -j .rodata.* -j .data -j .data.* -j .sdata -j .sdata.* \
		$(DEMO_DIR)/$(DEMO).elf $(DEMO_DIR)/$(DEMO).data.bin

clean:
	rm -rf $(DEMO_BUILD_DIR)
