extends Node
## Camera-facing display + separate upright alpha-cut shadow caster.
const Study: PackedScene = preload("res://scenes/render_study_3d.tscn")
const Fixture: GDScript = preload("res://scripts/render_study_3d/sprite_shadow_fixture.gd")
const GROUND_Y: float = 0.016 # Existing paving top is y=0.015.
const HOME: Vector3 = Vector3(4.8, GROUND_Y, 3.2)
var study: Node
var display_sprite: Sprite3D
var shadow_board: Sprite3D
var textures: Array[ImageTexture] = []
var automatic: bool = true
var phase: float = 0.0
var frame_index: int = 0
var flipped: bool = false
var render_foot: Vector3
var pixel_world: float = 0.0

func _ready() -> void:
	study = Study.instantiate()
	add_child(study)
	study.render_view.size = Vector2i(640,360)
	get_window().content_scale_size = Vector2i(640,360)
	get_window().min_size = Vector2i(640,360)
	study.set_time(1)
	study.set_process_input(false)
	for child: Node in study.get_children():
		if child is TextureRect:
			(child as TextureRect).size = Vector2(640,360)
		elif child is Control:
			(child as Control).hide()
	get_window().title = "グリーンベーダー｜歩行スプライトと3D影"
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	study.sun.shadow_blur = 1.0
	study.sun.shadow_bias = 0.10
	study.sun.shadow_normal_bias = 1.0
	textures = Fixture.frames()
	pixel_world = study.camera.size / float(study.render_view.size.y)
	display_sprite = _sprite("VisibleCameraFacing", GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	shadow_board = _sprite("UprightShadowOnly", GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	pose_at_time(0.0)

func _sprite(label_: String, shadow_mode: int) -> Sprite3D:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.name = label_
	sprite.pixel_size = pixel_world
	sprite.centered = true
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.5
	sprite.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF
	sprite.shaded = false
	sprite.double_sided = true
	sprite.cast_shadow = shadow_mode
	study.world.add_child(sprite)
	return sprite

func _process(delta: float) -> void:
	if automatic:
		phase = fmod(phase + delta, 4.0)
		pose_at_time(phase)

func pose_at_time(seconds: float) -> void:
	var time_: float = fposmod(seconds,4.0)
	var distance_: float = -1.35 + 1.35 * time_ if time_ < 2.0 else 1.35 - 1.35 * (time_-2.0)
	apply_pose(int(floor(time_ * 6.0)) % 4, time_ >= 2.0, HOME + study.camera.global_basis.x * distance_)

func apply_pose(index: int, flip: bool, logical_foot: Vector3) -> void:
	# One animation state drives both geometry instances. Only presentation is
	# snapped. Keep the shared foot on the physical ground plane.
	frame_index = posmod(index, textures.size())
	flipped = flip
	var camera: Camera3D = study.camera
	var point: Vector2 = camera.unproject_position(logical_foot)
	var correction: Vector2 = point.round() - point
	var forward_ground: Vector3 = Vector3(camera.global_basis.z.x,0,camera.global_basis.z.z).normalized()
	var vertical_projection: float = -camera.global_basis.y.dot(forward_ground)
	render_foot = logical_foot + camera.global_basis.x * correction.x * pixel_world + forward_ground * correction.y * pixel_world / vertical_projection
	var half_height: float = float(Fixture.SIZE.y) * pixel_world * 0.5
	display_sprite.global_basis = camera.global_basis
	display_sprite.global_position = render_foot + camera.global_basis.y * half_height
	# Deliberately upright, without camera pitch. Both lower edges meet the same
	# ground foot; the visible card and the physical shadow card are separate.
	# Artistic approximation: face the light horizontally so the alpha silhouette
	# remains readable. It is still an upright card with real 3D light projection,
	# not a volumetric character and not a shadow painted onto the ground.
	var light_normal: Vector3 = Vector3(study.sun.global_basis.z.x,0,study.sun.global_basis.z.z)
	if light_normal.length_squared() < 0.000001:
		light_normal = forward_ground # Stable upright card at a vertical light.
	light_normal = light_normal.normalized()
	shadow_board.global_basis = Basis(Vector3.UP.cross(light_normal),Vector3.UP,light_normal)
	shadow_board.global_position = render_foot + Vector3.UP * half_height
	for sprite: Sprite3D in [display_sprite,shadow_board]:
		sprite.texture = textures[frame_index]
		sprite.flip_h = flipped

func sync_snapshot() -> Dictionary:
	var half_height: float = 48.0 * pixel_world * 0.5
	var display_foot: Vector3 = display_sprite.global_position - study.camera.global_basis.y * half_height
	var caster_foot: Vector3 = shadow_board.global_position - Vector3.UP * half_height
	return {"frame":frame_index,"flip":flipped,"visible_texture":display_sprite.texture.get_instance_id(),"caster_texture":shadow_board.texture.get_instance_id(),"texture_match":display_sprite.texture == shadow_board.texture,"flip_match":display_sprite.flip_h == shadow_board.flip_h,"foot_match":display_foot.distance_to(caster_foot) < 0.00001,"foot":render_foot,"screen_foot":study.camera.unproject_position(render_foot),"pixel_world":pixel_world,"caster_enabled":shadow_board.visible}
