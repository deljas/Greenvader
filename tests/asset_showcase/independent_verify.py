"""TECH-3D-13: read-only delivery/baseline and submitted-frame checks."""
from collections import Counter
from hashlib import sha256
from pathlib import Path
import json
import struct
import subprocess

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "evidence/asset-showcase/independent"
OUT.mkdir(parents=True, exist_ok=True)

def read(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8-sig"))

def digest(path):
    return sha256(Path(path).read_bytes()).hexdigest()

def verify_hashes(entries, key="path"):
    failures = []
    for entry in entries:
        path = Path(entry[key])
        if not path.is_absolute():
            path = ROOT / path
        if digest(path) != entry["sha256"].lower():
            failures.append(str(path))
    return {"count": len(entries), "mismatches": failures}

frozen = read("evidence/asset-showcase/self/source-hashes.json")
manifest = read("assets/models/delivery_showcase/manifest.json")
assets = manifest["assets"]
expected = {
    "BLD": [7, 38, 79, 123], "VIN": [7, 32, 47, 60],
    "MOS": [3, 12, 24, 35], "TRE": [1, 27, 54, 74],
    "GND": [9, 36, 59, 77], "PRP": [1, 41, 75, 121],
}
ids = [f"{category}-{number:03}" for category, numbers in expected.items() for number in numbers]
checks = {
    "frozen_66": verify_hashes(frozen["source_files"]),
    "parent_existing_7": verify_hashes(read("evidence/asset-showcase/parent-baseline.json")),
    "source_original_glb_24": verify_hashes(read("evidence/asset-showcase/source-baseline.json")),
    "selected_ids_exact": sorted(ids) == sorted(a["id"] for a in assets),
    "category_counts": dict(Counter(a["category"] for a in assets)),
}
copies = []
glb_checks = []
for asset in assets:
    for entry in asset["files"]:
        source_hash = digest(entry["source"])
        copy_hash = digest(ROOT / entry["copy"])
        copies.append({"copy": entry["copy"], "sha256": copy_hash,
                       "match": source_hash == copy_hash == entry["sha256"].lower()})
    path = ROOT / asset["scene"].removeprefix("res://")
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", data)
    chunk_length, chunk_type = struct.unpack_from("<II", data, 12)
    gltf = json.loads(data[20:20 + chunk_length])
    external = [i["uri"] for i in gltf.get("images", [])
                if "uri" in i and not i["uri"].startswith("data:")]
    mesh_nodes = [n for n in gltf.get("nodes", []) if "mesh" in n]
    glb_checks.append({"id": asset["id"], "valid_glb2": magic == 0x46546C67 and version == 2 and length == len(data) and chunk_type == 0x4E4F534A,
                       "mesh_nodes": len(mesh_nodes),
                       "external_images_present": all((path.parent / uri).exists() for uri in external)})
checks["copies"] = {"count": len(copies), "mismatches": [x for x in copies if not x["match"]], "files": copies}
checks["glb_contents"] = glb_checks
frames = []
for category in expected:
    path = ROOT / f"evidence/asset-showcase/self/{category}_category_ui_1920.png"
    image = Image.open(path).convert("RGB")
    reduced = image.resize((640, 360), Image.Resampling.NEAREST)
    enlarged = reduced.resize((1920, 1080), Image.Resampling.NEAREST)
    raw = ROOT / f"evidence/asset-showcase/self/{category}_category_640.png"
    frames.append({"path": str(path.relative_to(ROOT)), "sha256": digest(path),
                   "size": image.size, "raw_size": Image.open(raw).size,
                   "integer_3_pixel_blocks": ImageChops.difference(image, enlarged).getbbox() is None})
checks["frames"] = frames
checks["head"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
checks["manifest_sha256"] = digest(ROOT / "assets/models/delivery_showcase/manifest.json")
checks["frozen_manifest_sha256"] = digest(ROOT / "evidence/asset-showcase/self/source-hashes.json")
bad = any(checks[key]["mismatches"] for key in ["frozen_66", "parent_existing_7", "source_original_glb_24", "copies"])
bad |= not checks["selected_ids_exact"] or set(checks["category_counts"].values()) != {4}
bad |= any(not g["valid_glb2"] or not g["mesh_nodes"] or not g["external_images_present"] for g in glb_checks)
bad |= any(not f["integer_3_pixel_blocks"] or f["size"] != (1920,1080) or f["raw_size"] != (640,360) for f in frames)
checks["failures"] = int(bad)
(OUT / "checks.json").write_text(json.dumps(checks, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"head": checks["head"], "frozen": checks["frozen_66"], "originals": checks["source_original_glb_24"], "existing": checks["parent_existing_7"], "copies": len(copies), "glb":len(glb_checks), "integer_frames":sum(f["integer_3_pixel_blocks"] for f in frames), "failures":checks["failures"]}, ensure_ascii=False))
raise SystemExit(int(bad))
