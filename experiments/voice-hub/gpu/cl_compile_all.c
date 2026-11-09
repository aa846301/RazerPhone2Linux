// Compile every .cl given on the command line with the rusticl-Adreno options; print the first errors per file.
#define CL_TARGET_OPENCL_VERSION 300
#include <CL/cl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *readfile(const char *p) {
    FILE *f = fopen(p, "rb"); if (!f) return NULL;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    char *b = malloc(n + 1); if (fread(b, 1, n, f) != (size_t)n) { fclose(f); return NULL; } b[n] = 0; fclose(f); return b;
}

int main(int argc, char **argv) {
    const char *opts = getenv("CLOPTS") ? getenv("CLOPTS") :
        "-cl-std=CL3.0 -DADRENO_GPU=1 -DREQD_SUBGROUP_SIZE_64= -DREQD_SUBGROUP_SIZE_128= "
        "-DCLK_SUB_GROUP_SHUFFLE_WIDTH_WAVE_SIZE_QCOM=0 -Dqcom_sub_group_shuffle_xor(v,m,w,d)=sub_group_shuffle_xor(v,m) "
        "-Dqcom_wave_pair_mode(x)=unused";
    cl_platform_id pl; cl_device_id d; cl_int e;
    clGetPlatformIDs(1, &pl, NULL); clGetDeviceIDs(pl, CL_DEVICE_TYPE_GPU, 1, &d, NULL);
    cl_context c = clCreateContext(NULL, 1, &d, NULL, NULL, &e);
    int bad = 0;
    for (int i = 1; i < argc; i++) {
        char *src = readfile(argv[i]); if (!src) continue;
        cl_program p = clCreateProgramWithSource(c, 1, (const char **)&src, NULL, &e);
        if (clBuildProgram(p, 1, &d, opts, NULL, NULL) != CL_SUCCESS) {
            size_t n = 0; clGetProgramBuildInfo(p, d, CL_PROGRAM_BUILD_LOG, 0, NULL, &n);
            char *log = calloc(1, n + 1); clGetProgramBuildInfo(p, d, CL_PROGRAM_BUILD_LOG, n, log, NULL);
            printf("FAIL %s\n", argv[i]); bad++;
            int shown = 0;
            for (char *l = strtok(log, "\n"); l && shown < 4; l = strtok(NULL, "\n"))
                if (strstr(l, "error")) { printf("   %s\n", l); shown++; }
            free(log);
        }
        clReleaseProgram(p); free(src);
    }
    printf("%d of %d files failed\n", bad, argc - 1);
    return 0;
}
