# WiFi / MSS / 供電 DTS 盤點 - 2026-06-11

這份文件的目的，是把 Razer Phone 2 WiFi/MSS 移植過程中混在一起的
DTS 假設拆開。之前有幾次是把 Razer 原廠 Android、OnePlus 原廠
Android、mainline/postmarketOS 的寫法混在一起看，導致某些設定看起來
像是「有來源」，但其實只是從別的機型或別的 driver model 推過來。

這次只做盤點，不直接改 DTS。

## 使用的來源

本次只使用專案內已經存在或已解包的資料：

- 目前 Razer mainline DTS：`dts/sdm845-razer-aura.dts`
- mainline SDM845 base DTSI：`doc/sdm845.dtsi`
- mainline OnePlus common DTSI：`doc/sdm845-oneplus-common.dtsi`
- mainline Xiaomi/Poco SDM845 參考：`doc/sdm845-xiaomi-beryllium-common.dtsi`
- Razer 原廠 Android DTB 解包：
  `output/reserved-memory-compare/android-base-00.dtb.dts`
- OnePlus 6 Android 11.1.2.2 原廠 boot DTB 解包：
  `output/op6-android-11.1.2.2/boot-dtbs/boot-dtb-00.dts`
- 既有專案紀錄：
  `doc/postmarketos-sdm845-wifi-reference-2026-06-02.md`
  `doc/pmos-oneplus-and-contrast-2026-06-02.md`
  `doc/op6-android-rmtfs-dtb-comparison-2026-06-10.md`
  `doc/reserved-memory-comparison-2026-06-10.md`
  `doc/factory-mss-mdss-power-reset-audit-2026-06-09.md`

沒有假裝重新讀取 postmarketOS 網頁。pmOS 相關內容來自你之前貼回來的
原文、專案內文件、以及本地參考檔。

## 目前故障邊界

目前證據顯示：

```text
rmtfs / RFS 路徑可以 open，初始 read 成功
診斷 build 中 PDM/QMI 的 tms/pddump_disabled 查詢成功
MSS 進入 remote processor 4080000.remoteproc is now up
MSS 在 WLFW / service 69 出現前 fatal
沒有 wlanmdsp.mbn TFTP request
沒有 /sys/class/ieee80211，也沒有 wlan0
```

所以目前問題不是 NetworkManager，也不是一般 WiFi 連線設定。真正卡點是
MPSS 已經跑起來後、WLFW/wlan_pd 暴露前發生 MSS fatal。

## WiFi 節點比對

### 原廠 Android downstream

Razer 原廠 Android 與 OnePlus 原廠 Android 都使用 downstream ICNSS：

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

Razer factory 對應：

| WiFi supply | phandle | regulator | 電壓 |
|---|---:|---|---:|
| `vdd-0.8-cx-mx-supply` | `0xeb` | `pm8998_l5` | 800000 uV |
| `vdd-1.8-xo-supply` | `0xec` | `pm8998_l7` | 1800000 uV |
| `vdd-1.3-rfa-supply` | `0xed` | `pm8998_l17` | 1304000 uV |
| `vdd-3.3-ch0-supply` | `0xee` | `pm8998_l25` | 3000000..3312000 uV |

OnePlus factory 對應：

| WiFi supply | phandle | regulator | 電壓 |
|---|---:|---|---:|
| `vdd-0.8-cx-mx-supply` | `0xe9` | `pm8998_l5` | 800000 uV |
| `vdd-1.8-xo-supply` | `0xea` | `pm8998_l7` | 1800000 uV |
| `vdd-1.3-rfa-supply` | `0xeb` | `pm8998_l17` | 1304000 uV |
| `vdd-3.3-ch0-supply` | `0xec` | `pm8998_l25` | 3000000..3312000 uV |

OnePlus factory downstream ICNSS 節點另外有 `qcom,smmu-s1-bypass`。

重點：目前檢查到的 Razer / OnePlus factory Android WiFi node 都沒有靜態
`vdd-3.3-ch1-supply`。

### mainline SDM845 base

mainline `doc/sdm845.dtsi` 使用的是另一套 driver model：

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

這不是 downstream `qcom,icnss`。所以不能直接把 Android ICNSS node
逐行抄到 mainline DTS。

### mainline OnePlus / pmOS 風格

mainline OnePlus 是這樣啟用 WiFi：

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

Xiaomi/Poco mainline 也採用同樣供電結構，並使用：

```dts
qcom,ath10k-calibration-variant = "xiaomi_beryllium";
```

### 目前 Razer mainline DTS

目前 `dts/sdm845-razer-aura.dts`：

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

判斷：

- L5/L7/L17/L25 和 Razer factory、OnePlus factory 的語義一致。
- L23 / ch1 是 mainline OnePlus/Poco 的寫法，不是 Razer factory Android
  原文。它可能是 mainline WCN3990 binding 需要或接受的，但不能說它來自
  Razer factory。
- `qcom,snoc-host-cap-8bit-quirk` 是 mainline SDM845 WCN3990 常見 quirk，
  factory downstream 沒有是正常的，因為那邊是 ICNSS driver。
- `qcom,calibration-variant` 可疑。upstream DTS 範例使用
  `qcom,ath10k-calibration-variant`。這不會解決目前 MSS fatal，因為現在
  WLFW 還沒出現；但這是後續 WiFi 真正起來前應該修正的 DTS 清理項。

## MSS / remoteproc 節點比對

### 原廠 Android downstream MSS

Razer 和 OnePlus factory Android 都使用：

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

Razer factory 與 OnePlus factory 的重要差異：

| 屬性 | Razer factory | OnePlus factory |
|---|---:|---:|
| `qcom,mss_pdc_offset` | `0x09` | `0x08` |
| `qcom,sequential-fw-load` | 無 | 有 |
| MBA memory phandle | Razer 專屬 | OnePlus 專屬 |
| GPIO phandle | Razer 專屬 | OnePlus 專屬 |
| regulator phandle | Razer 專屬 | OnePlus 專屬 |

所以 OnePlus factory MSS node 不能直接複製到 Razer。

### mainline SDM845 MSS

mainline `doc/sdm845.dtsi`：

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

mainline OnePlus 只覆寫狀態與 firmware name：

```dts
&mss_pil {
    status = "okay";
    firmware-name = "qcom/sdm845/oneplus6/mba.mbn",
                    "qcom/sdm845/oneplus6/modem.mbn";
};
```

目前 Razer 也是同型，只換成 Razer firmware：

```dts
&mss_pil {
    status = "okay";
    firmware-name = "qcom/sdm845/Razer/aura/mba.mbn",
                    "qcom/sdm845/Razer/aura/modem.mbn";
};
```

判斷：

- mainline DTS 不會直接寫 downstream 的 `qcom,override-acc`、
  `qcom,signal-aop`、`qcom,qdsp6v65-1-0`、`qcom,ssctl-instance-id`、
  `qcom,minidump-id`。
- 一部分 downstream 語義已經由 mainline driver / 標準 binding 表達：
  AOSS QMP `load_state`、PDC reset、RMB alt reset、halt-regs、
  CX/MX/MSS power domains、SMP2P interrupts、GLINK edge。
- 所以有用的問題不是「哪些 downstream qcom 屬性能貼進 DTS」。
  有用的問題是：mainline `qcom_q6v5_mss` 是否真的實作了 Razer factory
  需要的 downstream 行為。
- Razer vs OnePlus 的 `qcom,mss_pdc_offset` 差異很重要。Razer 是 `0x09`，
  OnePlus 是 `0x08`。任何 reset/PDC 假設都應以 Razer factory 為準。
- 之前「MSS glink-edge 沒有 child node」這個推論不應再當根因。
  mainline SDM845 modem glink edge 通常本來就是 bare edge，IPCRTR 是 remote
  processor 動態建立並由 `rpmsg:IPCRTR` 匹配。

## reserved-memory 比對

### mainline SDM845 base

核心區塊：

| 節點 | 位址 | 大小 |
|---|---:|---:|
| `rmtfs@88f00000` | `0x88f00000` | `0x200000` |
| `wlan-msa@8df00000` | `0x8df00000` | `0x100000` |
| `mpss@8e000000` | `0x8e000000` | `0x7800000` |
| `mba@96500000` | `0x96500000` | `0x200000` |

### Razer factory / 目前 mainline 關鍵 carveout

既有比對已確認 Razer factory 與目前 mainline 在關鍵 firmware carveout
一致：

| 區塊 | 位址 | 大小 |
|---|---:|---:|
| ADSP | `0x8c500000` | `0x1a00000` |
| WLAN MSA | `0x8df00000` | `0x100000` |
| MPSS | `0x8e000000` | `0x7800000` |
| CDSP | `0x95d00000` | `0x800000` |
| MBA | `0x96500000` | `0x200000` |
| SLPI | `0x96700000` | `0x1400000` |

所以 WLAN MSA / MPSS / MBA 的 base-size 錯誤目前機率較低。

### RMTFS

Razer 與 OnePlus factory Android 都是 downstream dynamic sharedmem：

```dts
qcom,rmtfs_sharedmem@0 {
    compatible = "qcom,sharedmem-uio";
    reg = <0x0 0x200000>;
    reg-names = "rmtfs";
    qcom,client-id = <1>;
    qcom,guard-memory;
};
```

這個 node 沒有給 physical address。

mainline OnePlus 將 downstream dynamic allocation 固定化成：

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

目前 Razer source 已經採用這個 OnePlus-style contrast pattern。

判斷：

- `0xf5b00000` 不是 Razer factory 證據，而是 OnePlus mainline porting
  決策。
- 最新 QMI dump 證明 high rmtfs mapping 可以完成早期 RFS read，但它沒有
  修好 MSS fatal。
- 除非出現新的 RFS allocation/access 失敗證據，不應再單獨猜 rmtfs 位址。

## 目前看起來是猜測或尚未證明的項目

| 目前項目 | 狀態 | 影響 |
|---|---|---|
| Razer 上的 `rmtfs-mem@f5b00000` | OnePlus 對照測試，不是 Razer factory 證據 | 早期 RFS read 成功，但 MSS fatal 沒變 |
| `removed-region@88f00000/0x1c00000` | mainline OnePlus/Samsung 類型安全保留 | 合理對照，但不是 Razer factory 直接寫出來 |
| WiFi `vdd-3.3-ch1-supply = <&vreg_l23a_3p3>` | mainline OnePlus/Poco 寫法，不是 factory ICNSS 原文 | 可能是 mainline WCN3990 正確寫法，但要標明來源 |
| `qcom,calibration-variant = "razer_aura"` | 非 upstream DTS 屬性名 | mainline-clean DTS 應使用 `qcom,ath10k-calibration-variant` |
| 直接把 downstream MSS 屬性貼進 DTS | 單獨無效 | mainline 不支援的 property 會被忽略 |
| MSS `glink-edge` 缺 child node | 已排除為根因 | mainline modem GLINK/IPCRTR 本來通常是 bare edge |

## 下一步 DTS 工作建議

不要因為這份文件就直接重 build。比較合理的最小 DTS 清理順序：

1. 修正 ath10k board-data property：

   ```dts
   qcom,ath10k-calibration-variant = "razer_aura";
   ```

   這是 WLFW 出現後的 WiFi hygiene，不預期修好目前 MSS fatal。

2. 保留 WiFi L5/L7/L17/L25 supplies。它們符合 factory 語義。

3. L23/ch1 視為 mainline WCN3990 binding 選擇。除非有 binding/driver
   證據或受控 boot 測試，不要單獨移除。

4. 停止把 rmtfs base address 當獨立修復方向。QMI/RFS 證據已經顯示早期
   rmtfs 足以走到同一個 fatal boundary。

5. MSS fatal 方向應改查 driver 行為，而不是 DTS 文字：

   - Razer factory `mss_pdc_offset = 0x09` vs OnePlus `0x08`
   - downstream `qcom,override-acc` 對應 mainline reset path 的差異
   - downstream proxy-clock / proxy-unvote 對應 mainline handover 的差異
   - downstream SSCTL / minidump 對應 mainline 診斷能力的差異

6. 如果後續仍需要 DTS 改動，應該一次只改一個變數，做 boot-only artifact，
   不要再把 rmtfs/WiFi/MSS 大改混在同一版。

## 目前工作模型

目前最合理的模型不是「WiFi 供電完全沒開」，也不是「直接 copy OnePlus
DTS」。比較像是：

```text
Razer MPSS 成功啟動
MPSS 完成早期 RFS / root service startup
MPSS 在 WLFW 出現前碰到某個 Razer-specific modem/WLAN/IPA/power/reset path
目前 mainline Razer DTS/driver sequencing 沒有完全提供 factory downstream PIL/ICNSS 所提供的行為
MSS 在能暴露 WLFW 或寫出 SSR reason 前 fatal
```

所以下一步高價值工作是做 Razer factory MSS sequencing 與 mainline
`qcom_q6v5_mss` driver 的行為比對，而不是繼續廣泛猜 DTS。
