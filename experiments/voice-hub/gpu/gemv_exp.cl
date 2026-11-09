// Experiments on the razer 4-bit GEMV (buffer weights, image1d input, float accumulation).
// MODE 0: current kernel (SB x SC split, per-block factored dequant)
// MODE 1: same loads, no math (XOR the weights) -> shows the pure-memory time of this access pattern
// MODE 2: cheaper unpack: two masks per uint, nibbles kept in byte lanes, one convert per 4 values
// MODE 3: MODE 0 but loads of a whole block issued before any math (more reads in flight)
#pragma OPENCL EXTENSION cl_khr_fp16 : enable
#ifndef SB
#define SB 8
#endif
#ifndef SC
#define SC 2
#endif
#ifndef MODE
#define MODE 0
#endif
#define S (SB * SC)
#ifndef L
#define L 64
#endif
#define R (L / S)
#define CPB 16           /* 16-byte chunks per 64-channel quant block */
#define PER (CPB / SC)   /* chunks per thread per block */

inline float8 unpack8(uint b4) {
    uint8 v = (uint8)(b4) >> (uint8)(4, 0, 12, 8, 20, 16, 28, 24);
    return convert_float8(v & (uint8)15);
}

__kernel __attribute__((reqd_work_group_size(L, 1, 1)))
void gemv_q4(__global const uint4 *w, __global const half *so, __read_only image1d_buffer_t in,
             __global half *out, int ic, int oc, float coef_inv, __global const half *inb) {
    __local float8 red[L];
    const int lid = get_local_id(0);
#if MODE == 5
    __local half4 xl[1024];
    for (int i = lid; i < (ic >> 2); i += L) xl[i] = vload4(i, inb);
    barrier(CLK_LOCAL_MEM_FENCE);
#endif
    const int s = lid % S, r = lid / S;
    const int sb = s / SC, sc = s % SC;
    const int g = get_group_id(0) * R + r;
    const int nc4 = ic >> 2, nblk = nc4 >> 4;
    float8 acc = 0;
    if (g < (oc >> 3)) {
        __global const uint4 *wr = w + (size_t)g * nc4;
#if MODE == 1
        uint4 x4 = 0;
        for (int blk = sb; blk < nblk; blk += SB) {
            const int c0 = blk << 4;
            #pragma unroll
            for (int u = sc; u < CPB; u += SC) x4 ^= wr[c0 + u];
        }
        acc = convert_float8((uint8)(x4, x4));
#elif MODE == 11
        // integer path: the thread's inputs of a block are quantized to int16 with a per-thread-per-block scale,
        // nibble x input products use mad24 (no int->float convert per weight); one convert per block.
#define LDQ(i) const uint4 q##i = wr[c0 + sc + (i) * SC]; const float4 x##i = convert_float4(read_imageh(in, c0 + sc + (i) * SC));
#define MX(i) m = fmax(m, fmax(fmax(fabs(x##i.s0), fabs(x##i.s1)), fmax(fabs(x##i.s2), fabs(x##i.s3))));
#define NIB(b) as_int8(((uint8)(b) >> (uint8)(4, 0, 12, 8, 20, 16, 28, 24)) & (uint8)15)
#define MATHQ(i) { int4 xi = convert_int4_rte(x##i * qs); \
            iraw = mad24(NIB(q##i.x), (int8)xi.s0, iraw); iraw = mad24(NIB(q##i.y), (int8)xi.s1, iraw); \
            iraw = mad24(NIB(q##i.z), (int8)xi.s2, iraw); iraw = mad24(NIB(q##i.w), (int8)xi.s3, iraw); \
            xs += x##i.s0 + x##i.s1 + x##i.s2 + x##i.s3; }
        for (int blk = sb; blk < nblk; blk += SB) {
            int8 iraw = 0; float xs = 0, m = 0;
            const int c0 = blk << 4;
#if PER == 8
            LDQ(0) LDQ(1) LDQ(2) LDQ(3) LDQ(4) LDQ(5) LDQ(6) LDQ(7)
            MX(0) MX(1) MX(2) MX(3) MX(4) MX(5) MX(6) MX(7)
            const float qs = m > 0 ? 32767.0f / m : 0.0f;
            MATHQ(0) MATHQ(1) MATHQ(2) MATHQ(3) MATHQ(4) MATHQ(5) MATHQ(6) MATHQ(7)
#elif PER == 4
            LDQ(0) LDQ(1) LDQ(2) LDQ(3)
            MX(0) MX(1) MX(2) MX(3)
            const float qs = m > 0 ? 32767.0f / m : 0.0f;
            MATHQ(0) MATHQ(1) MATHQ(2) MATHQ(3)
#else
#error MODE 11 needs PER 4 or 8
#endif
            const float8 raw = convert_float8(iraw) * (m * (1.0f / 32767.0f));
            float16 sf = convert_float16(vload16(0, so + (size_t)blk * oc * 2 + (g << 4)));
            acc = mad(sf.s02468ace * coef_inv, raw, acc);
            acc = mad(sf.s13579bdf * coef_inv, (float8)xs, acc);
        }
#undef LDQ
#undef MATHQ
#elif MODE == 8 || MODE == 9
        // manual unroll: issue all PER weight (and input) loads of the block, then the math.
        // MODE 9 additionally does the nibble products in half precision per chunk (4 terms), summed in float.
#define LDQ(i) const uint4 q##i = wr[c0 + sc + (i) * SC]; const half4 h##i = read_imageh(in, c0 + sc + (i) * SC);
#if MODE == 8
#define MATHQ(i) { float4 x = convert_float4(h##i); \
            raw = mad((float8)x.s0, unpack8(q##i.x), raw); raw = mad((float8)x.s1, unpack8(q##i.y), raw); \
            raw = mad((float8)x.s2, unpack8(q##i.z), raw); raw = mad((float8)x.s3, unpack8(q##i.w), raw); \
            xs += x.s0 + x.s1 + x.s2 + x.s3; }
#else
#define UNPH(b) convert_half8(((uint8)(b) >> (uint8)(4, 0, 12, 8, 20, 16, 28, 24)) & (uint8)15)
#define MATHQ(i) { half8 t = (half8)(h##i.s0) * UNPH(q##i.x); t = mad((half8)(h##i.s1), UNPH(q##i.y), t); \
            t = mad((half8)(h##i.s2), UNPH(q##i.z), t); t = mad((half8)(h##i.s3), UNPH(q##i.w), t); \
            raw += convert_float8(t); float4 x = convert_float4(h##i); xs += x.s0 + x.s1 + x.s2 + x.s3; }
#endif
        for (int blk = sb; blk < nblk; blk += SB) {
            float8 raw = 0; float xs = 0;
            const int c0 = blk << 4;
#if PER == 8
            LDQ(0) LDQ(1) LDQ(2) LDQ(3) LDQ(4) LDQ(5) LDQ(6) LDQ(7)
            MATHQ(0) MATHQ(1) MATHQ(2) MATHQ(3) MATHQ(4) MATHQ(5) MATHQ(6) MATHQ(7)
#elif PER == 4
            LDQ(0) LDQ(1) LDQ(2) LDQ(3)
            MATHQ(0) MATHQ(1) MATHQ(2) MATHQ(3)
#elif PER == 16
            LDQ(0) LDQ(1) LDQ(2) LDQ(3) LDQ(4) LDQ(5) LDQ(6) LDQ(7)
            MATHQ(0) MATHQ(1) MATHQ(2) MATHQ(3) MATHQ(4) MATHQ(5) MATHQ(6) MATHQ(7)
            { LDQ(8) LDQ(9) LDQ(10) LDQ(11) LDQ(12) LDQ(13) LDQ(14) LDQ(15)
              MATHQ(8) MATHQ(9) MATHQ(10) MATHQ(11) MATHQ(12) MATHQ(13) MATHQ(14) MATHQ(15) }
#else
            LDQ(0) LDQ(1) MATHQ(0) MATHQ(1)
#endif
            float16 sf = convert_float16(vload16(0, so + (size_t)blk * oc * 2 + (g << 4)));
            acc = mad(sf.s02468ace * coef_inv, raw, acc);
            acc = mad(sf.s13579bdf * coef_inv, (float8)xs, acc);
        }
#else
        for (int blk = sb; blk < nblk; blk += SB) {
            float8 raw = 0; float xs = 0;
            const int c0 = blk << 4;
#if MODE == 3
            uint4 qq[PER];
            #pragma unroll
            for (int i = 0; i < PER; i++) qq[i] = wr[c0 + sc + i * SC];
#endif
            #pragma unroll
            for (int i = 0; i < PER; i++) {
                const int u = sc + i * SC;
#if MODE == 3
                uint4 q = qq[i];
#elif MODE == 10
                uint4 q = (uint4)(u * 0x9E3779B9u) ^ (uint4)(g, g + 1, g + 2, g + 3);
#else
                uint4 q = wr[c0 + u];
#endif
#if MODE == 6
                // weights + input + scales, trivial math
                float4 x = convert_float4(read_imageh(in, c0 + u));
                raw += (float8)(x.s0) * as_float(q.x & 0x3f800000u) + as_float(q.y & q.z & q.w & 0x3f800000u);
                continue;
#elif MODE == 7 || MODE == 10
                // MODE 7: weights + scales + full math, input from a register; MODE 10: no weight loads either
                float4 x = (float4)(coef_inv, coef_inv * 0.5f, coef_inv * 0.25f, coef_inv * 0.125f) + (float)u;
#elif MODE == 4
                float4 x = convert_float4(vload4(c0 + u, inb));
#elif MODE == 5
                float4 x = convert_float4(xl[c0 + u]);
#else
                float4 x = convert_float4(read_imageh(in, c0 + u));
#endif
#if MODE == 2
                // byte k of each uint: hi nibble -> output 2k, lo -> 2k+1.  Keep nibbles in byte lanes:
                // e = even outputs (0,2,4,6) as bytes, o = odd outputs (1,3,5,7) as bytes.
                uint4 e = (q >> 4) & 0x0F0F0F0Fu, o = q & 0x0F0F0F0Fu;
                float4 e0 = convert_float4(as_uchar4(e.x)), o0 = convert_float4(as_uchar4(o.x));
                float4 e1 = convert_float4(as_uchar4(e.y)), o1 = convert_float4(as_uchar4(o.y));
                float4 e2 = convert_float4(as_uchar4(e.z)), o2 = convert_float4(as_uchar4(o.z));
                float4 e3 = convert_float4(as_uchar4(e.w)), o3 = convert_float4(as_uchar4(o.w));
                float4 ev = x.s0 * e0 + x.s1 * e1 + x.s2 * e2 + x.s3 * e3;
                float4 ov = x.s0 * o0 + x.s1 * o1 + x.s2 * o2 + x.s3 * o3;
                raw += (float8)(ev.s0, ov.s0, ev.s1, ov.s1, ev.s2, ov.s2, ev.s3, ov.s3);
#else
                raw = mad((float8)x.s0, unpack8(q.x), raw);
                raw = mad((float8)x.s1, unpack8(q.y), raw);
                raw = mad((float8)x.s2, unpack8(q.z), raw);
                raw = mad((float8)x.s3, unpack8(q.w), raw);
#endif
                xs += x.s0 + x.s1 + x.s2 + x.s3;
            }
            float16 sf = convert_float16(vload16(0, so + (size_t)blk * oc * 2 + (g << 4)));
            acc = mad(sf.s02468ace * coef_inv, raw, acc);
            acc = mad(sf.s13579bdf * coef_inv, (float8)xs, acc);
        }
#endif
    }
#if S > 1
    red[lid] = acc;
    barrier(CLK_LOCAL_MEM_FENCE);
    for (int st = S / 2; st > 0; st >>= 1) {
        if (s < st) red[lid] += red[lid + st];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    if (s == 0 && g < (oc >> 3)) vstore8(convert_half8(red[lid]), g, out);
#else
    if (g < (oc >> 3)) vstore8(convert_half8(acc), g, out);
#endif
}
