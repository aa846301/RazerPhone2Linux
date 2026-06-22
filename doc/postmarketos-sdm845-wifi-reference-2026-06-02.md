# postmarketOS SDM845 WiFi Reference - 2026-06-02

This note records the postmarketOS wiki/MR material provided by the user and
maps it to the Razer Phone 2 (`razer-aura`) Linux WiFi bring-up. It is a
working reference for future debugging, not proof that a generic image can be
flashed onto this phone.

## Source Status

The postmarketOS wiki and GitLab pages may be blocked by crawler protection.
When that happens, do not claim the page was read. Use these sources in this
order:

1. User-pasted wiki/MR text in the conversation.
2. Local pmaports checkout, if present.
3. Extracted postmarketOS reference images, if present.
4. Live web pages only when actually readable.

Relevant URLs from the user-provided material:

- <https://wiki.postmarketos.org/wiki/Qualcomm_SDM845_(qualcomm-sdm845)>
- <https://wiki.postmarketos.org/index.php?title=Qualcomm_SDM845_(qualcomm-sdm845)&action=edit>
- <https://gitlab.postmarketos.org/postmarketOS/pmaports/-/merge_requests/4599>
- <https://wiki.postmarketos.org/wiki/OnePlus_6_(oneplus-enchilada)/Dual_Booting_and_Custom_Partitioning>
- <https://wiki.postmarketos.org/wiki/Qualcomm_Snapdragon_845_(SDM845)>
- <https://wiki.postmarketos.org/index.php?title=WiFi>
- <https://wiki.postmarketos.org/index.php?title=Device_specific_package>
- <https://wiki.postmarketos.org/wiki/Firmware>
- <https://raw.githubusercontent.com/torvalds/linux/0cdd776ec92c0fec768c7079331804d3e52d4b27/arch/arm64/boot/dts/qcom/sdm845-oneplus-common.dtsi>

## SDM845 Generic / U-Boot Flow

The generic SDM845 postmarketOS device target uses U-Boot as an intermediary
bootloader. U-Boot is flashed to the Android boot partition, ABL treats it like
a Linux boot image, then U-Boot provides a UEFI environment and boots the first
EFI binary, typically systemd-boot.

Important details from the user-provided wiki/MR text:

- The generic device codename is `qualcomm-sdm845` / `qcom-sdm845`.
- U-Boot handles DTB selection automatically for supported devices.
- The boot flow expects an EFI System Partition containing kernel, initramfs,
  DTBs, and bootloader configuration.
- The example install command includes `fastboot erase dtbo flash boot
  u-boot-$CODENAME.img reboot`.
- The wiki marks this path as work in progress.
- U-Boot mass storage can expose the full UFS device and is useful for recovery,
  but it also carries real brick risk if the partition table is overwritten.
- MR 4599 mentions firmware conflicts as a known issue, including `board-2.bin`
  and Bluetooth firmware path handling.

Project judgment:

- U-Boot is not itself the WiFi fix. It changes boot management, DTB selection,
  and firmware/boot filesystem expectations.
- WiFi works on generic SDM845 because the complete stack is aligned: kernel,
  DTB, firmware, QRTR, modem remoteproc, `rmtfs`, `pd-mapper`, `tqftpserv`, and
  ath10k WCN3990 firmware.
- Do not directly flash a generic or other-device SDM845 image to Razer Phone 2.
  Use those images as references unless a Razer-specific U-Boot and matching
  install plan are available.

## OnePlus 6 Dedicated Port / A-B Slot Flow

The OnePlus 6 dual booting and custom partitioning page describes several
boot models. The important one for this project is the A/B-slot-only path:

- A dedicated postmarketOS port can generate a normal `boot.img`.
- That `boot.img` can be booted directly by the stock Android bootloader.
- The page's OnePlus example flashes pmOS `boot.img` into slot B and erases
  `dtbo_b`.
- UEFI/U-Boot is optional and belongs to a separate boot model.

Project judgment:

- This supports the original Razer approach: a dedicated-device style
  Android-compatible `boot.img` plus rootfs is a valid pmOS-style path.
- It does not require U-Boot for WiFi.
- The OnePlus partition commands are not directly portable to Razer because the
  partition layout, slot usage, recovery options, and rollback path are
  device-specific.
- For Razer, keep using the repo-controlled boot/rootfs flow unless there is a
  separate reason to test U-Boot.

## SDM845 Modem and WiFi Stack

The SDM845 wiki describes WiFi as ath10k WCN3990. The modem is booted by the
Q6V5 MSS Peripheral Image Loader and is required for WiFi. Communication is
exposed through Qualcomm QRTR over GLINK/rpmsg style transports, with QMI on
top.

For functional SDM845 WiFi, postmarketOS notes identify these key userspace
pieces:

- `rmtfs`
- `pd-mapper`
- `tqftpserv`

The SDM845 wiki says these are installed in postmarketOS with:

```sh
apk add rmtfs pd-mapper tqftpserv
```

The MSM8998/SDM835-style WiFi notes also mention:

- `qrtr` / `qrtr-ns`
- `rmtfs`
- `pd-mapper`
- `tqftpserv`
- OEM `wlanmdsp.mbn` placed beside the modem firmware
- `modemuw.jsn` placed beside modem firmware
- WCN3990 `board-2.bin`
- WCN3990 `firmware-5.bin`
- `diag-router` as a diagnostic path when MSS remoteproc keeps crashing

Project judgment:

- For Razer SDM845 mainline, the primary path is WCN3990 with `ath10k_snoc`,
  not old WCNSS/Prima.
- A successful `rmtfs` open/read log does not fully prove that the RFS/NV layer
  is semantically correct. It only proves that the tested files were readable.
- If MSS reaches `modem running` and then crashes before WLFW/service 69
  appears, the problem is below NetworkManager and before normal ath10k WiFi
  interface creation.

## OnePlus WCN3990 DTS Reference

The upstream Linux OnePlus 6/6T common DTS enables the SDM845 WiFi node with
the same supply structure used by the current Razer DTS:

```dts
&wifi {
	status = "okay";
	vdd-0.8-cx-mx-supply = <&vreg_l5a_0p8>;
	vdd-1.8-xo-supply = <&vreg_l7a_1p8>;
	vdd-1.3-rfa-supply = <&vreg_l17a_1p3>;
	vdd-3.3-ch0-supply = <&vreg_l25a_3p3>;
	vdd-3.3-ch1-supply = <&vreg_l23a_3p3>;

	qcom,snoc-host-cap-8bit-quirk;
};
```

Local Razer status:

- `dts/sdm845-razer-aura.dts` already has these five WiFi supplies.
- `dts/sdm845-razer-aura.dts` already has
  `qcom,snoc-host-cap-8bit-quirk`.

Project judgment:

- Missing the OnePlus WiFi quirk is not the current blocker.
- The current blocker is more likely elsewhere in the modem/WLFW bring-up
  chain, such as MSS stability, firmware/service descriptor layout, RFS/NV
  semantics, PDR/PD mapper behavior, or a Razer-specific firmware/DT mismatch.

## WiFi Wiki General Guidance

The WiFi wiki gives broad guidance for many chips:

- Most phone WiFi chips require proprietary firmware blobs.
- postmarketOS prefers packaging firmware files instead of mounting Android's
  firmware partition at runtime.
- Debugging starts with checking whether `wlan0` appears in `ip link`.
- If there is no WiFi interface, inspect `dmesg` and firmware loading logs.
- Missing firmware or missing kernel config are common failure classes.

The Qualcomm WiFi section on that page describes older WCNSS-style devices:

- `wcnss.mdt`
- `wcnss.b00`, `wcnss.b01`, and related segments
- `WCNSS_cfg.dat`
- `WCNSS_qcom_cfg.ini`
- `WCNSS_qcom_wlan_nv.bin`
- `/dev/wcnss_wlan`
- `/sys/module/wlan/parameters/fwpath`

Project judgment:

- Those WCNSS instructions are not the main path for SDM845 WCN3990 on
  mainline Linux.
- Do not switch the Razer bring-up to `WCNSS_qcom_wlan_nv.bin` or
  `/dev/wcnss_wlan` unless the active kernel actually exposes a downstream
  WCNSS/Prima driver path.
- The useful transferable parts are the general firmware packaging rule and
  the debugging order: interface presence, kernel logs, firmware load failures,
  then kernel config.

## Device Package Notes

The Device Specific Package wiki says a postmarketOS device package normally
contains at least:

- `deviceinfo`
- `APKBUILD`

Modern device packages use `devicepkg-dev` helpers:

```sh
makedepends="devicepkg-dev"

build() {
	devicepkg_build $startdir $pkgname
}

package() {
	devicepkg_package $startdir $pkgname
}
```

Relevant packaging mechanisms:

- `install_if` can pull in optional subpackages or config files only when
  related packages are installed.
- Multiple kernel variants can be exposed with kernel subpackages.
- `modules-initfs` lists modules needed in initramfs.
- `initfs-hook.sh` can run device-specific commands during initramfs boot.
- Device-specific proprietary firmware should be packaged rather than fetched
  ad hoc at runtime.

Local pmaports observations from the workspace:

- `device/testing/device-qualcomm-sdm845/APKBUILD` depends on shared SDM845
  packages such as `soc-qcom-sdm845`, `soc-qcom-sdm845-nonfree-firmware`,
  `linux-firmware-qcom`, `linux-firmware-ath10k`,
  `linux-postmarketos-qcom-sdm845`, and `systemd-boot`.
- `device/testing/device-qualcomm-sdm845/deviceinfo` sets
  `deviceinfo_generate_systemd_boot="true"` and uses a FAT32 boot filesystem.
- The generic package has no fixed Razer DTB because U-Boot is expected to
  select a supported device DTB.

Project judgment:

- The generic SDM845 target is a packaging and boot architecture, not just one
  boot image.
- For Razer, the comparable work is to align our Ubuntu rootfs overlay with the
  SDM845 package/service/firmware expectations while keeping Razer DTS,
  firmware, and partition mapping.

## Firmware Wiki Notes

The Firmware wiki says firmware files are software loaded by Linux onto other
processors, such as WiFi, Bluetooth, modem, GPU, audio DSPs, and sensor DSPs.

Possible firmware sources:

- Official or unofficial LineageOS proprietary vendor repositories.
- Existing Android system/vendor filesystem locations such as
  `/vendor/firmware` or `/etc/firmware`.
- Mounted Android firmware partitions.
- OTA images.
- `NON-HLOS.bin`, often a FAT image that can be mounted read-only.

Firmware files of interest for Qualcomm phone bring-up include:

- `adsp.*`
- `mba.*`
- `modem.*`
- `wcnss.*` where applicable

Project judgment:

- For Razer SDM845 WCN3990, the important modem/WiFi files are expected to be
  device-specific modem firmware, `mba`, `wlanmdsp.mbn`, JSON service
  descriptors such as `modemuw.jsn`, and ath10k WCN3990 board/firmware files.
- Use factory firmware or known matching Razer firmware, not files from another
  phone, unless the file is known to be SoC-generic and the kernel/firmware
  package expects it that way.

## Razer Applicability Checklist

Use this checklist before changing boot images or rootfs:

- Does the active kernel have the SDM845 QRTR/remoteproc/PDR pieces expected by
  postmarketOS?
- Does the Razer DTS point MSS and ath10k to the intended firmware names?
- Does the rootfs contain Razer-specific `mba`, modem, `wlanmdsp.mbn`, and JSON
  files in the paths the kernel and `tqftpserv` expect?
- Does the rootfs contain WCN3990 `firmware-5.bin` and `board-2.bin`?
- Are `rmtfs`, `pd-mapper`, and `tqftpserv` installed and ordered like the
  postmarketOS reference?
- Does QRTR ever expose WLFW/service 69?
- Does `ath10k_snoc` probe after MSS is stable?
- If MSS still crashes before WLFW, collect crash evidence before another DTS
  or rootfs guess.

## Current Working Rule

Use postmarketOS as a reference implementation, not as a blind replacement.
For Razer Phone 2, preserve the current Razer DTS, Razer firmware, Razer
partition mapping, Helix/SSH rootfs work, and only port specific differences
that are verified from the reference image or pmaports package metadata.
