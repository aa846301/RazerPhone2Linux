# Razer Phone 2 MSS IMEM Diagnostic - 2026-06-09

## Summary

An IMEM-only MSS crash diagnostic was built and tested. It does not trigger
DLOAD/EDL and does not read MPSS memory. The goal was to capture low-risk
shared IMEM state from the MSS fatal interrupt path.

Artifacts:

- Patch: `kernel-patches/0004-razor-aura-mss-imem-crash-snapshot.patch`
- Boot image: `output/boot.img`
- Live modules:
  - `output/live-modules/imem-diag/qcom_q6v5.ko`
  - `output/live-modules/imem-diag/qcom_q6v5_mss.ko`
- Evidence bundle: `output/mss-imem-diag-2026-06-09.tar.gz`

The boot cmdline included:

```text
razer_mss_imem_diag=1
```

The deployed module hashes were:

```text
d0d2090ae7ebb43746f5287fae984a21653b9601a547b38fcf2e0506c3e2f583  qcom_q6v5.ko
899d3373af2e436888a9eb2eddaaa1c21417c572f8f6c14e5fbfb9efde24c6f2  qcom_q6v5_mss.ko
```

## Result

The IMEM diagnostic worked. On MSS fatal, dmesg printed:

```text
mss rmb snapshot fatal: image=0x96500000 pbl=0x00000001 cmd=0x00000000 mba=0x00000004
mss rmb snapshot fatal: mss_status=0x0000000b alt_reset=0x00000000
mss imem snapshot fatal: range=head offset=0x000 len=0x40
mss imem snapshot fatal: range=dload_type offset=0x01c len=0x10
mss imem snapshot fatal: range=diag_dload offset=0x0c8 len=0xc8
mss imem snapshot fatal: range=restart_reason offset=0x65c len=0x10
mss imem snapshot fatal: range=boot_stats offset=0x6b0 len=0x20
mss imem snapshot fatal: range=pil offset=0x94c len=0xc8
fatal error without message (smem 421 err -2 len 0 state 2)
```

The `pil@94c` region decoded correctly as the PIL relocation table:

```text
adsp   base=0x8c500000 size=0x01a00000
cdsp   base=0x95d00000 size=0x00800000
slpi   base=0x96700000 size=0x01400000
modem  base=0x8e000000 size=0x07800000
```

This confirms the IMEM mapping is correct and matches the known reserved
regions. It does not expose an MSS internal assertion string.

## Interpretation

- IMEM is readable from the fatal path and does not trigger the TrustZone/XPU
  abort that occurred when attempting to read MPSS memory.
- The PIL relocation table is valid, so the `pil@94c` IMEM region is useful for
  confirming subsystem memory placement.
- `diag_dload@c8` and `restart_reason@65c` contain non-zero binary data but no
  obvious ASCII/F3 fatal message.
- SMEM item 421 remains absent, so the modem still does not publish a normal SSR
  reason before fatal.
- The crash boundary is unchanged: MSS reaches running, answers
  `tms/pddump_disabled`, then fatal-errors before WLFW, `wlan/fw`, or
  `kernel/elf_loader`.

## Next Direction

This test narrows the useful diagnostic paths:

- Do not repeat SMEM item 421 reads, generic remoteproc coredump, or MPSS memory
  pre-stop copying as standalone paths.
- IMEM alone is not enough to identify the MSS internal assertion.
- The next high-value paths are:
  - decode downstream Razer minidump/ramdump structures;
  - implement a controlled DLOAD opt-in path;
  - add QRTR/GLINK/PDR packet timing instrumentation around the final
    `tms/pddump_disabled` request and MSS fatal.
