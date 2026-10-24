extends Node3D
## Upright yaw-facing display + upright light-facing caster. Both share physical height.
const Fixture: GDScript = preload("res://scripts/render_study_3d/sprite_shadow_fixture.gd")
var textures: Array[ImageTexture] = []
var display_sprite: Sprite3D
var shadow_board: Sprite3D
var camera: Camera3D
var sun: DirectionalLight3D
var pixel_world: float
var render_foot: Vector3
var frame: int = 0
var flip: bool = false
var vertical_scale: float = 1.0

func setup(camera_: Camera3D, sun_: DirectionalLight3D) -> void:
	camera = camera_
	sun = sun_
	pixel_world = camera.size/360.0
	for texture: ImageTexture in Fixture.frames():
		var image_: Image = texture.get_image()
		image_.resize(16,24,Image.INTERPOLATE_NEAREST)
		textures.append(ImageTexture.create_from_image(image_))
	display_sprite = _sprite(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	shadow_board = _sprite(GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)

func _sprite(mode: int) -> Sprite3D:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.pixel_size = pixel_world
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.5
	sprite.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF
	sprite.shaded = false
	sprite.double_sided = true
	sprite.cast_shadow = mode
	add_child(sprite)
	return sprite

func pose(logical_foot: Vector3, frame_: int, flip_: bool) -> void:
	frame = posmod(frame_,4)
	flip = flip_
	var point: Vector2 = camera.unproject_position(logical_foot)
	var correction: Vector2 = point.round()-point
	var ground_forward: Vector3 = Vector3(camera.global_basis.z.x,0,camera.global_basis.z.z).normalized()
	render_foot = logical_foot+camera.global_basis.x*correction.x*pixel_world+ground_forward*correction.y*pixel_world/(-camera.global_basis.y.dot(ground_forward))
	# Correct upright projection foreshortening without tilting the head into walls.
	vertical_scale = 1.0/maxf(camera.global_basis.y.dot(Vector3.UP),0.1)
	var half_height: float = 12.0*pixel_world*vertical_scale
	display_sprite.global_basis = Basis(camera.global_basis.x,Vector3.UP*vertical_scale,ground_forward)
	display_sprite.global_position = render_foot+Vector3.UP*half_height
	var normal: Vector3 = Vector3(sun.global_basis.z.x,0,sun.global_basis.z.z).normalized()
	shadow_board.global_basis = Basis(Vector3.UP.cross(normal),Vector3.UP*vertical_scale,normal)
	shadow_board.global_position = render_foot+Vector3.UP*half_height
	for sprite: Sprite3D in [display_sprite,shadow_board]:
		sprite.texture = textures[frame]
		sprite.flip_h = flip

func sync_snapshot() -> Dictionary:
	var half_height: float = 12.0*pixel_world*vertical_scale
	return {"frame":frame,"flip":flip,"texture_match":display_sprite.texture==shadow_board.texture,"flip_match":display_sprite.flip_h==shadow_board.flip_h,"foot_match":(display_sprite.global_position-Vector3.UP*half_height).distance_to(shadow_board.global_position-Vector3.UP*half_height)<0.00001,"screen_foot":camera.unproject_position(render_foot),"physical_height":half_height*2.0,"vertical_scale":vertical_scale}
