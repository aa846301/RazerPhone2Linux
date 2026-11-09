// Per-dispatch overhead of rusticl/freedreno: N tiny kernels back-to-back (in-order queue, one clFinish).
// Reports: CPU enqueue cost per kernel, wall time per kernel, GPU span per kernel (first start .. last end),
// mean GPU duration per kernel, and the GPU-side gap between consecutive kernels.
#define CL_TARGET_OPENCL_VERSION 300
#include <CL/cl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define CK(x) do { cl_int e_ = (x); if (e_) { printf("err %d at %s line %d\n", e_, #x, __LINE__); exit(1); } } while (0)
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }

static const char *src =
"__kernel void tiny(__global float *a) { size_t i = get_global_id(0); a[i] = a[i] * 1.0001f + 1.0f; }\n"
"__kernel void tiny2(__global float *a, __global const float *b, float s) { size_t i = get_global_id(0); a[i] = b[i] * s; }\n";

int main(int argc, char **argv) {
    int N = argc > 1 ? atoi(argv[1]) : 2000;
    cl_platform_id pl; cl_device_id d; cl_int e;
    CK(clGetPlatformIDs(1, &pl, NULL)); CK(clGetDeviceIDs(pl, CL_DEVICE_TYPE_GPU, 1, &d, NULL));
    char ext[8192]; clGetDeviceInfo(d, CL_DEVICE_EXTENSIONS, sizeof ext, ext, NULL);
    printf("extensions: %s\n", ext);
    cl_context c = clCreateContext(NULL, 1, &d, NULL, NULL, &e); CK(e);
    cl_program p = clCreateProgramWithSource(c, 1, &src, NULL, &e); CK(e);
    CK(clBuildProgram(p, 1, &d, NULL, NULL, NULL));
    cl_kernel k = clCreateKernel(p, "tiny", &e); CK(e);
    cl_kernel k2 = clCreateKernel(p, "tiny2", &e); CK(e);
    cl_mem a = clCreateBuffer(c, CL_MEM_READ_WRITE, 1 << 20, NULL, &e); CK(e);
    cl_mem b = clCreateBuffer(c, CL_MEM_READ_WRITE, 1 << 20, NULL, &e); CK(e);
    CK(clSetKernelArg(k, 0, sizeof a, &a));
    float s = 1.5f;
    CK(clSetKernelArg(k2, 0, sizeof a, &a)); CK(clSetKernelArg(k2, 1, sizeof b, &b)); CK(clSetKernelArg(k2, 2, 4, &s));
    size_t sizes[] = {64, 1024, 65536};
    for (int prof = 0; prof < 2; prof++) {
        cl_queue_properties qp[] = {CL_QUEUE_PROPERTIES, prof ? CL_QUEUE_PROFILING_ENABLE : 0, 0};
        cl_command_queue q = clCreateCommandQueueWithProperties(c, d, qp, &e); CK(e);
        for (int si = 0; si < 3; si++) for (int alt = 0; alt < 2; alt++) {
            size_t G = sizes[si], L = 64;
            cl_event *ev = prof ? calloc(N, sizeof(cl_event)) : NULL;
            for (int w = 0; w < 50; w++) CK(clEnqueueNDRangeKernel(q, k, 1, NULL, &G, &L, 0, NULL, NULL));
            CK(clFinish(q));
            double t0 = now();
            for (int i = 0; i < N; i++)
                CK(clEnqueueNDRangeKernel(q, (alt && (i & 1)) ? k2 : k, 1, NULL, &G, &L, 0, NULL, prof ? &ev[i] : NULL));
            double t1 = now();
            CK(clFinish(q));
            double t2 = now();
            printf("%s G=%6zu %s: enqueue %.1f us/k, wall %.1f us/k", prof ? "prof  " : "noprof", G, alt ? "alt" : "same",
                   (t1 - t0) / N * 1e6, (t2 - t0) / N * 1e6);
            if (prof) {
                cl_ulong s0, e0, sN, eN, sum = 0, gap = 0, prevEnd = 0;
                for (int i = 0; i < N; i++) {
                    cl_ulong st, en;
                    clGetEventProfilingInfo(ev[i], CL_PROFILING_COMMAND_START, 8, &st, NULL);
                    clGetEventProfilingInfo(ev[i], CL_PROFILING_COMMAND_END, 8, &en, NULL);
                    if (i == 0) { s0 = st; e0 = en; }
                    if (i == N - 1) { sN = st; eN = en; }
                    sum += en - st;
                    if (i) gap += st > prevEnd ? st - prevEnd : 0;
                    prevEnd = en;
                    clReleaseEvent(ev[i]);
                }
                (void)e0; (void)sN;
                printf(", GPU span %.1f us/k, GPU dur %.1f us/k, gap %.1f us/k", (eN - s0) / 1e3 / N, sum / 1e3 / N, gap / 1e3 / (N - 1));
                free(ev);
            }
            printf("\n");
        }
        clReleaseCommandQueue(q);
    }
    return 0;
}
