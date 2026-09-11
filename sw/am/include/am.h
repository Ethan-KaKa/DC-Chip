#ifndef __AM_H__
#define __AM_H__

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  void *start;
  void *end;
} Area;

extern Area heap;

void _trm_init(void);
void putch(char ch);

static inline void halt(int code) __attribute__((__noreturn__));
static inline void halt(int code) {
  __asm__ volatile (
    "sw %0, -16(zero)\n"
    "1: jalr zero, 0(ra)\n"
    :
    : "r"(code)
  );
  __builtin_unreachable();
}

#ifdef __cplusplus
}
#endif

#endif // __AM_H__
