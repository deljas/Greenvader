"""Copy frozen source PNGs/manifest exactly; set lossless pixel-art import parameters."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets/concepts/spr01/fire-directions-v1"
TARGET = ROOT / "assets/sprites/poc/player/fire-directions-v1"
OUT = Path(__file__).parent
TARGET.mkdir(parents=True, exist_ok=True)
template_path = ROOT / "assets/sprites/poc/player/fire-front-v3/seed-character-sheet.png.import"
template = template_path.read_text(encoding="utf-8")
template_source = "res://assets/sprites/poc/player/fire-front-v3/seed-character-sheet.png"
template_dest = "res://.godot/imported/seed-character-sheet.png-" + hashlib.md5(template_source.encode()).hexdigest() + ".ctex"
copies = []
pngs = [p for p in sorted(SOURCE.glob("*.png")) if p.name.startswith(("seed-", "water-", "idle-"))]
for source in pngs + [SOURCE / "manifest.json"]:
    target = TARGET / source.name
    target.write_bytes(source.read_bytes())
    copies.append({"source": source.relative_to(ROOT).as_posix(), "runtime": target.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(target.read_bytes()).hexdigest()})
    if target.suffix == ".png":
        src = "res://" + target.relative_to(ROOT).as_posix()
        dst = "res://.godot/imported/" + target.name + "-" + hashlib.md5(src.encode()).hexdigest() + ".ctex"
        settings = re.sub(r'^uid=.*\n', '', template, flags=re.MULTILINE).replace(template_source, src).replace(template_dest, dst)
        target.with_suffix(".png.import").write_text(settings, encoding="utf-8", newline="\n")
parent_path = TARGET.parent / "manifest.json"
parent = json.loads(parent_path.read_text(encoding="utf-8"))
parent["fire_front"]["status"] = "historical prototype; runtime superseded by fire_directions"
parent["fire_directions"] = {
    "runtime_directory": "fire-directions-v1/",
    "source_directory": "assets/concepts/spr01/fire-directions-v1/",
    "directions": ["down", "left", "right", "up"],
    "sheet_rows": "directions; authored independently, never mirrored",
    "event_ms": {"seed": 66, "water": 400},
    "total_ms": {"seed": 400, "water": 800},
    "layers": ["character", "formation_fx", "flying_projectile"],
    "sockets": "release_events[0].socket_by_direction; visual offset only",
    "seed_eyes": "normal open eyes in every frame",
    "water_front": "byte-identical to front-v3"
}
parent_path.write_text(json.dumps(parent, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
(OUT / "source-copy.json").write_text(json.dumps({"files": copies, "count": len(copies)}, indent=2) + "\n", encoding="utf-8")
print(f"Copied {len(copies)} source files exactly")
