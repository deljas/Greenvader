"""Nearest crops from captured GPU phases; this is not continuous input recording."""
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).parent
rows = [(kind, direction) for direction in ("left", "right", "up") for kind in ("seed", "water")]
phases = ("000", "hold", "release", "flight", "walk")
scale = 4
cell = 64 * scale
tile_h = cell + 22
sheet = Image.new("RGB", (len(phases) * cell, len(rows) * tile_h), "#303b38")
draw = ImageDraw.Draw(sheet)
for row, (kind, direction) in enumerate(rows):
    for col, phase in enumerate(phases):
        source = Image.open(OUT / f"{kind}_{direction}_{phase}.png").convert("RGB")
        crop = source.crop((288, 144, 352, 208)).resize((cell, cell), Image.Resampling.NEAREST)
        sheet.paste(crop, (col * cell, row * tile_h + 22))
        draw.text((col * cell + 4, row * tile_h + 4), f"{kind} {direction} / {phase}", fill="white")
sheet.save(OUT / "game-directions-contact4x.png")
frames = []
for phase in phases:
    canvas = Image.new("RGB", (cell * 3, tile_h * 2), "#303b38")
    label = ImageDraw.Draw(canvas)
    for row, kind in enumerate(("seed", "water")):
        for col, direction in enumerate(("left", "right", "up")):
            source = Image.open(OUT / f"{kind}_{direction}_{phase}.png").convert("RGB")
            crop = source.crop((288, 144, 352, 208)).resize((cell, cell), Image.Resampling.NEAREST)
            canvas.paste(crop, (col * cell, row * tile_h + 22))
            label.text((col * cell + 4, row * tile_h + 4), f"{kind} {direction} / {phase}", fill="white")
    frames.append(canvas)
frames[0].save(OUT / "game-directions-phase4x.gif", save_all=True, append_images=frames[1:], duration=[350, 500, 350, 350, 450], loop=0, disposal=2)
print("Built GPU phase contact and phase-comparison GIF")
