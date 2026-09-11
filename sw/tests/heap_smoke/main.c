#include <am.h>

int main(const char *args) {
  (void)args;
  volatile int *p = (volatile int *)heap.start;
  *p = 42;
  volatile int val = *p;
  return val + (-42); // returns 0 on success
}
