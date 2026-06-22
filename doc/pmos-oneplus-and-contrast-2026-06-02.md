# pmOS OnePlus Reference and Razer Contrast - 2026-06-02

This note records two related checks requested for the Razer Phone 2
(`razer-aura`) WiFi/MSS bring-up:

1. Inspect a working SDM845 postmarketOS OnePlus 6 (`oneplus-enchilada`)
   reference image.
2. Produce a Razer `pmos-contrast` artifact: postmarketOS SDM845 kernel/config
   baseline, but with the Razer DTS, Razer factory firmware layout, and the
   existing Ubuntu/Razer rootfs flow.

## Source Access

The OnePlus reference image was already present in the repo workspace from a
previous download/export:

```text
.tmp/pmos-reference/downloads/oneplus-enchilada-20260525.img
.tmp/pmos-reference/downloads/oneplus-enchilada-20260525.raw.img
.tmp/pmos-reference/downloads/oneplus-root.ext4
.tmp/pmos-reference/downloads/oneplus-boot.ext2
```

This turn did not run `pmbootstrap init/install/export` from scratch because the
reference image was already available and readable. The rootfs was inspected
read-only with `debugfs`, without mounting it.

The pmaports checkout at `.tmp/pmos-reference/pmaports` is not necessarily the
same exact release as the downloaded image. The downloaded image rootfs reports
modules for `6.16.7-sdm845`, while the local pmaports kernel package config is
for `6.11.0`. Treat them as two references:

- downloaded image: rootfs, firmware layout, systemd service layout;
- pmaports checkout: device package, deviceinfo, kernel package config.

## OnePlus 6 Reference Findings

Reference rootfs files extracted into:

```text
output/pmos-oneplus-reference/
```

Important extracted files:

```text
firmware-layout.txt
service-layout.txt
service-rmtfs.txt
service-rmtfs-dir.txt
service-pd-mapper.txt
service-tqftpserv.txt
modules-layout.txt
modules-builtin.txt
modules-dep.txt
pmaports-key-files.txt
```

### Firmware Layout

The OnePlus image keeps device-specific modem firmware under:

```text
/usr/lib/firmware/qcom/sdm845/oneplus6/
```

That directory contains:

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

It also provides top-level SDM845 aliases/symlinks such as:

```text
/usr/lib/firmware/qcom/sdm845/modemuw.jsn
/usr/lib/firmware/qcom/sdm845/modem.mbn.zst
/usr/lib/firmware/qcom/sdm845/wlanmdsp.mbn.zst
```

For ath10k WCN3990:

```text
/usr/lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin.zst
/usr/lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin.zst
/usr/lib/firmware/ath10k/WCN3990/hw1.0/wlanmdsp.mbn.zst
```

This confirms the same high-level layout we have been trying to reproduce on
Razer: device-specific modem firmware plus global SDM845 aliases and ath10k
WCN3990 firmware.

### Service Layout

The OnePlus image uses systemd services for the modem/WiFi support chain:

```ini
# rmtfs.service
[Unit]
Description=Qualcomm remotefs service
Before=NetworkManager.service

[Service]
ExecStart=/usr/bin/rmtfs -r -P -s
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
```

```ini
# pd-mapper.service
[Unit]
Description=Qualcomm PD mapper service

[Service]
ExecStart=/usr/bin/pd-mapper
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
```

```ini
# tqftpserv.service
[Unit]
Description=QRTR TFTP services
Before=rmtfs.service

[Service]
ExecStart=/usr/bin/tqftpserv
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
```

The notable order is:

```text
tqftpserv before rmtfs
rmtfs before NetworkManager
pd-mapper independent, restart=always
```

This does not prove Razer should autostart the chain during unsafe validation,
but it is the working-system reference order to compare against after MSS crash
loops are controlled.

### Kernel Modules in the Downloaded Image

The downloaded OnePlus rootfs has module release:

```text
6.16.7-sdm845
```

Relevant modules present:

```text
kernel/net/qrtr/qrtr.ko.zst
kernel/net/qrtr/qrtr-smd.ko.zst
kernel/net/qrtr/qrtr-tun.ko.zst
kernel/net/qrtr/qrtr-mhi.ko.zst
kernel/drivers/remoteproc/qcom_q6v5_mss.ko.zst
kernel/drivers/remoteproc/qcom_sysmon.ko.zst
kernel/drivers/rpmsg/qcom_glink_smem.ko.zst
kernel/drivers/net/wireless/ath/ath10k/ath10k_snoc.ko.zst
kernel/drivers/net/wireless/ath/ath10k/ath10k_core.ko.zst
```

`modules.builtin` lists:

```text
kernel/drivers/soc/qcom/pdr_interface.ko
kernel/drivers/soc/qcom/qcom_pdr_msg.ko
kernel/drivers/soc/qcom/rmtfs_mem.ko
```

The image has userspace `pd-mapper.service`; `qcom_pd_mapper` was not found in
the extracted downloaded-image module lists. The local pmaports 6.11 config,
however, sets `CONFIG_QCOM_PD_MAPPER=m`. Keep this version mismatch in mind.

## pmaports OnePlus Device Package

The local pmaports OnePlus device package declares:

```text
linux-postmarketos-qcom-sdm845
soc-qcom-sdm845
soc-qcom-sdm845-ucm
soc-qcom-sdm845-qbootctl
```

The nonfree firmware subpackage depends on:

```text
firmware-oneplus-sdm845>=9
hexagonrpcd
soc-qcom-sdm845-nonfree-firmware
soc-qcom-sdm845-modem
```

Device info:

```text
deviceinfo_dtb="qcom/sdm845-oneplus-enchilada"
deviceinfo_append_dtb="true"
deviceinfo_kernel_cmdline="console=ttyMSM0,115200"
```

The initramfs module list is small and touch/haptics focused:

```text
i2c_qcom_geni
rmi_core
rmi_i2c
qcom_spmi_haptics
```

## pmOS Contrast Artifact Produced

The Razer `pmos-kernel` path was built successfully, then the existing Razer
rootfs was refreshed with matching modules and boot was repackaged.

Kernel release:

```text
6.11.0-sdm845-g2fa43795f607-dirty
```

Kernel flavor:

```text
pmos-sdm845-contrast
```

`output/rootfs.kernel-release` matches the kernel release.

Artifacts:

```text
output/boot.img
output/rootfs-sparse.img
output/vbmeta_disabled.img
output/Image.gz
output/sdm845-razer-aura.dtb
output/config-pmos-sdm845-contrast
```

SHA256:

```text
boot.img:
  7020ABE431C302C22F33DCDD3A53183497E7E86DD79B05FC24383E3C92D959EC

rootfs-sparse.img:
  A1B0EC0EC2ABA272727AECC06A287A385E2EC2DC4507600E53BFE61681B5DBFF

vbmeta_disabled.img:
  A5D672A1CC2ADF965555D09BB54DDBDA9424123635DB60DF93D204A3F547BEC3

Image.gz:
  DDD55E165C31347F177BF772D86639391381552116907C52E9F0826E15559364

sdm845-razer-aura.dtb:
  F18E1C30C64303A96CBB7A4367C8ECEA28ABE3C4C5184E49E34643BBB1D9764C

config-pmos-sdm845-contrast:
  EB2EBA1C9AF842F5177933CC03982F31A75BBE9BAF6410DA09B89D16F6D10C0E
```

Sizes:

```text
boot.img:                    15,659,008 bytes
rootfs-sparse.img:        2,159,423,844 bytes
vbmeta_disabled.img:              4,096 bytes
Image.gz:                    14,531,456 bytes
sdm845-razer-aura.dtb:          110,295 bytes
config-pmos-sdm845-contrast:    236,924 bytes
```

## Interpretation

The OnePlus reference supports the user's expectation that the SDM845 WiFi
chain is mostly common:

```text
MSS remoteproc
QRTR over GLINK/SMEM
rmtfs
pd-mapper
tqftpserv
wlanmdsp/modemuw/modemr
ath10k WCN3990 firmware and board data
```

But it also shows why flashing another device image directly is not a safe
shortcut:

- the device-specific firmware directory is `oneplus6`, not `Razer/aura`;
- the DTB is `qcom/sdm845-oneplus-enchilada`;
- the rootfs module release in the downloaded image is `6.16.7-sdm845`, while
  the local pmaports contrast kernel is `6.11.0-sdm845-...`;
- the OnePlus image service chain assumes its rmtfs/NV behavior is safe to
  autostart, while the Razer validation image has intentionally disabled
  automatic MSS/rmtfs crash loops.

The useful next comparison is not "rename image and flash", but:

1. Compare Razer rootfs service ordering against the OnePlus order:
   `tqftpserv -> rmtfs -> NetworkManager`, with pd-mapper always available.
2. Compare Razer firmware aliases against OnePlus's top-level
   `/usr/lib/firmware/qcom/sdm845/*` symlink pattern.
3. Test the produced `pmos-sdm845-contrast` artifact on Razer to see if the MSS
   fatal boundary moves. If it still fatal-errors before `wlan/fw` or
   `kernel/elf_loader`, the remaining difference is likely Razer-specific
   firmware/NV/RFS/downstream-MSS behavior rather than generic SDM845 kernel
   config.

## Flash Commands for pmOS Contrast Artifact

Only use these if intentionally testing the pmOS contrast build:

```powershell
fastboot flash boot output\boot.img
fastboot flash userdata output\rootfs-sparse.img
fastboot --disable-verity --disable-verification flash vbmeta output\vbmeta_disabled.img
fastboot reboot
```

After flashing userdata, reinstall the SSH key before diagnostics because
`/home/klipper/.ssh/authorized_keys` will be reset.
