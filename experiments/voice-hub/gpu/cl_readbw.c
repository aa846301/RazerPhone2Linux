// GPU read-only bandwidth: each work-item sums a strided slice of a big buffer (like a GEMV
// streaming weights) and writes one float. Tries several vector widths / work-group sizes.
#define CL_TARGET_OPENCL_VERSION 300
#include <CL/cl.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }
#define CK(x) do { cl_int e = (x); if (e) { printf("err %d at %s line %d\n", e, #x, __LINE__); exit(1); } } while (0)

static const char *src =
"__kernel void rd4(__global const float4 *a, __global float *o, uint n4, uint per) {\n"
"  uint g = get_global_id(0), G = get_global_size(0); float4 s = 0;\n"
"  for (uint i = 0; i < per; i++) { uint idx = i * G + g; if (idx < n4) s += a[idx]; }\n"
"  o[g] = s.x + s.y + s.z + s.w; }\n"
"__kernel void rd16(__global const float16 *a, __global float *o, uint n16, uint per) {\n"
"  uint g = get_global_id(0), G = get_global_size(0); float16 s = 0;\n"
"  for (uint i = 0; i < per; i++) { uint idx = i * G + g; if (idx < n16) s += a[idx]; }\n"
"  o[g] = s.s0 + s.s5 + s.sa + s.sf; }\n";

int main(void) {
    cl_platform_id p; cl_device_id d; cl_int e;
    CK(clGetPlatformIDs(1, &p, NULL)); CK(clGetDeviceIDs(p, CL_DEVICE_TYPE_GPU, 1, &d, NULL));
    char dv[128]; clGetDeviceInfo(d, CL_DRIVER_VERSION, sizeof dv, dv, NULL);
    cl_context c = clCreateContext(NULL, 1, &d, NULL, NULL, &e); CK(e);
    cl_command_queue q = clCreateCommandQueueWithProperties(c, d, NULL, &e); CK(e);
    cl_program pr = clCreateProgramWithSource(c, 1, &src, NULL, &e); CK(e);
    CK(clBuildProgram(pr, 1, &d, "-cl-fast-relaxed-math", NULL, NULL));
    size_t bytes = 448u << 20;   // ~ size of Qwen3.5-0.8B 4-bit weights
    cl_mem a = clCreateBuffer(c, CL_MEM_READ_ONLY, bytes, NULL, &e); CK(e);
    float zero = 0; CK(clEnqueueFillBuffer(q, a, &zero, 4, 0, bytes, 0, NULL, NULL)); CK(clFinish(q));
    printf("driver %s, buffer %zu MiB\n", dv, bytes >> 20);
    const char *names[] = {"rd4", "rd16"}; size_t vec[] = {16, 64};
    size_t globals[] = {8192, 16384, 32768, 65536};
    for (int k = 0; k < 2; k++) {
        cl_kernel kr = clCreateKernel(pr, names[k], &e); CK(e);
        for (int gi = 0; gi < 4; gi++) {
            size_t G = globals[gi]; cl_uint n = bytes / vec[k], per = (n + G - 1) / G;
            cl_mem o = clCreateBuffer(c, CL_MEM_WRITE_ONLY, G * 4, NULL, &e); CK(e);
            CK(clSetKernelArg(kr, 0, sizeof a, &a)); CK(clSetKernelArg(kr, 1, sizeof o, &o));
            CK(clSetKernelArg(kr, 2, 4, &n)); CK(clSetKernelArg(kr, 3, 4, &per));
            CK(clEnqueueNDRangeKernel(q, kr, 1, NULL, &G, NULL, 0, NULL, NULL)); CK(clFinish(q));
            double t0 = now();
            for (int r = 0; r < 5; r++) CK(clEnqueueNDRangeKernel(q, kr, 1, NULL, &G, NULL, 0, NULL, NULL));
            CK(clFinish(q));
            double dt = (now() - t0) / 5;
            printf("  %-5s global=%6zu  %.2f ms  -> %.1f GB/s  (=> %.0f tok/s if a token reads %zu MiB)\n",
                   names[k], G, dt * 1e3, bytes / dt / 1e9, 1 / dt, bytes >> 20);
            clReleaseMemObject(o);
        }
    }
    return 0;
}
