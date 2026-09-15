# DC-Chip 构建配置说明

- 状态：现行构建配置契约
- 更新日期：2026-09-14
- 配置规范：仓库根目录 `Dconfig`
- 仿真器接口：[`simulator.md`](simulator.md)

## 1. 范围与默认值

当前配置系统把独立布尔选项传递给 Make 和 C++ 构建：

| 名称 | 默认值 | 当前状态 |
| --- | --- | --- |
| `DC_SIM_SDB` | `n` | `y` 时编译 SDB，reset 后默认进入交互模式 |
| `DC_SIM_WAVE` | `n` | `y` 时编译并启用 VCD；`n` 时不编译 VCD 支持 |
| `DC_SIM_NVBOARD` | `n` | `y` 时把 NVBoard 绑定、SDL 和归档编入唯一的 `Vsim_top` |
| `DC_SIM_DIFFTEST` | `n` | `y` 时将 ReferenceModel 与 Difftest 编入主仿真器，全程进行指令级锁步差分验证 |

tracked `configs/default_defconfig` 显式关闭这些选项。本地选择保存在被 Git
忽略的仓库根 `.config`。`DC_SIM_SDB=y` 时正式仿真器额外编译 SDB 与反汇编
实现；`make sw tests sdboff` 可在该构建中临时关闭交互入口。
`DC_SIM_DIFFTEST=y` 时所有运行模式均在公共执行循环中锁步运行差分测试。

`make sim-build` 直接使用生成的 `config.h`，始终只生成
`build/verilator/Vsim_top`。NVBoard 开启时，自动绑定文件位于
`build/verilator/`，第三方对象与 `nvboard.a` 位于 `build/tools/nvboard/`，
外部源码树保持只读。默认源码固定为仓库 submodule `tools/nvboard`，不读取通用
`NVBOARD_HOME`。只有显式传入 `DC_NVBOARD_HOME=<path>`（命令行或同名环境变量）时
才覆盖该来源，避免 ysyx-workbench 等外部环境意外改变 NVBoard 版本。

构建会在 `build/tools/nvboard/src/` 复制并严格应用仓库受控的兼容 patch；它使 GUI
UART 采样分频固定为 SoC 的 `BAUD_DIV=432`，并把字体和图片资源根编译为
`DC_NVBOARD_HOME`。兼容 patch 版本和源码根都写入构建戳；不兼容的 NVBoard 源码会在
构建时明确失败，不会静默回退到上游的 16 周期 UART 采样。

## 2. 人工入口

```bash
make defconfig
make menuconfig
make config-show
make testinfra ALL=config
```

- `defconfig` 用 tracked default defconfig 重置 `.config`，并同步生成物；
- `menuconfig` 在缺少 `.config` 时先生成默认配置，再启动仓库内固定版本的
  curses 界面，保存退出后执行同步；
- `config-show` 只显示有效值；缺少 `.config` 时在内存中读取默认值，不创建
  `.config` 或 `build/`；
- `make testinfra ALL=config` 只使用 `build/test-fixtures/config/` 下的配置和生成目录，不读写
  仓库根 `.config`。

## 3. 非交互入口

```text
python3 scripts/config.py [--config PATH] [--output-dir DIR] COMMAND
```

`PATH` 默认为仓库根 `.config`，`DIR` 默认为仓库根 `build/config`。即使从其他
工作目录调用，默认路径与 `Dconfig`、default defconfig 和 vendored Kconfiglib
仍由脚本位置解析。显式给出的相对路径按调用者当前工作目录解析。

```bash
python3 scripts/config.py default
python3 scripts/config.py set DC_SIM_SDB=y DC_SIM_WAVE=n
python3 scripts/config.py show
python3 scripts/config.py sync
```

- `default` 重置配置并生成输出；
- `set` 接受一个或多个不带 `CONFIG_` 前缀的 `NAME=y|n`。未知名称、重复名称、
  非小写布尔值、缺少 `=` 或不可满足赋值都会在写文件前失败；
- `show` 按 `Dconfig` 顺序输出两行 `CONFIG_<NAME>=n|y`，且始终只读；
- `sync` 在缺少配置时从 default defconfig 初始化，随后规范化 `.config` 并
  生成 Make/C++ 输出。

诊断写入 stderr，正常结果写入 stdout，输入或文件错误返回非零。同步内容未
改变时保留文件 mtime，避免无意义重编。

## 4. Make 与 C++ 传递

仿真相关目标按需生成：

```text
.config
build/config/auto.conf
build/config/config.h
```

只有仿真构建/运行目标及 `testunit`、`testinfra`、`sw tests` 在 Make 解析期间
按需加载 `auto.conf`。`help`、`list` 和独立 RTL 模块测试不会因为
配置系统自动创建 `.config` 或配置生成目录。正式 CLI 与独立 Simulation
引擎测试的 Verilator 编译和 C++17 syntax check 都使用
`-Ibuild/config -include config.h`，从同一头文件读取配置。

顶层 `make test` 在 `build/test-fixtures/full-regression/` 下生成并使用隔离的
默认配置和构建目录，不读取、不覆盖仓库根 `.config`，因此本地 SDB、WAVE、
NVBoard 或 Difftest 选择不会改变完整回归门禁。

`make testinfra` 使用相同原则，在 `build/test-fixtures/infra-regression/` 下运行；
其中 WAVE、SDB 与统一仿真器专项再创建各自的隔离配置。直接执行 `sim-build`
或 `sw tests` 时仍使用仓库根 `.config`。

`make clean` 仍只删除默认仓库根 `build/`，不会删除用户 `.config`。可用
`PYTHON=<python3>` 覆盖 Python 解释器；`make check-tools` 会检查 Python 3、
标准库 `curses`、原有 HDL 工具和 C++17 支持。

`make testinfra ALL=sdb` 自行在 `build/test-fixtures/sdb/` 下生成 SDB-off、SDB-only 和
SDB+WAVE 三套隔离配置与构建，不读取或修改仓库根 `.config`。SDB 关闭时，
正式仿真器不包含 `sdb.cpp`；若 Difftest 启用，仍会编入反汇编实现以格式化失配诊断。

## 5. 波形构建行为

`CONFIG_DC_SIM_WAVE=y` 时，Make 只为正式仿真器和独立 Simulation 引擎测试的
Verilator 命令增加 `--trace`，生成结果为 `VM_TRACE=1`、`VM_TRACE_VCD=1`。
关闭时二者均为 0，项目 C++ 不包含 VCD 头文件、接口或 dump 调用，也不编译、
链接 `verilated_vcd_c` 实现。

波形开启构建运行时，从真实可执行文件所在的 `<BUILD_DIR>/verilator*` 目录
推导并截断写入唯一的 `<BUILD_DIR>/dump.vcd`。详细生命周期和接口见
[`simulator.md`](simulator.md)。`make testinfra ALL=wave` 使用
`build/test-fixtures/wave/off/` 和 `on/` 下的隔离配置与构建目录，不修改仓库根
`.config`。

SDB 和 WAVE 同时启用时，`info wave`、`wave on` 与 `wave off` 控制同一个
recorder。`waveoff` 启动时不创建 VCD；此后在 SDB 中执行 `wave on` 才延迟创建
并开始记录。暂停不改变 DUT 状态、周期、提交或仿真时间。

## 6. 软件测试运行时修饰符

`make sw tests [ALL=...]` 完全服从 `.config`。可在不改配置的前提下附加
`sdboff`、`nvboardoff`、`waveoff`，三者可任意排序但不能重复。`batch` 严格
等价于同时给出三项关闭修饰符，不能与它们混用；difftest 没有运行时关闭通路。
`list` 不能与 `ALL`、`batch` 或关闭修饰符混用。旧 `BATCH=1`、`WAVE=0`、
`DIFFTEST=0` 入口均在执行测试前报错。

## 7. 固定第三方实现

配置实现使用 Kconfiglib v14.1.0，不依赖系统安装包或 ysyx-workbench。仓库只
保存 `kconfiglib.py`、`menuconfig.py`、ISC `LICENSE.txt` 和来源/校验说明；
版本、上游 URL、获取日期及 SHA-256 见
[`../../tools/kconfiglib/UPSTREAM.md`](../../tools/kconfiglib/UPSTREAM.md)。
