#include <am.h>
#include <klib-macros.h>

extern char _heap_start;
extern char _heap_end;

Area heap = RANGE(&_heap_start, &_heap_end);

const char mainargs[1] = "";

void putch(char ch) {
  (void)ch;
  // MMIO UART will be mapped in the SoC phase.
}
