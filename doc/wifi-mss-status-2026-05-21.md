# Razer Phone 2 Linux WiFi/MSS Status - 2026-05-21

This document summarizes the current WiFi bring-up state for asking another
engineer or AI for review. The target device is Razer Phone 2 (`razer-aura`,
Qualcomm SDM845). The practical product goal is a phone-hosted Klipper device:
HelixScreen on the local touchscreen, Klipper/Moonraker in the background, USB
and WiFi networking.

## External Reference Considered

Reference project:

- https://github.com/umeiko/KlipperPhonesLinux
- https://github.com/umeiko/KlipperPhonesLinux/tree/main/LinuxKernels
- https://github.com/jhugo/linux/tree/5.5rc2_wifi

Relevant takeaways from that project:

- It treats the phone as a Klipper host with native Linux, touchscreen UI, SSH,
  USB serial terminal, and preinstalled Klipper-related services.
- The porting flow is kernel-first: pick or build a mainline/postmarketOS-style
  kernel, install kernel/modules into a base rootfs, copy device firmware into
  `/lib/firmware`, then package boot/rootfs images.
- For networking, the guide explicitly calls out copying model firmware into
  the filesystem before expecting networking/GPU to work. This matches our
  current conclusion: our failure is below NetworkManager and must be solved in
  kernel/DTS/firmware/rmtfs/MSS before WiFi UI configuration matters.
- The MSM8998/SDM845 WiFi bring-up recipe is a full chain, not a single kernel
  module: QRTR service lookup, rmtfs, pd-mapper, tqftpserv, `wlanmdsp.mbn`,
  `modemuw.jsn`, WCN3990 `firmware-5.bin`, and `board-2.bin` generated from
  OEM `bdwlan*` data.
- In the current Linux source used by this repo there is no `CONFIG_QRTR_GLINK`
  Kconfig symbol. The QRTR transport symbols are `CONFIG_QRTR_SMD`,
  `CONFIG_QRTR_TUN`, and `CONFIG_QRTR_MHI`, with Qualcomm GLINK supplied by
  `CONFIG_RPMSG_QCOM_GLINK` / `CONFIG_RPMSG_QCOM_GLINK_SMEM`. Do not chase a
  missing `qrtr-glink.ko` on this kernel tree as a standalone fix.
- The jhugo recipe uses userspace `pd-mapper`, but the current repo has also
  tested a live userspace pd-mapper contrast against the in-kernel
  `qcom_pd_mapper`. Both stayed at the same MSS fatal boundary, so pd-mapper
  package installation alone is not the next rootfs rebuild reason.

## Current Working Features

- USB NCM networking works. SSH to the phone is normally available at
  `klipper@192.168.137.133`.
- HelixScreen displays correctly on the phone after the current simplefb path.
- Klipper/Moonraker/NetworkManager services can run.
- Touch is enumerated as `Synaptics S3708AR` on `/dev/input/event0`; physical
  calibration remains separate from WiFi.
- Display path deliberately uses bootloader framebuffer through simpledrm/fbdev.
  Qualcomm MDSS/DSI remains disabled for practical bring-up.

## Current WiFi Failure

WiFi is not at the NetworkManager stage.

Observed live state before the latest `CONFIG_RESET_QCOM_PDC=y` build:

```text
ip -br link:
  lo
  usb0

/sys/class/ieee80211:
  empty

remoteproc0:
  name: 4080000.remoteproc
  state: crashed
  recovery: disabled after manual freeze

qrtr-lookup:
  service 14  Remote file system service
  service 49  IPA control service
  service 64  Service registry locator service
  service 4096 TFTP
  no WLFW / ath10k service
```

Kernel log pattern:

```text
platform 18800000.wifi: Adding to iommu group 6
ipa 1e40000.ipa: IPA driver initialized
qcom-q6v5-mss 4080000.remoteproc: failed to acquire pdc reset
remoteproc remoteproc0: Booting fw image qcom/sdm845/Razer/aura/mba.mbn
qcom-q6v5-mss 4080000.remoteproc: MBA booted without debug policy, loading mpss
ipa 1e40000.ipa: received modem running event
remoteproc remoteproc0: remote processor 4080000.remoteproc is now up
qcom-q6v5-mss 4080000.remoteproc: fatal error without message
remoteproc remoteproc0: crash detected in 4080000.remoteproc: type fatal error
```

The modem reaches `modem running`, then crashes roughly 0.1-0.3 seconds later
in repeated loops. Because WLFW never appears, `ath10k_snoc` cannot create
`wlan0`.

## Current Build Artifacts

Latest DTS-only test artifact, built 2026-05-22 after enabling the factory
ADSP + SLPI + CDSP remoteproc set and restoring IPA:

```text
output/boot.img
  SHA256 F91B65E38DD65EC203DE29148810DD1FFDBB437ED7E807C943A68F1ACE7F757B

output/sdm845-razer-aura.dtb
  SHA256 9E32E1C9C9476E74111165E921AEB72D922F0BBBE2E42C7435E1F5251236A652

output/Image.gz-dtb
  SHA256 CA43614F677B92BEB8B56D302C1227FB7309925AD49BCCE84B07F37DFB290B04
```

Flash only boot for this test because rootfs/modules were not changed:

```powershell
fastboot flash boot output\boot.img
fastboot reboot
```

The test variables are `&adsp_pas`, `&slpi_pas`, `&cdsp_pas`, and `&ipa` all
set to `status = "okay"` while keeping audio/SLIM, Bluetooth, GPU, MDSS/DSI,
and WLED disabled. The hypothesis is that Razer modem `root_pd` may expect the
factory remoteproc protection-domain environment and IPA data path before it
reaches `wlan_pd`.

Previous boot artifacts for reference:

```text
ADSP + SLPI + CDSP, IPA disabled:
  output/boot.img
  SHA256 B6600B8C38A48A6498C0667D1E5411666807493E1DFF5CC1FF020FECBD27CB62

SLPI-only:
output/boot.img
  SHA256 20BA4D6732D77CBF2C9B671AC71EEC315E7353B8233769D3AD2C84EE83C2A8C6
```

Latest produced artifacts after setting `CONFIG_RESET_QCOM_PDC=y`:

```text
output/boot.img
  SHA256 55E697D7A97A874D2867B0F25B190C8BB2FF862EC76EE309CA3CEE5945A1756C

output/rootfs-sparse.img
  SHA256 87D6237FF6FD9835340566FB325DDF5A0B127EB759359FEE9A52826CDE00A06E

output/vbmeta_disabled.img
  SHA256 A5D672A1CC2ADF965555D09BB54DDBDA9424123635DB60DF93D204A3F547BEC3
```

These artifacts need boot + userdata flashing because kernel modules were
refreshed in rootfs:

```powershell
fastboot flash boot output\boot.img
fastboot flash userdata output\rootfs-sparse.img
fastboot --disable-verity --disable-verification flash vbmeta output\vbmeta_disabled.img
fastboot reboot
```

The specific hypothesis for this latest build is only to remove the PDC reset
module-ordering variable. It is not yet proven to fix MSS.

## Current Kernel Config Direction

Canonical config fragment:

```text
config/razer-aura.config
```

Relevant options:

```text
CONFIG_ATH10K=m
CONFIG_ATH10K_SNOC=m
CONFIG_ATH10K_DEBUG=n
CONFIG_QCOM_PDC=y
CONFIG_RESET_QCOM_PDC=y
CONFIG_REMOTEPROC=y
CONFIG_QCOM_Q6V5_MSS=y
CONFIG_QCOM_Q6V5_ADSP=y
CONFIG_QCOM_Q6V5_PAS=y
CONFIG_QCOM_Q6V5_WCSS=m
CONFIG_QCOM_WCNSS_PIL=m
CONFIG_RPMSG_QCOM_SMD=m
CONFIG_RPMSG_QCOM_GLINK=m
CONFIG_RPMSG_QCOM_GLINK_SMEM=m
CONFIG_QRTR=m
CONFIG_QRTR_SMD=m
CONFIG_QRTR_TUN=m
CONFIG_QRTR_MHI=m
CONFIG_QCOM_IPA=y
```

Important note: before the latest build, live `/proc/config.gz` had
`CONFIG_RESET_QCOM_PDC=m`, and dmesg showed `failed to acquire pdc reset`.
The new build changes this to built-in.

## Current DTS Direction

Main DTS:

```text
dts/sdm845-razer-aura.dts
```

Important choices:

- `qcom,msm-id = <QCOM_ID_SDM845 0x20000>;`
- `qcom,board-id = <0 0>;`
- `qcom,calibration-variant = "razer_aura";`
- `&mss_pil` is enabled with Razer firmware names:

```dts
&mss_pil {
	status = "okay";
	firmware-name = "qcom/sdm845/Razer/aura/mba.mbn",
			"qcom/sdm845/Razer/aura/modem.mbn";
};
```

- `&wifi` is enabled with WCN3990 supplies and board-data variant:

```dts
&wifi {
	status = "okay";

	vdd-0.8-cx-mx-supply = <&vreg_l5a_0p8>;
	vdd-1.8-xo-supply = <&vreg_l7a_1p8>;
	vdd-1.3-rfa-supply = <&vreg_l17a_1p3>;
	vdd-3.3-ch0-supply = <&vreg_l25a_3p3>;
	vdd-3.3-ch1-supply = <&vreg_l23a_3p3>;

	qcom,calibration-variant = "razer_aura";
	qcom,snoc-host-cap-8bit-quirk;
};
```

Live DT after the previous boot confirmed:

```text
qcom,msm-id:   0x141 0x20000
qcom,board-id: 0x00  0x00
qcom,calibration-variant: razer_aura
```

## Factory Firmware / DT Baseline

Use the factory firmware package as the authoritative baseline, not live phone
partitions:

```text
aura-p-release-3201-user-full/aura-p-release-3201/
```

Important images in that package:

```text
boot.img
dtbo.img
modem.img
nvdef.img
bluetooth.img
```

Factory `flash_all.sh/bat` flashes:

```text
nvdef_a nvdef.img
nvdef_b nvdef.img
```

Factory boot DTB was unpacked and compared. It shows:

```text
qcom,msm-id = <0x141 0x20000>
qcom,board-id = <0 0>

hyp_region@85700000      size 0x600000
xbl_region@85e00000      size 0x100000
removed_region@85fc0000  size 0x2f40000
wlan_fw_region@8df00000  size 0x100000
modem_region@8e000000    size 0x7800000
mba_region@96500000      size 0x200000
```

Mainline SDM845 base DTS already has the modem/WLAN/MBA regions at matching
addresses. The current Razer DTS aligns the secure pre-rmtfs memory with the
factory DTB and does not re-add the previously tested non-factory tail reserve.

## Firmware Present In Rootfs

Repo firmware tree contains:

```text
firmware/qcom/sdm845/Razer/aura/mba.mbn
firmware/qcom/sdm845/Razer/aura/modem.mbn
firmware/qcom/sdm845/Razer/aura/modem.b*
firmware/qcom/sdm845/Razer/aura/wlanmdsp.mbn
firmware/qcom/sdm845/Razer/aura/ipa_fws.mbn
firmware/ath10k/WCN3990/hw1.0/board.bin
firmware/ath10k/WCN3990/hw1.0/board-2.bin
firmware/ath10k/WCN3990/hw1.0/bdwlan*
```

Rootfs runtime config creates firmware aliases such as:

```text
/lib/firmware/image/wlanmdsp.mbn
/readonly/firmware/image/wlanmdsp.mbn
/readonly/vendor/firmware_mnt/image/wlanmdsp.mbn
/lib/firmware/qcom/sdm845/wlanmdsp.mbn
```

Live hash checked previously:

```text
/lib/firmware/qcom/sdm845/Razer/aura/wlanmdsp.mbn
SHA256 6a9cc6d9836415be81138ac1b2ff16f96264b6b2ee2420c12b302f1329555e8c
```

`board-2.bin` contains `variant=razer_aura`.

Checked against the active 6.16 kernel source:

```text
drivers/net/wireless/ath/ath10k/hw.h:
  firmware-5.bin
  board-2.bin

drivers/net/wireless/ath/ath10k/core.c:
  qcom,calibration-variant
  qcom,ath10k-calibration-variant fallback
```

`WCNSS_qcom_wlan_nv.bin` appears in the kernel under the older
`wcn36xx`/`wcnss_ctrl` path (`wlan/prima/WCNSS_qcom_wlan_nv.bin`), not in the
current `ath10k_snoc` WCN3990 path. Do not treat Android init references to
`/mnt/vendor/persist/WCNSS_qcom_wlan_nv.bin` as proof that mainline
`ath10k_snoc` will load that file.

Factory package inspection on 2026-05-26:

```text
factory modem.img contains:
  wlanmdsp.mbn
  bdwlan.bin
  bdwlan.*

factory persist.img contains:
  sensors registry files only in this package
  no WCNSS_qcom_wlan_nv.bin

factory vendor init references:
  /mnt/vendor/persist/WCNSS_qcom_wlan_nv.bin
  /vendor/lib/modules/qca_cld3_wlan.ko
  cnss-daemon
```

Hashes confirmed that the repo copies of `wlanmdsp.mbn`, `bdwlan.bin`, and
sample `bdwlan.*` match the factory `modem.img` extraction exactly. The online
"extract WCNSS firmware and NV bin" advice maps to files already present for the
mainline path, except that a separate downstream `WCNSS_qcom_wlan_nv.bin` is not
present in this factory `persist.img` and is not consumed by `ath10k_snoc`.

Live `persist` read-only inspection on 2026-05-26:

```text
/dev/disk/by-partlabel/persist -> ext4
no /WCNSS_qcom_wlan_nv.bin
no /wifi_mac.bin
/wlan_mac.bin 62 bytes
SHA256 8fc2ce6299c7427e9dcdd1b6715057ea099a1e72eba191e65d28f04aa1482804
```

`wlan_mac.bin` is text containing only interface MAC addresses:

```text
Intf0MacAddress=445ECDB16026
Intf1MacAddress=465ECDB16026
END
```

So live `persist` also does not contain an Android-generated WCNSS calibration
blob. The remaining WiFi blocker is not an obvious missing `WCNSS_qcom_wlan_nv`
file.

## Userspace Services

Expected active services:

```text
rmtfs.service
qrtr-ns.service
tqftpserv.service
NetworkManager.service
HelixScreen.service
```

Before the latest artifact, live service state showed:

```text
rmtfs.service active:
  /usr/local/bin/rmtfs-razer-test -r -P -s

qrtr-ns.service active:
  /usr/bin/qrtr-ns -f 1

tqftpserv.service active:
  /usr/bin/tqftpserv
```

`rmtfs-razer-test` is a repo-controlled patched build of `rmtfs`.

## rmtfs / NV Attempts

Razer has the expected EFS/NV partitions:

```text
modemst1
modemst2
fsg
fsc
nvdef_a
nvdef_b
```

The stock Ubuntu rmtfs rejected:

```text
/boot/modem_fsg_oem_1
/boot/modem_fsg_oem_2
```

Patch added these mappings:

```c
{ "/boot/modem_fsg_oem_1", "modem_fsg_oem_1", "nvdef_a" },
{ "/boot/modem_fsg_oem_2", "modem_fsg_oem_2", "nvdef_b" },
```

This removed the obvious `unknown partition` rejection, but did not make MSS
stable.

Current rmtfs drop-in:

```ini
[Service]
ExecStart=
ExecStart=/usr/local/bin/rmtfs-razer-test -r -P -s -v
```

Latest verbose rmtfs check on 2026-05-26:

```text
open /boot/modem_fs1       => 0 (0:0)
open /boot/modem_fs2       => 1 (0:0)
open /boot/modem_fsg       => 2 (0:0)
open /boot/modem_fsc       => 3 (0:0)
open /boot/modem_fsg_oem_1 => 4 (0:0)
open /boot/modem_fsg_oem_2 => 5 (0:0)
alloc 0, 2097152 => 0x88f01000 (0:0)
iovec 0 read 1:1
iovec 1 read 1:1
iovec 1 read 2:4094
```

No unknown partition, open failure, write request, or RFS error appeared before
MSS fatal. rmtfs still runs read-only (`-r`) to protect partitions, but the
earlier non-read-only test also did not alter partition hashes or change the
crash timing. The current evidence makes a missing rmtfs path less likely than
an MSS reset/halt/service-registry/firmware interaction.

## Tried Directions That Did Not Create wlan0

Do not repeat these without a new reason:

- OnePlus-style rmtfs address `0xf5b00000`.
- Xiaomi-style rmtfs address `0xf6301000`.
- Razer/mainline `0x88f00000` with guard pages.
- Reserving the rest of the old `0x88f00000..0x8ab00000` modem/rmtfs window.
- Aligning Razer factory pre-rmtfs memory (`hyp/xbl/removed`) with the factory
  boot DTB.
- Mapping Razer OEM rmtfs paths to `nvdef_a` and `nvdef_b`.
- Aligning `qcom,msm-id` / `qcom,board-id` to the factory boot DTB.
- Fixing the ath10k board-data property name to
  `qcom,calibration-variant`.
- Building and flashing with `CONFIG_RESET_QCOM_PDC=y`. This removed the PDC
  reset ordering variable, but MSS still reached `remote processor is now up`
  and fataled roughly 0.15-0.25 seconds later.
- Disabling IPA in DTS. Live `/proc/device-tree/soc@0/ipa@1e40000/status`
  showed `disabled`; MSS still fataled, and the log no longer contained IPA
  running/crashed events. IPA is not the immediate trigger.
- Removing `qcom_q6v5_wcss` and `qcom_wcnss_pil` from module autoload.
  These modules no longer loaded, but MSS still fataled. They were noise, not
  the root cause.
- Preventing `ath10k_snoc` / `ath10k_core` from loading with a live
  `/etc/modprobe.d/blacklist-ath10k-snoc.conf` reboot test. `ath10k` was absent
  from `lsmod`, but MSS still fataled. WiFi client probing is not the crash
  trigger.
- Enabling only SLPI (`&slpi_pas status = "okay"`) while keeping IPA, ADSP,
  CDSP, audio/SLIM, Bluetooth, GPU, MDSS/DSI, and WLED disabled. Live DT showed
  SLPI `okay`, `remoteproc0` was `slpi running`, and QRTR showed SLPI node 9
  services. MSS still reached node 0 service 66/43 and fataled around
  0.14-0.22 seconds after `remote processor 4080000.remoteproc is now up`; no
  WLFW and no `wlan0`. SLPI alone is not sufficient.
- Enabling the factory non-modem remoteproc set: ADSP, SLPI, and CDSP all
  `okay`, with IPA, audio/SLIM users, Bluetooth, GPU, MDSS/DSI, and WLED still
  disabled. Live DT showed all three as `okay`; QRTR showed ADSP node 5, SLPI
  node 9, and CDSP node 10 services. MSS still fataled at the same point after
  `remote processor 4080000.remoteproc is now up`; no WLFW and no `wlan0`.
  Missing ADSP/CDSP/SLPI environment is not the root cause.
- Restoring IPA together with ADSP, SLPI, and CDSP. Live DT showed all four
  blocks `okay`, QRTR showed IPA control service plus ADSP node 5, SLPI node 9,
  and CDSP node 10 services, and the expected services
  `rmtfs`/`qrtr-ns`/`tqftpserv` were active. MSS still crash-looped after
  `remote processor 4080000.remoteproc is now up`, logging
  `qcom-q6v5-mss 4080000.remoteproc: fatal error without message`, and no WLFW,
  `/sys/class/ieee80211`, or `wlan0` appeared. Full remoteproc dependency
  toggling, including IPA, is now excluded as a standalone fix.
- Disabling `rmtfs.service` for one boot. MSS stayed at
  `4080000.remoteproc is available`; it did not power up and did not crash.
  This confirms the crash happens only once the rmtfs/QRTR/RFS chain permits
  MSS to boot far enough, and keeps rmtfs/NV as the active suspect.
- Running `rmtfs-razer-test` without `-r` as
  `/usr/local/bin/rmtfs-razer-test -P -s`. MSS still fataled at the same point.
  After the test, hashes of `modemst1`, `modemst2`, `fsg`, `fsc`, `nvdef_a`,
  and `nvdef_b` matched the pre-test backup exactly, so the test did not write
  those partitions. Read-only rmtfs is not the root cause.
- Verbose rmtfs logging with `-v` showed all six expected RFS opens and the
  subsequent iovec reads succeeding before fatal. Do not keep reworking path
  aliases unless a new log shows a failed RFS request.
- Controlled autoload testing narrowed the blocker further. Blacklisting
  `qcom_q6v5_mss` lets the system boot stably but makes auto-started rmtfs fail
  with `Failed to get rprocfd`. Autoloading `qcom_q6v5_mss` and letting rmtfs
  start at boot fixes that rmtfs failure, but MSS then powers up automatically
  and enters ~3 second crash loops even while `ath10k_core`/`ath10k_snoc` are
  blacklisted.
- The stable diagnostic baseline is therefore: do not autoload
  qcom_q6v5_mss, do not auto-start rmtfs, and let the manual late-start helper
  load qcom_q6v5_mss, disable recovery, start rmtfs, then optionally load
  ath10k. If that still does not produce WLFW, `/sys/class/ieee80211`, or
  `wlan0`, the blocker is before WLAN firmware side-load.
- The clean controlled late-start sample with rmtfs active showed the real
  current boundary: rmtfs registered service 14, all six expected RFS opens
  succeeded, the initial iovec reads succeeded, QRTR showed MSS node 0 services
  66/43, and then MSS fataled about 0.24 seconds after
  `remote processor 4080000.remoteproc is now up`.
- `tqftpserv` received no `wlanmdsp.mbn` request, WLFW service 69 never
  appeared, `/sys/class/ieee80211` stayed empty, and explicit ath10k loading
  after the crash could not advance. This excludes ath10k board data and TFTP
  file path as the immediate blocker.
- 2026-05-27 follow-up: the live rootfs was missing `/lib/firmware/image`.
  `/lib/firmware/image/wlanmdsp.mbn`, `/readonly/firmware/image`, and factory
  `modemr.jsn` / `modemuw.jsn` were installed live, and the files were added to
  the repo-controlled firmware overlay. After reboot and the same late-start
  test, MSS still fataled about 0.24 seconds after
  `remote processor 4080000.remoteproc is now up`; `tqftpserv` still logged no
  request, WLFW still did not appear, and `/sys/class/ieee80211` stayed empty.
  Therefore missing `/lib/firmware/image` was a real reproducibility bug but
  not the direct cause of the current MSS fatal.

None of the above produced `wlan0` or WLFW in QRTR on the tested live boots.

## Current Leading Hypotheses

## 2026-05-27 Claude-Suggested Direction Triage

The current boundary remains: MSS root services appear, then MSS fatal-errors
before `mpss_wlan_pd` / WLFW / TFTP. The following suggestions were checked
against the live device and local factory DTB.

1. Crash reason / SMEM / QDSP6SS registers:
   - Live debugfs exposes `/sys/kernel/debug/remoteproc/remoteproc*/crash`,
     `coredump`, and `recovery`, but no readable `crash_reason` file.
   - `remoteproc3` is MSS (`4080000.remoteproc`) when loaded.
   - `CONFIG_DEVMEM=y` but `CONFIG_STRICT_DEVMEM=y`; direct `/dev/mem` reads of
     the suggested QDSP6SS/MSS registers returned `Bad address`.
   - Conclusion: this direction is useful in principle, but the current kernel
     does not expose the needed reason registers through existing userspace
     interfaces. It needs a small kernel helper, devmem relaxation, or fixed
     driver logging.

2. Servreg / PDR timing:
   - Already partly tested and still plausible.
   - Live QRTR shows service registry locator and MSS root services 66/43
     during the crash window, but never WLFW.
   - Factory `modemuw.jsn` declares `msm/modem/wlan_pd`, instance `180`, with
     `kernel/elf_loader`, `tms/servreg`, and `wlan/fw`.
   - Upstream in-kernel `qcom_pd_mapper` for SDM845 has matching
     `mpss_wlan_pd` data. The next missing evidence is not the JSON content; it
     is whether `qcom_pd_mapper` / PDR sends and receives the expected QMI
     transactions before MSS fatal. Current kernel logs are too quiet.

3. WLAN carveout / reserved-memory:
   - The live DT has `wlan-msa@8df00000` size `0x100000`.
   - Razer factory Android DTB has `wlan_fw_region@0x8df00000` size
     `0x100000`.
   - Factory `modem_region@0x8e000000` size `0x7800000` and mainline
     `mpss@8e000000` size `0x7800000` match.
   - Conclusion: the generic "missing WLAN carveout" hypothesis does not fit
     this device. Do not add a 6 MiB WLAN region from another phone unless a new
     Razer-specific source proves it.

4. AOP / PDC / MSS reset-halt quirk:
   - This remains the strongest DTS/driver-level lead.
   - Razer factory MSS node is downstream `qcom,pil-q6v55-mss` and includes
     `pdc_sync`, `alt_reset`, `qcom,override-acc`, `qcom,signal-aop`,
     `qcom,qdsp6v65-1-0`, and `qcom,mss_pdc_offset = <0x09>`.
   - Mainline live node is generic `qcom,sdm845-mss-pil` with only
     `qdsp6`/`rmb`, `mss_restart`/`pdc_reset`, and `qcom,halt-regs`.
   - Since reserved memory and RFS now match, a Razer-specific reset/halt/AOP
     sequencing issue is more credible than another firmware path change.

5. kprobe / ftrace:
   - Current kernel has `# CONFIG_KPROBES is not set` and
     `# CONFIG_FTRACE is not set`. `/sys/kernel/debug/tracing` is absent.
   - This direction cannot run on the current image. A future diagnostic build
     can enable `CONFIG_KPROBES`/`CONFIG_FTRACE`, but a smaller and safer option
     may be fixed `pr_info` instrumentation in `qcom_q6v5_mss`,
     `qcom_sysmon`, `qcom_pd_mapper`, and PDR paths.

1. rmtfs/RFS request path still needs instrumentation:
   - With rmtfs disabled, MSS does not power up or crash.
   - With rmtfs enabled, MSS reaches `modem running`, exposes root modem QRTR
     services briefly, then fatal-errors before WLFW appears.
   - Address swaps, factory `nvdef` prefix verification, and read-write
     `rmtfs-razer-test -P -s` did not change the crash. The next useful test is
     not another blind mapping change; it is verbose logging of every RFS open,
     read, write, path, offset, result code, and final request before fatal.

2. The next useful window is the late-start 40-second timeout:
   - The current validation rootfs should auto-load `qcom_sysmon` and
     `qcom_pd_mapper`, but should not auto-start `qcom_q6v5_mss`,
     `ath10k_core`, `ath10k_snoc`, or `rmtfs.service`.
   - Use `/usr/local/sbin/razer-wifi-late-start` to load qcom_q6v5_mss, freeze
     MSS recovery, start rmtfs, and then load ath10k under observation.
   - If `tqftpserv` never receives a `wlanmdsp.mbn` request, the blocker is
     before WLAN firmware side-load: likely wlan protection-domain publication,
     servreg/PDR, sysmon, or an MSS reset/halt quirk.
   - The 2026-05-27 controlled sample already landed in this branch: rmtfs
     active, RFS reads successful, no TFTP firmware request, no WLFW, immediate
     MSS fatal after root services 66/43.
   - A second 2026-05-27 sample after restoring `/lib/firmware/image` and
     factory `modemr.jsn` / `modemuw.jsn` produced the same boundary. Do not
     chase `wlanmdsp.mbn` path or JSON placement as the next primary
     hypothesis unless a future log shows a TFTP request or userspace
     pd-mapper file-open failure.
   - If `wlanmdsp.mbn` is requested and fails, fix firmware path/tqftp layout.
   - If WLFW appears and only then ath10k fails, return to `firmware-5.bin`,
     `board-2.bin`, and `qcom,calibration-variant`.

3. Missing or wrong service-registry / pd-mapper runtime:
   - Factory firmware includes `slpir.jsn` and `slpius.jsn`.
   - Upstream in-kernel `qcom_pd_mapper` already maps SDM845 `slpi_root_pd`,
     `slpi_sensor_pd`, `mpss_root_pd`, and `mpss_wlan_pd`.
   - QRTR shows RFS/TFTP and service-registry locator, but never WLFW.
   - Factory `modemr.jsn` / `modemuw.jsn` matches upstream SDM845
     `qcom_pd_mapper` domain names and instance IDs:
     `msm/modem/root_pd`, `msm/modem/wlan_pd`, instance `180`.
   - The rootfs overlay now installs factory `modemr.jsn` and `modemuw.jsn`
     under `/lib/firmware/image` when refreshing or rebuilding the rootfs. This
     keeps a userspace pd-mapper comparison test reproducible, even though the
     active kernel path should be in-kernel `qcom_pd_mapper`.
   - Factory JSN lists `tms/servreg` in `root_pd` and `wlan_pd`, but mainline
     `qcom_pd_mapper` automatically registers every domain for
     `TMS_SERVREG_SERVICE` inside `qcom_pdm_add_domain()`. Do not add
     `tms/servreg` to a domain's `.services` array; that would duplicate the
     same service/domain pair and can make domain registration fail.
   - A live boot confirmed `qcom_pd_mapper` is loaded and QRTR service locator
     is present. Dynamic-debug logging would be useful, but the first
     `CONFIG_DYNAMIC_DEBUG=y` boot artifact returned to bootloader on this
     device, so that build was rejected and reverted before further WiFi work.
     Prefer the modem-load-order test below before trying another debug kernel.

4. Downstream MSS-specific reset/halt differences:
   - Android DT has downstream-only MSS properties such as
     `qcom,mss_pdc_offset = <0x09>`, `qcom,override-acc`, `qcom,signal-aop`,
     `qcom,qdsp6v65-1-0`, and extra `reg-names` such as `pdc_sync` and
     `alt_reset`.
   - Mainline SDM845 supports the generic `qcom,sdm845-mss-pil` path, but Razer
     may need a quirk if the modem firmware is stricter.
   - Offline source comparison on 2026-05-27 narrowed this further:
     mainline `qcom_q6v5_mss` for SDM845 already has AOSS QMP load-state
     support, `PDC_MODEM_SYNC_RESET` maps to the same effective
     `0x0b2e0100` / bit 9 register as factory `pdc_sync`, and `has_alt_reset`
     writes `RMB_MBA_ALT_RESET` at `rmb + 0x44`, matching factory
     `alt_reset = 0x04180044`.
   - Therefore the remaining reset/halt lead is not "mainline lacks all Razer
     properties"; it is the smaller sequencing/logging delta. Razer downstream
     inserts barriers and a roughly 200 us reset-settle delay in the MSS reset
     path, and exposes more crash/register state than the current mainline log.

5. NV/EFS content source:
   - User instructed to use factory firmware package, not live phone extraction,
     as authoritative where possible.
   - Factory package includes `nvdef.img`, flashed to both `nvdef_a` and
     `nvdef_b` in Android flashing scripts.
   - Live `nvdef_a/b` raw partition hashes differ from factory only because the
   partitions are 4 MiB while `nvdef.img` is 1,413,632 bytes. The first
   1,413,632 bytes of both live partitions match factory
   `nvdef.img` exactly (`c4c6118b...197f540`), so factory `nvdef` content is
   present.

## 2026-05-27 Offline Source Comparison

Sources compared locally:

- Mainline working kernel: `~/razorphone2linux/kernel/linux`, commit
  `ed6098a37`, branch `sdm845/6.16-dev`.
- Razer downstream reference:
  `~/razorphone2linux/reference/android_kernel_razer_aura`, commit `fec3a25`.
- Factory DTB: `android-fdt/android-base-00.dts` and
  `.tmp/android-stock-extract/dts/boot-dtb0.dts`.

What this excludes or demotes:

- `qcom_pd_mapper` data being absent is unlikely. Mainline SDM845 already
  registers `mpss_root_pd` and `mpss_wlan_pd` with domain names and instance
  IDs matching factory `modemr.jsn` / `modemuw.jsn`, and it automatically adds
  `tms/servreg` for each domain.
- The generic missing-WLAN-carveout theory does not fit Razer aura. Factory and
  live mainline both use `wlan-msa` / `wlan_fw_region` at `0x8df00000` size
  `0x100000`, with MPSS at `0x8e000000` size `0x7800000`.
- `qcom,override-acc` is probably not the first property to chase. Razer
  downstream sets `qcom,qdsp6v65-1-0`, and the downstream reset path for that
  variant does not use the older override-ACC branch.
- Direct live crash reason reads were blocked by the current image:
  `crash_reason` is not exposed in debugfs, `STRICT_DEVMEM` rejects the
  suggested QDSP6SS register reads, and `CONFIG_KPROBES` / `CONFIG_FTRACE` are
  not enabled.

What remains plausible:

- MSS reaches root services and then fatal-errors before `wlan_pd` / WLFW. That
  still points at the transition between MSS root protection domain and WLAN
  protection domain, not NetworkManager, board data, or `firmware-5.bin`.
- Because PDC, alt reset, AOSS load-state, and pd-mapper data are present in
  mainline, the next useful test is fixed instrumentation plus the small
  downstream reset-settle timing difference, not another ADSP/SLPI/CDSP/IPA
  permutation.

Repo-controlled diagnostic patch:

```text
kernel-patches/0001-razor-aura-mss-pdr-diagnostics.patch
```

This patch is applied by `scripts/02-build-kernel.sh` before configuring the
kernel. It logs:

- AOSS `load_state` on/off and whether QMP acknowledged it.
- `qcom_pd_mapper` service/domain/instance registration, including
  `msm/modem/root_pd` and `msm/modem/wlan_pd`.
- SMEM crash reason id, SMEM read error/length, and rproc state on fatal or
  watchdog.
- SDM845 MSS/RMB register snapshots around reset, boot-core-start, boot-cmd,
  and boot-FSM completion.

It also makes one controlled behavioral change copied from the Razer downstream
reset path: an `mb()` after `QDSP6SS_BOOT_CORE_START` and a 200 us delay before
releasing `ALT_RESET` / PDC after the restart pulse. If WiFi advances after
this build, the reset timing is implicated. If it still fatal-errors, the new
log should show whether AOSS, PDM registration, reset state, or SMEM crash
reason is missing. The safe patch intentionally does not dump QDSP6/RMB
registers after `BOOT_CMD`; the first diagnostic build did that and triggered a
kernel `synchronous external abort` in `q6v5_dump_sdm845_regs` during MSS boot.

Build choice for this diagnostic:

```bash
cd /mnt/c/repo/razorphone2linux
bash scripts/build-all.sh validate
```

Use `validate`, not `validate-boot`, because the patch touches kernel drivers
and may alter module artifacts as well as the kernel image.

Diagnostic artifacts produced 2026-05-27:

```text
output/boot.img
  SHA256 52230be7af9edcdd7b0ef275c55cba1868cbc6ae63f911c04be25da35d3e7498
  size 17M

output/rootfs-sparse.img
  SHA256 6a1a98cdefc404d4972e452170c01f555ae8fa31206512c95f3b34624979c1fb
  size 2.0G

output/vbmeta_disabled.img
  SHA256 a5d672a1cc2adf965555d09bb54ddbda9424123635db60df93d204a3f547bec3

output/Image.gz-dtb
  SHA256 ca01b686566696b1ae537cb27c48548c10c4de5b1f8bdb60d3ad95d450c3944d

output/sdm845-razer-aura.dtb
  SHA256 c32b193f6d6cadacb0d87d2b6328a1bf4a622bb7eccecf32f9b01e0ad3fd995c
```

`output/kernel.release` and `output/rootfs.kernel-release` both contain:

```text
6.16.0-rc2-sdm845-ged6098a37a4c-dirty
```

Flash boot, userdata, and vbmeta for this diagnostic because the rootfs modules
were refreshed to match the patched kernel.

Live result from the safe diagnostic build:

```text
MSS remoteproc: 4080000.remoteproc
state after test: crashed
recovery: disabled

PDM registration:
  tms/servreg -> msm/modem/root_pd instance 180
  tms/servreg -> msm/modem/wlan_pd instance 180
  kernel/elf_loader -> msm/modem/wlan_pd instance 180
  wlan/fw -> msm/modem/wlan_pd instance 180

RFS:
  /boot/modem_fs1 open ok
  /boot/modem_fs2 open ok
  /boot/modem_fsg open ok
  /boot/modem_fsc open ok
  /boot/modem_fsg_oem_1 open ok
  /boot/modem_fsg_oem_2 open ok
  initial iovec reads ok

QRTR after crash:
  modem node 0 services 66 and 43 present
  RFS, IPA, TFTP present
  WLFW absent
```

The fatal boundary is still:

```text
MBA/MPSS loads -> IPA modem running -> remoteproc up
-> RFS opens/reads succeed -> fatal error without SMEM message after ~0.24s
```

AOSS load-state is acknowledged, PDM static domain registration is correct, the
200 us downstream-like reset settle did not fix the fatal, and TFTP never sees a
`wlanmdsp.mbn` request. The remaining unknown is whether the modem actually
queries the in-kernel pd-mapper for `tms/servreg`, `kernel/elf_loader`, or
`wlan/fw` before the fatal.

The next diagnostic patch revision therefore promotes pd-mapper request/response
logging from `pr_debug` to `pr_info`. It records each
`SERVREG_GET_DOMAIN_LIST_REQ` caller node/port, requested service, offset, and
returned domain count.

Diagnostic artifacts produced after adding pd-mapper lookup logging:

```text
output/boot.img
  SHA256 b9b18feb80ec34640f0febbb0e88c17b7a2d4e2b39580a52e8c2c5cbe88f0de9

output/rootfs-sparse.img
  SHA256 56a0751dcb489a21f2e82c23a11862b99c7dc7cf470f2e65374e42ecb8433b6c

output/vbmeta_disabled.img
  SHA256 a5d672a1cc2adf965555d09bb54ddbda9424123635db60df93d204a3f547bec3
```

After flashing this build, the decisive log lines are:

```bash
dmesg --time-format=iso |
  egrep -i 'PDM diag: lookup|PDM diag: service|remoteproc|q6v5|modem|fatal|rmtfs|tftp|wlan|ath10k' |
  tail -220
```

Interpretation:

- If there are no `PDM diag: lookup request` lines from node 0 before fatal, the
  modem is dying before service-registry domain lookup reaches Linux.
- If node 0 requests `wlan/fw` or `kernel/elf_loader` and gets
  `msm/modem/wlan_pd`, then pd-mapper data is not the blocker and the next lead
  is downstream MSS/servreg/PDR behavior after lookup.
- If node 0 requests a service not present in the current in-kernel mapper, add
  only that missing service mapping and retest.

Live result from the lookup-logging build:

```text
1970-01-07T03:49:31 PDM diag: lookup request node=0 port=9 service=tms/pddump_disabled offset=0 valid=0
1970-01-07T03:49:31 PDM diag: lookup response service=tms/pddump_disabled offset=0 len=0 total=0
1970-01-07T03:49:31 remoteproc remoteproc3: remote processor 4080000.remoteproc is now up
1970-01-07T03:49:31 qcom-q6v5-mss 4080000.remoteproc: fatal error without message
```

This is the first concrete missing service lookup from modem node 0. It did not
request `wlan/fw` or `kernel/elf_loader` before fatal. The next controlled
artifact maps `tms/pddump_disabled` to `msm/modem/root_pd` for SDM845 only via
the repo-controlled diagnostic patch. This intentionally does not alter WiFi
DTS, rmtfs partition mapping, firmware files, or ath10k board data.

Diagnostic artifacts produced after adding the `tms/pddump_disabled` mapping:

```text
output/boot.img
  SHA256 be97c6a32d059dc7e27636bb77e77e584094cee2468d19fd07208c7857c7ea29

output/rootfs-sparse.img
  SHA256 023660e81a89b30f250aff891878d4af6d7e6fd58403554f1cc46e10b0b00965

output/vbmeta_disabled.img
  SHA256 a5d672a1cc2adf965555d09bb54ddbda9424123635db60df93d204a3f547bec3
```

After flashing this artifact, read the same `PDM diag: lookup` lines. Success
for this experiment does not require WiFi to be immediately usable; the first
win is seeing modem progress beyond the old `tms/pddump_disabled` lookup into
`wlan/fw`, `kernel/elf_loader`, WLFW service 69, or a different fatal boundary.

Live result from the `tms/pddump_disabled` mapping build:

```text
PDM diag: lookup request node=0 port=9 service=tms/pddump_disabled offset=0 valid=0
PDM diag: lookup response service=tms/pddump_disabled offset=0 len=1 total=1
remoteproc remoteproc3: remote processor 4080000.remoteproc is now up
qcom-q6v5-mss 4080000.remoteproc: fatal error without message
```

The mapping works but does not move the MSS boundary. The next controlled
artifact instruments `qcom_sysmon` / SSCTL and temporarily skips peer SSR
notifications sent to `modem` after power-up. This tests whether modem is
fataling when Linux tells it that ADSP/CDSP/SLPI are already up. It is a
diagnostic behavior change, not a final WiFi policy.

Diagnostic artifacts produced after adding sysmon/SSCTL diagnostics and the
temporary modem peer-event skip:

```text
output/boot.img
  SHA256 724ce13b2e5ac6cfc73376a4f60aa92683c3c2f6eae822cd13f243c50f5a00b4

output/rootfs-sparse.img
  SHA256 d24de7f7d1b6db83675d17abd650f28d060d2436b620105c7c53e10b78b8ff2d

output/vbmeta_disabled.img
  SHA256 a5d672a1cc2adf965555d09bb54ddbda9424123635db60df93d204a3f547bec3
```

After flashing any artifact that includes a userdata/rootfs flash, reinstall
the SSH key first:

```powershell
$pub = ssh-keygen.exe -y -f C:\tmp\razer_usb_ed25519
$cmd = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && grep -qxF '$pub' ~/.ssh/authorized_keys 2>/dev/null || printf '%s\n' '$pub' >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; echo KEY_INSTALLED"
& 'C:\Program Files\PuTTY\plink.exe' -ssh -batch -pw klipper -hostkey "SHA256:8+h/ReoB0QWsJrsE873CaiS6yRuATAtoJyewFarbUqU" klipper@192.168.137.133 $cmd
```

Live result from the first sysmon isolation build:

```text
qcom-q6v5-mss 4080000.remoteproc: sysmon diag: ssctl server name=modem version=2 instance=18 node=0 port=4
qcom-q6v5-mss 4080000.remoteproc: sysmon diag: start name=modem ssctl_version=2 ssctl_instance=18
qcom-q6v5-mss 4080000.remoteproc: sysmon diag: skip modem peer event slpi state=after_powerup
qcom-q6v5-mss 4080000.remoteproc: sysmon diag: skip modem peer event cdsp state=after_powerup
qcom-q6v5-mss 4080000.remoteproc: sysmon diag: skip modem peer event adsp state=after_powerup
qcom-q6v5-mss 4080000.remoteproc: fatal error without message
```

MSS still fataled. However ADSP/CDSP/SLPI were still notified about modem
`before_powerup` and `after_powerup`, so the final sysmon isolation artifact now
also skips notifier events where `peer=modem`.

Diagnostic artifacts produced after skipping all sysmon notifications involving
modem:

```text
output/boot.img
  SHA256 eca8328d23030bd98935b1c360e4dd1b44fbdaab18beb049340ad433cdd206ae

output/rootfs-sparse.img
  SHA256 39f5ad3510670a1ba723987a3b258e61e94d67b139e6c94242043b445ef1992a

output/vbmeta_disabled.img
  SHA256 a5d672a1cc2adf965555d09bb54ddbda9424123635db60df93d204a3f547bec3
```

Expected success marker for this artifact is not necessarily `wlan0`; first look
for either WLFW service 69 or a new log boundary. If MSS still fatal-errors after
`sysmon diag: skip peer notification target=... peer=modem`, then sysmon/SSCTL
peer notifications are not the immediate trigger and the next work should return
to deeper MSS reset/halt/firmware expectations rather than more pd-mapper or
sysmon service toggles.

## 2026-05-28 Live-First Follow-Up

The validation policy changed after repeated slow userdata/rootfs flashes:
when `uname -r` matches `output/kernel.release`, same-release kernel module
experiments are deployed live with `scripts/deploy-live-module.ps1`, followed
by `depmod` and reboot only when needed. No rootfs rebuild or userdata flash is
required for these tests.

The rejected diagnostic patches were moved under `kernel-patches/rejected/` and
the live phone was restored to the repo-controlled baseline with only
`kernel-patches/0001-razor-aura-mss-pdr-diagnostics.patch` active. Current
phone modules were verified to no longer contain the rejected markers:

- `sysmon diag: skip peer notification`
- `sysmon diag: ignore modem ssctl server`
- `sdm845 mss diag: keeping proxy resources after handover`
- `sdm845 mss diag: applying ACC override`

Results now excluded as immediate MSS fatal triggers:

- Sysmon peer SSR notifications involving modem. Skipping them did not change
  the fatal boundary.
- Binding the modem SSCTL server. Ignoring it did not change the fatal
  boundary.
- Proxy resource handover/unvote. The handover marker did not appear before the
  fatal, so handover is not reached before the crash.
- `qcom,override-acc` / `QDSP6SS_STRAP_ACC`. The marker appeared before MBA
  boot, but MSS still fataled at the same boundary.
- Missing `modem.b13` / `modem.b17`. ELF inspection showed those program
  headers have zero `FileSiz`, so the missing split files are expected holes,
  not a firmware extraction failure.

The clean live late-start still shows the same boundary:

- ADSP, CDSP, SLPI, IPA, qrtr-ns, tqftpserv, and qcom_pd_mapper are active.
- `rmtfs-razer-test -r -P -s -v` opens all six expected RFS paths and completes
  the initial reads.
- PDM static data includes `msm/modem/root_pd`,
  `msm/modem/wlan_pd`, `kernel/elf_loader`, and `wlan/fw`.
- Modem node 0 exposes QRTR services 66 and 43, asks only for
  `tms/pddump_disabled`, receives one mapped domain, and fatal-errors about
  0.24 seconds after `remote processor 4080000.remoteproc is now up`.
- There is still no `wlan/fw` or `kernel/elf_loader` lookup, no
  `wlanmdsp.mbn` TFTP request, no WLFW service 69, no `/sys/class/ieee80211`,
  and no `wlan0`.

An attempted live PDM-off contrast test removed `qcom_pd_mapper` and reloaded
`qcom_q6v5_mss` without rebooting. The phone reset before useful MSS window
logs could be captured and `/sys/fs/pstore` remained empty after reboot. Treat
this as a high-instability diagnostic path, not a fix direction, unless a later
test adds persistent logging first.

A real ath10k-before-MSS load-order test was also completed without flashing:
`qcom_q6v5_mss` was loaded while MSS stayed `offline`, recovery was disabled,
`ath10k_core` and `ath10k_snoc` were loaded first, and then
`rmtfs-razer-test -r -P -s -v` was run directly instead of through systemd.
Result: ath10k loaded successfully as modules, but `/sys/class/ieee80211`
remained empty before MSS start; once rmtfs powered MSS, the same RFS open/read
sequence completed and MSS fataled at the same boundary before WLFW appeared.
Therefore "ath10k must be loaded before modem/rmtfs" is excluded as the current
root cause.

An MSM8998-style `diag-router` live test was also completed without flashing.
`diag-router` was built from `andersson/diag` plus a static `andersson/qrtr`
library, copied to `/tmp`, and started before `qcom_q6v5_mss` and
`rmtfs-razer-test -r -P -s -v`. `qrtr-lookup` confirmed that AP-side DIAG
services were published before MSS came up:

```text
4097 N/A   0 1 16394 DIAG service (MODEM:CNTL)
4097 N/A   2 1 16396 DIAG service (MODEM:DATA)
4097 N/A   4 1 16397 DIAG service (MODEM:DCI)
```

Result: `diag-router` did not move the failure boundary. MSS reached
`remote processor 4080000.remoteproc is now up` at
`1970-01-07T09:25:05,673983+08:00`, requested only
`tms/pddump_disabled`, received the mapped response, and fataled at
`1970-01-07T09:25:05,930042+08:00`. There was still no `wlan/fw` or
`kernel/elf_loader` lookup, no `wlanmdsp.mbn` TFTP request, no WLFW service 69,
and no `wlan0`. Therefore "missing diag-router before MSS" is excluded as the
current root cause, although diag-router may still be useful later if WLFW
starts and then ath10k firmware crashes.

## Crash Reason Deep Diagnostics Build

After the `diag-router` exclusion, the next diagnostic moved from dependency
ordering to crash-message capture. The reason is that mainline `qcom_q6v5`
currently reads the MSS crash reason from global SMEM item 421, but the live log
shows:

```text
fatal error without message (smem 421 err -2 len 0 state 2)
```

Public remoteproc discussion notes that some Qualcomm targets store q6v5 crash
reason strings in a target-specific SMEM partition instead of the global
partition. The new repo-controlled patch is:

```text
kernel-patches/0002-razor-aura-mss-crash-reason-deep-diagnostics.patch
```

It is observational only:

- reads global `QCOM_SMEM_HOST_ANY` item 421 as before;
- additionally reads modem private SMEM host 1 item 421;
- also probes item 6 (`SMEM_DIAG_ERR_MESSAGE` on older downstream kernels) from
  global and modem-private SMEM;
- dumps the first printable text or first 16 bytes when an item exists;
- adds an MSS crash callback that logs SDM845 sleep/reset/power/strap/boot/RMB
  registers at the fatal/watchdog IRQ boundary.

Artifacts built on 2026-05-28 without refreshing rootfs:

```text
output/live-modules/qcom_q6v5.ko
output/live-modules/qcom_q6v5_mss.ko
```

The first version also attempted to read SDM845 MSS registers from the fatal
IRQ path. That was a bad diagnostic: after the fatal event, reading the MSS
register window triggered a synchronous external abort in
`q6v5_dump_sdm845_regs`. The patch was corrected to remove post-fatal register
reads and keep only SMEM probing.

Live result after deploying the corrected patch and running
`scripts/phone-mss-smem-short-test.sh`:

```text
remote processor 4080000.remoteproc is now up
fatal error without message (smem 421 err -2 len 0 state 2)
q6v5 diag fatal: smem host=-1 item=421 err=-2
q6v5 diag fatal: smem host=1 item=421 err=-2
q6v5 diag fatal: smem host=-1 item=6 err=-2
q6v5 diag fatal: smem host=1 item=6 err=-2
crash detected in 4080000.remoteproc: type fatal error
```

This excludes the obvious q6v5 crash-reason locations: the crash string is not
in global SMEM item 421, modem-private SMEM item 421, global item 6, or
modem-private item 6. The next crash-message direction needs a different
channel, such as downstream minidump/pddump/coredump buffers, Qualcomm DIAG
configuration, or additional downstream MSS dump code, not more q6v5
`crash_reason` reads.

Downstream source comparison also reduced the reset-quirk search space:
Android's `qcom,qdsp6v65-1-0` reset path enables `QDSP6SS_SLEEP`, writes
`QDSP6SS_BOOT_CORE_START`, executes a memory barrier, writes
`QDSP6SS_BOOT_CMD`, and polls the boot FSM. Mainline SDM845 already follows the
same sequence, and the current patch has the barrier plus reset-settle logging.
`qcom,signal-aop` is represented in mainline by the AOSS QMP `load_state`
toggle, which is acknowledged in live logs. Therefore the next useful work is
not another ADSP/SLPI/CDSP/IPA permutation and not another ath10k board-data
test; it needs either persistent crash capture, deeper modem/RFS protocol
instrumentation, or a controlled comparison against a known-working
postmarketOS/sdm845-mainline kernel branch.

## 2026-06-02 pmOS Contrast WiFi DTS Quirk Test

A boot-only pmOS contrast image was built with the Razer DTS changed from the
baseline WiFi node to:

```dts
qcom,ath10k-calibration-variant = "razer_aura";
qcom,snoc-host-cap-skip-quirk;
```

Live `/proc/device-tree` confirmed that `qcom,snoc-host-cap-skip-quirk` was
present, `qcom,snoc-host-cap-8bit-quirk` was absent, and the WiFi node was
`okay`. Kernel source inspection shows the current `ath10k` driver supports
both calibration property names: it reads `qcom,calibration-variant` first and
falls back to `qcom,ath10k-calibration-variant`. It also supports both
`qcom,snoc-host-cap-8bit-quirk` and `qcom,snoc-host-cap-skip-quirk`.

Controlled late-start test result with direct
`/usr/local/bin/rmtfs-razer-test -r -P -s -v`:

- all six RFS paths still opened successfully:
  `/boot/modem_fs1`, `/boot/modem_fs2`, `/boot/modem_fsg`,
  `/boot/modem_fsc`, `/boot/modem_fsg_oem_1`, and
  `/boot/modem_fsg_oem_2`;
- initial RFS iovec reads still succeeded;
- `ath10k_snoc 18800000.wifi` bound to the device and reached IOMMU group
  assignment;
- MSS still reached `remote processor 4080000.remoteproc is now up` and then
  fataled about 0.255 seconds later;
- QRTR still showed RFS and TFTP but no WLFW/service 69;
- `tqftpserv` received no `wlanmdsp.mbn` request;
- `/sys/class/ieee80211` stayed empty and no `wlan0` appeared.

Conclusion: the Xiaomi/LG-style `qcom,snoc-host-cap-skip-quirk` does not move
the current Razer failure boundary. The repo DTS was returned to the baseline
`qcom,calibration-variant = "razer_aura"` plus
`qcom,snoc-host-cap-8bit-quirk`. Do not repeat host-cap quirk swaps as a
standalone fix unless a new log shows ath10k has progressed past MSS root-PD
startup and is actually issuing a host capability request.

## 2026-06-02 rmtfs FS1/FS2 Swap Live Test

A live-only rmtfs variant was built from the same `linux-msm/rmtfs` source plus
the existing Razer `nvdef_a`/`nvdef_b` path additions, with only the modem FS
partition mapping changed:

```text
/boot/modem_fs1 -> modemst2
/boot/modem_fs2 -> modemst1
```

The test binary was copied to `/tmp/rmtfs-razer-fs12-swap` and run directly as:

```text
/tmp/rmtfs-razer-fs12-swap -r -P -s -v
```

Kernel, DTS, firmware, `qcom_pd_mapper`, `tqftpserv`, and `ath10k_snoc` were
unchanged. MSS was started from a clean `offline` state with recovery disabled.

Result:

- MSS still reached `remote processor 4080000.remoteproc is now up`;
- MSS still fataled quickly, at
  `1970-01-12T09:40:58,333028+08:00`, about 0.12 seconds after the `now up`
  message in this run;
- QRTR still showed root modem services, RFS, IPA, and TFTP, but no
  WLFW/service 69;
- `tqftpserv` still received no `wlanmdsp.mbn` request;
- `/sys/class/ieee80211` stayed empty and no `wlan0` appeared;
- rmtfs still opened all six expected RFS paths;
- the RFS read sequence changed: it only logged `iovec 0 read 1:1` and
  `iovec 1 read 1:1`; it did not reach the previous large
  `iovec 1 read 2:4094` request.

Conclusion: FS1/FS2 mapping affects the modem's RFS read path, so EFS/slot
selection is not irrelevant. However, simply swapping `modemst1` and
`modemst2` does not fix or meaningfully advance MSS into WLFW/TFTP. The
previous large `modemst2` read is not by itself the root cause. Do not promote
this swapped rmtfs into rootfs; keep it as a diagnostic artifact only.

## 2026-06-02 Retracted RFS Mapping Lead: `oem_a/b`

Factory GPT inspection found that Razer has both:

```text
nvdef_a / nvdef_b  4 MiB each, flashed from nvdef.img
oem_a   / oem_b    1 GiB each
```

The current patched rmtfs maps:

```text
/boot/modem_fsg_oem_1 -> nvdef_a
/boot/modem_fsg_oem_2 -> nvdef_b
```

The `oem_a/b` alternative was considered because the requested path contains
the word `oem`. After re-reading the local `doc/porting.md` and the pmOS SDM845
WiFi notes, this is not a good next step. The standard porting path does not
involve putting WiFi/modem firmware or calibration into Android `oem_a/b`
partitions. It packages firmware into `/lib/firmware` and relies on the
standard Qualcomm userspace chain: `rmtfs`, `pd-mapper`, and `tqftpserv`.

Conclusion: do not run or promote an `oem_a/b` rmtfs mapping test unless a
primary source from Razer Android, such as `rmt_storage` logs/source behavior or
factory init scripts, directly proves that `/boot/modem_fsg_oem_1/2` should map
to `oem_a/b`. The more defensible interpretation remains that `nvdef_a/b` is
the relevant factory-provided OEM NV content, because factory flashing writes
`nvdef.img` to both `nvdef_a` and `nvdef_b`.

One separate boot-management issue was found: after several reboots, slot A can
become `slot-retry-count:a:0` and `slot-unbootable:a:yes`, causing the phone to
return directly to fastboot even though Linux artifacts are otherwise usable.
Recovery is:

```powershell
fastboot --set-active=a
fastboot reboot
```

This resets slot A retry count to 7. It is not a WiFi failure and should not be
confused with a bad rootfs or bad boot image.

## Questions To Ask Another AI / Engineer

1. On SDM845 mainline, can `qcom_q6v5_mss` safely recover from missing
   `pdc_reset` on first probe, or must `CONFIG_RESET_QCOM_PDC=y` be built-in
   when `CONFIG_QCOM_Q6V5_MSS=y`?

2. For SDM845 WCN3990, if `qrtr-lookup` shows RFS/IPA/TFTP but no WLFW and MSS
   crashes after `modem running`, what is the most likely layer:
   rmtfs/NV, service-registry/pd-mapper, modem firmware path, or DTS reset/halt
   quirk?

3. Should rmtfs run read-write rather than `-r` for first real WiFi bring-up?
   If yes, what is the safest way to test that on partitions
   `modemst1/modemst2/fsg/fsc/nvdef_a/nvdef_b`?

4. Android downstream MSS node has `qcom,mss_pdc_offset`, `pdc_sync`,
   `alt_reset`, `qcom,override-acc`, `qcom,signal-aop`, and
   `qcom,qdsp6v65-1-0`. Which, if any, correspond to required mainline
   qcom_q6v5_mss behavior for SDM845 Razer firmware?

5. Is mapping `/boot/modem_fsg_oem_1` to `nvdef_a` and
     `/boot/modem_fsg_oem_2` to `nvdef_b` correct for Razer Phone 2, given the
   factory package flashes the same `nvdef.img` to both slots?

6. Are there known SDM845 ports where WLFW only appears after bringing up ADSP,
   SLPI, or another protection domain, or should MSS alone be enough for WCN3990
   WiFi?

7. If SDM845 MSS reaches `modem running`, QRTR shows root services 66/43, and
   then the modem fatal-errors before WLFW appears, what is the shortest
   instrumented test to distinguish rmtfs/NV protocol failure from an
   SDM845/Razer-specific MSS reset/halt quirk?

## Commands For Next Live Check After Flash

After flashing the reverted non-dynamic-debug artifacts:

```bash
zcat /proc/config.gz | egrep 'CONFIG_QCOM_Q6V5_MSS|CONFIG_RESET_QCOM_PDC|CONFIG_QCOM_PDC|CONFIG_DYNAMIC_DEBUG|CONFIG_DEBUG_FS'
echo disabled | sudo tee /sys/class/remoteproc/remoteproc3/recovery
dmesg --time-format=iso | egrep -i 'pdc reset|remoteproc|q6v5|mpss|mba|modem|fatal|crash|ipa|ath10k|wlan|wifi|qrtr|tftp' | tail -220
qrtr-lookup
ip -br link
ls -l /sys/class/ieee80211
for r in /sys/class/remoteproc/remoteproc*; do echo "$r"; cat "$r/name" "$r/state" "$r/recovery"; done
systemctl --no-pager --plain status rmtfs qrtr-ns tqftpserv NetworkManager
```

If MSS enters a repeated crash loop, immediately freeze recovery:

```bash
echo disabled | sudo tee /sys/class/remoteproc/remoteproc0/recovery
```

## 2026-06-03 Invalid Live Module Deployment

A live deployment attempted to replace `qcom_q6v5`, `qcom_q6v5_mss`, and
`qcom_pd_mapper` while the phone was running the `pmos-sdm845-contrast`
artifact. The copied modules had the same `uname -r`
(`6.11.0-sdm845-g2fa43795f607-dirty`) but were not ABI-compatible with the
flashed boot kernel.

COM4 showed:

```text
module qcom_q6v5: .gnu.linkonce.this_module section size must match the kernel's built struct module size at run time
module qcom_pd_mapper: .gnu.linkonce.this_module section size must match the kernel's built struct module size at run time
```

Treat all observations after that live deployment as invalid for WiFi/MSS root
cause analysis. This is a build/deploy integrity failure, not evidence that
`pd-mapper`, firmware packaging, or the pmOS SDM845 guidance is wrong.

Action taken in repo tooling:

- `scripts/deploy-live-module.ps1` now refuses to live-deploy
  `qcom_q6v5`, `qcom_q6v5_mss`, or `qcom_pd_mapper` by default.
- The build skill records that matching `uname -r` is not enough for these
  Qualcomm core modules; they must come from the exact kernel tree/flavor that
  produced the currently flashed boot image.

Recovery for this specific bad state is to restore a boot/rootfs-matched module
set. If SSH does not return, flash the existing matched artifacts:

```powershell
fastboot flash boot output\boot.img
fastboot flash userdata output\rootfs-sparse.img
fastboot reboot
```

Live recovery was completed over SSH after the phone came back:

- Reinstalled the SSH public key using password login.
- Extracted the original matching modules from `output/rootfs.img`.
- Restored these phone modules from the matched rootfs image:
  - `kernel/drivers/remoteproc/qcom_q6v5.ko.zst`
  - `kernel/drivers/remoteproc/qcom_q6v5_mss.ko.zst`
  - `kernel/drivers/soc/qcom/qcom_pd_mapper.ko.zst`
- Rebooted and confirmed the `.gnu.linkonce.this_module section size` errors
  disappeared.

After the restore, a controlled live MSS test was run with recovery disabled.
This restored the real WiFi/MSS failure boundary:

```text
remoteproc3: Booting fw image qcom/sdm845/Razer/aura/mba.mbn
qcom-q6v5-mss 4080000.remoteproc: MBA booted without debug policy, loading mpss
ipa 1e40000.ipa: received modem running event
remoteproc remoteproc3: remote processor 4080000.remoteproc is now up
qcom-q6v5-mss 4080000.remoteproc: fatal error without message
remoteproc remoteproc3: crash detected in 4080000.remoteproc: type fatal error
```

QRTR during the crash window showed modem root services 66 and 43, plus RFS and
TFTP, but no WLFW/service 69 and no `wlan0`. `rmtfs` opened
`modem_fs1`, `modem_fs2`, `modem_fsg`, `modem_fsc`,
`modem_fsg_oem_1`, and `modem_fsg_oem_2`, then completed the same read sequence
as earlier before MSS fataled.

Conclusion: after restoring module integrity, the current blocker is still the
original one: MSS fatal after root services and before `wlan_pd`/WLFW. The
invalid ABI module deployment is excluded as the root cause.

For device stability while this remains unresolved, `rmtfs.service` was stopped
and disabled on the live phone after the controlled test. Re-enable/start it
only for a deliberate MSS/WiFi test window.

## 2026-06-03 Matched pmOS MSS Diagnostic Evidence

A matched `pmos-mss-diag` artifact was built and flashed:

- `boot.img` and rootfs modules both reported
  `6.11.0-sdm845-g2fa43795f607-dirty`.
- `/etc/razerphone2linux/mss-diagnostic-mode` existed.
- `rmtfs.service` was `disabled` and `inactive` at boot.
- On this boot, MSS was `/sys/class/remoteproc/remoteproc0`
  (`4080000.remoteproc`), not `remoteproc3`. Future scripts must always find
  MSS by `name`, not by hard-coded index.

The evidence bundle is:

```text
output/mss-crash-evidence-19700113-054459.tar.gz
output/mss-crash-evidence-19700113-054459/
```

Controlled trigger result:

```text
1970-01-13T05:45:00 qcom-q6v5-mss 4080000.remoteproc: q6v5 diag: AOSS load_state modem -> on
1970-01-13T05:45:00 qcom-q6v5-mss 4080000.remoteproc: q6v5 diag: AOSS load_state acknowledged
1970-01-13T05:45:00 qcom-q6v5-mss 4080000.remoteproc: MBA booted without debug policy, loading mpss
1970-01-13T05:45:02 ipa 1e40000.ipa: received modem running event
1970-01-13T05:45:02 remoteproc remoteproc0: remote processor 4080000.remoteproc is now up
1970-01-13T05:45:02 qcom-q6v5-mss 4080000.remoteproc: fatal error without message
```

The diagnostic patch dumped SMEM/RMB state at fatal:

```text
q6v5 diag fatal: smem host=-1 item=421 err=-2
q6v5 diag fatal: smem host=1 item=421 err=-2
q6v5 diag fatal: smem host=-1 item=6 err=-2
q6v5 diag fatal: smem host=1 item=6 err=-2
mss diag fatal: RMB_MBA_IMAGE[0x000]=0x96500000
mss diag fatal: RMB_PBL_STATUS[0x004]=0x00000001
mss diag fatal: RMB_MBA_COMMAND[0x008]=0x00000000
mss diag fatal: RMB_MBA_STATUS[0x00c]=0x00000004
mss diag fatal: RMB_PMI_META[0x010]=0xbfffc000
mss diag fatal: RMB_PMI_CODE_START[0x014]=0x8e000000
mss diag fatal: RMB_PMI_CODE_LENGTH[0x018]=0x077685ad
mss diag fatal: RMB_MBA_MSS_STATUS[0x040]=0x0000000b
mss diag fatal: RMB_MBA_ALT_RESET[0x044]=0x00000000
```

No devcoredump or pstore crash payload was exposed by this run.

Important correction: this `pmos-mss-diag` artifact did not include the earlier
`tms/pddump_disabled -> msm/modem/root_pd` mapping. The live dmesg showed:

```text
PDM: service 'tms/pddump_disabled' offset -1 returning 0 domains (of 0)
```

Therefore, this specific run re-tested the older PDM boundary rather than the
later mapped-PDM boundary. The active pmOS contrast patch set was updated with:

```text
kernel-patches/pmos-contrast/0004-qcom-pd-mapper-map-tms-pddump-disabled.patch
```

A live replacement of only `qcom_pd_mapper.ko.zst` was then attempted from the
same pmOS kernel tree after adding that patch. The target module hash was
verified on the phone:

```text
74b90175dfcbec7a5ced3bdd49da0bca3a2bb19fb71f4ad9ab2151d089e200a0
```

After reboot, USB networking/SSH did not return within the observation window,
and Windows did not show ADB or fastboot. Do not treat that as WiFi evidence
yet; it is currently a device/USB availability problem after a live core-module
replacement. If the device does not come back, recover by flashing the last
matched `pmos-mss-diag` boot/rootfs pair or by restoring the previous
`qcom_pd_mapper.ko.zst` backup if SSH becomes available.

The phone later returned over SSH. The live `qcom_pd_mapper.ko.zst` replacement
was confirmed active with hash:

```text
74b90175dfcbec7a5ced3bdd49da0bca3a2bb19fb71f4ad9ab2151d089e200a0
```

A second controlled evidence run was captured:

```text
output/mss-crash-evidence-pddump-19700113-065709.tar.gz
output/mss-crash-evidence-pddump-19700113-065709/
```

This proved the `tms/pddump_disabled` mapping works but does not move the MSS
fatal boundary:

```text
PDM: found msm/modem/root_pd / 180
PDM: service 'tms/pddump_disabled' offset -1 returning 1 domains (of 1)
ipa 1e40000.ipa: received modem running event
remoteproc remoteproc1: remote processor 4080000.remoteproc is now up
qcom-q6v5-mss 4080000.remoteproc: fatal error without message
```

No later `wlan/fw`, `kernel/elf_loader`, `wlanmdsp.mbn` TFTP request,
WLFW/service 69, `/sys/class/ieee80211`, or `wlan0` appeared. This excludes
`tms/pddump_disabled` returning zero domains as the direct root cause. Do not
repeat pd-mapper or `tms/pddump_disabled` mapping as a standalone WiFi fix.

After the run, `rmtfs.service` was stopped and disabled again. MSS remained
`crashed` with recovery disabled, which is the intended stable diagnostic
state.

Follow-up checks for deeper crash channels on the live diagnostic kernel:

```text
/sys/kernel/debug/qcom_minidump: absent
/sys/fs/pstore: empty
/sys/class/devcoredump: no devcd* entries
CONFIG_PSTORE=y
CONFIG_PSTORE_RAM=y
CONFIG_DYNAMIC_DEBUG=y
CONFIG_FTRACE=y
# CONFIG_KPROBES is not set
```

So the current image does not expose a Qualcomm minidump or remoteproc
devcoredump payload for this MSS fatal. Further narrowing requires adding a
new crash-reason channel, such as Qualcomm minidump support, a ramoops memory
region that actually records the relevant SSR data, DIAG/F3 logging, or deeper
RFS/NV content instrumentation. Repeating PDM, TFTP, ath10k board file, or
service ordering tests is not expected to reveal a new cause.

## 2026-06-08 Mainline Config Alignment and Userspace PD Mapper Contrast

The kernel config was checkpointed and then aligned with the SDM845/pmOS WiFi
bring-up shape:

```text
CONFIG_QCOM_Q6V5_MSS=m
CONFIG_QCOM_Q6V5_ADSP=m
CONFIG_QCOM_Q6V5_PAS=m
# CONFIG_QCOM_Q6V5_WCSS is not set
CONFIG_RESET_QCOM_PDC=m
CONFIG_QCOM_IPA=m
CONFIG_QCOM_PD_MAPPER=m
CONFIG_QCOM_PDR_HELPERS=m
CONFIG_QCOM_PDR_MSG=m
CONFIG_QCOM_RMTFS_MEM=y
CONFIG_RPMSG_QCOM_SMD=y
CONFIG_RPMSG_QCOM_GLINK=y
CONFIG_ATH10K_SNOC=m
```

Commits:

```text
d092ecc checkpoint: current Razer WiFi MSS kernel config
a1e5c10 config: align SDM845 WiFi MSS kernel options
```

The flashed artifact booted as:

```text
Linux razer-aura 6.16.0-rc2-sdm845-ged6098a37a4c-dirty
```

Result after the config alignment:

- `qcom_q6v5_mss`, `qcom_pd_mapper`, `qcom_sysmon`, `ipa`,
  `ath10k_snoc`, and `reset_qcom_pdc` were present and loaded.
- `firmware-5.bin`, `board-2.bin`, `wlanmdsp.mbn`, `modemuw.jsn`, and
  Razer `modem.mbn`/`modem.bXX` files were present.
- `qcom_pd_mapper` registered `msm/modem/root_pd` and
  `msm/modem/wlan_pd`.
- Kernel PDM returned one domain for `tms/pddump_disabled`:

```text
PDM diag: lookup request node=0 port=9 service=tms/pddump_disabled offset=0 valid=0
PDM diag: lookup response service=tms/pddump_disabled offset=0 len=1 total=1
```

MSS still fataled at the same boundary:

```text
ipa 1e40000.ipa: received modem running event
remoteproc remoteproc3: remote processor 4080000.remoteproc is now up
qcom-q6v5-mss 4080000.remoteproc: fatal error without message (smem 421 err -2 len 0 state 2)
```

A live userspace `pd-mapper` contrast was then run without reflashing:

1. Temporarily installed `/usr/local/bin/pd-mapper-live`.
2. Temporarily blocked kernel `qcom_pd_mapper` via
   `/etc/modprobe.d/razer-no-kernel-pdmapper.conf`.
3. Started `pd-mapper-live.service` before `rmtfs.service`.
4. Started `rmtfs.service` manually under observation.
5. Removed the temporary service, binary, and modprobe block afterwards.

The userspace mapper behaved differently from the kernel mapper for
`tms/pddump_disabled`:

```text
[PD-MAPPER] get_domain_list from 0:9 service=tms/pddump_disabled
[PD-MAPPER] get_domain_list response service=tms/pddump_disabled domains=0
```

Despite that difference, the MSS fatal boundary did not change:

```text
ipa 1e40000.ipa: received modem running event
remoteproc remoteproc2: remote processor 4080000.remoteproc is now up
qcom-q6v5-mss 4080000.remoteproc: fatal error without message (smem 421 err -2 len 0 state 2)
```

No later `wlan/fw`, `kernel/elf_loader`, `wlanmdsp.mbn` TFTP request,
WLFW/service 69, `/sys/class/ieee80211`, or `wlan0` appeared.

Factory DTBO / boot DTB follow-up:

- Fresh local comparison is recorded in
  `doc/razer-factory-dtbo-mss-wlan-compare-2026-06-08.md`.
- Factory `dtbo.img` entries do not appear to carry the core MSS/WLAN memory
  nodes. The relevant nodes are in the factory boot base DTB.
- The key memory regions match factory:
  - factory `wlan_fw_region@0x8df00000` size `0x100000` matches current
    `wlan-msa@8df00000` size `0x100000`;
  - factory `modem_region@0x8e000000` size `0x7800000` matches current
    `mpss@8e000000` size `0x7800000`;
  - factory `mba_region@0x96500000` size `0x200000` matches current
    `mba@96500000` size `0x200000`.
- The larger DTS delta is not the carveout address. It is factory downstream
  `qcom,pil-q6v55-mss` sequencing (`pdc_sync`, `alt_reset`,
  `qcom,override-acc`, `qcom,signal-aop`, `qcom,mss_pdc_offset`, SSCTL and
  minidump properties) versus mainline `qcom,sdm845-mss-pil`.

Conclusion:

- The missing/incorrect kernel config theory is no longer the best explanation.
- Kernel `qcom_pd_mapper` vs userspace `pd-mapper` is not the direct fix.
- `tms/pddump_disabled` returning zero or one domain is not the direct fix.
- The failure remains inside MSS root_pd after MPSS reaches running and before
  wlan_pd requests `kernel/elf_loader` or `wlan/fw`.
- Next work should focus on concrete MSS crash evidence and factory-delta
  sequencing, not another generic carveout guess: working DIAG/F3 logs,
  Qualcomm minidump/SSR reason extraction, or a targeted mainline MSS
  reset/PDC/AOP instrumentation patch.

The live rmtfs mapping at the time of this test was:

```text
/boot/modem_fs1       -> modemst1
/boot/modem_fs2       -> modemst2
/boot/modem_fsg       -> fsg
/boot/modem_fsc       -> fsc
/boot/modem_fsg_oem_1 -> nvdef_a
/boot/modem_fsg_oem_2 -> nvdef_b
```

Do not repeat WiFi driver, ath10k board file, GLINK/QRTR, service ordering,
or pd-mapper-only tests unless new evidence changes the boundary.

## 2026-06-09 Mainline RMB-only crash snapshot patch

A new repo-controlled diagnostic patch was added:

```text
kernel-patches/0003-razor-aura-mss-rmb-crash-snapshot.patch
```

Purpose:

- capture MSS fatal/watchdog state before the normal SMEM crash-reason lookup;
- keep the snapshot read-only and limited to the already-mapped RMB window;
- avoid post-fatal reads from the QDSP6 register window or halt-map registers,
  because earlier SDM845 tests showed those reads can trigger a kernel
  synchronous external abort from the q6v5 IRQ thread.

The patch logs:

```text
RMB_MBA_IMAGE_REG
RMB_PBL_STATUS_REG
RMB_MBA_COMMAND_REG
RMB_MBA_STATUS_REG
RMB_PMI_META_DATA_REG
RMB_PMI_CODE_START_REG
RMB_PMI_CODE_LENGTH_REG
RMB_MBA_MSS_STATUS
RMB_MBA_ALT_RESET
```

It deliberately does not `ioremap` inside the IRQ handler and does not read the
MBA memory contents directly. If a later test needs MBA memory bytes, map them
outside the fatal IRQ path first or collect them after the crash from a safer
context.

Build status:

```text
bash scripts/build-all.sh kernel
```

completed successfully after applying `0003`. The kernel release remained:

```text
6.16.0-rc2-sdm845-ged6098a37a4c-dirty
```

Fresh live-deploy module outputs were copied to:

```text
output/live-modules/qcom_q6v5.ko
output/live-modules/qcom_q6v5_mss.ko
```

Hashes:

```text
d0d2090ae7ebb43746f5287fae984a21653b9601a547b38fcf2e0506c3e2f583  output/live-modules/qcom_q6v5.ko
0b62b86285c8c37d416d2e1d817c65705eb5bf62a887baa32e2a31d82887ef10  output/live-modules/qcom_q6v5_mss.ko
```

Next test should not flash rootfs. If the phone boots the same kernel release,
deploy these two modules over SSH, run `depmod`, reboot, then trigger the usual
late-start MSS test and search dmesg for:

```text
mss rmb snapshot fatal:
```

At the time this note was written, SSH to `192.168.137.133` timed out, so the
modules were built and staged but not deployed.

Follow-up live deployment:

- SSH was restored by reinstalling `C:\tmp\razer_usb_ed25519.pub` into
  `/home/klipper/.ssh/authorized_keys`.
- `qcom_q6v5.ko` and `qcom_q6v5_mss.ko` were live-deployed with
  `scripts/deploy-live-module.ps1`, then the phone was rebooted.
- The phone booted the same kernel release and the deployed module hashes
  matched the staged outputs:

```text
d0d2090ae7ebb43746f5287fae984a21653b9601a547b38fcf2e0506c3e2f583  /lib/modules/6.16.0-rc2-sdm845-ged6098a37a4c-dirty/kernel/drivers/remoteproc/qcom_q6v5.ko
0b62b86285c8c37d416d2e1d817c65705eb5bf62a887baa32e2a31d82887ef10  /lib/modules/6.16.0-rc2-sdm845-ged6098a37a4c-dirty/kernel/drivers/remoteproc/qcom_q6v5_mss.ko
```

Observed mainline RMB snapshot:

```text
ipa 1e40000.ipa: received modem running event
PDM diag: lookup request node=0 port=9 service=tms/pddump_disabled offset=0 valid=0
PDM diag: lookup response service=tms/pddump_disabled offset=0 len=1 total=1
remoteproc remoteproc2: remote processor 4080000.remoteproc is now up
qcom-q6v5-mss 4080000.remoteproc: mss rmb snapshot fatal: image=0x96500000 pbl=0x00000001 cmd=0x00000000 mba=0x00000004 pmi_meta=0xbfffc000 pmi_start=0x8e000000 pmi_len=0x077685ad
qcom-q6v5-mss 4080000.remoteproc: mss rmb snapshot fatal: mss_status=0x0000000b alt_reset=0x00000000 mba_phys=0x0000000096500000 mba_size=0x200000 mpss_phys=0x000000008e000000 mpss_size=0x7800000
qcom-q6v5-mss 4080000.remoteproc: fatal error without message (smem 421 err -2 len 0 state 2)
```

Interpretation:

- `PBL_STATUS=0x1` and `MBA_STATUS=0x4` mean PBL/MBA reached the normal
  success/auth-complete states used by mainline `qcom_q6v5_mss`.
- `RMB_MBA_MSS_STATUS=0xb` has bit 0 set. Mainline SDM845 only checks
  `RMB_MBA_MSS_STATUS & BIT(0)` to consider the boot FSM complete, so this is
  not an MBA boot failure.
- The public mainline/android-mainline driver does not document a named
  decoding for `0xb`; do not claim it is a specific hardware fault without a
  downstream register definition.
- The failure remains after MPSS has been loaded and modem root services have
  started, still before `wlan/fw`, `kernel/elf_loader`, `wlanmdsp.mbn`,
  WLFW/service 69, `/sys/class/ieee80211`, or `wlan0`.

After collecting this, MSS recovery was disabled and `rmtfs.service` was
stopped to avoid a crash loop:

```text
/sys/class/remoteproc/remoteproc2/name     = 4080000.remoteproc
/sys/class/remoteproc/remoteproc2/state    = offline
/sys/class/remoteproc/remoteproc2/recovery = disabled
```

Captured evidence file:

```text
output/mss-rmb-snapshot-mainline-2026-06-09.txt
```

## 2026-06-09 remoteproc coredump and rejected pre-stop snapshot

The next attempt was to use the existing Linux remoteproc/devcoredump path
instead of guessing DTS or firmware paths. The useful correction was:

- `/sys/class/devcoredump/disabled` is write-once. If it has been written to
  `1` in a boot, it cannot be restored to `0` live; reboot is required.
- `/sys/kernel/debug/remoteproc/remoteproc*/coredump` defaults to `disabled`.
  It must be changed to `enabled` before triggering the crash.
- With `coredump=enabled` and recovery temporarily enabled, MSS generated a
  devcoredump entry.

The core was copied from the phone and saved as:

```text
output/mss-remoteproc-core-2026-06-09.elf
```

Properties:

```text
sha256: 7f91e9de32456b5be50a048affe6531343b8f37c6c95aebed28356ca81fdfb9a
size:   120M
type:   ELF32 core, 28 LOAD program headers
```

However, segment analysis showed every MPSS segment copied as zero-filled
memory:

```text
segments: 28
nonzero ratio: 0.000 for all segments
strings -a -n 4: 0 strings
```

Interpretation:

- The remoteproc/devcoredump path is functional enough to create a valid ELF
  container.
- It does not currently preserve useful MSS memory on this device. The generic
  recovery path calls `rproc_stop()` before `rproc->ops->coredump(rproc)`, and
  `qcom_q6v5_mss` then reloads MBA / transfers ownership before copying
  segments. On this Razer run, the copied MPSS payload was all zero, so this
  route did not reveal the crash reason.

A follow-up experimental patch tried to snapshot MPSS segment head/tail data in
the fatal IRQ callback before `remoteproc_stop()`. That patch was rejected:

- It changed `qcom_q6v5_mss.ko` hash to
  `2345ae5d111d0c373f42a7b9ec5df0f40493715cab3eacdbef012dbd6778121f`.
- After live deployment, the phone reached initramfs and printed
  `Switching to real root...`, then the real-root stage reset before SSH came
  up. COM4 disappeared, COM5 briefly appeared, then the phone rebooted.
- This confirms the pre-stop snapshot approach is too invasive for the boot
  path as implemented. Do not reintroduce MPSS memory copying in the fatal IRQ
  path unless it is made strictly opt-in and never runs during automatic boot.

Recovery steps taken:

- Built and flashed a safe boot image with:

```text
systemd.mask=rmtfs.service systemd.mask=tqftpserv.service
```

- Output artifact:

```text
output/boot-safe-mask-rmtfs.img
sha256 fd4215161795e726eaa1e16c4243a4ac699cf76218e37c94ae0a6ec04fcd9c3d
```

- This restored SSH while keeping the MSS boot path inactive.
- Replaced the risky live modules with the RMB-only safe pair:

```text
d0d2090ae7ebb43746f5287fae984a21653b9601a547b38fcf2e0506c3e2f583  qcom_q6v5.ko
0b62b86285c8c37d416d2e1d817c65705eb5bf62a887baa32e2a31d82887ef10  qcom_q6v5_mss.ko
```

Current safe live state after reboot:

```text
cmdline contains: systemd.mask=rmtfs.service systemd.mask=tqftpserv.service
rmtfs.service: inactive, masked-runtime
tqftpserv.service: inactive, masked-runtime
systemd-modules-load.service: active
4080000.remoteproc: offline
```

Repository status:

- `kernel-patches/0003-razor-aura-mss-rmb-crash-snapshot.patch` has been
  reverted to RMB-only logging. It no longer performs MPSS memory copying.
- `bash scripts/build-all.sh kernel` was rerun successfully after the patch was
  reverted, proving the repo-controlled patch set builds again.

Next crash-reason direction:

- Do not repeat generic remoteproc coredump alone; it produced a valid but
  zero-filled MPSS core.
- Do not repeat fatal-IRQ MPSS memory copying in the default boot path.
- The next useful design must make crash capture opt-in after SSH is available,
  or use a different non-invasive channel such as a DIAG/F3 log mask path,
  downstream minidump table decoding if a readable MSS subsystem TOC exists, or
  a controlled rmtfs/QRTR transaction trace that does not touch MPSS memory.

## 2026-06-15 Exact pmOS/MSM8998 Service-Order Test

The postmarketOS/MSM8998 recommendation was tested with the exact intended
ordering, live over SSH and without rebuilding the rootfs:

```text
diag-router
  -> qrtr-ns
  -> userspace pd-mapper
  -> tqftpserv
  -> MSS driver already probed but remoteproc offline
  -> rmtfs powers MSS
```

The first run exposed two simultaneous service-registry locator services,
because the kernel `qcom_pd_mapper` was automatically loaded again. A second
clean run therefore moved `qcom_pd_mapper.ko` aside, ran `depmod`, rebooted with
`rmtfs.service` disabled, and verified:

```text
modinfo qcom_pd_mapper: module not found
4080000.remoteproc: offline
rmtfs.service: disabled/inactive
QRTR service 64 count: 1
```

The userspace-only run produced:

```text
00:51:19.111207 remote processor 4080000.remoteproc is now up
00:51:19.346753 mss rmb snapshot fatal
00:51:19.382831 fatal error without message
```

The fatal began about 0.236 seconds after modem-up. Userspace `pd-mapper`
received only the modem request for `tms/pddump_disabled` and returned zero
domains. It never received `wlan/fw` or `kernel/elf_loader`. All six RFS opens
and the initial reads succeeded, but QRTR never exposed WLFW service 69 and
`/sys/class/ieee80211` remained empty.

Evidence:

```text
output/razer-wifi-diag-router-19700125-004838/
output/razer-wifi-diag-router-19700125-005111/
```

Conclusion:

- Starting `diag-router` before all Qualcomm userspace services does not move
  the current MSS fatal boundary.
- Replacing kernel `qcom_pd_mapper` with userspace `pd-mapper` does not move the
  boundary either.
- Do not repeat DIAG service ordering or pd-mapper-only tests as a WiFi fix.
  `diag-router` remains useful only when paired with a real DIAG log-mask/F3
  capture mechanism.
- Do not unload `ath10k_snoc` or `qcom_q6v5_mss` after MSS has already
  crashed/running; both removal paths can block. Disable `rmtfs.service`,
  reboot to an offline MSS, then run controlled tests.

## 2026-06-15 F3 DIAG Capture With Userspace pd-mapper

A real F3 message-mask capture was staged before MSS boot, using the pmOS
service order:

```text
diag-router
  -> qrtr-ns
  -> userspace pd-mapper
  -> tqftpserv
  -> F3 message mask attached
  -> rmtfs powers MSS
```

The kernel `qcom_pd_mapper.ko` was temporarily removed for this test. Before
the run, MSS was `offline`, `rmtfs.service` was disabled/inactive, and
`modinfo qcom_pd_mapper` failed as expected. The AP-side DIAG setup was proven
to work: `diag-capture` received the F3 mask acknowledgement
`7d 05 01 00 ff ff ff ff`.

MSS then followed the unchanged failure sequence:

```text
01:14:24.084423 remote processor 4080000.remoteproc is now up
01:14:24.324082 mss rmb snapshot fatal
01:14:24.360241 fatal error without message
```

The first fatal snapshot was approximately 0.240 seconds after modem-up.
Userspace pd-mapper received `tms/pddump_disabled` from modem node 0, and all
six RFS files opened successfully. However:

- `diag-router` connected CMD sockets only to node 5, node 9, and node 10
  (ADSP/SLPI/CDSP).
- No Modem node 0 DIAG CMD/control/data channel became available before fatal.
- `diag-capture` received only its local mask acknowledgement and no F3 packet
  from MSS.
- No `wlan/fw`, `kernel/elf_loader`, WLFW service 69, `wlan0`, or
  `/sys/class/ieee80211` appeared.

The `MODEM:CNTL/DATA/DCI` entries shown by `qrtr-lookup` on node 1 are local
AP-side services registered by `diag-router`; they are not proof that Modem
node 0 established DIAG.

Evidence:

```text
output/razer-wifi-diag-f3-19700125-011412/
output/razer-wifi-diag-f3-19700125-011412.tar.gz
SHA256 750061C4C42D3A064948765D18E070EAB3B7C8377D97BEB013ECFE2F24335100
```

Conclusion:

- DIAG/F3 is now correctly built and staged on the AP side.
- The current MSS failure happens before its DIAG transport is established, so
  `diag-router` cannot expose an internal F3 crash string for this failure.
- Repeating service-order or log-mask tests will not reveal more unless a
  kernel/firmware change first moves the fatal boundary past Modem DIAG
  registration.
- The kernel pd-mapper module was restored and loaded after the test without a
  rootfs flash or reboot. MSS recovery remains disabled and rmtfs remains
  inactive.

## IWD / EAPoL Workaround Boundary

The postmarketOS MSM8998 note about `iwd` and
`ControlPortOverNL80211=false` is a post-WiFi-interface workaround. It applies
only after:

```text
WLFW appears
ath10k_snoc creates a phy
/sys/class/ieee80211 is non-empty
wlan0 exists
scan works but WPA/EAPoL association fails
```

It does not apply to the current Razer failure, because the phone still stops
before WLFW and before `/sys/class/ieee80211` exists. The current rootfs is
also using NetworkManager with `wpa_supplicant`; `iwd.service` is not installed
or active on the live phone in the last check. Do not add `/etc/iwd/main.conf`
as a WiFi bring-up fix unless the rootfs is deliberately switched to iwd and
wlan0 already exists.

If a later build reaches wlan0 and uses iwd, the only intended config is:

```ini
[General]
ControlPortOverNL80211=false
```

## Firmware Conflict Boundary

The useful firmware-conflict test is not "delete every other firmware file".
Linux firmware lookup is path/name driven. For this SDM845 WCN3990 path, only
conflicting files at the exact requested names/aliases are likely to matter:

```text
/usr/lib/firmware/qcom/sdm845/Razer/aura/{mba.mbn,modem.mbn,modem.b*,wlanmdsp.mbn,modemr.jsn,modemuw.jsn}
/lib/firmware/image/{wlanmdsp.mbn,modemr.jsn,modemuw.jsn}
/readonly/firmware/image -> /lib/firmware/image
/usr/lib/firmware/ath10k/WCN3990/hw1.0/{firmware-5.bin,board.bin,board-2.bin}
```

Do not remove ADSP/CDSP/SLPI/Venus firmware merely because it is "other
firmware"; those are requested by different remoteproc or media drivers. Prior
controlled dependency tests with ADSP/SLPI/CDSP/IPA did not move the MSS fatal
boundary.

The next safe firmware audit when SSH is available is:

```bash
cat /sys/module/firmware_class/parameters/path 2>/dev/null || true
find /lib/firmware /usr/lib/firmware /readonly/firmware \
  \( -path '*/qcom*' -o -path '*/image*' -o -iname '*modem*' \
     -o -iname '*wlan*' -o -iname '*mba*' -o -iname '*bdwlan*' \
     -o -iname 'board*.bin' -o -iname 'firmware-5.bin' \) \
  -type f -printf '%p %s\n' 2>/dev/null | sort
```

If a duplicate non-Razer file exists at one of the exact requested paths, move
only that file aside and retest. If duplicates are merely unrelated firmware in
other directories, leave them alone.

### 2026-06-15 Live WCNSS/WCN3990 Audit

The user-provided postmarketOS Qualcomm WiFi section was checked against the
live Razer rootfs. The old WCNSS/Prima interface is not present:

```text
/dev/wcnss_wlan: missing
/sys/module/wlan: missing
/sys/module/prima: missing
/sys/module/qca_cld: missing
/sys/module/wcnss_wlan: missing
/sys/module/qcom_wcnss_pil: missing
```

`qcom_wcnss_pil.ko` exists in `/lib/modules`, but it is not loaded and no
WCNSS/Prima autoload rule exists. The active path is mainline SDM845/WCN3990:

```text
ath10k_core.ko
ath10k_snoc.ko
qcom_q6v5_mss.ko
qcom_pd_mapper.ko
/sys/bus/platform/devices/18800000.wifi
```

Therefore the WiFi wiki commands:

```sh
echo 1 > /dev/wcnss_wlan
echo sta > /sys/module/wlan/parameters/fwpath
```

do not apply to the current kernel/rootfs. They are for downstream WCNSS-style
devices, not this mainline WCN3990/ath10k_snoc path.

The live firmware alias audit showed `/lib` is a symlink to `/usr/lib`, so
`/lib/firmware` and `/usr/lib/firmware` are not competing duplicate trees.
`wlanmdsp.mbn`, `modemr.jsn`, and `modemuw.jsn` matched the repo hashes through
their aliases. One stale exact-path file was found:

```text
/usr/lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin
```

The stale live hash was:

```text
fef6539e0127579536bc977be57a90d018b83f2931fedc3a8870fbe38d6c4127
```

It was backed up as `firmware-5.bin.before-20260615` and replaced with the
repo copy:

```text
e5c80e804b6188c5896dd926a4480523e25e06ce66e56819b98545b411bc1911
```

This is a real cleanup for the later ath10k stage, but it cannot explain the
current MSS fatal because no WLFW, ath10k firmware request, or wlan0 exists
before the crash.

## 2026-06-15 Remoteproc Devcoredump Result

The mainline remoteproc devcoredump path was tested successfully with the
matched diagnostic kernel. The required configuration is present:

```text
CONFIG_DEV_COREDUMP=y
CONFIG_REMOTEPROC=y
CONFIG_QCOM_Q6V5_MSS=m
```

The correct controlled sequence is:

```sh
echo inline > /sys/class/remoteproc/remoteproc0/coredump
echo enabled > /sys/class/remoteproc/remoteproc0/recovery
```

Do not combine this with `recovery=disabled`. In this kernel,
`rproc_boot_recovery()` stops the remote processor and only then calls
`rproc->ops->coredump()`. Disabling recovery therefore prevents creation of
the `devcdN` device.

With inline coredump enabled, the MSS fatal produced:

```text
/sys/class/devcoredump/devcd1
failing_device:
  /sys/devices/platform/soc@0/4080000.remoteproc/remoteproc/remoteproc0
```

The full ELF was captured as:

```text
output/mpss-coredump-20260615.elf
size:   125208929 bytes
sha256: 7f91e9de32456b5be50a048affe6531343b8f37c6c95aebed28356ca81fdfb9a
format: ELF32 CORE, 28 PT_LOAD segments
```

All 28 segment payloads were byte-for-byte zero:

```text
segment payload bytes: 125207981
0x00 bytes:            125207981
0xff bytes:            0
other bytes:           0
```

The kernel journal confirms the dump framework completed all bytes, but the
normal modem boot used `MBA booted without debug policy`. The mainline MSS
recovery order stops/reclaims the subsystem before the custom dump callback
reloads MBA and reclaims MPSS ownership. On this device that produces a valid
ELF container with no preserved MPSS contents.

Conclusion: remoteproc devcoredump is operational, but it cannot currently
provide the modem crash context. Repeating `enabled` instead of `inline` will
not fix this because both mechanisms use the same post-stop segment callback.
A useful modem-side dump now requires a valid Qualcomm `msadp` debug-policy
image, a downstream minidump/ramdump path that preserves data before reclaim,
or an external DLOAD/QXDM path. Do not patch the recovery order to read the
protected MPSS region before stop without a proven ownership transition; an
earlier direct pre-stop MPSS read caused a synchronous external abort.

## 2026-06-15 RMTFS IOVEC Decode And EFS Sector Check

The verbose rmtfs output has two separate identifiers:

```text
[RMTFS] iovec 1, not forced => (0:0)
[RMTFS]       read 2:4094 0xf5b01400
```

Source inspection of `.tmp/rmtfs-razer-test/rmtfs.c` proves:

- `iovec 1` is `req.caller_id`, selecting caller 1 (`/boot/modem_fs2`,
  mapped to `modemst2`).
- `read 2:4094` is `sector_addr:num_sector`.
- `0xf5b01400` is the shared-memory physical offset.

Therefore the final request is a read from `modemst2`, starting at sector 2
for 4094 sectors. The `2` is not caller/file descriptor 2 and does not select
`/boot/modem_fsg`. The preceding requests are:

```text
iovec 0 -> modemst1, sector 1, 1 sector
iovec 1 -> modemst2, sector 1, 1 sector
iovec 1 -> modemst2, sector 2, 4094 sectors
```

The final read covers `modemst2` sectors 2 through 4095. Together with the
sector-1 request, the modem reads all of the 2 MiB partition except sector 0.
The response completed about 146 ms before MSS fatal.

The `del_client 0:<port>` messages after each request are QRTR control-plane
notifications. `rmtfs_del_client()` only logs and returns; it does not call
`storage_close()`. A storage handle is closed only by a QMI
`QMI_RMTFS_CLOSE` request. Therefore these messages must not be interpreted as
the six RFS files being opened and immediately closed.

Read-only checks on the live phone showed:

```text
modemst1 sector 0: contains IMGEFS1
modemst2 sector 0: contains IMGEFS2
modemst1 sector 1 sha256:
  746406e1933e5f5a517393ba94836d8ca139b309a19131946bbaac07d3582407
modemst2 sector 1 sha256:
  0777e1439f7ecc30f540a2967c72eb622600355dc32d9007ee7d17dd43ee9244
fsg: 2097152 bytes, all zero
```

This disproves the proposed interpretation that the final IOVEC read was from
FSG. An all-zero FSG may still be worth comparing with a factory-fresh or
Android-booted Razer device, but it was not read in this crash window and
cannot currently be identified as the direct fatal trigger. Do not write or
restore FSG based on this log.

## 2026-06-16 RMTFS Detail Instrumentation Result

A live-only `rmtfs-detail` binary was built from `linux-msm/rmtfs` commit
`14cb1ee69f556873dc271832b77163669e1d6459` with
`tools/rmtfs-razer-detail-logging.patch`. The source preparation and phone-side
build flow is now reproducible with:

```bash
bash scripts/prepare-rmtfs-detail-live.sh
bash /tmp/phone-build-rmtfs-detail-live.sh
```

The tested phone binary was:

```text
/tmp/rmtfs-detail
sha256: 9a6db1f700aa59bcade7ac23c3fd2b80a6adb113b31e06b1ba8959035bf2ab0b
size:   157928 bytes
```

Evidence was saved under:

```text
output/rmtfs-detail-evidence-20260616-1143/
```

The detail log confirms the RFS path and content characteristics:

```text
open /boot/modem_fs1       -> modemst1
open /boot/modem_fs2       -> modemst2
open /boot/modem_fsg       -> fsg
open /boot/modem_fsc       -> fsc
open /boot/modem_fsg_oem_1 -> nvdef_a
open /boot/modem_fsg_oem_2 -> nvdef_b

caller=0 requested=/boot/modem_fs1 partlabel=modemst1
  sector=1 count=1 bytes=512
  fnv1a64=37952f49765fb9f6 zero_ratio=3.32%

caller=1 requested=/boot/modem_fs2 partlabel=modemst2
  sector=1 count=1 bytes=512
  fnv1a64=9949c03911562e42 zero_ratio=3.32%

caller=1 requested=/boot/modem_fs2 partlabel=modemst2
  sector=2 count=4094 bytes=2096128
  fnv1a64=6795d773f424a0f2 zero_ratio=0.39%
```

The bulk read from `modemst2` completed successfully and is not mostly zero.
No RFS write request was observed. FSG was opened but not read before the MSS
fatal. The fatal boundary remained the same:

```text
remote processor 4080000.remoteproc is now up
~273 ms later:
mss_status=0x0000000b
fatal error without message (smem 421 err -2 len 0 state 2)
SMEM host -1/1 item 421 and item 6 all return err=-2
```

There was still no `wlan/fw`, no `kernel/elf_loader`, no `wlanmdsp.mbn` TFTP
request, no WLFW/service 69, no `/sys/class/ieee80211`, and no `wlan0`.

Conclusion: this controlled run weakens the FSG-as-direct-cause hypothesis.
The modem's last AP-visible RFS operation is a successful, nonzero `modemst2`
bulk read. The next useful RFS/NV work is semantic EFS validation against
Android/factory behavior, not rewriting FSG from the Linux side. The main
bring-up blocker is still the MSS fatal after root service registration and
before WLFW/wlan_pd activity.

## 2026-06-18 WLFW and wlan0 breakthrough

The live `tqftpserv` v1.2 path translation allowed the Razer modem/WLAN PD to
request its Android-style firmware paths. On a cold boot this moved the system
past the old MSS fatal boundary:

- WLFW QRTR service 69 appeared and remained registered;
- baseline mainline ath10k sent `IND_REGISTER`, `HOST_CAP`, then `MSA_INFO`;
- WLFW rejected `MSA_INFO` with QMI error 90,
  `QMI_ERR_INCOMPATIBLE_STATE_V01`;
- no `phy0` or `wlan0` appeared in that baseline boot.

This made the earlier 2026-06-02 host-cap-skip test newly relevant. That old
test happened before WLFW existed, so ath10k never issued HOST_CAP and could
not evaluate the quirk. A same-release live `ath10k_snoc.ko` was therefore
built with a disabled-by-default `force_skip_host_cap` diagnostic parameter.
With `force_skip_host_cap=1` on the next cold boot:

- the log confirmed `forcing WLFW host capability request skip`;
- MSA_INFO and the remaining WLFW setup completed;
- ath10k reported Razer WLAN firmware
  `WLAN.HL.2.0.c10-00085-QCAHLSWMTPLZ-1.208093.1`;
- ath10k loaded API 5 firmware and completed HTT/WMI initialization;
- `/sys/class/ieee80211/phy0` and `wlan0` appeared;
- NetworkManager successfully scanned multiple nearby WPA2/WPA3 access points.

The live module SHA256 was
`0e07fdfe10e4e2b0788c3def987e2c4f1687429bb48686ef0b4e97fcc5025e21`.
Evidence is in
`output/wifi-hostcap-skip-success-20260618.tar.gz`.

The successful tqftpserv binary SHA256 was
`c103b1d28aa9514a835bcba7380ce7e838f26439e328deeb752470bd8e92a4ad`.
It is preserved as `rootfs-binaries/arm64/tqftpserv`; both the full rootfs
build and validation refresh install it over the distro package's
`/usr/bin/tqftpserv`, while retaining the package-provided service unit and
dependencies.

The production DTS policy is now `qcom,snoc-host-cap-skip-quirk`, matching the
successful SDM845 beryllium-style flow. Do not add an MSA retry or delay: the
binary test proved that the preceding HOST_CAP exchange, not TFTP timing or the
WLAN MSA carveout, caused QMI error 90.

Remaining cleanup after WiFi bring-up:

- ath10k currently reports an invalid factory MAC and chooses a random address;
- replace the live diagnostic module deployment with a normal boot artifact
  carrying the DTS quirk when the next boot image is intentionally packaged;
- then remove the live modprobe option after the DTS-backed boot is deployed.
