extends RefCounted
## POC-05 wall vegetation layout (pure data, no nodes). Ported from the vegetation lab (growth_patch sparse-window routes,
## surface_layers moss patches) for plane wall charts taken from the material ledger's vine_surfaces + the model metadata.
## Charts are in the GLB's local frame before centring (ledger "vine_frame"); u runs along the tangent from the chart origin,
## v is the height above the origin. Doors (opening starting at the ground) are never covered.
const DOOR_MAX_V: float = 0.3
const DOOR_MARGIN: float = 0.30
## Radius used for the coverage estimate (deliberately generous): a leaf at the display scale / a stem.
const LEAF_RADIUS_M: float = 0.28
const STEM_RADIUS_M: float = 0.05
const GRID_M: float = 0.1

static func _vec3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

## Wall charts of an asset: the ledger's vine_surfaces ids, geometry (size, openings, top profile) from the metadata's
## generated_receiver_surfaces. Each chart: {id, origin, tangent, normal, width, height, holes: Array[Rect2]}.
static func surfaces_for(entry: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var wanted: Array = []
	for item: Variant in entry.get("vine_surfaces", []):
		wanted.append(String((item as Dictionary)["id"]))
	if wanted.is_empty():
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(entry.get("metadata", ""))))
	if not (parsed is Dictionary):
		return out
	for record: Variant in (parsed as Dictionary).get("generated_receiver_surfaces", []):
		var rec: Dictionary = record
		if not wanted.has(String(rec["id"])):
			continue
		var origin: Vector3 = _vec3(rec["origin"])
		var tangent: Vector3 = _vec3(rec["tangent_u"])
		var holes: Array[Rect2] = []
		var width: float
		var height: float
		if rec.has("size"):
			width = float(rec["size"][0])
			height = float(rec["size"][1])
			for o: Variant in rec.get("openings_uv", []):
				holes.append(_hole(float(o[0]), float(o[1]), float(o[2]), float(o[3]), 0.0))
		else:
			var u0: float = float(rec["u_range"][0])
			width = float(rec["u_range"][1]) - u0
			origin += tangent * u0
			height = INF
			for p: Variant in rec["top_profile_uv"]:
				height = minf(height, float(p[1]))
			for o: Variant in rec.get("openings_uv", []):
				holes.append(_hole(float(o[0]), float(o[2]), float(o[1]), float(o[3]), u0))
		out.append({"id": String(rec["id"]), "kind": "plane", "origin": origin, "tangent": tangent, "normal": _vec3(rec["normal"]), "width": width, "height": height, "holes": holes})
	return out

## Opening [u0, v0, u1, v1] -> Rect2 on the chart. Openings that start at the ground are doors (v0 = 0).
static func _hole(u0: float, v0: float, u1: float, v1: float, u_shift: float) -> Rect2:
	var bottom: float = 0.0 if v0 < DOOR_MAX_V else v0
	return Rect2(u0 - u_shift, bottom, u1 - u0, v1 - bottom)

static func is_door(hole: Rect2) -> bool:
	return hole.position.y < 0.05

static func sample(surface: Dictionary, u: float, v: float) -> Dictionary:
	return {"position": surface["origin"] + surface["tangent"] * u + Vector3.UP * v, "normal": surface["normal"]}

static func blocked(surface: Dictionary, u: float, v: float, margin: float) -> bool:
	for hole: Rect2 in surface["holes"]:
		if hole.grow(margin).has_point(Vector2(u, v)):
			return true
	return false

static func route_safe(surface: Dictionary, uv: Vector2) -> bool:
	if uv.x < 0.25 or uv.x > float(surface["width"]) - 0.25 or uv.y > float(surface["height"]) - 0.25:
		return false
	for hole: Rect2 in surface["holes"]:
		if is_door(hole) and hole.grow(DOOR_MARGIN).has_point(uv):
			return false
	return true

static func _point(surface: Dictionary, u: float, v: float, stand_off: float, previous: Array[Dictionary]) -> Dictionary:
	var hit: Dictionary = sample(surface, u, v)
	hit["position"] += hit["normal"] * stand_off
	hit["u"] = u
	hit["v"] = v
	hit["distance"] = 0.0 if previous.is_empty() else float(previous[-1]["distance"]) + Vector3(previous[-1]["position"]).distance_to(hit["position"])
	return hit

## Vine paths (a root stem per window/route plus two branches), ported from growth_patch._window_routes.
## Each path: {points, surface (index), length, start, parent, junction}.
static func vine_paths(surfaces: Array[Dictionary], seed_value: int, stand_off: float) -> Array[Dictionary]:
	var paths: Array[Dictionary] = []
	for surface_index: int in surfaces.size():
		var surface: Dictionary = surfaces[surface_index]
		var window_index: int = 0
		var windows: Array[Rect2] = []
		for hole_: Rect2 in surface["holes"]:
			if hole_.position.y >= 0.05:
				windows.append(hole_)
		var has_windows: bool = not windows.is_empty()
		if not has_windows:
			windows.append(Rect2(float(surface["width"]) * 0.42, float(surface["height"]) * 0.28, 0.4, float(surface["height"]) * 0.50))
		for hole: Rect2 in windows:
			var side: float = -1.0 if window_index % 2 == 0 else 1.0
			var u: float = hole.position.x - 0.13 if side < 0.0 else hole.end.x + 0.13
			var root_u: float = u
			var clear_height: float = 0.0
			for door: Rect2 in surface["holes"]:
				if is_door(door) and door.grow(0.30).has_point(Vector2(root_u, 0.0)):
					root_u = door.position.x - 0.36 if side < 0.0 else door.end.x + 0.36
					clear_height = door.end.y + 0.34
			var top: float = minf(hole.end.y + 0.16, float(surface["height"]) - 0.30)
			var points: Array[Dictionary] = []
			var steps: int = ceili(top / 0.085)
			for n: int in range(steps + 1):
				var v: float = float(n) / steps * top
				var bend: float = sin(v * 3.1 + window_index * 1.7) * 0.13 if v < hole.position.y - 0.10 else 0.0
				if not has_windows:
					bend = 0.23 * (sin(v * 2.1 + 0.8) - sin(0.8))
				if clear_height > 0.0 and v < clear_height:
					bend *= 0.20
				var actual_u: float = lerpf(root_u, u, clampf((v - clear_height) / maxf(0.1, hole.position.y - clear_height), 0.0, 1.0)) + bend
				if not route_safe(surface, Vector2(actual_u, v)):
					break
				points.append(_point(surface, actual_u, v, stand_off, points))
			if points.size() < 5:
				continue
			var parent_index: int = paths.size()
			paths.append({"points": points, "surface": surface_index, "length": float(points[-1]["distance"]), "start": 0.0, "parent": -1, "junction": -1})
			for branch_index: int in 2:
				var height_: float = hole.position.y + hole.size.y * 0.48 if branch_index == 0 else 0.55
				var junction: int = mini(roundi(height_ / top * steps), points.size() - 1)
				var origin: Dictionary = points[junction]
				var branch: Array[Dictionary] = [origin.duplicate()]
				branch[0]["distance"] = 0.0
				var reach: float = minf(0.43, hole.size.x * 0.22 + 0.13) if branch_index == 0 and has_windows else 0.63
				var direction: float = -side if branch_index == 0 else side
				for n: int in range(1, 7):
					var t: float = float(n) / 6.0
					var uv: Vector2 = Vector2(float(origin["u"]) + direction * (reach * t + sin(t * TAU) * 0.065), float(origin["v"]) + 0.13 * t + sin(t * PI) * 0.13)
					if not route_safe(surface, uv):
						break
					branch.append(_point(surface, uv.x, uv.y, stand_off, branch))
				if branch.size() > 2:
					paths.append({"points": branch, "surface": surface_index, "length": float(branch[-1]["distance"]), "start": float(origin["distance"]), "parent": parent_index, "junction": junction})
			window_index += 1
	return paths

## Duration (m of stem) until every path of a root has finished growing: root path index -> metres.
static func root_durations(paths: Array[Dictionary]) -> Dictionary:
	var durations: Dictionary = {}
	for index: int in paths.size():
		var path: Dictionary = paths[index]
		var root: int = index if int(path["parent"]) < 0 else int(path["parent"])
		durations[root] = maxf(float(durations.get(root, 0.0)), float(path["start"]) + float(path["length"]) + 0.24)
	return durations

## Moss patches (wall only), ported from surface_layers: {surface, center: Vector2, span: Vector2, phase: Vector2}.
static func moss_patches(surfaces: Array[Dictionary], seed_value: int, span_scale: float) -> Array[Dictionary]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value + 7291
	var out: Array[Dictionary] = []
	var patch_index: int = 0
	for surface_index: int in surfaces.size():
		var surface: Dictionary = surfaces[surface_index]
		var u: float = 0.48
		while u < float(surface["width"]) - 0.20:
			var large: bool = patch_index % 3 == 1
			var size_: float = 2.0 if large else 1.0
			var span: Vector2 = Vector2(size_ * rng.randf_range(0.85, 1.13), size_ * rng.randf_range(0.83, 1.12)) * span_scale
			var center: Vector2 = Vector2(u + rng.randf_range(-0.18, 0.18), rng.randf_range(0.40, 0.94))
			var phase: Vector2 = Vector2(rng.randf() * 31.0, rng.randf() * 31.0)
			if _moss_valid_cells(surface, center, span) > 0:
				out.append({"surface": surface_index, "center": center, "span": span, "phase": phase})
			u += rng.randf_range(0.90, 1.38)
			patch_index += 1
	return out

static func moss_divisions(span: Vector2) -> int:
	return maxi(6, ceili(maxf(span.x, span.y) / 0.16))

## uv of a moss grid corner (xy in 0..divisions).
static func moss_uv(center: Vector2, span: Vector2, divisions: int, xy: Vector2) -> Vector2:
	return center + (xy / float(divisions) - Vector2.ONE * 0.5) * span

static func moss_corner_ok(surface: Dictionary, uv: Vector2) -> bool:
	return not (uv.x < 0.05 or uv.x > float(surface["width"]) - 0.05 or uv.y < 0.03 or uv.y > float(surface["height"]) - 0.03 or blocked(surface, uv.x, uv.y, 0.08))

static func _moss_valid_cells(surface: Dictionary, center: Vector2, span: Vector2) -> int:
	var divisions: int = moss_divisions(span)
	var count: int = 0
	for row: int in divisions:
		for col: int in divisions:
			var ok: bool = true
			for xy: Vector2 in [Vector2(col, row), Vector2(col + 1, row), Vector2(col + 1, row + 1), Vector2(col, row + 1)]:
				if not moss_corner_ok(surface, moss_uv(center, span, divisions, xy)):
					ok = false
			if ok:
				count += 1
	return count

## Estimated covered fraction of the visible (solid) wall area at full growth, on a GRID_M raster per chart.
## Vines: leaves (every 4th point, LEAF_RADIUS_M) and stems (STEM_RADIUS_M); moss: its valid grid cells.
## Returns {ratio, covered_m2, solid_m2}.
static func coverage(surfaces: Array[Dictionary], paths: Array[Dictionary], patches: Array[Dictionary]) -> Dictionary:
	var covered_total: float = 0.0
	var solid_total: float = 0.0
	for surface_index: int in surfaces.size():
		var surface: Dictionary = surfaces[surface_index]
		var nx: int = ceili(float(surface["width"]) / GRID_M)
		var ny: int = ceili(float(surface["height"]) / GRID_M)
		var mark: PackedByteArray = PackedByteArray()
		mark.resize(nx * ny)
		for path: Dictionary in paths:
			if int(path["surface"]) != surface_index:
				continue
			var points: Array = path["points"]
			for j: int in points.size():
				var radius: float = LEAF_RADIUS_M if j % 4 == 0 else STEM_RADIUS_M
				_stamp(mark, nx, ny, Vector2(float(points[j]["u"]), float(points[j]["v"])), radius)
		for patch: Dictionary in patches:
			if int(patch["surface"]) != surface_index:
				continue
			var span: Vector2 = patch["span"]
			var divisions: int = moss_divisions(span)
			for row: int in divisions:
				for col: int in divisions:
					var ok: bool = true
					for xy: Vector2 in [Vector2(col, row), Vector2(col + 1, row), Vector2(col + 1, row + 1), Vector2(col, row + 1)]:
						if not moss_corner_ok(surface, moss_uv(patch["center"], span, divisions, xy)):
							ok = false
					if ok:
						_stamp(mark, nx, ny, moss_uv(patch["center"], span, divisions, Vector2(col + 0.5, row + 0.5)), span.x / float(divisions) * 0.5)
		for y: int in ny:
			for x: int in nx:
				var uv: Vector2 = Vector2((x + 0.5) * GRID_M, (y + 0.5) * GRID_M)
				var in_hole: bool = false
				for hole: Rect2 in surface["holes"]:
					if hole.has_point(uv):
						in_hole = true
				if in_hole:
					continue
				solid_total += GRID_M * GRID_M
				if mark[y * nx + x] == 1:
					covered_total += GRID_M * GRID_M
	return {"ratio": covered_total / maxf(solid_total, 0.0001), "covered_m2": covered_total, "solid_m2": solid_total}

static func _stamp(mark: PackedByteArray, nx: int, ny: int, uv: Vector2, radius: float) -> void:
	var x0: int = maxi(floori((uv.x - radius) / GRID_M), 0)
	var x1: int = mini(floori((uv.x + radius) / GRID_M), nx - 1)
	var y0: int = maxi(floori((uv.y - radius) / GRID_M), 0)
	var y1: int = mini(floori((uv.y + radius) / GRID_M), ny - 1)
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			if Vector2((x + 0.5) * GRID_M, (y + 0.5) * GRID_M).distance_to(uv) <= radius:
				mark[y * nx + x] = 1
