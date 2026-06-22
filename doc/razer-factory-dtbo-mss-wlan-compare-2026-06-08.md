# Razer Factory DTBO / Boot DTB MSS WLAN Compare - 2026-06-08

## Reason

This note answers a specific gap in the WiFi/MSS debugging thread: whether the
Razer factory `dtbo.img` / boot DTB had been used to verify the MSS and WLAN
memory layout.

Short answer: older notes did contain a factory boot-DTB comparison, but the
current WiFi/config round did not rebuild a clear, auditable comparison report.
This file records the fresh local check.

## Sources

- Factory package:
  `aura-p-release-3201-user-full/aura-p-release-3201/`
- Factory extracted DTBs already present locally:
  `.tmp/android-stock-extract/dtbs/boot-dtb0.dtb`
  `.tmp/android-stock-extract/dtbs/dtbo0.dtb` ... `dtbo5.dtb`
- Factory decompiled DTS:
  `.tmp/android-stock-extract/dts/boot-dtb0.dts`
  `.tmp/android-stock-extract/dts/dtbo0.dts` ... `dtbo5.dts`
- Current built mainline DTB:
  `output/sdm845-razer-aura.dtb`
- Current decompiled mainline DTS generated for this check:
  `.tmp/current-output-sdm845-razer-aura.dts`

Commands used:

```bash
dtc -I dtb -O dts -o .tmp/current-output-sdm845-razer-aura.dts \
  output/sdm845-razer-aura.dtb

fdtget -t x output/sdm845-razer-aura.dtb / qcom,msm-id
fdtget -t x output/sdm845-razer-aura.dtb / qcom,board-id
fdtget -t x .tmp/android-stock-extract/dtbs/boot-dtb0.dtb / qcom,msm-id
fdtget -t x .tmp/android-stock-extract/dtbs/boot-dtb0.dtb / qcom,board-id
```

## DTBO Scope

The factory `dtbo.img` entries were checked first because they are the device
specific Android overlays.

All six factory DTBO entries report:

```text
qcom,msm-id   = <0x141 0x20000>
qcom,board-id = <0x08 0x00>
```

The factory boot base DTB and the current mainline DTB both report:

```text
qcom,msm-id   = <0x141 0x20000>
qcom,board-id = <0x00 0x00>
```

Searches through `dtbo0.dts` ... `dtbo5.dts` did not find these core nodes:

```text
qcom,mss@4080000
qcom,icnss@18800000
wlan_fw_region
modem_region
mba_region
qcom,ipa@01e00000
qcom,rmtfs_sharedmem@0
```

The factory DTBO does include board overlay material such as panel, PMIC, and a
Bluetooth WCN3990 overlay fragment. It does not appear to be where the MSS/WLAN
carveout and modem remoteproc layout are defined. Those are in the factory boot
base DTB.

## Reserved Memory

The important MSS/WLAN carveouts match between factory boot DTB and current
mainline output DTB:

| Region | Factory boot DTB | Current mainline DTB | Result |
| --- | --- | --- | --- |
| WLAN MSA | `wlan_fw_region@0x8df00000`, size `0x100000` | `wlan-msa@8df00000`, size `0x100000` | Match |
| MPSS modem | `modem_region@0x8e000000`, size `0x7800000` | `mpss@8e000000`, size `0x7800000` | Match |
| MBA | `mba_region@0x96500000`, size `0x200000` | `mba@96500000`, size `0x200000` | Match |

Fresh `fdtget` output:

```text
current /reserved-memory/wlan-msa@8df00000  0 8df00000 0 100000
current /reserved-memory/mpss@8e000000      0 8e000000 0 7800000
current /reserved-memory/mba@96500000       0 96500000 0 200000

factory /reserved-memory/wlan_fw_region@0x8df00000  0 8df00000 0 100000
factory /reserved-memory/modem_region@0x8e000000    0 8e000000 0 7800000
factory /reserved-memory/mba_region@0x96500000      0 96500000 0 200000
```

Conclusion: the generic theory that the WLAN MSA / MPSS / MBA memory base or
size is simply missing or wrong does not fit the current evidence.

## RMTFS Memory

Current mainline DTS explicitly overrides `rmtfs_mem`:

```text
/reserved-memory/rmtfs-mem@88f00000
reg = <0x0 0x88f00000 0x0 0x202000>
compatible = "qcom,rmtfs-mem"
qcom,client-id = <1>
qcom,vmid = <QCOM_SCM_VMID_MSS_MSA>
qcom,use-guard-pages
```

Factory downstream boot DTB has:

```text
/soc/qcom,rmtfs_sharedmem@0
compatible = "qcom,sharedmem-uio"
reg = <0x0 0x200000>
qcom,client-id = <1>
qcom,guard-memory
```

This is not represented in the same binding style. The mainline version uses
the SDM845 `qcom,rmtfs-mem` reserved-memory binding with guard pages.

## MSS Remoteproc Difference

The larger difference is not the reserved-memory address. It is the remoteproc
binding and sequencing model.

Factory boot DTB node:

```text
/soc/qcom,mss@4080000
compatible = "qcom,pil-q6v55-mss"
reg-names = "qdsp6_base", "halt_q6", "halt_modem", "halt_nc", "rmb_base",
            "restart_reg", "pdc_sync", "alt_reset"
qcom,firmware-name = "modem"
qcom,pil-self-auth
qcom,sysmon-id = <0>
qcom,minidump-id = <3>
qcom,ssctl-instance-id = <0x12>
qcom,override-acc
qcom,signal-aop
qcom,qdsp6v65-1-0
qcom,mss_pdc_offset = <0x09>
memory-region = <modem_region>
qcom,mem-protect-id = <0x0f>
qcom,gpio-err-fatal / ready / stop-ack / shutdown-ack / force-stop
mboxes = <...>
mbox-names = "mss-pil"
child qcom,mba-mem@0 -> mba_region
```

Current mainline output DTB node:

```text
/soc@0/remoteproc@4080000
compatible = "qcom,sdm845-mss-pil"
reg-names = "qdsp6", "rmb"
interrupt-names = "wdog", "fatal", "ready", "handover", "stop-ack",
                  "shutdown-ack"
qcom,qmp = <...>
qcom,smem-states = <...>
qcom,smem-state-names = "stop"
resets = <mss_restart>, <pdc_reset>
reset-names = "mss_restart", "pdc_reset"
qcom,halt-regs = <...>
power-domain-names = "cx", "mx", "mss"
firmware-name = "qcom/sdm845/Razer/aura/mba.mbn",
                "qcom/sdm845/Razer/aura/modem.mbn"
child mba -> mba region
child mpss -> mpss region
child metadata -> mpss-metadata
glink-edge label = "modem"
```

Important interpretation:

- These are different kernel driver families: downstream PIL vs mainline
  remoteproc.
- Some downstream properties cannot be copied directly because the mainline
  driver will ignore properties it does not implement.
- But this difference supports the stronger current lead: a Razer-specific
  MSS reset / PDC / AOP / handover sequencing issue is more credible than a
  missing WLAN memory carveout.

## WLAN / ICNSS Difference

Factory boot DTB uses downstream ICNSS:

```text
/soc/qcom,icnss@18800000
compatible = "qcom,icnss"
reg = <0x18800000 0x800000 0xa0000000 0x10000000 0xb0000000 0x10000>
reg-names = "membase", "smmu_iova_base", "smmu_iova_ipa"
iommus = <apps_smmu 0x40 0x01>
qcom,wlan-msa-memory = <0x100000>
qcom,gpio-force-fatal-error = <...>
qcom,gpio-early-crash-ind = <...>
vdd-0.8-cx-mx-supply
vdd-1.8-xo-supply
vdd-1.3-rfa-supply
vdd-3.3-ch0-supply
qcom,vdd-0.8-cx-mx-config
qcom,vdd-3.3-ch0-config
```

Current mainline output DTB uses ath10k SNOC:

```text
/soc@0/wifi@18800000
compatible = "qcom,wcn3990-wifi"
reg = <0x0 0x18800000 0x0 0x800000>
memory-region = <wlan-msa>
iommus = <apps_smmu 0x40 0x01>
vdd-0.8-cx-mx-supply
vdd-1.8-xo-supply
vdd-1.3-rfa-supply
vdd-3.3-ch0-supply
vdd-3.3-ch1-supply
qcom,calibration-variant = "razer_aura"
qcom,snoc-host-cap-8bit-quirk
```

Mainline note:

- The current property name `qcom,calibration-variant` is suspicious for
  ath10k SNOC board-2 matching. The upstream-style property is
  `qcom,ath10k-calibration-variant`.
- This is still unlikely to explain the current MSS fatal, because the modem
  fails before WLFW / ath10k board-data selection becomes visible.

## IPA Difference

Factory downstream IPA is a full downstream `qcom,ipa` binding with explicit
IPA SMMU WLAN context:

```text
/soc/qcom,ipa@01e00000
qcom,ipa-wdi2
qcom,arm-smmu
qcom,smmu-fast-map
ipa_smmu_wlan:
  iommus = <apps_smmu 0x721 0>
```

Current mainline uses:

```text
/soc@0/ipa@1e40000
compatible = "qcom,sdm845-ipa"
iommus = <apps_smmu 0x720 0>, <apps_smmu 0x722 0>
firmware-name = "qcom/sdm845/Razer/aura/ipa_fws.mbn"
```

This remains a possible interaction point because the observed crash happens
after IPA receives the modem-running event. However, a previous no-IPA test did
not prove IPA was the sole cause.

## Engineering Conclusion

The factory DTB comparison changes the debugging priority:

1. Do not spend more cycles guessing new `wlan_msa`, `mpss`, or `mba` addresses
   unless a new Razer source contradicts this report. They match factory.
2. Do not assume `dtbo.img` itself carries the MSS/WLAN memory layout. For this
   factory image, the relevant core nodes are in the boot base DTB.
3. Focus on the boundary that still differs:
   - downstream MSS reset/PDC/AOP/SSCTL/minidump properties vs mainline
     `qcom,sdm845-mss-pil`;
   - downstream ICNSS vs mainline ath10k SNOC binding;
   - downstream IPA SMMU/WDI behavior vs mainline IPA;
   - getting a real MSS crash reason via remoteproc/minidump/DIAG instead of
     changing firmware mapping blindly.

The next DTS change should be justified by one of these factory-delta items or
by concrete crash evidence, not by another generic SDM845 memory-carveout guess.
