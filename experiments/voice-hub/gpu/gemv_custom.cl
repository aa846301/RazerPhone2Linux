// Custom 4-bit asymmetric GEMV for Adreno 630 (Mesa rusticl/ir3), same weight layout as MNN's
// gemv_conv_c8_buf: weights [oc/8][ic/4] of 16-byte chunks; in a chunk, 4 bytes per input channel,
// each byte = (hi nibble -> output 2k, lo nibble -> output 2k+1) for 8 outputs.
// scale/offset: half pairs at so[blk * oc * 2 + o * 2 + {0,1}], quant block = 64 input channels.
// out[o] = sum_c x[c] * (q[o][c] * scale[o][blk] + offset[o][blk]) / coef
//        = sum_blk scale/coef * sum_c x[c]*q + offset/coef * sum_c x[c]       (factored per block)
// Work-group: L threads = R rows (8-output groups) x S slices of the input dimension.
#pragma OPENCL EXTENSION cl_khr_fp16 : enable

#ifndef S
#define S 4
#endif
#ifndef L
#define L 64
#endif
#define R (L / S)

inline float8 unpack8(uint b4) {  // 4 bytes -> 8 nibbles in output order
    uint8 v = (uint8)(b4) >> (uint8)(4, 0, 12, 8, 20, 16, 28, 24);
    return convert_float8(v & (uint8)15);
}

__kernel __attribute__((reqd_work_group_size(L, 1, 1)))
void gemv_q4(__global const uint4 *w, __global const half *so, __read_only image1d_buffer_t in,
             __global half *out, int ic, int oc, float coef_inv) {
    __local float8 red[L];
    const int lid = get_local_id(0);
    const int s = lid % S, r = lid / S;
    const int g = get_group_id(0) * R + r;           // 8-output group index
    const int nc4 = ic >> 2;                          // 16-byte chunks per row
    const int nblk = nc4 >> 4;                        // 64-channel quant blocks per row
    float8 acc = 0;
    if (g < (oc >> 3)) {
        __global const uint4 *wr = w + (size_t)g * nc4;
        for (int blk = s; blk < nblk; blk += S) {     // slices interleave by block
            float8 raw = 0; float xs = 0;
            const int c0 = blk << 4;
            #pragma unroll 4
            for (int u = 0; u < 16; u++) {
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
    if (s == 0 && g < (oc >> 3)) {
        for (int i = 1; i < S; i++) acc += red[lid + i];
        vstore8(convert_half8(acc), g, out);
    }
#else
    if (g < (oc >> 3)) vstore8(convert_half8(acc), g, out);
#endif
}

__kernel __attribute__((reqd_work_group_size(L, 1, 1)))
void gemv_q4_img(__read_only image2d_t w, __global const half *so, __read_only image1d_buffer_t in,
             __global half *out, int ic, int oc, float coef_inv) {
    __local float8 red[L];
    const int lid = get_local_id(0);
    const int s = lid % S, r = lid / S;
    const int g = get_group_id(0) * R + r;           // 8-output group index
    const int nc4 = ic >> 2;                          // 16-byte chunks per row
    const int nblk = nc4 >> 4;                        // 64-channel quant blocks per row
    float8 acc = 0;
    if (g < (oc >> 3)) {
                for (int blk = s; blk < nblk; blk += S) {     // slices interleave by block
            float8 raw = 0; float xs = 0;
            const int c0 = blk << 4;
            #pragma unroll 4
            for (int u = 0; u < 16; u++) {
                uint4 q = read_imageui(w, (int2)(c0 + u, g));
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
    if (s == 0 && g < (oc >> 3)) {
        for (int i = 1; i < S; i++) acc += red[lid + i];
        vstore8(convert_half8(acc), g, out);
    }
#else
    if (g < (oc >> 3)) vstore8(convert_half8(acc), g, out);
#endif
}


inline half8 unpack8h(uint b4) {  // 4 bytes -> 8 nibbles as half, via 1024+n exponent trick
    uint8 v = ((uint8)(b4) >> (uint8)(4, 0, 12, 8, 20, 16, 28, 24)) & (uint8)15;
    return as_half8(convert_ushort8(v) | (ushort8)0x6400) - (half8)1024.0h;
}

__kernel __attribute__((reqd_work_group_size(L, 1, 1)))
void gemv_q4h(__global const uint4 *w, __global const half *so, __read_only image1d_buffer_t in,
              __global half *out, int ic, int oc, float coef_inv) {
    __local float8 red[L];
    const int lid = get_local_id(0);
    const int s = lid % S, r = lid / S;
    const int g = get_group_id(0) * R + r;
    const int nc4 = ic >> 2, nblk = nc4 >> 4;
    float8 acc = 0;
    if (g < (oc >> 3)) {
        __global const uint4 *wr = w + (size_t)g * nc4;
        for (int blk = s; blk < nblk; blk += S) {
            half8 raw = 0; half4 xs4 = 0;
            const int c0 = blk << 4;
            #pragma unroll 4
            for (int u = 0; u < 16; u++) {
                uint4 q = wr[c0 + u];
                half4 x = read_imageh(in, c0 + u);
                raw = mad((half8)x.s0, unpack8h(q.x), raw);
                raw = mad((half8)x.s1, unpack8h(q.y), raw);
                raw = mad((half8)x.s2, unpack8h(q.z), raw);
                raw = mad((half8)x.s3, unpack8h(q.w), raw);
                xs4 += x;
            }
            float xs = convert_float(xs4.s0) + convert_float(xs4.s1) + convert_float(xs4.s2) + convert_float(xs4.s3);
            float16 sf = convert_float16(vload16(0, so + (size_t)blk * oc * 2 + (g << 4)));
            acc = mad(sf.s02468ace * coef_inv, convert_float8(raw), acc);
            acc = mad(sf.s13579bdf * coef_inv, (float8)xs, acc);
        }
    }
#if S > 1
    red[lid] = acc;
    barrier(CLK_LOCAL_MEM_FENCE);
    if (s == 0 && g < (oc >> 3)) {
        for (int i = 1; i < S; i++) acc += red[lid + i];
        vstore8(convert_half8(acc), g, out);
    }
#else
    if (g < (oc >> 3)) vstore8(convert_half8(acc), g, out);
#endif
}


// Coalesced variant: every thread of a row visits every quant block; inside a block, slice s reads chunks
// s, s+S, ... so the S threads of a row touch S consecutive 16-byte chunks per load instruction.
__kernel __attribute__((reqd_work_group_size(L, 1, 1)))
void gemv_q4c(__global const uint4 *w, __global const half *so, __read_only image1d_buffer_t in,
              __global half *out, int ic, int oc, float coef_inv) {
    __local float8 red[L];
    const int lid = get_local_id(0);
    const int s = lid % S, r = lid / S;
    const int g = get_group_id(0) * R + r;
    const int nc4 = ic >> 2, nblk = nc4 >> 4;
    float8 acc = 0;
    if (g < (oc >> 3)) {
        __global const uint4 *wr = w + (size_t)g * nc4;
        for (int blk = 0; blk < nblk; blk++) {
            float8 raw = 0; float xs = 0;
            const int c0 = blk << 4;
            for (int u = s; u < 16; u += S) {
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
    if (s == 0 && g < (oc >> 3)) {
        for (int i = 1; i < S; i++) acc += red[lid + i];
        vstore8(convert_half8(acc), g, out);
    }
#else
    if (g < (oc >> 3)) vstore8(convert_half8(acc), g, out);
#endif
}
