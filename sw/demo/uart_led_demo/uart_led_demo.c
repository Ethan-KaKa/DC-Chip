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

static bool handle_command(const char *command, bool *running, bool *left,
                           uint32_t *delay, uint16_t *pattern) {
  if (strcmp(command, "exit") == 0) {
    led_write(0);
    printf("Leaving UART LED demo.\n");
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
  uint32_t delay = 60000;
  uint32_t delay_left = 0;
  char command[16];
  size_t command_len = 0;

  ioe_init();
  printf("\nDC-Chip UART LED demo\n");
  printf("Type ? for help. Type exit and press Enter to quit.\n");
  show_status(running, left, delay);

  for (;;) {
    char ch;
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
