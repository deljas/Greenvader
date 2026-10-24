"""Initial drafting and small per-frame pixel authoring; export.py reads saved grids only."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / "four-directions-v2"
DIRECTIONS = ("down", "left", "right", "up")


def blank():
    return [list("." * 24) for _ in range(36)]


def put(grid, x, y, char):
    assert 0 <= x < 24 and 0 <= y < 36
    grid[y][x] = char


def main():
    shutil.copyfile(SOURCE / "palette.json", ROOT / "palette.json")
    for direction in DIRECTIONS:
        original = (SOURCE / f"grid-{direction}.txt").read_text().splitlines()
        shutil.copyfile(SOURCE / f"grid-{direction}.txt", ROOT / f"grid-{direction}-0.txt")
        for frame in (1, 2, 3):
            grid = blank()
            # Body, face and hands. One upper-body row is compressed in preparation;
            # eyes are below that row, so both 1x2 eyes remain intact.
            for y, row in enumerate(original):
                for x, char in enumerate(row):
                    if char not in "WISEM":
                        continue
                    if frame == 1:
                        if y == 23:
                            continue
                        target_y = y + 1 if y <= 22 else y
                    else:
                        target_y = y - (2 if frame == 2 else 1)
                    put(grid, x, target_y, char)
            # Each leaf bends about its attached root. Tip rows lag on ascent,
            # then overshoot on descent. No reflection or alternate-facing reuse.
            for y, row in enumerate(original):
                for x, char in enumerate(row):
                    if char not in "LGH":
                        continue
                    if frame == 1:
                        target_y = y + (2 if y <= 8 else 1)
                        offset_x = (1 if x < 12 else -1) if y <= 8 else 0
                    elif frame == 2:
                        target_y = y if y <= 5 else y - (1 if y <= 10 else 2)
                        offset_x = (-1 if x < 12 else 1) if y <= 8 else 0
                    else:
                        target_y = y - (2 if y <= 8 else 1)
                        offset_x = 0
                    put(grid, x + offset_x, target_y, char)
                    if frame == 3 and y == 8:
                        # One authored bridging row preserves the two leaf blades
                        # as their tips recover faster than the roots.
                        put(grid, x, 7, char)
            # Small foot push/curl/recovery, separately authored for each view.
            if frame == 1:
                additions = {"down": [(5, 33), (18, 33)], "up": [(5, 33), (18, 33)], "left": [(11, 33), (4, 32)], "right": [(12, 33), (20, 32)]}[direction]
                for x, y in additions:
                    put(grid, x, y, "I")
            elif frame == 2:
                curled = {"down": [6, 17], "up": [6, 17], "left": [12, 18], "right": [5, 11]}[direction]
                for x in curled:
                    put(grid, x, 31, ".")
            else:
                additions = {"down": [(5, 32), (18, 32)], "up": [(5, 32), (18, 32)], "left": [(11, 32)], "right": [(12, 32)]}[direction]
                for x, y in additions:
                    put(grid, x, y, "I")
            (ROOT / f"grid-{direction}-{frame}.txt").write_text("\n".join("".join(row) for row in grid) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
