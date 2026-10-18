extends RefCounted
## POC-02 placement: reads the asset catalog and a placement map (instance id, asset id, position m, yaw), builds the
## collision shapes in metres, rasterizes them to the 0.4 m logical cells as an obstacle layer (with per-instance
## ownership) and writes the result into WorldState (obstacle cell -> terrain "building": not walkable, not a greening
## target). The base terrain is kept separately, so removing/moving a placement restores the original cells.
## No rendering dependency; the GLB is only instantiated (not added to a tree) to read its meshes. Works headless.
##
## Judgement API (all read the same WorldState, nothing else): blocks_walk, blocks_projectile, can_plant,
## is_greening_target, target_count, is_water_source.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")

const DEFAULT_CATALOG: String = "res://data/poc/asset_catalog.json"
## Fine samples per cell side used to measure how much of a cell a collision shape covers.
const FINE: int = 4
## A cell is an obstacle when at least this fraction of it is covered (cell-centre-like rule: a 0.4 m wall always
## blocks at least one cell and never leaks; a wall-to-wall clear gap G leaves about G - 0.4 m free).
const COVER_MIN: float = 0.5
## Vertical faces are thin; they are thickened by this much on each side before rasterizing.
const WALL_GROW_M: float = 0.2
## Only vertical faces between these heights above the placed floor count (same rule as the town lab).
const WALL_MIN_Y: float = 0.15
const WALL_MAX_Y: float = 1.6
const DEDUP_M: float = 0.025
## Faces count as walls when the normal is this close to horizontal (|normal.y| <= value).
const WALL_MAX_NORMAL_Y: float = 0.3

## glb path -> {offset: Vector3 (model.position that puts the AABB centre xz on the origin and the bottom at y=0),
## size: Vector3, tris: PackedVector3Array (vertical ground-height faces in the placed local frame)}
static var _shapes: Dictionary = {}

var catalog: Dictionary = {}
var instances: Array[Dictionary] = []
var width: int = 0
var height: int = 0
var state: WorldState
var base_terrain: PackedByteArray = PackedByteArray()
## 1 where a placed object blocks walking (also the cells written as terrain "building").
var obstacle: PackedByteArray = PackedByteArray()
## 1 where a projectile stops (placed objects that block projectiles, plus base terrain building).
var projectile: PackedByteArray = PackedByteArray()
## Instance index + 1 that owns the obstacle cell (0 = none).
var owner_index: PackedInt32Array = PackedInt32Array()
var puddle: PackedByteArray = PackedByteArray()
## instance_id -> PackedInt32Array of the obstacle cell indices it owns.
var cells_of: Dictionary = {}
var player_start_cell: Vector2i = Vector2i(24, 20)
var building_id: int = -1
## Walkable cells that cannot be reached from player_start_cell (building interiors, closed yards) become obstacles:
## interiors are out of scope for the PoC and must not count in the greening denominator.
var seal_enclosed: bool = true
var sealed_count: int = 0
## POC-04: extra cells (islands, shooting-only ground) treated as open when sealing enclosed interiors, in addition to the
## player start. Empty by default (POC-02 behaviour unchanged).
var reach_seeds: Array[Vector2i] = []

# ---------------------------------------------------------------- loading

static func _read_json(path: String) -> Variant:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	return JSON.parse_string(text)

func load_catalog(path: String = DEFAULT_CATALOG) -> bool:
	var data: Variant = _read_json(path)
	if not (data is Dictionary) or not (data as Dictionary).has("assets"):
		return false
	catalog = {}
	for entry: Dictionary in (data as Dictionary)["assets"]:
		catalog[entry["id"]] = entry
	return true

## Loads a placement map. Instances: {instance_id, asset (or kind "puddle"), pos [x,z] m, yaw_deg, radius (puddle)}.
func load_map(path: String) -> bool:
	var data: Variant = _read_json(path)
	if not (data is Dictionary):
		return false
	var map: Dictionary = data
	if catalog.is_empty() and not load_catalog(map.get("catalog", DEFAULT_CATALOG)):
		return false
	instances.clear()
	for entry: Dictionary in map.get("instances", []):
		var pos: Array = entry["pos"]
		var inst: Dictionary = {
			"id": entry["instance_id"],
			"asset": entry.get("asset", ""),
			"kind": entry.get("kind", catalog.get(entry.get("asset", ""), {}).get("kind", "prop")),
			"pos": Vector2(pos[0], pos[1]),
			"yaw": deg_to_rad(float(entry.get("yaw_deg", 0.0))),
			"radius": float(entry.get("radius", 0.0)),
		}
		if inst["asset"] != "" and not catalog.has(inst["asset"]):
			return false
		instances.append(inst)
	var start: Array = map.get("player_start_cell", [24, 20])
	player_start_cell = Vector2i(start[0], start[1])
	return validate_ids()

func validate_ids() -> bool:
	var seen: Dictionary = {}
	for inst: Dictionary in instances:
		if seen.has(inst["id"]):
			return false
		seen[inst["id"]] = true
	return true

## True when every adopted GLB / metadata file still has the recorded sha256.
func verify_hashes() -> bool:
	for id: String in catalog:
		var entry: Dictionary = catalog[id]
		if FileAccess.get_sha256(entry["glb"]) != entry["glb_sha256"]:
			return false
		if FileAccess.get_sha256(entry["metadata"]) != entry["metadata_sha256"]:
			return false
	return true

func instance_index(instance_id: String) -> int:
	for i: int in instances.size():
		if instances[i]["id"] == instance_id:
			return i
	return -1

func get_instance(instance_id: String) -> Dictionary:
	var i: int = instance_index(instance_id)
	return instances[i] if i >= 0 else {}

# ---------------------------------------------------------------- editing (re-placement)

func move_instance(instance_id: String, pos: Vector2, yaw_deg: float, rebuild_now: bool = true) -> bool:
	var i: int = instance_index(instance_id)
	if i < 0:
		return false
	instances[i]["pos"] = pos
	instances[i]["yaw"] = deg_to_rad(yaw_deg)
	if rebuild_now:
		rebuild()
	return true

func remove_instance(instance_id: String, rebuild_now: bool = true) -> bool:
	var i: int = instance_index(instance_id)
	if i < 0:
		return false
	instances.remove_at(i)
	if rebuild_now:
		rebuild()
	return true

func add_instance(instance_id: String, asset: String, pos: Vector2, yaw_deg: float = 0.0, rebuild_now: bool = true) -> bool:
	if instance_index(instance_id) >= 0 or not catalog.has(asset):
		return false
	instances.append({"id": instance_id, "asset": asset, "kind": catalog[asset].get("kind", "prop"), "pos": pos, "yaw": deg_to_rad(yaw_deg), "radius": 0.0})
	if rebuild_now:
		rebuild()
	return true

# ---------------------------------------------------------------- shapes (GLB meshes -> metres)

static func _collect(node: Node, xf: Transform3D, out: Array) -> void:
	var local: Transform3D = xf
	if node is Node3D:
		local = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append({"mesh": (node as MeshInstance3D).mesh, "xf": local})
	for child: Node in node.get_children():
		_collect(child, local, out)

## Placement frame of a GLB: `offset` is the model position that centres the AABB on x/z and puts the bottom at y=0
## (same as the town lab). `tris` are the vertical faces in that frame. Cached per GLB path.
static func shape_of(glb_path: String) -> Dictionary:
	if _shapes.has(glb_path):
		return _shapes[glb_path]
	var scene: PackedScene = load(glb_path) as PackedScene
	if scene == null:
		return {}
	var model: Node3D = scene.instantiate() as Node3D
	var meshes: Array = []
	_collect(model, Transform3D.IDENTITY, meshes)
	var bounds: AABB = AABB()
	var first: bool = true
	for item: Dictionary in meshes:
		var box: AABB = (item["xf"] as Transform3D) * (item["mesh"] as Mesh).get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var offset: Vector3 = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)
	var tris: PackedVector3Array = PackedVector3Array()
	for item: Dictionary in meshes:
		var xf: Transform3D = item["xf"]
		var faces: PackedVector3Array = (item["mesh"] as Mesh).get_faces()
		for i: int in range(0, faces.size() - 2, 3):
			var a: Vector3 = xf * faces[i] + offset
			var b: Vector3 = xf * faces[i + 1] + offset
			var c: Vector3 = xf * faces[i + 2] + offset
			if maxf(a.y, maxf(b.y, c.y)) < WALL_MIN_Y or minf(a.y, minf(b.y, c.y)) > WALL_MAX_Y:
				continue
			var normal: Vector3 = (b - a).cross(c - a).normalized()
			if absf(normal.y) > WALL_MAX_NORMAL_Y:
				continue
			tris.append(a)
			tris.append(b)
			tris.append(c)
	model.free()
	var shape: Dictionary = {"offset": offset, "size": bounds.size, "tris": tris}
	_shapes[glb_path] = shape
	return shape

func asset_shape(asset_id: String) -> Dictionary:
	return shape_of(catalog[asset_id]["glb"])

# ---------------------------------------------------------------- rasterization

func _fine_size() -> Vector2i:
	return Vector2i(width * FINE, height * FINE)

## Marks fine samples whose centre satisfies `inside` over the fine range [lo, hi]. Returns nothing; tracks the window.
func _fine_range(box: Rect2) -> Rect2i:
	var step: float = Config.CELL_M / float(FINE)
	var x0: int = ceili((box.position.x - Coords.ORIGIN.x) / step - 0.5)
	var x1: int = floori((box.end.x - Coords.ORIGIN.x) / step - 0.5)
	var y0: int = ceili((box.position.y - Coords.ORIGIN.y) / step - 0.5)
	var y1: int = floori((box.end.y - Coords.ORIGIN.y) / step - 0.5)
	var fs: Vector2i = _fine_size()
	x0 = maxi(x0, 0)
	y0 = maxi(y0, 0)
	x1 = mini(x1, fs.x - 1)
	y1 = mini(y1, fs.y - 1)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

func _rotate(v: Vector2, yaw: float) -> Vector2:
	var b: Basis = Basis(Vector3.UP, yaw)
	var r: Vector3 = b * Vector3(v.x, 0.0, v.y)
	return Vector2(r.x, r.z)

## Rasterizes one instance; returns {cells: PackedInt32Array, coverage: PackedFloat32Array}.
func _raster(inst: Dictionary) -> PackedInt32Array:
	var entry: Dictionary = catalog.get(inst["asset"], {})
	var kind: String = entry.get("collision", "none")
	var fs: Vector2i = _fine_size()
	var fine: PackedByteArray = PackedByteArray()
	fine.resize(fs.x * fs.y)
	var step: float = Config.CELL_M / float(FINE)
	var pos: Vector2 = inst["pos"]
	var yaw: float = inst["yaw"]
	var window: Rect2i = Rect2i()
	var have_window: bool = false
	var guaranteed: PackedInt32Array = PackedInt32Array()
	if kind == "none":
		return PackedInt32Array()
	var shape: Dictionary = shape_of(entry["glb"])
	if kind == "walls":
		var tris: PackedVector3Array = shape["tris"]
		var seen: Dictionary = {}
		for i: int in range(0, tris.size() - 2, 3):
			var lo: Vector2 = Vector2(INF, INF)
			var hi: Vector2 = Vector2(-INF, -INF)
			for k: int in 3:
				var p: Vector2 = pos + _rotate(Vector2(tris[i + k].x, tris[i + k].z), yaw)
				lo = lo.min(p)
				hi = hi.max(p)
			var key: Vector4i = Vector4i(roundi(lo.x / DEDUP_M), roundi(lo.y / DEDUP_M), roundi(hi.x / DEDUP_M), roundi(hi.y / DEDUP_M))
			if seen.has(key):
				continue
			seen[key] = true
			var fr: Rect2i = _fine_range(Rect2(lo, hi - lo).grow(WALL_GROW_M))
			if fr.size.x <= 0 or fr.size.y <= 0:
				continue
			for fy: int in range(fr.position.y, fr.end.y):
				var row: int = fy * fs.x
				for fx: int in range(fr.position.x, fr.end.x):
					fine[row + fx] = 1
			window = fr if not have_window else window.merge(fr)
			have_window = true
	elif kind == "aabb":
		var half: Vector2 = Vector2(shape["size"].x, shape["size"].z) * 0.5
		var corners: Array[Vector2] = [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]
		var lo2: Vector2 = Vector2(INF, INF)
		var hi2: Vector2 = Vector2(-INF, -INF)
		for corner: Vector2 in corners:
			var p2: Vector2 = pos + _rotate(corner, yaw)
			lo2 = lo2.min(p2)
			hi2 = hi2.max(p2)
		window = _fine_range(Rect2(lo2, hi2 - lo2))
		have_window = window.size.x > 0 and window.size.y > 0
		if have_window:
			for fy: int in range(window.position.y, window.end.y):
				for fx: int in range(window.position.x, window.end.x):
					var center: Vector2 = Coords.ORIGIN + Vector2((float(fx) + 0.5) * step, (float(fy) + 0.5) * step)
					var local: Vector2 = _rotate(center - pos, -yaw)
					if absf(local.x) <= half.x and absf(local.y) <= half.y:
						fine[fy * fs.x + fx] = 1
		guaranteed.append(_cell_index(pos))
	elif kind == "circle":
		var radius: float = float(entry.get("radius", 0.3))
		# The circle sits on the GLB origin (trunk / pole foot), not on the AABB centre.
		var origin_local: Vector3 = -(shape["offset"] as Vector3)
		var center_g: Vector2 = pos + _rotate(Vector2(origin_local.x, origin_local.z), yaw)
		window = _fine_range(Rect2(center_g - Vector2(radius, radius), Vector2(radius, radius) * 2.0))
		have_window = window.size.x > 0 and window.size.y > 0
		if have_window:
			for fy: int in range(window.position.y, window.end.y):
				for fx: int in range(window.position.x, window.end.x):
					var c: Vector2 = Coords.ORIGIN + Vector2((float(fx) + 0.5) * step, (float(fy) + 0.5) * step)
					if c.distance_to(center_g) <= radius:
						fine[fy * fs.x + fx] = 1
		guaranteed.append(_cell_index(center_g))
	var out: PackedInt32Array = PackedInt32Array()
	if have_window:
		var cx0: int = window.position.x / FINE
		var cx1: int = (window.end.x - 1) / FINE
		var cy0: int = window.position.y / FINE
		var cy1: int = (window.end.y - 1) / FINE
		var need: int = ceili(COVER_MIN * float(FINE * FINE) - 0.0001)
		for cy: int in range(cy0, cy1 + 1):
			for cx: int in range(cx0, cx1 + 1):
				var count: int = 0
				for sy: int in FINE:
					var row2: int = (cy * FINE + sy) * fs.x + cx * FINE
					for sx: int in FINE:
						count += fine[row2 + sx]
				if count >= need:
					out.append(cy * width + cx)
	for g: int in guaranteed:
		if g >= 0 and not out.has(g) and out.is_empty():
			out.append(g)
	return out

func _cell_index(ground: Vector2) -> int:
	var cell: Vector2i = Coords.ground_to_cell(ground)
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return -1
	return cell.y * width + cell.x

## Recomputes the obstacle layer from the instances and (when attached) writes WorldState.
func rebuild() -> void:
	var n: int = width * height
	obstacle = PackedByteArray()
	obstacle.resize(n)
	projectile = PackedByteArray()
	projectile.resize(n)
	puddle = PackedByteArray()
	puddle.resize(n)
	owner_index = PackedInt32Array()
	owner_index.resize(n)
	cells_of = {}
	for k: int in instances.size():
		var inst: Dictionary = instances[k]
		if inst["kind"] == "puddle":
			_mark_puddle(inst)
			cells_of[inst["id"]] = PackedInt32Array()
			continue
		var cells: PackedInt32Array = _raster(inst)
		cells_of[inst["id"]] = cells
		var blocks_shot: bool = bool(catalog[inst["asset"]].get("blocks_projectile", false))
		for index: int in cells:
			obstacle[index] = 1
			if blocks_shot:
				projectile[index] = 1
			if owner_index[index] == 0:
				owner_index[index] = k + 1
	sealed_count = 0
	if state != null:
		if seal_enclosed:
			_seal_enclosed()
		_sync_state()

func _base_walkable(index: int) -> bool:
	return state.walkable_by_terrain[base_terrain[index]] == 1

func _seal_enclosed() -> void:
	var start: int = player_start_cell.y * width + player_start_cell.x
	if not _valid(player_start_cell) or obstacle[start] == 1 or not _base_walkable(start):
		return
	var reached: PackedByteArray = PackedByteArray()
	reached.resize(width * height)
	var stack: PackedInt32Array = PackedInt32Array([start])
	reached[start] = 1
	for extra: Vector2i in reach_seeds:
		if _valid(extra):
			var extra_index: int = extra.y * width + extra.x
			if reached[extra_index] == 0 and obstacle[extra_index] == 0 and _base_walkable(extra_index):
				reached[extra_index] = 1
				stack.append(extra_index)
	while not stack.is_empty():
		var index: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var x: int = index % width
		var y: int = index / width
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				continue
			var ni: int = ny * width + nx
			if reached[ni] == 0 and obstacle[ni] == 0 and _base_walkable(ni):
				reached[ni] = 1
				stack.append(ni)
	var sealed: PackedInt32Array = PackedInt32Array()
	for i: int in width * height:
		if reached[i] == 0 and obstacle[i] == 0 and _base_walkable(i):
			sealed.append(i)
	# Hand the sealed cells to the neighbouring owner (breadth by repeated passes) so the owner list stays complete.
	var pending: PackedInt32Array = sealed
	while not pending.is_empty():
		var rest: PackedInt32Array = PackedInt32Array()
		for i: int in pending:
			var found: int = 0
			var cx: int = i % width
			var cy: int = i / width
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = cx + d.x
				var ny: int = cy + d.y
				if nx >= 0 and ny >= 0 and nx < width and ny < height and owner_index[ny * width + nx] > 0:
					found = owner_index[ny * width + nx]
					break
			if found > 0:
				owner_index[i] = found
			else:
				rest.append(i)
		if rest.size() == pending.size():
			break
		pending = rest
	for i: int in sealed:
		obstacle[i] = 1
		# POC-03: a sealed interior cell stops shots too (the outer wall normally stops them first).
		projectile[i] = 1
		if owner_index[i] > 0:
			var id: String = instances[owner_index[i] - 1]["id"]
			var list: PackedInt32Array = cells_of[id]
			list.append(i)
			cells_of[id] = list
	sealed_count = sealed.size()

func _mark_puddle(inst: Dictionary) -> void:
	var radius: float = float(inst["radius"])
	var pos: Vector2 = inst["pos"]
	var lo: Vector2i = Coords.ground_to_cell(pos - Vector2(radius, radius))
	var hi: Vector2i = Coords.ground_to_cell(pos + Vector2(radius, radius))
	for y: int in range(maxi(lo.y, 0), mini(hi.y, height - 1) + 1):
		for x: int in range(maxi(lo.x, 0), mini(hi.x, width - 1) + 1):
			if Coords.cell_center_ground(Vector2i(x, y)).distance_to(pos) <= radius:
				puddle[y * width + x] = 1

# ---------------------------------------------------------------- WorldState link

## Attaches to a WorldState (any size) with its base terrain (kept separate; never modified here) and rebuilds.
## Setup-time call: apply_terrain_defs() resets target/stage/plant data of the whole map.
func attach(world_state: WorldState, base: PackedByteArray) -> void:
	state = world_state
	width = world_state.width
	height = world_state.height
	base_terrain = base.duplicate()
	building_id = -1
	for def: TerrainDef in world_state.terrain_defs:
		if def.key == &"building":
			building_id = def.id
	rebuild()

func detach() -> void:
	if state == null:
		return
	obstacle.fill(0)
	projectile.fill(0)
	_sync_state()
	state = null

func _sync_state() -> void:
	for i: int in width * height:
		state.terrain[i] = building_id if obstacle[i] == 1 else base_terrain[i]
	state.apply_terrain_defs()

# ---------------------------------------------------------------- common judgement API (WorldState only)

func _valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height

func blocks_walk(cell: Vector2i) -> bool:
	return not state.is_walkable(cell.x, cell.y)

func can_plant(cell: Vector2i) -> bool:
	return _valid(cell) and state.can_plant(cell.y * width + cell.x)

func is_greening_target(cell: Vector2i) -> bool:
	return _valid(cell) and state.is_target_tile(cell.y * width + cell.x)

var target_count: int:
	get:
		return state.target_count

## Constant water source = terrain flagged waterside (water / shore). A decorative puddle is never a source.
func is_water_source(cell: Vector2i) -> bool:
	if not _valid(cell):
		return false
	return state.terrain_def_at(cell.y * width + cell.x).is_waterside

func is_puddle(cell: Vector2i) -> bool:
	return _valid(cell) and puddle[cell.y * width + cell.x] == 1

func projectile_blocked_cell(cell: Vector2i) -> bool:
	if not _valid(cell):
		return true
	var index: int = cell.y * width + cell.x
	if projectile[index] == 1:
		return true
	return building_id >= 0 and state.terrain[index] == building_id and obstacle[index] == 0

## Segment between two logical-px points; true when any cell it crosses (start and end included) stops projectiles.
func blocks_projectile(from_logic: Vector2, to_logic: Vector2) -> bool:
	var a: Vector2 = from_logic / float(Config.TILE_PX)
	var b: Vector2 = to_logic / float(Config.TILE_PX)
	var cell: Vector2i = Vector2i(floori(a.x), floori(a.y))
	var last: Vector2i = Vector2i(floori(b.x), floori(b.y))
	if projectile_blocked_cell(cell):
		return true
	var d: Vector2 = b - a
	var step: Vector2i = Vector2i(1 if d.x > 0.0 else -1, 1 if d.y > 0.0 else -1)
	var t_delta: Vector2 = Vector2(INF if d.x == 0.0 else absf(1.0 / d.x), INF if d.y == 0.0 else absf(1.0 / d.y))
	var t_max: Vector2 = Vector2(
		INF if d.x == 0.0 else ((float(cell.x + (1 if d.x > 0.0 else 0)) - a.x) / d.x),
		INF if d.y == 0.0 else ((float(cell.y + (1 if d.y > 0.0 else 0)) - a.y) / d.y))
	var guard: int = absi(last.x - cell.x) + absi(last.y - cell.y) + 2
	while cell != last and guard > 0:
		guard -= 1
		if t_max.x < t_max.y:
			cell.x += step.x
			t_max.x += t_delta.x
		else:
			cell.y += step.y
			t_max.y += t_delta.y
		if projectile_blocked_cell(cell):
			return true
	return false

# ---------------------------------------------------------------- debug

## ASCII picture of a cell rectangle: # placed obstacle, % base building (ring), ~ water, : puddle, o target, . other.
func ascii(region: Rect2i = Rect2i(0, 0, 0, 0)) -> String:
	var r: Rect2i = region if region.size.x > 0 else Rect2i(0, 0, width, height)
	var lines: PackedStringArray = []
	for y: int in range(r.position.y, r.end.y):
		var line: String = ""
		for x: int in range(r.position.x, r.end.x):
			var i: int = y * width + x
			var ch: String = "."
			if obstacle[i] == 1:
				ch = "#"
			elif state.terrain[i] == building_id:
				ch = "%"
			elif not state.is_walkable(x, y):
				ch = "~"
			elif puddle[i] == 1:
				ch = ":"
			elif state.target[i] == 1:
				ch = "o"
			line += ch
		lines.append(line)
	return "\n".join(lines)
