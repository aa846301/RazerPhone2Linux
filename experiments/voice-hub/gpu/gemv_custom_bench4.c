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


static double run_custom(Ctx *x, const char *src, int img, int S_, int L_, int ic, int oc, const uint8_t *w,
                         const uint16_t *so, const uint16_t *in, uint16_t *out, int reps) {
    char opts[256]; snprintf(opts, sizeof opts, "-DS=%d -DL=%d -cl-mad-enable", S_, L_);
    cl_int e; cl_program p = clCreateProgramWithSource(x->c, 1, &src, NULL, &e); CK(e);
    if (clBuildProgram(p, 1, &x->d, opts, NULL, NULL)) {
        char log[8192] = {0}; clGetProgramBuildInfo(p, x->d, CL_PROGRAM_BUILD_LOG, sizeof log - 1, log, NULL);
        printf("custom build failed:\n%s\n", log); exit(1);
    }
    cl_kernel k = clCreateKernel(p, img == 3 ? "gemv_q4c" : img == 2 ? "gemv_q4h" : img ? "gemv_q4_img" : "gemv_q4", &e); CK(e);
    size_t wbytes = (size_t)oc * ic / 2, nblk = ic / 64;
    cl_mem mw = clCreateBuffer(x->c, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR, wbytes, (void *)w, &e); CK(e);
    cl_mem mso = clCreateBuffer(x->c, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR, nblk * oc * 2 * 2, (void *)so, &e); CK(e);
    cl_mem mo = clCreateBuffer(x->c, CL_MEM_WRITE_ONLY, oc * 2, NULL, &e); CK(e);
    cl_mem mib = clCreateBuffer(x->c, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR, ic * 2, (void *)in, &e); CK(e);
    cl_image_format fmt = {CL_RGBA, CL_HALF_FLOAT}; cl_image_desc desc; memset(&desc, 0, sizeof desc);
    desc.image_type = CL_MEM_OBJECT_IMAGE1D_BUFFER; desc.image_width = ic / 4; desc.buffer = mib;
    cl_mem mimg = clCreateImage(x->c, CL_MEM_READ_ONLY, &fmt, &desc, NULL, &e); CK(e);
    float cinv = 1.0f;
    cl_mem wimg = NULL;
    if (img == 1) {
        cl_image_format f2 = {CL_RGBA, CL_UNSIGNED_INT32}; cl_image_desc d2; memset(&d2, 0, sizeof d2);
        d2.image_type = CL_MEM_OBJECT_IMAGE2D; d2.image_width = ic / 4; d2.image_height = oc / 8;
        d2.image_row_pitch = (size_t)(ic / 4) * 16; d2.buffer = mw;
        wimg = clCreateImage(x->c, CL_MEM_READ_ONLY, &f2, &d2, NULL, &e); CK(e);
        CK(clSetKernelArg(k, 0, sizeof wimg, &wimg));
    } else CK(clSetKernelArg(k, 0, sizeof mw, &mw)); CK(clSetKernelArg(k, 1, sizeof mso, &mso));
    CK(clSetKernelArg(k, 2, sizeof mimg, &mimg)); CK(clSetKernelArg(k, 3, sizeof mo, &mo));
    CK(clSetKernelArg(k, 4, 4, &ic)); CK(clSetKernelArg(k, 5, 4, &oc)); CK(clSetKernelArg(k, 6, 4, &cinv));
    int R_ = L_ / S_; size_t groups = ((oc / 8) + R_ - 1) / R_;
    size_t gws = groups * L_, lws = L_;
    CK(clEnqueueNDRangeKernel(x->q, k, 1, NULL, &gws, &lws, 0, NULL, NULL)); CK(clFinish(x->q));
    double t0 = now();
    for (int r = 0; r < reps; r++) CK(clEnqueueNDRangeKernel(x->q, k, 1, NULL, &gws, &lws, 0, NULL, NULL));
    CK(clFinish(x->q));
    double us = (now() - t0) / reps * 1e6;
    CK(clEnqueueReadBuffer(x->q, mo, CL_TRUE, 0, oc * 2, out, 0, NULL, NULL));
    if (wimg) clReleaseMemObject(wimg); clReleaseMemObject(mimg); clReleaseMemObject(mib); clReleaseMemObject(mo); clReleaseMemObject(mso);
    clReleaseMemObject(mw); clReleaseKernel(k); clReleaseProgram(p);
    return us;
}

int main(int argc, char **argv) {
    char *orig = readfile(argv[1]), *cust = readfile(argv[2]);
    Ctx x; cl_platform_id pl; cl_int e;
    CK(clGetPlatformIDs(1, &pl, NULL)); CK(clGetDeviceIDs(pl, CL_DEVICE_TYPE_GPU, 1, &x.d, NULL));
    x.c = clCreateContext(NULL, 1, &x.d, NULL, NULL, &e); CK(e);
    x.q = clCreateCommandQueueWithProperties(x.c, x.d, NULL, &e); CK(e);
    struct { int ic, oc; const char *what; } shapes[] = {{1024, 3584, "1024->3584"}, {3584, 1024, "3584->1024"},
                                                         {1024, 1024, "1024->1024"}, {1024, 248320, "lm_head 1024->248320"}};
    srand(1);
    for (int sh = 0; sh < 4; sh++) {
        int ic = shapes[sh].ic, oc = shapes[sh].oc; size_t wbytes = (size_t)oc * ic / 2, nblk = ic / 64;
        uint8_t *w = malloc(wbytes); for (size_t i = 0; i < wbytes; i++) w[i] = rand();
        uint16_t *so = malloc(nblk * oc * 2 * 2);
        for (size_t i = 0; i < nblk * oc * 2; i++) so[i] = f2h(i & 1 ? -0.05f : 0.01f * (1 + rand() % 5));
        uint16_t *in = malloc(ic * 2); for (int i = 0; i < ic; i++) in[i] = f2h((rand() % 200 - 100) / 100.0f);
        uint16_t *ref = malloc(oc * 2), *o = malloc(oc * 2);
        int reps = oc > 100000 ? 5 : 50;
        double tref = run(&x, orig, 128, ic, oc, w, so, in, ref, reps);
        double rmax = 0; for (int k = 0; k < oc; k++) { double a = fabs(h2f(ref[k])); if (a > rmax) rmax = a; }
        printf("== %s  weights %.2f MB  ideal(16.9GB/s) %.0f us | MNN orig WGS128 %.0f us (%.1f GB/s), |out|max %.2f\n",
               shapes[sh].what, wbytes / 1e6, wbytes / 16.9e9 * 1e6, tref, wbytes / tref / 1e3, rmax);
        size_t maxh = 0; clGetDeviceInfo(x.d, CL_DEVICE_IMAGE2D_MAX_HEIGHT, sizeof maxh, &maxh, NULL);
        int cfg[][2] = {{4, 64}, {8, 64}, {16, 64}, {8, 128}, {16, 128}};
        for (int ci = 0; ci < 5; ci++) for (int img = 0; img < 4; img += 3) {
            if (img == 1 && (size_t)(oc / 8) > maxh) { if (ci == 0) printf("   (image variant skipped: height %d > max %zu)\n", oc / 8, maxh); continue; }
            double t = run_custom(&x, cust, img, cfg[ci][0], cfg[ci][1], ic, oc, w, so, in, o, reps);
            double md = 0; for (int k = 0; k < oc; k++) { double d = fabs(h2f(ref[k]) - h2f(o[k])); if (d > md) md = d; }
            printf("   %s L=%-3d S=%-2d %7.0f us  %5.1f GB/s  x%.2f vs MNN   maxdiff %.3g\n", img == 3 ? "COAL  " : img == 2 ? "HALF  " : img ? "IMAGE " : "block ",
                   cfg[ci][1], cfg[ci][0], t, wbytes / t / 1e3, tref / t, md);
        }
        free(w); free(so); free(in); free(ref); free(o);
    }
    return 0;
}
