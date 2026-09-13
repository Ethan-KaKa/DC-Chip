# Common AM application build rules.
# Applications provide a name and source, then invoke AM_DEFINE_APP.

AM_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT ?= $(abspath $(AM_ROOT)/../..)
BUILD_DIR ?= $(REPO_ROOT)/build/sw
AM_BUILD_DIR ?= $(BUILD_DIR)/am

RISCV_GCC     ?= $(shell which riscv64-unknown-elf-gcc 2>/dev/null || which riscv64-linux-gnu-gcc 2>/dev/null || echo riscv64-linux-gnu-gcc)
RISCV_OBJDUMP ?= $(shell which riscv64-unknown-elf-objdump 2>/dev/null || which riscv64-linux-gnu-objdump 2>/dev/null || echo riscv64-linux-gnu-objdump)
RISCV_OBJCOPY ?= $(shell which riscv64-unknown-elf-objcopy 2>/dev/null || which riscv64-linux-gnu-objcopy 2>/dev/null || echo riscv64-linux-gnu-objcopy)
PYTHON        ?= python3

AM_CFLAGS := -march=rv32e -mabi=ilp32e -mstrict-align -nostdlib \
	-fno-pic -fno-pie -static -mcmodel=medlow \
	-fno-asynchronous-unwind-tables -fno-builtin -fno-stack-protector \
	-O2 -Wall -Wextra -Wno-main -I$(AM_ROOT)/include
AM_LDFLAGS := -nostdlib -static -mcmodel=medlow \
	-T $(AM_ROOT)/scripts/link.ld -Wl,--gc-sections \
	-Wl,--build-id=none -lgcc

# Application-specific additions are optional; AM policy remains centralized.
AM_APP_CFLAGS ?=
AM_APP_LDFLAGS ?=
AM_CHECK_ISA := $(PYTHON) $(REPO_ROOT)/scripts/check_isa_subset.py

AM_SRCS := $(AM_ROOT)/src/start.S $(AM_ROOT)/src/trm.c \
	$(AM_ROOT)/src/klib.c $(AM_ROOT)/src/ioe.c
AM_OBJS := $(patsubst $(AM_ROOT)/src/%,$(AM_BUILD_DIR)/%.o,$(AM_SRCS))

$(AM_BUILD_DIR)/%.S.o: $(AM_ROOT)/src/%.S
	@mkdir -p $(dir $@)
	$(RISCV_GCC) $(AM_CFLAGS) -c $< -o $@

$(AM_BUILD_DIR)/%.c.o: $(AM_ROOT)/src/%.c
	@mkdir -p $(dir $@)
	$(RISCV_GCC) $(AM_CFLAGS) -c $< -o $@

define AM_DEFINE_APP
AM_APP_$(1)_ELF := $(2)/$(1).elf
AM_APP_$(1)_TXT := $(2)/$(1).txt
AM_APP_$(1)_INST := $(2)/$(1).inst.bin
AM_APP_$(1)_DATA := $(2)/$(1).data.bin

$$(AM_APP_$(1)_ELF): $(3) $$(AM_OBJS)
	@mkdir -p $$(dir $$@)
	$$(RISCV_GCC) $$(AM_CFLAGS) $$(AM_APP_CFLAGS) $$^ $$(AM_LDFLAGS) $$(AM_APP_LDFLAGS) -o $$@

$$(AM_APP_$(1)_TXT): $$(AM_APP_$(1)_ELF)
	$$(RISCV_OBJDUMP) -d $$< > $$@
	$$(AM_CHECK_ISA) $$@

$$(AM_APP_$(1)_INST): $$(AM_APP_$(1)_TXT)
	$$(RISCV_OBJCOPY) -S -O binary -j .text $$(AM_APP_$(1)_ELF) $$@
	$$(RISCV_OBJCOPY) -S -O binary -j .rodata -j .rodata.* -j .data -j .data.* -j .sdata -j .sdata.* $$(AM_APP_$(1)_ELF) $$(AM_APP_$(1)_DATA)
endef
