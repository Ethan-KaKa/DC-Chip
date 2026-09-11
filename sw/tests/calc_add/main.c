#include <am.h>

int main(const char *args) {
  (void)args;
  volatile int a = 15;
  volatile int b = 27;
  volatile int c = a + b;     // 42
  volatile int d = c + 10;    // 52
  volatile int e = d + (-52); // 0
  return e;
}
