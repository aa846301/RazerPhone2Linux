# Rootfs userspace profiles

The base image is intentionally app-free. It contains the hardware platform:
kernel, firmware layout, charging limits, panel sleep helpers, USB networking,
SSH, WiFi bring-up, and recovery/debug basics.

Optional userspace profiles are selected with `RAZER_USERSPACE_PROFILE`:

- `none`: default app-free release image.
- `ha`: Home Assistant kiosk-oriented packages and prototype files.
- `3dprinter`: Klipper/Moonraker/HelixScreen printer host stack.

GitHub Actions maps release tag suffixes to these profiles:

- `v1.0.0` -> `none`
- `v1.0.0-ha` -> `ha`
- `v1.0.0-3dprinter` -> `3dprinter`
