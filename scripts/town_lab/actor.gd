extends Node3D
## Same human fixture, fixed 1.65m physical height across zoom, shaded display.
const Fixture: GDScript = preload("res://scripts/render_study_3d/sprite_shadow_fixture.gd")
const SUN_CARD: int = 8
const LAMP_CARD: int = 16
const PIXEL_WORLD: float = 1.65*0.8660254/24
var textures: Array[ImageTexture] = []
var display_sprite: Sprite3D
var shadow_board: Sprite3D
var point_board: Sprite3D
var camera: Camera3D
var frame: int = 1
var selected_lamp: int = -1
var render_foot: Vector3
var lamp_normal: Vector3 = Vector3.BACK

func setup(camera_: Camera3D) -> void:
	camera = camera_
	for texture: ImageTexture in Fixture.frames():
		var image_: Image = texture.get_image()
		image_.resize(16,24,Image.INTERPOLATE_NEAREST)
		textures.append(ImageTexture.create_from_image(image_))
	display_sprite = _sprite(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,1)
	shadow_board = _sprite(GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,SUN_CARD)
	point_board = _sprite(GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,LAMP_CARD)

func _sprite(mode: int, layer: int) -> Sprite3D:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.pixel_size = PIXEL_WORLD
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

func pose(foot: Vector3, frame_: int, flip: bool, directional: DirectionalLight3D, lamps: Array[OmniLight3D], delta: float) -> void:
	frame = posmod(frame_,4)
	var pixel: float = camera.size/360
	var screen: Vector2 = camera.unproject_position(foot)
	var correction: Vector2 = screen.round()-screen
	var ground_forward: Vector3 = Vector3(camera.global_basis.z.x,0,camera.global_basis.z.z).normalized()
	render_foot = foot+camera.global_basis.x*correction.x*pixel+ground_forward*correction.y*pixel/(-camera.global_basis.y.dot(ground_forward))
	var upright: float = 1/maxf(camera.global_basis.y.dot(Vector3.UP),0.1)
	var center: Vector3 = render_foot+Vector3.UP*12*PIXEL_WORLD*upright
	display_sprite.global_basis = Basis(camera.global_basis.x,Vector3.UP*upright,ground_forward)
	var normal: Vector3 = Vector3(directional.global_basis.z.x,0,directional.global_basis.z.z).normalized()
	shadow_board.global_basis = Basis(Vector3.UP.cross(normal),Vector3.UP*upright,normal)
	var candidate: int = -1
	var distance: float = INF
	for i: int in range(lamps.size()):
		var d: float = foot.distance_to(lamps[i].global_position)
		if d<distance: distance=d; candidate=i
	if selected_lamp<0 or distance+1.3<foot.distance_to(lamps[selected_lamp].global_position): selected_lamp=candidate
	for i: int in range(lamps.size()): lamps[i].shadow_caster_mask = 1|(LAMP_CARD if i==selected_lamp else 0)
	if selected_lamp>=0:
		var point_normal: Vector3 = lamps[selected_lamp].global_position-foot
		point_normal.y = 0
		if point_normal.length_squared()>0.001:
			point_normal = point_normal.normalized()
			# Short interpolation and distance hysteresis avoid abrupt card flips.
			lamp_normal = lamp_normal.slerp(point_normal,1-exp(-maxf(delta,0.016)*8)).normalized()
		point_board.global_basis = Basis(Vector3.UP.cross(lamp_normal),Vector3.UP*upright,lamp_normal)
	for sprite: Sprite3D in [display_sprite,shadow_board,point_board]:
		sprite.global_position = center
		sprite.texture = textures[frame]
		sprite.flip_h = flip

func snapshot() -> Dictionary:
	return {"frame":frame,"matching_texture":display_sprite.texture==shadow_board.texture and display_sprite.texture==point_board.texture,
		"matching_feet":display_sprite.global_position.is_equal_approx(shadow_board.global_position) and display_sprite.global_position.is_equal_approx(point_board.global_position),
		"shaded":display_sprite.shaded,"height":24*PIXEL_WORLD*display_sprite.global_basis.y.length(),"lamp":selected_lamp}
