# Razer Phone 2 (SDM845) - Linux Flashing Guide

## Prerequisites

- **ADB/Fastboot**: Install Android Platform Tools
- **Unlocked bootloader**: `fastboot flashing unlock`
- All image files in `output/` directory:
  - `boot.img` (16 MB) - Kernel + initramfs
  - `rootfs-sparse.img` (2.5 GB) - Ubuntu 24.04 arm64 + KlipperScreen
  - `vbmeta_disabled.img` (4 KB) - Disabled verified boot

## Flashing Steps

### 1. Boot into Fastboot Mode

```
adb reboot bootloader
```

Or power off, then hold **Volume Down + Power** until fastboot screen appears.

### 2. Flash vbmeta (Disable Verified Boot)

```
fastboot --disable-verity --disable-verification flash vbmeta vbmeta_disabled.img
```

### 3. Flash Boot Image

```
fastboot flash boot boot.img
```

### 4. Flash Rootfs to Userdata

> **WARNING**: This erases all Android data on the phone!

```
fastboot flash userdata rootfs-sparse.img
```

### 5. Reboot

```
fastboot reboot
```

## Login Credentials

| Account | Username | Password |
|---------|----------|----------|
| User    | klipper  | klipper  |
| Root    | root     | klipper  |

## Serial Console

The kernel is configured with serial console on `ttyMSM0` (115200 baud).
USB CDC ACM serial gadget (`ttyGS0`) is also enabled for USB serial access.

## Network

- **NetworkManager** is enabled for WiFi/Ethernet management
- **SSH** is enabled (port 22)

## KlipperScreen

KlipperScreen auto-starts via `xinit-klipperscreen.service` on boot.
Configuration: `/home/klipper/KlipperScreen.conf`
Default Moonraker URL: `http://localhost:7125`

Edit the config to point to your Klipper host:
```
[main]
moonraker_host = <your-klipper-ip>
moonraker_port = 7125
```

## Known Limitations

- **No WiFi/GPU firmware**: Firmware blobs were not included. WiFi and GPU acceleration won't work until firmware is extracted from the stock ROM.
- **Display**: Uses the NT36830-based panel driver. Should work with the mainline DRM/MSM driver.

## Troubleshooting

### Phone doesn't boot
- Ensure vbmeta was flashed with verification disabled
- Try `fastboot flash boot boot.img` again

### No display output
- Connect via USB serial (`ttyGS0`) or SSH to debug
- Check `dmesg | grep drm` for panel driver status

### Revert to Android
Flash original factory images for Razer Phone 2.
