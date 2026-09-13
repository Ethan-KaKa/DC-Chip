REPO_ROOT ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
BUILD_DIR ?= $(REPO_ROOT)/build/sw
DEMO_BUILD_DIR := $(BUILD_DIR)/demo
AM_ROOT := $(REPO_ROOT)/sw/am
AM_BUILD_DIR := $(BUILD_DIR)/am
include $(AM_ROOT)/build.mk
DEMO := uart_led_demo
DEMO_DIR := $(DEMO_BUILD_DIR)/$(DEMO)

TARGET := $(DEMO_DIR)/$(DEMO).inst.bin

.PHONY: all build clean $(DEMO)
all build $(DEMO): $(TARGET)

$(eval $(call AM_DEFINE_APP,$(DEMO),$(DEMO_DIR),$(REPO_ROOT)/sw/demo/$(DEMO)/$(DEMO).c))

clean:
	rm -rf $(DEMO_BUILD_DIR)
