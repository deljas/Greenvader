"""Export two independently authored pixel grids; no source images or resampling."""
from pathlib import Path
import hashlib
import json

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
PALETTE = {key: tuple(value) for key, value in json.loads((ROOT / "palette.json").read_text()).items()}
SPECS = [
    ("16x24", (16, 24), 12, (44, 68), (8, 22)),
    ("24x36", (24, 36), 8, (332, 68), (12, 34)),
]


def read_grid(name, size):
    rows = (ROOT / f"grid-{name}.txt").read_text().splitlines()
    assert len(rows) == size[1], (name, "height")
    assert all(len(row) == size[0] for row in rows), (name, "width")
    assert all(char in PALETTE for row in rows for char in row), (name, "palette")
    return rows


def font(size):
    try:
        return ImageFont.truetype("C:/Windows/Fonts/consola.ttf", size)
    except OSError:
        return ImageFont.load_default()


def main():
    preview = Image.new("RGB", (568, 400), (39, 44, 45))
    draw = ImageDraw.Draw(preview)
    draw.text((24, 12), "FRONT / CONCEPT", fill=(236, 231, 213), font=font(20))
    draw.text((24, 374), "Independent grids - equal displayed frame size", fill=(192, 195, 186), font=font(16))
    results = []
    for name, size, scale, origin, anchor in SPECS:
        rows = read_grid(name, size)
        sprite = Image.new("RGBA", size, PALETTE["."])
        for y, row in enumerate(rows):
            for x, char in enumerate(row):
                sprite.putpixel((x, y), PALETTE[char])
                color = PALETTE[char]
                if color[3]:
                    px = origin[0] + x * scale
                    py = origin[1] + y * scale
                    draw.rectangle((px, py, px + scale - 1, py + scale - 1), fill=color[:3])
        path = ROOT / f"front-{name}.png"
        sprite.save(path)
        # Validate the actual PNG readback, rather than only the working image.
        actual = Image.open(path)
        assert actual.mode == "RGBA"
        assert actual.size == size
        actual_pixels = [actual.getpixel((x, y)) for y in range(size[1]) for x in range(size[0])]
        assert sorted({pixel[3] for pixel in actual_pixels}) == [0, 255]
        expected_pixels = [PALETTE[char] for row in rows for char in row]
        assert actual_pixels == expected_pixels, (name, "grid readback")
        assert all(pixel in PALETTE.values() for pixel in actual_pixels)
        # Every preview cell is the exact constant RGB rectangle of its source.
        for y, row in enumerate(rows):
            for x, char in enumerate(row):
                expected = PALETTE[char][:3] if PALETTE[char][3] else (39, 44, 45)
                for cy in range(origin[1] + y * scale, origin[1] + (y + 1) * scale):
                    for cx in range(origin[0] + x * scale, origin[0] + (x + 1) * scale):
                        assert preview.getpixel((cx, cy)) == expected
        draw.rectangle((origin[0] - 1, origin[1] - 1, origin[0] + size[0] * scale, origin[1] + size[1] * scale), outline=(84, 90, 88))
        draw.text((origin[0] - 5, 43), f"{size[0]}x{size[1]} px | {scale}x", fill=(236, 231, 213), font=font(16))
        results.append({
            "file": path.name,
            "mode": actual.mode,
            "size": actual.size,
            "alpha_values": sorted({pixel[3] for pixel in actual_pixels}),
            "opaque_color_count": len({pixel for pixel in actual_pixels if pixel[3]}),
            "bbox_xyxy_exclusive": actual.getbbox(),
            "foot_anchor_candidate_xy": anchor,
            "grid_matches_png": True,
            "preview_cells_exact": True,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        })
    preview.save(ROOT / "preview.png")
    assert Image.open(ROOT / "preview.png").size == (568, 400)
    report = {
        "source": "Independent hand-authored character grids and palette; no input PNG or image resampling.",
        "results": results,
        "preview": {"size": [568, 400], "scales": [12, 8], "displayed_frames": [[192, 288], [192, 288]], "mode": "RGB"},
        "status": "PASS",
    }
    (ROOT / "self-check.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
