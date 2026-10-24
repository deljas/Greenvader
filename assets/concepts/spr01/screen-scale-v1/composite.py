"""Exact screenshot composites, with no generated redrawing or background cleanup."""
from pathlib import Path
import hashlib
import json

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[3]
SOURCE = REPO / "evidence/spr01/references/user-game-640.png"
SPRITES = REPO / "assets/concepts/spr01/front-pixel-v1"
GAME_ORIGIN = (1, 31)
FEET = (589, 431)
SCALE = 2
CROP = (481, 319, 801, 559)
SPECS = [
    ("16x24", (16, 24), (8, 22), (573, 387)),
    ("24x36", (24, 36), (12, 34), (565, 363)),
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def font(size):
    try:
        return ImageFont.truetype("C:/Windows/Fonts/consola.ttf", size)
    except OSError:
        return ImageFont.load_default()


def main():
    original_hash = sha(SOURCE)
    source = Image.open(SOURCE)
    assert source.mode in ("RGB", "RGBA")
    original_pixels = list(source.get_flattened_data()) if hasattr(source, "get_flattened_data") else list(source.getdata())
    preview = Image.new("RGB", (688, 328), (37, 42, 43))
    draw = ImageDraw.Draw(preview)
    results = []
    for index, (name, size, anchor, top_left) in enumerate(SPECS):
        sprite_path = SPRITES / f"front-{name}.png"
        sprite_hash = sha(sprite_path)
        sprite = Image.open(sprite_path)
        assert sprite.mode == "RGBA" and sprite.size == size
        assert {pixel[3] for pixel in sprite.getdata()} == {0, 255}
        assert (top_left[0] + anchor[0] * SCALE, top_left[1] + anchor[1] * SCALE) == FEET
        assert all((top_left[axis] - GAME_ORIGIN[axis]) % SCALE == 0 for axis in (0, 1))
        scaled = sprite.resize((size[0] * SCALE, size[1] * SCALE), Image.Resampling.NEAREST)
        for y in range(size[1]):
            for x in range(size[0]):
                for dy in range(SCALE):
                    for dx in range(SCALE):
                        assert scaled.getpixel((x * SCALE + dx, y * SCALE + dy)) == sprite.getpixel((x, y))
        output = source.copy()
        output.paste(scaled, top_left, scaled.getchannel("A"))
        output_path = ROOT / f"screen-{name}.png"
        output.save(output_path)
        actual = Image.open(output_path)
        assert actual.size == source.size and actual.mode == source.mode
        outside_count = foreground_count = changed_count = 0
        for y in range(source.height):
            for x in range(source.width):
                sx, sy = x - top_left[0], y - top_left[1]
                covered = 0 <= sx < scaled.width and 0 <= sy < scaled.height and scaled.getpixel((sx, sy))[3] == 255
                actual_pixel = actual.getpixel((x, y))
                original_pixel = source.getpixel((x, y))
                if covered:
                    expected = scaled.getpixel((sx, sy))
                    if source.mode == "RGB":
                        expected = expected[:3]
                    assert actual_pixel == expected, (name, "foreground", x, y)
                    foreground_count += 1
                else:
                    assert actual_pixel == original_pixel, (name, "outside alpha", x, y)
                    outside_count += 1
                changed_count += actual_pixel != original_pixel
        # Both panels retain exactly the same source crop and scale.
        panel = actual.crop(CROP).convert("RGB")
        panel_origin = (16 + index * 336, 44)
        preview.paste(panel, panel_origin)
        for y in range(panel.height):
            for x in range(panel.width):
                assert preview.getpixel((panel_origin[0] + x, panel_origin[1] + y)) == actual.getpixel((CROP[0] + x, CROP[1] + y))[:3]
        draw.text((panel_origin[0], 12), f"{name} sprite | window 2x", font=font(15), fill=(237, 233, 217))
        assert sha(sprite_path) == sprite_hash
        results.append({
            "source_sprite": str(sprite_path.relative_to(REPO)),
            "source_sprite_sha256": sprite_hash,
            "sprite_size": size,
            "source_foot_anchor": anchor,
            "scale": SCALE,
            "scaled_frame_size": scaled.size,
            "top_left_in_screenshot": top_left,
            "feet_in_screenshot": FEET,
            "scaled_opaque_bbox_relative": scaled.getbbox(),
            "outside_alpha_pixels_preserved": outside_count,
            "foreground_pixels_exact": foreground_count,
            "changed_pixels": changed_count,
            "nearest_2x_replication": True,
            "preview_crop_exact": True,
            "file": output_path.name,
            "sha256": sha(output_path),
        })
    draw.text((16, 299), "Same crop / both 2x / 24x36 is 1.5x larger", font=font(15), fill=(204, 206, 196))
    preview_path = ROOT / "comparison.png"
    preview.save(preview_path)
    assert sha(SOURCE) == original_hash
    assert list(source.get_flattened_data() if hasattr(source, "get_flattened_data") else source.getdata()) == original_pixels
    report = {
        "status": "PASS",
        "source": str(SOURCE.relative_to(REPO)),
        "source_sha256": original_hash,
        "source_mode": source.mode,
        "source_size": source.size,
        "game_origin_in_screenshot": GAME_ORIGIN,
        "game_internal_size": [640, 360],
        "window_integer_scale": SCALE,
        "common_feet_in_game_pixels": [(FEET[0] - GAME_ORIGIN[0]) // SCALE, (FEET[1] - GAME_ORIGIN[1]) // SCALE],
        "source_bytes_unchanged": True,
        "results": results,
        "comparison": {"file": "comparison.png", "size": preview.size, "same_crop_xyxy": CROP, "additional_scale": 1, "sha256": sha(preview_path)},
        "limitations": ["Static screenshot size preview only", "No lighting/shadow/occlusion/game rendering verification"],
    }
    (ROOT / "self-check.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
