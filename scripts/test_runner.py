#!/usr/bin/env python3
"""
scripts/test_runner.py

DC-Chip 统一自省与测试调度引擎。
支持:
  - make list (列出顶层三大验证范畴)
  - make testunit list | batch | ALL=alu,uart,...
  - make testinfra list | batch | ALL=memory,reference,...
  - make sw tests list | batch | ALL=cpu_fib,uart_hello,...
  - make sw riscv-tests list | batch | ALL=...
"""

import argparse
import os
import re
import subprocess
import sys
import time

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

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
    print("  1. testunit       - 硬件单测与静态测试 (RTL Module Testbenches & Lint)")
    print("                      基于 Icarus Verilog 与 Verilator Lint 的白盒电路自检。")
    print("                      查看列表: make testunit list")
    print("                      全量运行: make testunit batch")
    print("                      指定运行: make testunit ALL=alu,uart,core")
    print("")
    print("  2. testinfra      - 仿真基础设施测试 (Simulator Engine, Memory & Models)")
    print("                      测试 C++ 双端口内存模型、反汇编器、Spike/RefModel 及故障注入。")
    print("                      查看列表: make testinfra list")
    print("                      全量运行: make testinfra batch")
    print("                      指定运行: make testinfra ALL=memory,reference")
    print("")
    print("  3. sw tests       - 系统级软件测试 (C Programs on Complete SoC)")
    print("                      真实编译 RV32E 固件并在包含 CPU+总线+外设的完整 SoC 上执行。")
    print("                      受 Kconfig 特性控制 (自动编入并运行 Difftest/Wave/SDB 等)。")
    print("                      查看列表: make sw tests list")
    print("                      全量运行: make sw tests batch")
    print("                      指定运行: make sw tests ALL=cpu_fib,uart_hello")
    print("")
    print("  4. sw riscv-tests - RISC-V 体系结构合规测试套件 (架构扩展预留)")
    print("                      查看列表: make sw riscv-tests list")
    print("                      全量运行: make sw riscv-tests batch")
    print("----------------------------------------------------------------------")
    print("  提示: 直接运行 make testunit / make testinfra / make sw tests 默认执行 batch。")
    print("=" * 70 + "\n")

# -----------------------------------------------------------------------------
# 2. 硬件单测 (testunit)
# -----------------------------------------------------------------------------
UNIT_TESTS = [
    {
        "name": "alu",
        "target": "build/unit/tb_alu.vvp",
        "tb": "sim/tb/tb_alu.sv",
        "default_desc": "算术逻辑单元运算、位移与分支比较标志位自检",
    },
    {
        "name": "decoder",
        "target": "build/unit/tb_decoder.vvp",
        "tb": "sim/tb/tb_decoder.sv",
        "default_desc": "RV32E 37条基础指令译码、立即数重组与非法指令识别自检",
    },
    {
        "name": "regfile",
        "target": "build/unit/tb_regfile.vvp",
        "tb": "sim/tb/tb_regfile.sv",
        "default_desc": "通用寄存器堆 (x0--x15) 读写、内部旁路与 x0 写保护自检",
    },
    {
        "name": "core",
        "target": "build/unit/tb_cpu_core.vvp",
        "tb": "sim/tb/tb_cpu_core.sv",
        "default_desc": "单周期 CPU 核心取指、译码、执行与写回流水自检",
    },
    {
        "name": "led",
        "target": "build/unit/tb_led_controller.vvp",
        "tb": "sim/tb/tb_led_controller.sv",
        "default_desc": "16位 MMIO LED 控制器读写、字节使能与管脚输出自检",
    },
    {
        "name": "uart",
        "target": "build/unit/tb_uart_controller.vvp",
        "tb": "sim/tb/tb_uart_controller.sv",
        "default_desc": "MMIO UART 控制器 16字节 FIFO、波特率分频与收发移位自检",
    },
    {
        "name": "periph-interconnect",
        "target": "build/unit/tb_periph_interconnect.vvp",
        "tb": "sim/tb/tb_periph_interconnect.sv",
        "default_desc": "1-to-N 外设总线路由器地址分流与未映射地址总线错误自检",
    },
    {
        "name": "cdc",
        "target": "build/unit/tb_mmio_cdc_bridge.vvp",
        "tb": "sim/tb/tb_mmio_cdc_bridge.sv",
        "default_desc": "CPU 与外设跨时钟域 MMIO 握手桥异步四相翻转自检",
    },
    {
        "name": "interconnect",
        "target": "build/unit/tb_soc_interconnect.vvp",
        "tb": "sim/tb/tb_soc_interconnect.sv",
        "default_desc": "SoC 内存与外设地址空间译码分流与 access fault 契约自检",
    },
    {
        "name": "soc",
        "target": "build/unit/tb_dc_soc_top.vvp",
        "tb": "sim/tb/tb_dc_soc_top.sv",
        "default_desc": "完整 SoC 顶层单步集成、指令取指与 DRAM 访存时序自检",
    },
    {
        "name": "lint",
        "target": "lint",
        "tb": "",
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

def run_unit_tests(filter_str=None):
    selected = UNIT_TESTS
    if filter_str and filter_str != "batch" and filter_str != "all":
        names = [n.strip() for n in filter_str.split(",") if n.strip()]
        selected = [t for t in UNIT_TESTS if t["name"] in names]
        if not selected:
            print(f"error: 未匹配到任何指定的单测: {filter_str}", file=sys.stderr)
            sys.exit(1)

    print(f"\n>>> 开始执行硬件单测 (共 {len(selected)} 项)...")
    passed = 0
    start_all = time.time()

    for idx, t in enumerate(selected, 1):
        name = t["name"]
        print(f"  [{idx}/{len(selected)}] {name:<22} ... ", end="", flush=True)
        t0 = time.time()

        if name == "lint":
            cmd = ["make", "--no-print-directory", "lint-isa", "lint-comb", "lint", "lint-mem"]
        else:
            cmd = ["make", "--no-print-directory", f"test-{name}"]

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
    {"name": "config", "cmd": ["make", "--no-print-directory", "test-config"], "desc": "Kconfig 选项解析、依赖图同步与头文件生成机制测试"},
    {"name": "isa", "cmd": ["make", "--no-print-directory", "test-isa"], "desc": "RV32E 编码宏、硬件译码器与反汇编器跨工具一致性测试"},
    {"name": "disasm", "cmd": ["make", "--no-print-directory", "test-disasm"], "desc": "C++ 反汇编引擎格式化字符串与操作数提取自检"},
    {"name": "memory", "cmd": ["make", "--no-print-directory", "test-memory"], "desc": "双端口仿真内存模型多 byte-lane、掩码与边界自检"},
    {"name": "reference", "cmd": ["make", "--no-print-directory", "test-reference"], "desc": "C++ 体系结构黄金模型 (ReferenceModel) 指令行为自检"},
    {"name": "simulation", "cmd": ["make", "--no-print-directory", "test-simulation"], "desc": "Verilator 仿真步进引擎状态机、快照与复位自检"},
    {"name": "difftest-engine", "cmd": ["make", "--no-print-directory", "test-difftest"], "desc": "差分测试引擎断言、mismatch 捕获与 skip_ref 自检"},
    {"name": "integration", "cmd": ["make", "--no-print-directory", "test-integration"], "desc": "命令行 CLI、未对齐/非法指令异常注入正反例自检"},
    {"name": "wave", "cmd": ["make", "--no-print-directory", "test-wave"], "desc": "VCD 波形转储开关控制与文件完整性自检"},
    {"name": "sdb", "cmd": ["make", "--no-print-directory", "test-sdb"], "desc": "SDB 单步交互调试器断点与命令执行自检"},
]

def list_infra_tests():
    print("\n" + "=" * 70)
    print("      [Layer 2: 仿真基础设施测试清单 (make testinfra list)]")
    print("=" * 70)
    for t in INFRA_TESTS:
        print(f"  - {t['name']:<22} : {t['desc']}")
    print("----------------------------------------------------------------------")
    print("用法示例:")
    print("  make testinfra batch              # 运行全部基础设施测试")
    print("  make testinfra ALL=memory,reference # 仅运行指定基础设施测试")
    print("=" * 70 + "\n")

def run_infra_tests(filter_str=None):
    selected = INFRA_TESTS
    if filter_str and filter_str != "batch" and filter_str != "all":
        names = [n.strip() for n in filter_str.split(",") if n.strip()]
        selected = [t for t in INFRA_TESTS if t["name"] in names]
        if not selected:
            print(f"error: 未匹配到任何指定的基础设施测试: {filter_str}", file=sys.stderr)
            sys.exit(1)

    print(f"\n>>> 开始执行基础设施测试 (共 {len(selected)} 项)...")
    passed = 0
    start_all = time.time()

    for idx, t in enumerate(selected, 1):
        name = t["name"]
        print(f"  [{idx}/{len(selected)}] {name:<22} ... ", end="", flush=True)
        t0 = time.time()

        res = subprocess.run(t["cmd"], cwd=REPO_ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
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
def list_sw_suite(suite_dir, title):
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
    print(f"用法示例:")
    print(f"  make sw tests batch")
    print(f"  make sw tests ALL=cpu_fib,uart_hello")
    print("=" * 70 + "\n")

def run_sw_tests(filter_str=None, simulator=None, difftest_override=None, wave_override=None):
    sim_bin = simulator or os.path.join(REPO_ROOT, "build/verilator/Vsim_top")
    if not os.path.isfile(sim_bin):
        print(f">>> 仿真系统未构建，正在调用 make sim-build ...")
        subprocess.run(["make", "sim-build"], cwd=REPO_ROOT, check=True)

    sw_dir = os.path.join(REPO_ROOT, "build/sw/tests")
    if not os.path.isdir(sw_dir) or not os.listdir(sw_dir):
        print(f">>> 软件镜像未构建，正在调用 make sw ...")
        subprocess.run(["make", "sw"], cwd=REPO_ROOT, check=True)

    cmd = [
        sys.executable,
        os.path.join(REPO_ROOT, "scripts/run_sw_tests.py"),
        "--simulator", sim_bin,
        "--test-dir", sw_dir,
    ]

    env = os.environ.copy()
    if difftest_override in ("0", "off", "no"):
        env["DIFFTEST"] = "0"
    if wave_override in ("0", "off", "no"):
        env["WAVE"] = "0"

    if filter_str and filter_str not in ("batch", "all"):
        test_names = [n.strip() for n in filter_str.split(",") if n.strip()]
        cmd.extend(test_names)

    print(f"\n>>> 调度全系统软件测试运行...")
    res = subprocess.run(cmd, cwd=REPO_ROOT, env=env)
    if res.returncode != 0:
        sys.exit(res.returncode)

# -----------------------------------------------------------------------------
# CLI 入口
# -----------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="DC-Chip Test Runner & Introspection Tool")
    parser.add_argument("--list-suites", action="store_true", help="List all top-level test suites")
    parser.add_argument("--suite", choices=["unit", "infra", "sw-tests", "riscv-tests"], help="Select suite")
    parser.add_argument("--list", action="store_true", help="List tests in selected suite")
    parser.add_argument("--batch", action="store_true", help="Run all tests in suite")
    parser.add_argument("--filter", default=None, help="Filter test names, comma-separated")
    parser.add_argument("--simulator", default=None, help="Path to simulator binary")
    parser.add_argument("--difftest-override", default=None, help="Override difftest (e.g. 0/off)")
    parser.add_argument("--wave-override", default=None, help="Override waveform dump")
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
            run_unit_tests(args.filter or ("batch" if args.batch else None))

    elif args.suite == "infra":
        if args.list:
            list_infra_tests()
        else:
            run_infra_tests(args.filter or ("batch" if args.batch else None))

    elif args.suite == "sw-tests":
        if args.list:
            list_sw_suite("sw/tests", "全系统软件微测试清单 (sw tests)")
        else:
            run_sw_tests(args.filter or ("batch" if args.batch else None),
                         simulator=args.simulator,
                         difftest_override=args.difftest_override,
                         wave_override=args.wave_override)

    elif args.suite == "riscv-tests":
        if args.list:
            list_sw_suite("sw/riscv-tests", "RISC-V 体系结构合规测试套件 (sw riscv-tests)")
        else:
            print("提示: sw riscv-tests 扩展套件暂未导入，执行原型清单展示。")
            list_sw_suite("sw/riscv-tests", "RISC-V 体系结构合规测试套件 (sw riscv-tests)")

if __name__ == "__main__":
    main()
