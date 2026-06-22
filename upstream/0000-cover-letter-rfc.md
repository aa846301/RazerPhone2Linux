Subject: [RFC PATCH 0/6] arm64: qcom: initial Razer Phone 2 support

Add initial mainline support for the Razer Phone 2, also known as `aura`.
The device is based on Qualcomm SDM845.

The current development image boots Ubuntu 24.04 from the userdata
partition. UFS, USB gadget networking, SSH, Synaptics RMI4 touch and the
bootloader-provided framebuffer are usable. WiFi has also been demonstrated,
but currently depends on a Razer/FIH NV reserved-memory handoff plus Qualcomm
userspace services and is kept separate from the minimal board submission.

The built-in NT36830 panel is dual-DSI with DSC. A driver has been generated
and hand-adapted from the factory DTBO, but native DRM scanout is still
experimental. The first board patch should therefore leave MDSS disabled and
must not claim native panel support.

This RFC is intended to establish the acceptable DT representation and patch
split before a send-ready v1. Known gaps and test status are documented in
`upstream/STATUS.md`.

Proposed series:

  1. dt-bindings: arm: qcom: add Razer Phone 2
  2. arm64: dts: qcom: add initial Razer Phone 2 support
  3. dt-bindings: display: panel: add Razer NT36830 panel
  4. drm/panel: add Novatek NT36830 panel support
  5. dt-bindings: remoteproc: document Razer FIH NV memory
  6. remoteproc: qcom_q6v5_mss: share Razer FIH NV memory

The final submission may be split into independent board, panel and
remoteproc series according to maintainer feedback.

Assisted-by: Codex:gpt-5

---

Base tree: to be selected from the current Qualcomm maintainer tree.
Testing: Razer Phone 2 hardware, clean `6.16.0-rc2-sdm845` development build.
Not yet tested: dt_binding_check, full dtbs_check, native NT36830 scanout.
