#!/usr/bin/env python3
"""Play FF_RUMBLE ticks on spmi_haptics so the user can pick one.
Usage: haptic_try.py [ms[:percent] ...]   (percent 1-100 = drive strength; the driver maps strong>>8 to percent)"""
import fcntl
import glob
import os
import struct
import sys
import time

dev = next(f"/dev/input/{os.path.basename(os.path.dirname(os.path.dirname(p)))}"
           for p in glob.glob("/sys/class/input/event*/device/name") if open(p).read().strip() == "spmi_haptics")
fd = os.open(dev, os.O_RDWR)
EVIOCSFF = 0x40304580
os.write(fd, struct.pack("llHHi", 0, 0, 0x15, 0x60, 0xffff))            # FF_GAIN
time.sleep(float(os.environ.get("DELAY", "3")))
for arg in sys.argv[1:] or ["40", "80", "120", "200"]:
    ms, _, pct = arg.partition(":")
    ms, pct = int(ms), int(pct or 100)
    eff = bytearray(48)
    struct.pack_into("HhH", eff, 0, 0x50, -1, 0)                        # FF_RUMBLE, id -1
    struct.pack_into("HH", eff, 10, ms, 0)                              # replay length, delay
    struct.pack_into("HH", eff, 16, min(pct, 100) << 8, 0)              # strong magnitude: driver uses >>8 as %
    fcntl.ioctl(fd, EVIOCSFF, eff)
    eid = struct.unpack_from("h", eff, 2)[0]
    os.write(fd, struct.pack("llHHi", 0, 0, 0x15, eid, 1))
    print(f"tick {ms} ms {pct}% (effect {eid})", flush=True)
    time.sleep(float(os.environ.get("GAP", "1.5")))
    fcntl.ioctl(fd, 0x40044581, eid)                                    # EVIOCRMFF
