# mk/list.mk - 自省与顶层帮助模块

ifeq ($(firstword $(MAKECMDGOALS)),list)
list:
	@$(PYTHON) scripts/test_runner.py --list-suites
else
list:
	@:
endif

batch:
	@:

tests:
	@:

riscv-tests:
	@:

help:
	@$(PYTHON) scripts/test_runner.py --list-suites

.PHONY: list help batch tests riscv-tests
