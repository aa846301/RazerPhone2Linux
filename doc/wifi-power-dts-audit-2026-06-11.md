# WiFi / MSS / Power DTS Audit - 2026-06-11

This audit exists because the Razer Phone 2 WiFi/MSS work has accumulated too
many mixed assumptions from three different DTS models:

- Razer factory Android downstream DTB.
- OnePlus 6 factory Android downstream DTB.
- Mainline/postmarketOS SDM845 DTS style.

The goal is to separate evidence from guesses before changing DTS again.

## Sources Used

Local files inspected:

- Razer current mainline DTS: `dts/sdm845-razer-aura.dts`
- Mainline SDM845 base DTSI copy: `doc/sdm845.dtsi`
- Mainline OnePlus common DTSI copy: `doc/sdm845-oneplus-common.dtsi`
- Mainline Xiaomi/Poco SDM845 reference: `doc/sdm845-xiaomi-beryllium-common.dtsi`
- Razer factory Android DTB decompile:
  `output/reserved-memory-compare/android-base-00.dtb.dts`
- OnePlus 6 Android 11.1.2.2 factory boot DTB decompile:
  `output/op6-android-11.1.2.2/boot-dtbs/boot-dtb-00.dts`
- Existing project notes:
  `doc/postmarketos-sdm845-wifi-reference-2026-06-02.md`
  `doc/pmos-oneplus-and-contrast-2026-06-02.md`
  `doc/op6-android-rmtfs-dtb-comparison-2026-06-10.md`
  `doc/reserved-memory-comparison-2026-06-10.md`
  `doc/factory-mss-mdss-power-reset-audit-2026-06-09.md`

No new postmarketOS web page was assumed to be readable for this audit. The
pmOS knowledge here comes from user-pasted/source-recorded local docs and local
reference files.

## Current Failure Boundary

The current evidence says:

```text
rmtfs/RFS paths open and initial reads succeed
PDM/QMI tms/pddump_disabled lookup succeeds in diagnostic builds
MSS reaches "remote processor 4080000.remoteproc is now up"
MSS fatal happens before WLFW/service 69 appears
No wlanmdsp.mbn TFTP request
No /sys/class/ieee80211 and no wlan0
```

So the immediate blocker is still MSS fatal after MPSS is running and before
WLFW/wlan_pd exposure. It is not NetworkManager and not normal ath10k AP
connection setup.

## WiFi Node Comparison

### Factory Android Downstream

Razer factory Android and OnePlus factory Android both use downstream ICNSS:

```dts
qcom,icnss@18800000 {
    compatible = "qcom,icnss";
    reg = <0x18800000 0x800000 0xa0000000 0x10000000 0xb0000000 0x10000>;
    reg-names = "membase", "smmu_iova_base", "smmu_iova_ipa";
    iommus = <apps_smmu 0x40 0x1>;
    qcom,wlan-msa-memory = <0x100000>;
    vdd-0.8-cx-mx-supply = <pm8998_l5>;
    vdd-1.8-xo-supply = <pm8998_l7>;
    vdd-1.3-rfa-supply = <pm8998_l17>;
    vdd-3.3-ch0-supply = <pm8998_l25>;
    qcom,vdd-0.8-cx-mx-config = <800000 800000>;
    qcom,vdd-3.3-ch0-config = <3104000 3312000>;
};
```

Razer factory:

- `vdd-0.8-cx-mx-supply = <0xeb>` -> `pm8998_l5`, 800000 uV.
- `vdd-1.8-xo-supply = <0xec>` -> `pm8998_l7`, 1800000 uV.
- `vdd-1.3-rfa-supply = <0xed>` -> `pm8998_l17`, 1304000 uV.
- `vdd-3.3-ch0-supply = <0xee>` -> `pm8998_l25`, 3000000..3312000 uV.

OnePlus factory:

- `vdd-0.8-cx-mx-supply = <0xe9>` -> `pm8998_l5`, 800000 uV.
- `vdd-1.8-xo-supply = <0xea>` -> `pm8998_l7`, 1800000 uV.
- `vdd-1.3-rfa-supply = <0xeb>` -> `pm8998_l17`, 1304000 uV.
- `vdd-3.3-ch0-supply = <0xec>` -> `pm8998_l25`, 3000000..3312000 uV.
- OnePlus additionally has `qcom,smmu-s1-bypass` in the downstream ICNSS node.

Important: neither inspected factory Android WiFi node has a static
`vdd-3.3-ch1-supply`.

### Mainline SDM845 Base

Mainline base `doc/sdm845.dtsi` defines:

```dts
wifi: wifi@18800000 {
    compatible = "qcom,wcn3990-wifi";
    status = "disabled";
    reg = <0 0x18800000 0 0x800000>;
    reg-names = "membase";
    memory-region = <&wlan_msa_mem>;
    clock-names = "cxo_ref_clk_pin";
    clocks = <&rpmhcc RPMH_RF_CLK2>;
    interrupts = <GIC_SPI 414..425 IRQ_TYPE_LEVEL_HIGH>;
    iommus = <&apps_smmu 0x0040 0x1>;
};
```

This is a different driver model from downstream `qcom,icnss`; copying the
downstream node directly would be wrong.

### Mainline OnePlus / pmOS-Style Reference

Mainline OnePlus enables the node as:

```dts
&wifi {
    status = "okay";
    vdd-0.8-cx-mx-supply = <&vreg_l5a_0p8>;
    vdd-1.8-xo-supply = <&vreg_l7a_1p8>;
    vdd-1.3-rfa-supply = <&vreg_l17a_1p3>;
    vdd-3.3-ch0-supply = <&vreg_l25a_3p3>;
    vdd-3.3-ch1-supply = <&vreg_l23a_3p3>;
    qcom,snoc-host-cap-8bit-quirk;
    qcom,ath10k-calibration-variant = "oneplus_sdm845";
};
```

Xiaomi/Poco mainline follows the same supply shape and uses:

```dts
qcom,ath10k-calibration-variant = "xiaomi_beryllium";
```

### Current Razer Mainline DTS

Current `dts/sdm845-razer-aura.dts` has:

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

Assessment:

- L5/L7/L17/L25 match both Razer factory and OnePlus factory semantics.
- L23/ch1 is copied from mainline OnePlus/Poco style, not from Razer factory
  Android text. It may be correct for mainline WCN3990 binding, but it should
  be recorded as a mainline-porting choice, not factory evidence.
- `qcom,snoc-host-cap-8bit-quirk` is a known mainline SDM845 WiFi quirk used by
  OnePlus/Poco. It is not present in factory downstream because that is a
  different ICNSS driver.
- `qcom,calibration-variant` is suspicious. Upstream DTS examples use
  `qcom,ath10k-calibration-variant`. Some local diagnostics noted patched
  driver fallback support, but upstream/mainline-clean DTS should prefer the
  upstream property name. This is not the current MSS fatal cause because WLFW
  never appears, but it is a real cleanup item before final WiFi validation.

## MSS / Remoteproc Node Comparison

### Factory Android Downstream MSS

Both Razer and OnePlus factory Android use:

```dts
qcom,mss@4080000 {
    compatible = "qcom,pil-q6v55-mss";
    reg-names = "qdsp6_base", "halt_q6", "halt_modem", "halt_nc",
                "rmb_base", "restart_reg", "pdc_sync", "alt_reset";
    clock-names = "xo", "iface_clk", "bus_clk", "mem_clk",
                  "gpll0_mss_clk", "snoc_axi_clk", "mnoc_axi_clk",
                  "prng_clk";
    qcom,proxy-clock-names = "xo", "prng_clk";
    qcom,active-clock-names = "iface_clk", "bus_clk", "mem_clk",
                              "gpll0_mss_clk", "snoc_axi_clk",
                              "mnoc_axi_clk";
    vdd_cx-supply;
    vdd_mx-supply;
    vdd_mss-supply;
    qcom,pil-self-auth;
    qcom,sysmon-id = <0>;
    qcom,minidump-id = <3>;
    qcom,ssctl-instance-id = <0x12>;
    qcom,override-acc;
    qcom,signal-aop;
    qcom,qdsp6v65-1-0;
    memory-region = <modem_region>;
    qcom,mem-protect-id = <0x0f>;
    qcom,gpio-err-fatal;
    qcom,gpio-err-ready;
    qcom,gpio-proxy-unvote;
    qcom,gpio-stop-ack;
    qcom,gpio-shutdown-ack;
    qcom,gpio-force-stop;
};
```

Differences between the two inspected factory nodes:

| Property | Razer factory | OnePlus factory |
|---|---:|---:|
| `qcom,mss_pdc_offset` | `0x09` | `0x08` |
| `qcom,sequential-fw-load` | absent | present |
| MBA memory phandle | Razer-specific | OnePlus-specific |
| GPIO phandles | Razer-specific | OnePlus-specific |
| Regulator phandles | Razer-specific | OnePlus-specific |

This is enough to say: OnePlus factory MSS cannot be blindly copied over Razer.

### Mainline SDM845 MSS

Mainline base `doc/sdm845.dtsi` defines:

```dts
mss_pil: remoteproc@4080000 {
    compatible = "qcom,sdm845-mss-pil";
    reg = <0 0x04080000 0 0x408>, <0 0x04180000 0 0x48>;
    reg-names = "qdsp6", "rmb";
    interrupts-extended = wdog, fatal, ready, handover, stop-ack, shutdown-ack;
    clock-names = "iface", "bus", "mem", "gpll0_mss",
                  "snoc_axi", "mnoc_axi", "prng", "xo";
    qcom,qmp = <&aoss_qmp>;
    resets = <&aoss_reset AOSS_CC_MSS_RESTART>,
             <&pdc_reset PDC_MODEM_SYNC_RESET>;
    reset-names = "mss_restart", "pdc_reset";
    qcom,halt-regs = <&tcsr_regs_1 0x3000 0x5000 0x4000>;
    power-domain-names = "cx", "mx", "mss";
    mba { memory-region = <&mba_region>; };
    mpss { memory-region = <&mpss_region>; };
    metadata { memory-region = <&mdata_mem>; };
    glink-edge {
        interrupts = <GIC_SPI 449 IRQ_TYPE_EDGE_RISING>;
        label = "modem";
        qcom,remote-pid = <1>;
        mboxes = <&apss_shared 12>;
    };
};
```

Mainline OnePlus only overrides status and firmware names:

```dts
&mss_pil {
    status = "okay";
    firmware-name = "qcom/sdm845/oneplus6/mba.mbn",
                    "qcom/sdm845/oneplus6/modem.mbn";
};
```

Current Razer mirrors that shape with Razer firmware names:

```dts
&mss_pil {
    status = "okay";
    firmware-name = "qcom/sdm845/Razer/aura/mba.mbn",
                    "qcom/sdm845/Razer/aura/modem.mbn";
};
```

Assessment:

- Mainline does not encode downstream-only properties like
  `qcom,override-acc`, `qcom,signal-aop`, `qcom,qdsp6v65-1-0`,
  `qcom,ssctl-instance-id`, or `qcom,minidump-id` as DTS properties.
- Some downstream semantics are represented in mainline by driver data and
  standard bindings: AOSS QMP `load_state`, PDC reset, RMB alt reset,
  halt-regs, CX/MX/MSS power domains, SMP2P interrupts, and GLINK edge.
- Therefore the useful question is not "which downstream property can be pasted
  into DTS". The useful question is whether mainline `qcom_q6v5_mss` implements
  the Razer-specific downstream behavior behind those properties.
- The Razer-vs-OnePlus `qcom,mss_pdc_offset` difference is important. Razer
  factory says `0x09`; OnePlus factory says `0x08`. Any driver-level reset/PDC
  assumption must be checked against Razer, not OnePlus.
- The previous "MSS glink-edge lacks channel child nodes" theory should not be
  treated as root cause. Mainline SDM845 modem glink edges are normally bare;
  IPCRTR is dynamically created by the remote side and `rpmsg:IPCRTR`.

## Reserved Memory Comparison

### Mainline SDM845 Base

Relevant base carveouts:

| Node | Address | Size |
|---|---:|---:|
| `rmtfs@88f00000` | `0x88f00000` | `0x200000` |
| `wlan-msa@8df00000` | `0x8df00000` | `0x100000` |
| `mpss@8e000000` | `0x8e000000` | `0x7800000` |
| `mba@96500000` | `0x96500000` | `0x200000` |

### Razer Factory / Current Mainline Critical Carveouts

Existing comparison docs already established that Razer factory and current
mainline agree on the critical firmware carveouts:

| Region | Address | Size |
|---|---:|---:|
| ADSP | `0x8c500000` | `0x1a00000` |
| WLAN MSA | `0x8df00000` | `0x100000` |
| MPSS | `0x8e000000` | `0x7800000` |
| CDSP | `0x95d00000` | `0x800000` |
| MBA | `0x96500000` | `0x200000` |
| SLPI | `0x96700000` | `0x1400000` |

So WLAN MSA / MPSS / MBA base-size mismatch is currently low probability.

### RMTFS

Factory Android downstream Razer and OnePlus both describe dynamic sharedmem:

```dts
qcom,rmtfs_sharedmem@0 {
    compatible = "qcom,sharedmem-uio";
    reg = <0x0 0x200000>;
    reg-names = "rmtfs";
    qcom,client-id = <1>;
    qcom,guard-memory;
};
```

That node does not provide a physical address.

Mainline OnePlus converts the dynamic downstream allocation into:

```dts
rmtfs-mem@f5b00000 {
    compatible = "qcom,rmtfs-mem";
    reg = <0 0xf5b00000 0 0x202000>;
    qcom,client-id = <1>;
    qcom,vmid = <QCOM_SCM_VMID_MSS_MSA>;
    qcom,use-guard-pages;
};

removed-region@88f00000 {
    reg = <0 0x88f00000 0 0x1c00000>;
    no-map;
};
```

Current Razer source now follows this OnePlus-style contrast pattern.

Assessment:

- `0xf5b00000` is not Razer factory evidence. It is a OnePlus mainline porting
  decision used as a controlled contrast.
- The latest QMI dump proved this high rmtfs mapping can serve early RFS reads,
  but it did not fix MSS fatal.
- Therefore rmtfs address guessing should stop unless new evidence shows an
  RFS allocation/access failure.

## What Looks Guessed Or Not Yet Proven

| Current item | Status | Why it matters |
|---|---|---|
| `rmtfs-mem@f5b00000` on Razer | Controlled OnePlus contrast, not Razer factory proof | It works for early RFS reads but did not move the MSS fatal boundary. |
| `removed-region@88f00000/0x1c00000` | Mainline OnePlus/Samsung-style safety reserve | Reasonable contrast, but not directly from Razer factory DTB. |
| WiFi `vdd-3.3-ch1-supply = <&vreg_l23a_3p3>` | Mainline OnePlus/Poco pattern, not factory ICNSS text | Probably required/accepted by mainline WCN3990, but should not be described as factory-derived. |
| `qcom,calibration-variant = "razer_aura"` | Non-upstream property name for DTS | Use `qcom,ath10k-calibration-variant` for mainline-clean DTS unless a local driver patch intentionally supports both. |
| Copying downstream MSS properties into DTS | Not useful by itself | Mainline ignores unsupported downstream properties unless driver code implements them. |
| Missing modem `glink-edge` child nodes | Rejected as root cause | Mainline modem GLINK/IPCRTR normally uses a bare edge. |

## Evidence-Driven Next DTS Work

Do not rebuild yet just because this file exists. The smallest useful DTS
cleanup sequence should be:

1. Fix the ath10k board-data property name:

   ```dts
   qcom,ath10k-calibration-variant = "razer_aura";
   ```

   This is hygiene for after WLFW appears; it is not expected to fix the MSS
   fatal before WLFW.

2. Keep L5/L7/L17/L25 WiFi supplies as-is. They match factory semantics.

3. Treat L23/ch1 as a mainline WCN3990 binding choice. Do not remove it unless
   comparing against binding/driver evidence or a controlled boot.

4. Stop changing rmtfs base addresses as a standalone fix. The QMI/RFS evidence
   now says early rmtfs is functional enough to reach the same fatal boundary.

5. For the MSS fatal, compare driver behavior rather than DTS text:

   - Razer factory downstream `mss_pdc_offset = 0x09` vs OnePlus `0x08`.
   - Downstream `qcom,override-acc` behavior vs mainline SDM845 reset path.
   - Downstream proxy-clock/proxy-unvote semantics vs mainline handover.
   - Downstream SSCTL/minidump support vs mainline diagnostic visibility.

6. If a DTS change is still needed after driver audit, it should be a single
   variable boot-only artifact, not a combined rmtfs/WiFi/MSS rewrite.

## Working Model After This Audit

The most likely current class is not "WiFi supplies absent" and not "copy
OnePlus DTS". The remaining high-value class is:

```text
Razer MPSS starts successfully
MPSS completes early RFS / root service startup
MPSS touches a Razer-specific modem/WLAN/IPA/power/reset path before WLFW
mainline Razer DTS/driver sequencing does not match what the factory downstream
PIL/ICNSS stack provided
MSS fatal occurs before the modem can expose WLFW or write an SSR reason
```

That points the next work toward a Razer-vs-mainline MSS driver sequencing
audit, using the factory DTS as evidence, not toward more broad DTS guessing.
