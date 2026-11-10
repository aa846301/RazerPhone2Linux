"""Trace line events inside mlc_llm/model/qwen3_5* during export_tvm; the last printed line precedes the segfault."""
import os, sys, runpy

LOG = os.open("/tmp/trace35.log", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)


def tracer(frame, event, arg):
    fn = frame.f_code.co_filename
    if "qwen3_5" in fn or "qwen35" in fn or "gated_delta" in fn or "nn/op" in fn or "op_ext" in fn:
        if event in ("line", "call"):
            os.write(LOG, f"{event} {fn.split('site-packages/')[-1]}:{frame.f_lineno} {frame.f_code.co_name}\n".encode())
        return tracer
    return tracer if event == "call" else None


sys.argv = ["mlc_step.py"] + sys.argv[1:]
sys.settrace(tracer)
runpy.run_path(os.path.expanduser("~/mlc/mlc_step.py"), run_name="__main__")
