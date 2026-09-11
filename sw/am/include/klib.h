#ifndef __KLIB_H__
#define __KLIB_H__

#include <am.h>
#include <klib-macros.h>

#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Assertion check
void check(bool cond);

// String manipulation
size_t strlen(const char *s);
char *strcpy(char *dst, const char *src);
char *strncpy(char *dst, const char *src, size_t n);
char *strcat(char *dst, const char *src);
int strcmp(const char *s1, const char *s2);
int strncmp(const char *s1, const char *s2, size_t n);

// Memory manipulation
void *memset(void *s, int c, size_t n);
void *memcpy(void *out, const void *in, size_t n);
void *memmove(void *dst, const void *src, size_t n);
int memcmp(const void *s1, const void *s2, size_t n);

#ifdef __cplusplus
}
#endif

#endif // __KLIB_H__
