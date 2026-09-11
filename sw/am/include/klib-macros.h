#ifndef __KLIB_MACROS_H__
#define __KLIB_MACROS_H__

#include <stdint.h>

#define ROUNDUP(a, sz)   ((((uintptr_t)(a)) + ((sz) - 1)) & ~((uintptr_t)((sz) - 1)))
#define ROUNDDOWN(a, sz) (((uintptr_t)(a)) & ~((uintptr_t)((sz) - 1)))
#define LENGTH(arr)      (sizeof(arr) / sizeof((arr)[0]))
#define RANGE(st, ed)     (Area){ .start = (void *)(st), .end = (void *)(ed) }

#endif // __KLIB_MACROS_H__
