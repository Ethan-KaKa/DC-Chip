#include <am.h>
#include <klib-macros.h>

extern char _heap_start;
extern char _heap_end;

Area heap = RANGE(&_heap_start, &_heap_end);

const char mainargs[1] = "";

#define UART_TX_ADDR        0x10000000u
#define UART_STATUS_ADDR    0x10000008u
#define UART_STATUS_TX_RDY  (1u << 1)

void putch(char ch) {
  while ((*(volatile uint32_t *)UART_STATUS_ADDR & UART_STATUS_TX_RDY) == 0);
  *(volatile uint8_t *)UART_TX_ADDR = (uint8_t)ch;
}
