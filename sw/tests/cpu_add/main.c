#include "trap.h"

int add(int a, int b) {
  int c = a + b;
  return c;
}

int test_data[] = {0, 1, 2, 0x7fffffff, (int)0x80000000, (int)0x80000001, -2, -1};
int ans[] = {
  0, 0x1, 0x2, 0x7fffffff, (int)0x80000000, (int)0x80000001, -2, -1,
  0x1, 0x2, 0x3, (int)0x80000000, (int)0x80000001, (int)0x80000002, -1, 0,
  0x2, 0x3, 0x4, (int)0x80000001, (int)0x80000002, (int)0x80000003, 0, 0x1,
  0x7fffffff, (int)0x80000000, (int)0x80000001, -2, -1, 0, 0x7ffffffd, 0x7ffffffe,
  (int)0x80000000, (int)0x80000001, (int)0x80000002, -1, 0, 0x1, 0x7ffffffe, 0x7fffffff,
  (int)0x80000001, (int)0x80000002, (int)0x80000003, 0, 0x1, 0x2, 0x7fffffff, (int)0x80000000,
  -2, -1, 0, 0x7ffffffd, 0x7ffffffe, 0x7fffffff, -4, -3,
  -1, 0, 0x1, 0x7ffffffe, 0x7fffffff, (int)0x80000000, -3, -2
};

#define NR_DATA LENGTH(test_data)

int main() {
  int i, j, ans_idx = 0;
  for (i = 0; i < (int)NR_DATA; i++) {
    for (j = 0; j < (int)NR_DATA; j++) {
      check(add(test_data[i], test_data[j]) == ans[ans_idx++]);
    }
    check(j == (int)NR_DATA);
  }

  check(i == (int)NR_DATA);
  return 0;
}
