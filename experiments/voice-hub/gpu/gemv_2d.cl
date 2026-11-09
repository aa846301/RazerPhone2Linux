// Generalized split: S = SB (quant-block interleave) x SC (chunks inside a block) threads per 8-output row group.
#pragma OPENCL EXTENSION cl_khr_fp16 : enable
#ifndef SB
#define SB 4
#endif
#ifndef SC
#define SC 2
#endif
#define S (SB * SC)
#ifndef L
#define L 64
#endif
#define R (L / S)

inline float8 unpack8(uint b4) {
    uint8 v = (uint8)(b4) >> (uint8)(4, 0, 12, 8, 20, 16, 28, 24);
    return convert_float8(v & (uint8)15);
}

__kernel __attribute__((reqd_work_group_size(L, 1, 1)))
void gemv_q4(__global const uint4 *w, __global const half *so, __read_only image1d_buffer_t in,
             __global half *out, int ic, int oc, float coef_inv) {
    __local float8 red[L];
    const int lid = get_local_id(0);
    const int s = lid % S, r = lid / S;
    const int sb = s / SC, sc = s % SC;
    const int g = get_group_id(0) * R + r;
    const int nc4 = ic >> 2, nblk = nc4 >> 4;
    float8 acc = 0;
    if (g < (oc >> 3)) {
        __global const uint4 *wr = w + (size_t)g * nc4;
        for (int blk = sb; blk < nblk; blk += SB) {
            float8 raw = 0; float xs = 0;
            const int c0 = blk << 4;
            #pragma unroll
            for (int u = sc; u < 16; u += SC) {
                uint4 q = wr[c0 + u];
                float4 x = convert_float4(read_imageh(in, c0 + u));
                raw = mad((float8)x.s0, unpack8(q.x), raw);
                raw = mad((float8)x.s1, unpack8(q.y), raw);
                raw = mad((float8)x.s2, unpack8(q.z), raw);
                raw = mad((float8)x.s3, unpack8(q.w), raw);
                xs += x.s0 + x.s1 + x.s2 + x.s3;
            }
            float16 sf = convert_float16(vload16(0, so + (size_t)blk * oc * 2 + (g << 4)));
            acc = mad(sf.s02468ace * coef_inv, raw, acc);
            acc = mad(sf.s13579bdf * coef_inv, (float8)xs, acc);
        }
    }
#if S > 1
    red[lid] = acc;
    barrier(CLK_LOCAL_MEM_FENCE);
    // tree over the S lanes of a row
    for (int st = S / 2; st > 0; st >>= 1) {
        if (s < st) red[lid] += red[lid + st];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    if (s == 0 && g < (oc >> 3)) vstore8(convert_half8(red[lid]), g, out);
#else
    if (g < (oc >> 3)) vstore8(convert_half8(acc), g, out);
#endif
}
