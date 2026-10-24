"""TECH-3D-15 read-only source, delivery, placement and GPU-evidence audit."""
from collections import Counter
from hashlib import sha256
from pathlib import Path
import json
import math
import re
import subprocess
from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "evidence/town-lab"
OUT = BASE / "independent"
OUT.mkdir(parents=True, exist_ok=True)

def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))

def digest(path):
    return sha256(Path(path).read_bytes()).hexdigest()

def hashes(entries):
    wrong = []
    for entry in entries:
        path = Path(entry["path"])
        if not path.is_absolute():
            path = ROOT / path
        if digest(path) != entry["sha256"].lower():
            wrong.append(str(path))
    return {"count": len(entries), "mismatches": wrong}

def vector(text):
    return tuple(float(x) for x in text.strip("()").split(","))

def changed(name1, name2):
    a = Image.open(BASE / "self" / (name1 + "_640.png")).convert("RGB")
    b = Image.open(BASE / "self" / (name2 + "_640.png")).convert("RGB")
    return sum(x != y for x,y in zip(a.getdata(), b.getdata()))

frozen = read(BASE / "self/source-hashes.json")
manifest = read(ROOT / "assets/models/town_lab/manifest.json")
checks = {
    "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
    "frozen": hashes(frozen["files"]),
    "protected": hashes(read(BASE / "self/protected-baseline.json")),
}
copies = [f for entry in manifest for f in entry["files"]]
checks["source_copies"] = {"count":len(copies), "mismatches":[]}
for entry in copies:
    if not digest(entry["source"]) == digest(ROOT / entry["copy"]) == entry["sha256"].lower():
        checks["source_copies"]["mismatches"].append(entry["copy"])
placements = read(BASE / "self/placements.json")
buildings = [p for p in placements if p["kind"] == "building"]
expected_buildings = [f"BLD-{n:03}" for n in [7,19,38,46,79,91,123]]
checks["inventory"] = {"assets":len(manifest), "placed":len(placements), "buildings":[b["id"] for b in buildings],
                       "exact_7_buildings": sorted(b["id"] for b in buildings) == expected_buildings,
                       "all_native_scale": all(vector(p["scale"]) == (1,1,1) for p in placements),
                       "building_grounded": all(abs(vector(p["bounds_min"])[1]) < 0.001 for p in buildings),
                       "blocker_count":sum(p["collision_rectangles"] for p in placements)}
overlaps = []
for i,a in enumerate(buildings):
    for b in buildings[i+1:]:
        amin, bmin = vector(a["bounds_min"]),vector(b["bounds_min"])
        asize, bsize = vector(a["bounds_size"]),vector(b["bounds_size"])
        if all(min(amin[k]+asize[k], bmin[k]+bsize[k]) > max(amin[k], bmin[k]) for k in range(3)):
            overlaps.append([a["id"],b["id"]])
checks["building_overlap_pairs"] = overlaps
checks["frames"] = []
for path in sorted((BASE / "self").glob("*_ui_1920.png")):
    image = Image.open(path).convert("RGB")
    restored = image.resize((640,360), Image.Resampling.NEAREST).resize((1920,1080), Image.Resampling.NEAREST)
    checks["frames"].append({"path":str(path.relative_to(ROOT)),"sha256":digest(path),"size":image.size,
                             "integer3":ImageChops.difference(image,restored).getbbox() is None})
checks["gpu_differences"] = {
    "day_shadow_pixels":changed("water_day_shadow","water_day_shadow_OFF"),
    "night_shadow_pixels":changed("water_night_lamps","water_night_shadow_OFF"),
    "final_P1_reflection_pixels":changed("water_building_reflection","water_reflection_OFF"),
}
means = {}
for name in ["morning","noon","evening","night"]:
    image = Image.open(BASE / "self" / (name + "_overview_640.png")).convert("RGB")
    means[name] = sum(ImageStat.Stat(image).mean)/(3*255)
checks["final_overview_average_RGB"] = means
raw = read(BASE / "self/raw-repair.json")
compass = []
for row in raw:
    if row["label"] not in [n+"_overview" for n in ["morning","noon","evening","night"]]:
        continue
    x,y,z = vector(row["sun"])
    # Camera screen right is (+X,-Z); screen north on the ground is (-X,-Z).
    right = (x-z)/math.sqrt(2)
    south = (x+z)/math.sqrt(2)
    label = row["label"]
    expected = ((right>0 and y>0) if label=="morning_overview" else
                (abs(right)<0.001 and south>0 and y>0) if label=="noon_overview" else
                (right<0 and y>0) if label=="evening_overview" else
                (not row["sun_visible"] and row["sun_energy"]==0 and y<0))
    compass.append({"label":label,"screen_right_source":right,"screen_south_source":south,
                    "height":y,"expected_compass":expected,"actor_shaded":row["actor"]["shaded"],
                    "actor_sync":row["actor"]["matching_texture"] and row["actor"]["matching_feet"]})
checks["raw_compass"] = compass
results = read(BASE / "self/results.json")
checks["recorded_results"] = {"count":len(results["checks"]), "statuses":dict(Counter(r["status"] for r in results["checks"])),
                               "effective_conditions":len(results["checks"])-2,
                               "excluded_superseded":["water_night_local_shadow","building_reflection_present"]}
checks["evidence_sha256"] = {str(p.relative_to(ROOT)):digest(p) for p in (BASE / "self").glob("*.json")}
bad = any(checks[k]["mismatches"] for k in ["frozen","protected","source_copies"])
bad |= not checks["inventory"]["exact_7_buildings"] or not checks["inventory"]["all_native_scale"] or bool(overlaps)
bad |= any(not p["integer3"] or p["size"]!=(1920,1080) for p in checks["frames"])
bad |= any(not r["expected_compass"] or not r["actor_shaded"] or not r["actor_sync"] for r in compass)
bad |= not all(value>0 for value in checks["gpu_differences"].values())
checks["failures"] = int(bad)
(OUT/"checks.json").write_text(json.dumps(checks,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps({k:checks[k] for k in ["frozen","protected","source_copies","inventory","gpu_differences","recorded_results","failures"]},ensure_ascii=False))
raise SystemExit(int(bad))
