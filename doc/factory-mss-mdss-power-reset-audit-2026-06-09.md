# Razer Factory MSS/MDSS Power and Reset Audit - 2026-06-09

## Question

Could the short MSS fatal window be caused by MPSS executing into a hardware
initialization path where a required rail, clock, reset, AOP/PDC handshake, or
bus path is not available?

Current answer: yes, this is more plausible than the earlier theory that the
mainline MSS `glink-edge` is missing static channel child nodes.

The mainline SDM845, MSM8998, SC7280, and SM8450 modem `glink-edge` nodes are
normally bare edges with `label`, `qcom,remote-pid`, interrupt, and mailbox.
The IPCRTR channel is created dynamically by the remote processor and matched
by the `rpmsg:IPCRTR` driver. Missing `apr` or `fastrpc` child nodes under the
modem edge is therefore not evidence of a broken modem QRTR path.

## Evidence Boundary

Observed working pieces:

- MBA loads and hands off to MPSS.
- RMB status reaches `0x0b`, so the basic MSS boot FSM completes.
- IPCRTR/QRTR probes on the modem glink edge.
- rmtfs opens all expected RFS paths and completes early reads.
- PDM receives `tms/pddump_disabled` lookup from modem node 0 and returns the
  mapped domain in the current diagnostic kernel.

Observed failure:

- MSS fatal happens after MPSS is running and before WLFW/wlan_pd appears.
- No `wlan/fw`, `kernel/elf_loader`, `wlanmdsp.mbn` TFTP request, WLFW service,
  `/sys/class/ieee80211`, or `wlan0`.
- SMEM SSR reason is absent and MPSS memory is XPU-protected at fatal time.

This makes an MPSS runtime hardware access, power vote, reset handover, or
downstream sequencing delta a credible remaining class.

## Factory MSS Node: Relevant Hardware Controls

Factory boot DTB path: `/soc/qcom,mss@4080000`.

Relevant factory properties:

```text
compatible = "qcom,pil-q6v55-mss"
reg-names = "qdsp6_base", "halt_q6", "halt_modem", "halt_nc",
            "rmb_base", "restart_reg", "pdc_sync", "alt_reset"
clocks = xo, iface_clk, bus_clk, mem_clk, gpll0_mss_clk,
         snoc_axi_clk, mnoc_axi_clk, prng_clk
qcom,proxy-clock-names = "xo", "prng_clk"
qcom,active-clock-names = iface/bus/mem/gpll0/snoc/mnoc
vdd_cx-supply
vdd_cx-voltage
vdd_mx-supply
vdd_mx-uV
vdd_mss-supply
vdd_mss-uV
qcom,pil-self-auth
qcom,sysmon-id = <0>
qcom,minidump-id = <3>
qcom,ssctl-instance-id = <0x12>
qcom,override-acc
qcom,signal-aop
qcom,qdsp6v65-1-0
qcom,mss_pdc_offset = <0x09>
memory-region = modem_region
qcom,mem-protect-id = <0x0f>
qcom,gpio-err-fatal
qcom,gpio-err-ready
qcom,gpio-proxy-unvote
qcom,gpio-stop-ack
qcom,gpio-shutdown-ack
qcom,gpio-force-stop
mboxes / mbox-names = "mss-pil"
qcom,mba-mem@0 -> mba_region
```

Current mainline model represents only part of this directly:

```text
compatible = "qcom,sdm845-mss-pil"
reg-names = "qdsp6", "rmb"
clocks / clock-names include the common MSS clocks
qcom,qmp = aoss_qmp
resets = mss_restart, pdc_reset
reset-names = "mss_restart", "pdc_reset"
qcom,halt-regs
power-domain-names = "cx", "mx", "mss"
qcom,smem-states = stop
mba/mpss/metadata memory regions
glink-edge label = "modem"
```

Interpretation:

- The factory node clearly contains extra downstream sequencing state around
  PDC sync, alternate reset, ACC override, AOP signalling, proxy clocks, proxy
  unvote GPIO, SSCTL, and minidump.
- Mainline already has equivalents for some of these, such as AOSS QMP
  `load_state`, PDC reset bit 9, RMB alt reset handling, halt registers, and
  CX/MX/MSS power domains.
- The likely bug class is therefore not "copy all downstream qcom properties".
  Mainline will ignore unsupported properties. The useful work is to identify
  which downstream behavior is not implemented or is sequenced differently in
  `qcom_q6v5_mss`.

## Factory WLAN / ICNSS Node: Relevant Hardware Controls

Factory boot DTB uses downstream ICNSS for WCN3990:

```text
/soc/qcom,icnss@18800000
compatible = "qcom,icnss"
reg-names = "membase", "smmu_iova_base", "smmu_iova_ipa"
iommus = apps_smmu SID 0x40
qcom,wlan-msa-memory = <0x100000>
qcom,gpio-force-fatal-error
qcom,gpio-early-crash-ind
vdd-0.8-cx-mx-supply
vdd-1.8-xo-supply
vdd-1.3-rfa-supply
vdd-3.3-ch0-supply
qcom,vdd-0.8-cx-mx-config
qcom,vdd-3.3-ch0-config
```

Current mainline WCN3990 node uses:

```text
compatible = "qcom,wcn3990-wifi"
memory-region = wlan-msa
iommus = apps_smmu SID 0x40
vdd-0.8-cx-mx-supply
vdd-1.8-xo-supply
vdd-1.3-rfa-supply
vdd-3.3-ch0-supply
vdd-3.3-ch1-supply
qcom,snoc-host-cap-8bit-quirk
```

Interpretation:

- WLAN MSA base/size matches factory.
- WiFi rails are mostly represented, but downstream ICNSS also has explicit
  regulator load/config values and crash indication GPIOs.
- Because the current fatal happens before WLFW or `wlanmdsp.mbn` request, the
  WLAN node is a secondary suspect. It becomes primary only if the modem is
  already touching WCN3990 power/IPA/WLAN hardware before exposing WLFW.

## Factory MDSS Node: Relevance

Factory MDSS has extensive SDE/DSI/DP clock, GDSC, bus, regulator, and QoS
configuration. This matters for display bring-up and could explain display
handoff/black-screen behavior.

It is less likely to be the direct cause of the MSS/WiFi fatal because the
current crash boundary is inside modem root_pd before WLAN service exposure.
There is no evidence yet that MPSS requires MDSS/DSI to be powered during WiFi
startup.

## Current Probability Ranking

Higher-probability remaining causes:

1. MSS reset/PDC/AOP/ACC sequencing delta between downstream PIL and mainline
   `qcom_q6v5_mss`.
2. A modem runtime hardware access that expects a bus, clock, power vote, or
   peripheral state not represented by the current mainline Razer DTS.
3. WLAN/ICNSS regulator-load or crash-GPIO semantic difference that matters
   before WLFW is exposed.
4. IPA/WLAN SMMU or IPA WDI setup mismatch, though IPA-off testing already
   reduced this likelihood.

Lower-probability causes:

- Missing modem `glink-edge` child nodes.
- Basic RFS path/open/read failure.
- Wrong WLAN/MSA/MPSS/MBA reserved-memory base or size.
- Missing ath10k board data as the immediate fatal trigger.

## Next Controlled Test Direction

Do not add a broad downstream property dump to DTS. Instead:

1. Audit mainline `qcom_q6v5_mss` against factory MSS controls:
   PDC sync, alt reset, ACC override, AOP load-state, proxy clocks, proxy
   unvote, SSCTL/minidump, and stop/shutdown handover.
2. Instrument `qcom_glink_native` only to timestamp channel/intent timeouts
   relative to fatal, so glink timeout can be classified as cause or aftermath.
3. Add a narrow MSS sequencing experiment only if the audited downstream
   behavior has a mainline code location and a single variable can be tested.
4. Keep WiFi rail/regulator-load experiments separate from MSS reset
   experiments, because mixing them will make the result uninterpretable.
