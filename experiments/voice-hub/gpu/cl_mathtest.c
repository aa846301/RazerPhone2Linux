// Does the OpenCL compiler handle libclc math builtins (float + half)? Prints build log on failure.
#define CL_TARGET_OPENCL_VERSION 300
#include <CL/cl.h>
#include <stdio.h>
#include <stdlib.h>

static const char *srcs[] = {
  "__kernel void k(__global float *a){size_t i=get_global_id(0); a[i]=exp(a[i])+tanh(a[i])+erf(a[i])+log(a[i]+2.0f)+native_exp(a[i])+rsqrt(a[i]+1.0f);}",
  "#pragma OPENCL EXTENSION cl_khr_fp16 : enable\n__kernel void k(__global half *a){size_t i=get_global_id(0); half x=a[i]; a[i]=exp(x)+tanh(x)+(half)erf((float)x)+native_exp(x);}",
  "#pragma OPENCL EXTENSION cl_khr_fp16 : enable\n__kernel void k(__global half *a){size_t i=get_global_id(0); float4 v=vload_half4(i,a); vstore_half4(v*2.0f,i,a);}",
};
const char *names[] = {"float math", "half math", "vload_half4"};

int main(void) {
    cl_platform_id p; cl_device_id d; cl_int e;
    clGetPlatformIDs(1, &p, NULL); clGetDeviceIDs(p, CL_DEVICE_TYPE_GPU, 1, &d, NULL);
    cl_context c = clCreateContext(NULL, 1, &d, NULL, NULL, &e);
    for (int i = 0; i < 3; i++) {
        cl_program pr = clCreateProgramWithSource(c, 1, &srcs[i], NULL, &e);
        e = clBuildProgram(pr, 1, &d, "", NULL, NULL);
        cl_int ek = -1; cl_kernel k = NULL;
        if (!e) k = clCreateKernel(pr, "k", &ek);
        printf("%-12s build=%d kernel=%d\n", names[i], e, k ? 0 : ek);
        if (e) { char log[4096] = {0}; clGetProgramBuildInfo(pr, d, CL_PROGRAM_BUILD_LOG, sizeof log - 1, log, NULL); printf("  log: %.1500s\n", log); }
    }
    return 0;
}
