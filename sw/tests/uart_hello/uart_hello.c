#include <am.h>
#include <klib.h>

int main(void) {
  // 1. Test UART status register initially (FIFO is empty, tx_ready should be 1)
  volatile uint32_t *uart_st = (volatile uint32_t *)0x10000008u;
  uint32_t init_st = *uart_st;
  check((init_st & (1u << 1)) != 0);

  // 2. Direct character output via putch
  putch('[');
  putch('U');
  putch('A');
  putch('R');
  putch('T');
  putch(']');
  putch(' ');

  // 3. Formatted output via printf
  printf("Hello, RV32E UART! num=%d hex=0x%x str=%s\n", 12345, 0xabcd, "antigravity");

  // 4. Formatted string buffer via sprintf and verify with strcmp
  char buf[64];
  sprintf(buf, "test_%d_%x", 42, 0x5a);
  check(strcmp(buf, "test_42_5a") == 0);

  // 5. Test coexistence with LED peripheral
  volatile uint32_t *led_mmio = (volatile uint32_t *)0x10000100u;
  *led_mmio = 0xa5a5u;
  check((*led_mmio & 0xffffu) == 0xa5a5u);

  // 6. Test UART status register after burst: wait until TX is ready again
  while ((*uart_st & (1u << 1)) == 0) {
  }
  check((*uart_st & (1u << 1)) != 0);

  printf("UART self-test: PASS\n");
  check(true);
  return 0;
}
