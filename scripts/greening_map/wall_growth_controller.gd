extends Node
## Visual-only delayed wall growth from fixed local target-cell neighborhoods.
const Session: GDScript = preload("res://scripts/greening_map/session.gd")
const Patch: GDScript = preload("res://scripts/vegetation_lab/growth_patch.gd")
const Layers: GDScript = preload("res://scripts/vegetation_lab/surface_layers.gd")
const Geometry: GDScript = preload("res://scripts/vegetation_lab/building_geometry.gd")
const WallCracks: GDScript = preload("res://scripts/greening_map/wall_cracks.gd")
const RADIUS: float = 0.65
const VINE_SECONDS: float = 90.0
const MOSS_SECONDS: float = 135.0
var session: RefCounted
var entries: Array[Dictionary] = []
var tick_count: int = 0

func setup(model: RefCounted, buildings: Array[Dictionary], library: RefCounted) -> void:
	session = model
	var moss_material: ShaderMaterial = ShaderMaterial.new()
	moss_material.shader = Layers.Moss
	moss_material.set_shader_parameter("coverage",0.0)
	var crack_material: ShaderMaterial = ShaderMaterial.new()
	crack_material.shader = Layers.Cracks
	for building: Dictionary in buildings:
		var node: Node3D = building["node"]
		var def: Dictionary = building["definition"]
		var tile_rect: Rect2i = building["footprint"]
		var footprint: Rect2 = Rect2(Session.ORIGIN+Vector2(tile_rect.position)*Session.CELL,Vector2(tile_rect.size)*Session.CELL)
		var patch: Node3D = Patch.new()
		node.add_child(patch)
		patch.setup(def,library,{"include_ground":false,"walls_only":true,"sparse_windows":true})
		var layer: Node3D = Layers.new()
		node.add_child(layer)
		layer.setup(def,moss_material,crack_material,{"walls_only":true,"individual_moss":true,"include_cracks":false,"moss_span_scale":0.40})
		var wall_cracks: Node3D = WallCracks.new()
		node.add_child(wall_cracks)
		wall_cracks.setup(def)
		var roots: Array[Dictionary] = []
		var values: Dictionary = {}
		for path_index: int in patch.paths.size():
			var path: Dictionary = patch.paths[path_index]
			if path["parent"]>=0:
				continue
			var hit: Dictionary = path["points"][0]
			var anchor: Vector2 = outside_anchor(node.global_position+hit["position"],hit["normal"],footprint)
			roots.append({"path":path_index,"anchor":anchor,"cells":nearby_cells(anchor,footprint),"progress":0.0,"input":0.0})
			values[path_index] = 0.0
		patch.set_root_progress(values)
		var moss: Array[Dictionary] = []
		for index: int in layer.moss_entries.size():
			var item: Dictionary = layer.moss_entries[index]
			var hit: Dictionary = Geometry.sample(item["surface"],item["center"].x,0)
			var anchor: Vector2 = outside_anchor(node.global_position+hit["position"],hit["normal"],footprint)
			moss.append({"patch":index,"anchor":anchor,"cells":nearby_cells(anchor,footprint),"progress":0.0,"input":0.0})
		entries.append({"id":def["id"],"patch":patch,"layer":layer,"roots":roots,"moss":moss,"cracks":wall_cracks})
	session.clock.growth_ticked.connect(_growth_tick)

func outside_anchor(point: Vector3, normal: Vector3, footprint: Rect2) -> Vector2:
	var p: Vector2 = Vector2(point.x,point.z)
	if normal.x>0.5:
		p.x = footprint.end.x+0.20
	elif normal.x< -0.5:
		p.x = footprint.position.x-0.20
	if normal.z>0.5:
		p.y = footprint.end.y+0.20
	elif normal.z< -0.5:
		p.y = footprint.position.y-0.20
	return p

func nearby_cells(anchor: Vector2, footprint: Rect2) -> PackedInt32Array:
	var cells: PackedInt32Array = PackedInt32Array()
	for index: int in session.state.tile_count():
		var p: Vector2 = Session.cell_center(index)
		if session.state.target[index]==1 and not footprint.has_point(p) and p.distance_squared_to(anchor)<=RADIUS*RADIUS:
			cells.append(index)
	return cells

func local_input(cells: PackedInt32Array) -> float:
	if cells.is_empty():
		return 0
	var total: float = 0
	for index: int in cells:
		var stage: int = session.state.stage[index]
		if stage==WorldState.STAGE_MATURE:
			total += 1.0
		elif stage>=WorldState.STAGE_SPROUT1:
			total += clampf(float(session.state.growth[index])/float(session.sim_tuning.mature_growth),0,1)
	return total/float(cells.size()) # Empty target cells stay in this denominator.

func _growth_tick(_index: int) -> void:
	tick_count += 1
	var dt: float = session.sim_tuning.growth_tick_seconds
	for entry: Dictionary in entries:
		var values: Dictionary = {}
		for root: Dictionary in entry["roots"]:
			root["input"] = local_input(root["cells"])
			root["progress"] = minf(1.0,float(root["progress"])+dt*float(root["input"])/VINE_SECONDS)
			values[root["path"]] = root["progress"]
		entry["patch"].set_root_progress(values)
		for moss: Dictionary in entry["moss"]:
			moss["input"] = local_input(moss["cells"])
			moss["progress"] = minf(1.0,float(moss["progress"])+dt*float(moss["input"])/MOSS_SECONDS)
			entry["layer"].set_patch_progress(moss["patch"],moss["progress"])

func snapshot() -> Dictionary:
	var rows: Array[Dictionary] = []
	for entry: Dictionary in entries:
		rows.append({"building":entry["id"],"roots":entry["roots"].duplicate(true),"moss":entry["moss"].duplicate(true)})
	return {"growth_ticks":tick_count,"radius":RADIUS,"vine_seconds":VINE_SECONDS,"moss_seconds":MOSS_SECONDS,"entries":rows}

func _exit_tree() -> void:
	if session!=null and session.clock.growth_ticked.is_connected(_growth_tick):
		session.clock.growth_ticked.disconnect(_growth_tick)
