# ARM64 package overlay

`arm64/tqftpserv_1.0-5_arm64.deb` supplies the distro service/package metadata.
The tested v1.2-compatible executable from `rootfs-binaries/arm64/tqftpserv`
replaces its binary afterward.

`arm64/qbootctl_0.2.2-1_arm64.deb` is the Debian ARM64 build of the
linux-msm qbootctl utility. Its systemd service marks a completed Qualcomm A/B
boot successful so ordinary reboots do not exhaust the active slot retry
counter. Source: https://github.com/linux-msm/qbootctl

SHA-256:

```text
71f7bf0a95c0dfe79f4eb2c1f41b758bb763031061e78185003f20ba93525d5e  arm64/tqftpserv_1.0-5_arm64.deb
76b9be97107f14a79641bc274a00010aade3362b5099df5ae8b85603cbb6eb22  arm64/qbootctl_0.2.2-1_arm64.deb
```
