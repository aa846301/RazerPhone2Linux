# ARM64 runtime binaries

These small binaries are pinned because the live SDM845 WiFi path depends on
the exact tested behavior and validation refreshes must not download or rebuild
userspace.

SHA-256:

```text
d17f09881a3f65ee724e962fe7d92011a4123dc764b214da60e69fd1eaca34e4  arm64/pd-mapper
d20d5cb9bf3fa37de6f2f155cff67d29287c2ac5ad59e1913eebe90a63520bb3  arm64/rmtfs-razer-test
c103b1d28aa9514a835bcba7380ce7e838f26439e328deeb752470bd8e92a4ad  arm64/tqftpserv
```

Long-term maintenance should add reproducible source-build recipes and submit
the tqftpserv Android firmware-path change upstream. Until then, changing one
of these files requires updating this checksum list and validating a cold boot.
