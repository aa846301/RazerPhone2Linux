# WCN3990 WiFi firmware packaging audit

## Scope and baseline

- Hardware/board revision: Razer Phone 2 `aura`, Qualcomm SDM845 with WCN3990
  WiFi over SNOC; exact handset PCB revision is not exposed by the current
  userspace and is not relevant to the missing common API file.
- Factory production include chain: Razer Android 9 SMR7 factory modem image
  supplies `wlanmdsp.mbn` and `bdwlan*`; the production DTS baseline and
  reserved-memory comparison are recorded in
  `doc/wifi-power-dts-audit-2026-06-11.md`.
- Repo/kernel/rootfs/firmware identity: repo `026672515`; live kernel
  `7.1.0-rc1-sdm845 #1 SMP PREEMPT Sat Jul 18 17:45:53 UTC 2026`; live rootfs
  had Razer board data but no
  `/usr/lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin`.
- Reproduction command: boot the release image, then inspect
  `journalctl -b -k` and `ip -br link`.
- Last proven stage: MSS boots, WLFW QMI reports WCN3990 chip and firmware
  identity, and `ath10k_snoc` begins its mainline firmware lookup.
- First failing stage:
  `Failed to find firmware-N.bin (N between 2 and 6) ...: -2`, followed by
  `could not fetch firmware files` and no `wlan0`.

## Mainline capability

- Binding/compatible: SDM845 `wifi@18800000`, represented by the upstream
  SDM845 WiFi node and the board `&wifi` override.
- Driver/config: mainline `ath10k_snoc`, `CONFIG_ATH10K` and
  `CONFIG_ATH10K_SNOC`.
- Reference DTS/commit: pinned `sdm845-mainline/linux` commit
  `85f1df2a4ec71d7a91dd95a7a49f889d1595ffa8`; current board DTS documents
  `board.bin`/`board-2.bin` and `firmware-5.bin` as runtime requirements.
- DTS-only, quirk, or new driver: no driver or DTS change is justified. The
  live failure is a rootfs packaging omission after successful device/QMI
  enumeration.

## Online prior art

| Source | Version/board | Proven result | Reusable part | Gap |
|---|---|---|---|---|
| `kernel-firmware/linux-firmware` commit `b142c2e0229bc89b44ac527f4f3c3def063bcbc6` | WCN3990 hw1.0 | Introduces `firmware-5.bin`, SHA-256 `fef6539e0127579536bc977be57a90d018b83f2931fedc3a8870fbe38d6c4127` | Pinned common ath10k API file | Does not contain Razer calibration |
| Razer Android 9 SMR7 factory modem image | Razer `aura` | Supplies `wlanmdsp.mbn` and `bdwlan*` used by the live QMI/board-data path | Device-specific firmware and calibration | Does not supply mainline `firmware-5.bin` |

## Requirements inventory

| Area/item | Required value | Factory/source evidence | Mainline representation | Status |
|---|---|---|---|---|
| Identity | WCN3990 hw1.0 over SNOC | Live QMI `chip_id 0x30214`; factory WLAN payload | `ath10k_snoc`, `ath10k/WCN3990/hw1.0` | proven |
| Power | Five SDM845 WiFi regulator supplies | Factory/mainline DTS audit | `&wifi` supply properties | proven |
| Sequence | MSS/WLFW available before ath10k probe completes | Live MSS-up and QMI identity logs | remoteproc/QRTR/QMI probe chain | proven |
| Clock/reset | Existing SDM845 controller resources | Mainline SDM845 base DTS | inherited WiFi node resources | proven |
| GPIO/pinctrl | No new board GPIO required for this packaging failure | Mainline SNOC integration and successful QMI | inherited controller node | N/A |
| Protocol | SNOC plus WLFW QMI | Live `ath10k_snoc` QMI messages | ath10k SNOC/QMI transport | proven |
| IRQ/wakeup | Existing SDM845 WiFi node resources | Probe reaches firmware request | inherited mainline resources | proven |
| Memory/DMA | Factory-aligned WLAN/MSS reserved memory | Existing WiFi power/DTS audit; MSS reaches running | SDM845 reserved-memory and IOMMU nodes | proven |
| Firmware/data | Razer `wlanmdsp.mbn`; Razer `board.bin` or `board-2.bin`; upstream `firmware-5.bin` | Factory extraction plus linux-firmware commit above | `/usr/lib/firmware/ath10k/WCN3990/hw1.0/` | proven |
| Chip commands | No new register/profile data | QMI identifies chip before file lookup fails | existing ath10k implementation | N/A |
| Kernel/ABI | ath10k SNOC plus NetworkManager after `wlan0` exists | Live modules loaded; NetworkManager reports hardware missing | standard cfg80211/mac80211 netdev | proven |
| Validation | Firmware lookup must succeed and create `wlan0` | Current failure log supplies negative baseline | dmesg plus `ip -br link` | physical proof pending rebuilt rootfs |

## Factory-to-mainline call-chain comparison

| Step | Factory behavior | Mainline mechanism | Current port | Delta | Evidence |
|---|---|---|---|---|---|
| Board selection | Loads Razer WLAN calibration | `board-2.bin` variant or `board.bin` fallback | `board.bin` is present | none | live rootfs listing |
| Remote firmware | Starts WLAN protection domain from modem payload | MSS/WLFW QMI with `wlanmdsp.mbn` | chip and WLAN firmware identity reported | none | live kernel log |
| API file lookup | Android downstream does not use the mainline filename contract | ath10k requests `firmware-[2-6].bin` | every candidate absent | install pinned `firmware-5.bin` | live `-ENOENT` log |
| Netdev registration | Factory WLAN driver registers an interface | ath10k/cfg80211 registers `wlan0` after firmware probe | not reached | unblock API file lookup | NetworkManager `WIFI-HW missing` |

## Implementation and staged validation

- Smallest justified change: one shared, pinned installer validates
  `firmware-5.bin` by SHA-256 and requires Razer board data. Full rootfs build,
  cached-rootfs refresh, and both CI firmware-cache paths call it. CI firmware
  cache version is bumped and required-file validation now fails closed.
- Static checks: `git diff --check`, `bash -n` for the shared installer and
  both rootfs paths, YAML parsing, a real pinned download/hash test, an
  idempotent second install, and fail-closed/explicit-opt-out board-data tests
  all pass on 2026-07-25. `shellcheck` was unavailable in Ubuntu-24.04.
- Build/run identity: pending the next GitHub Actions image.
- Probe/resource proof: existing MSS/WLFW/QMI proof retained.
- Transfer proof: pending successful ath10k firmware probe and `wlan0`.
- Physical proof: pending scan/association test on the rebuilt rootfs.
- Remaining unknowns: none that alter this packaging fix; RF operation remains
  to be validated after flashing.
