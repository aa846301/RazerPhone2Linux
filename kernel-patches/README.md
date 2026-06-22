# Kernel patch policy

Only production-required patches belong directly in this directory. The
canonical kernel build applies top-level `*.patch` files in lexical order.

Current production delta:

- `0001-remoteproc-qcom-share-razer-fih-nv-with-mss.patch` grants the Razer
  factory FIH NV reserved region to MSS, matching the downstream boot flow.

Observational logging, crash dumps, QRTR dumps, and live-only experiments are
kept under `diagnostics/` and are not applied by normal builds.

The external kernel checkout under `~/razorphone2linux/kernel/linux` is a
generated build workspace. Project changes are maintained here as DTS, driver
source, config, and patches; they should not be committed to that checkout.
