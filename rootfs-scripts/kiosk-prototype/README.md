# HA dashboard kiosk prototype (validated 2026-07-09)

Working end-to-end graphics + touch stack on the native display driver,
validated live on the device against https://demo.home-assistant.io.
These files are the archive of that prototype; nothing here is installed
by the build pipeline yet — productizing this is the Home Assistant task.

## Validated stack

- Panel: native NT36830 dual-DSI + DSC (kernel-patches/0002+0003)
- GPU: Adreno 630 hardware GL via freedreno
  - `a630_sqe.fw` must be the linux-firmware version (>= v190); the copy
    on the Android vendor partition is v176 and mainline rejects it
  - `a630_zap.*` (device-signed) extracted from vendor_a partition,
    lives in `firmware/qcom/sdm845/Razer/aura/`
  - firmware must be inside the initramfs (GPU probes at ~2.5s, before
    rootfs mount) — handled by
    `rootfs-scripts/initramfs-tools/razer-gpu-firmware`
- Compositor: sway with `sway-kiosk.conf`
  (landscape via `transform 90`, UI scale 2 => logical 1280x720)
- Browser: epiphany (WebKitGTK), fullscreen via for_window rule
- Touch: Synaptics S3708AR via mainline rmi4 (already in DTS), works
  through libinput/sway including rotation coordinate transform

## Packages used on the device (apt, not yet in 03-build-rootfs.sh)

cage epiphany-browser seatd evtest wlr-randr libinput-tools sway wev

## Gotchas learned

- cage 0.1.5 is a dead end: crashes (wlr scene assertion) on any runtime
  output reconfiguration (wlr-randr transform), and segfaults under
  pixman software rendering with a real client. sway is fine.
- Without a GPU, WebKitGTK 2.44 segfaults probing the dead render node
  (needs WEBKIT_DISABLE_DMABUF_RENDERER=1 + LIBGL_ALWAYS_SOFTWARE=1 to
  survive, and then cage still crashes) — hardware GL is the real fix.
- wev buffers stdout when piped: use `stdbuf -oL wev`, and its touch
  lines read `[wl_touch] down:` (not "touch_down").
- `touchviz.html` draws green dots for touch events / red for emulated
  mouse events with an on-screen event log — instant on-device
  visual check for offset / phantom-double-tap complaints.
