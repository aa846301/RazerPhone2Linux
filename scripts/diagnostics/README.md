# Bring-up diagnostics

These scripts preserve one-off or narrowly scoped experiments from WiFi, MSS,
rmtfs, QRTR, DIAG, and stock Android comparison work. They do not participate
in `build-all.sh`, rootfs assembly, boot packaging, release artifacts, or
GitHub Actions.

The collection is retained because the project documentation records both
successful and failed hardware experiments. Keeping the exact reproducers
prevents repeating destructive or inconclusive tests from memory.

## Host-side builders and captures

- `build-diag-router-live.sh`
- `build-pdmapper-live.sh`
- `capture-android-wifi-mechanism.sh`
- `deploy-pmos-mss-diag-live.ps1`
- `prepare-rmtfs-detail-live.sh`

## Phone-side experiments

Files named `phone-*.sh` are copied to a live phone and run explicitly. Many
require root and may stop remote processors, replace live modules, alter module
autoload policy, or reboot the device. Read the script and its matching status
document before use. None are safe general-purpose setup commands.

Run host-side commands from the repository root, for example:

```bash
bash scripts/diagnostics/build-pdmapper-live.sh
```
