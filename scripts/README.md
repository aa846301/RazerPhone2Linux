# Script layout

The top-level `scripts/` directory contains supported build and maintenance
entry points. Scripts under `scripts/diagnostics/` are retained experiment
reproducers and are never called by normal local or GitHub Actions builds.

## Release build entry points

- `01-setup-environment.sh`: provision the WSL/Linux build environment.
- `02-build-kernel.sh`: build or restore the production kernel, DTBs, modules,
  and kernel core cache.
- `03-build-rootfs.sh`: create a new reusable ARM64 rootfs base.
- `03-refresh-rootfs.sh`: refresh a cached rootfs with current modules,
  firmware, services, and initramfs.
- `04-make-boot-image.sh`: package the final Android boot image.
- `build-all.sh`: canonical Linux/WSL dispatcher.
- `build-all-wsl.ps1`: canonical Windows wrapper for operations requiring a
  root-owned rootfs phase.

## Alternate and shared build helpers

- `02-build-pmos-kernel-contrast.sh`: optional postmarketOS kernel contrast.
- `ci-apt-install.sh`: retrying package installation for GitHub Actions.
- `extract-modem-firmware.sh`: extract the factory firmware overlay.
- `kernel-core-cache-key.sh` and `rootfs-cache-key.sh`: reusable cache keys.
- `register-binfmt.sh`: register ARM64 QEMU execution for rootfs work.

## Maintenance tools

- `06-capture-usb-console.ps1`: capture the USB serial console.
- `deploy-live-module.ps1`: deploy a matching same-release kernel module.
- `generate-panel-driver.sh`: regenerate the experimental panel patch input.
- `linux_cdc_acm.inf`: Windows USB serial driver metadata.
- `prepare-upstream-rfc.sh`: prepare an upstream patch series.
- `razer-charge-limits-selftest.sh`: test charging policy logic.

See `diagnostics/README.md` before running any bring-up experiment.
