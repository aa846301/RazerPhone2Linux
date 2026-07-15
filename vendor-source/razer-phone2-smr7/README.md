# Razer Phone 2 Android kernel reference

This directory records the official Razer Phone 2 Android 9 SMR7 kernel
source used as a reference for PMI8998 SMB2 charging and USB/Type-C behavior.

- Release: Razer Phone 2 Global Android 9 SMR7
- Archive: `msm-4.9-3225.tar`
- Official URL: <https://cheryl-factory-images.s3.amazonaws.com/msm-4.9-3225.tar>
- SHA-256: `DB89AEA07B96280C9ADBFCD886C4164C8DCB6DCE3D0D16552C8CF029841A79AA`
- Local extracted source: `msm-4.9/`

The extracted source is intentionally ignored by Git because it is a large
vendor source tree. Keep this README tracked so the exact source can be fetched
and verified again.

Charging implementation files of primary interest:

- `msm-4.9/drivers/power/supply/qcom/qpnp-smb2.c`
- `msm-4.9/drivers/power/supply/qcom/smb-lib.c`
- `msm-4.9/drivers/power/supply/qcom/smb-lib.h`
- `msm-4.9/Documentation/devicetree/bindings/power/supply/qcom/qpnp-smb2.txt`
