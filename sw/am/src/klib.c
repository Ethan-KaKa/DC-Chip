#include <klib.h>

// Minimal klib functions for DC-Chip AM platform
void check(bool cond) {
  if (!cond) {
    halt(1);
  }
}
