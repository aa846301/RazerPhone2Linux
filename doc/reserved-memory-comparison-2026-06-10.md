# Reserved Memory Comparison - Razer Phone 2 / OnePlus 6

Generated from decompiled DTBs and local DTS sources. Live FDT was captured from `/sys/firmware/fdt` over SSH.

## Razer factory boot DTB

Source: `output/reserved-memory-compare/boot-dtb0.dtb.dts`

| node | label | base | size | compatible | flags / notes |
|---|---|---:|---:|---|---|
| `hyp_region@85700000` | `` | 0x85700000 | 0x600000 | `` | no-map |
| `xbl_region@85e00000` | `` | 0x85e00000 | 0x100000 | `` | no-map |
| `removed_region@85fc0000` | `` | 0x85fc0000 | 0x2f40000 | `` | no-map |
| `qseecom_region@0x8ab00000` | `` | 0x8ab00000 | 0x1400000 | `shared-dma-pool` | no-map |
| `camera_region@0x8bf00000` | `` | 0x8bf00000 | 0x500000 | `removed-dma-pool` | no-map |
| `ips_fw_region@0x8c400000` | `` | 0x8c400000 | 0x10000 | `removed-dma-pool` | no-map |
| `ipa_gsi_region@0x8c410000` | `` | 0x8c410000 | 0x5000 | `removed-dma-pool` | no-map |
| `gpu_region@0x8c415000` | `` | 0x8c415000 | 0x2000 | `removed-dma-pool` | no-map |
| `adsp_region@0x8c500000` | `` | 0x8c500000 | 0x1a00000 | `removed-dma-pool` | no-map |
| `wlan_fw_region@0x8df00000` | `` | 0x8df00000 | 0x100000 | `removed-dma-pool` | no-map |
| `modem_region@0x8e000000` | `` | 0x8e000000 | 0x7800000 | `removed-dma-pool` | no-map |
| `video_region@0x95800000` | `` | 0x95800000 | 0x500000 | `removed-dma-pool` | no-map |
| `cdsp_region@0x95d00000` | `` | 0x95d00000 | 0x800000 | `removed-dma-pool` | no-map |
| `mba_region@0x96500000` | `` | 0x96500000 | 0x200000 | `removed-dma-pool` | no-map |
| `slpi_region@0x96700000` | `` | 0x96700000 | 0x1400000 | `removed-dma-pool` | no-map |
| `pil_spss_region@0x97b00000` | `` | 0x97b00000 | 0x100000 | `removed-dma-pool` | no-map |
| `adsp_region` | `` |  | 0x1000000 | `shared-dma-pool` | reusable, dynamic/resizable, alloc-ranges 0x00 0x00 0x00 0xffffffff |
| `qseecom_ta_region` | `` |  | 0x1000000 | `shared-dma-pool` | reusable, dynamic/resizable, alloc-ranges 0x00 0x00 0x00 0xffffffff |
| `secure_sp_region` | `` |  | 0x800000 | `shared-dma-pool` | reusable, dynamic/resizable, alloc-ranges 0x00 0x00 0x00 0xffffffff |
| `cont_splash_region@9d400000` | `` | 0x9d400000 | 0x2400000 | `` |  |
| `secure_display_region` | `` |  | 0x5c00000 | `shared-dma-pool` | reusable, dynamic/resizable, alloc-ranges 0x00 0x00 0x00 0xffffffff |
| `mem_dump_region` | `` |  | 0x2400000 | `shared-dma-pool` | reusable, dynamic/resizable |
| `linux,cma` | `` |  | 0x2000000 | `shared-dma-pool` | reusable, dynamic/resizable, alloc-ranges 0x00 0x00 0x00 0xffffffff |
| `fih_nv_region@0xAF000000` | `` | 0xaf000000 | 0x800000 | `removed-dma-pool` | no-map |
| `pstore_region@0xAF800000` | `` | 0xaf800000 | 0x200000 | `removed-dma-pool` | no-map |
| `fih_region@0xAFA00000` | `` | 0xafa00000 | 0x600000 | `removed-dma-pool` | no-map |

## Razer current source dts

Source: `dts/sdm845-razer-aura.dts`

| node | label | base | size | compatible | flags / notes |
|---|---|---:|---:|---|---|
| `rmtfs-mem@88f00000` | `rmtfs_mem` | 0x88f00000 | 0x202000 | `qcom,rmtfs-mem` | no-map |
| `ramoops@ac300000` | `ramoops` | 0xac300000 | 0x400000 | `ramoops` |  |
| `fih-nv@af000000` | `fih_nv_mem` | 0xaf000000 | 0x800000 | `removed-dma-pool` | no-map |
| `fih-pstore@af800000` | `fih_pstore_mem` | 0xaf800000 | 0x200000 | `removed-dma-pool` | no-map |
| `fih@afa00000` | `fih_mem` | 0xafa00000 | 0x600000 | `removed-dma-pool` | no-map |

## Razer current output dtb

Source: `output/reserved-memory-compare/sdm845-razer-aura.dtb.dts`

| node | label | base | size | compatible | flags / notes |
|---|---|---:|---:|---|---|
| `hyp-mem@85700000` | `` | 0x85700000 | 0x600000 | `` | no-map |
| `xbl-mem@85e00000` | `` | 0x85e00000 | 0x100000 | `` | no-map |
| `aop-mem@85fc0000` | `` | 0x85fc0000 | 0x20000 | `` | no-map |
| `aop-cmd-db-mem@85fe0000` | `` | 0x85fe0000 | 0x20000 | `qcom,cmd-db` | no-map |
| `smem@86000000` | `` | 0x86000000 | 0x200000 | `qcom,smem` | no-map |
| `tz@86200000` | `` | 0x86200000 | 0x2d00000 | `` | no-map |
| `qseecom@8ab00000` | `` | 0x8ab00000 | 0x1400000 | `` | no-map |
| `camera-mem@8bf00000` | `` | 0x8bf00000 | 0x500000 | `` | no-map |
| `ipa-fw@8c400000` | `` | 0x8c400000 | 0x10000 | `` | no-map |
| `ipa-gsi@8c410000` | `` | 0x8c410000 | 0x5000 | `` | no-map |
| `gpu@8c415000` | `` | 0x8c415000 | 0x2000 | `` | no-map |
| `adsp@8c500000` | `` | 0x8c500000 | 0x1a00000 | `` | no-map |
| `wlan-msa@8df00000` | `` | 0x8df00000 | 0x100000 | `` | no-map |
| `mpss@8e000000` | `` | 0x8e000000 | 0x7800000 | `` | no-map |
| `venus@95800000` | `` | 0x95800000 | 0x500000 | `` | no-map |
| `cdsp@95d00000` | `` | 0x95d00000 | 0x800000 | `` | no-map |
| `mba@96500000` | `` | 0x96500000 | 0x200000 | `` | no-map |
| `slpi@96700000` | `` | 0x96700000 | 0x1400000 | `` | no-map |
| `spss@97b00000` | `` | 0x97b00000 | 0x100000 | `` | no-map |
| `mpss-metadata` | `` |  | 0x4000 | `` | no-map, dynamic/resizable, alloc-ranges 0x00 0xa0000000 0x00 0x20000000 |
| `framebuffer@9d400000` | `` | 0x9d400000 | 0x2400000 | `` | no-map |
| `fastrpc` | `` |  | 0x1000000 | `shared-dma-pool` | reusable, dynamic/resizable, alloc-ranges 0x00 0x00 0x00 0xffffffff |
| `rmtfs-mem@88f00000` | `` | 0x88f00000 | 0x202000 | `qcom,rmtfs-mem` | no-map |
| `ramoops@ac300000` | `` | 0xac300000 | 0x400000 | `ramoops` |  |
| `fih-nv@af000000` | `` | 0xaf000000 | 0x800000 | `removed-dma-pool` | no-map |
| `fih-pstore@af800000` | `` | 0xaf800000 | 0x200000 | `removed-dma-pool` | no-map |
| `fih@afa00000` | `` | 0xafa00000 | 0x600000 | `removed-dma-pool` | no-map |

## Razer live /sys/firmware/fdt

Source: `output/reserved-memory-compare/live-fdt.dtb.dts`

| node | label | base | size | compatible | flags / notes |
|---|---|---:|---:|---|---|
| `hyp-mem@85700000` | `` | 0x85700000 | 0x600000 | `` | no-map |
| `xbl-mem@85e00000` | `` | 0x85e00000 | 0x100000 | `` | no-map |
| `aop-mem@85fc0000` | `` | 0x85fc0000 | 0x20000 | `` | no-map |
| `aop-cmd-db-mem@85fe0000` | `` | 0x85fe0000 | 0x20000 | `qcom,cmd-db` | no-map |
| `smem@86000000` | `` | 0x86000000 | 0x200000 | `qcom,smem` | no-map |
| `tz@86200000` | `` | 0x86200000 | 0x2d00000 | `` | no-map |
| `qseecom@8ab00000` | `` | 0x8ab00000 | 0x1400000 | `` | no-map |
| `camera-mem@8bf00000` | `` | 0x8bf00000 | 0x500000 | `` | no-map |
| `ipa-fw@8c400000` | `` | 0x8c400000 | 0x10000 | `` | no-map |
| `ipa-gsi@8c410000` | `` | 0x8c410000 | 0x5000 | `` | no-map |
| `gpu@8c415000` | `` | 0x8c415000 | 0x2000 | `` | no-map |
| `adsp@8c500000` | `` | 0x8c500000 | 0x1a00000 | `` | no-map |
| `wlan-msa@8df00000` | `` | 0x8df00000 | 0x100000 | `` | no-map |
| `mpss@8e000000` | `` | 0x8e000000 | 0x7800000 | `` | no-map |
| `venus@95800000` | `` | 0x95800000 | 0x500000 | `` | no-map |
| `cdsp@95d00000` | `` | 0x95d00000 | 0x800000 | `` | no-map |
| `mba@96500000` | `` | 0x96500000 | 0x200000 | `` | no-map |
| `slpi@96700000` | `` | 0x96700000 | 0x1400000 | `` | no-map |
| `spss@97b00000` | `` | 0x97b00000 | 0x100000 | `` | no-map |
| `mpss-metadata` | `` |  | 0x4000 | `` | no-map, dynamic/resizable, alloc-ranges 0x00 0xa0000000 0x00 0x20000000 |
| `framebuffer@9d400000` | `` | 0x9d400000 | 0x2400000 | `` | no-map |
| `fastrpc` | `` |  | 0x1000000 | `shared-dma-pool` | reusable, dynamic/resizable, alloc-ranges 0x00 0x00 0x00 0xffffffff |
| `rmtfs-mem@88f00000` | `` | 0x88f00000 | 0x202000 | `qcom,rmtfs-mem` | no-map |
| `ramoops@ac300000` | `` | 0xac300000 | 0x400000 | `ramoops` |  |
| `fih-nv@af000000` | `` | 0xaf000000 | 0x800000 | `removed-dma-pool` | no-map |
| `fih-pstore@af800000` | `` | 0xaf800000 | 0x200000 | `removed-dma-pool` | no-map |
| `fih@afa00000` | `` | 0xafa00000 | 0x600000 | `removed-dma-pool` | no-map |

## OnePlus 6 common dtsi

Source: `output/reserved-memory-compare/sdm845-oneplus-common.dtsi`

| node | label | base | size | compatible | flags / notes |
|---|---|---:|---:|---|---|
| `rmtfs-mem@f5b00000` | `rmtfs_mem` | 0xf5b00000 | 0x202000 | `qcom,rmtfs-mem` | no-map |
| `removed-region@88f00000` | `removed_region` | 0x88f00000 | 0x1c00000 | `` | no-map |
| `ramoops@ac300000` | `ramoops` | 0xac300000 | 0x400000 | `ramoops` |  |

## SDM845 base dtsi inherited by OnePlus

Source: `output/reserved-memory-compare/sdm845.dtsi`

| node | label | base | size | compatible | flags / notes |
|---|---|---:|---:|---|---|
| `hyp-mem@85700000` | `hyp_mem` | 0x85700000 | 0x600000 | `` | no-map |
| `xbl-mem@85e00000` | `xbl_mem` | 0x85e00000 | 0x100000 | `` | no-map |
| `aop-mem@85fc0000` | `aop_mem` | 0x85fc0000 | 0x20000 | `` | no-map |
| `aop-cmd-db-mem@85fe0000` | `aop_cmd_db_mem` | 0x85fe0000 | 0x20000 | `qcom,cmd-db` | no-map |
| `smem@86000000` | `` | 0x86000000 | 0x200000 | `qcom,smem` | no-map |
| `tz@86200000` | `tz_mem` | 0x86200000 | 0x2d00000 | `` | no-map |
| `rmtfs@88f00000` | `rmtfs_mem` | 0x88f00000 | 0x200000 | `qcom,rmtfs-mem` | no-map |
| `qseecom@8ab00000` | `qseecom_mem` | 0x8ab00000 | 0x1400000 | `` | no-map |
| `camera-mem@8bf00000` | `camera_mem` | 0x8bf00000 | 0x500000 | `` | no-map |
| `ipa-fw@8c400000` | `ipa_fw_mem` | 0x8c400000 | 0x10000 | `` | no-map |
| `ipa-gsi@8c410000` | `ipa_gsi_mem` | 0x8c410000 | 0x5000 | `` | no-map |
| `gpu@8c415000` | `gpu_mem` | 0x8c415000 | 0x2000 | `` | no-map |
| `adsp@8c500000` | `adsp_mem` | 0x8c500000 | 0x1a00000 | `` | no-map |
| `wlan-msa@8df00000` | `wlan_msa_mem` | 0x8df00000 | 0x100000 | `` | no-map |
| `mpss@8e000000` | `mpss_region` | 0x8e000000 | 0x7800000 | `` | no-map |
| `venus@95800000` | `venus_mem` | 0x95800000 | 0x500000 | `` | no-map |
| `cdsp@95d00000` | `cdsp_mem` | 0x95d00000 | 0x800000 | `` | no-map |
| `mba@96500000` | `mba_region` | 0x96500000 | 0x200000 | `` | no-map |
| `slpi@96700000` | `slpi_mem` | 0x96700000 | 0x1400000 | `` | no-map |
| `spss@97b00000` | `spss_mem` | 0x97b00000 | 0x100000 | `` | no-map |
| `mpss-metadata` | `mdata_mem` |  | 0x4000 | `` | no-map, dynamic/resizable, alloc-ranges 0 0xa0000000 0 0x20000000 |
| `framebuffer@9d400000` | `cont_splash_mem` | 0x9d400000 | 0x2400000 | `` | no-map |
| `fastrpc` | `fastrpc_mem` |  | 0x1000000 | `shared-dma-pool` | reusable, dynamic/resizable, alloc-ranges 0x0 0x00000000 0x0 0xffffffff |

## Key Differences

- Razer factory and current mainline agree on the critical firmware carveouts: ADSP `0x8c500000/0x1a00000`, WLAN MSA `0x8df00000/0x100000`, MPSS `0x8e000000/0x7800000`, CDSP `0x95d00000/0x800000`, MBA `0x96500000/0x200000`, SLPI `0x96700000/0x1400000`.

- Razer factory groups `0x85fc0000..0x88efffff` as one removed region. Mainline splits it into AOP, cmd-db, SMEM and TZ nodes. The total span matches the factory removed region.

- Razer current DTS adds `ramoops@0xac300000` and preserves FIH OEM regions at `0xaf000000`, `0xaf800000`, and `0xafa00000`, matching factory addresses.

- Razer current `rmtfs-mem` is `0x88f00000/0x202000`; OnePlus 6 uses `0xf5b00000/0x202000` and additionally reserves the old `0x88f00000/0x1c00000` window.

- OnePlus common does not define the core ADSP/WLAN/MPSS/MBA/SLPI carveouts itself; those come from the inherited SDM845 base dtsi.

- Follow-up check with `11.1.2.2-OP6-FASTBOOT.zip` shows OnePlus Android DTBs
  also use downstream-style `qcom,rmtfs_sharedmem@0` with only
  `reg=<0x0 0x200000>`, `qcom,client-id=<1>`, and guard memory. The physical
  `0xf5b00000` active rmtfs address is not present in the Android DTB; it is a
  mainline OnePlus porting decision based on downstream runtime allocation
  behavior. See `doc/op6-android-rmtfs-dtb-comparison-2026-06-10.md`.
