"""Offline evidence checks only. Does not start Godot, send input or edit images."""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "evidence/render-study-3d/self"
OUT = ROOT / "evidence/render-study-3d/independent"
checks = []
images = {}
for time in ("morning", "noon", "evening"):
    with Image.open(SOURCE / f"{time}_960.png") as image:
        small = image.convert("RGBA")
    with Image.open(SOURCE / f"{time}_1920.png") as image:
        large = image.convert("RGBA")
    images[time] = small
    expected = small.resize((1920, 1080), Image.Resampling.NEAREST)
    checks.append({"id": f"integer2x.{time}", "result": "PASS" if small.size == (960, 540) and large.size == (1920, 1080) and expected.tobytes() == large.tobytes() else "FAIL", "detail": "All 1920x1080 output pixels compared with exact source-pixel replication."})

with Image.open(SOURCE / "noon_shadow_disabled_reference_960.png") as image:
    no_shadow = image.convert("RGBA")
noon = images["noon"]
changed = sum(p != q for p, q in zip(noon.getdata(), no_shadow.getdata()))
checks.append({"id": "shadow_reference_difference", "result": "PASS" if changed > 0 else "FAIL", "changed_pixels": changed, "detail": "Files differ; claim that only shadow was toggled is separately reviewed against capture code."})

frames = []
for index in range(5):
    path = SOURCE / f"camera_noon_{index:02d}_960.png"
    with Image.open(path) as image:
        converted = image.convert("RGBA")
    frames.append({"path": path.relative_to(ROOT).as_posix(), "size": list(converted.size), "equals_noon": converted.tobytes() == noon.tobytes()})
checks.append({"id": "camera_evidence_files", "result": "PASS" if len(frames) == 5 and all(frame["size"] == [960, 540] for frame in frames) else "FAIL", "detail": "Five samples exist; no claim of all-frame temporal stability."})
output = {"method": "Independent offline image-byte inspection; no engine execution", "checks": checks, "frames": frames, "failures": sum(check["result"] == "FAIL" for check in checks)}
(OUT / "png-checks.json").write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(output, ensure_ascii=False))
