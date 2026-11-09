// Benchmark gemv_exp.cl modes on real Qwen3.5-0.8B shapes. GPU time via profiling events (median of N),
// plus max error vs a CPU double reference. Usage: gemv_exp_bench gemv_exp.cl [reps]
#define CL_TARGET_OPENCL_VERSION 300
#include <CL/cl.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CK(x) do { cl_int e_ = (x); if (e_) { printf("err %d at %s line %d\n", e_, #x, __LINE__); exit(1); } } while (0)

static char *readfile(const char *p) {
    FILE *f = fopen(p, "rb"); if (!f) { perror(p); exit(1); }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    char *b = malloc(n + 1); if (fread(b, 1, n, f) != (size_t)n) exit(1); b[n] = 0; fclose(f); return b;
}
static uint16_t f2h(float f) {
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
static int cmpd(const void *a, const void *b) { double x = *(double *)a, y = *(double *)b; return x < y ? -1 : x > y; }

static cl_context C; static cl_device_id D; static cl_command_queue Q;

int main(int argc, char **argv) {
    char *src = readfile(argv[1]); int reps = argc > 2 ? atoi(argv[2]) : 50;
    const char *only = argc > 3 ? argv[3] : NULL;
    cl_platform_id pl; cl_int e;
    CK(clGetPlatformIDs(1, &pl, NULL)); CK(clGetDeviceIDs(pl, CL_DEVICE_TYPE_GPU, 1, &D, NULL));
    C = clCreateContext(NULL, 1, &D, NULL, NULL, &e); CK(e);
    cl_queue_properties qp[] = {CL_QUEUE_PROPERTIES, CL_QUEUE_PROFILING_ENABLE, 0};
    Q = clCreateCommandQueueWithProperties(C, D, qp, &e); CK(e);
    struct { int ic, oc; } shapes[] = {{1024, 1024}, {1024, 2048}, {2048, 1024}, {1024, 3584}, {3584, 1024},
                                       {1024, 6144}, {1024, 248320}};
    int cfgs[][3] = {{8, 2, 64}, {4, 4, 64}, {16, 1, 64}, {8, 2, 128}, {4, 4, 128}, {1, 4, 64}, {2, 4, 64}, {1, 8, 64}};
    int modes[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11};
    srand(1);
    for (int sh = 0; sh < 7; sh++) {
        int ic = shapes[sh].ic, oc = shapes[sh].oc, nc4 = ic / 4, nblk = ic / 64;
        size_t wbytes = (size_t)oc * ic / 2;
        uint8_t *w = malloc(wbytes); for (size_t i = 0; i < wbytes; i++) w[i] = rand();
        size_t nso = (size_t)nblk * oc * 2;
        uint16_t *so = malloc(nso * 2);
        for (size_t i = 0; i < nso; i++) so[i] = f2h(i & 1 ? -0.05f : 0.01f * (1 + rand() % 5));
        uint16_t *in = malloc(ic * 2); for (int i = 0; i < ic; i++) in[i] = f2h((rand() % 200 - 100) / 100.0f);
        double *ref = calloc(oc, sizeof(double));
        for (int g = 0; g < oc / 8; g++)
            for (int c = 0; c < nc4; c++) {
                const uint8_t *ch = w + ((size_t)g * nc4 + c) * 16; int blk = c / 16;
                for (int j = 0; j < 4; j++) {
                    double xv = h2f(in[4 * c + j]);
                    for (int k = 0; k < 4; k++) {
                        uint8_t b = ch[j * 4 + k];
                        int o0 = 8 * g + 2 * k, o1 = o0 + 1;
                        const uint16_t *sp = so + (size_t)blk * oc * 2;
                        ref[o0] += xv * ((b >> 4) * h2f(sp[o0 * 2]) + h2f(sp[o0 * 2 + 1]));
                        ref[o1] += xv * ((b & 15) * h2f(sp[o1 * 2]) + h2f(sp[o1 * 2 + 1]));
                    }
                }
            }
        cl_mem mw = clCreateBuffer(C, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR, wbytes, w, &e); CK(e);
        cl_mem mso = clCreateBuffer(C, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR, nso * 2, so, &e); CK(e);
        cl_mem mo = clCreateBuffer(C, CL_MEM_READ_WRITE, (size_t)oc * 2, NULL, &e); CK(e);
        cl_mem mib = clCreateBuffer(C, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR, ic * 2, in, &e); CK(e);
        cl_image_format fmt = {CL_RGBA, CL_HALF_FLOAT}; cl_image_desc desc; memset(&desc, 0, sizeof desc);
        desc.image_type = CL_MEM_OBJECT_IMAGE1D_BUFFER; desc.image_width = ic / 4; desc.buffer = mib;
        cl_mem mimg = clCreateImage(C, CL_MEM_READ_ONLY, &fmt, &desc, NULL, &e); CK(e);
        printf("== %d->%d  %.2f MB  (24.1 GB/s => %.0f us)\n", ic, oc, wbytes / 1e6, wbytes / 24.1e3);
        uint16_t *o = malloc((size_t)oc * 2);
        for (int ci = 0; ci < 8; ci++) for (int mi = 0; mi < 12; mi++) {
            int sb = cfgs[ci][0], sc = cfgs[ci][1], l = cfgs[ci][2], md = modes[mi];
            if (sb * sc > l || sb > nblk) continue;
            if (only && !strchr(only, md < 10 ? '0' + md : 'a' + md - 10)) continue;
            if (getenv("ONLY_CFG") && atoi(getenv("ONLY_CFG")) != ci) continue;
            if (getenv("ONLY_SHAPE") && atoi(getenv("ONLY_SHAPE")) != sh) continue;
            char opts[256]; snprintf(opts, sizeof opts, "-DSB=%d -DSC=%d -DL=%d -DMODE=%d -cl-mad-enable", sb, sc, l, md);
            cl_program p = clCreateProgramWithSource(C, 1, (const char **)&src, NULL, &e); CK(e);
            if (clBuildProgram(p, 1, &D, opts, NULL, NULL)) {
                char log[8192] = {0}; clGetProgramBuildInfo(p, D, CL_PROGRAM_BUILD_LOG, sizeof log - 1, log, NULL);
                printf("build failed %s:\n%s\n", opts, log); exit(1);
            }
            cl_kernel k = clCreateKernel(p, "gemv_q4", &e); CK(e);
            float cinv = 1.0f;
            CK(clSetKernelArg(k, 0, sizeof mw, &mw)); CK(clSetKernelArg(k, 1, sizeof mso, &mso));
            CK(clSetKernelArg(k, 2, sizeof mimg, &mimg)); CK(clSetKernelArg(k, 3, sizeof mo, &mo));
            CK(clSetKernelArg(k, 4, 4, &ic)); CK(clSetKernelArg(k, 5, 4, &oc)); CK(clSetKernelArg(k, 6, 4, &cinv));
            CK(clSetKernelArg(k, 7, sizeof mib, &mib));
            int R_ = l / (sb * sc); size_t gws = (size_t)((oc / 8 + R_ - 1) / R_) * l, lws = l;
            CK(clEnqueueNDRangeKernel(Q, k, 1, NULL, &gws, &lws, 0, NULL, NULL)); CK(clFinish(Q));
            int n = oc > 100000 ? 7 : reps; double *ts = malloc(n * sizeof(double));
            for (int rr = 0; rr < n; rr++) {
                cl_event ev; CK(clEnqueueNDRangeKernel(Q, k, 1, NULL, &gws, &lws, 0, NULL, &ev)); CK(clFinish(Q));
                cl_ulong t0, t1;
                clGetEventProfilingInfo(ev, CL_PROFILING_COMMAND_START, 8, &t0, NULL);
                clGetEventProfilingInfo(ev, CL_PROFILING_COMMAND_END, 8, &t1, NULL);
                clReleaseEvent(ev); ts[rr] = (t1 - t0) * 1e-3;
            }
            qsort(ts, n, sizeof(double), cmpd); double us = ts[n / 2]; free(ts);
            CK(clEnqueueReadBuffer(Q, mo, CL_TRUE, 0, (size_t)oc * 2, o, 0, NULL, NULL));
            double err = 0, mag = 0;
            for (int i = 0; i < oc; i++) { double d = fabs(h2f(o[i]) - ref[i]); if (d > err) err = d; if (fabs(ref[i]) > mag) mag = fabs(ref[i]); }
            printf("  mode %d SB=%-2d SC=%-2d L=%-3d %8.1f us %5.1f GB/s  relerr %.2e\n", md, sb, sc, l, us, wbytes / us / 1e3,
                   md == 1 ? 0.0 : err / mag);
            clReleaseKernel(k); clReleaseProgram(p);
        }
        clReleaseMemObject(mimg); clReleaseMemObject(mib); clReleaseMemObject(mo); clReleaseMemObject(mso); clReleaseMemObject(mw);
        free(w); free(so); free(in); free(ref); free(o);
    }
    return 0;
}
