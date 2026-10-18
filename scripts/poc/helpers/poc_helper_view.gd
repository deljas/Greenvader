extends Node3D
## HLP-01 provisional display of helper plants, their effect areas, the ground helper seeds and the placement ghost.
## No game logic: it only reads the session. Helper plants are camera-facing 2D pixel cards like the player and the boars
## (1 texel = 1 screen px: resolution-specific frames, nearest, feet snapped to the screen pixel grid, no outline) with a
## SHADOWS_ONLY twin of the same frame so the shadow follows the sprite. The effect area is a filled translucent ground disc
## (no outline). Placeholder art is drawn here in code (replaced by final art later).
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const SUN_CARD: int = 8
## Frame (texels) per resolution index (640, 960); the 960 frame is the 640 art resized 1.5x nearest.
const FRAMES: Array[Vector2i] = [Vector2i(28, 36), Vector2i(42, 54)]
## Above the grass blades (<= ~0.36 m) so the translucent ground displays stay readable on greened ground.
const GROUND_Y: float = 0.38
const AREA_ALPHA: float = 0.17

var session: RefCounted
var camera: Camera3D
var sun: DirectionalLight3D
var resolution_index: int = 0
var render_height: int = 360
var _cards: Dictionary = {}
var _areas: Dictionary = {}
var _seen: Dictionary = {}
var _cache: Dictionary = {}
var _materials: Dictionary = {}
var _pickup_pool: Array[MeshInstance3D] = []
var _flight_pool: Array[MeshInstance3D] = []
var _units: Dictionary = {}
var _pickup_mesh: SphereMesh
var ghost: MeshInstance3D
var ghost_area: MeshInstance3D
var ghost_material: StandardMaterial3D
var ghost_area_material: StandardMaterial3D

func setup(source: RefCounted, camera_: Camera3D, sun_: DirectionalLight3D) -> void:
	session = source
	camera = camera_
	sun = sun_
	_pickup_mesh = SphereMesh.new()
	_pickup_mesh.radius = 0.5
	_pickup_mesh.height = 1.0
	_pickup_mesh.radial_segments = 4
	_pickup_mesh.rings = 2
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(1.0, 0.01, 1.0)
	ghost = MeshInstance3D.new()
	ghost.mesh = box
	ghost_material = _flat(Color(0.3, 0.9, 0.35, 0.42))
	ghost.material_override = ghost_material
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.visible = false
	add_child(ghost)
	ghost_area = _disc(1.0)
	ghost_area_material = _flat(Color(1, 1, 1, AREA_ALPHA * 0.8))
	ghost_area.material_override = ghost_area_material
	ghost_area.visible = false
	set_resolution(Config.DEFAULT_RESOLUTION)

func set_resolution(index: int) -> void:
	resolution_index = index
	render_height = Config.RESOLUTIONS[index].y

func _flat(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	return material

func _disc(radius: float) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.01
	mesh.radial_segments = 48
	mesh.rings = 1
	mesh.cap_bottom = false
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance

func _set_disc(instance: MeshInstance3D, radius: float) -> void:
	var mesh: CylinderMesh = instance.mesh
	if not is_equal_approx(mesh.top_radius, radius):
		mesh.top_radius = radius
		mesh.bottom_radius = radius

func _kind_color(key: String, alpha: float) -> Color:
	var color: Color = Color(String(session.helpers.kind_def(key).get("color", "ffffff")))
	color.a = alpha
	return color

# ---------------------------------------------------------------- placeholder art

static func _dot(image: Image, cx: float, cy: float, radius: float, color: Color) -> void:
	for y: int in range(floori(cy - radius), ceili(cy + radius) + 1):
		for x: int in range(floori(cx - radius), ceili(cx + radius) + 1):
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height() and Vector2(x + 0.5, y + 0.5).distance_to(Vector2(cx, cy)) <= radius:
				image.set_pixel(x, y, color)

static func _rect(image: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	image.fill_rect(Rect2i(x, y, w, h).intersection(Rect2i(0, 0, image.get_width(), image.get_height())), color)

## 28x36 base art per kind. Flat colours, no outline.
func _art(key: String) -> Image:
	if key == "army_unit":
		var unit_image: Image = Image.create(12, 18, false, Image.FORMAT_RGBA8)
		unit_image.fill(Color(0, 0, 0, 0))
		var body: Color = _kind_color("army", 1.0)
		_rect(unit_image, 3, 12, 2, 6, body.darkened(0.4))
		_rect(unit_image, 7, 12, 2, 6, body.darkened(0.4))
		_rect(unit_image, 2, 5, 8, 8, body)
		_rect(unit_image, 3, 0, 6, 5, body.lightened(0.2))
		_rect(unit_image, 10, 1, 1, 14, Color("d8d8d0"))
		return unit_image
	var image: Image = Image.create(FRAMES[0].x, FRAMES[0].y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var main_color: Color = _kind_color(key, 1.0)
	var leaf: Color = Color("4f9a3a")
	var dark: Color = main_color.darkened(0.35)
	match key:
		"gatlinger":
			_rect(image, 13, 17, 3, 19, leaf)
			_rect(image, 6, 28, 8, 3, leaf)
			_rect(image, 15, 24, 8, 3, leaf)
			_dot(image, 14.0, 10.0, 10.0, main_color)
			_dot(image, 14.0, 10.0, 5.5, Color("6b4423"))
			_dot(image, 14.0, 10.0, 2.5, dark)
		"sprinkler":
			_rect(image, 13, 20, 3, 16, leaf)
			_rect(image, 7, 30, 7, 3, leaf)
			for row: int in range(0, 18):
				var half: int = maxi(int(round(10.0 * (1.0 - float(row) / 18.0))), 1)
				_rect(image, 14 - half, 2 + row, half * 2, 1, main_color.lightened(0.18) if row < 4 else main_color)
			_rect(image, 9, 4, 3, 5, Color(1, 1, 1, 0.7))
		_:
			_rect(image, 8, 26, 4, 10, dark)
			_rect(image, 15, 26, 4, 10, dark)
			_rect(image, 6, 11, 16, 16, main_color)
			_rect(image, 6, 17, 16, 1, dark)
			_rect(image, 6, 23, 16, 1, dark)
			_rect(image, 8, 2, 12, 9, main_color.lightened(0.15))
			_rect(image, 10, 5, 2, 2, Color("2a1a10"))
			_rect(image, 16, 5, 2, 2, Color("2a1a10"))
			_rect(image, 24, 0, 2, 36, Color("7a5a2e"))
			_rect(image, 23, 0, 4, 4, Color("e6e6d8"))
	return image

func texture_for(key: String) -> ImageTexture:
	var cache_key: String = "%s:%d" % [key, resolution_index]
	if not _cache.has(cache_key):
		var image: Image = _art(key)
		var size: Vector2i = image.get_size() if resolution_index == 0 else Vector2i(roundi(image.get_width() * 1.5), roundi(image.get_height() * 1.5))
		if image.get_size() != size:
			image.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
		_cache[cache_key] = ImageTexture.create_from_image(image)
	return _cache[cache_key]

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

func _card(uid: int) -> Dictionary:
	if not _cards.has(uid):
		_cards[uid] = {"display": _sprite(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, 1), "shadow": _sprite(GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, SUN_CARD)}
		_areas[uid] = _disc(1.0)
		(_areas[uid] as MeshInstance3D).visible = true
	_seen[uid] = true
	return _cards[uid]

## Same pose as the boar cards: feet on a whole screen pixel, shadow twin with the identical frame.
func _pose(entry: Dictionary, key: String, foot_logic: Vector2, tint: Color) -> void:
	var texture: ImageTexture = texture_for(key)
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
	display.modulate = tint
	display.visible = true
	var shadow: Sprite3D = entry["shadow"]
	var normal: Vector3 = Vector3(sun.global_basis.z.x, 0.0, sun.global_basis.z.z).normalized()
	shadow.global_basis = Basis(Vector3.UP.cross(normal), Vector3.UP * upright, normal)
	shadow.pixel_size = pixel_size
	shadow.global_position = center
	shadow.texture = texture
	shadow.visible = true

# ---------------------------------------------------------------- per frame

func sync() -> void:
	var helpers: RefCounted = session.helpers
	_seen.clear()
	for plant: Dictionary in helpers.plants:
		var uid: int = int(plant["uid"])
		var key: String = String(plant["kind"])
		var def: Dictionary = helpers.kind_def(key)
		var entry: Dictionary = _card(uid)
		var ratio: float = float(int(plant["hp"])) / float(int(def["hp"]))
		var tint: Color = Color.WHITE.lerp(Color(1.0, 0.55, 0.55), 1.0 - ratio)
		var centre: Vector2 = helpers.plant_center_px(plant)
		_pose(entry, key, centre, tint)
		var area: MeshInstance3D = _areas[uid]
		_set_disc(area, float(def["radius_m"]))
		area.material_override = _area_material_for(plant)
		var ground: Vector2 = Coords.logic_to_ground(centre)
		area.position = Vector3(ground.x, GROUND_Y, ground.y)
	for uid: Variant in _cards.keys():
		if not _seen.has(uid):
			(_cards[uid]["display"] as Node).queue_free()
			(_cards[uid]["shadow"] as Node).queue_free()
			(_areas[uid] as Node).queue_free()
			_cards.erase(uid)
			_areas.erase(uid)
	_sync_ghost()
	_sync_pickups()
	_sync_units()
	_sync_flights()

func _area_material(key: String) -> StandardMaterial3D:
	if not _materials.has(key):
		_materials[key] = _flat(_kind_color(key, AREA_ALPHA))
	return _materials[key]

## Sprinkler states shown on its area: a pulse just wetted (bright), out of water (grey), else the kind colour.
func _area_material_for(plant: Dictionary) -> StandardMaterial3D:
	var key: String = String(plant["kind"])
	if key == "sprinkler":
		var helpers: RefCounted = session.helpers
		if helpers.pulse_fx.has(int(plant["uid"])):
			if not _materials.has("pulse"):
				_materials["pulse"] = _flat(Color(0.55, 0.85, 1.0, 0.42))
			return _materials["pulse"]
		if not helpers.is_by_water(plant) and float(plant["stock"]) + 1.0e-6 < float(helpers.spr["pulse_cost"]):
			if not _materials.has("dry"):
				_materials["dry"] = _flat(Color(0.5, 0.5, 0.5, 0.2))
			return _materials["dry"]
	return _area_material(key)

func _sync_ghost() -> void:
	var preview: Dictionary = session.helper_preview()
	ghost.visible = not preview.is_empty()
	ghost_area.visible = ghost.visible
	if preview.is_empty():
		return
	var origin: Vector2i = preview["origin"]
	var side: float = float(session.helpers.FOOTPRINT) * Config.CELL_M
	var centre: Vector2 = Coords.logic_to_ground(session.helpers.block_center_px(origin))
	ghost.scale = Vector3(side, 1.0, side)
	ghost.position = Vector3(centre.x, GROUND_Y + 0.01, centre.y)
	ghost_material.albedo_color = Color(0.3, 0.9, 0.35, 0.42) if bool(preview["ok"]) else Color(0.95, 0.25, 0.2, 0.42)
	var def: Dictionary = session.helpers.kind_def(String(preview["kind"]))
	_set_disc(ghost_area, float(def["radius_m"]))
	ghost_area.position = Vector3(centre.x, GROUND_Y + 0.005, centre.y)
	var color: Color = _kind_color(String(preview["kind"]), AREA_ALPHA * 0.8)
	ghost_area_material.albedo_color = color

func _sync_pickups() -> void:
	var items: Array[Dictionary] = session.helpers.pickups
	while _pickup_pool.size() < items.size():
		var node: MeshInstance3D = MeshInstance3D.new()
		node.mesh = _pickup_mesh
		node.material_override = _flat(Color("6cf0ff"))
		node.scale = Vector3(0.34, 0.5, 0.34)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_pickup_pool.append(node)
	var bob_time: float = session.clock.elapsed
	for i: int in _pickup_pool.size():
		_pickup_pool[i].visible = i < items.size()
		if i < items.size():
			var ground: Vector2 = Coords.logic_to_ground(Vector2(float(items[i]["x"]), float(items[i]["y"])))
			_pickup_pool[i].position = Vector3(ground.x, 0.26 + 0.04 * sin(bob_time * 4.0 + float(i)), ground.y)
			_pickup_pool[i].rotation.y = bob_time * 2.0 + float(i)

## The Army's field unit: a small camera-facing card at its position (home when idle), same pixel-grid pose as the other cards.
func _sync_units() -> void:
	var seen: Dictionary = {}
	for plant: Dictionary in session.helpers.plants:
		if String(plant["kind"]) != "army":
			continue
		var uid: int = int(plant["uid"])
		seen[uid] = true
		if not _units.has(uid):
			_units[uid] = {"display": _sprite(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, 1), "shadow": _sprite(GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, SUN_CARD)}
		_pose(_units[uid], "army_unit", session.helpers.unit_pos(plant), Color.WHITE)
	for uid: Variant in _units.keys():
		if not seen.has(uid):
			(_units[uid]["display"] as Node).queue_free()
			(_units[uid]["shadow"] as Node).queue_free()
			_units.erase(uid)

## Seeds in the air (Gatlinger): small yellow dots on a short arc from the plant to the target cell.
func _sync_flights() -> void:
	var list: Array[Dictionary] = session.helpers.flights
	while _flight_pool.size() < list.size():
		var node: MeshInstance3D = MeshInstance3D.new()
		node.mesh = _pickup_mesh
		node.material_override = _flat(Color("ffe066"))
		node.scale = Vector3(0.22, 0.22, 0.22)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_flight_pool.append(node)
	for i: int in _flight_pool.size():
		_flight_pool[i].visible = i < list.size()
		if i < list.size():
			var f: Dictionary = list[i]
			var t: float = clampf(float(f["age"]) / float(f["dur"]), 0.0, 1.0)
			var tile: float = float(session.helpers.tile_px)
			var logic: Vector2 = Vector2(float(f["ox"]), float(f["oy"])).lerp(Vector2((float(f["cx"]) + 0.5) * tile, (float(f["cy"]) + 0.5) * tile), t)
			var ground: Vector2 = Coords.logic_to_ground(logic)
			_flight_pool[i].position = Vector3(ground.x, lerpf(1.4, 0.4, t) + 1.2 * 4.0 * t * (1.0 - t), ground.y)

## Observability for tests / screenshots.
func snapshot() -> Dictionary:
	var pairs_ok: bool = true
	for uid: Variant in _cards.keys():
		var display: Sprite3D = _cards[uid]["display"]
		var shadow: Sprite3D = _cards[uid]["shadow"]
		pairs_ok = pairs_ok and display.texture == shadow.texture and display.global_position.is_equal_approx(shadow.global_position)
	return {
		"plants": _cards.size(),
		"areas": _areas.size(),
		"units": _units.size(),
		"flights_visible": _flight_pool.filter(func(n: MeshInstance3D) -> bool: return n.visible).size(),
		"pickups_visible": _pickup_pool.filter(func(n: MeshInstance3D) -> bool: return n.visible).size(),
		"ghost_visible": ghost.visible,
		"shadow_pairs_match": pairs_ok,
		"texels": [texture_for("gatlinger").get_width(), texture_for("gatlinger").get_height()],
	}
