// spin.c
#include <stdint.h>
#include <stdio.h>
#include <time.h>

static inline uint64_t ns() {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000000ull + t.tv_nsec;
}

int main() {
    volatile uint64_t x = 1;
    uint64_t t0 = ns();

    for (uint64_t i = 0; i < 2000000000ULL; i++)
        x = x * 1103515245 + 12345;

    uint64_t t1 = ns();

    FILE *f = fopen("timing.txt", "a");  // append mode
    if (!f) {
        perror("fopen");
        return 1;
    }

    fprintf(f, "%llu\n", (unsigned long long)(t1 - t0));
    fclose(f);

    return 0;
}
