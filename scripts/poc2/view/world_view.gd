extends Node3D
## PoC2 scene adapter: reuses adopted assets and one dirty-list consumer.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Actor: GDScript = preload("res://scripts/poc/poc_actor.gd")
const PlacementView: GDScript = preload("res://scripts/poc/assets/placement_view.gd")
const Ground: GDScript = preload("res://scripts/poc/environment/ground_cover.gd")
const Water: GDScript = preload("res://scripts/poc/environment/water_view.gd")
const Walls: GDScript = preload("res://scripts/poc/environment/wall_view.gd")
const Day: GDScript = preload("res://scripts/poc/environment/poc_day.gd")
const Cutaway: GDScript = preload("res://scripts/poc2/view/cutaway_view.gd")
var session: RefCounted
var camera: Camera3D
var sun: DirectionalLight3D
var actor: Node3D
var ground: Node3D
var placement_view: Node3D
var wall_view: Node3D
var water: Node3D
var occlusion: Node
var environment: Environment
var entities: Dictionary = {}
var _light_bucket: int = -99999
var light_updates: int = 0
var animation_time: float = 0.0
var facing: StringName = &"down"
var walking: bool = false
var fire_time: float = 0.0
var fire_kind: StringName = &""
var marker: MeshInstance3D
var last_position: Vector2
var preview: Dictionary = {}
var _last_clock: float = 0.0

func build(source: RefCounted, viewport: SubViewport) -> void:
	session = source
	last_position = source.position
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = Config.CAMERA_SIZE_M
	camera.far = Config.CAMERA_FAR_M
	add_child(camera)
	camera.current = true
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("29332f")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("9fadb8")
	environment.ambient_light_energy = 0.55
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = environment
	add_child(env)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 95.0
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 0.4
	sun.light_angular_distance = 0.0
	sun.shadow_caster_mask = 1 | 8
	add_child(sun)
	_build_terrain_meshes()
	if source.placement != null:
		placement_view = PlacementView.new()
		add_child(placement_view)
		placement_view.build(source.placement)
	if source.wall_growth != null:
		wall_view = Walls.new()
		add_child(wall_view)
		wall_view.build(source.wall_growth, source.env_tuning.get("wall", {}))
	ground = Ground.new()
	add_child(ground)
	ground.build(source, source.env_tuning)
	source.state.clear_dirty()
	water = Water.new()
	add_child(water)
	water.setup(viewport, camera, source, source.env_tuning, placement_view)
	actor = Actor.new()
	add_child(actor)
	actor.setup(camera)
	marker = _mesh("marker", Color("bdeaa2"), false)
	marker.visible = false
	if placement_view != null:
		occlusion = Cutaway.new()
		add_child(occlusion)
		occlusion.setup(placement_view, camera, wall_view)
	sync(0.0)

func _mesh(key: String, color: Color, sphere: bool = true) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = key
	if sphere:
		var mesh: SphereMesh = SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 1.0
		mesh.radial_segments = 8
		mesh.rings = 4
		node.mesh = mesh
	else:
		node.mesh = BoxMesh.new()
	var material_: StandardMaterial3D = StandardMaterial3D.new()
	material_.albedo_color = color
	material_.roughness = 1.0
	material_.metallic_specular = 0.0
	node.material_override = material_
	add_child(node)
	return node

static func color_for(kind: String) -> Color:
	return {"clover": Color("79b45a"), "carrot": Color("f39c43"), "wheat": Color("e8cd79"), "rafflesia": Color("cb5d6d"), "watermelon": Color("478950"), "army": Color("aec75e"), "gatlinger": Color("d9af54"), "sprinkler": Color("75c8dc"), "boar": Color("a77b70"), "spider": Color("9875a4"), "mother": Color("bb81ae"), "nest": Color("8b6352"), "seed": Color("f0d280"), "bazooka": Color("f4a558"), "water": Color("75c8dc")}.get(kind, Color("d4bc91"))

func sync(dt: float) -> void:
	var foot: Vector3 = Coords.ground3(Coords.logic_to_ground(session.position))
	var offset: Vector3 = Vector3(0.6123724, 0.5, 0.6123724) * Config.CAMERA_DISTANCE_M
	var target: Vector3 = foot + Vector3.UP * Config.CAMERA_TARGET_HEIGHT_M
	# Snap camera translation in both camera image axes, without changing simulation positions.
	var right: Vector3 = Vector3(0.70710678, 0, -0.70710678)
	var up: Vector3 = Vector3(-0.35355339, 0.8660254, -0.35355339)
	var pixel: float = camera.size / 360.0
	target += right * (snappedf(target.dot(right), pixel) - target.dot(right))
	target += up * (snappedf(target.dot(up), pixel) - target.dot(up))
	camera.position = target + offset
	camera.look_at(target, Vector3.UP)
	var game_dt: float = maxf(float(session.clock.elapsed) - _last_clock, 0.0)
	_last_clock = session.clock.elapsed
	animation_time += game_dt
	walking = session.position.distance_squared_to(last_position) > 0.00001
	last_position = session.position
	if session.has_aim:
		var screen_dir: Vector2 = Coords.ground_dir_to_screen(session.aim - session.position)
		if absf(screen_dir.x) > absf(screen_dir.y):
			facing = &"right" if screen_dir.x > 0 else &"left"
		else:
			facing = &"down" if screen_dir.y > 0 else &"up"
	fire_time = maxf(fire_time - game_dt, 0.0)
	var firing: StringName = fire_kind if fire_time > 0.0 else &""
	actor.pose(foot, int(animation_time * 7.0) % 4, facing, sun, 0, walking, firing, 2 if fire_time > 0.08 else 3)
	ground.apply(session.state.take_dirty()) # The ONLY dirty-list consumer.
	if wall_view != null: wall_view.sync()
	_lighting()
	water.sync_camera()
	if occlusion != null: occlusion.update(dt, foot, actor.pixel_size * 34.0)
	_entities()

func show_fire(kind: StringName) -> void:
	fire_time = 0.25
	fire_kind = kind

func _lighting() -> void:
	# One-degree game-hour buckets (~2.5 seconds at a 600s day) stop per-frame shadow crawling.
	var hour: float = session.day_hour()
	var bucket: int = floori(hour * 10.0)
	if bucket == _light_bucket: return
	_light_bucket = bucket
	light_updates += 1
	var day: Dictionary = Day.state(float(bucket) / 10.0, session.env_tuning)
	var moon: bool = float(day.altitude) <= 0.0
	var direction: Vector3 = day.moon_source if moon else day.source
	sun.global_transform = Transform3D(Basis.looking_at(-direction, Vector3.UP), Vector3(0,10,0))
	sun.light_energy = 0.18 * float(day.moon_power) if moon else 0.8 * float(day.sun_power)
	sun.light_color = Color("90b5e0") if moon else day.sun_color
	var daylight: float = float(day.daylight)
	environment.ambient_light_energy = lerpf(0.3, 0.55, daylight)
	environment.ambient_light_color = Color("6b85b5").lerp(Color("9fadb8"), daylight)
	environment.background_color = Color("172334").lerp(Color("29332f"), daylight)
	water.set_daylight(daylight)

func _visible(logic: Vector2) -> bool:
	var cell: Vector2i = Coords.logic_to_cell(logic)
	return session.state.in_bounds(cell.x, cell.y) and session.visible[session.state.index_of(cell.x, cell.y)] != 0

func _entities() -> void:
	var seen: Dictionary = {}
	var alive: Dictionary = {}
	for category: String in ["plants", "helpers", "enemies", "nests", "fossils", "shots"]:
		for item: Dictionary in session.get(category):
			if float(item.get("hp", 1.0)) <= 0: continue
			var key: String = category + str(item.id)
			alive[key] = true
			if category in ["enemies", "nests", "fossils"] and not _visible(item.pos): continue
			if category == "fossils" and (bool(item.get("found", false)) or int(item.get("nest_id", -1)) >= 0): continue
			seen[key] = true
			var node: MeshInstance3D = entities.get(key) as MeshInstance3D
			var kind: String = item.get("kind", "seed")
			if node == null:
				node = _mesh(key, color_for(kind), category != "nests")
				entities[key] = node
				if category == "helpers": _helper_parts(node, kind)
				if category == "enemies" or (category == "nests" and bool(item.get("mother", false))): _animal_parts(node, kind)
			var height: float = 0.55
			var width: float = 0.55
			var depth: float = -1.0
			if category == "plants":
				var footprint: Vector2i = item.size
				width = float(footprint.x) * 0.4 * 0.85
				depth = float(footprint.y) * 0.4 * 0.85
				height = 0.15 + 0.6 * clampf(float(item.age) / maxf(float(item.maturity), 1.0), 0.0, 1.0)
			elif category == "nests":
				width = {"small": 1.1, "medium": 1.5, "large": 2.2}.get(String(item.get("scale", "small")), 1.1)
				height = width * 0.65
			elif category == "fossils":
				width = 0.35
				height = 0.35
			elif category == "shots":
				width = 0.22 if kind == "bazooka" else 0.12
				height = width
			node.scale = Vector3(width, height, depth if depth>0 else width)
			var at: Vector2 = Coords.logic_to_ground(item.pos)
			node.position = Vector3(at.x, height * 0.5, at.y)
			node.visible = true
			if category == "enemies":
				var material_: StandardMaterial3D = node.material_override as StandardMaterial3D
				material_.albedo_color = Color("f2c372") if String(item.get("phase", "")) in ["windup", "tell"] else color_for(kind)
	for key: Variant in entities.keys():
		if not alive.has(key):
			(entities[key] as Node3D).queue_free()
			entities.erase(key)
		elif not seen.has(key):
			(entities[key] as Node3D).visible = false

func _helper_parts(node: MeshInstance3D, kind: String) -> void:
	var part: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.18, 0.9, 0.18) if kind == "army" else Vector3(0.7, 0.2, 0.2)
	part.mesh = mesh
	var material_: StandardMaterial3D = StandardMaterial3D.new()
	material_.albedo_color = Color("d5e6ad") if kind == "army" else color_for(kind).lightened(0.3)
	part.material_override = material_
	part.position = Vector3(0.45, 0.7, 0.0)
	node.add_child(part)

func _animal_parts(node: MeshInstance3D, kind: String) -> void:
	for side: int in [-1,1]:
		for row: int in (4 if "spider" in kind or "mother" in kind else 2):
			var leg: MeshInstance3D = MeshInstance3D.new()
			var mesh: BoxMesh = BoxMesh.new()
			mesh.size = Vector3(0.65, 0.1, 0.12)
			leg.mesh = mesh
			leg.material_override = node.material_override
			leg.position = Vector3(float(side) * 0.5, -0.2, float(row) * 0.24 - 0.3)
			node.add_child(leg)

func pick(pixel: Vector2) -> Vector2:
	var origin: Vector3 = camera.project_ray_origin(pixel)
	var direction: Vector3 = camera.project_ray_normal(pixel)
	if absf(direction.y) < 0.00001: return Vector2(-1000,-1000)
	var hit: Vector3 = origin + direction * (-origin.y / direction.y)
	return Coords.ground_to_logic(Vector2(hit.x, hit.z))

func set_preview(kind: String, cell: Vector2i, valid: bool, footprint: Vector2i) -> void:
	marker.visible = not kind.is_empty()
	if not marker.visible: return
	var at: Vector2 = Coords.logic_to_ground((Vector2(cell) + Vector2(footprint) * 0.5) * 4.0)
	marker.position = Vector3(at.x, 0.07, at.y)
	marker.scale = Vector3(footprint.x * 0.4, 0.06, footprint.y * 0.4)
	(marker.material_override as StandardMaterial3D).albedo_color = Color("bdeaa2") if valid else Color("e76e65")
func _wall_height(x: int, y: int) -> float:
	var state: WorldState = session.state
	if not state.in_bounds(x, y):
		return 0.0
	if state.terrain[state.index_of(x, y)] != 4:
		return 0.0
	var border: bool = x == 0 or y == 0 or x == state.width - 1 or y == state.height - 1
	if session.placement != null and not border:
		return 0.0
	return 1.0 if border else 1.6

func _build_terrain_meshes() -> void:
	var state: WorldState = session.state
	var ground: Dictionary = _new_arrays()
	var blocks: Dictionary = _new_arrays()
	var cell: float = Config.CELL_M
	for y: int in state.height:
		for x: int in state.width:
			var def: TerrainDef = state.terrain_def_at(state.index_of(x, y))
			if session.placement != null:
				def = state.terrain_defs[session.base_terrain[state.index_of(x, y)]]
			var color: Color = def.ground_color
			var x0: float = Coords.ORIGIN.x + float(x) * cell
			var z0: float = Coords.ORIGIN.y + float(y) * cell
			var x1: float = x0 + cell
			var z1: float = z0 + cell
			var h: float = _wall_height(x, y)
			if h <= 0.0:
				_quad(ground, Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1), Vector3.UP, color)
				continue
			_quad(blocks, Vector3(x0, h, z0), Vector3(x1, h, z0), Vector3(x1, h, z1), Vector3(x0, h, z1), Vector3.UP, color.lightened(0.12))
			var shade: Color = color.darkened(0.06)
			var low: float = _wall_height(x, y - 1)
			if low < h:
				_quad(blocks, Vector3(x0, h, z0), Vector3(x1, h, z0), Vector3(x1, low, z0), Vector3(x0, low, z0), Vector3(0, 0, -1), shade)
			low = _wall_height(x, y + 1)
			if low < h:
				_quad(blocks, Vector3(x1, h, z1), Vector3(x0, h, z1), Vector3(x0, low, z1), Vector3(x1, low, z1), Vector3(0, 0, 1), shade)
			low = _wall_height(x - 1, y)
			if low < h:
				_quad(blocks, Vector3(x0, h, z1), Vector3(x0, h, z0), Vector3(x0, low, z0), Vector3(x0, low, z1), Vector3(-1, 0, 0), shade)
			low = _wall_height(x + 1, y)
			if low < h:
				_quad(blocks, Vector3(x1, h, z0), Vector3(x1, h, z1), Vector3(x1, low, z1), Vector3(x1, low, z0), Vector3(1, 0, 0), shade)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	material.metallic_specular = 0.0
	for pair: Array in [[ground, "Ground", false], [blocks, "Blocks", true]]:
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.name = pair[1]
		instance.mesh = _mesh_from(pair[0], material)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if pair[2] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not pair[2]:
			instance.layers = 2 # the floor is not part of the water reflection (layer 1 only)
		add_child(instance)

func _new_arrays() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "i": PackedInt32Array()}

func _quad(arrays: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	var vertices: PackedVector3Array = arrays["v"]
	var normals: PackedVector3Array = arrays["n"]
	var colors: PackedColorArray = arrays["c"]
	var indices: PackedInt32Array = arrays["i"]
	var base: int = vertices.size()
	for point: Vector3 in [a, b, c, d]:
		vertices.append(point)
		normals.append(normal)
		colors.append(color)
	indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	arrays["v"] = vertices
	arrays["n"] = normals
	arrays["c"] = colors
	arrays["i"] = indices

func _mesh_from(arrays: Dictionary, material: Material) -> ArrayMesh:
	var data: Array = []
	data.resize(Mesh.ARRAY_MAX)
	data[Mesh.ARRAY_VERTEX] = arrays["v"]
	data[Mesh.ARRAY_NORMAL] = arrays["n"]
	data[Mesh.ARRAY_COLOR] = arrays["c"]
	data[Mesh.ARRAY_INDEX] = arrays["i"]
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data)
	mesh.surface_set_material(0, material)
	return mesh






