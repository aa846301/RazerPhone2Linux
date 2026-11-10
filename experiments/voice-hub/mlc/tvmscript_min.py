"""Minimal TVMScript parse tests to isolate the nightly parser segfault."""
import sys
from tvm.script import tirx as T
from tvm import tirx

case = sys.argv[1]
print(">>", case, flush=True)
if case == "plain":
    @T.prim_func(s_tir=True)
    def f(a: T.Buffer((4,), "float32"), b: T.Buffer((4,), "float32")):
        for i in range(4):
            with T.sblock("c"):
                vi = T.axis.remap("S", [i])
                b[vi] = a[vi]
elif case == "closure_int":
    n = 4

    @T.prim_func(s_tir=True)
    def f(a: T.Buffer((n,), "float32"), b: T.Buffer((n,), "float32")):
        for i in range(n):
            with T.sblock("c"):
                vi = T.axis.remap("S", [i])
                b[vi] = a[vi]
elif case == "closure_var":
    mb = tirx.Var("max_batch_size", "int64")

    @T.prim_func(s_tir=True)
    def f(var_a: T.handle):
        a = T.match_buffer(var_a, (mb, 4), "float32")
        for i, j in T.grid(mb, 4):
            with T.sblock("c"):
                vi, vj = T.axis.remap("SS", [i, j])
                a[vi, vj] = T.float32(0)
elif case == "dyn_batch":
    @T.prim_func(s_tir=True)
    def f(var_a: T.handle):
        batch_size = T.int32()
        a = T.match_buffer(var_a, (batch_size, 4), "float32")
        for i, j in T.grid(batch_size, 4):
            with T.sblock("c"):
                vi, vj = T.axis.remap("SS", [i, j])
                a[vi, vj] = T.float32(0)
elif case == "attr_fstring":
    sid = 3

    @T.prim_func(s_tir=True)
    def f(a: T.Buffer((4,), "float32")):
        T.func_attr({"global_symbol": f"fn_{sid}"})
        for i in range(4):
            with T.sblock("c"):
                vi = T.axis.remap("S", [i])
                a[vi] = T.float32(0)
elif case == "local_var":
    @T.prim_func(s_tir=True)
    def f(a: T.Buffer((4,), "int32"), b: T.Buffer((4,), "int32")):
        for i in range(4):
            with T.sblock("c"):
                vi = T.axis.remap("S", [i])
                x: T.int32 = a[vi]
                b[vi] = x
print("ok", case, flush=True)
