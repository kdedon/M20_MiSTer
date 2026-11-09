#!/usr/bin/env python3
"""Convert binary PPM (P6) frames to PNG with zlib only.

  ppm2png.py in.ppm [out.png] [--scale N]
Lines are doubled by default (the M20 shows 512 x 256 on a 4:3 screen).
"""
import struct
import sys
import zlib


def read_ppm(path):
    data = open(path, "rb").read()
    fields, pos = [], 0
    while len(fields) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        start = pos
        while not data[pos:pos + 1].isspace():
            pos += 1
        fields.append(data[start:pos])
    pos += 1
    if fields[0] != b"P6":
        sys.exit("ppm2png: not a P6 file")
    w, h = int(fields[1]), int(fields[2])
    return w, h, data[pos:pos + w * h * 3]


def write_png(path, w, h, rows):
    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body))
    raw = b"".join(b"\x00" + r for r in rows)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    vscale = 2
    if "--scale" in sys.argv:
        vscale = int(sys.argv[sys.argv.index("--scale") + 1])
        args = [a for a in args if a != str(vscale)]
    src = args[0]
    dst = args[1] if len(args) > 1 else src.rsplit(".", 1)[0] + ".png"
    w, h, pix = read_ppm(src)
    rows = []
    for y in range(h):
        r = pix[y * w * 3:(y + 1) * w * 3]
        rows.extend([r] * vscale)
    write_png(dst, w, h * vscale, rows)
    print(dst)


if __name__ == "__main__":
    main()
