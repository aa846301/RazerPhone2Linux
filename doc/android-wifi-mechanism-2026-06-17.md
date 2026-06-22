# Android WiFi/MSS Working Mechanism — captured 2026-06-17 (CLAUDE.md §5 B 方向)

Device flashed back to **stock Android** (`aura 3201`, P-SMR6-RC001-RZR-201022,
**user build, NOT rooted**) and captured over `adb` to obtain the *working*
WiFi / modem bring-up mechanism for diff against the failing mainline-Linux MSS
bring-up (root cause boundary in `doc/wifi-mss-status-2026-05-21.md` / `CLAUDE.md` §2).

## Capture method / limits

- Reproducible script: `scripts/capture-android-wifi-mechanism.sh`.
- No root (`uid=2000 shell`, `ro.build.type=user`, no `su`). SELinux denied
  `adb pull` of `/sys/firmware/fdt`, `/vendor/firmware_mnt/image`,
  `/vendor/firmware/wlan`. The §5 root-only items (strace `rmt_storage`,
  `/dev/diag` modem F3) are **not** obtainable on this stock build.
- The kernel ring buffer **did** retain from t=0, so the full healthy modem +
  WLAN bring-up was recovered from **`adb bugreport` → KERNEL LOG (dmesg)**.

## Artifacts (`output/android-wifi-mechanism-20260617-101416/`)

```
08-bugreport.zip                b01734b3e6ec14b510207598f0d6dec46854a112d58439d443f107b93fe8560c
11-android-dmesg.txt            a44334b2eeff2cb857a99012ea0a4aad45b6a066ac92214e9480a19cf7026558
vendor-etc-wifi/WCNSS_qcom_cfg.ini  abd86dd72d7dd65afc1bf78d255d08f96017d575bf1cc20ff3f4daa4b5d7d811
01-getprop-all.txt, 05-dumpsys-wifi.txt, 06-logcat-*, 10-wifi-toggle-logcat.txt
```

## Versions (authoritative, from running Android)

```
modem (MPSS)  MPSS.AT.4.0.c2-00888-SDM845_GEN_PACK-1.179738.2.191546.3   (gsm.version.baseband)
wlan driver   qca_cld3 v5.1.1.69C  (2020-10-29, out-of-tree)
build         razer/cheryl2/aura:9/P-SMR6-RC001-RZR-201022/3201 user release-keys
```

## Healthy Android modem + WLAN timeline (from 11-android-dmesg.txt)

```
4.121  subsys-restart: fw_name -> modem
4.123  ipa-wan: IPA received MPSS BEFORE_POWERUP / handling complete       <-- IPA SSR-notifier coupling
4.125  pil-q6v5-mss: modem loading 0x8e000000 -> 0x95800000
4.127  pil_mss_reset_load_mba: Assign modem memory 0xaf000000 0x00800000 (initial)  <-- extra HYP mem assign
4.131  Debug policy not present - msadp. Continue.                          (SAME as Linux: no msadp)
4.131  Loading MBA and DP from 0x96500000 -> 0x96600000
4.208  MBA boot done
6.305  modem: Brought out of reset          <-- ~2.1s mpss auth+boot, modem app starts
6.359  Subsystem error monitoring/handling services are up
6.360  ipa-wan: IPA received MPSS AFTER_POWERUP / handling complete
6.364  rmt_storage: Open modem_fs1/fs2/fsg/fsc
6.367  rmt_storage: Read modem_fs1 [offset=512,size=512] -> Done 512 bytes
6.794  Sending QMI_IPA_INIT_MODEM_DRIVER_REQ_V01
6.802  QMI_IPA_INIT_MODEM_DRIVER_REQ_V01 response received                 <-- IPA<->modem QMI handshake OK
7.529  modem: Power/Clock ready interrupt received
7.682  service-notifier: Indication from msm/modem/wlan_pd, state 0x1fffffff  <-- WLAN PD up
7.684  icnss: QMI Server Connected: state 0x981                            <-- WLFW (service 69) appears
21.35  icnss: WLAN FW is ready: 0xd87
21.39  ueventd loads wlan/qca_cld/WCNSS_qcom_cfg.ini -> wlan0
```

## Decisive comparison vs Linux fatal (CLAUDE.md §2)

| stage | Android (working) | mainline Linux |
|---|---|---|
| MBA boot | `MBA boot done` @4.208, no debug policy | OK ("MBA booted without debug policy") |
| mpss auth+boot | `modem: Brought out of reset` @6.305 | reaches "remote processor is now up" |
| **app-init window** | survives ~1.4 s, reaches wlan_pd @7.682 | **FATAL ~273 ms after up; never reaches wlan_pd** |
| WLAN PD | `msm/modem/wlan_pd` indication @7.682 | never |
| WLFW | `icnss QMI Server Connected` @7.684 | never (no service 69) |

**Confirmed:** WiFi (WCN3990) is hosted on the modem's `wlan_pd` protection
domain; WLFW/icnss only arrives *after* `msm/modem/wlan_pd` comes up. Linux
dies in the modem app-init window before that. This validates the whole CLAUDE.md
thesis: the blocker is the modem fataling, on the modem side, in app-init.

## What Android does in the exact window Linux fatals — new leads

These are the observable behaviours present on Android **inside the post-reset,
pre-wlan_pd window** where mainline fatals. Stated as observations + hypotheses
(per CLAUDE.md §8.3), not proven cause:

1. **IPA QMI handshake (raise to PRIMARY lead).** Android couples IPA tightly to
   modem bring-up: `IPA BEFORE_POWERUP` (4.123) before load, `IPA AFTER_POWERUP`
   (6.360) after reset-release, then **`QMI_IPA_INIT_MODEM_DRIVER_REQ_V01` sent
   @6.794 and response @6.802** — i.e. the AP-side IPA completes a QMI handshake
   with the modem ~0.5 s after reset-release, *before* the modem proceeds to
   wlan_pd. The MPSS image contains IPA microcode and expects this. If mainline's
   `drivers/net/ipa` does not complete the equivalent INIT_MODEM_DRIVER exchange
   in this window, the modem could fatal waiting for it. CLAUDE.md §5 listed IPA
   as a *secondary* lead; this evidence elevates it. **Next: on the Linux side,
   verify whether IPA sends/completes the modem QMI driver-init, and its timing
   vs the ~273 ms fatal.**

2. **Extra HYP memory assignment `0xaf000000 / 0x00800000 (initial)`** during MBA
   load (`pil_mss_reset_load_mba: Assign modem memory ...`). This is a modem
   metadata region the downstream transfers to the modem VMID. Compare against
   the region set mainline `qcom-q6v5-mss` transfers via
   `q6v5_xfer_mem_ownership` — a missing/incorrect region could fault the modem
   after it starts using it.

3. **Driver model difference.** Android = downstream `pil-q6v5-mss` +
   `subsys-pil-tz` with per-stage `Power/Clock ready interrupt received`;
   mainline = `qcom-q6v5-mss`. Not itself a bug, but the downstream sequences
   power/clock/PDC more granularly (CLAUDE.md §6 already adopted parts of this).

## Notes (do not over-read)

- `Debug policy not present - msadp` is the **same** on Android — confirms the
  no-debug-policy state is normal and not the fatal cause (matches CLAUDE.md §3).
- rmt_storage on Android opens fs1/fs2/fsg/fsc and the first read shown is
  `modem_fs1 [offset=512,size=512]` (= modemst1 sector1). This window does not
  prove the full EFS read order; do not conclude EFS parity from it alone.
- WiFi off→on toggle (`10-wifi-toggle-logcat.txt`) did **not** reload WCN3990
  firmware/WLAN-PD — only netdev up/down + `cnss-daemon wlan_service_core_minfreq
  RESET`. Cold WLFW handshake only occurs at boot or SSR (SSR needs root).
