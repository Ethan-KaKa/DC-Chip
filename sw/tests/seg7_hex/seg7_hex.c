#include <am.h>
#include <klib.h>

#define MMIO_SEG7_ADDR 0x10000300u

int main(void) {
  volatile uint32_t *seg7_word = (volatile uint32_t *)MMIO_SEG7_ADDR;
  volatile uint8_t *seg7_byte = (volatile uint8_t *)MMIO_SEG7_ADDR;

  check(ioe_init());
  seg7_show_hex(0x89abcdefu);
  printf("SEG7 write/read: 0x%x\n", *seg7_word);
  check(*seg7_word == 0x89abcdefu);

  // Verify the AM register API and each byte lane share the same MMIO value.
  AM_GPIO_SEG7_T seg7 = { .data = 0 };
  ioe_read(AM_GPIO_SEG7, &seg7);
  check(seg7.data == 0x89abcdefu);

  seg7_byte[2] = 0x12u;
  check(*seg7_word == 0x8912cdefu);
  seg7_byte[0] = 0x34u;
  check(*seg7_word == 0x8912cd34u);

  led_write(0xa55au);
  check(led_read() == 0xa55au);
  printf("SEG7 self-test: 0x%x PASS\n", *seg7_word);
  return 0;
}
