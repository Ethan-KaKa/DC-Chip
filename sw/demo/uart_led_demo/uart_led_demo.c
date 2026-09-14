#include <am.h>
#include <klib.h>

static inline void delay_cycles(uint32_t count) {
  asm volatile("1: addi %0, %0, -1\n   bnez %0, 1b\n" : "+r"(count));
}

static void print_help(void) {
  printf("\nCommands (press Enter for a command):\n");
  printf("  s       start/stop\n  +/-     change speed\n");
  printf("  l/r     shift left/right\n  c       clear LEDs\n");
  printf("  ?       show help\n  exit    leave demo\n\n");
}

static void show_status(bool running, bool left, uint32_t delay) {
  printf("status: %s, direction=%s, delay=%u\n",
         running ? "running" : "paused", left ? "left" : "right", delay);
}

#define INPUT_SW0       (1u << 0)
#define INPUT_SW1       (1u << 1)
#define INPUT_SW2       (1u << 2)
#define INPUT_SW3       (1u << 3)
#define INPUT_SW4       (1u << 4)
#define INPUT_SW5       (1u << 5)
#define INPUT_SW6       (1u << 6)
#define INPUT_SW7       (1u << 7)
#define INPUT_SW8       (1u << 8)
#define INPUT_SW9       (1u << 9)
#define INPUT_SW10      (1u << 10)
#define INPUT_SW11      (1u << 11)
#define INPUT_SW12      (1u << 12)
#define INPUT_SW13      (1u << 13)
#define INPUT_SW14      (1u << 14)
#define INPUT_SW15      (1u << 15)
#define INPUT_BTNC      (1u << 16)
#define INPUT_BTNU      (1u << 17)
#define INPUT_BTND      (1u << 18)
#define INPUT_BTNL      (1u << 19)
#define INPUT_BTNR      (1u << 20)

static void handle_button_event(uint32_t event, bool *running, bool *left,
                               uint32_t *delay, uint16_t *pattern) {
  if (event & (INPUT_SW0 | INPUT_SW8 | INPUT_BTNC)) {
    *running = !*running;
    printf("button 0: %s\n", *running ? "start" : "pause");
    show_status(*running, *left, *delay);
  }
  if (event & (INPUT_SW1 | INPUT_SW9 | INPUT_BTNL)) {
    *left = !*left;
    printf("button 1: direction %s\n", *left ? "left" : "right");
  }
  if (event & (INPUT_SW2 | INPUT_SW10 | INPUT_BTNU)) {
    if (*delay > 10000) *delay -= 10000;
    printf("button 2: faster\n");
    show_status(*running, *left, *delay);
  }
  if (event & (INPUT_SW3 | INPUT_SW11 | INPUT_BTND)) {
    if (*delay < 200000) *delay += 10000;
    printf("button 3: slower\n");
    show_status(*running, *left, *delay);
  }
  if (event & (INPUT_SW4 | INPUT_SW12 | INPUT_BTNR)) {
    *pattern = 1;
    led_write(0);
    printf("button 4: LEDs cleared.\n");
  }
  if (event & INPUT_SW5) {
    printf("button 5: ");
    show_status(*running, *left, *delay);
  }
  if (event & INPUT_SW6) {
    *pattern = 1;
    led_write(*pattern);
    printf("button 6: pattern reset.\n");
  }
  if (event & INPUT_SW7) {
    printf("button 7: help\n");
    print_help();
  }
}

static bool handle_command(const char *command, bool *running, bool *left,
                           uint32_t *delay, uint16_t *pattern) {
  if (strcmp(command, "exit") == 0) {
    led_write(0);
    seg7_show_hex(0);
    printf("Leaving UART LED/SEG7 demo.\n");
    return true;
  }
  if (strcmp(command, "s") == 0) {
    *running = !*running;
    show_status(*running, *left, *delay);
  } else if (strcmp(command, "+") == 0) {
    if (*delay > 10000) *delay -= 10000;
    show_status(*running, *left, *delay);
  } else if (strcmp(command, "-") == 0) {
    if (*delay < 200000) *delay += 10000;
    show_status(*running, *left, *delay);
  } else if (strcmp(command, "l") == 0) {
    *left = true;
    printf("direction: left\n");
  } else if (strcmp(command, "r") == 0) {
    *left = false;
    printf("direction: right\n");
  } else if (strcmp(command, "c") == 0) {
    *pattern = 1;
    led_write(0);
    printf("LEDs cleared.\n");
  } else if (strcmp(command, "?") == 0) {
    print_help();
  } else if (command[0] != '\0') {
    printf("unknown command: %s (try ?)\n", command);
  }
  return false;
}

int main(void) {
  bool running = true;
  bool left = true;
  uint16_t pattern = 1;
  uint32_t seg7_count = 0;
  uint32_t delay = 60000;
  uint32_t delay_left = 0;
  char command[16];
  size_t command_len = 0;
  uint32_t previous_buttons = 0;

  ioe_init();
  seg7_show_hex(seg7_count);
  previous_buttons = buttons_read();
  printf("\nDC-Chip UART LED/SEG7 demo\n");
  printf("Type ? for help. Type exit and press Enter to quit.\n");
  show_status(running, left, delay);

  for (;;) {
    char ch;
    uint32_t buttons = buttons_read();
    uint32_t button_events = buttons & ~previous_buttons;
    if (button_events != 0) {
      handle_button_event(button_events, &running, &left, &delay, &pattern);
    }
    previous_buttons = buttons;

    if (uart_read(&ch)) {
      if (ch == '\r' || ch == '\n') {
        putch('\n');
        command[command_len] = '\0';
        if (handle_command(command, &running, &left, &delay, &pattern)) return 0;
        command_len = 0;
      } else if (ch == '\b') {
        if (command_len > 0) {
          command_len--;
          printf("\b \b");
        }
      } else if (ch == 's' || ch == '+' || ch == '-' || ch == 'l' ||
                 ch == 'r' || ch == 'c' || ch == '?') {
        putch(ch);
        command[0] = ch;
        command[1] = '\0';
        if (handle_command(command, &running, &left, &delay, &pattern)) return 0;
      } else if (command_len + 1 < sizeof(command)) {
        command[command_len++] = ch;
        putch(ch);
      } else {
        printf("command too long\n");
        command_len = 0;
      }
    }

    if (running && delay_left == 0) {
      led_write(pattern);
      seg7_count++;
      seg7_show_hex(seg7_count);
      pattern = left ? (uint16_t)((pattern << 1) | (pattern >> 15))
                     : (uint16_t)((pattern >> 1) | (pattern << 15));
      delay_left = delay;
    } else if (delay_left > 1000) {
      delay_left -= 1000;
    } else {
      delay_left = 0;
    }
    delay_cycles(1000);
  }
}
