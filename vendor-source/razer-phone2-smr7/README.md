# Razer Phone 2 Android kernel reference

This directory records the official Razer Phone 2 Android 9 SMR7 kernel
source used as a reference for PMI8998 SMB2 charging, USB/Type-C, camera,
audio and haptics behavior.

- Release: Razer Phone 2 Global Android 9 SMR7
- Archive: `msm-4.9-3225.tar`
- Official URL: <https://cheryl-factory-images.s3.amazonaws.com/msm-4.9-3225.tar>
- SHA-256: `DB89AEA07B96280C9ADBFCD886C4164C8DCB6DCE3D0D16552C8CF029841A79AA`
- Local extracted source: `msm-4.9/`

Razer also publishes the matching 9.0 MR0/MR1 audio kernel archive separately:

- Archive: `audio-kernel-3040.tar.gz`
- Official URL: <https://s3.amazonaws.com/cheryl-factory-images/audio-kernel-3040.tar.gz>
- SHA-256: `CC49940D16D7730737254573B36175745D1FB97C895C724BAC7EE9A0B07EF4BF`

The extracted source is intentionally ignored by Git because it is a large
vendor source tree. Keep this README tracked so the exact source can be fetched
and verified again.

Charging implementation files of primary interest:

- `msm-4.9/drivers/power/supply/qcom/qpnp-smb2.c`
- `msm-4.9/drivers/power/supply/qcom/smb-lib.c`
- `msm-4.9/drivers/power/supply/qcom/smb-lib.h`
- `msm-4.9/Documentation/devicetree/bindings/power/supply/qcom/qpnp-smb2.txt`

Razer board files of primary interest:

- `msm-4.9/arch/arm64/boot/dts/fih/RC2_common/sdm845-camera_rc2-pre-evt2.dtsi`
- `msm-4.9/arch/arm64/boot/dts/fih/RC2_common/sdm845-front-camera.dtsi`
- `msm-4.9/arch/arm64/boot/dts/fih/RC2_common/sdm845-audio_rc2-evb.dtsi`
- `msm-4.9/arch/arm64/boot/dts/fih/RC2_common/vibrator.dtsi`
