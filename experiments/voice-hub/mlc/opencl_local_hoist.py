"""TVM OpenCL post-processing for Mesa rusticl (clang): hoist `__local` declarations to kernel scope.

OpenCL C requires local-address-space variables to be declared in the outermost scope of a kernel; TVM's codegen
may emit them inside nested blocks (`if`/`for`), which Qualcomm's proprietary compiler tolerates but clang rejects
("variables in the local address space can only be declared in the outermost scope of a kernel function").
Registered as `tvm_callback_opencl_postproc`, called once per generated function source.

Identical duplicate declarations (same name, same text) are merged; a name declared twice with different text is
an error (we refuse to guess). Every hoist is appended to $OPENCL_HOIST_LOG (default /tmp/opencl_hoist.log)."""
import os
import re

DECL = re.compile(r"^(\s*)(__local\s+[^;=(){}]*?([A-Za-z_][A-Za-z0-9_]*)\s*(\[[^\]]*\]\s*)*;)\s*$")
KERNEL = re.compile(r"__kernel\b[^{;]*\)\s*\{")
LOG = os.environ.get("OPENCL_HOIST_LOG", "/tmp/opencl_hoist.log")


def hoist(src: str) -> str:
    out = []
    pos = 0
    for m in KERNEL.finditer(src):
        if m.start() < pos:
            continue
        body_start = m.end()  # just after the kernel's opening brace
        out.append(src[pos:body_start])
        depth = 1
        j = body_start
        lines = []
        hoisted = {}
        while j < len(src) and depth > 0:
            nl = src.find("\n", j)
            nl = len(src) if nl == -1 else nl
            line = src[j:nl]
            dm = DECL.match(line)
            if dm and depth > 1:
                name, text = dm.group(3), dm.group(2).strip()
                if name in hoisted and hoisted[name] != text:
                    raise RuntimeError(f"opencl_local_hoist: conflicting __local declarations for {name}: "
                                       f"{hoisted[name]!r} vs {text!r}")
                hoisted[name] = text
                line = f"{dm.group(1)}/* __local {name} hoisted to kernel scope */"
            depth += line.count("{") - line.count("}")
            lines.append(line)
            j = nl + 1
        body = "\n".join(lines) + ("\n" if j <= len(src) else "")
        if hoisted:
            kname = src[m.start():m.end()].split("(")[0].split()[-1]
            with open(LOG, "a") as f:
                f.write(f"{kname}: {', '.join(hoisted)}\n")
            out.append("\n" + "".join(f"  {t}\n" for t in hoisted.values()))
        out.append(body)
        pos = min(j, len(src))
    out.append(src[pos:])
    return "".join(out)


def register():
    import tvm_ffi

    @tvm_ffi.register_global_func("tvm_callback_opencl_postproc", override=True)
    def _postproc(code, target):  # noqa: ARG001
        return hoist(str(code))


if __name__ == "__main__":
    demo = """// Function: k
__kernel void k(__global float* a) {
  float x = 0.f;
  if (get_local_id(0) < 4) {
    __local float red_buf0[64];
    red_buf0[get_local_id(0)] = a[0];
  }
  for (int i = 0; i < 2; ++i) {
    __local float red_buf0[64];
    __local int idx;
    a[i] = x;
  }
}
"""
    print(hoist(demo))
