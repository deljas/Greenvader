extends Node3D
## POC-05 terrain-specific greening display (replaces the POC-03 provisional cell boxes). Reads the WorldState only:
##   soil (wasteland / safe / shore): a tuft cluster per cell that grows with the stage and, mature, closes into a carpet;
##   pavement (terrain "paved"): grass tufts along a crack line + a dark crack ribbon (greening_map ground_view method).
## Every terrain has one MultiMesh instance per cell; only the cells the WorldState marked dirty are rewritten
## (apply(take_dirty())). The display density is a view setting: it hides some cells but never touches the greening counts.
## No outline, no baked brightness / shadow: the ground colour is flat and lit by the sun like everything else.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Parts: GDScript = preload("res://scripts/poc/environment/wall_parts.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")

const HIDDEN_Y: float = -20.0
## Display scale per stage (index = WorldState.STAGE_*).
const STAGE_SCALE: Array[float] = [0.0, 0.0, 0.45, 0.72, 1.0]
const STAGE_TINT: Array[Color] = [Color.WHITE, Color.WHITE, Color(1.0, 1.0, 0.82), Color(0.95, 1.0, 0.88), Color.WHITE]
## Watered ground (POC3-PLAYTEST-01 item 4): a damp patch under the grass plus a cool tint on the blades.
const WET_TINT: Color = Color(0.74, 0.90, 1.0)
const WET_BASE: Color = Color(0.10, 0.24, 0.36, 0.62)
const WET_SPECK: Color = Color(0.58, 0.86, 1.0, 0.95)
## Crack line (cell-local metres) shared by the ribbon and the tufts along it.
const CRACK_PATH: Array[Vector2] = [Vector2(-0.18, -0.12), Vector2(-0.08, -0.04), Vector2(0.025, -0.07), Vector2(0.09, 0.02), Vector2(0.17, 0.12)]

var session: RefCounted
var state: WorldState
var soil_multimesh: MultiMesh
var pave_multimesh: MultiMesh
var seed_multimesh: MultiMesh
var crack_multimesh: MultiMesh
var wet_multimesh: MultiMesh
## Cell indices under watered cultivated plants (set by the view); grass wetness comes from the WorldState.
var crop_wet: Dictionary = {}
var soil_density: float = 1.0
var pave_density: float = 1.0
## Instances rewritten since build (observability for the "no whole-map rebuild" check).
var cell_updates: int = 0
## CPU mirror of what each layer shows per cell (0 = hidden, otherwise the display scale in 1/100): the renderer cannot be read
## back headless, and tests / tools read this instead.
var shown_soil: PackedByteArray = PackedByteArray()
var shown_pave: PackedByteArray = PackedByteArray()
var shown_seed: PackedByteArray = PackedByteArray()
var shown_crack: PackedByteArray = PackedByteArray()
var shown_wet: PackedByteArray = PackedByteArray()
var _paved_id: int = Session.T_PAVED
var _parts: RefCounted = Parts.new()

func build(source: RefCounted, tuning: Dictionary = {}) -> void:
	session = source
	state = session.state
	var ground: Dictionary = tuning.get("ground", {})
	soil_density = clampf(float(ground.get("soil_density", 1.0)), 0.0, 1.0)
	pave_density = clampf(float(ground.get("pave_density", 1.0)), 0.0, 1.0)
	var count: int = state.tile_count()
	shown_soil.resize(count)
	shown_pave.resize(count)
	shown_seed.resize(count)
	shown_crack.resize(count)
	shown_wet.resize(count)
	soil_multimesh = _layer("SoilCover", _soil_mesh(), count, true, true)
	pave_multimesh = _layer("PaveCover", _pave_mesh(), count, true, true)
	var dot: BoxMesh = BoxMesh.new()
	dot.size = Vector3(0.10, 0.045, 0.075)
	seed_multimesh = _layer("Seeds", dot, count, false, false)
	crack_multimesh = _layer("Cracks", _crack_mesh(), count, false, false)
	wet_multimesh = _wet_layer(count)
	refresh_all()

func _layer(label: String, mesh: Mesh, count: int, vertex_colors: bool, instance_colors: bool) -> MultiMesh:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = instance_colors
	mm.mesh = mesh
	mm.instance_count = count
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 200.0
	var material_: StandardMaterial3D = StandardMaterial3D.new()
	material_.vertex_color_use_as_albedo = vertex_colors or instance_colors
	material_.roughness = 1.0
	material_.metallic_specular = 0.0
	material_.cull_mode = BaseMaterial3D.CULL_DISABLED
	if not vertex_colors:
		material_.albedo_color = Color("f0d98b") if label == "Seeds" else Color(0.13, 0.16, 0.12)
	node.material_override = material_
	add_child(node)
	return mm

## Flat damp patch: no outline, alpha only from vertex colours, drawn on layer 2 like the floor (not mirrored by the water).
func _wet_layer(count: int) -> MultiMesh:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.mesh = _wet_mesh()
	mm.instance_count = count
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = "WetPatch"
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 200.0
	node.layers = 2
	var material_: StandardMaterial3D = StandardMaterial3D.new()
	material_.vertex_color_use_as_albedo = true
	material_.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_.roughness = 1.0
	material_.metallic_specular = 0.0
	material_.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = material_
	add_child(node)
	return mm

static func _wet_quad(st: SurfaceTool, cx: float, cz: float, half: float, y: float, color: Color) -> void:
	var corners: Array[Vector3] = [Vector3(cx - half, y, cz - half), Vector3(cx + half, y, cz - half), Vector3(cx + half, y, cz + half), Vector3(cx - half, y, cz + half)]
	for index: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_color(color)
		st.add_vertex(corners[index])

func _wet_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_wet_quad(st, 0.0, 0.0, 0.2, 0.0, WET_BASE)
	# Small bright droplets, lifted a hair so they win the depth test against the base.
	for speck: Vector2 in [Vector2(-0.10, -0.07), Vector2(0.08, 0.02), Vector2(-0.03, 0.11)]:
		_wet_quad(st, speck.x, speck.y, 0.026, 0.004, WET_SPECK)
	return st.commit()

# ---------------------------------------------------------------- meshes

static func _blade(st: SurfaceTool, root: Vector3, angle: float, height: float, lean: float, half_width: float) -> void:
	var tip: Vector3 = root + Vector3(cos(angle) * lean, height, sin(angle) * lean)
	var side: Vector3 = Vector3(cos(angle + 1.57), 0.0, sin(angle + 1.57)) * half_width
	Parts.triangle(st, root - side, tip, root + side, Color("487343"), Color("9aaa57"))

## Fourteen blades spread over one 0.4 m cell: neighbouring mature cells overlap into a carpet.
func _soil_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in 14:
		var angle: float = float(i) * 2.39996
		var radius: float = 0.03 + 0.15 * sqrt(float(i) / 14.0)
		var root: Vector3 = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		_blade(st, root, angle, 0.18 + float(i % 4) * 0.06, 0.07, 0.055)
	return st.commit()

## Small tufts along the crack line (the blades grow out of the crack, not over the whole cell).
func _pave_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: int in CRACK_PATH.size():
		var base: Vector2 = CRACK_PATH[p]
		for k: int in 3:
			var angle: float = float(p * 3 + k) * 2.39996
			var root: Vector3 = Vector3(base.x + cos(angle) * 0.025, 0.0, base.y + sin(angle) * 0.025)
			_blade(st, root, angle, 0.14 + float((p + k) % 3) * 0.05, 0.05, 0.04)
	return st.commit()

func _crack_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment: int in CRACK_PATH.size() - 1:
		var a: Vector2 = CRACK_PATH[segment]
		var b: Vector2 = CRACK_PATH[segment + 1]
		var side: Vector2 = Vector2(-(b - a).y, (b - a).x).normalized() * 0.0275
		var corners: Array[Vector2] = [a - side, a + side, b + side, b - side]
		for index: int in [0, 2, 1, 0, 3, 2]:
			var v: Vector2 = corners[index]
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(v.x, 0.0, v.y))
	return st.commit()

# ---------------------------------------------------------------- state -> instances

func _hash01(index: int) -> float:
	return float((index * 2654435761) % 1000) / 1000.0

func _hide(mm: MultiMesh, index: int) -> void:
	mm.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.00001), Vector3(0.0, HIDDEN_Y, 0.0)))

func _set_cell(index: int) -> void:
	cell_updates += 1
	var stage: int = state.stage[index] if state.target[index] == 1 else 0
	var paved: bool = state.terrain[index] == _paved_id
	var cell: Vector2i = Vector2i(index % state.width, index / state.width)
	var centre: Vector2 = Coords.cell_center_ground(cell)
	var origin: Vector3 = Vector3(centre.x, 0.0, centre.y)
	var angle: float = float(state.sprout_slot[index]) * PI * 0.5
	var visible_cell: bool = _hash01(index) < (pave_density if paved else soil_density)
	var scale_: float = STAGE_SCALE[stage] if visible_cell else 0.0
	var soil_on: bool = scale_ > 0.0 and not paved
	var pave_on: bool = scale_ > 0.0 and paved
	if soil_on:
		soil_multimesh.set_instance_transform(index, Transform3D(Basis(Vector3.UP, angle + float(index % 7)).scaled(Vector3.ONE * scale_), origin))
		soil_multimesh.set_instance_color(index, STAGE_TINT[stage] * (WET_TINT if _is_wet(index) else Color.WHITE))
	else:
		_hide(soil_multimesh, index)
	if pave_on:
		pave_multimesh.set_instance_transform(index, Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * scale_), origin))
		pave_multimesh.set_instance_color(index, STAGE_TINT[stage] * (WET_TINT if _is_wet(index) else Color.WHITE))
	else:
		_hide(pave_multimesh, index)
	var seed_on: bool = stage == WorldState.STAGE_SEED and visible_cell
	if seed_on:
		var seed_at: Vector3 = origin + (Basis(Vector3.UP, angle) * Vector3(CRACK_PATH[1].x, 0.0, CRACK_PATH[1].y) if paved else Vector3.ZERO)
		seed_multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, seed_at + Vector3.UP * 0.03))
	else:
		_hide(seed_multimesh, index)
	var crack_on: bool = paved and stage >= WorldState.STAGE_SEED
	if crack_on:
		crack_multimesh.set_instance_transform(index, Transform3D(Basis(Vector3.UP, angle), origin + Vector3.UP * 0.004))
	else:
		_hide(crack_multimesh, index)
	shown_soil[index] = roundi(scale_ * 100.0) if soil_on else 0
	shown_pave[index] = roundi(scale_ * 100.0) if pave_on else 0
	shown_seed[index] = 1 if seed_on else 0
	shown_crack[index] = 1 if crack_on else 0
	set_wet_cell(index)

## True for a growing grass cell with moisture, or a cell under a watered cultivated plant.
func _is_wet(index: int) -> bool:
	if crop_wet.has(index):
		return true
	return state.target[index] == 1 and state.moisture[index] > 0 and state.stage[index] >= WorldState.STAGE_SEED and state.stage[index] < WorldState.STAGE_MATURE

## Updates only the damp-patch layer of one cell (the crop-cover pass must not redraw the grass).
func set_wet_cell(index: int) -> void:
	var wet: bool = _is_wet(index)
	if wet:
		var cell: Vector2i = Vector2i(index % state.width, index / state.width)
		var centre: Vector2 = Coords.cell_center_ground(cell)
		var angle: float = float(state.sprout_slot[index]) * PI * 0.5
		wet_multimesh.set_instance_transform(index, Transform3D(Basis(Vector3.UP, angle), Vector3(centre.x, 0.008, centre.y)))
	else:
		_hide(wet_multimesh, index)
	shown_wet[index] = 1 if wet else 0

func refresh_all() -> void:
	for index: int in state.tile_count():
		_set_cell(index)

## Rewrites only the given cells (the WorldState dirty list).
func apply(dirty: PackedInt32Array) -> void:
	for index: int in dirty:
		_set_cell(index)

## View-only setting: fraction of cells that show their cover (1.0 = all). Never changes the greening counts.
func set_density(soil: float, pave: float) -> void:
	soil_density = clampf(soil, 0.0, 1.0)
	pave_density = clampf(pave, 0.0, 1.0)
	refresh_all()

## Observability: number of cells a layer ("soil", "pave", "seed", "crack") currently shows.
func visible_count(layer: String) -> int:
	var count: int = 0
	var mirror: PackedByteArray = shown_soil
	match layer:
		"pave":
			mirror = shown_pave
		"seed":
			mirror = shown_seed
		"crack":
			mirror = shown_crack
		"wet":
			mirror = shown_wet
	for value: int in mirror:
		if value > 0:
			count += 1
	return count
