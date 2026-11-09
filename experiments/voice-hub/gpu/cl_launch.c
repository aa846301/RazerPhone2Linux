// Measure OpenCL per-kernel fixed cost on the current platform (rusticl/freedreno).
// 1) sync:   enqueue tiny kernel + clFinish, N times  -> round-trip latency per call
// 2) async:  enqueue N tiny kernels, one clFinish      -> pipelined cost per call
// 3) work:   one kernel touching a 64 MiB buffer       -> sanity check of real bandwidth
#define CL_TARGET_OPENCL_VERSION 300
#include <CL/cl.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }
#define CK(x) do { cl_int e = (x); if (e) { printf("err %d at %s\n", e, #x); exit(1); } } while (0)

static const char *src =
    "__kernel void tiny(__global float *a) { size_t i = get_global_id(0); a[i] = a[i] + 1.0f; }\n"
    "__kernel void big(__global const float4 *a, __global float4 *b) { size_t i = get_global_id(0); b[i] = a[i] * 2.0f; }\n";

int main(void) {
    cl_platform_id p; cl_device_id d; cl_int e;
    CK(clGetPlatformIDs(1, &p, NULL));
    CK(clGetDeviceIDs(p, CL_DEVICE_TYPE_GPU, 1, &d, NULL));
    char name[128]; clGetDeviceInfo(d, CL_DEVICE_NAME, sizeof name, name, NULL);
    cl_context c = clCreateContext(NULL, 1, &d, NULL, NULL, &e); CK(e);
    cl_command_queue q = clCreateCommandQueueWithProperties(c, d, NULL, &e); CK(e);
    cl_program pr = clCreateProgramWithSource(c, 1, &src, NULL, &e); CK(e);
    CK(clBuildProgram(pr, 1, &d, NULL, NULL, NULL));
    cl_kernel kt = clCreateKernel(pr, "tiny", &e); CK(e);
    cl_kernel kb = clCreateKernel(pr, "big", &e); CK(e);
    size_t small = 1024, bign = (64u << 20) / 16;
    cl_mem s = clCreateBuffer(c, CL_MEM_READ_WRITE, small * 4, NULL, &e); CK(e);
    cl_mem a = clCreateBuffer(c, CL_MEM_READ_WRITE, bign * 16, NULL, &e); CK(e);
    cl_mem b = clCreateBuffer(c, CL_MEM_READ_WRITE, bign * 16, NULL, &e); CK(e);
    CK(clSetKernelArg(kt, 0, sizeof s, &s));
    CK(clSetKernelArg(kb, 0, sizeof a, &a)); CK(clSetKernelArg(kb, 1, sizeof b, &b));
    printf("device: %s\n", name);
    for (int w = 0; w < 20; w++) { CK(clEnqueueNDRangeKernel(q, kt, 1, NULL, &small, NULL, 0, NULL, NULL)); CK(clFinish(q)); }
    int N = 500;
    double t0 = now();
    for (int i = 0; i < N; i++) { CK(clEnqueueNDRangeKernel(q, kt, 1, NULL, &small, NULL, 0, NULL, NULL)); CK(clFinish(q)); }
    double sync_us = (now() - t0) / N * 1e6;
    t0 = now();
    for (int i = 0; i < N; i++) CK(clEnqueueNDRangeKernel(q, kt, 1, NULL, &small, NULL, 0, NULL, NULL));
    double enq = now() - t0;
    CK(clFinish(q));
    double async_us = (now() - t0) / N * 1e6;
    printf("tiny kernel (1024 floats): sync %.1f us/call, async %.1f us/call (enqueue cost %.1f us/call)\n",
           sync_us, async_us, enq / N * 1e6);
    CK(clEnqueueNDRangeKernel(q, kb, 1, NULL, &bign, NULL, 0, NULL, NULL)); CK(clFinish(q));
    t0 = now();
    for (int i = 0; i < 5; i++) CK(clEnqueueNDRangeKernel(q, kb, 1, NULL, &bign, NULL, 0, NULL, NULL));
    CK(clFinish(q));
    double dt = (now() - t0) / 5;
    printf("64 MiB read + 64 MiB write: %.2f ms -> %.1f GB/s\n", dt * 1e3, 2 * 64.0 / 1024 / dt);
    return 0;
}
