"""Independent map counter: decodes the region PNG with zlib only (no Godot, no Pillow) and counts RGB colours.
Usage: python -I tests/p1/count_png.py data/region_01.png > evidence/p1/p1-01/png_counts.json
"""
import json
import struct
import sys
import zlib
from collections import Counter


def decode(path):
    raw = open(path, "rb").read()
    assert raw[:8] == b"\x89PNG\r\n\x1a\n"
    pos, idat, header = 8, b"", None
    while pos < len(raw):
        length, kind = struct.unpack(">I4s", raw[pos:pos + 8])
        body = raw[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    width, height, depth, color_type, _, _, interlace = header
    assert depth == 8 and interlace == 0 and color_type in (2, 6), header
    bpp = 3 if color_type == 2 else 4
    data = zlib.decompress(idat)
    stride = width * bpp
    rows, previous = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        mode, line = data[start], bytearray(data[start + 1:start + 1 + stride])
        for i in range(stride):
            left = line[i - bpp] if i >= bpp else 0
            up = previous[i]
            upleft = previous[i - bpp] if i >= bpp else 0
            if mode == 1:
                line[i] = (line[i] + left) & 255
            elif mode == 2:
                line[i] = (line[i] + up) & 255
            elif mode == 3:
                line[i] = (line[i] + (left + up) // 2) & 255
            elif mode == 4:
                p = left + up - upleft
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - upleft)
                pred = left if pa <= pb and pa <= pc else (up if pb <= pc else upleft)
                line[i] = (line[i] + pred) & 255
        rows.append(line)
        previous = line
    return width, height, bpp, rows


width, height, bpp, rows = decode(sys.argv[1])
counts = Counter()
for line in rows:
    for x in range(width):
        counts["%02x%02x%02x" % tuple(line[x * bpp:x * bpp + 3])] += 1
print(json.dumps({"width": width, "height": height, "counts": counts}, indent=1))
