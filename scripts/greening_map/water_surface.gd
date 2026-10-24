extends Node
## A single reflection pass shared by the existing pond and optional cosmetic puddle.
const Session: GDScript = preload("res://scripts/greening_map/session.gd")
const Surface: Shader = preload("res://scripts/greening_map/water_surface.gdshader")
const HEIGHT: float = 0.006
var reflection_view: SubViewport
var reflection_camera: Camera3D
var main_camera: Camera3D
var material_: ShaderMaterial
var surfaces: Array[MeshInstance3D] = []
var pond_bounds: Rect2
var puddle: MeshInstance3D

func setup(parent_view: SubViewport, camera: Camera3D, world: Node3D, state: WorldState) -> void:
	main_camera = camera
	reflection_view = SubViewport.new()
	reflection_view.size = Vector2i(320,180)
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
	reflection_camera.cull_mask = 1 # Scene objects only: excludes floors/foundations(2), water(4).
	reflection_view.add_child(reflection_camera)
	reflection_camera.current = true
	material_ = ShaderMaterial.new()
	material_.shader = Surface
	material_.set_shader_parameter("reflection_texture",reflection_view.get_texture())
	var lo: Vector2 = Vector2(INF,INF)
	var hi: Vector2 = Vector2(-INF,-INF)
	for index: int in state.tile_count():
		if state.terrain[index]==3:
			var p: Vector2 = Session.cell_center(index)
			lo = lo.min(p-Vector2.ONE*Session.CELL*0.5)
			hi = hi.max(p+Vector2.ONE*Session.CELL*0.5)
	pond_bounds = Rect2(lo,hi-lo)
	_plane(world,pond_bounds,"ExistingLogicalPond")
	sync_camera()

func _plane(world: Node3D, rect: Rect2, label_: String) -> MeshInstance3D:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = label_
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = rect.size
	mesh.mesh = plane
	var p: Vector2 = rect.get_center()
	mesh.position = Vector3(p.x,HEIGHT,p.y)
	mesh.material_override = material_
	mesh.layers = 4
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mesh)
	surfaces.append(mesh)
	return mesh

func add_cosmetic_puddle(world: Node3D) -> void:
	# Approved visual-only sample on existing pavement; no collision/state changes.
	puddle = _plane(world,Rect2(Vector2(-0.5,1.8),Vector2(1.4,0.8)),"WalkableVisualOnlyPuddle")

func sync_camera() -> void:
	var eye: Vector3 = main_camera.global_position
	var target: Vector3 = eye-main_camera.global_basis.z*10.0
	eye.y = HEIGHT*2.0-eye.y
	target.y = HEIGHT*2.0-target.y
	reflection_camera.global_position = eye
	reflection_camera.look_at(target,Vector3.UP)
	reflection_camera.size = main_camera.size
	reflection_camera.near = main_camera.near
	reflection_camera.far = main_camera.far
	var matrix: Projection = reflection_camera.get_camera_projection()*Projection(reflection_camera.global_transform.affine_inverse())
	material_.set_shader_parameter("reflection_view_projection",matrix)

func set_reflection(enabled: bool) -> void:
	material_.set_shader_parameter("reflection_strength",0.76 if enabled else 0.0)

func _process(_delta: float) -> void:
	sync_camera()
