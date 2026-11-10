#!/usr/bin/env python3
"""Disassemble one function of a raw arm64 kernel Image using a kallsyms dump (from kallsyms_extract.py).
Branch targets are annotated with symbol names; `--calls` prints only bl/b-to-other-function lines.
usage: kdis.py <Image> <kallsyms.txt> <function> [--calls]   (needs aarch64-linux-gnu-objdump)"""
import bisect
import re
import subprocess
import sys

image, ksyms, func = sys.argv[1:4]
calls_only = "--calls" in sys.argv
syms = []
for line in open(ksyms):
    a, t, name = line.split(None, 2)
    syms.append((int(a, 16), name.strip()))
syms.sort()
addrs = [a for a, _ in syms]
text = next(a for a, nm in syms if nm == "_text")
start = next(a for a, nm in syms if nm == func)
i = bisect.bisect_right(addrs, start)
end = addrs[i]


def name_of(addr):
    j = bisect.bisect_right(addrs, addr) - 1
    a, nm = syms[j]
    return nm if a == addr else f"{nm}+{addr - a:#x}"


out = subprocess.run(["aarch64-linux-gnu-objdump", "-D", "-b", "binary", "-m", "aarch64", f"--adjust-vma={text:#x}",
                      f"--start-address={start:#x}", f"--stop-address={end:#x}", "--no-show-raw-insn", image],
                     capture_output=True, text=True).stdout
print(f"{func}: {start:#x}..{end:#x} ({end - start} bytes)")
for line in out.splitlines():
    m = re.match(r"\s*([0-9a-f]+):\s+(.*)", line)
    if not m:
        continue
    addr, ins = int(m.group(1), 16), m.group(2)
    tm = re.search(r"\b(bl|b|b\.\w+|cbz|cbnz|tbz|tbnz)\s+(?:.*,\s*)?0x([0-9a-f]+)", ins)
    if tm:
        tgt = int(tm.group(2), 16)
        local = start <= tgt < end
        if calls_only and (local or tm.group(1) not in ("bl", "b")):
            continue
        ins = re.sub(r"0x[0-9a-f]+\s*$", "", ins) + (f"{tgt - start:#x}" if local else f"<{name_of(tgt)}>")
    elif calls_only:
        continue
    print(f"  {addr - start:5x}: {ins}")
