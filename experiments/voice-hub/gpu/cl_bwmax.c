// GPU read-bandwidth ceiling sweep (448 MiB, like Qwen3.5-0.8B 4-bit weights).
// Variants:  buffer uint4 with U independent loads in flight per thread (interleaved = coalesced),
//            buffer uint4 contiguous-per-workgroup slices, image2d RGBA32UI via read_imageui (TP/L1 path).
// Timing uses OpenCL profiling events (pure GPU time), best of 5.
#define CL_TARGET_OPENCL_VERSION 300
#include <CL/cl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CK(x) do { cl_int e_ = (x); if (e_) { printf("err %d at %s line %d\n", e_, #x, __LINE__); exit(1); } } while (0)

static const char *src =
"#ifndef U\n#define U 1\n#endif\n"
"__kernel void buf_il(__global const uint4 *a, __global uint *o, uint n, uint iters) {\n"
"  uint g = get_global_id(0), G = get_global_size(0); uint4 s[U];\n"
"  for (int u = 0; u < U; u++) s[u] = 0;\n"
"  for (uint i = 0; i < iters; i++) {\n"
"    uint base = i * G * U + g;\n"
"    for (int u = 0; u < U; u++) { uint idx = base + u * G; if (idx < n) s[u] ^= a[idx]; }\n"
"  }\n"
"  uint4 t = 0; for (int u = 0; u < U; u++) t ^= s[u];\n"
"  o[g] = t.x ^ t.y ^ t.z ^ t.w; }\n"
"__kernel void buf_wg(__global const uint4 *a, __global uint *o, uint n, uint per_wg) {\n"
"  uint l = get_local_id(0), L = get_local_size(0), w = get_group_id(0);\n"
"  uint start = w * per_wg, end = min(start + per_wg, n); uint4 s[U];\n"
"  for (int u = 0; u < U; u++) s[u] = 0;\n"
"  for (uint i = start + l; i < end; i += L * U)\n"
"    for (int u = 0; u < U; u++) { uint idx = i + u * L; if (idx < end) s[u] ^= a[idx]; }\n"
"  uint4 t = 0; for (int u = 0; u < U; u++) t ^= s[u];\n"
"  o[get_global_id(0)] = t.x ^ t.y ^ t.z ^ t.w; }\n"
"__kernel void img(__read_only image2d_t a, __global uint *o, int H) {\n"
"  int x = get_global_id(0), gy = get_global_id(1), Gy = get_global_size(1); uint4 s[U];\n"
"  for (int u = 0; u < U; u++) s[u] = 0;\n"
"  for (int y = gy; y < H; y += Gy * U)\n"
"    for (int u = 0; u < U; u++) { int yy = y + u * Gy; if (yy < H) s[u] ^= read_imageui(a, (int2)(x, yy)); }\n"
"  uint4 t = 0; for (int u = 0; u < U; u++) t ^= s[u];\n"
"  o[gy * get_global_size(0) + x] = t.x ^ t.y ^ t.z ^ t.w; }\n";

static cl_context c; static cl_device_id d; static cl_command_queue q;
static const size_t BYTES = 448u << 20;

static double run(cl_kernel k, cl_uint dim, const size_t *gws, const size_t *lws) {
    cl_event ev; double best = 1e9;
    CK(clEnqueueNDRangeKernel(q, k, dim, NULL, gws, lws, 0, NULL, NULL)); CK(clFinish(q));
    for (int r = 0; r < 5; r++) {
        CK(clEnqueueNDRangeKernel(q, k, dim, NULL, gws, lws, 0, NULL, &ev)); CK(clFinish(q));
        cl_ulong t0, t1;
        clGetEventProfilingInfo(ev, CL_PROFILING_COMMAND_START, sizeof t0, &t0, NULL);
        clGetEventProfilingInfo(ev, CL_PROFILING_COMMAND_END, sizeof t1, &t1, NULL);
        clReleaseEvent(ev);
        double dt = (t1 - t0) * 1e-9; if (dt < best) best = dt;
    }
    return best;
}

static cl_program build(int U) {
    cl_int e; char opt[64]; snprintf(opt, sizeof opt, "-DU=%d", U);
    cl_program p = clCreateProgramWithSource(c, 1, &src, NULL, &e); CK(e);
    if (clBuildProgram(p, 1, &d, opt, NULL, NULL)) {
        char log[8192]; clGetProgramBuildInfo(p, d, CL_PROGRAM_BUILD_LOG, sizeof log, log, NULL); printf("%s\n", log); exit(1);
    }
    return p;
}

int main(int argc, char **argv) {
    const char *only = argc > 1 ? argv[1] : "";
    cl_platform_id pl; cl_int e;
    CK(clGetPlatformIDs(1, &pl, NULL)); CK(clGetDeviceIDs(pl, CL_DEVICE_TYPE_GPU, 1, &d, NULL));
    c = clCreateContext(NULL, 1, &d, NULL, NULL, &e); CK(e);
    cl_queue_properties qp[] = {CL_QUEUE_PROPERTIES, CL_QUEUE_PROFILING_ENABLE, 0};
    q = clCreateCommandQueueWithProperties(c, d, qp, &e); CK(e);
    cl_mem a = clCreateBuffer(c, CL_MEM_READ_ONLY, BYTES, NULL, &e); CK(e);
    unsigned pat = 0x01020304; CK(clEnqueueFillBuffer(q, a, &pat, 4, 0, BYTES, 0, NULL, NULL)); CK(clFinish(q));
    cl_mem o = clCreateBuffer(c, CL_MEM_WRITE_ONLY, 4u << 20, NULL, &e); CK(e);
    cl_uint n = BYTES / 16;
    printf("buffer %zu MiB, %u uint4\n", BYTES >> 20, n);
    int Us[] = {1, 2, 4, 8};
    for (int ui = 0; ui < 4; ui++) {
        int U = Us[ui]; cl_program p = build(U);
        if (!*only || strstr(only, "il")) {
            cl_kernel k = clCreateKernel(p, "buf_il", &e); CK(e);
            size_t gs[] = {16384, 65536, 262144}, ls[] = {64, 128, 256};
            for (int gi = 0; gi < 3; gi++) for (int li = 0; li < 3; li++) {
                size_t G = gs[gi], L = ls[li]; cl_uint iters = (n + G * U - 1) / (G * U);
                CK(clSetKernelArg(k, 0, sizeof a, &a)); CK(clSetKernelArg(k, 1, sizeof o, &o));
                CK(clSetKernelArg(k, 2, 4, &n)); CK(clSetKernelArg(k, 3, 4, &iters));
                double dt = run(k, 1, &G, &L);
                printf("buf_il U=%d G=%6zu L=%3zu  %7.2f ms  %5.1f GB/s\n", U, G, L, dt * 1e3, BYTES / dt / 1e9);
            }
            clReleaseKernel(k);
        }
        if (!*only || strstr(only, "wg")) {
            cl_kernel k = clCreateKernel(p, "buf_wg", &e); CK(e);
            size_t wgs[] = {64, 256, 1024}, ls[] = {64, 128};
            for (int wi = 0; wi < 3; wi++) for (int li = 0; li < 2; li++) {
                size_t L = ls[li], G = wgs[wi] * L; cl_uint per = (n + wgs[wi] - 1) / wgs[wi];
                CK(clSetKernelArg(k, 0, sizeof a, &a)); CK(clSetKernelArg(k, 1, sizeof o, &o));
                CK(clSetKernelArg(k, 2, 4, &n)); CK(clSetKernelArg(k, 3, 4, &per));
                double dt = run(k, 1, &G, &L);
                printf("buf_wg U=%d WG=%4zu L=%3zu  %7.2f ms  %5.1f GB/s\n", U, wgs[wi], L, dt * 1e3, BYTES / dt / 1e9);
            }
            clReleaseKernel(k);
        }
        if (!*only || strstr(only, "img")) {
            const size_t W = 16384, H = n / W;
            cl_image_format f = {CL_RGBA, CL_UNSIGNED_INT32};
            cl_image_desc dsc; memset(&dsc, 0, sizeof dsc);
            dsc.image_type = CL_MEM_OBJECT_IMAGE2D; dsc.image_width = W; dsc.image_height = H; dsc.buffer = a;
            cl_mem im = clCreateImage(c, CL_MEM_READ_ONLY, &f, &dsc, NULL, &e);
            if (e) { printf("img from buffer failed %d\n", e); }
            else {
                cl_kernel k = clCreateKernel(p, "img", &e); CK(e);
                size_t gys[] = {1, 4, 16}; size_t lxs[] = {64, 128};
                for (int yi = 0; yi < 3; yi++) for (int li = 0; li < 2; li++) {
                    size_t gws[2] = {W, gys[yi]}, lws[2] = {lxs[li], 1}; int Hh = (int)H;
                    CK(clSetKernelArg(k, 0, sizeof im, &im)); CK(clSetKernelArg(k, 1, sizeof o, &o)); CK(clSetKernelArg(k, 2, 4, &Hh));
                    double dt = run(k, 2, gws, lws);
                    printf("img    U=%d Gy=%3zu Lx=%3zu  %7.2f ms  %5.1f GB/s\n", U, gys[yi], lxs[li], dt * 1e3, (double)W * H * 16 / dt / 1e9);
                }
                clReleaseKernel(k); clReleaseMemObject(im);
            }
        }
        clReleaseProgram(p);
    }
    return 0;
}
