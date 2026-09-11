#ifndef __KLIB_H__
#define __KLIB_H__

#include <am.h>
#include <klib-macros.h>

#ifdef __cplusplus
extern "C" {
#endif

static inline void check(bool cond) {
  if (!cond) {
    halt(1);
  }
}

#ifdef __cplusplus
}
#endif

#endif // __KLIB_H__
