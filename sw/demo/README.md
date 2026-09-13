# Software demos

这里存放面向展示的交互式裸机程序，不属于 `sw/tests` 自动回归集合。

## `uart_led_demo`

通过 UART 终端控制 16 位 GPIO LED 流水灯。快捷键输入后回车即可执行；`exit`
需要输入完整单词后按回车：

| 命令 | 作用 |
| --- | --- |
| `s` | 启动/暂停 |
| `+` / `-` | 加速/减速 |
| `l` / `r` | 左移/右移 |
| `c` | 清灯 |
| `?` | 显示帮助 |
| `exit` | 清灯并退出程序 |

```bash
make sw demo list
make sw demo build
make sw demo run
```

`run` 需要 `.config` 启用 `DC_SIM_NVBOARD`，启动后点击 NVBoard UART 终端获得
输入焦点。真实 FPGA 使用同一字符协议；板卡综合、引脚和上板运行目前未验证。
