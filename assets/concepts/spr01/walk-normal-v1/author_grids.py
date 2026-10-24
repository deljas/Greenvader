"""Author normal walk: fixed bulb/face, alternating short feet, retained leaf lag."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / "four-directions-v2"
HOP = ROOT.parent / "walk-v1"
ORDER = ("down", "left", "right", "up")


def fill(grid, y, start, end, char):
    for x in range(start, end + 1):
        grid[y][x] = char


def main():
    shutil.copyfile(SOURCE / "palette.json", ROOT / "palette.json")
    for direction in ORDER:
        neutral = (SOURCE / f"grid-{direction}.txt").read_text().splitlines()
        shutil.copyfile(SOURCE / f"grid-{direction}.txt", ROOT / f"grid-{direction}-0.txt")
        for frame in (1, 2, 3):
            grid = [list("." * 24) for _ in range(36)]
            # Every body/face/hand pixel through y31 remains at its accepted position.
            for y, row in enumerate(neutral):
                if y >= 32:
                    continue
                for x, char in enumerate(row):
                    if char in "WISEM":
                        grid[y][x] = char
            # Preserve the liked hop leaf deformation RELATIVE to the fixed bulb.
            # Only normalize its root height; no mirroring or body-height changes.
            leaves = (HOP / f"grid-{direction}-{frame}.txt").read_text().splitlines()
            root_adjust = {1: -1, 2: 2, 3: 1}[frame]
            for y, row in enumerate(leaves):
                for x, char in enumerate(row):
                    if char in "LGH":
                        target_y = y + root_adjust
                        assert 0 < target_y < 15
                        grid[target_y][x] = char
            if frame == 2:
                # Passing through the same neutral foot position between left/right steps.
                grid[32], grid[33] = list(neutral[32]), list(neutral[33])
            elif frame == 1:
                if direction in ("down", "up"):
                    fill(grid, 32, 5, 8, "W"); fill(grid, 32, 9, 10, "I")
                    fill(grid, 33, 5, 10, "I")
                    fill(grid, 32, 14, 17, "I")
                elif direction == "left":
                    fill(grid, 32, 4, 7, "W"); fill(grid, 32, 8, 9, "I")
                    fill(grid, 33, 4, 9, "I")
                    fill(grid, 32, 13, 17, "I")
                else:
                    fill(grid, 32, 4, 8, "W"); fill(grid, 32, 9, 11, "I")
                    fill(grid, 33, 4, 11, "I")
                    fill(grid, 32, 15, 18, "I")
            else:
                if direction in ("down", "up"):
                    fill(grid, 32, 6, 9, "I")
                    fill(grid, 32, 13, 16, "W"); fill(grid, 32, 17, 18, "I")
                    fill(grid, 33, 13, 18, "I")
                elif direction == "left":
                    fill(grid, 32, 6, 9, "I")
                    fill(grid, 32, 11, 15, "W"); fill(grid, 32, 16, 18, "I")
                    fill(grid, 33, 11, 18, "I")
                else:
                    fill(grid, 32, 6, 10, "I")
                    fill(grid, 32, 15, 18, "W"); fill(grid, 32, 19, 20, "I")
                    fill(grid, 33, 15, 20, "I")
            (ROOT / f"grid-{direction}-{frame}.txt").write_text("\n".join("".join(row) for row in grid) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
