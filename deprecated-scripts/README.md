# Deprecated Scripts

This folder keeps old bring-up helpers out of the active build path.

Do not run these scripts as part of the normal Razer Phone 2 Linux flow. They
were retained only as references for old experiments, one-off fixes, serial
workarounds, observable boot attempts, and earlier rootfs repair paths.

Current supported entrypoints are:

- `scripts/build-all.sh`
- `scripts/02-build-kernel.sh`
- `scripts/03-build-rootfs.sh`
- `scripts/04-make-boot-image.sh`
- `scripts/05-flash.sh`
- `scripts/06-capture-usb-console.ps1`
- `scripts/extract-modem-firmware.sh`
- `scripts/register-binfmt.sh`

Inventory:

- `root-wrappers/` - old top-level compatibility wrappers such as
  `make-boot.sh` and `rebuild-kernel.sh`.
- `scripts/` - old PowerShell/WSL repair scripts, observable boot tooling,
  SSH/serial workaround deployers, and one-off kernel patch helpers.
- `wsl-scripts/` - old WSL diagnostics, rootfs repair, sparse image repair,
  firmware injection, DTB extraction, and compatibility wrappers.

If one of these helpers becomes necessary again, move the smallest needed logic
back into a supported script or document a new active entrypoint. Do not revive
parallel build flows.
