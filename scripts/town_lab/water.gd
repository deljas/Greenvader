extends Node
const Surface: Shader = preload("res://scripts/town_lab/water.gdshader")
const HEIGHT: float = 0.018
var reflection_view: SubViewport
var reflection_camera: Camera3D
var main_camera: Camera3D
var material_: ShaderMaterial
var surfaces: Array[MeshInstance3D] = []

func setup(parent_view: SubViewport, camera: Camera3D, world: Node3D) -> void:
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
	reflection_camera.cull_mask = 1|32 # Include lamp housings, exclude floor/water/caster cards.
	reflection_view.add_child(reflection_camera)
	reflection_camera.current = true
	material_ = ShaderMaterial.new()
	material_.shader = Surface
	material_.set_shader_parameter("reflection_texture",reflection_view.get_texture())
	var specs: Array[Dictionary] = [
		{"center":Vector2(-5.4,-11.8),"size":Vector2(1.8,4.5),"seed":11},
		{"center":Vector2(2,0.8),"size":Vector2(3.8,2.2),"seed":23},
		{"center":Vector2(14,5.7),"size":Vector2(3.4,1.7),"seed":38},
		{"center":Vector2(-4.2,15.8),"size":Vector2(2.2,1.25),"seed":57}]
	for spec: Dictionary in specs: _puddle(world,spec)
	sync_camera()

func _puddle(world: Node3D, spec: Dictionary) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = spec["seed"]
	var polygon: PackedVector2Array = PackedVector2Array()
	for i: int in range(13):
		var a: float = TAU*i/13
		polygon.append(Vector2(cos(a),sin(a))*spec["size"]*0.5*rng.randf_range(0.77,1.08))
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in indices:
		surface.set_normal(Vector3.UP)
		surface.add_vertex(Vector3(polygon[i].x,0,polygon[i].y))
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "IrregularPuddle"+str(surfaces.size()+1)
	mesh.mesh = surface.commit()
	mesh.material_override = material_
	mesh.layers = 4
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = Vector3(spec["center"].x,HEIGHT,spec["center"].y)
	world.add_child(mesh)
	surfaces.append(mesh)

func sync_camera() -> void:
	var eye: Vector3 = main_camera.global_position
	var target: Vector3 = eye-main_camera.global_basis.z*10
	eye.y = HEIGHT*2-eye.y
	target.y = HEIGHT*2-target.y
	reflection_camera.global_position = eye
	reflection_camera.look_at(target,Vector3.UP)
	reflection_camera.size = main_camera.size
	reflection_camera.near = main_camera.near
	reflection_camera.far = main_camera.far
	material_.set_shader_parameter("reflection_view_projection",reflection_camera.get_camera_projection()*Projection(reflection_camera.global_transform.affine_inverse()))

func set_reflection(enabled: bool) -> void:
	material_.set_shader_parameter("reflection_strength",0.78 if enabled else 0.0)

func _process(_delta: float) -> void:
	sync_camera()
