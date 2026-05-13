#!/usr/bin/env python3
import os

dts = os.path.expanduser("~/razorphone2linux/fw-extract-tmp/dtbo-out/dtbo-entry-00.dts")

with open(dts) as f:
    lines = f.readlines()

# NT36830 main panel node starts at line 8985 (1-indexed)
start = 8984  # 0-indexed
end = min(start + 220, len(lines))
for i, line in enumerate(lines[start:end], start+1):
    print(f"{i}: {line}", end="")
