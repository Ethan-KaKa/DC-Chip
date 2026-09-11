AM_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILD_DIR ?= $(abspath $(AM_ROOT)/../../build/sw)
AM_BUILD_DIR := $(BUILD_DIR)/am

RISCV_GCC     ?= $(shell which riscv64-unknown-elf-gcc 2>/dev/null || which riscv64-linux-gnu-gcc 2>/dev/null || echo riscv64-linux-gnu-gcc)
RISCV_OBJDUMP ?= $(shell which riscv64-unknown-elf-objdump 2>/dev/null || which riscv64-linux-gnu-objdump 2>/dev/null || echo riscv64-linux-gnu-objdump)
RISCV_OBJCOPY ?= $(shell which riscv64-unknown-elf-objcopy 2>/dev/null || which riscv64-linux-gnu-objcopy 2>/dev/null || echo riscv64-linux-gnu-objcopy)

AM_INC_DIR := $(AM_ROOT)/include
AM_LDSCRIPT := $(AM_ROOT)/scripts/link.ld

AM_CFLAGS := -march=rv32e -mabi=ilp32e -nostdlib \
	-fno-pic -fno-pie -static -mcmodel=medlow \
	-fno-asynchronous-unwind-tables -fno-builtin -fno-stack-protector \
	-O2 -Wall -Wextra -Wno-main \
	-I$(AM_INC_DIR)

AM_LDFLAGS := -nostdlib -static -mcmodel=medlow \
	-T $(AM_LDSCRIPT) \
	-Wl,--gc-sections \
	-Wl,--build-id=none

AM_SRCS := $(AM_ROOT)/src/start.S \
	$(AM_ROOT)/src/trm.c \
	$(AM_ROOT)/src/klib.c

AM_OBJS := $(patsubst $(AM_ROOT)/src/%,$(AM_BUILD_DIR)/%.o,$(AM_SRCS))

.PHONY: all clean

all: $(AM_OBJS)

$(AM_BUILD_DIR)/%.S.o: $(AM_ROOT)/src/%.S
	@mkdir -p $(dir $@)
	$(RISCV_GCC) $(AM_CFLAGS) -c $< -o $@

$(AM_BUILD_DIR)/%.c.o: $(AM_ROOT)/src/%.c
	@mkdir -p $(dir $@)
	$(RISCV_GCC) $(AM_CFLAGS) -c $< -o $@

clean:
	rm -rf $(AM_BUILD_DIR)
