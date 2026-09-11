#include "trap.h"

long long sub(long long a, long long b) {
  long long c = a - b;
  return c;
}

long long test_data[] = {0, 1, 2, 0x7fffffffffffffffLL, (long long)0x8000000000000000LL, (long long)0x8000000000000001LL, -2LL, -1LL};
long long ans[] = {
  0LL, -1LL, -2LL, (long long)0x8000000000000001LL, (long long)0x8000000000000000LL, 0x7fffffffffffffffLL, 2LL, 1LL,
  1LL, 0LL, -1LL, (long long)0x8000000000000002LL, (long long)0x8000000000000001LL, (long long)0x8000000000000000LL, 3LL, 2LL,
  2LL, 1LL, 0LL, (long long)0x8000000000000003LL, (long long)0x8000000000000002LL, (long long)0x8000000000000001LL, 4LL, 3LL,
  0x7fffffffffffffffLL, 0x7ffffffffffffffeLL, 0x7ffffffffffffffdLL, 0LL, -1LL, -2LL, (long long)0x8000000000000001LL, (long long)0x8000000000000000LL,
  (long long)0x8000000000000000LL, 0x7fffffffffffffffLL, 0x7ffffffffffffffeLL, 1LL, 0LL, -1LL, (long long)0x8000000000000002LL, (long long)0x8000000000000001LL,
  (long long)0x8000000000000001LL, (long long)0x8000000000000000LL, 0x7fffffffffffffffLL, 2LL, 1LL, 0LL, (long long)0x8000000000000003LL, (long long)0x8000000000000002LL,
  -2LL, -3LL, -4LL, 0x7fffffffffffffffLL, 0x7ffffffffffffffeLL, 0x7ffffffffffffffdLL, 0LL, -1LL,
  -1LL, -2LL, -3LL, (long long)0x8000000000000000LL, 0x7fffffffffffffffLL, 0x7ffffffffffffffeLL, 1LL, 0LL
};

#define NR_DATA LENGTH(test_data)

int main() {
  int i, j, ans_idx = 0;
  for (i = 0; i < (int)NR_DATA; i++) {
    for (j = 0; j < (int)NR_DATA; j++) {
      check(sub(test_data[i], test_data[j]) == ans[ans_idx++]);
    }
  }
  return 0;
}
