# Razer Phone 2 EFS / FSG Check - 2026-06-10

## Summary

This check was done read-only over SSH after the phone booted Linux. It answers
whether blank `fsg` / `fsc` alone is enough reason to flash Android before
continuing WiFi/MSS debugging.

Current conclusion: do **not** flash Android just to validate WiFi/FSG yet.
The factory 3201 package does not contain `fsg.img`, `fsc.img`, or
`modemst*.img`; its stock flashing script only flashes `nvdef_a` and
`nvdef_b` from `nvdef.img`. The live phone's `nvdef_a/b` prefix matches the
factory `nvdef.img` exactly, while `modemst1/2` contain valid `IMGEFS1/2`
headers and non-zero data.

## Phone State

Remoteproc state at the time of the check:

```text
remoteproc0 cdsp running
remoteproc1 adsp running
remoteproc2 slpi running
remoteproc3 4080000.remoteproc crashed
```

Partition snapshot:

```text
modemst1 size=2097152 sha256=79f39404638623479b1e1373c786d09e9cd73df0981978dfe6b387614755d743 nonzero_first8MiB=2088464
modemst2 size=2097152 sha256=d2ab58099ca7132ac436db84cd71a26dbdc1b27246ebd40c2093868aa29f859e nonzero_first8MiB=2088443
fsg     size=2097152 sha256=5647f05ec18958947d32874eeb788fa396a05d0bab7c1b71f112ceb7e9b31eee nonzero_first8MiB=0
fsc     size=131072  sha256=fa43239bcee7b97ca62f007cc68487560a39e19f74f3dde7486db3f98df8e471 nonzero_first8MiB=0
nvdef_a size=4194304 sha256=829d5eb102cf0614f5a3f46b2cc7b0f516e967fcd046c03e3f4acee290cb2ce0 nonzero_first8MiB=418854
nvdef_b size=4194304 sha256=829d5eb102cf0614f5a3f46b2cc7b0f516e967fcd046c03e3f4acee290cb2ce0 nonzero_first8MiB=418854
persist size=33554432 sha256=2aaabb7be805e8cf573d75b7f5c9c8ddf2746b5fc6e52ddd88ab48c5b66a9c85 nonzero_first8MiB=461796
```

`modemst1` starts with `IMGEFS1`; `modemst2` starts with `IMGEFS2`. These are
not wiped.

## Factory Package Check

Factory package:

```text
aura-p-release-3201-user-full/aura-p-release-3201/
```

Relevant files:

```text
nvdef.img present, sha256=c4c6118bd70ce1f4a31333e257dccf7ee1ec153af7b9f67cc9d0c26f4197f540
fsg.img absent
fsc.img absent
modemst1.img absent
modemst2.img absent
```

`flash_all.sh` relevant lines:

```text
fastboot flash persist persist.img
fastboot flash modem_a modem.img
fastboot flash modem_b modem.img
fastboot flash dsp_a dsp.img
fastboot flash dsp_b dsp.img
...
fastboot flash nvdef_a nvdef.img
fastboot flash nvdef_b nvdef.img
fastboot erase userdata
```

Live `nvdef_a/b` prefix hash for the factory image length
(`1413632` bytes) matches factory `nvdef.img`:

```text
nvdef_a_prefix_sha256=c4c6118bd70ce1f4a31333e257dccf7ee1ec153af7b9f67cc9d0c26f4197f540
nvdef_b_prefix_sha256=c4c6118bd70ce1f4a31333e257dccf7ee1ec153af7b9f67cc9d0c26f4197f540
```

## QMI/RFS Boundary

`razer_qmi_dump.xml` contains successful RFS path activity for:

```text
modem_fs1
modem_fs2
modem_fsg
modem_fsc
modem_fsg_oem_1
modem_fsg_oem_2
tms/pddump_disabled -> msm/modem/root_pd
```

It does not show progress to:

```text
wlan/fw
kernel/elf_loader
WLFW
```

So blank `fsg/fsc` is a remaining content question, not a proven immediate
cause. The observed fatal still happens after RFS opens/reads and the
`tms/pddump_disabled` lookup, before the WLAN PD / firmware-loader stage.

## Backup

Read-only backup saved locally:

```text
output/efs-backup-19700120-022620.tar.gz
```

The timestamp comes from the phone's unset RTC and is not meaningful.

## Decision

Do not flash Android as the next step solely because `fsg/fsc` are blank.
Android flashing would change multiple variables and may overwrite useful
evidence. Revisit Android only if one of these becomes true:

- a Razer stock source proves `fsg/fsc` should be non-zero on this model;
- Android `rmt_storage` logs prove the modem requires a non-empty `fsg/fsc`
  record before WLAN PD appears;
- a controlled restore of only EFS/NV content is planned and the current backup
  can be restored.
