# OnePlus 6 Android 11.1.2.2 DTB / RMTFS Comparison

Source zip: `11.1.2.2-OP6-FASTBOOT.zip`. Extracted `boot.img` and `dtbo.img` only.

## Extracted Artifacts

- Boot DTBs: `output/op6-android-11.1.2.2/boot-dtbs/boot-dtb-00..03.*`
- DTBO overlays: `output/op6-android-11.1.2.2/dtbo-entries/dtbo-entry-00..23.*`

## OnePlus Android boot DTB 00 reserved-memory

Source: `output/op6-android-11.1.2.2/boot-dtbs/boot-dtb-00.dts`

| node | label | base | size | compatible | flags |
|---|---|---:|---:|---|---|
| `hyp_region@85700000` | `` | 0x85700000 | 0x600000 | `` | no-map |
| `xbl_region@85e00000` | `` | 0x85e00000 | 0x100000 | `` | no-map |
| `removed_region@85fc0000` | `` | 0x85fc0000 | 0x4b40000 | `` | no-map |
| `qseecom_region@0x8ab00000` | `` | 0x8ab00000 | 0x1400000 | `shared-dma-pool` | no-map |
| `camera_region@0x8bf00000` | `` | 0x8bf00000 | 0x500000 | `removed-dma-pool` | no-map |
| `ips_fw_region@0x8c400000` | `` | 0x8c400000 | 0x10000 | `removed-dma-pool` | no-map |
| `ipa_gsi_region@0x8c410000` | `` | 0x8c410000 | 0x5000 | `removed-dma-pool` | no-map |
| `gpu_region@0x8c415000` | `` | 0x8c415000 | 0x2000 | `removed-dma-pool` | no-map |
| `adsp_region@0x8c500000` | `` | 0x8c500000 | 0x1a00000 | `removed-dma-pool` | no-map |
| `wlan_fw_region@0x8df00000` | `` | 0x8df00000 | 0x100000 | `removed-dma-pool` | no-map |
| `modem_region@0x8e000000` | `` | 0x8e000000 | 0x7800000 | `removed-dma-pool` | no-map |
| `video_region@0x95800000` | `` | 0x95800000 | 0x500000 | `removed-dma-pool` | no-map |
| `cdsp_region@0x95d00000` | `` | 0x95d00000 | 0x900000 | `removed-dma-pool` | no-map |
| `mba_region@0x96600000` | `` | 0x96600000 | 0x200000 | `removed-dma-pool` | no-map |
| `slpi_region@0x96800000` | `` | 0x96800000 | 0x1400000 | `removed-dma-pool` | no-map |
| `pil_spss_region@0x97c00000` | `` | 0x97c00000 | 0x100000 | `removed-dma-pool` | no-map |
| `adsp_region` | `` |  | 0x1000000 | `shared-dma-pool` | reusable |
| `qseecom_ta_region` | `` |  | 0x1000000 | `shared-dma-pool` | reusable |
| `secure_sp_region` | `` |  | 0x800000 | `shared-dma-pool` | reusable |
| `cont_splash_region@9d400000` | `` | 0x9d400000 | 0x2400000 | `` |  |
| `secure_display_region` | `` |  | 0x5c00000 | `shared-dma-pool` | reusable |
| `mem_dump_region` | `` |  | 0x2400000 | `shared-dma-pool` | reusable |
| `linux,cma` | `` |  | 0x2000000 | `shared-dma-pool` | reusable |
| `bootloader_log_mem@0x9FFF7000` | `` | 0x9fff7000 | 0x100000 | `` |  |
| `param_mem@ac200000` | `` | 0xac200000 | 0x100000 | `` |  |
| `ramoops@0xAC300000` | `` | 0xac300000 | 0x400000 | `ramoops` |  |
| `mtp_mem@ac700000` | `` | 0xac700000 | 0xb00000 | `` |  |

## OnePlus Android boot DTB 01 reserved-memory

Source: `output/op6-android-11.1.2.2/boot-dtbs/boot-dtb-01.dts`

| node | label | base | size | compatible | flags |
|---|---|---:|---:|---|---|
| `hyp_region@85700000` | `` | 0x85700000 | 0x600000 | `` | no-map |
| `xbl_region@85e00000` | `` | 0x85e00000 | 0x100000 | `` | no-map |
| `removed_region@85fc0000` | `` | 0x85fc0000 | 0x4b40000 | `` | no-map |
| `qseecom_region@0x8ab00000` | `` | 0x8ab00000 | 0x1400000 | `shared-dma-pool` | no-map |
| `camera_region@0x8bf00000` | `` | 0x8bf00000 | 0x500000 | `removed-dma-pool` | no-map |
| `ips_fw_region@0x8c400000` | `` | 0x8c400000 | 0x10000 | `removed-dma-pool` | no-map |
| `ipa_gsi_region@0x8c410000` | `` | 0x8c410000 | 0x5000 | `removed-dma-pool` | no-map |
| `gpu_region@0x8c415000` | `` | 0x8c415000 | 0x2000 | `removed-dma-pool` | no-map |
| `adsp_region@0x8c500000` | `` | 0x8c500000 | 0x1a00000 | `removed-dma-pool` | no-map |
| `wlan_fw_region@0x8df00000` | `` | 0x8df00000 | 0x100000 | `removed-dma-pool` | no-map |
| `modem_region@0x8e000000` | `` | 0x8e000000 | 0x7800000 | `removed-dma-pool` | no-map |
| `video_region@0x95800000` | `` | 0x95800000 | 0x500000 | `removed-dma-pool` | no-map |
| `cdsp_region@0x95d00000` | `` | 0x95d00000 | 0x900000 | `removed-dma-pool` | no-map |
| `mba_region@0x96600000` | `` | 0x96600000 | 0x200000 | `removed-dma-pool` | no-map |
| `slpi_region@0x96800000` | `` | 0x96800000 | 0x1400000 | `removed-dma-pool` | no-map |
| `pil_spss_region@0x97c00000` | `` | 0x97c00000 | 0x100000 | `removed-dma-pool` | no-map |
| `adsp_region` | `` |  | 0x1000000 | `shared-dma-pool` | reusable |
| `qseecom_ta_region` | `` |  | 0x1000000 | `shared-dma-pool` | reusable |
| `secure_sp_region` | `` |  | 0x800000 | `shared-dma-pool` | reusable |
| `cont_splash_region@9d400000` | `` | 0x9d400000 | 0x2400000 | `` |  |
| `secure_display_region` | `` |  | 0x5c00000 | `shared-dma-pool` | reusable |
| `mem_dump_region` | `` |  | 0x2400000 | `shared-dma-pool` | reusable |
| `linux,cma` | `` |  | 0x2000000 | `shared-dma-pool` | reusable |
| `bootloader_log_mem@0x9FFF7000` | `` | 0x9fff7000 | 0x100000 | `` |  |
| `param_mem@ac200000` | `` | 0xac200000 | 0x100000 | `` |  |
| `ramoops@0xAC300000` | `` | 0xac300000 | 0x400000 | `ramoops` |  |
| `mtp_mem@ac700000` | `` | 0xac700000 | 0xb00000 | `` |  |

## OnePlus Android boot DTB 02 reserved-memory

Source: `output/op6-android-11.1.2.2/boot-dtbs/boot-dtb-02.dts`

| node | label | base | size | compatible | flags |
|---|---|---:|---:|---|---|
| `hyp_region@85700000` | `` | 0x85700000 | 0x600000 | `` | no-map |
| `xbl_region@85e00000` | `` | 0x85e00000 | 0x100000 | `` | no-map |
| `removed_region@85fc0000` | `` | 0x85fc0000 | 0x4b40000 | `` | no-map |
| `qseecom_region@0x8ab00000` | `` | 0x8ab00000 | 0x1400000 | `shared-dma-pool` | no-map |
| `camera_region@0x8bf00000` | `` | 0x8bf00000 | 0x500000 | `removed-dma-pool` | no-map |
| `ips_fw_region@0x8c400000` | `` | 0x8c400000 | 0x10000 | `removed-dma-pool` | no-map |
| `ipa_gsi_region@0x8c410000` | `` | 0x8c410000 | 0x5000 | `removed-dma-pool` | no-map |
| `gpu_region@0x8c415000` | `` | 0x8c415000 | 0x2000 | `removed-dma-pool` | no-map |
| `adsp_region@0x8c500000` | `` | 0x8c500000 | 0x1a00000 | `removed-dma-pool` | no-map |
| `wlan_fw_region@0x8df00000` | `` | 0x8df00000 | 0x100000 | `removed-dma-pool` | no-map |
| `modem_region@0x8e000000` | `` | 0x8e000000 | 0x7800000 | `removed-dma-pool` | no-map |
| `video_region@0x95800000` | `` | 0x95800000 | 0x500000 | `removed-dma-pool` | no-map |
| `cdsp_region@0x95d00000` | `` | 0x95d00000 | 0x900000 | `removed-dma-pool` | no-map |
| `mba_region@0x96600000` | `` | 0x96600000 | 0x200000 | `removed-dma-pool` | no-map |
| `slpi_region@0x96800000` | `` | 0x96800000 | 0x1400000 | `removed-dma-pool` | no-map |
| `pil_spss_region@0x97c00000` | `` | 0x97c00000 | 0x100000 | `removed-dma-pool` | no-map |
| `adsp_region` | `` |  | 0x1000000 | `shared-dma-pool` | reusable |
| `qseecom_ta_region` | `` |  | 0x1000000 | `shared-dma-pool` | reusable |
| `secure_sp_region` | `` |  | 0x800000 | `shared-dma-pool` | reusable |
| `cont_splash_region@9d400000` | `` | 0x9d400000 | 0x2400000 | `` |  |
| `secure_display_region` | `` |  | 0x5c00000 | `shared-dma-pool` | reusable |
| `mem_dump_region` | `` |  | 0x2400000 | `shared-dma-pool` | reusable |
| `linux,cma` | `` |  | 0x2000000 | `shared-dma-pool` | reusable |
| `bootloader_log_mem@0x9FFF7000` | `` | 0x9fff7000 | 0x100000 | `` |  |
| `param_mem@ac200000` | `` | 0xac200000 | 0x100000 | `` |  |
| `ramoops@0xAC300000` | `` | 0xac300000 | 0x400000 | `ramoops` |  |
| `mtp_mem@ac700000` | `` | 0xac700000 | 0xb00000 | `` |  |

## OnePlus Android rmtfs_sharedmem nodes

### boot-dtb-00.dts

```dts
			compatible = "qcom,msm_gsi";
		};

		qcom,rmtfs_sharedmem@0 {
			compatible = "qcom,sharedmem-uio";
			reg = <0x00 0x200000>;
			reg-names = "rmtfs";
			qcom,client-id = <0x01>;
			qcom,guard-memory;
		};

		qcom,rmnet-ipa {

```

### boot-dtb-01.dts

```dts
			compatible = "qcom,msm_gsi";
		};

		qcom,rmtfs_sharedmem@0 {
			compatible = "qcom,sharedmem-uio";
			reg = <0x00 0x200000>;
			reg-names = "rmtfs";
			qcom,client-id = <0x01>;
			qcom,guard-memory;
		};

		qcom,rmnet-ipa {

```

### boot-dtb-02.dts

```dts
			compatible = "qcom,msm_gsi";
		};

		qcom,rmtfs_sharedmem@0 {
			compatible = "qcom,sharedmem-uio";
			reg = <0x00 0x200000>;
			reg-names = "rmtfs";
			qcom,client-id = <0x01>;
			qcom,guard-memory;
		};

		qcom,rmnet-ipa {

```

## DTBO overlay scan

No `qcom,rmtfs_sharedmem`, `reg-names = "rmtfs"`, or `rmtfs` node was found in the 24 OnePlus DTBO overlay DTS files. The rmtfs node is in the base boot DTBs, not panel overlays.

## Cross-check against mainline OnePlus 6

The downstream Android DTB only states rmtfs shared memory size and guard behavior:

```dts
qcom,rmtfs_sharedmem@0 {
    compatible = "qcom,sharedmem-uio";
    reg = <0x00 0x200000>;
    reg-names = "rmtfs";
    qcom,client-id = <0x01>;
    qcom,guard-memory;
};
```

Mainline OnePlus 6 converts that dynamic downstream allocation into a fixed active rmtfs region at `0xf5b00000/0x202000`, and separately reserves the old `0x88f00000/0x1c00000` modem/rmtfs window. This fixed address is not directly present in the Android DTB; it is a porting decision based on observed downstream allocation behavior.

## Implication for Razer Phone 2

- Razer Android and OnePlus Android both use the same downstream-style `qcom,rmtfs_sharedmem@0` with `reg=<0x0 0x200000>`, `client-id=<1>`, and guard memory. Neither Android DTB gives a physical rmtfs base.

- Therefore Razer current `rmtfs-mem@88f00000` is not proven by Razer Android DTB.

- A valid controlled test is the complete mainline OnePlus pattern: active `rmtfs-mem@f5b00000` with guard pages plus a separate `removed-region@88f00000/0x1c00000`, not only moving the rmtfs address by itself.
