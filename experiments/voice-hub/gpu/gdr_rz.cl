
// linear_attn_gdr_decode_rz (razorphone2linux): decode-phase gated delta rule with coalesced state access.
// Work-group = one (batch, v-head): RZ_CT column threads (4 value columns each, adjacent threads read adjacent
// bytes of a state row) x RZ_RS row slices of d_k. Two small RZ_RS-way reductions instead of LOCAL_SIZE trees.
// Same arguments and math as linear_attn_gated_delta_rule with DECODE_PHASE.
#if defined(DECODE_PHASE) && defined(RZ_CT)
#ifndef RZ_RS
#define RZ_RS 4
#endif
__kernel void linear_attn_gdr_decode_rz(
    __global const FLOAT* conv_out,
    __global const FLOAT* gate,
    __global const FLOAT* beta_in,
    __global FLOAT* recurrent_state,
    __global FLOAT* attn_out,
    __private const int batch,
    __private const int conv_dim,
    __private const int seq_len,
    __private const int num_k_heads,
    __private const int num_v_heads,
    __private const int d_k,
    __private const int d_v,
    __private const int key_dim,
    __private const int val_dim,
    __private const int gqa_factor,
    __private const float q_scale
#ifdef GATE_FOLD
    , __global const float* gate_coef
    , __global const float* gate_bias
#endif
)
{
    __local float4 red[RZ_RS][RZ_CT];
    const int lid = get_local_id(0);
    const int c = lid % RZ_CT;           // column thread: value columns 4c..4c+3
    const int rs = lid / RZ_CT;          // row slice
    const int bh = get_global_id(1);
    const int h = bh % num_v_heads;
    const int b = bh / num_v_heads;
    const int k_head = h / gqa_factor;
    const int x = c << 2;
    const bool active = x < d_v;
    const int conv_base = b * conv_dim;
    float g_t = (float)(gate[linear_attn_gate_offset(b, 0, h, batch, seq_len, num_v_heads)]);
    float beta_raw = (float)(beta_in[linear_attn_beta_offset(b, 0, h, batch, seq_len, num_v_heads)]);
#ifdef GATE_FOLD
    g_t = linear_attn_gate_fold(g_t, h, gate_coef, gate_bias);
    beta_raw = linear_attn_beta_fold(beta_raw);
#endif
    const float decay = exp(g_t);
    const int rows = K_SIZE / RZ_RS;
    const int i0 = rs * rows;
    __global FLOAT* st = recurrent_state + (b * num_v_heads + h) * K_SIZE * d_v + x;
    __global const FLOAT* keyp = conv_out + conv_base + key_dim + k_head * K_SIZE;
    __global const FLOAT* qp = conv_out + conv_base + k_head * K_SIZE;

    // pass 1: s = sum_i decay * S[i] * k[i]
    float4 s = 0;
    if (active) {
        for (int i = i0; i < i0 + rows; i++) {
            s = mad(convert_float4(vload4(0, st + i * d_v)), (float4)((float)keyp[i]), s);
        }
    }
    red[rs][c] = s * decay;
    barrier(CLK_LOCAL_MEM_FENCE);
    s = 0;
    for (int j = 0; j < RZ_RS; j++) s += red[j][c];
    barrier(CLK_LOCAL_MEM_FENCE);

    // delta = beta * (v - s); pass 2: S'[i] = decay*S[i] + k[i]*delta, out = sum_i S'[i] * q[i] * q_scale
    float4 o = 0;
    if (active) {
        const float4 v = convert_float4(vload4(0, conv_out + conv_base + 2 * key_dim + h * d_v + x));
        const float4 delta = (float4)(beta_raw) * (v - s);
        for (int i = i0; i < i0 + rows; i++) {
            float4 ns = mad(convert_float4(vload4(0, st + i * d_v)), (float4)(decay), (float4)((float)keyp[i]) * delta);
            vstore4(CONVERT_FLOAT4(ns), 0, st + i * d_v);
            o = mad(ns, (float4)((float)qp[i] * q_scale), o);
        }
    }
    red[rs][c] = o;
    barrier(CLK_LOCAL_MEM_FENCE);
    if (rs == 0 && active) {
        for (int j = 1; j < RZ_RS; j++) o += red[j][c];
        const int out_offset = linear_attn_output_offset(b * num_v_heads + h, x >> 2, batch * num_v_heads, d_v);
        vstore4(CONVERT_FLOAT4(o), 0, attn_out + out_offset);
    }
}
#endif
