// Run alu_tp.cl kernels; report per-weight time (8 weights per iteration per thread) and lane-op throughput.
#define CL_TARGET_OPENCL_VERSION 300
#include <CL/cl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CK(x) do { cl_int e_ = (x); if (e_) { printf("err %d at %s line %d\n", e_, #x, __LINE__); exit(1); } } while (0)
static char *readfile(const char *p) {
    FILE *f = fopen(p, "rb"); fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    char *b = malloc(n + 1); if (fread(b, 1, n, f) != (size_t)n) exit(1); b[n] = 0; fclose(f); return b;
}
int main(int argc, char **argv) {
    char *src = readfile(argv[1]);
    cl_platform_id pl; cl_device_id d; cl_int e;
    CK(clGetPlatformIDs(1, &pl, NULL)); CK(clGetDeviceIDs(pl, CL_DEVICE_TYPE_GPU, 1, &d, NULL));
    cl_context c = clCreateContext(NULL, 1, &d, NULL, NULL, &e); CK(e);
    cl_queue_properties qp[] = {CL_QUEUE_PROPERTIES, CL_QUEUE_PROFILING_ENABLE, 0};
    cl_command_queue q = clCreateCommandQueueWithProperties(c, d, qp, &e); CK(e);
    cl_program p = clCreateProgramWithSource(c, 1, (const char **)&src, NULL, &e); CK(e);
    if (clBuildProgram(p, 1, &d, "-DITER=256", NULL, NULL)) { char log[8192]; clGetProgramBuildInfo(p, d, CL_PROGRAM_BUILD_LOG, sizeof log, log, NULL); printf("%s\n", log); return 1; }
    const size_t G = 1 << 20, L = 64; const int ITER = 256;
    cl_mem o = clCreateBuffer(c, CL_MEM_WRITE_ONLY, G * 4, NULL, &e); CK(e);
    const char *names[] = {"k_fma", "k_int", "k_cov", "k_magic"};
    for (int k = 0; k < 4; k++) {
        cl_kernel kr = clCreateKernel(p, names[k], &e); CK(e);
        float a = 0.999f, b = 0.001f; unsigned qv = 12345;
        CK(clSetKernelArg(kr, 0, sizeof o, &o));
        if (k == 0) { CK(clSetKernelArg(kr, 1, 4, &a)); CK(clSetKernelArg(kr, 2, 4, &b)); }
        else if (k == 1) CK(clSetKernelArg(kr, 1, 4, &qv));
        else { CK(clSetKernelArg(kr, 1, 4, &qv)); CK(clSetKernelArg(kr, 2, 4, &b)); }
        double best = 1e9;
        for (int r = 0; r < 6; r++) {
            cl_event ev; CK(clEnqueueNDRangeKernel(q, kr, 1, NULL, &G, &L, 0, NULL, &ev)); CK(clFinish(q));
            cl_ulong t0, t1;
            clGetEventProfilingInfo(ev, CL_PROFILING_COMMAND_START, 8, &t0, NULL);
            clGetEventProfilingInfo(ev, CL_PROFILING_COMMAND_END, 8, &t1, NULL);
            clReleaseEvent(ev); double dt = (t1 - t0) * 1e-9; if (r && dt < best) best = dt;
        }
        double items = (double)G * ITER * 8;
        printf("%-8s %7.2f ms  %6.1f G items/s  (%.3f ns per 1e3 items)\n", names[k], best * 1e3, items / best / 1e9, best / items * 1e12);
        clReleaseKernel(kr);
    }
    return 0;
}
