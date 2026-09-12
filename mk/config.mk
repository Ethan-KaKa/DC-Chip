# mk/config.mk - Kconfig 配置与同步模块

CONFIG_FILE  := .config
CONFIG_DIR   := $(BUILD_DIR)/config
AUTO_CONF    := $(CONFIG_DIR)/auto.conf
CONFIG_H     := $(CONFIG_DIR)/config.h
CONFIG_STAMP := $(CONFIG_DIR)/.sync.stamp

CONFIG_INPUTS := Dconfig \
	scripts/config.py \
	tools/kconfiglib/kconfiglib.py \
	tools/kconfiglib/menuconfig.py

CONFIG_CMD = $(PYTHON) scripts/config.py \
	--config "$(abspath $(CONFIG_FILE))" \
	--output-dir "$(abspath $(CONFIG_DIR))"

ifneq ($(filter sim-build sim nvboard-build nvboard-run test-simulation test-reference test-difftest test-integration test sw sw-run testunit testinfra,$(MAKECMDGOALS)),)
-include $(AUTO_CONF)
endif

defconfig:
	$(CONFIG_CMD) default

$(CONFIG_FILE): configs/default_defconfig
	$(CONFIG_CMD) default

$(CONFIG_STAMP): $(CONFIG_FILE) $(CONFIG_INPUTS)
	$(CONFIG_CMD) sync
	@touch $@

$(AUTO_CONF) $(CONFIG_H) &: | $(CONFIG_STAMP)
	@set -eu; \
	if [ ! -f "$(AUTO_CONF)" ] || [ ! -f "$(CONFIG_H)" ]; then \
		$(CONFIG_CMD) sync; \
	fi

menuconfig: $(CONFIG_FILE)
	CONFIG_="CONFIG_" KCONFIG_CONFIG_HEADER="" \
		KCONFIG_CONFIG="$(abspath $(CONFIG_FILE))" srctree="$(abspath .)" \
		$(PYTHON) tools/kconfiglib/menuconfig.py Dconfig
	$(CONFIG_CMD) sync

config-show:
	$(CONFIG_CMD) show

test-config:
	$(PYTHON) scripts/test_config.py \
		--fixture-root "$(abspath $(BUILD_DIR))/test-fixtures/config" \
		--cxx "$(CXX)"

.PHONY: defconfig menuconfig config-show test-config
