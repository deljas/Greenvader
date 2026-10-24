"""Export separately authored 24x36 direction grids. No mirrored sprite production."""
from pathlib import Path
import hashlib
import json
import shutil
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / "front-pixel-v1"
ORDER = ["down", "left", "right", "up"]
SIZE = (24, 36)
ANCHOR = (12, 34)
PALETTE = {key: tuple(value) for key, value in json.loads((ROOT / "palette.json").read_text()).items()}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def font(size):
    try:
        return ImageFont.truetype("C:/Windows/Fonts/consola.ttf", size)
    except OSError:
        return ImageFont.load_default()


def draw_cells(draw, rows, origin, scale):
    for y, row in enumerate(rows):
        for x, char in enumerate(row):
            color = PALETTE[char]
            if color[3]:
                px, py = origin[0] + x * scale, origin[1] + y * scale
                draw.rectangle((px, py, px + scale - 1, py + scale - 1), fill=color[:3])


def main():
    source_hash = sha(SOURCE / "front-24x36.png")
    assert source_hash == "d12e39f3ba986f36d0b2a7a0a762518794eaa370d72de17096c804041c8d8d18"
    assert (ROOT / "palette.json").read_bytes() == (SOURCE / "palette.json").read_bytes()
    shutil.copyfile(SOURCE / "front-24x36.png", ROOT / "down.png")
    shutil.copyfile(SOURCE / "grid-24x36.txt", ROOT / "grid-down.txt")
    preview = Image.new("RGB", (864, 480), (39, 44, 45))
    draw = ImageDraw.Draw(preview)
    draw.text((24, 10), "FOUR DIRECTIONS / STATIC / 24x36", fill=(236, 231, 213), font=font(20))
    sheet = Image.new("RGBA", (96, 36), PALETTE["."])
    images, all_rows, results = {}, {}, []
    manifest = {"type": "static-direction-candidates", "internal_screen": [640, 360], "sheet": "sheet.png", "sheet_size": [96, 36], "frame_size": [24, 36], "directions": []}
    for index, direction in enumerate(ORDER):
        rows = (ROOT / f"grid-{direction}.txt").read_text().splitlines()
        assert len(rows) == 36 and all(len(row) == 24 for row in rows)
        assert all(char in PALETTE for row in rows for char in row)
        expected = [PALETTE[char] for row in rows for char in row]
        image = Image.new("RGBA", SIZE)
        image.putdata(expected)
        path = ROOT / f"{direction}.png"
        if direction != "down":
            image.save(path)
        actual = Image.open(path)
        pixels = [actual.getpixel((x, y)) for y in range(36) for x in range(24)]
        assert actual.mode == "RGBA" and actual.size == SIZE and pixels == expected
        assert {pixel[3] for pixel in pixels} == {0, 255}
        assert all(pixel in PALETTE.values() for pixel in pixels)
        bbox = actual.getbbox()
        assert 0 < bbox[0] < bbox[2] < 24 and 0 < bbox[1] < bbox[3] < 36
        assert bbox[3] == ANCHOR[1]
        assert all(actual.getpixel((x, 34))[3] == 0 for x in range(24))
        assert actual.getpixel((10, 33))[3] or actual.getpixel((13, 33))[3]
        if direction == "up":
            assert all(char not in "EM" for row in rows for char in row)
        images[direction] = actual.copy()
        all_rows[direction] = rows
        sheet.paste(actual, (index * 24, 0))
        origin = (24 + index * 208, 56)
        draw.text((origin[0], 35), f"{direction.upper()} / 8x", fill=(236, 231, 213), font=font(15))
        draw.rectangle((origin[0] - 1, 55, origin[0] + 192, 344), outline=(84, 90, 88))
        draw_cells(draw, rows, origin, 8)
        draw.text((origin[0] + 60, 354), "2x", fill=(192, 195, 186), font=font(14))
        draw_cells(draw, rows, (origin[0] + 72, 374), 2)
        manifest["directions"].append({"direction": direction, "file": path.name, "rect": [index * 24, 0, 24, 36], "anchor_xy": [12, 34], "frame_count": 1, "fps": 1, "loop": False})
        results.append({"direction": direction, "file": path.name, "size": [24, 36], "mode": actual.mode, "alpha": [0, 255], "opaque_colors": len({pixel for pixel in pixels if pixel[3]}), "bbox_exclusive": bbox, "anchor_xy": [12, 34], "no_clipping": True, "grid_readback_match": True, "sha256": sha(path)})
    draw.text((24, 454), "Independent direction grids / common foot anchor (12,34) / no walking frames", fill=(192, 195, 186), font=font(15))
    # Mirrored coordinates are used only to detect equality, never to construct a sprite.
    direct_equal = all(images["left"].getpixel((x, y)) == images["right"].getpixel((x, y)) for y in range(36) for x in range(24))
    reflected_equal = all(images["left"].getpixel((23 - x, y)) == images["right"].getpixel((x, y)) for y in range(36) for x in range(24))
    assert not direct_equal and not reflected_equal
    body_masks_differ = {}
    for direction in ("left", "right"):
        differs = sum((all_rows[direction][y][x] in "WISEM") != (all_rows["down"][y][x] in "WISEM") for y in range(15, 34) for x in range(24))
        assert differs > 0
        body_masks_differ[direction] = differs
    assert (ROOT / "down.png").read_bytes() == (SOURCE / "front-24x36.png").read_bytes()
    assert (ROOT / "grid-down.txt").read_bytes() == (SOURCE / "grid-24x36.txt").read_bytes()
    assert sha(SOURCE / "front-24x36.png") == source_hash
    sheet.save(ROOT / "sheet.png")
    preview.save(ROOT / "preview.png")
    # Check saved sheet rectangles against the four independent PNGs.
    actual_sheet = Image.open(ROOT / "sheet.png")
    for index, direction in enumerate(ORDER):
        assert actual_sheet.crop((index * 24, 0, (index + 1) * 24, 36)).tobytes() == images[direction].tobytes()
    # Check both preview magnifications against complete constant-color source cells.
    for index, direction in enumerate(ORDER):
        for scale, origin in [(8, (24 + index * 208, 56)), (2, (96 + index * 208, 374))]:
            for y, row in enumerate(all_rows[direction]):
                for x, char in enumerate(row):
                    expected = PALETTE[char][:3] if PALETTE[char][3] else (39, 44, 45)
                    for dy in range(scale):
                        for dx in range(scale):
                            assert preview.getpixel((origin[0] + x * scale + dx, origin[1] + y * scale + dy)) == expected
    (ROOT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    report = {"status": "PASS", "front_png_byte_identical": True, "front_grid_byte_identical": True, "front_source_sha256": source_hash, "palette_source_identical": True, "left_right_direct_equal": direct_equal, "left_right_reflected_equal": reflected_equal, "side_body_mask_changes_from_front": body_masks_differ, "sheet_rects_match": True, "preview_8x_and_2x_cells_exact": True, "results": results}
    (ROOT / "self-check.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
