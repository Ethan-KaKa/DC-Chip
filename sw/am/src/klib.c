#include <klib.h>

// Minimal klib functions for DC-Chip AM platform
void check(bool cond) {
  if (!cond) {
    halt(1);
  }
}

size_t strlen(const char *s) {
  size_t len = 0;
  while (s[len] != '\0') {
    len++;
  }
  return len;
}

char *strcpy(char *dst, const char *src) {
  size_t i = 0;
  while (src[i] != '\0') {
    dst[i] = src[i];
    i++;
  }
  dst[i] = '\0';
  return dst;
}

char *strncpy(char *dst, const char *src, size_t n) {
  size_t i = 0;
  while (i < n && src[i] != '\0') {
    dst[i] = src[i];
    i++;
  }
  while (i < n) {
    dst[i] = '\0';
    i++;
  }
  return dst;
}

char *strcat(char *dst, const char *src) {
  char *p = dst;
  while (*p != '\0') {
    p++;
  }
  while ((*p++ = *src++) != '\0') {
  }
  return dst;
}

int strcmp(const char *s1, const char *s2) {
  size_t i = 0;
  while (s1[i] != '\0' && s2[i] != '\0') {
    if ((unsigned char)s1[i] != (unsigned char)s2[i]) {
      return (unsigned char)s1[i] - (unsigned char)s2[i];
    }
    i++;
  }
  return (unsigned char)s1[i] - (unsigned char)s2[i];
}

int strncmp(const char *s1, const char *s2, size_t n) {
  size_t i = 0;
  while (i < n && s1[i] != '\0' && s2[i] != '\0') {
    if ((unsigned char)s1[i] != (unsigned char)s2[i]) {
      return (unsigned char)s1[i] - (unsigned char)s2[i];
    }
    i++;
  }
  if (i == n) {
    return 0;
  }
  return (unsigned char)s1[i] - (unsigned char)s2[i];
}

void *memset(void *s, int c, size_t n) {
  unsigned char *p = (unsigned char *)s;
  for (size_t i = 0; i < n; i++) {
    p[i] = (unsigned char)c;
  }
  return s;
}

void *memcpy(void *out, const void *in, size_t n) {
  unsigned char *dst = (unsigned char *)out;
  const unsigned char *src = (const unsigned char *)in;
  for (size_t i = 0; i < n; i++) {
    dst[i] = src[i];
  }
  return out;
}

void *memmove(void *dst, const void *src, size_t n) {
  unsigned char *d = (unsigned char *)dst;
  const unsigned char *s = (const unsigned char *)src;
  if (d < s) {
    for (size_t i = 0; i < n; i++) {
      d[i] = s[i];
    }
  } else if (d > s) {
    for (size_t i = n; i > 0; i--) {
      d[i - 1] = s[i - 1];
    }
  }
  return dst;
}

int memcmp(const void *s1, const void *s2, size_t n) {
  const unsigned char *p1 = (const unsigned char *)s1;
  const unsigned char *p2 = (const unsigned char *)s2;
  for (size_t i = 0; i < n; i++) {
    if (p1[i] != p2[i]) {
      return p1[i] - p2[i];
    }
  }
  return 0;
}

// -----------------------------------------------------------------------------
// Formatted Output Functions
// -----------------------------------------------------------------------------
struct fmt_out {
  char *buf;
  size_t max_len;
  size_t count;
};

static void fmt_putc(struct fmt_out *out, char c) {
  if (out->buf != NULL) {
    if (out->count + 1 < out->max_len) {
      out->buf[out->count] = c;
    }
  } else {
    putch(c);
  }
  out->count++;
}

static uint32_t udiv_mod(uint32_t dividend, uint32_t divisor, uint32_t *remainder) {
  if (divisor == 0) {
    if (remainder) *remainder = 0;
    return 0;
  }
  uint32_t quotient = 0;
  uint32_t rem = 0;
  for (int i = 31; i >= 0; i--) {
    rem = (rem << 1) | ((dividend >> (uint32_t)i) & 1u);
    if (rem >= divisor) {
      rem -= divisor;
      quotient |= (1u << (uint32_t)i);
    }
  }
  if (remainder) *remainder = rem;
  return quotient;
}

int vsnprintf(char *out, size_t n, const char *fmt, va_list ap) {
  struct fmt_out fo;
  fo.buf = out;
  fo.max_len = n;
  fo.count = 0;

  for (const char *p = fmt; *p != '\0'; p++) {
    if (*p != '%') {
      fmt_putc(&fo, *p);
      continue;
    }

    p++;
    if (*p == '\0') break;

    switch (*p) {
      case 'c': {
        char c = (char)va_arg(ap, int);
        fmt_putc(&fo, c);
        break;
      }
      case 's': {
        const char *s = va_arg(ap, const char *);
        if (s == NULL) s = "(null)";
        while (*s != '\0') {
          fmt_putc(&fo, *s++);
        }
        break;
      }
      case 'd': {
        int val = va_arg(ap, int);
        uint32_t uval;
        if (val < 0) {
          fmt_putc(&fo, '-');
          uval = (uint32_t)(-val);
        } else {
          uval = (uint32_t)val;
        }
        char num_buf[12];
        int idx = 0;
        if (uval == 0) {
          num_buf[idx++] = '0';
        } else {
          while (uval > 0) {
            uint32_t rem;
            uval = udiv_mod(uval, 10, &rem);
            num_buf[idx++] = (char)('0' + rem);
          }
        }
        for (int i = idx - 1; i >= 0; i--) {
          fmt_putc(&fo, num_buf[i]);
        }
        break;
      }
      case 'u': {
        uint32_t uval = va_arg(ap, uint32_t);
        char num_buf[12];
        int idx = 0;
        if (uval == 0) {
          num_buf[idx++] = '0';
        } else {
          while (uval > 0) {
            uint32_t rem;
            uval = udiv_mod(uval, 10, &rem);
            num_buf[idx++] = (char)('0' + rem);
          }
        }
        for (int i = idx - 1; i >= 0; i--) {
          fmt_putc(&fo, num_buf[i]);
        }
        break;
      }
      case 'x':
      case 'p': {
        uint32_t uval = va_arg(ap, uint32_t);
        char hex_buf[10];
        int idx = 0;
        if (uval == 0) {
          hex_buf[idx++] = '0';
        } else {
          while (uval > 0) {
            uint32_t nibble = uval & 0xfu;
            hex_buf[idx++] = (char)((nibble < 10) ? ('0' + nibble) : ('a' + nibble - 10));
            uval >>= 4;
          }
        }
        for (int i = idx - 1; i >= 0; i--) {
          fmt_putc(&fo, hex_buf[i]);
        }
        break;
      }
      case '%': {
        fmt_putc(&fo, '%');
        break;
      }
      default: {
        fmt_putc(&fo, '%');
        fmt_putc(&fo, *p);
        break;
      }
    }
  }

  if (out != NULL && n > 0) {
    if (fo.count < n) {
      out[fo.count] = '\0';
    } else {
      out[n - 1] = '\0';
    }
  }

  return (int)fo.count;
}

int vsprintf(char *out, const char *fmt, va_list ap) {
  return vsnprintf(out, (size_t)-1, fmt, ap);
}

int sprintf(char *out, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int ret = vsprintf(out, fmt, ap);
  va_end(ap);
  return ret;
}

int snprintf(char *out, size_t n, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int ret = vsnprintf(out, n, fmt, ap);
  va_end(ap);
  return ret;
}

int printf(const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int ret = vsnprintf(NULL, 0, fmt, ap);
  va_end(ap);
  return ret;
}
