"""Offline preparation checks only. Does not run Godot or claim actual reachability."""
import collections
import hashlib
import json
import math
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = pathlib.Path(__file__).resolve().parent
MAP = ROOT / "data/poc3/maps/town_03.json"
OLD = ROOT / "data/poc2/maps/town_02.json"
m = json.loads(MAP.read_text(encoding="utf-8"))
old = json.loads(OLD.read_text(encoding="utf-8"))
catalog_path = ROOT / "data/poc/asset_catalog.json"
catalog = {a["id"]: a for a in json.loads(catalog_path.read_text(encoding="utf-8"))["assets"]}
checks = []


def check(name, condition, detail):
    checks.append({"id": name, "status": "PASS" if condition else "FAIL", "detail": detail})


def distance(a, b):
    return round(math.dist(a, b) * 0.4, 6)


def ground(cell):
    return ((cell[0] + 0.5) * 0.4 - 9.6, (cell[1] + 0.5) * 0.4 - 8.0)


size = m["size"]
check("json_schema", size == [224, 224] and m["version"] == old["version"] == 2,
      "224x224 cells, 0.4m => 89.6m square; existing placement schema version retained")
check("instances_unchanged", m["instances"] == old["instances"],
      f"All {len(m['instances'])} original instance rows unchanged, including 28 buildings")
ids = [r["instance_id"] for r in m["instances"]]
check("asset_ids", len(ids) == len(set(ids)) and all(
    r.get("asset") in catalog or r.get("kind") == "puddle" for r in m["instances"]),
    "Unique instance IDs and existing catalog references only")
check("nests_unlocks", [{k: v for k, v in r.items() if k != "cell"} for r in m["nests"]] ==
      [{k: v for k, v in r.items() if k != "cell"} for r in old["nests"]],
      "5 nests: small boar/army, small spider/wheat, medium boar/watermelon, medium spider/rafflesia, large mother")
check("fossils_unlocks", [r["unlock"] for r in m["fossils"]] == [r["unlock"] for r in old["fossils"]],
      "3 exploration fossils preserve carrot/gatlinger/sprinkler")
check("island_preserved", m["open_cells"] == old["open_cells"] and m["island_rect"] == old["island_rect"] and
      m["paint"][:10] == old["paint"][:10], "Outer ring, canal, remote bridges, lake/island and island reach seed retained")
terrain = {}
valid_rects = True
for row in m["paint"]:
    x, y, w, h = row["rect"]
    valid_rects &= all(isinstance(v, int) for v in row["rect"]) and x >= 0 and y >= 0 and w > 0 and h > 0 and x+w <= 224 and y+h <= 224
    for yy in range(y, y+h):
        for xx in range(x, x+w):
            terrain[xx, yy] = row["terrain"]
check("paint_bounds", valid_rects and len(terrain) == 224 * 224, "All paint rectangles within bounds")
start = tuple(m["player_start_cell"])
safe = {p for p, t in terrain.items() if t == "safe"}
expected = {p for p in terrain if math.dist(start, p) * 0.4 <= 3.0}
check("central_initial_green", start == (112, 112) and safe == expected and len(safe) == 177,
      {"start_cell": start, "start_ground_m": ground(start), "green_cells": len(safe), "radius_m": 3.0,
       "derived_income_seeds_per_minute": len(safe)*2/100, "resource_compensation": "none; parent approved area-derived income"})
nest_distances = [distance(start, r["cell"]) for r in m["nests"]]
check("nest_center_distances", 12 <= nest_distances[0] <= 16 and all(d >= 20 for d in nest_distances[1:]),
      [{**r, "distance_m": d} for r, d in zip(m["nests"], nest_distances)])
check("initial_spawn_margin_before_free_position", min(nest_distances)-math.sqrt(2) > 8,
      {"lower_bound_before_relocation_m": min(nest_distances)-math.sqrt(2),
       "basis": "Current spawn jitter is +/-10 logical px per axis = +/-1m; free_position relocation still requires Godot verification"})

# Conservative approximation from published model metadata, not placement.gd rasterization.
# AABB blocks the whole building, so interiors cannot create a false short route.
# 0.5m inflation = 0.2m wall growth + 0.2m player half-size + 0.1m spare.
shapes = []
metadata_paths = set()
for row in m["instances"]:
    if "asset" not in row or catalog[row["asset"]]["collision"] == "none":
        continue
    a = catalog[row["asset"]]
    p = ROOT / a["metadata"].removeprefix("res://")
    metadata_paths.add(p)
    meta = json.loads(p.read_text(encoding="utf-8"))
    dimensions = meta["dimensions"]
    # Match the model's centered placement frame; canopy AABBs deliberately overestimate trunks.
    shapes.append((row["pos"], math.radians(row.get("yaw_deg", 0)), dimensions[0]/2+0.5, dimensions[2]/2+0.5))


def near_model(cell):
    x, y = ground(cell)
    for (cx, cy), angle, hx, hy in shapes:
        dx, dy = x-cx, y-cy
        # Godot rotation about +Y: local x = cos*x - sin*z; local z = sin*x + cos*z.
        lx = math.cos(angle)*dx-math.sin(angle)*dy
        ly = math.sin(angle)*dx+math.cos(angle)*dy
        if abs(lx) <= hx and abs(ly) <= hy:
            return True
    return False


blocked = {p for p, t in terrain.items() if t in ("building", "water") or near_model(p)}
check("clear_initial_circle_metadata", all(p not in blocked for p in safe),
      "177 initial cells clear in inflated metadata AABB approximation; actual rasterization NOT_RUN")
targets = {"east_small_nest": tuple(m["nests"][0]["cell"]), "north_small_nest": tuple(m["nests"][1]["cell"]),
           "west_medium_nest": tuple(m["nests"][2]["cell"]), "south_medium_nest": tuple(m["nests"][3]["cell"]),
           "mother": tuple(m["nests"][4]["cell"]), "north_water_bank": (112, 104)}
targets.update({"fossil_"+r["unlock"]: tuple(r["cell"]) for r in m["fossils"]})
previous = {start: None}
queue = collections.deque([start])
while queue:
    x, y = queue.popleft()
    for p in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
        if p in terrain and p not in blocked and p not in previous:
            previous[p] = (x, y)
            queue.append(p)
routes = {}
for name, target in targets.items():
    path = []
    at = target
    while at in previous:
        path.append(at)
        at = previous[at]
    path.reverse()
    routes[name] = {"target_cell": target, "metadata_candidate_exists": target in previous,
                    "candidate_length_m": round(max(0,len(path)-1)*0.4, 3), "candidate_cells": path}
check("representative_routes_metadata_only", all(r["metadata_candidate_exists"] for r in routes.values()),
      {k: {kk: vv for kk, vv in v.items() if kk != "candidate_cells"} for k, v in routes.items()})
bank = targets["north_water_bank"]
check("nearby_water_bank_metadata_only", bank in previous and terrain[112,103] == "water" and
      routes["north_water_bank"]["candidate_length_m"] <= 4.0,
      "3.2m candidate walk to (112,104), cardinally adjacent to water (112,103); existing refill rule reads terrain water")
check("no_local_moat_in_paint", all(terrain[x,112] not in ("water","building") for x in range(100,125)),
      "Central 10m x 6.8m land bridge joins both banks; north/south water is a canal, not a ring")

not_run = ["Godot import/start", "actual rendering/pixel perfect/outline verification", "actual placement rasterization and enclosed sealing",
           "actual player movement/water refill", "post-free_position enemy/nest positions and 8m safety",
           "dormancy/noncontact/approach/green-contact activation", "helper work/frontline division",
           "zone stability/no reinvasion and full greening including island", "save/restore and respawn", "physical input", "fun/final distance balance"]
manifest_paths = [MAP, OLD, catalog_path, ROOT / "scripts/poc/assets/placement.gd", ROOT / "scripts/poc/poc_coords.gd",
                  ROOT / "scripts/poc2/simulation/combat.gd", *sorted(metadata_paths)]
report = {"scope": "offline unconnected map preparation only; PASS refers to static checks, never actual reachability",
          "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
          "working_tree_status_at_check": subprocess.check_output(["git", "status", "--short"], cwd=ROOT, text=True),
          "checks": checks, "summary": dict(collections.Counter(r["status"] for r in checks)),
          "NOT_RUN": not_run,
          "sha256": {str(p.relative_to(ROOT)).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest() for p in manifest_paths}}
(OUT / "static_results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
(OUT / "candidate_routes.json").write_text(json.dumps(routes, indent=2)+"\n", encoding="utf-8")
print(json.dumps(report["summary"]))
for row in checks:
    if row["status"] != "PASS":
        print(row)
raise SystemExit(1 if any(r["status"] == "FAIL" for r in checks) else 0)
