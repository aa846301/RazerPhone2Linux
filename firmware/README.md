# Firmware

This directory is intentionally empty in Git because the Razer/Qualcomm blobs
come from the proprietary Razer Phone 2 factory image.

Put `aura-p-release-3201-user-full.zip` in the repository root (preferred), or
pass a path to `modem.img`, then run from WSL:

```bash
cd /mnt/c/repo/razorphone2linux
bash scripts/extract-modem-firmware.sh
```

The full factory ZIP also supplies the Razer TFA9912 speaker container from
`vendor.img`, installed as `firmware/tfa98xx.cnt`. A standalone `modem.img`
cannot provide that audio firmware and the extraction script will warn.

The full rootfs build also downloads redistributable WCN3990 and Adreno files
from linux-firmware when they are not supplied by the local firmware overlay.
