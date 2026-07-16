# CI and release workflow

The public repository builds flashable images with GitHub Actions through
`.github/workflows/build-image.yml`. It uses GitHub's `ubuntu-24.04-arm`
hosted runners. A `master` push warms caches in the default-branch scope; a
pushed `v*` tag restores those caches, assembles the flashable images, and
publishes the release.

GitHub isolates caches created by different tags. Always wait for the matching
`master` run to finish before pushing a release tag. That master run executes
three independent jobs in parallel:

- `seed-firmware`: download the factory package once, extract modem/WiFi and
  Bluetooth firmware, then save only the reusable blobs.
- `seed-kernel`: restore kernel core/ccache, build the current DTB and any
  missing core objects, then save Image/modules/config/fingerprints.
- `seed-rootfs-base`: debootstrap and install the distribution, packages,
  users, BlueZ, NetworkManager, and selected userspace profile without waiting
  for kernel modules or proprietary firmware.

The tag build restores all three products. `03-refresh-rootfs.sh` is the join
point: it installs current firmware and modules into the rootfs base, applies
services/runtime configuration, regenerates initramfs and sparse rootfs, and
then `04-make-boot-image.sh` packages the boot image.

## What the Action does

- Selects `none`, `ha`, or `3dprinter` from the release tag suffix.
- Restores factory firmware previously extracted in the `master` cache warm-up
  or imports it from the configured large-file URL on a cache miss.
- Installs and verifies the Ubuntu 24.04 arm64 build toolchain.
- Clones the pinned SDM845 kernel commit from `config/kernel-source.env`.
- Applies the repository DTS, panel driver, kernel patches, config fragments,
  rootfs overlay, and the native-panel/GPU build setting.
- Runs the canonical scripts with `03-build-rootfs.sh` in base-only mode for
  the parallel seed job, followed by `03-refresh-rootfs.sh` at the join point.
- Uploads one release zip containing only the flashable images: `boot.img`,
  `rootfs-sparse.img`, and `vbmeta_disabled.img`.

## Firmware policy

Razer/Qualcomm proprietary firmware is intentionally not stored in Git. For CI,
set `RAZER_FACTORY_ZIP_URL` as a repository variable or secret pointing to
`aura-p-release-3201-user-full.zip`. Use a variable for a public upstream URL,
or a secret plus optional `RAZER_FACTORY_ZIP_AUTH_HEADER` for a private
large-file URL. The Action downloads it during the run, extracts the firmware
into the temporary checkout, and never commits the blobs back to the repository.

If the secret is absent, CI fails before the rootfs build. This keeps public
artifacts from looking complete while missing the firmware required for the
validated native panel/GPU path.

## Manual release flow

1. Push the intended commit to `master`.
2. Wait for all three master cache-seed jobs to succeed.
3. For the app-free image, tag `v1.0.0`.
4. For Home Assistant, tag `v1.0.0-ha`.
5. For the 3D-printer stack, tag `v1.0.0-3dprinter`.
6. Download the release zip from the workflow run.
7. Flash both A/B boot slots and userdata as documented in `FLASH-GUIDE.md`.
