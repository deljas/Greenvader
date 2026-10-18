extends Node3D
## POC-05 water surface of the constant water (terrain "water"): planar reflection + receives the current sun's shadows.
## The reflection viewport shares the render world and is a fixed fraction of the render resolution (so it scales with
## 640x360 / 960x540). Decorative puddles may use the same material but are never a water source (logic lives in the session).
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const Surface: Shader = preload("res://scripts/poc/environment/water_surface.gdshader")

var reflection_view: SubViewport
var reflection_camera: Camera3D
var main_camera: Camera3D
var material_: ShaderMaterial
var surface_node: MeshInstance3D
var height_m: float = 0.006
var divisor: int = 2
var strength: float = 0.78
var reflection_enabled: bool = true
var water_cells: int = 0
var puddle_nodes: Array[MeshInstance3D] = []

func setup(parent_view: SubViewport, camera: Camera3D, session: RefCounted, tuning: Dictionary, placement_view: Node3D) -> void:
	main_camera = camera
	var water: Dictionary = tuning.get("water", {})
	height_m = float(water.get("height_m", 0.006))
	divisor = maxi(int(water.get("reflection_divisor", 2)), 1)
	strength = float(water.get("reflection_strength", 0.78))
	reflection_view = SubViewport.new()
	reflection_view.size = parent_view.size / divisor
	reflection_view.world_3d = parent_view.find_world_3d()
	reflection_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	reflection_view.msaa_3d = Viewport.MSAA_DISABLED
	reflection_view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	reflection_view.use_taa = false
	reflection_view.use_debanding = false
	add_child(reflection_view)
	reflection_camera = Camera3D.new()
	reflection_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	reflection_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	reflection_camera.cull_mask = 1 # scene objects only: the floor (2) and the water (4) are excluded
	reflection_view.add_child(reflection_camera)
	reflection_camera.current = true
	material_ = ShaderMaterial.new()
	material_.shader = Surface
	material_.set_shader_parameter("reflection_texture", reflection_view.get_texture())
	_build_surface(session.state)
	if placement_view != null:
		for id: Variant in placement_view.holders.keys():
			var node: Node3D = placement_view.holders[id]
			if node is MeshInstance3D and (node as MeshInstance3D).mesh is CylinderMesh:
				(node as MeshInstance3D).material_override = material_
				(node as MeshInstance3D).layers = 4
				puddle_nodes.append(node as MeshInstance3D)
	set_reflection(true)
	sync_camera()

func _build_surface(state: WorldState) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell: float = Config.CELL_M
	water_cells = 0
	for y: int in state.height:
		for x: int in state.width:
			if state.terrain[state.index_of(x, y)] != Session.T_WATER:
				continue
			water_cells += 1
			var x0: float = Coords.ORIGIN.x + float(x) * cell
			var z0: float = Coords.ORIGIN.y + float(y) * cell
			for corner: Vector2 in [Vector2(x0, z0), Vector2(x0 + cell, z0 + cell), Vector2(x0 + cell, z0), Vector2(x0, z0), Vector2(x0, z0 + cell), Vector2(x0 + cell, z0 + cell)]:
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(corner.x, 0.0, corner.y))
	surface_node = MeshInstance3D.new()
	surface_node.name = "WaterSurface"
	if water_cells > 0:
		surface_node.mesh = st.commit()
	surface_node.material_override = material_
	surface_node.layers = 4
	surface_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface_node.position = Vector3(0.0, height_m, 0.0)
	add_child(surface_node)

## Reflection viewport = render size / divisor (proportional to the resolution).
func set_render_size(size: Vector2i) -> void:
	reflection_view.size = size / divisor

func sync_camera() -> void:
	var eye: Vector3 = main_camera.global_position
	var target: Vector3 = eye - main_camera.global_basis.z * 10.0
	eye.y = height_m * 2.0 - eye.y
	target.y = height_m * 2.0 - target.y
	reflection_camera.global_position = eye
	reflection_camera.look_at(target, Vector3.UP)
	reflection_camera.size = main_camera.size
	reflection_camera.near = main_camera.near
	reflection_camera.far = main_camera.far
	material_.set_shader_parameter("reflection_view_projection", reflection_camera.get_camera_projection() * Projection(reflection_camera.global_transform.affine_inverse()))

func set_reflection(enabled: bool) -> void:
	reflection_enabled = enabled
	material_.set_shader_parameter("reflection_strength", strength if enabled else 0.0)

## Day brightness of the wet tint (from the day state).
func set_daylight(value: float) -> void:
	material_.set_shader_parameter("daylight", value)
