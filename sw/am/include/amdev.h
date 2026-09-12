#ifndef __AMDEV_H__
#define __AMDEV_H__

#include <stdint.h>
#include <stdbool.h>

#define AM_DEVREG(id, reg, perm, ...) \
  enum { AM_##reg = (id) }; \
  typedef struct { __VA_ARGS__; } AM_##reg##_T;

AM_DEVREG( 1, UART_CONFIG,  RD, bool present);
AM_DEVREG( 2, UART_TX,      WR, char data);
AM_DEVREG( 3, UART_RX,      RD, char data);
AM_DEVREG( 4, TIMER_CONFIG, RD, bool present, has_rtc);
AM_DEVREG( 5, TIMER_RTC,    RD, int year, month, day, hour, minute, second);
AM_DEVREG( 6, TIMER_UPTIME, RD, uint64_t us);
AM_DEVREG( 7, INPUT_CONFIG, RD, bool present);
AM_DEVREG( 8, INPUT_KEYBRD, RD, bool keydown; int keycode);
AM_DEVREG(25, GPIO_LED,     WR, uint32_t data);

#endif // __AMDEV_H__
