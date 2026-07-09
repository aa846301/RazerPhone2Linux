# Bring-up log, 2026-07-09

This document records the public-repository consolidation after
`claude/gallant-bun-4a6741`. That branch is the active progress source for
Linux 7.1 native display, GPU, and the WebKit kiosk prototype.

## Integrated into master

- The Linux 7.1 display baseline and the later `claude` native-panel/GPU work
  are now merged into `master`.
- The active project tree keeps only source, configuration, scripts, rootfs
  overlay inputs, documented binaries, and upstream submission material.
- The README is the project introduction and build entrypoint.
- Detailed process notes live under `doc/`.
- GitHub Actions now builds native-panel boot/rootfs artifacts from the
  canonical scripts.

## Preserved source-level work

- SDM845 7.1 kernel pin and config ordering.
- Razer Phone 2 DTS changes.
- NT36830 native dual-DSI/DSC panel driver and LK-aligned timing/DSC fixes.
- Adreno 630 freedreno enablement, including the initramfs firmware hook needed
  because the GPU probes before rootfs mount.
- Validated WebKitGTK/Epiphany + sway Home Assistant kiosk prototype, archived
  under `rootfs-scripts/kiosk-prototype/`.
- Razer-specific kernel patches for FIH NV sharing and upstreamable metadata.
- Rootfs runtime configuration for USB gadget, NetworkManager, WiFi readiness,
  quiet panel console handoff, native-panel color tests, and the base Home
  Assistant hub direction.
- Recovery notes for the known-good 6.16 baseline.

## Deliberately kept out of Git

- Proprietary Razer/Qualcomm firmware blobs.
- Generated `output/` images.
- Factory and reference images.
- One-off diagnostic scripts and captured logs that are not part of the
  reproducible build contract.

Those inputs can still be used locally or inside CI through documented
extraction steps and private workflow secrets.
