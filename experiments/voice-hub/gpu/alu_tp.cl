// ALU throughput microbenchmarks for ir3/a630: 8 independent chains per thread, ITER iterations.
#ifndef ITER
#define ITER 256
#endif
// fma only
__kernel void k_fma(__global float *o, float a, float b) {
    float v0 = get_global_id(0), v1 = v0 + 1, v2 = v0 + 2, v3 = v0 + 3, v4 = v0 + 4, v5 = v0 + 5, v6 = v0 + 6, v7 = v0 + 7;
    for (int i = 0; i < ITER; i++) {
        v0 = mad(v0, a, b); v1 = mad(v1, a, b); v2 = mad(v2, a, b); v3 = mad(v3, a, b);
        v4 = mad(v4, a, b); v5 = mad(v5, a, b); v6 = mad(v6, a, b); v7 = mad(v7, a, b);
    }
    o[get_global_id(0)] = v0 + v1 + v2 + v3 + v4 + v5 + v6 + v7;
}
// nibble extract (shrm) + int->float convert (cov) + fma : current GEMV recipe
__kernel void k_cov(__global float *o, uint q, float b) {
    uint w = q ^ get_global_id(0);
    float v0 = 0, v1 = 0, v2 = 0, v3 = 0, v4 = 0, v5 = 0, v6 = 0, v7 = 0;
    for (int i = 0; i < ITER; i++) {
        w = w * 1664525u + 1013904223u;
        v0 = mad(b, (float)((w >> 4) & 15), v0);  v1 = mad(b, (float)(w & 15), v1);
        v2 = mad(b, (float)((w >> 12) & 15), v2); v3 = mad(b, (float)((w >> 8) & 15), v3);
        v4 = mad(b, (float)((w >> 20) & 15), v4); v5 = mad(b, (float)((w >> 16) & 15), v5);
        v6 = mad(b, (float)((w >> 28) & 15), v6); v7 = mad(b, (float)((w >> 24) & 15), v7);
    }
    o[get_global_id(0)] = v0 + v1 + v2 + v3 + v4 + v5 + v6 + v7;
}
// cov-free: move the nibble to mantissa bits 19..22 and OR the exponent of 1.0 -> value 1 + n/16
__kernel void k_magic(__global float *o, uint q, float b) {
    uint w = q ^ get_global_id(0);
    float v0 = 0, v1 = 0, v2 = 0, v3 = 0, v4 = 0, v5 = 0, v6 = 0, v7 = 0;
    const uint E = 0x3F800000u, M = 0x00780000u;
    for (int i = 0; i < ITER; i++) {
        w = w * 1664525u + 1013904223u;
        v0 = mad(b, as_float(((w << 15) & M) | E), v0); v1 = mad(b, as_float(((w << 19) & M) | E), v1);
        v2 = mad(b, as_float(((w << 7) & M) | E), v2);  v3 = mad(b, as_float(((w << 11) & M) | E), v3);
        v4 = mad(b, as_float(((w >> 1) & M) | E), v4);  v5 = mad(b, as_float(((w << 3) & M) | E), v5);
        v6 = mad(b, as_float(((w >> 9) & M) | E), v6);  v7 = mad(b, as_float(((w >> 5) & M) | E), v7);
    }
    o[get_global_id(0)] = v0 + v1 + v2 + v3 + v4 + v5 + v6 + v7;
}
// only the LCG + shrm (no convert, integer accumulate) to isolate the integer part
__kernel void k_int(__global uint *o, uint q) {
    uint w = q ^ get_global_id(0);
    uint v0 = 0, v1 = 0, v2 = 0, v3 = 0, v4 = 0, v5 = 0, v6 = 0, v7 = 0;
    for (int i = 0; i < ITER; i++) {
        w = w * 1664525u + 1013904223u;
        v0 += (w >> 4) & 15;  v1 += w & 15;  v2 += (w >> 12) & 15; v3 += (w >> 8) & 15;
        v4 += (w >> 20) & 15; v5 += (w >> 16) & 15; v6 += (w >> 28) & 15; v7 += (w >> 24) & 15;
    }
    o[get_global_id(0)] = v0 ^ v1 ^ v2 ^ v3 ^ v4 ^ v5 ^ v6 ^ v7;
}
