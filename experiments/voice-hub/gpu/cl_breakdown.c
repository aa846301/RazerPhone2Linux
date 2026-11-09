// Break one tiny OpenCL kernel call into stages using CL event profiling.
//   QUEUED -> SUBMIT : time in the runtime's queue before it is handed to the driver
//   SUBMIT -> START  : driver submit + kernel scheduling + GPU dispatch latency
//   START  -> END    : actual GPU execution
//   host wall time   : enqueue call .. clFinish return (includes completion wakeup)
// Prints medians over N calls. Pass "async" to enqueue N calls before one clFinish.
#define CL_TARGET_OPENCL_VERSION 300
#include <CL/cl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define N 300
static double now_us(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e6 + t.tv_nsec * 1e-3; }
#define CK(x) do { cl_int e = (x); if (e) { printf("err %d at %s\n", e, #x); exit(1); } } while (0)
static int cmp(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return (x > y) - (x < y); }
static double med(double *v) { qsort(v, N, sizeof *v, cmp); return v[N / 2]; }
static double p90(double *v) { return v[N * 9 / 10]; }

static const char *src = "__kernel void tiny(__global float *a) { size_t i = get_global_id(0); a[i] += 1.0f; }\n";

int main(int argc, char **argv) {
    int async = argc > 1 && !strcmp(argv[1], "async");
    cl_platform_id p; cl_device_id d; cl_int e;
    CK(clGetPlatformIDs(1, &p, NULL));
    CK(clGetDeviceIDs(p, CL_DEVICE_TYPE_GPU, 1, &d, NULL));
    char ver[256]; clGetPlatformInfo(p, CL_PLATFORM_VERSION, sizeof ver, ver, NULL);
    char dver[256]; clGetDeviceInfo(d, CL_DRIVER_VERSION, sizeof dver, dver, NULL);
    cl_context c = clCreateContext(NULL, 1, &d, NULL, NULL, &e); CK(e);
    cl_queue_properties qp[] = {CL_QUEUE_PROPERTIES, CL_QUEUE_PROFILING_ENABLE, 0};
    cl_command_queue q = clCreateCommandQueueWithProperties(c, d, qp, &e); CK(e);
    cl_program pr = clCreateProgramWithSource(c, 1, &src, NULL, &e); CK(e);
    CK(clBuildProgram(pr, 1, &d, NULL, NULL, NULL));
    cl_kernel k = clCreateKernel(pr, "tiny", &e); CK(e);
    size_t n = 1024;
    cl_mem s = clCreateBuffer(c, CL_MEM_READ_WRITE, n * 4, NULL, &e); CK(e);
    CK(clSetKernelArg(k, 0, sizeof s, &s));
    for (int w = 0; w < 20; w++) { CK(clEnqueueNDRangeKernel(q, k, 1, NULL, &n, NULL, 0, NULL, NULL)); CK(clFinish(q)); }

    static cl_event ev[N];
    static double qs[N], ss[N], se[N], wall[N], enq[N];
    double t_all = now_us();
    for (int i = 0; i < N; i++) {
        double t0 = now_us();
        CK(clEnqueueNDRangeKernel(q, k, 1, NULL, &n, NULL, 0, NULL, &ev[i]));
        enq[i] = now_us() - t0;
        if (!async) { CK(clFinish(q)); wall[i] = now_us() - t0; }
    }
    if (async) CK(clFinish(q));
    double total = now_us() - t_all;
    for (int i = 0; i < N; i++) {
        cl_ulong tq, ts, tb, te;
        CK(clGetEventProfilingInfo(ev[i], CL_PROFILING_COMMAND_QUEUED, sizeof tq, &tq, NULL));
        CK(clGetEventProfilingInfo(ev[i], CL_PROFILING_COMMAND_SUBMIT, sizeof ts, &ts, NULL));
        CK(clGetEventProfilingInfo(ev[i], CL_PROFILING_COMMAND_START, sizeof tb, &tb, NULL));
        CK(clGetEventProfilingInfo(ev[i], CL_PROFILING_COMMAND_END, sizeof te, &te, NULL));
        qs[i] = (ts - tq) / 1e3; ss[i] = (tb - ts) / 1e3; se[i] = (te - tb) / 1e3;
        clReleaseEvent(ev[i]);
    }
    printf("%s | %s | mode=%s\n", ver, dver, async ? "async" : "sync");
    printf("  enqueue call (CPU)     median %7.1f us  p90 %7.1f\n", med(enq), p90(enq));
    printf("  QUEUED->SUBMIT         median %7.1f us  p90 %7.1f\n", med(qs), p90(qs));
    printf("  SUBMIT->START          median %7.1f us  p90 %7.1f\n", med(ss), p90(ss));
    printf("  START->END (GPU work)  median %7.1f us  p90 %7.1f\n", med(se), p90(se));
    if (!async) printf("  wall enqueue..finish   median %7.1f us  p90 %7.1f\n", med(wall), p90(wall));
    printf("  total %.1f us/call\n", total / N);
    return 0;
}
