"""TECH-3D-14 read-only frozen-source, original-data and evidence checks."""
from collections import Counter
from hashlib import sha256
from pathlib import Path
import json
import struct
import subprocess
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "evidence/vine-compare"
OUT = BASE / "independent"
OUT.mkdir(parents=True, exist_ok=True)

def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))

def digest(path):
    return sha256(Path(path).read_bytes()).hexdigest()

def hashes(entries):
    mismatches = []
    for entry in entries:
        path = Path(entry["path"])
        if not path.is_absolute():
            path = ROOT / path
        if digest(path) != entry["sha256"].lower():
            mismatches.append(str(path))
    return {"count": len(entries), "mismatches": mismatches}

frozen = read(BASE / "self/source-hashes.json")
checks = {
    "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
    "frozen": hashes(frozen["files"]),
    "existing": hashes(read(BASE / "parent-baseline.json")),
    "originals": hashes(read(BASE / "source-baseline.json")),
}
source_folder = Path("C:/godot/greenvader_asset_deliveries/assets/vines")
inventory = {}
for metadata in source_folder.glob("*/metadata.json"):
    meta = read(metadata)
    glbs = sorted(metadata.parent.glob("*.glb"))
    if not meta.get("asset_id", "").startswith("VIN-") or not glbs:
        continue
    glb = glbs[0].read_bytes()
    size, kind = struct.unpack_from("<II", glb, 12)
    gltf = json.loads(glb[20:20 + size])
    triangles = 0
    for mesh in gltf.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            if primitive.get("mode", 4) != 4:
                continue
            accessor = primitive.get("indices", primitive["attributes"]["POSITION"])
            triangles += gltf["accessors"][accessor]["count"] // 3
    inventory[meta["asset_id"]] = {"triangles": triangles, "metadata": str(metadata)}
smoke = read(BASE / "self/smoke.json")
representatives = read(BASE / "self/representatives.json")
checks["inventory"] = {"count": len(inventory), "ids": sorted(inventory),
                       "smoke_ids_match": sorted(inventory) == sorted(row["id"] for row in smoke),
                       "smoke_status_counts": dict(Counter(row["status"] for row in smoke)),
                       "source_import_sidecars": [str(p) for p in source_folder.rglob("*.import")]}
checks["smoke_stat_mismatch"] = [{"id": row["id"], "recorded_triangles": row["stats"]["triangles"],
                                   "glb_triangles": inventory[row["id"]]["triangles"]}
                                  for row in smoke
                                  if row["stats"]["triangles"] != inventory[row["id"]]["triangles"]]
checks["representatives"] = []
for row in representatives:
    counts = row["counts"]
    actual = inventory[f"VIN-{row['id']:03}"]["triangles"]
    checks["representatives"].append({"id": row["id"], "glb_triangles": actual,
                                      "counts": counts, "root": row["stats"]["root"],
                                      "endpoint_monotonic": counts[0] == 0 and counts[-1] == actual and all(a <= b for a,b in zip(counts, counts[1:]))})
checks["frames"] = []
for path in sorted((BASE / "self").glob("*_ui_1920.png")):
    image = Image.open(path).convert("RGB")
    restored = image.resize((640,360), Image.Resampling.NEAREST).resize((1920,1080), Image.Resampling.NEAREST)
    raw = path.with_name(path.name.replace("_ui_1920", "_640"))
    checks["frames"].append({"path": str(path.relative_to(ROOT)), "sha256": digest(path),
                              "size": image.size, "raw_size": Image.open(raw).size,
                              "integer3_blocks": ImageChops.difference(image, restored).getbbox() is None})
checks["evidence_sha256"] = {str(p.relative_to(ROOT)): digest(p) for p in (BASE / "self").glob("*.json")}
bad = any(checks[key]["mismatches"] for key in ["frozen", "existing", "originals"])
bad |= len(inventory) != 63 or not checks["inventory"]["smoke_ids_match"] or bool(checks["inventory"]["source_import_sidecars"])
bad |= any(not row["endpoint_monotonic"] for row in checks["representatives"])
bad |= any(not row["integer3_blocks"] or row["size"] != (1920,1080) or row["raw_size"] != (640,360) for row in checks["frames"])
# The submitted smoke's VIN-007 stat belongs to VIN-006; initial/representative
# tests separately cover VIN-007. Keep this diagnostic; do not silently fix it.
checks["failures"] = int(bad)
(OUT / "checks.json").write_text(json.dumps(checks, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"frozen": checks["frozen"], "existing": checks["existing"], "originals": checks["originals"],
                  "inventory": len(inventory), "frames": len(checks["frames"]),
                  "smoke_stat_mismatch": checks["smoke_stat_mismatch"], "failures": int(bad)}, ensure_ascii=False))
raise SystemExit(int(bad))
