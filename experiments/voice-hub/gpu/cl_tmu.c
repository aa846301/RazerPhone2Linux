// TMU throughput: stream 448 MiB through read_imagef/read_imageui with different formats (free format conversion
// in the texture unit). Reports GB/s and G texels/s. Format list: RGBA32UI (16 B/texel), RGBA8 UNORM (4 B),
// RGBA16 UNORM (8 B), R8 UNORM (1 B).
#define CL_TARGET_OPENCL_VERSION 300
#include <CL/cl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CK(x) do { cl_int e_ = (x); if (e_) { printf("err %d at %s line %d\n", e_, #x, __LINE__); exit(1); } } while (0)
static const char *src =
"__constant sampler_t S = CLK_NORMALIZED_COORDS_FALSE | CLK_ADDRESS_NONE | CLK_FILTER_NEAREST;\n"
"__kernel void rf(__read_only image2d_t a, __global float *o, int H, int U) {\n"
"  int x = get_global_id(0), gy = get_global_id(1), Gy = get_global_size(1); float4 s = 0;\n"
"  for (int y = gy; y < H; y += Gy) s += read_imagef(a, S, (int2)(x, y));\n"
"  o[gy * get_global_size(0) + x] = s.x + s.y + s.z + s.w; }\n"
"__kernel void ru(__read_only image2d_t a, __global float *o, int H, int U) {\n"
"  int x = get_global_id(0), gy = get_global_id(1), Gy = get_global_size(1); uint4 s = 0;\n"
"  for (int y = gy; y < H; y += Gy) s ^= read_imageui(a, S, (int2)(x, y));\n"
"  o[gy * get_global_size(0) + x] = (float)(s.x ^ s.y ^ s.z ^ s.w); }\n";

int main(void) {
    cl_platform_id pl; cl_device_id d; cl_int e;
    CK(clGetPlatformIDs(1, &pl, NULL)); CK(clGetDeviceIDs(pl, CL_DEVICE_TYPE_GPU, 1, &d, NULL));
    cl_context c = clCreateContext(NULL, 1, &d, NULL, NULL, &e); CK(e);
    cl_queue_properties qp[] = {CL_QUEUE_PROPERTIES, CL_QUEUE_PROFILING_ENABLE, 0};
    cl_command_queue q = clCreateCommandQueueWithProperties(c, d, qp, &e); CK(e);
    cl_program p = clCreateProgramWithSource(c, 1, &src, NULL, &e); CK(e);
    CK(clBuildProgram(p, 1, &d, NULL, NULL, NULL));
    const size_t BYTES = 448u << 20;
    cl_mem buf = clCreateBuffer(c, CL_MEM_READ_ONLY, BYTES, NULL, &e); CK(e);
    unsigned pat = 0x5a3c1e0f; CK(clEnqueueFillBuffer(q, buf, &pat, 4, 0, BYTES, 0, NULL, NULL)); CK(clFinish(q));
    cl_mem o = clCreateBuffer(c, CL_MEM_WRITE_ONLY, 16 << 20, NULL, &e); CK(e);
    struct { const char *name; cl_channel_order ord; cl_channel_type ty; int bpt; int fl; } F[] = {
        {"RGBA32UI", CL_RGBA, CL_UNSIGNED_INT32, 16, 0}, {"RGBA8 UNORM", CL_RGBA, CL_UNORM_INT8, 4, 1},
        {"RGBA8 UINT", CL_RGBA, CL_UNSIGNED_INT8, 4, 0}, {"RGBA16 UNORM", CL_RGBA, CL_UNORM_INT16, 8, 1},
        {"R8 UNORM", CL_R, CL_UNORM_INT8, 1, 1}};
    for (int f = 0; f < 5; f++) {
        size_t W = 16384, H = BYTES / F[f].bpt / W; if (H > 16384) H = 16384;
        size_t used = W * H * F[f].bpt;
        cl_image_format fmt = {F[f].ord, F[f].ty}; cl_image_desc dsc; memset(&dsc, 0, sizeof dsc);
        dsc.image_type = CL_MEM_OBJECT_IMAGE2D; dsc.image_width = W; dsc.image_height = H;
        dsc.image_row_pitch = W * F[f].bpt; dsc.buffer = buf;
        cl_mem im = clCreateImage(c, CL_MEM_READ_ONLY, &fmt, &dsc, NULL, &e);
        if (e) { printf("%-13s not available (%d)\n", F[f].name, e); continue; }
        cl_kernel k = clCreateKernel(p, F[f].fl ? "rf" : "ru", &e); CK(e);
        int Hi = (int)H, U = 1;
        CK(clSetKernelArg(k, 0, sizeof im, &im)); CK(clSetKernelArg(k, 1, sizeof o, &o));
        CK(clSetKernelArg(k, 2, 4, &Hi)); CK(clSetKernelArg(k, 3, 4, &U));
        size_t gys[] = {16, 64};
        for (int gi = 0; gi < 2; gi++) {
            size_t gws[2] = {W, gys[gi]}, lws[2] = {64, 1}; double best = 1e9;
            for (int r = 0; r < 4; r++) {
                cl_event ev; CK(clEnqueueNDRangeKernel(q, k, 2, NULL, gws, lws, 0, NULL, &ev)); CK(clFinish(q));
                cl_ulong t0, t1; clGetEventProfilingInfo(ev, CL_PROFILING_COMMAND_START, 8, &t0, NULL);
                clGetEventProfilingInfo(ev, CL_PROFILING_COMMAND_END, 8, &t1, NULL); clReleaseEvent(ev);
                double dt = (t1 - t0) * 1e-9; if (r && dt < best) best = dt;
            }
            printf("%-13s Gy=%-3zu %7.2f ms  %5.1f GB/s  %5.2f G texels/s\n", F[f].name, gys[gi], best * 1e3,
                   used / best / 1e9, W * H / best / 1e9);
        }
        clReleaseKernel(k); clReleaseMemObject(im);
    }
    return 0;
}
