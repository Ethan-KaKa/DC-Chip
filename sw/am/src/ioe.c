#include <am.h>
#include <amdev.h>
#include <klib-macros.h>

#define MMIO_LED_ADDR         0x10000100u
#define MMIO_UART_TX_ADDR     0x10000000u
#define MMIO_UART_RX_ADDR     0x10000004u
#define MMIO_UART_STATUS_ADDR 0x10000008u

#define UART_STATUS_RX_READY  (1u << 0)
#define UART_STATUS_TX_READY  (1u << 1)

typedef void (*handler_t)(void *buf);

static void *read_lut[128];
static void *write_lut[128];

static void fail(void *buf) {
  (void)buf;
  halt(1);
}

static void __am_uart_config(AM_UART_CONFIG_T *cfg) {
  cfg->present = true;
}

static void __am_uart_tx(AM_UART_TX_T *uart) {
  volatile uint32_t *st = (volatile uint32_t *)MMIO_UART_STATUS_ADDR;
  while ((*st & UART_STATUS_TX_READY) == 0);
  *(volatile uint8_t *)MMIO_UART_TX_ADDR = (uint8_t)uart->data;
}

static void __am_uart_rx(AM_UART_RX_T *uart) {
  volatile uint32_t *st = (volatile uint32_t *)MMIO_UART_STATUS_ADDR;
  if (*st & UART_STATUS_RX_READY) {
    uart->data = (char)(*(volatile uint32_t *)MMIO_UART_RX_ADDR & 0xff);
  } else {
    uart->data = (char)0xff;
  }
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
  read_lut[AM_UART_CONFIG] = (void *)__am_uart_config;
  write_lut[AM_UART_TX]    = (void *)__am_uart_tx;
  read_lut[AM_UART_RX]     = (void *)__am_uart_rx;
  read_lut[AM_GPIO_LED]    = (void *)__am_gpio_led_read;
  write_lut[AM_GPIO_LED]   = (void *)__am_gpio_led_write;
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

void uart_write(char ch) {
  AM_UART_TX_T uart;
  uart.data = ch;
  ioe_write(AM_UART_TX, &uart);
}

int uart_read(char *ch) {
  volatile uint32_t *st = (volatile uint32_t *)MMIO_UART_STATUS_ADDR;
  if ((*st & UART_STATUS_RX_READY) && ch != NULL) {
    *ch = (char)(*(volatile uint32_t *)MMIO_UART_RX_ADDR & 0xff);
    return 1;
  }
  return 0;
}
