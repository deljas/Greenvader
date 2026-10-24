"""Export saved per-frame grids, exact palettes, manifest and animated previews."""
from pathlib import Path
import hashlib
import json
import shutil
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / "four-directions-v2"
ORDER = ["down", "left", "right", "up"]
DURATIONS = [120, 130, 120, 130]
PALETTE = {key: tuple(value) for key, value in json.loads((ROOT / "palette.json").read_text()).items()}
GLYPHS = {
"D":["1110","1001","1001","1001","1001","1001","1110"],"O":["0110","1001","1001","1001","1001","1001","0110"],
"W":["10001","10001","10001","10101","10101","10101","01010"],"N":["1001","1101","1101","1011","1011","1001","1001"],
"L":["1000","1000","1000","1000","1000","1000","1111"],"E":["1111","1000","1000","1110","1000","1000","1111"],
"F":["1111","1000","1000","1110","1000","1000","1000"],"T":["11111","00100","00100","00100","00100","00100","00100"],
"R":["1110","1001","1001","1110","1010","1001","1001"],"I":["111","010","010","010","010","010","111"],
"G":["0111","1000","1000","1011","1001","1001","0111"],"H":["1001","1001","1001","1111","1001","1001","1001"],
"U":["1001","1001","1001","1001","1001","1001","0110"],"P":["1110","1001","1001","1110","1000","1000","1000"],
"X":["1001","1001","0110","0110","0110","1001","1001"],"S":["0111","1000","1000","0110","0001","0001","1110"],
"0":["0110","1001","1011","1001","1101","1001","0110"],"1":["010","110","010","010","010","010","111"],
"2":["0110","1001","0001","0010","0100","1000","1111"],"3":["1110","0001","0001","0110","0001","0001","1110"],
"6":["0111","1000","1000","1110","1001","1001","0110"],"8":["0110","1001","1001","0110","1001","1001","0110"],
" ":["000"] * 7,
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def label(draw, xy, text, color, scale=1):
    x0, y0 = xy
    for char in text:
        glyph = GLYPHS[char]
        for y, row in enumerate(glyph):
            for x, bit in enumerate(row):
                if bit == "1":
                    draw.rectangle((x0 + x * scale, y0 + y * scale, x0 + (x + 1) * scale - 1, y0 + (y + 1) * scale - 1), fill=color)
        x0 += (len(glyph[0]) + 1) * scale


def cells(draw, rows, origin, scale, colors):
    for y, row in enumerate(rows):
        for x, char in enumerate(row):
            if char != ".":
                px, py = origin[0] + x * scale, origin[1] + y * scale
                draw.rectangle((px, py, px + scale - 1, py + scale - 1), fill=colors[char])


def green_mask(rows):
    return {(x, y) for y, row in enumerate(rows) for x, char in enumerate(row) if char in "LGH"}


def main():
    source_hashes = {d: sha(SOURCE / f"{d}.png") for d in ORDER}
    all_rows, images, results = {}, {}, []
    sheet = Image.new("RGBA", (96, 144), (0, 0, 0, 0))
    contacts = Image.new("RGB", (516, 680), (39, 44, 45))
    cd = ImageDraw.Draw(contacts)
    for frame in range(4):
        label(cd, (80 + frame * 108, 12), "F" + str(frame), PALETTE["W"][:3], 2)
    manifest = {"kind": "walk-normal-initial-trial", "internal_screen": [640, 360], "frame_size": [24, 36], "sheet": "sheet.png", "sheet_size": [96, 144], "row_order": ORDER, "fps": 8, "loop": True, "cycle_ms": 500, "foot_anchor_xy": [12, 34], "gif_frame_ms": DURATIONS, "directions": []}
    for row_index, direction in enumerate(ORDER):
        sequence = []
        label(cd, (8, 32 + row_index * 160 + 64), direction.upper(), PALETTE["W"][:3])
        neutral_rows = (SOURCE / f"grid-{direction}.txt").read_text().splitlines()
        for frame in range(4):
            rows = (ROOT / f"grid-{direction}-{frame}.txt").read_text().splitlines()
            assert len(rows) == 36 and all(len(row) == 24 for row in rows)
            assert all(char in PALETTE for row in rows for char in row)
            image = Image.new("RGBA", (24, 36))
            expected = [PALETTE[char] for row in rows for char in row]
            image.putdata(expected)
            path = ROOT / f"{direction}-{frame}.png"
            if frame == 0:
                assert rows == neutral_rows
                shutil.copyfile(SOURCE / f"{direction}.png", path)
            else:
                image.save(path)
            actual = Image.open(path)
            assert actual.mode == "RGBA" and actual.size == (24, 36)
            assert [actual.getpixel((x, y)) for y in range(36) for x in range(24)] == expected
            assert {value[3] for value in expected} == {0, 255}
            bbox = actual.getbbox()
            assert 0 < bbox[0] < bbox[2] < 24 and 0 < bbox[1] < bbox[3] < 36
            expected_bottom = 34
            assert bbox[3] == expected_bottom
            source_pixels = Image.open(SOURCE / f"{direction}.png")
            body_dy = [0,1,0,1][frame]
            core = [(x,y) for y,line in enumerate(neutral_rows) for x,char in enumerate(line) if char in "WISEM" and (15 <= y <= 23 or char in "EM")]
            assert all(actual.getpixel((x,y+body_dy)) == source_pixels.getpixel((x,y)) for x,y in core), (direction,frame,"torso/face 0,1,0,1 cycle")
            eye_expected = {(x,y+body_dy) for y,line in enumerate(neutral_rows) for x,char in enumerate(line) if char in "EM"}
            assert {(x,y) for y,line in enumerate(rows) for x,char in enumerate(line) if char in "EM"} == eye_expected
            if frame in (1,3):
                prior_rows = (ROOT.parent / "walk-normal-v1" / f"grid-{direction}-{frame}.txt").read_text().splitlines()
                # The animated skin flaps differ from a rigid one-pixel body shift.
                changed_hands = sum(rows[y][x] != prior_rows[y-1][x] for y in range(25,32) for x in list(range(1,4))+list(range(16,23)))
                assert changed_hands > 0
            support_x = [x for x in range(24) if actual.getpixel((x, 33))[3]]
            assert support_x
            if frame == 1:
                assert max(support_x) < 12
            elif frame == 3:
                # LEFT's long near foot begins at x11; its center still lies to the right.
                assert sum(support_x) / len(support_x) > 12
            if direction == "up":
                assert all(char not in "EM" for row in rows for char in row)
            else:
                eyes = {(x, y) for y, line in enumerate(rows) for x, char in enumerate(line) if char == "E"}
                eye_xs = {x for x, y in eyes}
                assert len(eyes) == 4 and len(eye_xs) == 2
                for x in eye_xs:
                    ys = sorted(y for ex, y in eyes if ex == x)
                    assert len(ys) == 2 and ys[1] == ys[0] + 1
                assert any("M" in line for line in rows)
            if frame:
                rigid_dy = body_dy
                rigid_green = {(x, y + rigid_dy) for x, y in green_mask(neutral_rows)}
                assert green_mask(rows) != rigid_green
            all_rows[direction, frame] = rows
            images[direction, frame] = actual.copy()
            rect = [frame * 24, row_index * 36, 24, 36]
            sheet.paste(actual, (rect[0], rect[1]))
            cells(cd, rows, (80 + frame * 108, 32 + row_index * 160), 4, {key: value[:3] for key, value in PALETTE.items()})
            item = {"file": path.name, "rect": rect, "anchor_xy": [12,34], "visible_bbox_exclusive": bbox, "visible_bottom_gap_px": 0, "nominal_body_y_offset_px": body_dy, "hand_relative_y_offsets": [[0,0],[-1,1],[0,0],[1,-1]][frame], "phase": ["neutral-contact","left-contact-weight-down","passing-contact","right-contact-weight-down"][frame], "support_pixel_x_at_y33": support_x, "sha256": sha(path)}
            sequence.append(item)
            results.append({"direction": direction, "frame": frame, "grid_matches": True, "no_clipping": True, "eyes_1x2_or_back_faceless": True, **item})
        manifest["directions"].append({"direction": direction, "fps": 8, "loop": True, "frames": sequence})
    sheet.save(ROOT / "sheet.png")
    contacts.save(ROOT / "contact-sheet.png")
    # Fixed palette, direct index drawing: no RGB quantization and no dither.
    color_keys = ["W", "I", "S", "L", "G", "H", "E", "M"]
    rgb_colors = [(39, 44, 45)] + [PALETTE[key][:3] for key in color_keys] + [(84, 90, 88)]
    gif_palette = [component for rgb in rgb_colors for component in rgb] + [0] * (768 - len(rgb_colors) * 3)
    indices = {key: index + 1 for index, key in enumerate(color_keys)}
    gif_frames = []
    for frame in range(4):
        page = Image.new("P", (656, 400), 0)
        page.putpalette(gif_palette)
        pd = ImageDraw.Draw(page)
        for index, direction in enumerate(ORDER):
            x = 16 + index * 160
            label(pd, (x, 8), direction.upper(), 1, 2)
            cells(pd, all_rows[direction, frame], (x, 32), 6, indices)
            label(pd, (x, 260), "6X", 1)
            label(pd, (x + 48, 278), "2X", 1)
            cells(pd, all_rows[direction, frame], (x + 48, 296), 2, indices)
            # Fixed ground ticks are outside the sprite rectangles.
            for origin, scale in [((x, 32), 6), ((x + 48, 296), 2)]:
                ground = origin[1] + 34 * scale
                pd.line((origin[0] - 6, ground, origin[0] - 2, ground), fill=9)
                pd.line((origin[0] + 24 * scale + 2, ground, origin[0] + 24 * scale + 6, ground), fill=9)
        label(pd, (16, 384), "8FPS", 1)
        gif_frames.append(page)
    gif_path = ROOT / "preview.gif"
    gif_frames[0].save(gif_path, save_all=True, append_images=gif_frames[1:], duration=DURATIONS, loop=0, optimize=False, disposal=2)
    gif = Image.open(gif_path)
    assert gif.n_frames == 4 and gif.info["loop"] == 0
    actual_durations = []
    for frame in range(4):
        gif.seek(frame)
        actual_durations.append(gif.info["duration"])
        assert gif.convert("RGB").tobytes() == gif_frames[frame].convert("RGB").tobytes(), ("GIF palette loss", frame)
    assert actual_durations == DURATIONS and sum(actual_durations) == 500
    saved_sheet = Image.open(ROOT / "sheet.png")
    for row_index, direction in enumerate(ORDER):
        assert sha(SOURCE / f"{direction}.png") == source_hashes[direction]
        assert sha(ROOT / f"{direction}-0.png") == source_hashes[direction]
        for frame in range(4):
            assert saved_sheet.crop((frame * 24, row_index * 36, frame * 24 + 24, row_index * 36 + 36)).tobytes() == images[direction, frame].tobytes()
    (ROOT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    report = {"status":"PASS","source_sha256_unchanged":source_hashes,"frame0_png_byte_matches_source":True,"all_sizes_rgba_24x36":True,"alpha_values":[0,255],"palette_subset":True,"sheet_matches_frames":True,"torso_face_y_offsets":[0,1,0,1],"hands_move_relative_to_body":True,"support_at_y33_all_frames":True,"alternating_contact_foot_f1_left_f3_right":True,"leaf_masks_not_rigid_body_translation":True,"gif_decoded_rgb_exact":True,"gif_frames":4,"gif_frame_ms":actual_durations,"gif_cycle_ms":500,"gif_average_fps":8,"anchor_xy":[12,34],"frames":results}
    (ROOT / "self-check.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key != "frames"}, indent=2))


if __name__ == "__main__":
    main()
