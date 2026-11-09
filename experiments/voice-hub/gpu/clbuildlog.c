// LD_PRELOAD shim: log every failing clBuildProgram / clCreateKernel with the compiler log.
#define _GNU_SOURCE
#define CL_TARGET_OPENCL_VERSION 300
#include <CL/cl.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static FILE *out(void) {
    static FILE *f;
    if (!f) { f = fopen(getenv("CLLOG") ? getenv("CLLOG") : "/tmp/clbuild.log", "a"); setvbuf(f, NULL, _IOLBF, 0); }
    return f;
}

CL_API_ENTRY cl_int CL_API_CALL clBuildProgram(cl_program p, cl_uint n, const cl_device_id *d, const char *opts,
                                               void (CL_CALLBACK *cb)(cl_program, void *), void *ud) {
    static cl_int (*real)(cl_program, cl_uint, const cl_device_id *, const char *, void (CL_CALLBACK *)(cl_program, void *), void *);
    if (!real) real = dlsym(RTLD_NEXT, "clBuildProgram");
    cl_int r = real(p, n, d, opts, cb, ud);
    static int count;
    count++;
    if (r != CL_SUCCESS) {
        cl_device_id dev = d ? d[0] : NULL;
        if (!dev) clGetProgramInfo(p, CL_PROGRAM_DEVICES, sizeof dev, &dev, NULL);
        size_t len = 0;
        clGetProgramBuildInfo(p, dev, CL_PROGRAM_BUILD_LOG, 0, NULL, &len);
        char *log = calloc(1, len + 1);
        clGetProgramBuildInfo(p, dev, CL_PROGRAM_BUILD_LOG, len, log, NULL);
        size_t slen = 0;
        clGetProgramInfo(p, CL_PROGRAM_SOURCE, 0, NULL, &slen);
        char *src = calloc(1, slen + 1);
        clGetProgramInfo(p, CL_PROGRAM_SOURCE, slen, src, NULL);
        char head[121] = {0};
        strncpy(head, src, 120);
        for (char *c = head; *c; c++) if (*c == '\n') *c = ' ';
        fprintf(out(), "=== BUILD FAIL #%d err=%d opts=[%s]\n--- source head: %s\n--- log:\n%.4000s\n", count, r, opts ? opts : "", head, log);
        free(log); free(src);
    }
    return r;
}

CL_API_ENTRY cl_kernel CL_API_CALL clCreateKernel(cl_program p, const char *name, cl_int *err) {
    static cl_kernel (*real)(cl_program, const char *, cl_int *);
    if (!real) real = dlsym(RTLD_NEXT, "clCreateKernel");
    cl_int e = 0;
    cl_kernel k = real(p, name, &e);
    if (err) *err = e;
    if (e != CL_SUCCESS || !k) fprintf(out(), "=== CREATE KERNEL FAIL name=%s err=%d\n", name, e);
    return k;
}
