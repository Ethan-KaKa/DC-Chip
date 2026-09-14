#!/usr/bin/env python3
"""
scripts/test_runner.py

DC-Chip 统一自省与测试调度引擎。
支持:
  - make list (列出顶层三大验证范畴)
  - make testunit list | batch | ALL=alu,uart,...
  - make testinfra list | batch | ALL=memory,reference,...
  - make sw tests list | batch | ALL=cpu_fib,uart_hello,...
  - make sw demo list | build | run
  - make sw riscv-tests list | batch | ALL=...
"""

import argparse
import os
import subprocess
import sys
import time

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def select_tests(tests, filter_str, suite_name):
    """Validate a comma-separated filter before starting any test."""
    if filter_str is None:
        return [test for test in tests if test.get("default", True)]

    names = [name.strip() for name in filter_str.split(",") if name.strip()]
    if not names:
        print(f"error: {suite_name} 的 ALL 不能为空", file=sys.stderr)
        sys.exit(2)

    duplicates = sorted({name for name in names if names.count(name) > 1})
    available = {test["name"]: test for test in tests}
    unknown = [name for name in names if name not in available]
    if duplicates or unknown:
        if duplicates:
            print(f"error: {suite_name} 包含重复测试项: {','.join(duplicates)}", file=sys.stderr)
        if unknown:
            print(f"error: {suite_name} 包含未知测试项: {','.join(unknown)}", file=sys.stderr)
        print(f"available: {','.join(available)}", file=sys.stderr)
        sys.exit(2)

    return [available[name] for name in names]

def extract_readme_summary(path):
    """
    如果 path 是目录，尝试寻找 README.md 并提取简要说明；
    如果是文件（如 README.md），直接提取说明。
    优先读取第一行非空文字，或一级标题后的首行说明。
    """
    if os.path.isdir(path):
        readme_path = os.path.join(path, "README.md")
    else:
        readme_path = path

    if not os.path.isfile(readme_path):
        return ""

    try:
        with open(readme_path, "r", encoding="utf-8") as f:
            lines = [line.strip() for line in f.readlines()]

        content_lines = [l for l in lines if l]
        if not content_lines:
            return ""

        first = content_lines[0]
        if first.startswith("#"):
            title = first.lstrip("#").strip()
            if len(content_lines) > 1 and not content_lines[1].startswith("#"):
                return content_lines[1]
            return title
        return first
    except Exception:
        return ""

# -----------------------------------------------------------------------------
# 1. 顶层自省 (make list)
# -----------------------------------------------------------------------------
def cmd_list_suites():
    print("\n" + "=" * 70)
    print("           DC-Chip 验证体系与测试范畴 (Verification Suites)")
    print("=" * 70)
    print("  make test         - 运行默认的 unit、infra 与 software 三层完整回归")
    print("")
    print("  1. testunit       - 硬件单测与静态测试 (RTL Module Testbenches & Lint)")
    print("                      基于 Icarus Verilog 与 Verilator Lint 的白盒电路自检。")
    print("                      查看列表: make testunit list")
    print("                      全量运行: make testunit batch")
    print("                      指定运行: make testunit ALL=alu,uart,core")
    print("")
    print("  2. testinfra      - 仿真基础设施测试 (Simulator Engine, Memory & Models)")
    print("                      测试 C++ 内存模型、反汇编器、RefModel 与仿真命令行。")
    print("                      查看列表: make testinfra list")
    print("                      全量运行: make testinfra batch")
    print("                      指定运行: make testinfra ALL=memory,reference")
    print("")
    print("  3. sw tests       - 系统级软件测试 (C Programs on Complete SoC)")
    print("                      真实编译 RV32E 固件并在包含 CPU+总线+外设的完整 SoC 上执行。")
    print("                      受 Kconfig 特性控制 (自动编入并运行 Difftest/Wave/SDB 等)。")
    print("                      查看列表: make sw tests list")
    print("                      按配置运行: make sw tests")
    print("                      自动批处理: make sw tests batch")
    print("                      临时关闭: make sw tests sdboff nvboardoff waveoff")
    print("                      指定运行: make sw tests ALL=cpu_fib,uart_hello")
    print("")
    print("  4. sw demo        - 面向展示的交互式软件演示")
    print("                      查看列表: make sw demo list")
    print("                      构建镜像: make sw demo build")
    print("                      交互运行: make sw demo run")
    print("")
    print("  5. sw riscv-tests - RISC-V 体系结构合规测试套件 (预留，当前不可执行)")
    print("                      查看列表: make sw riscv-tests list")
    print("----------------------------------------------------------------------")
    print("  提示: testunit/testinfra 默认 batch；裸 sw tests 完全服从 .config。")
    print("=" * 70 + "\n")

# -----------------------------------------------------------------------------
# 2. 硬件单测 (testunit)
# -----------------------------------------------------------------------------
UNIT_TESTS = [
    {
        "name": "alu",
        "make_target": "_test-unit-alu",
        "default_desc": "算术逻辑单元运算、位移与分支比较标志位自检",
    },
    {
        "name": "decoder",
        "make_target": "_test-unit-decoder",
        "default_desc": "RV32E 37条基础指令译码、立即数重组与非法指令识别自检",
    },
    {
        "name": "regfile",
        "make_target": "_test-unit-regfile",
        "default_desc": "通用寄存器堆 (x0--x15) 读写、内部旁路与 x0 写保护自检",
    },
    {
        "name": "core",
        "make_target": "_test-unit-core",
        "default_desc": "顺序 CPU 核心取指、译码、执行、访存、提交与 fault 自检",
    },
    {
        "name": "led",
        "make_target": "_test-unit-led",
        "default_desc": "16位 MMIO LED 控制器读写、字节使能与管脚输出自检",
    },
    {
        "name": "uart",
        "make_target": "_test-unit-uart",
        "default_desc": "MMIO UART 控制器 16字节 FIFO、波特率分频与收发移位自检",
    },
    {
        "name": "buttons",
        "make_target": "_test-unit-buttons",
        "default_desc": "21位 MMIO Buttons 输入同步、可选去抖与只读访问自检",
    },
    {
        "name": "seg7",
        "make_target": "_test-unit-seg7",
        "default_desc": "8位十六进制七段数码管 MMIO 读写、字节使能与全字形译码自检",
    },
    {
        "name": "periph-interconnect",
        "make_target": "_test-unit-periph-interconnect",
        "default_desc": "1-to-N 外设总线路由器地址分流与未映射地址总线错误自检",
    },
    {
        "name": "cdc",
        "make_target": "_test-unit-cdc",
        "default_desc": "CPU 与外设跨时钟域 MMIO 握手桥异步四相翻转自检",
    },
    {
        "name": "interconnect",
        "make_target": "_test-unit-interconnect",
        "default_desc": "SoC 内存与外设地址空间译码分流与 access fault 契约自检",
    },
    {
        "name": "soc",
        "make_target": "_test-unit-soc",
        "default_desc": "完整 SoC 顶层单步集成、指令取指与 DRAM 访存时序自检",
    },
    {
        "name": "lint",
        "make_target": "_test-unit-lint",
        "default_desc": "Verilator 静态代码规则检查 (ISA/Comb/Core/Mem 全模块)",
    },
]

def list_unit_tests():
    print("\n" + "=" * 70)
    print("      [Layer 1: 硬件单测与静态测试清单 (make testunit list)]")
    print("=" * 70)
    for t in UNIT_TESTS:
        desc = t["default_desc"]
        print(f"  - {t['name']:<22} : {desc}")
    print("----------------------------------------------------------------------")
    print("用法示例:")
    print("  make testunit batch             # 运行全部硬件单测与 Lint")
    print("  make testunit ALL=alu,uart,core # 仅运行指定的单测")
    print("=" * 70 + "\n")

def run_unit_tests(filter_str=None, make_command="make"):
    selected = select_tests(UNIT_TESTS, filter_str, "testunit")

    print(f"\n>>> 开始执行硬件单测 (共 {len(selected)} 项)...")
    passed = 0
    start_all = time.time()

    for idx, t in enumerate(selected, 1):
        name = t["name"]
        print(f"  [{idx}/{len(selected)}] {name:<22} ... ", end="", flush=True)
        t0 = time.time()

        cmd = [make_command, "--no-print-directory", "ALL=", t["make_target"]]

        res = subprocess.run(cmd, cwd=REPO_ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        dt = time.time() - t0

        if res.returncode == 0:
            print(f"PASS ({dt:.2f}s)")
            passed += 1
        else:
            print(f"FAIL ({dt:.2f}s)")
            print(f"\n--- {name} 失败日志 ---")
            print(res.stdout)
            print(res.stderr)
            print("-------------------------\n")
            sys.exit(1)

    total_time = time.time() - start_all
    print(f">>> 硬件单测全数通过: {passed}/{len(selected)} PASS (耗时 {total_time:.2f}s)\n")

# -----------------------------------------------------------------------------
# 3. 基础设施测试 (testinfra)
# -----------------------------------------------------------------------------
INFRA_TESTS = [
    {"name": "make-cli", "make_target": "_test-infra-make-cli", "desc": "Make 公开命令、分层语法、错误前置校验与旧接口移除自检"},
    {"name": "repo-rules", "make_target": "_test-infra-repo-rules", "desc": "Markdown 链接、临时文档隔离与 tracked/index 规则自检"},
    {"name": "config", "make_target": "_test-infra-config", "desc": "Kconfig 选项解析、依赖图同步与头文件生成机制测试"},
    {"name": "isa", "make_target": "_test-infra-isa", "desc": "RV32E 编码宏、硬件译码器与反汇编器跨工具一致性测试"},
    {"name": "disasm", "make_target": "_test-infra-disasm", "desc": "C++ 反汇编引擎格式化字符串与操作数提取自检"},
    {"name": "memory", "make_target": "_test-infra-memory", "desc": "双端口仿真内存模型多 byte-lane、掩码与边界自检"},
    {"name": "reference", "make_target": "_test-infra-reference", "desc": "C++ 体系结构黄金模型 (ReferenceModel) 指令行为自检"},
    {"name": "simulation", "make_target": "_test-infra-simulation", "desc": "Verilator 仿真步进引擎状态机、快照与复位自检"},
    {"name": "difftest-engine", "make_target": "_test-infra-difftest-engine", "desc": "差分测试引擎断言、mismatch 捕获与 skip_ref 自检"},
    {"name": "integration", "make_target": "_test-infra-integration", "desc": "命令行 CLI、未对齐/非法指令异常注入正反例自检"},
    {"name": "wave", "make_target": "_test-infra-wave", "desc": "VCD 波形转储开关控制与文件完整性自检"},
    {"name": "sdb", "make_target": "_test-infra-sdb", "desc": "SDB 单步交互调试器断点与命令执行自检"},
    {"name": "unified-sim", "make_target": "_test-infra-unified-sim", "desc": "全特性单一 Vsim_top、NVBoard 产物隔离与运行时关闭组合自检"},
    {"name": "difftest-spike", "make_target": "_test-infra-difftest-spike", "default": False, "desc": "可选：使用官方 Spike backend 运行软件差分回归"},
]

def list_infra_tests():
    print("\n" + "=" * 70)
    print("      [Layer 2: 仿真基础设施测试清单 (make testinfra list)]")
    print("=" * 70)
    for t in INFRA_TESTS:
        marker = " [optional]" if not t.get("default", True) else ""
        print(f"  - {t['name']:<22} : {t['desc']}{marker}")
    print("----------------------------------------------------------------------")
    print("用法示例:")
    print("  make testinfra batch              # 运行全部基础设施测试")
    print("  make testinfra ALL=memory,reference # 仅运行指定基础设施测试")
    print("  make testinfra ALL=difftest-spike # 显式运行非默认 Spike 差分测试")
    print("=" * 70 + "\n")

def run_infra_tests(filter_str=None, make_command="make", build_dir=None, config_file=None):
    selected = select_tests(INFRA_TESTS, filter_str, "testinfra")

    print(f"\n>>> 开始执行基础设施测试 (共 {len(selected)} 项)...")
    passed = 0
    start_all = time.time()

    for idx, t in enumerate(selected, 1):
        name = t["name"]
        print(f"  [{idx}/{len(selected)}] {name:<22} ... ", end="", flush=True)
        t0 = time.time()

        cmd = [make_command, "--no-print-directory", "ALL="]
        if build_dir:
            cmd.append(f"BUILD_DIR={build_dir}")
        if config_file:
            cmd.append(f"CONFIG_FILE={config_file}")
        cmd.append(t["make_target"])
        res = subprocess.run(cmd, cwd=REPO_ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        dt = time.time() - t0

        if res.returncode == 0:
            print(f"PASS ({dt:.2f}s)")
            passed += 1
        else:
            print(f"FAIL ({dt:.2f}s)")
            print(f"\n--- {name} 失败日志 ---")
            print(res.stdout)
            print(res.stderr)
            print("-------------------------\n")
            sys.exit(1)

    total_time = time.time() - start_all
    print(f">>> 基础设施测试全数通过: {passed}/{len(selected)} PASS (耗时 {total_time:.2f}s)\n")

# -----------------------------------------------------------------------------
# 4. 全系统软件测试 (sw tests / sw riscv-tests)
# -----------------------------------------------------------------------------
def list_sw_suite(suite_dir, title, command_prefix="make sw tests", runnable=True,
                  examples=None):
    full_path = os.path.join(REPO_ROOT, suite_dir)
    print("\n" + "=" * 70)
    print(f"      [Layer 3: {title} ({suite_dir})]")
    print("=" * 70)

    if not os.path.isdir(full_path):
        print(f"  提示: 目录 {suite_dir} 尚未创建或为空")
        return

    items = sorted(os.listdir(full_path))
    test_dirs = [d for d in items if os.path.isdir(os.path.join(full_path, d))]

    if not test_dirs:
        print(f"  提示: {suite_dir} 暂无子测试项")
    else:
        for d in test_dirs:
            item_dir = os.path.join(full_path, d)
            summary = extract_readme_summary(item_dir)
            if summary:
                print(f"  - {d:<24} : {summary}")
            else:
                print(f"  - {d:<24}")

    print("----------------------------------------------------------------------")
    print("用法示例:")
    if examples is not None:
        for example in examples:
            print(f"  {example}")
    elif runnable:
        print(f"  {command_prefix} batch")
        print(f"  {command_prefix} ALL=cpu_fib,uart_hello")
    else:
        print(f"  {command_prefix} list  # 当前仅支持查看预留清单")
    print("=" * 70 + "\n")

def run_sw_tests(filter_str=None, simulator=None, test_dir=None, make_command="make",
                 build_dir=None, config_file=None, runtime_off=(), interactive=False):
    source_tests = [
        {"name": name}
        for name in sorted(os.listdir(os.path.join(REPO_ROOT, "sw/tests")))
        if os.path.isdir(os.path.join(REPO_ROOT, "sw/tests", name))
    ]
    selected = select_tests(source_tests, filter_str, "sw tests")
    test_names = [test["name"] for test in selected]

    sim_bin = simulator or os.path.join(REPO_ROOT, "build/verilator/Vsim_top")
    make_common = [make_command, "--no-print-directory", "ALL="]
    if build_dir:
        make_common.append(f"BUILD_DIR={build_dir}")
    if config_file:
        make_common.append(f"CONFIG_FILE={config_file}")

    print(">>> 检查当前 .config 对应的统一仿真器 ...", flush=True)
    subprocess.run([*make_common, "sim-build"], cwd=REPO_ROOT, check=True)

    sw_dir = test_dir or os.path.join(REPO_ROOT, "build/sw/tests")
    missing_images = [
        name
        for name in test_names
        if not os.path.isfile(os.path.join(sw_dir, name, f"{name}.inst.bin"))
    ]
    if missing_images:
        print(f">>> 软件镜像未构建，正在调用 make sw ...")
        subprocess.run([*make_common, "sw"], cwd=REPO_ROOT, check=True)

    cmd = [
        sys.executable,
        os.path.join(REPO_ROOT, "scripts/run_sw_tests.py"),
        "--simulator", sim_bin,
        "--test-dir", sw_dir,
    ]
    for feature in runtime_off:
        cmd.append(f"--{feature}-off")
    if interactive:
        cmd.append("--interactive")

    if filter_str is not None:
        cmd.extend(test_names)

    print("\n>>> 调度全系统软件测试运行...", flush=True)
    res = subprocess.run(cmd, cwd=REPO_ROOT)
    if res.returncode != 0:
        sys.exit(res.returncode)

# -----------------------------------------------------------------------------
# CLI 入口
# -----------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="DC-Chip Test Runner & Introspection Tool")
    parser.add_argument("--list-suites", action="store_true", help="List all top-level test suites")
    parser.add_argument("--suite", choices=["unit", "infra", "sw-tests", "sw-demos", "riscv-tests"], help="Select suite")
    parser.add_argument("--list", action="store_true", help="List tests in selected suite")
    parser.add_argument("--batch", action="store_true", help="Run all tests in suite")
    parser.add_argument("--filter", default=None, help="Filter test names, comma-separated")
    parser.add_argument("--simulator", default=None, help="Path to simulator binary")
    parser.add_argument("--test-dir", default=None, help="Path to built software tests")
    parser.add_argument("--build-dir", default=None, help="Build directory for private Make targets")
    parser.add_argument("--config-file", default=None, help="Configuration file for private Make targets")
    parser.add_argument("--make", default="make", help="Make executable used for internal targets")
    parser.add_argument("--sdb-off", action="store_true")
    parser.add_argument("--nvboard-off", action="store_true")
    parser.add_argument("--wave-off", action="store_true")
    parser.add_argument("--interactive", action="store_true")
    args = parser.parse_args()

    if args.list_suites:
        cmd_list_suites()
        return

    if not args.suite:
        cmd_list_suites()
        return

    if args.suite == "unit":
        if args.list:
            list_unit_tests()
        else:
            run_unit_tests(args.filter, make_command=args.make)

    elif args.suite == "infra":
        if args.list:
            list_infra_tests()
        else:
            run_infra_tests(
                args.filter,
                make_command=args.make,
                build_dir=args.build_dir,
                config_file=args.config_file,
            )

    elif args.suite == "sw-tests":
        if args.list:
            list_sw_suite("sw/tests", "全系统软件微测试清单 (sw tests)")
        else:
            run_sw_tests(args.filter,
                         simulator=args.simulator,
                         test_dir=args.test_dir,
                         make_command=args.make,
                         build_dir=args.build_dir,
                         config_file=args.config_file,
                         runtime_off=tuple(
                             name for name, enabled in (
                                 ("sdb", args.sdb_off),
                                 ("nvboard", args.nvboard_off),
                                 ("wave", args.wave_off),
                             ) if enabled
                         ),
                         interactive=args.interactive)

    elif args.suite == "riscv-tests":
        if args.list:
            list_sw_suite(
                "sw/riscv-tests",
                "RISC-V 体系结构合规测试套件 (sw riscv-tests)",
                command_prefix="make sw riscv-tests",
                runnable=False,
            )
        else:
            print("error: sw riscv-tests 尚未导入，当前只支持 make sw riscv-tests list", file=sys.stderr)
            sys.exit(2)

    elif args.suite == "sw-demos":
        if args.list:
            list_sw_suite("sw/demo", "交互式软件演示清单 (sw demo)",
                          command_prefix="make sw demo", runnable=True,
                          examples=("make sw demo list", "make sw demo build",
                                    "make sw demo run"))
        else:
            print("error: sw demo 目前只支持 make sw demo list", file=sys.stderr)
            sys.exit(2)

if __name__ == "__main__":
    main()
