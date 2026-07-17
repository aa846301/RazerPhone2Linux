# Camera, audio, and haptics status (2026-07-17)

## Camera audit of `85aeb9a6d`

Both preview paths are represented end to end in the source:

- rear IMX363: CCI0 -> CSIPHY0 -> CSID0 -> VFE0 RDI0;
- front S5K3H7: CCI1 -> CSIPHY2 -> CSID0 -> VFE0 RDI0;
- the experimental control panel resets/configures the media graph and renders
  1920x1080 RAW10 frames for either sensor.

This is preview bring-up, not a complete camera stack. There is no recorded
on-device success in the repository and no 3A, still capture, recording,
rear-telephoto, autofocus, OIS, or framework integration. The audit also found
and fixed the S5K3H7 crop-height response using `width` instead of `height`.

## Haptics source and port

The official Android 9 SMR7 source is present at
`vendor-source/razer-phone2-smr7/msm-4.9/`. Its PMI8998 DTS node describes the
integrated LRA haptics peripheral at `0xc000`, and both Cheryl2 defconfigs enable
Qualcomm PMIC haptics. The mainline equivalent is `qcom-spmi-haptics`, exposed
through Linux force feedback.

The aura DTS now enables `pmi8998_haptics` with the downstream 6667 us period,
and the kernel fragment builds the force-feedback driver as a module. Validate
with `scripts/diagnostics/phone-test-haptics.sh` before checking off support.

## Audio source and port

The known mainline path is ADSP/QDSP6 + SLIMbus + WCD9340 (tavil). The DTS
already contained an SDM845 sound-card graph copied from the proven OnePlus
mainline structure, but deliberately disabled SLIM, the card, and the codec.
They are now enabled and `SND_SOC_WCD934X` is explicit in the kernel fragment.

The public SMR7 archive includes Cheryl2 defconfigs and common Qualcomm audio
code, but not the proprietary Cheryl2 board DTS needed to prove every physical
route or any external speaker amplifier. Therefore this change targets ALSA
card/codec enumeration first and does not claim that speakers, microphones,
earpiece, or USB-C audio are complete. Validate with
`scripts/diagnostics/phone-test-audio.sh`, `aplay -l`, mixer inspection, and
audio-related `dmesg` output.
