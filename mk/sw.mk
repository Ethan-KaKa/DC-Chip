# mk/sw.mk - 全系统软件编译与测试调度模块 (Layer 3)

# 统一入口:
#   make sw                             -> 仅编译所有软件镜像
#   make sw tests [list|batch|ALL=...]  -> 运行全系统微测试
#   make sw riscv-tests [list|batch...] -> 运行合规套件
sw:
	@if [ -z "$(word 2,$(MAKECMDGOALS))" ]; then \
		$(MAKE) -C sw/tests BUILD_DIR=$(abspath $(BUILD_DIR))/sw; \
	else \
		case "$(word 2,$(MAKECMDGOALS))" in \
			tests) \
				case "$(word 3,$(MAKECMDGOALS))" in \
					list)  $(PYTHON) scripts/test_runner.py --suite sw-tests --list ;; \
					batch) $(PYTHON) scripts/test_runner.py --suite sw-tests --batch \
								--simulator "$(abspath $(SIM_BIN))" \
								--difftest-override "$(DIFFTEST)" --wave-override "$(WAVE)" ;; \
					*)     if [ -n "$(ALL)" ]; then \
							$(PYTHON) scripts/test_runner.py --suite sw-tests --filter "$(ALL)" \
								--simulator "$(abspath $(SIM_BIN))" \
								--difftest-override "$(DIFFTEST)" --wave-override "$(WAVE)"; \
						   else \
							$(PYTHON) scripts/test_runner.py --suite sw-tests --batch \
								--simulator "$(abspath $(SIM_BIN))" \
								--difftest-override "$(DIFFTEST)" --wave-override "$(WAVE)"; \
						   fi ;; \
				esac ;; \
			riscv-tests) \
				case "$(word 3,$(MAKECMDGOALS))" in \
					list)  $(PYTHON) scripts/test_runner.py --suite riscv-tests --list ;; \
					batch) $(PYTHON) scripts/test_runner.py --suite riscv-tests --batch ;; \
					*)     if [ -n "$(ALL)" ]; then \
							$(PYTHON) scripts/test_runner.py --suite riscv-tests --filter "$(ALL)"; \
						   else \
							$(PYTHON) scripts/test_runner.py --suite riscv-tests --batch; \
						   fi ;; \
				esac ;; \
			*) \
				printf 'error: 未知的 sw 子目标 "%s". 支持: make sw tests [list|batch|ALL=...] 或 make sw riscv-tests [list|batch]\n' "$(word 2,$(MAKECMDGOALS))" >&2; \
				exit 1 ;; \
		esac; \
	fi

# 历史兼容目标
test-sw: sw sim-build
	$(PYTHON) scripts/run_sw_tests.py \
		--simulator "$(abspath $(SIM_BIN))" \
		--test-dir "$(abspath $(BUILD_DIR))/sw/tests"

.PHONY: sw test-sw
