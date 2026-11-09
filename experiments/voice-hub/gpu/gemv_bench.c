// Standalone benchmark of MNN's gemv_conv_c8_buf (4-bit, asymmetric, fp16, image1d input, buffer weights)
// with real Qwen3.5-0.8B shapes. Variants are produced by editing the kernel source text (see main()).
#define CL_TARGET_OPENCL_VERSION 300
#include <CL/cl.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define CK(x) do { cl_int e_ = (x); if (e_) { printf("err %d at %s line %d\n", e_, #x, __LINE__); exit(1); } } while (0)
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }

static char *readfile(const char *p) {
    FILE *f = fopen(p, "rb"); if (!f) { perror(p); exit(1); }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    char *b = malloc(n + 1); fread(b, 1, n, f); b[n] = 0; fclose(f); return b;
}
static char *replace_all(const char *s, const char *a, const char *b) {
    size_t la = strlen(a), lb = strlen(b), cnt = 0;
    for (const char *p = strstr(s, a); p; p = strstr(p + la, a)) cnt++;
    char *out = malloc(strlen(s) + cnt * (lb > la ? lb - la : 0) + 1), *o = out;
    const char *p = s, *q;
    while ((q = strstr(p, a))) { memcpy(o, p, q - p); o += q - p; memcpy(o, b, lb); o += lb; p = q + la; }
    strcpy(o, p); return out;
}
static uint16_t f2h(float f) {  // float -> half (round to nearest, no denormals needed here)
    uint32_t x; memcpy(&x, &f, 4);
    uint32_t sign = (x >> 16) & 0x8000; int e = ((x >> 23) & 0xff) - 127 + 15; uint32_t m = x & 0x7fffff;
    if (e <= 0) return sign; if (e >= 31) return sign | 0x7c00;
    return sign | (e << 10) | ((m + 0x1000) >> 13);
}
static float h2f(uint16_t h) {
    uint32_t sign = (h & 0x8000) << 16, e = (h >> 10) & 0x1f, m = h & 0x3ff, x;
    if (e == 0) x = sign; else x = sign | ((e - 15 + 127) << 23) | (m << 13);
    float f; memcpy(&f, &x, 4); return f;
}

static const char *OPTS_BASE =
    "-DASYMMETRIC -DQUANT_BIT=4 -DMNN_SUPPORT_FP16 -DUSE_IMAGE1D_INPUT -DINPUT_CHANNEL_LEAVES_NUM=0 -DSET_ATTRIBUTE=false "
    "-DFLOAT=half -DFLOAT2=half2 -DFLOAT3=half3 -DFLOAT4=half4 -DFLOAT8=half8 -DFLOAT16=half16 "
    "-DCOMPUTE_FLOAT=half -DCOMPUTE_FLOAT2=half2 -DCOMPUTE_FLOAT3=half3 -DCOMPUTE_FLOAT4=half4 -DCOMPUTE_FLOAT8=half8 -DCOMPUTE_FLOAT16=half16 "
    "-DCONVERT_FLOAT=convert_half -DCONVERT_FLOAT2=convert_half2 -DCONVERT_FLOAT3=convert_half3 -DCONVERT_FLOAT4=convert_half4 "
    "-DCONVERT_FLOAT8=convert_half8 -DCONVERT_FLOAT16=convert_half16 "
    "-DCONVERT_COMPUTE_FLOAT=convert_half -DCONVERT_COMPUTE_FLOAT2=convert_half2 -DCONVERT_COMPUTE_FLOAT3=convert_half3 "
    "-DCONVERT_COMPUTE_FLOAT4=convert_half4 -DCONVERT_COMPUTE_FLOAT8=convert_half8 -DCONVERT_COMPUTE_FLOAT16=convert_half16 "
    "-DRI_F=read_imageh -DWI_F=write_imageh";

typedef struct { cl_context c; cl_device_id d; cl_command_queue q; } Ctx;

// returns microseconds per call; copies output into out (oc halves)
static double run(Ctx *x, const char *src, int wgs, int ic, int oc, const uint8_t *w, const uint16_t *so,
                  const uint16_t *in, uint16_t *out, int reps) {
    char opts[4096]; snprintf(opts, sizeof opts, "%s -DWGS=%d", OPTS_BASE, wgs);
    cl_int e;
    cl_program p = clCreateProgramWithSource(x->c, 1, &src, NULL, &e); CK(e);
    if (clBuildProgram(p, 1, &x->d, opts, NULL, NULL)) {
        char log[8192] = {0}; clGetProgramBuildInfo(p, x->d, CL_PROGRAM_BUILD_LOG, sizeof log - 1, log, NULL);
        printf("build failed:\n%s\n", log); exit(1);
    }
    cl_kernel k = clCreateKernel(p, "gemv_conv_c8_buf", &e); CK(e);
    size_t wbytes = (size_t)oc * ic / 2, nblk = ic / 64;
    cl_mem mw = clCreateBuffer(x->c, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR, wbytes, (void *)w, &e); CK(e);
    cl_mem mso = clCreateBuffer(x->c, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR, nblk * oc * 2 * 2, (void *)so, &e); CK(e);
    uint16_t *bias = calloc(oc, 2);
    cl_mem mb = clCreateBuffer(x->c, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR, oc * 2, bias, &e); CK(e);
    cl_mem mo = clCreateBuffer(x->c, CL_MEM_WRITE_ONLY, oc * 2, NULL, &e); CK(e);
    cl_mem mib = clCreateBuffer(x->c, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR, ic * 2, (void *)in, &e); CK(e);
    cl_image_format fmt = {CL_RGBA, CL_HALF_FLOAT};
    cl_image_desc desc; memset(&desc, 0, sizeof desc);
    desc.image_type = CL_MEM_OBJECT_IMAGE1D_BUFFER; desc.image_width = ic / 4; desc.buffer = mib;
    cl_mem mimg = clCreateImage(x->c, CL_MEM_READ_ONLY, &fmt, &desc, NULL, &e); CK(e);
    int g0 = wgs, g1 = oc / 8, ocb = oc / 4, icb = ic / 4, blockNum = nblk, blockDim = 64; float coef = 1.0f;
    int i = 0;
    CK(clSetKernelArg(k, i++, 4, &g0)); CK(clSetKernelArg(k, i++, 4, &g1)); CK(clSetKernelArg(k, i++, 4, &g1));
    CK(clSetKernelArg(k, i++, sizeof mimg, &mimg)); CK(clSetKernelArg(k, i++, sizeof mw, &mw));
    CK(clSetKernelArg(k, i++, sizeof mso, &mso)); CK(clSetKernelArg(k, i++, sizeof mb, &mb));
    CK(clSetKernelArg(k, i++, sizeof mo, &mo));
    CK(clSetKernelArg(k, i++, 4, &ocb)); CK(clSetKernelArg(k, i++, 4, &icb)); CK(clSetKernelArg(k, i++, 4, &ocb));
    CK(clSetKernelArg(k, i++, 4, &icb)); CK(clSetKernelArg(k, i++, 4, &ic)); CK(clSetKernelArg(k, i++, 4, &blockNum));
    CK(clSetKernelArg(k, i++, 4, &blockDim)); CK(clSetKernelArg(k, i++, 4, &coef));
    size_t gws[2] = {(size_t)g0, (size_t)g1}, lws[2] = {(size_t)wgs, 1};
    CK(clEnqueueNDRangeKernel(x->q, k, 2, NULL, gws, lws, 0, NULL, NULL)); CK(clFinish(x->q));
    double t0 = now();
    for (int r = 0; r < reps; r++) CK(clEnqueueNDRangeKernel(x->q, k, 2, NULL, gws, lws, 0, NULL, NULL));
    CK(clFinish(x->q));
    double us = (now() - t0) / reps * 1e6;
    CK(clEnqueueReadBuffer(x->q, mo, CL_TRUE, 0, oc * 2, out, 0, NULL, NULL));
    clReleaseMemObject(mimg); clReleaseMemObject(mib); clReleaseMemObject(mo); clReleaseMemObject(mb);
    clReleaseMemObject(mso); clReleaseMemObject(mw); clReleaseKernel(k); clReleaseProgram(p); free(bias);
    return us;
}

int main(int argc, char **argv) {
    if (argc < 3) { printf("usage: %s original.cl patched.cl\n", argv[0]); return 1; }
    char *orig = readfile(argv[1]), *pat = readfile(argv[2]);
    // V2: hoist 1/coef out of the loop (division -> multiply)
    char *v2a = replace_all(pat, "/ coef)", "* coef_inv)");
    char *v2 = replace_all(v2a, "const int lid = get_local_id(0);", "const int lid = get_local_id(0); const float coef_inv = 1.0f / coef;");
    // V3: no dequant scale/offset (wrong numbers; cost bound)
    char *v3a = replace_all(v2, "scale = scaleOffset.s02468ace;", "scale = (COMPUTE_FLOAT8)1;");
    char *v3 = replace_all(v3a, "offset = scaleOffset.s13579bdf;", "offset = (COMPUTE_FLOAT8)0;");
    Ctx x; cl_platform_id pl; cl_int e;
    CK(clGetPlatformIDs(1, &pl, NULL)); CK(clGetDeviceIDs(pl, CL_DEVICE_TYPE_GPU, 1, &x.d, NULL));
    x.c = clCreateContext(NULL, 1, &x.d, NULL, NULL, &e); CK(e);
    x.q = clCreateCommandQueueWithProperties(x.c, x.d, NULL, &e); CK(e);
    struct { int ic, oc; const char *what; } shapes[] = {{1024, 3584, "mlp up/gate (1024->3584)"}, {3584, 1024, "mlp down (3584->1024)"},
                                                         {1024, 1024, "attn proj (1024->1024)"}};
    srand(1);
    for (int s = 0; s < 3; s++) {
        int ic = shapes[s].ic, oc = shapes[s].oc; size_t wbytes = (size_t)oc * ic / 2, nblk = ic / 64;
        uint8_t *w = malloc(wbytes); for (size_t i = 0; i < wbytes; i++) w[i] = rand();
        uint16_t *so = malloc(nblk * oc * 2 * 2);
        for (size_t i = 0; i < nblk * oc * 2; i++) so[i] = f2h(i & 1 ? -0.05f : 0.01f * (1 + rand() % 5));
        uint16_t *in = malloc(ic * 2); for (int i = 0; i < ic; i++) in[i] = f2h((rand() % 200 - 100) / 100.0f);
        uint16_t *o0 = malloc(oc * 2), *o2 = malloc(oc * 2), *tmp = malloc(oc * 2);
        double ideal = wbytes / 16.9e9 * 1e6;  // at the 16.9 GB/s measured with aligned reads
        printf("== %s  weights %.2f MB, bandwidth-bound ideal %.0f us\n", shapes[s].what, wbytes / 1e6, ideal);
        int wgss[] = {64, 128, 256};
        for (int wi = 0; wi < 3; wi++) {
            int wgs = wgss[wi];
            double t0 = run(&x, orig, wgs, ic, oc, w, so, in, o0, 50);
            double t1 = run(&x, pat, wgs, ic, oc, w, so, in, tmp, 50);
            double t2 = run(&x, v2, wgs, ic, oc, w, so, in, o2, 50);
            double t3 = run(&x, v3, wgs, ic, oc, w, so, in, tmp, 50);
            double maxd = 0; for (int i = 0; i < oc; i++) { double dd = fabs(h2f(o0[i]) - h2f(o2[i])); if (dd > maxd) maxd = dd; }
            printf("  WGS=%3d  V0 orig %6.0f us | V1 aligned %6.0f | V2 +rcp %6.0f | V3 no-dequant %6.0f | V0-vs-V2 max diff %.4g\n",
                   wgs, t0, t1, t2, t3, maxd);
        }
        free(w); free(so); free(in); free(o0); free(o2); free(tmp);
    }
    return 0;
}
