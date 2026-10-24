"""Normal v2: one-pixel weight shift, independently swinging peel hands, planted feet."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / "four-directions-v2"
V1 = ROOT.parent / "walk-normal-v1"
ORDER = ("down", "left", "right", "up")
# Explicit peel-hand pixels, separate from the torso; screen-left and screen-right.
HANDS = {
    "down": [[(2,26),(1,27),(2,27),(2,28)],[(21,26),(21,27),(22,27),(21,28)]],
    "left": [[(2,25)],[(17,27),(18,27),(19,27),(20,27),(21,27),(16,28),(17,28),(18,28),(19,28),(20,28),(21,28)]],
    "right": [[(2,27),(2,28),(3,28),(4,28),(5,28),(6,28)],[(22,25)]],
    "up": [[(2,25),(1,26),(2,26)],[(21,25),(21,26),(22,26)]],
}


def main():
    shutil.copyfile(SOURCE / "palette.json", ROOT / "palette.json")
    for direction in ORDER:
        neutral = (SOURCE / f"grid-{direction}.txt").read_text().splitlines()
        shutil.copyfile(SOURCE / f"grid-{direction}.txt", ROOT / f"grid-{direction}-0.txt")
        for frame in (1,2,3):
            prior = (V1 / f"grid-{direction}-{frame}.txt").read_text().splitlines()
            grid = [list("." * 24) for _ in range(36)]
            dy = 1 if frame in (1,3) else 0
            torso = [list(row) for row in neutral]
            if dy:
                for group in HANDS[direction]:
                    for x,y in group:
                        torso[y][x] = "."
                # Restore the solid bulb plane beneath internal peel folds.
                if direction == "left":
                    for x in range(17,21): torso[27][x] = "S"
                    for x in range(16,21): torso[28][x] = "I" if x == 16 else "S"
                elif direction == "right":
                    for x in range(3,7): torso[28][x] = "I"
            for y,row in enumerate(torso):
                if y >= 32: continue
                for x,char in enumerate(row):
                    if char in "WISEM":
                        grid[y+dy][x] = char
            for y,row in enumerate(prior):
                for x,char in enumerate(row):
                    if char in "LGH":
                        grid[y+dy][x] = char
            if dy:
                hand_dys = (-1,1) if frame == 1 else (1,-1)
                for side,group in enumerate(HANDS[direction]):
                    relative = hand_dys[side]
                    # Lowered skin flaps tuck one pixel inward to stay attached.
                    tuck = (1 if side == 0 else -1) if relative > 0 and len(group) > 1 else 0
                    for x,y in group:
                        tx,ty = x+tuck, y+dy+relative
                        grid[ty][tx] = neutral[y][x]
            # Planted alternating feet remain in their two authored bottom rows.
            grid[32],grid[33] = list(prior[32]),list(prior[33])
            (ROOT/f"grid-{direction}-{frame}.txt").write_text("\n".join("".join(row) for row in grid)+"\n",encoding="utf-8")


if __name__ == "__main__":
    main()
