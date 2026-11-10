"""`python -m mlc_llm ...` with the rusticl OpenCL fix (opencl_local_hoist) registered first."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import opencl_local_hoist  # noqa: E402

opencl_local_hoist.register()
from mlc_llm.__main__ import main  # noqa: E402

sys.argv[0] = "mlc_llm"
main()
