# Kernel patch policy

Only production-required patches belong directly in this directory. The
canonical kernel build applies top-level `*.patch` files in lexical order.

Current production delta:

- `0001-remoteproc-qcom-share-razer-fih-nv-with-mss.patch` grants the Razer
  factory FIH NV reserved region to MSS, matching the downstream boot flow.
- `0002-drm-msm-dsi-allow-bootloader-powered-probe.patch` preserves a
  bootloader-powered DSI path while the panel is being brought up.
- `0003-drm-panel-novatek-nt36830-razer-aura.patch` adds the Razer Phone 2
  NT36830 panel implementation.
- `0004-usb-typec-qcom-pmic-pdphy-recovery.patch` carries the production USB
  Type-C/PD recovery and SMB2 adapter allowance changes.
- `0005-power-supply-qcom-smbx-add-charge-behaviour.patch` exposes the
  standard `charge_behaviour` power-supply control and inhibits battery
  charging without suspending external USB input.

Observational logging, crash dumps, QRTR dumps, and live-only experiments are
kept under `diagnostics/` and are not applied by normal builds.

The external kernel checkout under `~/razorphone2linux/kernel/linux` is a
generated build workspace. Project changes are maintained here as DTS, driver
source, config, and patches; they should not be committed to that checkout.
