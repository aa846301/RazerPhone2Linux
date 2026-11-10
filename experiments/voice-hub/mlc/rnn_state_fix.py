"""Workaround for a nightly TVMScript parser segfault (mlc-ai-nightly 0.26.dev246): any annotated local
variable inside a prim_func (e.g. `seq_id: T.int32 = seq_slot_ids[vi]`) crashes the parser
(see tvmscript_min.py: case "local_var"). mlc_llm.nn.rnn_state uses exactly that in its get/set functions,
which Qwen3.5's gated-delta-rule state needs. These replacements inline the index loads instead; the
computed addresses are identical. Supports 1-D to 3-D state shapes. Import before building the model."""
from tvm.script import tirx as T
from mlc_llm.nn import rnn_state as _rs

_orig_get = _rs.RNNState.create_get_func
_orig_set = _rs.RNNState.create_set_func


def _get(shape, dtype, max_batch_size, max_history, state_id):
    if len(shape) == 1:
        (s0,) = shape

        @T.prim_func(s_tir=True)
        def f(var_storage: T.handle, var_seq: T.handle, var_hist: T.handle, var_output: T.handle):
            batch_size = T.int32()
            T.func_attr({"global_symbol": f"rnn_state_get_{state_id}"})
            storage = T.match_buffer(var_storage, (max_batch_size, max_history, s0), dtype)
            seq = T.match_buffer(var_seq, (batch_size,), "int32")
            hist = T.match_buffer(var_hist, (batch_size,), "int32")
            output = T.match_buffer(var_output, (batch_size, s0), dtype)
            for i, a in T.grid(batch_size, s0):
                with T.sblock("copy"):
                    vi, va = T.axis.remap("SS", [i, a])
                    output[vi, va] = storage[seq[vi], hist[vi], va]

        return f
    if len(shape) == 2:
        s0, s1 = shape

        @T.prim_func(s_tir=True)
        def f(var_storage: T.handle, var_seq: T.handle, var_hist: T.handle, var_output: T.handle):
            batch_size = T.int32()
            T.func_attr({"global_symbol": f"rnn_state_get_{state_id}"})
            storage = T.match_buffer(var_storage, (max_batch_size, max_history, s0, s1), dtype)
            seq = T.match_buffer(var_seq, (batch_size,), "int32")
            hist = T.match_buffer(var_hist, (batch_size,), "int32")
            output = T.match_buffer(var_output, (batch_size, s0, s1), dtype)
            for i, a, b in T.grid(batch_size, s0, s1):
                with T.sblock("copy"):
                    vi, va, vb = T.axis.remap("SSS", [i, a, b])
                    output[vi, va, vb] = storage[seq[vi], hist[vi], va, vb]

        return f
    if len(shape) == 3:
        s0, s1, s2 = shape

        @T.prim_func(s_tir=True)
        def f(var_storage: T.handle, var_seq: T.handle, var_hist: T.handle, var_output: T.handle):
            batch_size = T.int32()
            T.func_attr({"global_symbol": f"rnn_state_get_{state_id}"})
            storage = T.match_buffer(var_storage, (max_batch_size, max_history, s0, s1, s2), dtype)
            seq = T.match_buffer(var_seq, (batch_size,), "int32")
            hist = T.match_buffer(var_hist, (batch_size,), "int32")
            output = T.match_buffer(var_output, (batch_size, s0, s1, s2), dtype)
            for i, a, b, c in T.grid(batch_size, s0, s1, s2):
                with T.sblock("copy"):
                    vi, va, vb, vc = T.axis.remap("SSSS", [i, a, b, c])
                    output[vi, va, vb, vc] = storage[seq[vi], hist[vi], va, vb, vc]

        return f
    return _orig_get(shape, dtype, max_batch_size, max_history, state_id)


def _set(shape, dtype, max_batch_size, max_history, state_id):
    if len(shape) == 1:
        (s0,) = shape

        @T.prim_func(s_tir=True)
        def f(var_storage: T.handle, var_seq: T.handle, var_hist: T.handle, var_data: T.handle):
            batch_size = T.int32()
            T.func_attr({"global_symbol": f"rnn_state_set_{state_id}"})
            storage = T.match_buffer(var_storage, (max_batch_size, max_history, s0), dtype)
            seq = T.match_buffer(var_seq, (batch_size,), "int32")
            hist = T.match_buffer(var_hist, (batch_size,), "int32")
            data = T.match_buffer(var_data, (batch_size, s0), dtype)
            for i, a in T.grid(batch_size, s0):
                with T.sblock("copy"):
                    vi, va = T.axis.remap("SS", [i, a])
                    storage[seq[vi], (hist[vi] + 1) % T.cast(max_history, "int32"), va] = data[vi, va]

        return f
    if len(shape) == 2:
        s0, s1 = shape

        @T.prim_func(s_tir=True)
        def f(var_storage: T.handle, var_seq: T.handle, var_hist: T.handle, var_data: T.handle):
            batch_size = T.int32()
            T.func_attr({"global_symbol": f"rnn_state_set_{state_id}"})
            storage = T.match_buffer(var_storage, (max_batch_size, max_history, s0, s1), dtype)
            seq = T.match_buffer(var_seq, (batch_size,), "int32")
            hist = T.match_buffer(var_hist, (batch_size,), "int32")
            data = T.match_buffer(var_data, (batch_size, s0, s1), dtype)
            for i, a, b in T.grid(batch_size, s0, s1):
                with T.sblock("copy"):
                    vi, va, vb = T.axis.remap("SSS", [i, a, b])
                    storage[seq[vi], (hist[vi] + 1) % T.cast(max_history, "int32"), va, vb] = data[vi, va, vb]

        return f
    if len(shape) == 3:
        s0, s1, s2 = shape

        @T.prim_func(s_tir=True)
        def f(var_storage: T.handle, var_seq: T.handle, var_hist: T.handle, var_data: T.handle):
            batch_size = T.int32()
            T.func_attr({"global_symbol": f"rnn_state_set_{state_id}"})
            storage = T.match_buffer(var_storage, (max_batch_size, max_history, s0, s1, s2), dtype)
            seq = T.match_buffer(var_seq, (batch_size,), "int32")
            hist = T.match_buffer(var_hist, (batch_size,), "int32")
            data = T.match_buffer(var_data, (batch_size, s0, s1, s2), dtype)
            for i, a, b, c in T.grid(batch_size, s0, s1, s2):
                with T.sblock("copy"):
                    vi, va, vb, vc = T.axis.remap("SSSS", [i, a, b, c])
                    storage[seq[vi], (hist[vi] + 1) % T.cast(max_history, "int32"), va, vb, vc] = data[vi, va, vb, vc]

        return f
    return _orig_set(shape, dtype, max_batch_size, max_history, state_id)


_rs.RNNState.create_get_func = staticmethod(_get)
_rs.RNNState.create_set_func = staticmethod(_set)
