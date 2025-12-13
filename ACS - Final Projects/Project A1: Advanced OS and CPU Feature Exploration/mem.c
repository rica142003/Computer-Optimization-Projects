// mem.c
#include <stdlib.h>
#include <stdio.h>
#include <time.h>

int main(int argc, char **argv) {
  size_t N = atol(argv[1]) * 1024 * 1024;
  char *a = malloc(N);
  for (size_t i = 0; i < N; i += 64) a[i]++;
  return 0;
}
