"""Record runtime exact-copy / preserved inputs, and a crop of the four real GPU captures."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[3]
OUT = REPO / "evidence/spr01/walk-normal-v2/self"
PLAYER = REPO / "assets/sprites/poc/player"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    protected = {
        "assets/sprites/poc/player/idle.png": "754a97bd44912a87bf2197ce74dfdca8cdf4b01a835f88c7b1ba99b1d8e029fe",
        "assets/sprites/poc/player/walk-hop.png": "77357397cf258da39457ad66ec451522c75f3553f66f156852dd4669c3bb635c",
        "assets/sprites/poc/player/walk-normal.png.import": "d51352c3f9289a8c941ddd0e63744d8e29e7fa7328e9d6efa73fbdaba286a504",
        "assets/concepts/spr01/walk-normal-v1/sheet.png": "a9ba10fbbf66538197b8b08b2ec3344042f7e2153a6117a2f7f68737f9698c5e",
        "assets/concepts/spr01/front-pixel-v1/front-16x24.png": "f188d843f64c3d2c54f1442deff625ddee920d6af14b59c64a8ec422976efffc",
    }
    for relative, expected in protected.items():
        assert sha(REPO / relative) == expected, relative
    assert (ROOT / "sheet.png").read_bytes() == (PLAYER / "walk-normal.png").read_bytes()
    manifest = json.loads((PLAYER / "manifest.json").read_text(encoding="utf-8-sig"))
    assert manifest["source_directories"]["normal"] == "assets/concepts/spr01/walk-normal-v2/"
    # Exact hand destinations are part of the authored revision, not an inferred centroid.
    from author_grids import HANDS
    hand_evidence = []
    for direction in ("down","left","right","up"):
        original = (ROOT.parent / "four-directions-v2" / f"grid-{direction}.txt").read_text().splitlines()
        for frame in (1,3):
            rows = (ROOT / f"grid-{direction}-{frame}.txt").read_text().splitlines()
            offsets = (-1,1) if frame == 1 else (1,-1)
            for side, group in enumerate(HANDS[direction]):
                tuck = (1 if side == 0 else -1) if offsets[side] > 0 and len(group) > 1 else 0
                points = []
                for x,y in group:
                    actual_x,actual_y = x+tuck,y+1+offsets[side]
                    assert rows[actual_y][actual_x] == original[y][x]
                    points.append([actual_x,actual_y])
                hand_evidence.append({"direction":direction,"frame":frame,"screen_side":"left" if side==0 else "right","body_offset":1,"relative_y":offsets[side],"actual_hand_pixels":points})
    report = {"runtime_copy_byte_matches":True,"runtime_sheet_sha256":sha(PLAYER / "walk-normal.png"),"source_manifest_v2":True,"protected_hashes_unchanged":protected,"hands_relative_offsets_verified":hand_evidence}
    (OUT / "runtime-check.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    strip = Image.new("RGB",(960,224),(39,44,45))
    draw = ImageDraw.Draw(strip)
    font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf",16)
    crop = (290,160,350,210)
    for frame in range(4):
        capture = Image.open(OUT / f"normal_{frame}.png").convert("RGB")
        strip.paste(capture.crop(crop).resize((240,200),Image.Resampling.NEAREST),(240*frame,24))
        draw.text((240*frame+8,3),f"GPU F{frame} / crop 4x",font=font,fill=(236,231,213))
    strip.save(OUT / "gpu-frames.png")
    targets = [p for p in ROOT.iterdir() if p.is_file()] + [PLAYER / "walk-normal.png",PLAYER / "manifest.json",REPO / "tests/poc/spr01/self_normal_v2.gd"]
    hashes = {str(p.relative_to(REPO)).replace(chr(92),"/"):sha(p) for p in targets}
    (OUT / "target-hashes.json").write_text(json.dumps({"head":"151a53f20255489ef08481e2a353258cd8ac559c","shared_dirty_tree":True,"files":hashes},indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"runtime_sheet_sha256":report["runtime_sheet_sha256"],"protected_files":len(protected),"verified_hand_poses":len(hand_evidence)},indent=2))


if __name__ == "__main__":
    main()
