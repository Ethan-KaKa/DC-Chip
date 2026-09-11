#include <am.h>

const int ro_val = 100;
int rw_val = 200;
char byte_buf[4] = {0x11, 0x22, 0x33, 0x44};
int bss_val;

int main(const char *args) {
  (void)args;
  rw_val = rw_val + 42;          // 242
  byte_buf[1] = 0x55;            // 0x55 = 85
  bss_val = 10;                  // 10

  int diff1 = ro_val + (-100);                         // 0
  int diff2 = rw_val + (-242);                         // 0
  int diff3 = (int)(unsigned char)byte_buf[1] + (-85); // 0
  int diff4 = bss_val + (-10);                         // 0

  return diff1 + diff2 + diff3 + diff4;                // 0 on success
}
