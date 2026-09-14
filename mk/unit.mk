# mk/unit.mk - 硬件单测与静态测试模块 (Layer 1)

UNIT_DIR := $(BUILD_DIR)/unit

ISA_PKG := rtl/core/dc_isa_pkg.sv
COMB_RTL := $(ISA_PKG) \
	rtl/core/decoder.sv \
	rtl/core/alu.sv
CORE_RTL := $(COMB_RTL) \
	rtl/core/regfile.sv \
	rtl/core/cpu_core.sv
PERIPH_RTL := rtl/periph/led_controller.sv \
	rtl/periph/uart_controller.sv \
	rtl/periph/buttons_controller.sv \
	rtl/periph/seg7_controller.sv
SOC_RTL := rtl/soc/mmio_cdc_bridge.sv \
	rtl/soc/periph_interconnect.sv \
	rtl/soc/soc_interconnect.sv \
	rtl/soc/dc_soc_top.sv

# 静态规则检查 (Lint)
_lint-isa:
	$(VERILATOR) --lint-only --language 1800-2012 -Wall -Wno-UNUSEDPARAM \
		--top-module decoder $(ISA_PKG) rtl/core/decoder.sv

_lint-comb:
	$(VERILATOR) --lint-only --language 1800-2012 -Wall -Wno-UNUSEDPARAM \
		--top-module alu $(ISA_PKG) rtl/core/alu.sv
	$(VERILATOR) --lint-only --language 1800-2012 -Wall -Wno-UNUSEDPARAM \
		--top-module decoder $(ISA_PKG) rtl/core/decoder.sv

_lint-core:
	$(VERILATOR) --lint-only --language 1800-2012 -Wall \
		--top-module cpu_core $(CORE_RTL)

_lint-mem:
	$(VERILATOR) --lint-only --language 1800-2012 -Wall \
		--top-module sim_mem $(MEM_RTL)

# 单元编译规则
$(UNIT_DIR):
	mkdir -p $@

$(UNIT_DIR)/tb_alu.vvp: $(ISA_PKG) rtl/core/alu.sv sim/tb/tb_alu.sv $(BUILD_MAKEFILES) | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_alu -o $@ $(ISA_PKG) rtl/core/alu.sv sim/tb/tb_alu.sv

$(UNIT_DIR)/tb_decoder.vvp: $(ISA_PKG) rtl/core/decoder.sv sim/tb/tb_decoder.sv $(BUILD_MAKEFILES) | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_decoder -o $@ $(ISA_PKG) rtl/core/decoder.sv sim/tb/tb_decoder.sv

$(UNIT_DIR)/tb_regfile.vvp: $(ISA_PKG) rtl/core/regfile.sv sim/tb/tb_regfile.sv $(BUILD_MAKEFILES) | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_regfile -o $@ $(ISA_PKG) rtl/core/regfile.sv sim/tb/tb_regfile.sv

$(UNIT_DIR)/tb_cpu_core.vvp: $(CORE_RTL) sim/tb/tb_cpu_core.sv $(BUILD_MAKEFILES) | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_cpu_core -o $@ $(CORE_RTL) sim/tb/tb_cpu_core.sv

$(UNIT_DIR)/tb_led_controller.vvp: rtl/periph/led_controller.sv sim/tb/tb_led_controller.sv $(BUILD_MAKEFILES) | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_led_controller -Irtl/periph -o $@ rtl/periph/led_controller.sv sim/tb/tb_led_controller.sv

$(UNIT_DIR)/tb_uart_controller.vvp: rtl/periph/uart_controller.sv sim/tb/tb_uart_controller.sv $(BUILD_MAKEFILES) | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_uart_controller -Irtl/periph -o $@ rtl/periph/uart_controller.sv sim/tb/tb_uart_controller.sv

$(UNIT_DIR)/tb_buttons_controller.vvp: rtl/periph/buttons_controller.sv sim/tb/tb_buttons_controller.sv $(BUILD_MAKEFILES) | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_buttons_controller -Irtl/periph -o $@ rtl/periph/buttons_controller.sv sim/tb/tb_buttons_controller.sv

$(UNIT_DIR)/tb_seg7_controller.vvp: rtl/periph/seg7_controller.sv sim/tb/tb_seg7_controller.sv $(BUILD_MAKEFILES) | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_seg7_controller -Irtl/periph -o $@ rtl/periph/seg7_controller.sv sim/tb/tb_seg7_controller.sv

$(UNIT_DIR)/tb_periph_interconnect.vvp: rtl/soc/periph_interconnect.sv sim/tb/tb_periph_interconnect.sv $(BUILD_MAKEFILES) | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_periph_interconnect -Irtl/soc -o $@ rtl/soc/periph_interconnect.sv sim/tb/tb_periph_interconnect.sv

$(UNIT_DIR)/tb_mmio_cdc_bridge.vvp: rtl/soc/mmio_cdc_bridge.sv sim/tb/tb_mmio_cdc_bridge.sv $(BUILD_MAKEFILES) | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_mmio_cdc_bridge -Irtl/soc -o $@ rtl/soc/mmio_cdc_bridge.sv sim/tb/tb_mmio_cdc_bridge.sv

$(UNIT_DIR)/tb_soc_interconnect.vvp: rtl/soc/soc_interconnect.sv sim/tb/tb_soc_interconnect.sv $(BUILD_MAKEFILES) | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_soc_interconnect -Irtl/soc -o $@ rtl/soc/soc_interconnect.sv sim/tb/tb_soc_interconnect.sv

$(UNIT_DIR)/tb_dc_soc_top.vvp: $(CORE_RTL) $(PERIPH_RTL) $(SOC_RTL) sim/tb/tb_dc_soc_top.sv $(BUILD_MAKEFILES) | $(UNIT_DIR)
	$(IVERILOG) -g2012 -s tb_dc_soc_top -Irtl/core -Irtl/soc -Irtl/periph -o $@ $(CORE_RTL) $(PERIPH_RTL) $(SOC_RTL) sim/tb/tb_dc_soc_top.sv

# 各单独单测运行目标
_test-unit-alu: $(UNIT_DIR)/tb_alu.vvp
	$(VVP) $<

_test-unit-decoder: $(UNIT_DIR)/tb_decoder.vvp
	$(VVP) $<

_test-unit-regfile: $(UNIT_DIR)/tb_regfile.vvp
	$(VVP) $<

_test-unit-core: $(UNIT_DIR)/tb_cpu_core.vvp
	$(VVP) $<

_test-unit-led: $(UNIT_DIR)/tb_led_controller.vvp
	$(VVP) $<

_test-unit-uart: $(UNIT_DIR)/tb_uart_controller.vvp
	$(VVP) $<

_test-unit-buttons: $(UNIT_DIR)/tb_buttons_controller.vvp
	$(VVP) $<

_test-unit-seg7: $(UNIT_DIR)/tb_seg7_controller.vvp
	$(VVP) $<

_test-unit-periph-interconnect: $(UNIT_DIR)/tb_periph_interconnect.vvp
	$(VVP) $<

_test-unit-cdc: $(UNIT_DIR)/tb_mmio_cdc_bridge.vvp
	$(VVP) $<

_test-unit-interconnect: $(UNIT_DIR)/tb_soc_interconnect.vvp
	$(VVP) $<

_test-unit-soc: $(UNIT_DIR)/tb_dc_soc_top.vvp
	$(VVP) $<

_test-unit-lint:
	$(MAKE) --no-print-directory _lint-isa
	$(MAKE) --no-print-directory _lint-comb
	$(MAKE) --no-print-directory _lint-core
	$(MAKE) --no-print-directory _lint-mem

# 统一新入口: make testunit [list | batch | ALL=...]

testunit:
	@case "$(word 2,$(MAKECMDGOALS))" in \
		list)  $(PYTHON) scripts/test_runner.py --suite unit --list --make "$(MAKE)" ;; \
		batch) $(PYTHON) scripts/test_runner.py --suite unit --batch --make "$(MAKE)" ;; \
		*)     if [ -n "$(ALL)" ]; then \
				$(PYTHON) scripts/test_runner.py --suite unit --filter "$(ALL)" --make "$(MAKE)"; \
			   else \
				$(PYTHON) scripts/test_runner.py --suite unit --batch --make "$(MAKE)"; \
			   fi ;; \
	esac

.PHONY: _lint-isa _lint-comb _lint-core _lint-mem \
	_test-unit-alu _test-unit-decoder _test-unit-regfile _test-unit-core \
	_test-unit-led _test-unit-uart _test-unit-buttons _test-unit-periph-interconnect \
	_test-unit-seg7 \
	_test-unit-cdc _test-unit-interconnect _test-unit-soc _test-unit-lint testunit
