#include <am.h>
#include <amdev.h>
#include <klib-macros.h>

#define MMIO_LED_ADDR 0x10000100

typedef void (*handler_t)(void *buf);

static void *read_lut[128];
static void *write_lut[128];

static void fail(void *buf) {
  (void)buf;
  halt(1);
}

static void __am_gpio_led_read(AM_GPIO_LED_T *led) {
  volatile uint32_t *led_mmio = (volatile uint32_t *)MMIO_LED_ADDR;
  led->data = *led_mmio;
}

static void __am_gpio_led_write(AM_GPIO_LED_T *led) {
  volatile uint32_t *led_mmio = (volatile uint32_t *)MMIO_LED_ADDR;
  *led_mmio = led->data;
}

bool ioe_init(void) {
  for (size_t i = 0; i < LENGTH(read_lut); i++) {
    read_lut[i]  = (void *)fail;
    write_lut[i] = (void *)fail;
  }
  read_lut[AM_GPIO_LED]  = (void *)__am_gpio_led_read;
  write_lut[AM_GPIO_LED] = (void *)__am_gpio_led_write;
  return true;
}

void ioe_read(int reg, void *buf) {
  if (reg >= 0 && (size_t)reg < LENGTH(read_lut)) {
    ((handler_t)read_lut[reg])(buf);
  }
}

void ioe_write(int reg, void *buf) {
  if (reg >= 0 && (size_t)reg < LENGTH(write_lut)) {
    ((handler_t)write_lut[reg])(buf);
  }
}

void led_write(uint16_t val) {
  AM_GPIO_LED_T led;
  led.data = (uint32_t)val;
  ioe_write(AM_GPIO_LED, &led);
}

uint16_t led_read(void) {
  AM_GPIO_LED_T led;
  led.data = 0;
  ioe_read(AM_GPIO_LED, &led);
  return (uint16_t)(led.data & 0xffff);
}
