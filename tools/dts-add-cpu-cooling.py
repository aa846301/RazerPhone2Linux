#!/usr/bin/env python3
"""Add software CPU thermal throttling to a decompiled SDM845 DTS.

Mainline sdm845.dtsi has passive trips (90/95 C) on the cpuN-thermal zones but
no cooling-maps: it relies on the LMh hardware limiter, which only clamps at
95 C. On the Razer Phone 2 a sustained LLM load sat at ~97 C.

This edits the text produced by `dtc -I dtb -O dts` (so every other byte of the
DTB stays as it was) and, for every cpuN-thermal zone, adds passive trips at
WARM and HOT millicelsius bound to that cluster's cpufreq cooling device
(the CPU nodes, #cooling-cells = 2) with THERMAL_NO_LIMIT limits. step_wise
then lowers the cluster frequency one OPP at a time above WARM.

Usage: dts-add-cpu-cooling.py IN.dts OUT.dts [WARM=80000] [HOT=88000]
"""
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
warm = int(sys.argv[3]) if len(sys.argv) > 3 else 80000
hot = int(sys.argv[4]) if len(sys.argv) > 4 else 88000
t = open(src).read()

# cpu node phandles (cpus { cpu@0 { ... phandle = <0x..>; ... } })
cpus = {}
for m in re.finditer(r"\n\t\tcpu@(\d+) \{(.*?)\n\t\t\};", t, re.S):
    body = m.group(2)
    ph = re.search(r"\tphandle = <(0x[0-9a-f]+)>;", body)
    if "#cooling-cells" not in body:
        sys.exit(f"cpu@{m.group(1)} has no #cooling-cells")
    cpus[int(m.group(1), 16) // 0x100] = ph.group(1)
if sorted(cpus) != list(range(8)):
    sys.exit(f"unexpected cpu nodes: {cpus}")

used = {int(x, 16) for x in re.findall(r"phandle = <(0x[0-9a-f]+)>;", t)}
nxt = max(used) + 1
NOLIM = "0xffffffff 0xffffffff"
count = 0
for n in range(8):
    m = re.search(r"\n(\t\t)cpu%d-thermal \{\n(.*?)\n\t\t\};" % n, t, re.S)
    if not m:
        sys.exit(f"cpu{n}-thermal not found")
    body = m.group(2)
    if "cooling-maps" in body:
        sys.exit(f"cpu{n}-thermal already has cooling-maps")
    cluster = range(0, 4) if n < 4 else range(4, 8)
    pw, ph = nxt, nxt + 1
    nxt += 2
    trips_add = (f"\n\t\t\t\ttrip-razer-warm {{\n\t\t\t\t\thysteresis = <0x7d0>;\n\t\t\t\t\ttemperature = <{warm:#x}>;\n"
                 f"\t\t\t\t\ttype = \"passive\";\n\t\t\t\t\tphandle = <{pw:#x}>;\n\t\t\t\t}};\n"
                 f"\n\t\t\t\ttrip-razer-hot {{\n\t\t\t\t\thysteresis = <0x7d0>;\n\t\t\t\t\ttemperature = <{hot:#x}>;\n"
                 f"\t\t\t\t\ttype = \"passive\";\n\t\t\t\t\tphandle = <{ph:#x}>;\n\t\t\t\t}};\n")
    devs = ", ".join(f"<{cpus[c]} {NOLIM}>" for c in cluster)
    maps = (f"\n\t\t\tcooling-maps {{\n"
            f"\t\t\t\tmap-razer-warm {{\n\t\t\t\t\ttrip = <{pw:#x}>;\n\t\t\t\t\tcooling-device = {devs};\n\t\t\t\t}};\n"
            f"\t\t\t\tmap-razer-hot {{\n\t\t\t\t\ttrip = <{ph:#x}>;\n\t\t\t\t\tcooling-device = {devs};\n\t\t\t\t}};\n"
            f"\t\t\t}};")
    new_body = body.replace("\t\t\ttrips {\n", "\t\t\ttrips {\n" + trips_add, 1)
    if new_body == body:
        sys.exit(f"cpu{n}-thermal has no trips block")
    new_body += maps
    t = t[:m.start(2)] + new_body + t[m.end(2):]
    count += 1
open(dst, "w").write(t)
print(f"added cooling to {count} zones (warm {warm}, hot {hot}); cpu phandles {cpus}")
