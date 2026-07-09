#!/usr/bin/env python3
"""Panel bring-up sanity check: fill /dev/fb0 with solid colors.

Full-screen solid color removes all ambiguity that scrolling console text
leaves ("is this garbled because of font rendering or because of DSC/format
corruption?"). If a solid red fill shows up as anything other than solid red,
the fault is in the display pipeline (DSC config, DSI clock, pixel format),
not in whatever content was being drawn.

Usage: razer-panel-colortest [--once COLOR] [--interval SECONDS]
  No args: cycle red -> green -> blue -> white -> black forever.
  --once red: fill once and exit (for scripted / SSH-driven testing).
"""
import argparse
import mmap
import os
import sys
import time

FB = "/dev/fb0"
SYSFS = "/sys/class/graphics/fb0"

# DRM_FORMAT_XRGB8888 stored little-endian: byte order in memory is B,G,R,X.
COLORS = {
    "red":   (0x00, 0x00, 0xFF, 0x00),
    "green": (0x00, 0xFF, 0x00, 0x00),
    "blue":  (0xFF, 0x00, 0x00, 0x00),
    "white": (0xFF, 0xFF, 0xFF, 0x00),
    "black": (0x00, 0x00, 0x00, 0x00),
}


def read_geometry():
    with open(f"{SYSFS}/virtual_size") as f:
        width, height = (int(x) for x in f.read().strip().split(","))
    with open(f"{SYSFS}/bits_per_pixel") as f:
        bpp = int(f.read().strip())
    if bpp != 32:
        print(f"WARNING: fb0 is {bpp}bpp, this tool assumes 32bpp XRGB8888", file=sys.stderr)
    return width, height, bpp


def write_frame(data):
    """mmap /dev/fb0 and write through the mapping.

    DRM fbdev emulation drives its flush via deferred I/O, which detects
    dirty pages through mmap() page faults. A plain write() syscall to the
    character device lands in the shadow buffer but never trips that page-
    fault detection, so nothing ever gets flushed to the panel -- the
    screen just keeps showing whatever frame was last actually committed.
    mmap + memoryview assignment (a real memory store, not a syscall) is
    what deferred I/O is designed to see.
    """
    fd = os.open(FB, os.O_RDWR)
    try:
        size = len(data)
        m = mmap.mmap(fd, size, prot=mmap.PROT_WRITE | mmap.PROT_READ)
        try:
            m[:] = data
            m.flush()
        finally:
            m.close()
    finally:
        os.close(fd)


def fill(name):
    width, height, bpp = read_geometry()
    pixel = bytes(COLORS[name])
    size = width * height * (bpp // 8)
    print(f"razer-panel-colortest: filling {name} ({width}x{height}, {size} bytes)")
    write_frame(pixel * (size // len(pixel)))


def split_halves(left_name, right_name, border=20):
    """Left half one color, right half another, with a white border frame
    and a black column at the exact horizontal center. Lets you map buffer
    coordinates to physical screen regions directly: which color(s) appear
    where, whether the center column lines up, whether edges/corners are
    cropped or offset — all readable straight off the panel.
    """
    width, height, bpp = read_geometry()
    left = COLORS[left_name]
    right = COLORS[right_name]
    white = COLORS["white"]
    black = COLORS["black"]
    half = width // 2
    print(f"razer-panel-colortest: split {left_name}|{right_name} "
          f"({width}x{height}, border={border}px, center column marked black)")

    white_row = bytes(white) * width
    body_row = (
        bytes(white) * border
        + bytes(left) * (half - border - 1)
        + bytes(black) * 2
        + bytes(right) * (half - border - 1)
        + bytes(white) * border
    )
    assert len(body_row) == width * 4, (len(body_row), width * 4)

    frame = bytearray(width * height * 4)
    row_bytes = width * 4
    for y in range(height):
        row = white_row if (y < border or y >= height - border) else body_row
        frame[y * row_bytes:(y + 1) * row_bytes] = row
    write_frame(bytes(frame))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--once", choices=sorted(COLORS), help="fill one color and exit")
    ap.add_argument("--interval", type=float, default=3.0, help="seconds per color when cycling")
    ap.add_argument("--split", nargs=2, metavar=("LEFT", "RIGHT"), choices=sorted(COLORS),
                     help="left half one color, right half another, white border, "
                          "black center column -- maps buffer coords to screen regions")
    ap.add_argument("--border", type=int, default=20, help="border width in px for --split")
    args = ap.parse_args()

    if args.split:
        split_halves(args.split[0], args.split[1], border=args.border)
        return

    if args.once:
        fill(args.once)
        return

    print("razer-panel-colortest: cycling colors forever (Ctrl-C or systemctl stop to end)")
    order = ["red", "green", "blue", "white", "black"]
    while True:
        for name in order:
            fill(name)
            time.sleep(args.interval)


if __name__ == "__main__":
    main()
