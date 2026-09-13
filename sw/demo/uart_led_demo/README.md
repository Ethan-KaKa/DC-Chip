# uart_led_demo

UART 交互控制 16 位 GPIO LED 流水灯，同时支持 NVBoard 的 16 个 SW 和 5 个 Button Pad。

按钮采用按下沿触发，长按不会重复执行：

| 按钮 | 功能 |
|---|---|
| `SW0` / `SW8` / `BTNC` | 启动/暂停 |
| `SW1` / `SW9` / `BTNL` | 切换方向 |
| `SW2` / `SW10` / `BTNU` | 加速 |
| `SW3` / `SW11` / `BTND` | 减速 |
| `SW4` / `SW12` / `BTNR` | 清空 LED |
| `SW5` / `SW13` | 打印当前状态 |
| `SW6` / `SW14` | 重置流水灯图案 |
| `SW7` / `SW15` | 打印帮助 |

UART 命令仍然可用：`s` 启停、`+/-` 调速、`l/r` 切换方向、`c` 清灯、`?` 帮助、`exit` 退出。
