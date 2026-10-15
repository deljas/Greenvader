"""P1-06 independent map check: own PNG decoder (zlib only), BFS over 4-neighbour tiles and over foot positions.
Usage: python -I tests/p1/independent/p1_06_map.py <png> <out.json>
Terrain colours are taken from the spec'd terrain map_color values (data/terrain/*.tres), rounded to 8 bit.
"""
import json, struct, sys, zlib
from collections import deque

def decode(path):
    raw = open(path, "rb").read()
    assert raw[:8] == b"\x89PNG\r\n\x1a\n"
    pos, idat, hdr = 8, b"", None
    while pos < len(raw):
        ln, kind = struct.unpack(">I4s", raw[pos:pos + 8]); body = raw[pos + 8:pos + 8 + ln]
        if kind == b"IHDR": hdr = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT": idat += body
        pos += 12 + ln
    w, h, depth, ctype, _, _, interlace = hdr
    assert depth == 8 and interlace == 0 and ctype in (2, 6), hdr
    bpp = 3 if ctype == 2 else 4
    data = zlib.decompress(idat)
    stride = w * bpp
    rows, prev = [], bytearray(stride)
    p = 0
    for _y in range(h):
        f = data[p]; line = bytearray(data[p + 1:p + 1 + stride]); p += 1 + stride
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]; c = prev[i - bpp] if i >= bpp else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        rows.append(line); prev = line
    return w, h, bpp, rows

COL = {(176, 160, 96): "wasteland", (96, 176, 96): "safe", (224, 208, 144): "shore",
       (64, 128, 224): "water", (128, 128, 128): "building", (112, 176, 224): "shallows"}
TARGET = {"wasteland", "safe", "shore"}
WALK = {"wasteland", "safe", "shore", "shallows"}

def main():
    path, out = sys.argv[1], sys.argv[2]
    w, h, bpp, rows = decode(path)
    g = [[None] * w for _ in range(h)]
    unknown = 0
    for y in range(h):
        r = rows[y]
        for x in range(w):
            c = (r[x * bpp], r[x * bpp + 1], r[x * bpp + 2])
            t = COL.get(c)
            if t is None: unknown += 1
            g[y][x] = t
    counts = {}
    for y in range(h):
        for x in range(w):
            counts[g[y][x]] = counts.get(g[y][x], 0) + 1
    start = (184, 188)
    targets = sum(counts.get(k, 0) for k in TARGET)

    def bfs(blocked_extra=()):
        seen = [bytearray(w) for _ in range(h)]
        q = deque([start]); seen[start[1]][start[0]] = 1; n = 0
        while q:
            x, y = q.popleft(); n += 1
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx]:
                    t = g[ny][nx]
                    if t in WALK and t not in blocked_extra:
                        seen[ny][nx] = 1; q.append((nx, ny))
        return seen, n
    seen, nwalk = bfs()
    seen_nf, nwalk_nf = bfs(("shallows",))
    def tcount(s):
        return sum(1 for y in range(h) for x in range(w) if s[y][x] and g[y][x] in TARGET)
    reach_t, reach_t_nf = tcount(seen), tcount(seen_nf)
    # islands: connected components of walkable tiles not reached, containing targets
    comp = [bytearray(w) for _ in range(h)]
    islands = []
    for y0 in range(h):
        for x0 in range(w):
            if g[y0][x0] in WALK and not seen[y0][x0] and not comp[y0][x0]:
                q = deque([(x0, y0)]); comp[y0][x0] = 1; tiles = 0; tg = 0
                while q:
                    x, y = q.popleft(); tiles += 1
                    if g[y][x] in TARGET: tg += 1
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < w and 0 <= ny < h and g[ny][nx] in WALK and not seen[ny][nx] and not comp[ny][nx]:
                            comp[ny][nx] = 1; q.append((nx, ny))
                if tg > 0: islands.append({"walk_tiles": tiles, "targets": tg, "seed_xy": [x0, y0]})
    # shallows components and what each connects
    sh = [bytearray(w) for _ in range(h)]
    fords = []
    for y0 in range(h):
        for x0 in range(w):
            if g[y0][x0] == "shallows" and not sh[y0][x0]:
                q = deque([(x0, y0)]); sh[y0][x0] = 1; tiles = 0; xs = []; ys = []
                while q:
                    x, y = q.popleft(); tiles += 1; xs.append(x); ys.append(y)
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < w and 0 <= ny < h and g[ny][nx] == "shallows" and not sh[ny][nx]:
                            sh[ny][nx] = 1; q.append((nx, ny))
                fords.append({"tiles": tiles, "x": [min(xs), max(xs)], "y": [min(ys), max(ys)]})
    # east bank = targets reachable only by crossing shallows
    east = reach_t - reach_t_nf
    # foot-based reachability on a 1 px grid: foot 6x4 around integer pixel position p is clear when all covered tiles walkable
    def clear(px, py):
        x0 = (px - 3) // 4; x1 = (px + 3 - 1) // 4  # covers [px-3, px+3)
        y0 = (py - 2) // 4; y1 = (py + 2 - 1) // 4
        for ty in range(y0, y1 + 1):
            if ty < 0 or ty >= h: return False
            for tx in range(x0, x1 + 1):
                if tx < 0 or tx >= w or g[ty][tx] not in WALK: return False
        return True
    W, H = w * 4, h * 4
    fseen = bytearray(W * H)
    sp = (start[0] * 4 + 2, start[1] * 4 + 2)
    q = deque([sp]); fseen[sp[1] * W + sp[0]] = 1
    assert clear(*sp)
    while q:
        px, py = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = px + dx, py + dy
            if 0 <= nx < W and 0 <= ny < H and not fseen[ny * W + nx] and clear(nx, ny):
                fseen[ny * W + nx] = 1; q.append((nx, ny))
    foot_t = 0; foot_tiles = 0
    for y in range(h):
        for x in range(w):
            if g[y][x] in WALK:
                hit = False
                for sy in range(4):
                    base = (y * 4 + sy) * W + x * 4
                    if any(fseen[base:base + 4]): hit = True; break
                if hit:
                    foot_tiles += 1
                    if g[y][x] in TARGET: foot_t += 1
    res = {"size": [w, h], "unknown_pixels": unknown, "counts": counts, "targets": targets,
           "tile_bfs_walk_tiles": nwalk, "tile_bfs_reach_targets": reach_t,
           "no_shallows_reach_targets": reach_t_nf, "east_bank_targets_via_fords": east,
           "islands": islands, "island_count": len(islands), "island_targets_total": sum(i["targets"] for i in islands),
           "island_walk_tiles_total": sum(i["walk_tiles"] for i in islands),
           "shallows_components": fords, "foot_bfs_reach_targets": foot_t, "foot_bfs_tiles": foot_tiles,
           "start_terrain": g[start[1]][start[0]]}
    json.dump(res, open(out, "w"), indent=1)
    print(json.dumps({k: v for k, v in res.items() if k not in ("islands",)}))
main()
