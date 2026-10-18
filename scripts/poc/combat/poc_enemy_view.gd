extends Node3D
## POC-04 provisional display of the enemy layer (replaced by final art later). No game logic: it only reads the session.
## Boars, nests, carcasses/bones and nest ruins are 2D pixel sprites (existing PixelArt.boar / EnemyArt images) shown as
## camera-facing Sprite3D cards, the same way as the player actor: 1 texel = 1 screen px (resolution-specific frames, nearest),
## feet snapped to the screen pixel grid, no outline. Boars and nests also get a SHADOWS_ONLY card with the same frame so the
## shadow follows the sprite. Flat ground items (carcass, bone, ruin) have no shadow card.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const SUN_CARD: int = 8

## Target frame (texels) per art and resolution index (640, 960). Sources are cropped to their used rect and resized nearest.
const FRAMES: Dictionary = {
	"boar": [Vector2i(16, 8), Vector2i(24, 12)],
	"nest": [Vector2i(32, 32), Vector2i(48, 48)],
	"ruin": [Vector2i(32, 32), Vector2i(48, 48)],
	"corpse": [Vector2i(14, 8), Vector2i(21, 12)],
	"bone": [Vector2i(10, 6), Vector2i(15, 9)],
}
const FLASH: Color = Color(2.0, 2.0, 2.0, 1.0)

var session: RefCounted
var camera: Camera3D
var sun: DirectionalLight3D
var resolution_index: int = 0
var render_height: int = 360
var _items: Dictionary = {}
var _sources: Dictionary = {}
var _cache: Dictionary = {}
var _seen: Dictionary = {}

func setup(source: RefCounted, camera_: Camera3D, sun_: DirectionalLight3D) -> void:
	session = source
	camera = camera_
	sun = sun_
	_sources["boar"] = _crop(PixelArt.boar().get_image())
	_sources["nest"] = EnemyArt.nest().get_image()
	_sources["ruin"] = EnemyArt.nest_ruin().get_image()
	_sources["corpse"] = EnemyArt.corpse().get_image()
	_sources["bone"] = EnemyArt.bone().get_image()
	set_resolution(Config.DEFAULT_RESOLUTION)

func _crop(image: Image) -> Image:
	var used: Rect2i = image.get_used_rect()
	return image.get_region(used) if used.size.x > 0 else image

func set_resolution(index: int) -> void:
	resolution_index = index
	render_height = Config.RESOLUTIONS[index].y

func texture_for(art: String) -> ImageTexture:
	var key: String = "%s:%d" % [art, resolution_index]
	if not _cache.has(key):
		var size: Vector2i = FRAMES[art][resolution_index]
		var image: Image = (_sources[art] as Image).duplicate()
		image.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
		_cache[key] = ImageTexture.create_from_image(image)
	return _cache[key]

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

func _entry(key: String, with_shadow: bool) -> Dictionary:
	if not _items.has(key):
		var entry: Dictionary = {"display": _sprite(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, 1), "shadow": null}
		if with_shadow:
			entry["shadow"] = _sprite(GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, SUN_CARD)
		_items[key] = entry
	_seen[key] = true
	return _items[key]

## Places a card with its feet at logical px `foot_logic`, snapped so the feet land on a whole screen pixel.
func _pose(entry: Dictionary, art: String, foot_logic: Vector2, flip: bool, tint: Color) -> void:
	var texture: ImageTexture = texture_for(art)
	var foot: Vector3 = Coords.ground3(Coords.logic_to_ground(foot_logic), 0.04)
	var pixel_size: float = camera.size / float(render_height)
	var screen: Vector2 = camera.unproject_position(foot)
	var correction: Vector2 = screen.round() - screen
	var ground_forward: Vector3 = Vector3(camera.global_basis.z.x, 0.0, camera.global_basis.z.z).normalized()
	var tilt: float = -camera.global_basis.y.dot(ground_forward)
	var render_foot: Vector3 = foot + camera.global_basis.x * correction.x * pixel_size + ground_forward * correction.y * pixel_size / tilt
	var upright: float = 1.0 / maxf(camera.global_basis.y.dot(Vector3.UP), 0.1)
	var center: Vector3 = render_foot + Vector3.UP * (float(texture.get_height()) * 0.5) * pixel_size * upright
	var display: Sprite3D = entry["display"]
	display.global_basis = Basis(camera.global_basis.x, Vector3.UP * upright, ground_forward)
	display.pixel_size = pixel_size
	display.global_position = center
	display.texture = texture
	display.flip_h = flip
	display.modulate = tint
	display.visible = true
	var shadow: Sprite3D = entry["shadow"]
	if shadow != null:
		var normal: Vector3 = Vector3(sun.global_basis.z.x, 0.0, sun.global_basis.z.z).normalized()
		shadow.global_basis = Basis(Vector3.UP.cross(normal), Vector3.UP * upright, normal)
		shadow.pixel_size = pixel_size
		shadow.global_position = center
		shadow.texture = texture
		shadow.flip_h = flip
		shadow.visible = true

## Per frame: rebuilds the card list from the EnemyField (created/removed as it changes; at most boar_cap + nests + carcass_cap).
func sync() -> void:
	var field: EnemyField = session.enemies
	if field == null:
		return
	_seen.clear()
	for nest: Nest in field.nests:
		var centre: Vector2 = nest.center_px(Config.TILE_PX)
		# The card stands on the middle of the nest block (feet at its centre).
		if nest.alive:
			var tint: Color = FLASH if field.flash_bright(nest.flash_steps) else Color.WHITE
			_pose(_entry("nest%d" % nest.id, true), "nest", centre, false, tint)
		else:
			_pose(_entry("ruin%d" % nest.id, false), "ruin", centre, false, Color.WHITE)
	for boar: Boar in field.boars:
		var tint_b: Color = FLASH if field.flash_bright(boar.flash_steps) else Color.WHITE
		_pose(_entry("boar%d" % boar.id, true), "boar", boar.pos, boar.facing < 0, tint_b)
	for carcass: Carcass in field.carcasses:
		var art: String = "corpse" if carcass.stage == Carcass.STAGE_CORPSE else "bone"
		_pose(_entry("carcass%d" % carcass.id, false), art, carcass.pos, false, Color.WHITE)
	for key: Variant in _items.keys():
		if not _seen.has(key):
			(_items[key]["display"] as Node).queue_free()
			if _items[key]["shadow"] != null:
				(_items[key]["shadow"] as Node).queue_free()
			_items.erase(key)

func count_prefix(prefix: String) -> int:
	var total: int = 0
	for key: Variant in _items.keys():
		if String(key).begins_with(prefix):
			total += 1
	return total

## Observability for tests / screenshots.
func snapshot() -> Dictionary:
	var pairs_ok: bool = true
	for key: Variant in _items.keys():
		var entry: Dictionary = _items[key]
		if entry["shadow"] != null:
			var display: Sprite3D = entry["display"]
			var shadow: Sprite3D = entry["shadow"]
			pairs_ok = pairs_ok and display.texture == shadow.texture and display.global_position.is_equal_approx(shadow.global_position) and display.flip_h == shadow.flip_h
	return {
		"boars": count_prefix("boar"),
		"nests": count_prefix("nest"),
		"ruins": count_prefix("ruin"),
		"carcasses": count_prefix("carcass"),
		"shadow_pairs_match": pairs_ok,
		"boar_texels": [texture_for("boar").get_width(), texture_for("boar").get_height()],
	}
