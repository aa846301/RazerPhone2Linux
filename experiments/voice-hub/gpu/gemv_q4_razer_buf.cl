// gemv_q4_razer: 4-bit asymmetric GEMV (batch 1) tuned for Adreno 630 on Mesa rusticl/ir3.
// Drop-in for gemv_conv_c8_buf when QUANT_BIT == 4 && ASYMMETRIC && USE_IMAGE1D_INPUT.
// Same weight layout as MNN: chunk (c, g) = 16 bytes = 4 input channels x 8 outputs, 4 bits each,
// byte = (hi nibble -> output 2k, lo nibble -> output 2k+1). Weights are an RGBA int32 image2d
// (x = chunk, y = 8-output group) with USE_IMAGE, else a buffer of [groups][srcChannelC4] uint4.
// dequantScaleOffset: per quant block, per output channel (scale, offset) pairs.
// Work-group: RZ_L threads = (RZ_L / RZ_S) output groups x RZ_S slices of the quant blocks;
// per block the dequant is factored: sum(x*(q*s+o)) = s*sum(x*q) + o*sum(x).
#ifdef MNN_SUPPORT_FP16
#pragma OPENCL EXTENSION cl_khr_fp16 : enable
#endif

#ifndef RZ_L
#define RZ_L 64
#endif
#ifndef RZ_SB
#define RZ_SB 8
#endif
#ifndef RZ_SC
#define RZ_SC 2
#endif
#define RZ_S (RZ_SB * RZ_SC)
#define RZ_R (RZ_L / RZ_S)

__constant sampler_t RZ_SAMPLER = CLK_NORMALIZED_COORDS_FALSE | CLK_ADDRESS_CLAMP | CLK_FILTER_NEAREST;

inline float8 rz_unpack8(uint b4) {
    uint8 v = (uint8)(b4) >> (uint8)(4, 0, 12, 8, 20, 16, 28, 24);
    return convert_float8(v & (uint8)15);
}

__kernel __attribute__((reqd_work_group_size(RZ_L, 1, 1)))
void gemv_q4_razer(
#ifdef USE_IMAGE
                   __read_only image2d_t weight,
#else
                   __global const uint4 *weight,
#endif
                   __global const FLOAT *dequantScaleOffset,
                   __global const FLOAT *bias,
                   __read_only image1d_buffer_t input,
                   __global FLOAT *output,
                   __private const int srcChannelC4,
                   __private const int dstChannelC4,
                   __private const int groups8,
                   __private const int blockDim,
                   __private const float coefInv) {
    __local float8 red[RZ_L];
    const int lid = get_local_id(0);
    const int s = lid % RZ_S, r = lid / RZ_S;
    const int sb = s / RZ_SC, sc = s % RZ_SC;
    const int g = get_group_id(0) * RZ_R + r;
    const int cpb = blockDim >> 2;                     // 16-byte chunks per quant block
    const int nblk = (srcChannelC4 << 2) / blockDim;
    float8 acc = 0;
    if (g < groups8) {
#ifndef USE_IMAGE
        __global const uint4 *wr = weight + (size_t)g * srcChannelC4;
#endif
        for (int blk = sb; blk < nblk; blk += RZ_SB) {
            float8 raw = 0;
            float xs = 0;
            const int c0 = blk * cpb;
            #pragma unroll 4
            for (int u = sc; u < cpb; u += RZ_SC) {
#ifdef USE_IMAGE
                uint4 q = as_uint4(read_imagei(weight, RZ_SAMPLER, (int2)(c0 + u, g)));
#else
                uint4 q = wr[c0 + u];
#endif
                float4 x = convert_float4(RI_F(input, c0 + u));
                raw = mad((float8)x.s0, rz_unpack8(q.x), raw);
                raw = mad((float8)x.s1, rz_unpack8(q.y), raw);
                raw = mad((float8)x.s2, rz_unpack8(q.z), raw);
                raw = mad((float8)x.s3, rz_unpack8(q.w), raw);
                xs += x.s0 + x.s1 + x.s2 + x.s3;
            }
            float16 sf = convert_float16(vload16(0, dequantScaleOffset + (size_t)blk * dstChannelC4 * 8 + (g << 4)));
            acc = mad(sf.s02468ace * coefInv, raw, acc);
            acc = mad(sf.s13579bdf * coefInv, (float8)xs, acc);
        }
    }
#if RZ_S > 1
    red[lid] = acc;
    barrier(CLK_LOCAL_MEM_FENCE);
    for (int st = RZ_S / 2; st > 0; st >>= 1) {
        if (s < st) red[lid] += red[lid + st];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    if (s != 0 || g >= groups8) return;
    acc = red[lid];
#else
    if (g >= groups8) return;
#endif
    acc += convert_float8(vload8(g, bias));
#ifdef RELU
    acc = fmax(acc, (float8)0);
#endif
#ifdef RELU6
    acc = clamp(acc, (float8)0, (float8)6);
#endif
    vstore8(CONVERT_FLOAT8(acc), g, output);
}

// gemv_q8_razer: 8-bit asymmetric variant (same scheme). MNN 8-bit layout: chunk (c, g) = 16 signed bytes =
// 2 input channels x 8 outputs (s0..7 -> channel 2c, s8..f -> channel 2c+1); 2 chunks per C4 of input.
// Input is a plain FLOAT buffer (MNN only builds the image1d input for 4-bit).
__kernel __attribute__((reqd_work_group_size(RZ_L, 1, 1)))
void gemv_q8_razer(
#ifdef USE_IMAGE
                   __read_only image2d_t weight,
#else
                   __global const int4 *weight,
#endif
                   __global const FLOAT *dequantScaleOffset,
                   __global const FLOAT *bias,
                   __global const FLOAT *input,
                   __global FLOAT *output,
                   __private const int srcChannelC4,
                   __private const int dstChannelC4,
                   __private const int groups8,
                   __private const int blockDim,
                   __private const float coefInv) {
    __local float8 red[RZ_L];
    const int lid = get_local_id(0);
    const int s = lid % RZ_S, r = lid / RZ_S;
    const int sb = s / RZ_SC, sc = s % RZ_SC;
    const int g = get_group_id(0) * RZ_R + r;
    const int cpb = blockDim >> 1;                     // 16-byte chunks per quant block
    const int nblk = (srcChannelC4 << 2) / blockDim;
    float8 acc = 0;
    if (g < groups8) {
#ifndef USE_IMAGE
        __global const int4 *wr = weight + (size_t)g * srcChannelC4 * 2;
#endif
        for (int blk = sb; blk < nblk; blk += RZ_SB) {
            float8 raw = 0;
            float xs = 0;
            const int c0 = blk * cpb;
            #pragma unroll 4
            for (int u = sc; u < cpb; u += RZ_SC) {
#ifdef USE_IMAGE
                int4 q = read_imagei(weight, RZ_SAMPLER, (int2)(c0 + u, g));
#else
                int4 q = wr[c0 + u];
#endif
                float16 wv = convert_float16(as_char16(q));
                float2 x = convert_float2(vload2(c0 + u, input));
                raw = mad((float8)x.s0, wv.lo, raw);
                raw = mad((float8)x.s1, wv.hi, raw);
                xs += x.s0 + x.s1;
            }
            float16 sf = convert_float16(vload16(0, dequantScaleOffset + (size_t)blk * dstChannelC4 * 8 + (g << 4)));
            acc = mad(sf.s02468ace * coefInv, raw, acc);
            acc = mad(sf.s13579bdf * coefInv, (float8)xs, acc);
        }
    }
#if RZ_S > 1
    red[lid] = acc;
    barrier(CLK_LOCAL_MEM_FENCE);
    for (int st = RZ_S / 2; st > 0; st >>= 1) {
        if (s < st) red[lid] += red[lid + st];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    if (s != 0 || g >= groups8) return;
    acc = red[lid];
#else
    if (g >= groups8) return;
#endif
    acc += convert_float8(vload8(g, bias));
#ifdef RELU
    acc = fmax(acc, (float8)0);
#endif
#ifdef RELU6
    acc = clamp(acc, (float8)0, (float8)6);
#endif
    vstore8(CONVERT_FLOAT8(acc), g, output);
}
