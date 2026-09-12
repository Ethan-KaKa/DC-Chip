#include "trap.h"

static inline void delay_cycles(uint32_t count) {
  asm volatile(
    "1: addi %0, %0, -1\n"
    "   bnez %0, 1b\n"
    : "+r"(count)
  );
}

int main() {
  ioe_init();

  // Test 1: Direct write and readback using AM helper
  led_write(0x1234);
  check(led_read() == 0x1234);

  // Test 2: Direct write and readback using standard AM ioe_read / ioe_write
  AM_GPIO_LED_T led;
  led.data = 0x5678;
  ioe_write(AM_GPIO_LED, &led);
  led.data = 0;
  ioe_read(AM_GPIO_LED, &led);
  check(led.data == 0x5678);

  // Test 3: Visual Marquee Animation (running time >= 5s on NVBoard)
  // Each step delays 50,000 loop iterations (~100,000 clock cycles, ~57ms in NVBoard).
  // Total 96 steps * ~57ms = ~5.5s visible animation.
  const uint32_t step_delay = 50000;

  // Pattern 1: Rotate Left across 16 LEDs (2 full rotations, 32 steps)
  uint16_t pattern = 0x0001;
  for (int step = 0; step < 32; step++) {
    led_write(pattern);
    check(led_read() == pattern);
    delay_cycles(step_delay);
    pattern = (uint16_t)(((pattern << 1) | (pattern >> 15)) & 0xffff);
  }

  // Pattern 2: Rotate Right across 16 LEDs (2 full rotations, 32 steps)
  pattern = 0x8000;
  for (int step = 0; step < 32; step++) {
    led_write(pattern);
    check(led_read() == pattern);
    delay_cycles(step_delay);
    pattern = (uint16_t)(((pattern >> 1) | (pattern << 15)) & 0xffff);
  }

  // Pattern 3: Ping-Pong bouncing scanner (LD0 -> LD15 -> LD0, 32 steps)
  pattern = 0x0001;
  for (int step = 0; step < 16; step++) {
    led_write(pattern);
    check(led_read() == pattern);
    delay_cycles(step_delay);
    pattern = (uint16_t)(pattern << 1);
  }
  pattern = 0x8000;
  for (int step = 0; step < 16; step++) {
    led_write(pattern);
    check(led_read() == pattern);
    delay_cycles(step_delay);
    pattern = (uint16_t)(pattern >> 1);
  }

  // Final clear
  led_write(0x0000);
  check(led_read() == 0x0000);

  return 0;
}
