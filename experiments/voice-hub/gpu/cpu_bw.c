// CPU read bandwidth reference: N threads each XOR-reduce a slice of a 448 MiB buffer, best of 5.
#include <arm_neon.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static const size_t BYTES = 448u << 20;
static uint8_t *buf; static int nth;
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }
static volatile uint64_t sink;

static void *work(void *arg) {
    long id = (long)arg; size_t per = BYTES / nth;
    const uint8_t *p = buf + id * per, *e = p + per;
    uint8x16_t a0 = vdupq_n_u8(0), a1 = a0, a2 = a0, a3 = a0;
    for (; p < e; p += 64) {
        a0 = veorq_u8(a0, vld1q_u8(p)); a1 = veorq_u8(a1, vld1q_u8(p + 16));
        a2 = veorq_u8(a2, vld1q_u8(p + 32)); a3 = veorq_u8(a3, vld1q_u8(p + 48));
    }
    a0 = veorq_u8(veorq_u8(a0, a1), veorq_u8(a2, a3));
    sink += vgetq_lane_u64(vreinterpretq_u64_u8(a0), 0);
    return NULL;
}

int main(int argc, char **argv) {
    nth = argc > 1 ? atoi(argv[1]) : 4;
    buf = aligned_alloc(4096, BYTES); memset(buf, 1, BYTES);
    double best = 1e9;
    for (int r = 0; r < 5; r++) {
        pthread_t t[16]; double t0 = now();
        for (long i = 0; i < nth; i++) pthread_create(&t[i], NULL, work, (void *)i);
        for (int i = 0; i < nth; i++) pthread_join(t[i], NULL);
        double dt = now() - t0; if (dt < best) best = dt;
    }
    printf("cpu threads=%d  %.2f ms  %.1f GB/s\n", nth, best * 1e3, BYTES / best / 1e9);
    return 0;
}
