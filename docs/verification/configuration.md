# DC-Chip 构建配置说明

- 版本：v0.1
- 状态：仿真调试基础设施步骤 1 已实现
- 更新日期：2026-09-10
- 配置规范：仓库根目录 `Dconfig`
- 仿真器接口：[`simulator.md`](simulator.md)

## 1. 范围与默认值

当前配置系统只负责把两个独立布尔选项传递给 Make 和 C++ 构建：

| 名称 | 默认值 | 步骤 1 状态 |
| --- | --- | --- |
| `DC_SIM_SDB` | `n` | 可配置、可生成宏；SDB 功能尚未实现 |
| `DC_SIM_WAVE` | `n` | 可配置、可生成宏；VCD 功能尚未实现 |

tracked `configs/default_defconfig` 显式关闭两个选项。本地选择保存在被 Git
忽略的仓库根 `.config`，不得把当前开关值理解为 SDB 或波形已经可用。

## 2. 人工入口

```bash
make defconfig
make menuconfig
make config-show
make test-config
```

- `defconfig` 用 tracked default defconfig 重置 `.config`，并同步生成物；
- `menuconfig` 在缺少 `.config` 时先生成默认配置，再启动仓库内固定版本的
  curses 界面，保存退出后执行同步；
- `config-show` 只显示有效值；缺少 `.config` 时在内存中读取默认值，不创建
  `.config` 或 `build/`；
- `test-config` 只使用 `build/test-fixtures/config/` 下的配置和生成目录，不读写
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

只有 `sim-build`、`sim`、`test-integration` 和 `test` 在 Make 解析期间加载
`auto.conf`。`help`、lint 和独立模块测试不会因为配置系统自动创建 `.config`
或配置生成目录。Verilator 编译与独立 C++17 syntax check 都使用
`-Ibuild/config -include config.h`，从同一头文件读取配置。

`make clean` 仍只删除默认仓库根 `build/`，不会删除用户 `.config`。可用
`PYTHON=<python3>` 覆盖 Python 解释器；`make check-tools` 会检查 Python 3、
标准库 `curses`、原有 HDL 工具和 C++17 支持。

## 5. 固定第三方实现

配置实现使用 Kconfiglib v14.1.0，不依赖系统安装包或 ysyx-workbench。仓库只
保存 `kconfiglib.py`、`menuconfig.py`、ISC `LICENSE.txt` 和来源/校验说明；
版本、上游 URL、获取日期及 SHA-256 见
[`../../tools/kconfiglib/UPSTREAM.md`](../../tools/kconfiglib/UPSTREAM.md)。
