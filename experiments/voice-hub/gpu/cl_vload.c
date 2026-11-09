// Hypothesis test: reading weights with vload16 on a uchar* (1-byte aligned as far as the compiler
// knows) vs the same bytes through a uint4* (16-byte aligned) pointer. Same data, same work.
#define CL_TARGET_OPENCL_VERSION 300
#include <CL/cl.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }
#define CK(x) do { cl_int e = (x); if (e) { printf("err %d at %s line %d\n", e, #x, __LINE__); exit(1); } } while (0)

static const char *src =
"__kernel void by_vload(__global const uchar *w, __global uint *o, uint n16, uint per) {\n"
"  uint g = get_global_id(0), G = get_global_size(0); uint acc = 0;\n"
"  for (uint i = 0; i < per; i++) { uint idx = i * G + g; if (idx < n16) { uchar16 v = vload16(idx, w);\n"
"    acc += v.s0 + v.s5 + v.sa + v.sf + v.s3 + v.sc; } }\n"
"  o[g] = acc; }\n"
"__kernel void by_uint4(__global const uint4 *w, __global uint *o, uint n16, uint per) {\n"
"  uint g = get_global_id(0), G = get_global_size(0); uint acc = 0;\n"
"  for (uint i = 0; i < per; i++) { uint idx = i * G + g; if (idx < n16) { uchar16 v = as_uchar16(w[idx]);\n"
"    acc += v.s0 + v.s5 + v.sa + v.sf + v.s3 + v.sc; } }\n"
"  o[g] = acc; }\n";

int main(void) {
    cl_platform_id p; cl_device_id d; cl_int e;
    CK(clGetPlatformIDs(1, &p, NULL)); CK(clGetDeviceIDs(p, CL_DEVICE_TYPE_GPU, 1, &d, NULL));
    char dv[128]; clGetDeviceInfo(d, CL_DRIVER_VERSION, sizeof dv, dv, NULL);
    cl_context c = clCreateContext(NULL, 1, &d, NULL, NULL, &e); CK(e);
    cl_command_queue q = clCreateCommandQueueWithProperties(c, d, NULL, &e); CK(e);
    cl_program pr = clCreateProgramWithSource(c, 1, &src, NULL, &e); CK(e);
    CK(clBuildProgram(pr, 1, &d, "", NULL, NULL));
    size_t bytes = 256u << 20;
    cl_mem a = clCreateBuffer(c, CL_MEM_READ_ONLY, bytes, NULL, &e); CK(e);
    unsigned char one = 1; CK(clEnqueueFillBuffer(q, a, &one, 1, 0, bytes, 0, NULL, NULL)); CK(clFinish(q));
    size_t G = 32768; cl_uint n16 = bytes / 16, per = (n16 + G - 1) / G;
    cl_mem o = clCreateBuffer(c, CL_MEM_WRITE_ONLY, G * 4, NULL, &e); CK(e);
    printf("driver %s, %zu MiB\n", dv, bytes >> 20);
    const char *names[] = {"by_vload", "by_uint4"};
    for (int k = 0; k < 2; k++) {
        cl_kernel kr = clCreateKernel(pr, names[k], &e); CK(e);
        CK(clSetKernelArg(kr, 0, sizeof a, &a)); CK(clSetKernelArg(kr, 1, sizeof o, &o));
        CK(clSetKernelArg(kr, 2, 4, &n16)); CK(clSetKernelArg(kr, 3, 4, &per));
        CK(clEnqueueNDRangeKernel(q, kr, 1, NULL, &G, NULL, 0, NULL, NULL)); CK(clFinish(q));
        double t0 = now();
        for (int r = 0; r < 5; r++) CK(clEnqueueNDRangeKernel(q, kr, 1, NULL, &G, NULL, 0, NULL, NULL));
        CK(clFinish(q));
        double dt = (now() - t0) / 5;
        printf("  %-9s %.2f ms -> %.1f GB/s\n", names[k], dt * 1e3, bytes / dt / 1e9);
    }
    return 0;
}
