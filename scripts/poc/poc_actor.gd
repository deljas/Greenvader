extends Node3D
## Provisional human sprite: a lit display card (no shadow) plus a SHADOWS_ONLY card with the same frame and
## the same feet. 1 texel = 1 screen px: resolution-specific frames (nearest) and a pixel_size derived from the
## camera. No outline is added.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Fixture: GDScript = preload("res://scripts/render_study_3d/sprite_shadow_fixture.gd")
const SUN_CARD: int = 8

var camera: Camera3D
var display_sprite: Sprite3D
var shadow_board: Sprite3D
var resolution_index: int = 0
var render_height: int = 360
var frame: int = 1
var render_foot: Vector3 = Vector3.ZERO
var pixel_size: float = 0.0
var _sources: Array[Image] = []
var _cache: Dictionary = {}

func setup(camera_: Camera3D) -> void:
	camera = camera_
	for texture: ImageTexture in Fixture.frames():
		_sources.append(texture.get_image())
	display_sprite = _sprite(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, 1)
	shadow_board = _sprite(GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, SUN_CARD)
	set_resolution(Config.DEFAULT_RESOLUTION)

func _sprite(mode: int, layer: int) -> Sprite3D:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.5
	sprite.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF
	sprite.shaded = true
	sprite.double_sided = true
	sprite.cast_shadow = mode
	sprite.layers = layer
	add_child(sprite)
	return sprite

func set_resolution(index: int) -> void:
	resolution_index = index
	render_height = Config.RESOLUTIONS[index].y

func frame_texture(index: int, frame_: int) -> ImageTexture:
	var key: int = index * 16 + frame_
	if not _cache.has(key):
		var size: Vector2i = Config.SPRITE_FRAME_PX[index]
		var image: Image = _sources[frame_].duplicate()
		image.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
		_cache[key] = ImageTexture.create_from_image(image)
	return _cache[key]

## Places the sprite with its feet at `foot` (world), snapped so the feet land on a whole screen pixel.
func pose(foot: Vector3, frame_: int, flip: bool, directional: DirectionalLight3D) -> void:
	frame = posmod(frame_, 4)
	var texture: ImageTexture = frame_texture(resolution_index, frame)
	var texels: Vector2i = Config.SPRITE_FRAME_PX[resolution_index]
	pixel_size = camera.size / float(render_height)
	var screen: Vector2 = camera.unproject_position(foot)
	var correction: Vector2 = screen.round() - screen
	var ground_forward: Vector3 = Vector3(camera.global_basis.z.x, 0.0, camera.global_basis.z.z).normalized()
	var tilt: float = -camera.global_basis.y.dot(ground_forward)
	render_foot = foot + camera.global_basis.x * correction.x * pixel_size + ground_forward * correction.y * pixel_size / tilt
	var upright: float = 1.0 / maxf(camera.global_basis.y.dot(Vector3.UP), 0.1)
	var center: Vector3 = render_foot + Vector3.UP * (float(texels.y) * 0.5) * pixel_size * upright
	display_sprite.global_basis = Basis(camera.global_basis.x, Vector3.UP * upright, ground_forward)
	var normal: Vector3 = Vector3(directional.global_basis.z.x, 0.0, directional.global_basis.z.z).normalized()
	shadow_board.global_basis = Basis(Vector3.UP.cross(normal), Vector3.UP * upright, normal)
	for sprite: Sprite3D in [display_sprite, shadow_board]:
		sprite.pixel_size = pixel_size
		sprite.global_position = center
		sprite.texture = texture
		sprite.flip_h = flip

func snapshot() -> Dictionary:
	var texels: Vector2i = Config.SPRITE_FRAME_PX[resolution_index]
	return {
		"frame": frame,
		"texels": [texels.x, texels.y],
		"pixel_size": pixel_size,
		"matching_texture": display_sprite.texture == shadow_board.texture,
		"matching_feet": display_sprite.global_position.is_equal_approx(shadow_board.global_position),
		"matching_flip": display_sprite.flip_h == shadow_board.flip_h,
		"shaded": display_sprite.shaded,
		"foot_screen": camera.unproject_position(render_foot),
		"height_m": float(texels.y) * pixel_size,
	}
