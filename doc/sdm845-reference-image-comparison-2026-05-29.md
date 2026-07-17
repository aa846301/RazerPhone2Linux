# SDM845 Reference Image Comparison - 2026-05-29

Goal: stop guessing around the Razer Phone 2 WiFi failure and compare our
bring-up chain against a working SDM845 Linux image.

## Current Boundary

Razer Phone 2 currently reaches this point:

1. `rmtfs` starts and powers MSS.
2. MBA/MPSS firmware loads.
3. MSS reaches `remote processor 4080000.remoteproc is now up`.
4. QRTR exposes modem root services 66/43.
5. The modem asks PDM only for `tms/pddump_disabled`.
6. MSS fatal-errors about 0.24 seconds later.
7. No `wlan/fw`, no `kernel/elf_loader`, no `wlanmdsp.mbn` TFTP request, no
   WLFW service 69, no `wlan0`.

Therefore the immediate fault is before ath10k board data, before NetworkManager,
and before the WCN3990 WLAN firmware subdomain is requested.

## First-Principles Startup Chain

For SDM845 WCN3990, WiFi is not an independent PCIe/USB device. It is a
remoteproc/service chain:

1. Kernel + DT create MSS, WLAN MSA, MPSS/MBA memory, QRTR/glink, rmtfs shared
   memory, IPA, and WCN3990 SNOC nodes.
2. Userspace starts QRTR support, PD mapper, TFTP service, and rmtfs.
3. rmtfs exposes modemst/fsg/fsc/nvdef storage and powers MSS through the
   remoteproc handle.
4. MSS root_pd boots and asks the protection-domain mapper where services live.
5. If root_pd proceeds, wlan_pd requests `kernel/elf_loader` and `wlan/fw`.
6. tqftpserv serves `wlanmdsp.mbn`.
7. WLFW appears on QRTR.
8. `ath10k_snoc` can then complete QMI firmware bring-up and create `wlan0`.

Our failure is between steps 4 and 5.

## Reference Image Used

Reference image:

- Device: OnePlus 6 / `oneplus-enchilada`
- OS: postmarketOS `v25.12`, phosh
- Image directory:
  `https://images.postmarketos.org/bpo/v25.12/oneplus-enchilada/phosh/20260525-1750/`
- Full image sha256:
  `8e3c977628583ce7771d4cfaccdb731fa6118c4d638736f68e3f0f1f07aabbc9`
- Boot image sha256:
  `8197686ac737495106b3ef83af1ba4160d2d66510395e91945d10731f0981daf`
- pmaports clone inspected at commit `817ed87`.

The downloaded image was an Android sparse image. It was converted with
`simg2img`, then split into:

- `pmOS_boot`: ext2, contains `boot.img`, `initramfs`,
  `sdm845-oneplus-enchilada.dtb`.
- `pmOS_root`: ext4, contains the real systemd rootfs.

Temporary extraction paths are under:

```text
.tmp/pmos-reference/
```

## What Matched

The main SDM845 hardware description is very close to our mainline base:

- `mss_pil` compatible is `qcom,sdm845-mss-pil`.
- MSS registers, interrupts, reset names, halt regs, glink edge, memory regions,
  and power domains match the mainline SDM845 structure.
- `wlan-msa@8df00000`, `mpss@8e000000`, `mba@96500000`, and
  `mpss-metadata` layout matches the expected SDM845 layout.
- WCN3990 node uses `qcom,wcn3990-wifi`, `qcom,snoc-host-cap-8bit-quirk`,
  and a board-data calibration variant.
- `modemr.jsn` / `modemuw.jsn` content is structurally identical to Razer:
  `msm/modem/root_pd`, `msm/modem/wlan_pd`, instance `180`,
  `tms/servreg`, `kernel/elf_loader`, and `wlan/fw`.

This makes a generic "copy OnePlus DTS WiFi block" unlikely to fix the current
0.24 second root_pd fatal. The failing boundary is earlier than the actual
WLAN firmware request.

## What Differed

### 1. Working pmOS runs userspace pd-mapper

The reference rootfs has:

```text
/usr/lib/systemd/system/pd-mapper.service
/usr/lib/systemd/system/tqftpserv.service
/usr/lib/systemd/system/rmtfs.service
```

Service contents from the extracted rootfs:

```ini
[Service]
ExecStart=/usr/bin/pd-mapper
Restart=always
RestartSec=1
```

```ini
[Unit]
Description=QRTR TFTP services
Before=rmtfs.service

[Service]
ExecStart=/usr/bin/tqftpserv
Restart=always
RestartSec=1
```

```ini
[Unit]
Description=Qualcomm remotefs service
Before=NetworkManager.service

[Service]
ExecStart=/usr/bin/rmtfs -r -P -s
Restart=always
RestartSec=1
```

The reference rootfs enables all three in `multi-user.target.wants`.

Our current rootfs primarily uses the kernel module `qcom_pd_mapper`. The
kernel mapper should work in theory, but the working SDM845 image still carries
and starts userspace `pd-mapper`. This is the strongest new test variable.

External support for this direction:

- postmarketOS issue #863 notes `tqftpserv` and `pd-mapper` are part of the QRTR
  service stack on Qualcomm devices.
- postmarketOS MR !1700 explicitly says updating `qrtr` and `pd-mapper` was
  needed to fix modem and ADSP crashes on SDM845 OnePlus 6 and Poco F1.
- Linux Kconfig documents `CONFIG_QCOM_PD_MAPPER` as a simpler in-kernel
  alternative to the userspace daemon, not as proof that userspace behavior is
  identical in every failure mode.
- Debian's `pd-mapper` ITP describes it as the reference implementation for
  mapping remote processor services including WiFi/modem/sensors on recent
  Qualcomm SoCs.

Sources:

- https://gitlab.com/postmarketOS/pmaports/-/work_items/863
- https://gitlab.com/postmarketOS/pmaports/-/merge_requests/1700
- https://cateee.net/lkddb/web-lkddb/QCOM_PD_MAPPER.html
- https://lists.debian.org/debian-devel/2022/07/msg00260.html

### 2. pmOS service order is explicit

pmOS declares:

```text
tqftpserv.service Before=rmtfs.service
rmtfs.service Before=NetworkManager.service
msm-modem-uim-selection.service After=rmtfs.service Requires=rmtfs.service
```

`pd-mapper.service` has no explicit `Before=rmtfs.service`, but it is enabled in
the same target and restarts persistently.

For our device, auto-starting rmtfs causes crash loops, so this should not be
copied directly into boot. It should be reproduced through the controlled
late-start path.

### 3. pmOS kernel config keeps the chain modular

pmOS reference kernel has:

```text
CONFIG_QCOM_Q6V5_MSS=m
CONFIG_QCOM_Q6V5_ADSP=m
CONFIG_QCOM_Q6V5_PAS=m
CONFIG_QCOM_SYSMON=m
CONFIG_QCOM_PD_MAPPER=m
CONFIG_QCOM_PDR_HELPERS=y
CONFIG_QCOM_PDR_MSG=y
CONFIG_QCOM_RMTFS_MEM=y
CONFIG_QCOM_IPA=m
CONFIG_ATH10K_SNOC=m
CONFIG_RESET_QCOM_PDC=m
```

Our built WSL `.config` now also has the WiFi/MSS chain modular except
`RESET_QCOM_PDC=y`, which we intentionally keep built-in because a prior boot
logged `failed to acquire pdc reset` when it was not ready early enough.

### 4. Firmware paths are normal per-device qcom paths

pmOS OnePlus firmware lives under:

```text
/lib/firmware/qcom/sdm845/oneplus6/
```

and includes:

```text
mba.mbn
modem.mbn
modemr.jsn
modemuw.jsn
wlanmdsp.mbn
adsp.mbn
slpi.mbn
cdsp.mbn
ipa_fws.mbn
```

It does not rely on `/lib/firmware/image` for the primary DT firmware names.
However, `tqftpserv` searches `/lib/firmware/` and `/readonly/firmware/image/`.
Our rootfs already creates the `/lib/firmware/image` and `/readonly` aliases for
Razer, and earlier live testing proved missing aliases were not the immediate
0.24 second fatal trigger.

## New Highest-Value Test

Run a live-only userspace `pd-mapper` contrast test:

1. Stop `rmtfs`.
2. Remove kernel `qcom_pd_mapper`.
3. Start userspace `/tmp/pd-mapper-live`.
4. Start `tqftpserv`.
5. Load `qcom_q6v5_mss`.
6. Disable MSS recovery.
7. Start `rmtfs-razer-test -r -P -s -v`.
8. Watch whether MSS still asks only for `tms/pddump_disabled`, or progresses to
   `kernel/elf_loader`, `wlan/fw`, `wlanmdsp.mbn`, WLFW, and `wlan0`.

Build the ARM64 live diagnostic binary from WSL:

```bash
cd /mnt/c/repo/razorphone2linux
bash scripts/diagnostics/build-pdmapper-live.sh
```

Deploy/run when SSH works:

```powershell
scp -i C:\tmp\razer_usb_ed25519 -o UserKnownHostsFile=C:\tmp\razer_known_hosts output\pd-mapper-live\pd-mapper-live klipper@192.168.137.133:/tmp/pd-mapper-live
scp -i C:\tmp\razer_usb_ed25519 -o UserKnownHostsFile=C:\tmp\razer_known_hosts scripts\phone-userspace-pdmapper-test.sh klipper@192.168.137.133:/tmp/phone-userspace-pdmapper-test.sh
ssh -i C:\tmp\razer_usb_ed25519 -o UserKnownHostsFile=C:\tmp\razer_known_hosts klipper@192.168.137.133 "chmod +x /tmp/pd-mapper-live /tmp/phone-userspace-pdmapper-test.sh && sudo /tmp/phone-userspace-pdmapper-test.sh"
```

This does not require a rootfs rebuild or flash.

## Decision Logic

If userspace `pd-mapper` changes the failure:

- If WLFW appears, continue from ath10k/firmware/QMI.
- If a new PDM request appears, follow that exact missing service.
- If fatal moves later, keep userspace pd-mapper as the active direction and
  make it reproducible in rootfs after one more confirmation.

If userspace `pd-mapper` does not change anything:

- The remaining blocker is likely below service mapping: MSS firmware's
  root_pd initialization, RFS/NV protocol content, or Razer-specific
  downstream modem-side expectations.
- Next useful comparison should be Android/downstream MSS logging/minidump or
  RFS packet-level instrumentation, not another ath10k board-data or service
  ordering permutation.

## Live Results

The OnePlus/postmarketOS service model was reproduced live without rebuilding or
flashing rootfs:

1. The phone's kernel `qcom_pd_mapper.ko` was temporarily moved to
   `qcom_pd_mapper.ko.disabled`, `depmod` was run, and the device was rebooted.
2. `qrtr-ns` and `tqftpserv` were active before MSS startup.
3. A live-built ARM64 `pd-mapper` was started from `/tmp/pd-mapper-live`.
4. `rmtfs-razer-test -r -P -s -v` was started manually to power MSS.

Result:

- QRTR showed userspace service 64 from `pd-mapper`.
- Kernel `qcom_pd_mapper` was not loaded.
- rmtfs opened all six Razer RFS targets and completed the same initial reads.
- modem node 0 asked only for `tms/pddump_disabled`.
- userspace `pd-mapper` responded with zero domains.
- MSS still fataled about 0.25 seconds after `remote processor ... is now up`.
- No `kernel/elf_loader`, no `wlan/fw`, no `wlanmdsp.mbn` TFTP request, no
  WLFW service 69, and no `wlan0`.

The kernel mapper was then restored and the patched in-kernel mapper was tested
with `tms/pddump_disabled` explicitly mapped to `msm/modem/root_pd`.

Result:

- modem node 0 again asked only for `tms/pddump_disabled`.
- the kernel mapper responded `len=1 total=1`.
- MSS still fataled at the same boundary.

Conclusion: the OnePlus/postmarketOS userspace mapper/service ordering is now
tested and does not move the Razer failure. The immediate blocker is not
kernel-vs-userspace `pd-mapper`, service 64 availability, or the
`tms/pddump_disabled` response alone. Further work should not keep rebuilding
rootfs for service ordering. The next useful directions are:

- instrument RFS reads/writes enough to identify the exact NV/EFS content being
  consumed immediately before fatal;
- find a modem dump/minidump/DIAG path that exposes the MSS-side fatal reason;
- compare Razer downstream modem/RFS handling against mainline for behavior not
  represented in the generic SDM845 OnePlus stack.

Additional read-only RFS inspection after the failed kernel-mapper run:

- `modemst1`: 2 MiB,
  `79f39404638623479b1e1373c786d09e9cd73df0981978dfe6b387614755d743`
- `modemst2`: 2 MiB,
  `d2ab58099ca7132ac436db84cd71a26dbdc1b27246ebd40c2093868aa29f859e`
- `fsg`: 2 MiB,
  `5647f05ec18958947d32874eeb788fa396a05d0bab7c1b71f112ceb7e9b31eee`
- `fsc`: 128 KiB,
  `fa43239bcee7b97ca62f007cc68487560a39e19f74f3dde7486db3f98df8e471`
- `nvdef_a` / `nvdef_b`: 4 MiB each, both
  `829d5eb102cf0614f5a3f46b2cc7b0f516e967fcd046c03e3f4acee290cb2ce0`

The final RFS reads before fatal were:

- `modemst2` sector 1:
  `0777e1439f7ecc30f540a2967c72eb622600355dc32d9007ee7d17dd43ee9244`
- `fsg` sector 4094:
  `076a27c79e5ace2a3d47f9dd2e83e4ff6ea8872b3c2218f66c92b89b55f36560`
  and its first 128 bytes were all zero.

This does not prove RFS data is wrong, but it is the closest observed data
access before the fatal and should be the next place to instrument before
changing DTS or rootfs services again.

## postmarketOS Kernel Contrast Artifact

Prepared a controlled kernel-baseline comparison that keeps the Razer-specific
parts in place:

- kernel source: `https://gitlab.com/sdm845-mainline/linux.git`
- tag: `sdm845-6.11`
- commit: `2fa43795f607c67020ac78662e12ecb89a9d737c`
- config source:
  `.tmp/pmos-reference/pmaports/device/community/linux-postmarketos-qcom-sdm845/config-postmarketos-qcom-sdm845.aarch64`
- DTS: repo `dts/sdm845-razer-aura.dts`, copied into the pmOS kernel tree
- retained Razer pieces: factory firmware, RFS/rootfs partition mapping,
  Ubuntu rootfs, Helix/USB gadget runtime config

The only DTS compatibility transform is removing the disabled DSI1
`assigned-clock-parents` block because Linux 6.11's SDM845 DSI PHY headers do
not define the newer `DSI_BYTE_PLL_CLK` and `DSI_PIXEL_PLL_CLK` constants used
by the newer mainline DTS. MDSS/DSI remains disabled for this contrast.

Canonical commands:

```bash
cd /mnt/c/repo/razorphone2linux
bash scripts/build-all.sh pmos-kernel
bash scripts/build-all.sh pmos-contrast
```

Current prepared artifact:

- flavor: `pmos-sdm845-contrast`
- kernel/rootfs module release:
  `6.11.0-sdm845-g2fa43795f607-dirty`
- pmOS WiFi/MSS modules installed as `.ko.zst`:
  `ath10k_core`, `ath10k_snoc`, `qcom_q6v5_mss`, `qcom_sysmon`,
  `qcom_pd_mapper`
- `CONFIG_SCSI_UFS_QCOM=y`
- `CONFIG_PHY_QCOM_QMP_UFS=y`
- `CONFIG_QCOM_RMTFS_MEM=y`
- `CONFIG_QCOM_IPA=m`
- `CONFIG_QRTR=m`
- `CONFIG_QCOM_Q6V5_MSS=m`
- `CONFIG_QCOM_PD_MAPPER=m`

Generated flashable files:

- `output/boot.img`
- `output/rootfs-sparse.img`
- `output/vbmeta_disabled.img`

This is the next useful flash test because it changes the SDM845 kernel patch
and config baseline without changing the Razer firmware/NV/rootfs mapping. If
the failure boundary changes, compare pmOS 6.11 remoteproc/QRTR/PDR/rmtfs/IPA
behavior against the current kernel. If the boundary remains identical, the
evidence points away from generic SDM845 kernel patch/config differences and
back toward Razer-specific modem/RFS/NV/downstream expectations.

## Concrete Crash Evidence Gate

Before changing DTS, services, RFS mapping, firmware layout, or rootfs packages
again, collect one concrete MSS crash evidence bundle:

```bash
sudo /tmp/phone-mss-crash-evidence.sh
```

Source script:

```text
scripts/diagnostics/phone-mss-crash-evidence.sh
```

The script is live-only and captures:

- remoteproc sysfs state and coredump mode;
- `/sys/kernel/debug/remoteproc/remoteproc*/trace*`, carveouts, and resource
  table if the modem firmware exposes them;
- `/sys/class/devcoredump/devcd*/` metadata and the first 16 MiB of any dump,
  plus `strings`;
- pstore contents;
- dynamic-debug dmesg for remoteproc/q6v5/QRTR/PDR;
- QRTR service polling through the 0.25 second crash window;
- rmtfs and tqftpserv journals.

This evidence gate exists because the project has already tested multiple
service-order, pd-mapper, firmware-alias, RFS-mapping, and module-order
hypotheses without moving the fatal boundary. The next decision should come
from a crash reason, remoteproc trace, devcoredump string, or proof that these
channels are unavailable on the current kernel.

### Evidence Results on pmOS Kernel Contrast

Artifact under test:

- kernel: `6.11.0-sdm845-g2fa43795f607-dirty`
- flavor: `pmos-sdm845-contrast`
- evidence archives:
  - `output/mss-crash-evidence-text.tar.gz`
  - `output/mss-crash-evidence-diag-text.tar.gz`
  - `output/mss-crash-evidence-noipa-text.tar.gz`

Direct evidence from the first capture:

- no `trace0` / `trace1` entries under remoteproc debugfs;
- no pstore crash contents;
- no `/sys/class/devcoredump/devcd*` data after MSS fatal;
- remoteproc state after test: `4080000.remoteproc` is `crashed`,
  `recovery=disabled`, `coredump=enabled`;
- QRTR never shows WLFW service 69;
- MSS node 0 only reaches services 66/43, then disappears.

Added live diagnostic patch:

```text
kernel-patches/pmos-contrast/0001-qcom-q6v5-dump-mss-crash-smem.patch
```

This patch only logs SMEM crash items at q6v5 fatal/watchdog IRQ time. It does
not change DTS, firmware, RFS mapping, service ordering, or remoteproc behavior.

Result with the diagnostic module loaded:

```text
qcom-q6v5-mss 4080000.remoteproc: fatal error without message
qcom-q6v5-mss 4080000.remoteproc: q6v5 diag fatal: smem host=-1 item=421 err=-2
qcom-q6v5-mss 4080000.remoteproc: q6v5 diag fatal: smem host=1 item=421 err=-2
qcom-q6v5-mss 4080000.remoteproc: q6v5 diag fatal: smem host=-1 item=6 err=-2
qcom-q6v5-mss 4080000.remoteproc: q6v5 diag fatal: smem host=1 item=6 err=-2
```

Interpretation: at the fatal IRQ boundary, the modem has not written the normal
MPSS crash reason SMEM item 421 in either the global or modem host view. This is
not a hidden printable crash string; the item is absent (`-ENOENT`).

IPA was then removed live before starting MSS:

```text
ipa 1e40000.ipa: IPA driver removed
```

Result without IPA:

```text
PDM: service 'tms/pddump_disabled' offset -1 returning 0 domains (of 0)
remoteproc remoteproc3: remote processor 4080000.remoteproc is now up
qcom-q6v5-mss 4080000.remoteproc: fatal error without message
qcom-q6v5-mss 4080000.remoteproc: q6v5 diag fatal: smem host=-1 item=421 err=-2
```

Interpretation: IPA is not the immediate fatal trigger. With IPA unloaded, MSS
still crashes at the same root service boundary and still writes no SMEM crash
reason.

Current evidence-based boundary:

1. MBA boots and MPSS loads.
2. RFS opens all mapped partitions and performs the same final reads.
3. QRTR root services 66/43 appear on node 0.
4. PDM handles `tms/pddump_disabled`.
5. No WLFW, no WLAN PD, no TFTP WLAN request.
6. MSS asserts fatal IRQ without writing MPSS crash reason SMEM.

Next concrete direction should be lower than userspace service ordering:

- instrument qcom_q6v5_mss register/RMB state at fatal time, not only SMEM;
- compare downstream Razer MSS reset/power sequencing and RMB register writes;
- find a DIAG/minidump path outside mainline remoteproc, because mainline
  remoteproc trace/devcoredump/pstore did not expose MSS internals here.

### pmOS MSS Register Diagnostic Staging

On 2026-05-29, a pmOS-only live diagnostic patch set was prepared but not
flashed into rootfs:

```text
kernel-patches/pmos-contrast/0001-qcom-q6v5-dump-mss-crash-smem.patch
kernel-patches/pmos-contrast/0002-qcom-q6v5-mss-dump-registers-on-crash.patch
scripts/diagnostics/deploy-pmos-mss-diag-live.ps1
output/live-modules/pmos-mss-diag/kernel/drivers/remoteproc/qcom_q6v5.ko.zst
output/live-modules/pmos-mss-diag/kernel/drivers/remoteproc/qcom_q6v5_mss.ko.zst
```

The diagnostic modules were built against the current pmOS contrast release:

```text
6.11.0-sdm845-g2fa43795f607-dirty
```

Initial staged hashes:

```text
qcom_q6v5.ko.zst     2c1ce8c0b0656123a64847e61543ae38b0bfcc012143c0b1597946dbcc8cd047
qcom_q6v5_mss.ko.zst f442183b42e4cddf3cc9b7341fc0c606ac373631218fba69c399ac000ac543cb
```

The canonical pmOS kernel output was rebuilt immediately afterward without
`PMOS_APPLY_DIAG_PATCHES=1`, so `output/Image.gz`, `output/Image.gz-dtb`, and
the default `output/modules_install` are back to the non-diagnostic baseline.
The risky register-dump modules exist only under `output/live-modules/`.

Use this only as a controlled live test, not as a normal flash artifact:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\deploy-pmos-mss-diag-live.ps1
```

The script verifies that the live phone's `uname -r` matches
`output/kernel.release`, copies only `qcom_q6v5.ko.zst` and
`qcom_q6v5_mss.ko.zst`, runs `depmod`, and reboots. Do not refresh or flash
rootfs just to run this test.

Live result after deployment:

- archive: `output/mss-crash-evidence-pmos-mss-regdiag.tar.gz`
- extracted directory: `output/mss-crash-evidence-pmos-mss-regdiag/`
- SMEM crash reason stayed absent:
  - `host=-1 item=421 err=-2`
  - `host=1 item=421 err=-2`
  - `host=-1 item=6 err=-2`
  - `host=1 item=6 err=-2`
- safe RMB values captured at both fatal and watchdog:
  - `RMB_MBA_IMAGE[0x000]=0x96500000`
  - `RMB_PBL_STATUS[0x004]=0x00000001`
  - `RMB_MBA_COMMAND[0x008]=0x00000000`
  - `RMB_MBA_STATUS[0x00c]=0x00000004`
  - `RMB_PMI_META[0x010]=0xbfffc000`
  - `RMB_PMI_CODE_START[0x014]=0x8e000000`
  - `RMB_PMI_CODE_LENGTH[0x018]=0x077685ad`
  - `RMB_MBA_MSS_STATUS[0x040]=0x0000000b`
  - `RMB_MBA_ALT_RESET[0x044]=0x00000000`
- `qrtr-lookup` still showed modem node 0 services 66/43, RFS, service 64,
  and TFTP, but no WLFW service 69.
- rmtfs again opened all six RFS targets and completed the same reads before
  the fatal.

The first version of the register-dump patch continued after RMB and read
post-fatal QDSP6/halt registers. That is unsafe on this device: it caused a
kernel synchronous external abort from `q6v5_mss_diag_dump_reg` in the
q6v5 fatal/watchdog IRQ thread. The phone was immediately restored to stable
modules:

```text
qcom_q6v5.ko.zst     d92811d61363ceaa918c14b6209d318410fa6ad9b523cdc28ab8c0fbc78a94dc
qcom_q6v5_mss.ko.zst 9a5b4136a6b4c851e0767b645cad34bbbfab541b74f769a9e1a89a25951f3ad4
```

The repo patch was then corrected to dump only the verified-safe RMB window.
The refreshed safe staged diagnostic module hashes are:

```text
qcom_q6v5.ko.zst     2c1ce8c0b0656123a64847e61543ae38b0bfcc012143c0b1597946dbcc8cd047
qcom_q6v5_mss.ko.zst 1f46c25a5a4820290c744adabdf1265ceb8d492a9ff53a64912ee1e267c2980c
```

The default pmOS kernel output was rebuilt once more without
`PMOS_APPLY_DIAG_PATCHES=1`, so `output/modules_install` and the live phone are
back on the stable hashes above. Do not deploy any diagnostic module whose
`qcom_q6v5_mss.ko.zst` hash is
`f442183b42e4cddf3cc9b7341fc0c606ac373631218fba69c399ac000ac543cb`; that was
the unsafe QDSP6/halt-register build.
