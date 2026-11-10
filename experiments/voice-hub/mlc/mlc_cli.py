"""Run `python -m mlc_llm <subcommand> ...` with a workaround for a nightly bug: printing a tvm Device object
(ConversionArgs.display / compile arg display) segfaults inside tvm::ffi::ReprPrint. The display methods are
replaced with a plain-text version that never formats Device objects."""
import sys


def _safe_display(self):
    fields = {k: v for k, v in vars(self).items() if k != "device"}
    print("args:", {k: str(v) if isinstance(v, (str, int, float)) else type(v).__name__ for k, v in fields.items()})


def main():
    import os
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import rnn_state_fix  # noqa: F401  (multi-dim RNN state parser segfault workaround)
    from mlc_llm.interface import convert_weight as cw
    cw.ConversionArgs.display = _safe_display
    try:
        from mlc_llm.interface import compile as cp
        if hasattr(cp, "CompileArgs"):
            cp.CompileArgs.display = _safe_display
    except Exception:
        pass
    from mlc_llm.__main__ import main as mlc_main
    mlc_main()


if __name__ == "__main__":
    sys.argv[0] = "mlc_llm"
    main()
