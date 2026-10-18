extends Node
## PoC display layer: SubViewport 3D rendering, fixed orthographic quarter-view camera, resolution switching,
## ground picking and a minimal HUD. All game state lives in PocSession (preloaded below); this node only shows it.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const PocInput: GDScript = preload("res://scripts/poc/poc_input.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const Actor: GDScript = preload("res://scripts/poc/poc_actor.gd")
const PlacementView: GDScript = preload("res://scripts/poc/assets/placement_view.gd")
const PlayView: GDScript = preload("res://scripts/poc/play/poc_play_view.gd")
const EnemyViewScript: GDScript = preload("res://scripts/poc/combat/poc_enemy_view.gd")
const EnvViewScript: GDScript = preload("res://scripts/poc/environment/environment_view.gd")
const WaterViewScript: GDScript = preload("res://scripts/poc/environment/water_view.gd")
const ReadabilityScript: GDScript = preload("res://scripts/poc/environment/readability_view.gd")
const WallViewScript: GDScript = preload("res://scripts/poc/environment/wall_view.gd")
const HelperViewScript: GDScript = preload("res://scripts/poc/helpers/poc_helper_view.gd")
const WeatherViewScript: GDScript = preload("res://scripts/poc/environment/weather_view.gd")
const OcclusionViewScript: GDScript = preload("res://scripts/poc/occlusion/occlusion_view.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const PocUi: GDScript = preload("res://scripts/poc/ui/poc_ui.gd")
const ViewpointScript: GDScript = preload("res://scripts/poc/view/poc_viewpoint.gd")
const ViewMarkerScript: GDScript = preload("res://scripts/poc/view/viewpoint_view.gd")
const ViewPanelScript: GDScript = preload("res://scripts/poc/view/viewpoint_panel.gd")
const AudioScript: GDScript = preload("res://scripts/poc/audio/poc_audio.gd")

const WALL_BORDER_M: float = 1.0
const WALL_BLOCK_M: float = 1.6
const NOTICE_SECONDS: float = 4.0

var session: RefCounted
var render_view: SubViewport
var view_rect: TextureRect
var world: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
## WTH-01 weather display: the rain overlay (a ColorRect inside the render SubViewport, over the 3D picture) and the 3D part (cloud shadows).
var rain_rect: ColorRect
var weather_view: Node3D
var actor: Node3D
## POC-02 placed objects (GLB instances); null with the bare POC-01 fixture (user arg --bare).
var placement_view: Node3D
var marker: MeshInstance3D
## POC-03 provisional display of plants, pickups, sources and shots.
var play_view: Node3D
## POC-04 provisional display of nests / boars / carcasses; null unless the combat fixture is loaded (--combat or meta "poc_combat").
var enemy_view: Node3D
## HLP-01 display of helper plants, their effect areas, the ground helper seeds and the placement ghost.
var helper_view: Node3D
## POC-05: day/night lighting from the game clock, water reflection, wall vegetation (null without a placement).
var env_view: Node
var water_view: Node3D
var wall_view: Node3D
## POL-01 foot marker / night lights (display only).
var readability: Node3D
var world_environment: Environment
## POC-06: fades the placed objects that hide the player (display only); null without a placement.
var occlusion_view: Node
## WTH-02: viewpoint logic (RefCounted; `active` = the panorama is shown and the world is stopped), its ground marker, the panel
## and the sound (display / effect only).
var viewpoint: RefCounted
var viewpoint_view: Node3D
var view_panel: PanelContainer
var audio: Node
var _near_spot_prev: bool = false
var _seen_message: int = 0
var resolution_index: int = Config.DEFAULT_RESOLUTION
## Per-frame driving from Input/_process; tests turn this off and call tick() themselves.
var auto_process: bool = true
var window_size_override: Vector2i = Vector2i(-1, -1)
var walking: bool = false
var facing_left: bool = false
var animation_time: float = 0.0
var notice_time: float = 0.0
var hud: Label
var notice: Label
var button_box: HBoxContainer
var resolution_buttons: Array[Button] = []
var pause_button: Button
var ui_controls: Array[Control] = []
var _right: Vector3
var _up: Vector3
var _offset: Vector3
## POC-08: UI layer (title / pause menu / help / badge), the save folder (tests may point it elsewhere) and the menu state.
var ui: CanvasLayer
var save_dir: String = PocSave.DEFAULT_DIR
## "" (playing), "title", "pause" or "help". The game clock stays paused while a menu is open.
var menu: StringName = &""
var _menu_prev_paused: bool = false
var _help_return: StringName = &"pause"
var _town: bool = false
var _args_combat: bool = false
var _args_bare: bool = false
## The title appears only when this scene is the running main scene (run_poc.bat); `--no-title` or a test instance skips it.
var show_title_at_start: bool = false

func _ready() -> void:
	PocInput.register()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	# POC-07: the playable town (combat on) is the default when this scene is the game's main scene, or with --town /
	# meta "poc_town". The older fixtures stay available: --fixture=02 (placement only), --fixture=04 or --combat (combat
	# fixture), --bare; a test that instantiates the scene without any of these still gets the POC-02 placement fixture.
	var legacy: bool = args.has("--fixture=02") or args.has("--fixture=04") or args.has("--combat") or args.has("--bare")
	var town: bool = not legacy and (args.has("--town") or bool(get_meta(&"poc_town", false)) or (get_tree().current_scene == self and not bool(get_meta(&"poc_combat", false))))
	_town = town
	_args_combat = args.has("--combat") or args.has("--fixture=04") or bool(get_meta(&"poc_combat", false))
	_args_bare = args.has("--bare")
	show_title_at_start = town and get_tree().current_scene == self and not args.has("--no-title")
	session = make_session()
	var elevation: float = deg_to_rad(Config.ELEVATION_DEG)
	var azimuth: float = deg_to_rad(Config.AZIMUTH_DEG)
	var horizontal: Vector3 = Vector3(sin(azimuth), 0.0, cos(azimuth))
	_offset = (horizontal * cos(elevation) + Vector3.UP * sin(elevation)) * Config.CAMERA_DISTANCE_M
	_right = Vector3(horizontal.z, 0.0, -horizontal.x)
	_up = Vector3(-horizontal.x * sin(elevation), cos(elevation), -horizontal.z * sin(elevation))
	var window: Window = get_window()
	window.title = "グリーンベーダー｜3D PoC"
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	window.min_size = Config.MIN_WINDOW
	window.content_scale_size = Config.RESOLUTIONS[resolution_index]
	if OS.get_cmdline_user_args().has("--1080"):
		window.size = Vector2i(1920, 1080)
	window.size_changed.connect(_on_window_size_changed)
	_build_view()
	_build_world()
	_build_ui()
	audio = AudioScript.new()
	add_child(audio)
	audio.calm_provider = Callable(self, "is_calm")
	audio.attach(session)
	_apply_resolution_layout()
	_refresh()
	if show_title_at_start:
		open_title()

## Builds a new session for the map this instance plays (also used by new game and by loading a save).
func make_session() -> RefCounted:
	var made: RefCounted
	if _town:
		var size: Vector2i = Session.town_size()
		made = Session.new(size.x, size.y)
		made.paving = Session.paving_from(made.env_tuning)
		if not made.load_combat(Session.TOWN_SETUP):
			push_error("PoC: town map %s could not be loaded" % Session.TOWN_SETUP)
		else:
			print("PoC: map town_01 (%dx%d cells, %d objects, combat on)" % [size.x, size.y, made.placement.instances.size()])
	else:
		made = Session.new()
		made.paving = Session.paving_from(made.env_tuning)
		if _args_combat:
			made.load_combat()
		elif not _args_bare:
			made.load_placement()
	made.debug_refill_enabled = OS.get_cmdline_user_args().has("--debug-refill")
	made.debug_weather_enabled = OS.get_cmdline_user_args().has("--debug-weather")
	return made

# ---------------------------------------------------------------- construction

func _build_view() -> void:
	render_view = SubViewport.new()
	render_view.size = Config.RESOLUTIONS[resolution_index]
	render_view.own_world_3d = true
	render_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_view.msaa_3d = Viewport.MSAA_DISABLED
	render_view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	render_view.use_taa = false
	render_view.use_debanding = false
	add_child(render_view)
	view_rect = TextureRect.new()
	view_rect.texture = render_view.get_texture()
	view_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view_rect.stretch_mode = TextureRect.STRETCH_SCALE
	view_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view_rect)
	rain_rect = ColorRect.new()
	rain_rect.name = "RainOverlay"
	rain_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rain_rect.color = Color(1, 1, 1, 1)
	rain_rect.visible = false
	render_view.add_child(rain_rect) # inside the render viewport: drawn in render pixels, over the 3D picture

func _build_world() -> void:
	world = Node3D.new()
	render_view.add_child(world)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("29332f")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.68, 0.72)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var env_node: WorldEnvironment = WorldEnvironment.new()
	env_node.environment = environment
	world.add_child(env_node)
	world_environment = environment
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 95.0
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 0.4
	sun.light_angular_distance = 0.0
	sun.light_energy = 0.8
	sun.shadow_caster_mask = 1 | 8
	world.add_child(sun)
	sun.look_at_from_position(Vector3(0, 10, 0), Vector3(0, 10, 0) + Vector3(0.8, -0.75, -0.2), Vector3.UP)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = Config.CAMERA_SIZE_M
	camera.far = Config.CAMERA_FAR_M
	world.add_child(camera)
	camera.current = true
	_build_terrain_meshes()
	if session.placement != null:
		placement_view = PlacementView.new()
		placement_view.name = "Placement"
		world.add_child(placement_view)
		placement_view.build(session.placement)
	if session.wall_growth != null:
		wall_view = WallViewScript.new()
		wall_view.name = "WallVegetation"
		world.add_child(wall_view)
		wall_view.build(session.wall_growth, session.env_tuning.get("wall", {}))
	water_view = WaterViewScript.new()
	water_view.name = "Water"
	world.add_child(water_view)
	water_view.setup(render_view, camera, session, session.env_tuning, placement_view)
	play_view = PlayView.new()
	play_view.name = "PlayView"
	world.add_child(play_view)
	play_view.build(session)
	if session.enemies != null:
		enemy_view = EnemyViewScript.new()
		enemy_view.name = "EnemyView"
		world.add_child(enemy_view)
		enemy_view.setup(session, camera, sun)
		enemy_view.set_resolution(resolution_index)
	helper_view = HelperViewScript.new()
	helper_view.name = "HelperView"
	world.add_child(helper_view)
	helper_view.setup(session, camera, sun)
	helper_view.set_resolution(resolution_index)
	marker = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.5, 0.04, 0.5)
	marker.mesh = box
	var marker_material: StandardMaterial3D = StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.albedo_color = Color("ffd34a")
	marker.material_override = marker_material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = false
	world.add_child(marker)
	actor = Actor.new()
	world.add_child(actor)
	actor.setup(camera)
	actor.set_resolution(resolution_index)
	env_view = EnvViewScript.new()
	env_view.name = "EnvView"
	add_child(env_view)
	readability = ReadabilityScript.new()
	readability.name = "Readability"
	world.add_child(readability)
	readability.setup(session.env_tuning, session.placement, placement_view.holders if placement_view != null else {})
	env_view.readability = readability
	weather_view = WeatherViewScript.new()
	weather_view.name = "WeatherView"
	world.add_child(weather_view)
	weather_view.setup(session, camera, rain_rect)
	weather_view.set_resolution(Config.RESOLUTIONS[resolution_index])
	env_view.weather_view = weather_view
	env_view.setup(session, world_environment, sun, water_view)
	if placement_view != null:
		occlusion_view = OcclusionViewScript.new()
		occlusion_view.name = "OcclusionView"
		add_child(occlusion_view)
		occlusion_view.setup(placement_view, wall_view, camera, water_view)
	viewpoint = ViewpointScript.new(session)
	viewpoint_view = null
	if viewpoint.has_spot:
		viewpoint_view = ViewMarkerScript.new()
		viewpoint_view.name = "ViewpointMarker"
		world.add_child(viewpoint_view)
		viewpoint_view.build(viewpoint.cell, viewpoint.tuning)
	_near_spot_prev = false
	_update_camera()
	_update_actor()
	_update_occlusion(0.0)

## Frees everything that shows the current session (the 3D world and the two display helpers outside it).
func _teardown_world() -> void:
	if occlusion_view != null:
		remove_child(occlusion_view)
		occlusion_view.free()
		occlusion_view = null
	if env_view != null:
		remove_child(env_view)
		env_view.free()
		env_view = null
	if world != null:
		render_view.remove_child(world)
		world.free()
		world = null
	readability = null
	viewpoint_view = null
	weather_view = null
	placement_view = null
	wall_view = null
	water_view = null
	play_view = null
	enemy_view = null
	helper_view = null
	actor = null
	marker = null

## Swaps in a fully built session: the old one is closed, every view (placement, occlusion, wall vegetation, ground cover,
## enemies, play) is rebuilt through the normal build path. Used by new game and by a successful load.
func replace_session(new_session: RefCounted) -> void:
	var old: RefCounted = session
	_teardown_world()
	session = new_session
	if old != null and old != new_session:
		old.close()
	_build_world()
	if view_panel != null:
		view_panel.hide_panel()
	if audio != null:
		audio.attach(session)
	_seen_message = session.message_serial
	walking = false
	animation_time = 0.0
	notice.text = ""
	notice_time = 0.0
	_apply_resolution_layout()
	_refresh()

func _wall_height(x: int, y: int) -> float:
	var state: WorldState = session.state
	if not state.in_bounds(x, y):
		return 0.0
	if state.terrain[state.index_of(x, y)] != Session.T_BUILDING:
		return 0.0
	var border: bool = x == 0 or y == 0 or x == state.width - 1 or y == state.height - 1
	if session.placement != null and not border:
		return 0.0
	return WALL_BORDER_M if border else WALL_BLOCK_M

func _build_terrain_meshes() -> void:
	var state: WorldState = session.state
	var ground: Dictionary = _new_arrays()
	var blocks: Dictionary = _new_arrays()
	var cell: float = Config.CELL_M
	for y: int in state.height:
		for x: int in state.width:
			var def: TerrainDef = state.terrain_def_at(state.index_of(x, y))
			if session.placement != null:
				def = state.terrain_defs[session.base_terrain[state.index_of(x, y)]]
			var color: Color = def.ground_color
			var x0: float = Coords.ORIGIN.x + float(x) * cell
			var z0: float = Coords.ORIGIN.y + float(y) * cell
			var x1: float = x0 + cell
			var z1: float = z0 + cell
			var h: float = _wall_height(x, y)
			if h <= 0.0:
				_quad(ground, Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1), Vector3.UP, color)
				continue
			_quad(blocks, Vector3(x0, h, z0), Vector3(x1, h, z0), Vector3(x1, h, z1), Vector3(x0, h, z1), Vector3.UP, color.lightened(0.12))
			var shade: Color = color.darkened(0.06)
			var low: float = _wall_height(x, y - 1)
			if low < h:
				_quad(blocks, Vector3(x0, h, z0), Vector3(x1, h, z0), Vector3(x1, low, z0), Vector3(x0, low, z0), Vector3(0, 0, -1), shade)
			low = _wall_height(x, y + 1)
			if low < h:
				_quad(blocks, Vector3(x1, h, z1), Vector3(x0, h, z1), Vector3(x0, low, z1), Vector3(x1, low, z1), Vector3(0, 0, 1), shade)
			low = _wall_height(x - 1, y)
			if low < h:
				_quad(blocks, Vector3(x0, h, z1), Vector3(x0, h, z0), Vector3(x0, low, z0), Vector3(x0, low, z1), Vector3(-1, 0, 0), shade)
			low = _wall_height(x + 1, y)
			if low < h:
				_quad(blocks, Vector3(x1, h, z0), Vector3(x1, h, z1), Vector3(x1, low, z1), Vector3(x1, low, z0), Vector3(1, 0, 0), shade)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	material.metallic_specular = 0.0
	for pair: Array in [[ground, "Ground", false], [blocks, "Blocks", true]]:
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.name = pair[1]
		instance.mesh = _mesh_from(pair[0], material)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if pair[2] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not pair[2]:
			instance.layers = 2 # the floor is not part of the water reflection (layer 1 only)
		world.add_child(instance)

func _new_arrays() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "i": PackedInt32Array()}

func _quad(arrays: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	var vertices: PackedVector3Array = arrays["v"]
	var normals: PackedVector3Array = arrays["n"]
	var colors: PackedColorArray = arrays["c"]
	var indices: PackedInt32Array = arrays["i"]
	var base: int = vertices.size()
	for point: Vector3 in [a, b, c, d]:
		vertices.append(point)
		normals.append(normal)
		colors.append(color)
	indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	arrays["v"] = vertices
	arrays["n"] = normals
	arrays["c"] = colors
	arrays["i"] = indices

func _mesh_from(arrays: Dictionary, material: Material) -> ArrayMesh:
	var data: Array = []
	data.resize(Mesh.ARRAY_MAX)
	data[Mesh.ARRAY_VERTEX] = arrays["v"]
	data[Mesh.ARRAY_NORMAL] = arrays["n"]
	data[Mesh.ARRAY_COLOR] = arrays["c"]
	data[Mesh.ARRAY_INDEX] = arrays["i"]
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data)
	mesh.surface_set_material(0, material)
	return mesh

func _build_ui() -> void:
	hud = Label.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.8))
	hud.add_theme_constant_override(&"shadow_offset_x", 1)
	hud.add_theme_constant_override(&"shadow_offset_y", 1)
	add_child(hud)
	notice = Label.new()
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice.add_theme_color_override(&"font_color", Color("ffd34a"))
	notice.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.9))
	notice.add_theme_constant_override(&"shadow_offset_x", 1)
	notice.add_theme_constant_override(&"shadow_offset_y", 1)
	add_child(notice)
	button_box = HBoxContainer.new()
	add_child(button_box)
	for i: int in Config.RESOLUTIONS.size():
		var res: Vector2i = Config.RESOLUTIONS[i]
		var button: Button = Button.new()
		button.text = "%d×%d" % [res.x, res.y]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(set_resolution.bind(i))
		button_box.add_child(button)
		resolution_buttons.append(button)
		ui_controls.append(button)
	pause_button = Button.new()
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.pressed.connect(toggle_pause)
	button_box.add_child(pause_button)
	ui_controls.append(pause_button)
	ui_controls.append(button_box)
	view_panel = ViewPanelScript.new()
	view_panel.name = "ViewpointPanel"
	add_child(view_panel)
	ui = PocUi.new()
	ui.name = "PocUi"
	add_child(ui)
	ui.chosen.connect(_on_ui_chosen)
	for control: Control in ui.blockers:
		ui_controls.append(control)

func _apply_resolution_layout() -> void:
	var res: Vector2i = Config.RESOLUTIONS[resolution_index]
	var font_size: int = 10 * res.x / 640
	var theme_: Theme = Theme.new()
	theme_.default_font_size = font_size
	for control: Control in [hud, notice, button_box]:
		control.theme = theme_
	hud.position = Vector2(4, 2)
	notice.position = Vector2(4, res.y - font_size * 2 - 6)
	button_box.reset_size()
	button_box.position = Vector2(res.x - button_box.get_combined_minimum_size().x - 4, 2)
	view_rect.size = Vector2(res)
	rain_rect.size = Vector2(res)
	if view_panel != null:
		view_panel.layout(res)
	if weather_view != null:
		weather_view.set_resolution(res)
	if ui != null:
		ui.set_scale_for(res)

# ---------------------------------------------------------------- resolution

func current_resolution() -> Vector2i:
	return Config.RESOLUTIONS[resolution_index]

## Real window size; tests may set window_size_override (headless windows are always content-sized).
func window_size() -> Vector2i:
	return get_window().size if window_size_override.x < 0 else window_size_override

## Switches the render resolution. The visible area (camera.size), the player position and the aim stay.
## Returns false (and shows a notice) when the window is smaller than the requested resolution.
func set_resolution(index: int, window_size_: Vector2i = Vector2i(-1, -1)) -> bool:
	if index < 0 or index >= Config.RESOLUTIONS.size():
		return false
	var win: Vector2i = window_size() if window_size_.x < 0 else window_size_
	var res: Vector2i = Config.RESOLUTIONS[index]
	if not Config.fits(res, win):
		show_notice("窓が小さく %d×%d は選べません（現在 %d×%d）" % [res.x, res.y, win.x, win.y])
		return false
	resolution_index = index
	render_view.size = res
	get_window().content_scale_size = res
	actor.set_resolution(index)
	if enemy_view != null:
		enemy_view.set_resolution(index)
	helper_view.set_resolution(index)
	water_view.set_render_size(res)
	_apply_resolution_layout()
	_update_camera()
	_update_actor()
	if occlusion_view != null:
		occlusion_view.reset()
	_update_occlusion(0.0)
	_refresh()
	return true

func toggle_resolution(window_size_: Vector2i = Vector2i(-1, -1)) -> bool:
	return set_resolution((resolution_index + 1) % Config.RESOLUTIONS.size(), window_size_)

func _on_window_size_changed() -> void:
	enforce_window(window_size())

## Disables resolutions that do not fit; falls back to the lowest one (with a notice) if the current one no longer fits.
func enforce_window(win: Vector2i) -> void:
	for i: int in resolution_buttons.size():
		resolution_buttons[i].disabled = not Config.fits(Config.RESOLUTIONS[i], win)
	if not Config.fits(Config.RESOLUTIONS[resolution_index], win):
		var res: Vector2i = Config.RESOLUTIONS[resolution_index]
		set_resolution(Config.DEFAULT_RESOLUTION, win)
		show_notice("窓が小さいため %d×%d から 640×360 へ戻しました" % [res.x, res.y])

func show_notice(text: String) -> void:
	notice.text = text
	notice_time = NOTICE_SECONDS

# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if auto_process:
		tick(delta, PocInput.move_vector())
	else:
		_refresh()

## One frame: walk, advance game time, update camera/actor/HUD.
func tick(delta: float, screen_dir: Vector2) -> void:
	var moved: Vector2 = session.walk(screen_dir, delta)
	walking = moved.length_squared() > 0.000001
	if walking:
		animation_time += delta
		if absf(screen_dir.x) > 0.01:
			facing_left = screen_dir.x < 0.0
	session.advance(delta)
	ui.tick(delta)
	audio.update(delta)
	_check_spot_hint()
	env_view.sync()
	play_view.sync()
	if wall_view != null:
		wall_view.sync()
	if enemy_view != null:
		enemy_view.sync()
	helper_view.sync()
	if session.message_serial != _seen_message:
		_seen_message = session.message_serial
		show_notice(session.last_message)
	if notice_time > 0.0:
		notice_time -= delta
		if notice_time <= 0.0:
			notice.text = ""
	_update_camera()
	_update_actor()
	_update_occlusion(delta)
	water_view.sync_camera()
	_refresh()

## POC-06: judge what hides the player from the (already updated) camera and fade it. Display only.
func _update_occlusion(delta: float) -> void:
	if occlusion_view == null:
		return
	var upright: float = 1.0 / maxf(camera.global_basis.y.dot(Vector3.UP), 0.1)
	occlusion_view.update(delta, player_ground3() + Vector3.UP * 0.04, float(actor.snapshot()["height_m"]) * upright)
	if readability != null:
		readability.set_see_through(not occlusion_view.fading.is_empty())

func player_ground3() -> Vector3:
	return Coords.ground3(Coords.logic_to_ground(session.position), 0.0)

## Camera follows the player; the target is rounded to the screen pixel grid so sprites do not shimmer.
func _update_camera() -> void:
	var viewing: bool = is_viewing()
	camera.size = viewpoint.camera_size() if viewing else Config.CAMERA_SIZE_M
	var pixel: float = camera.size / float(render_view.size.y)
	var focus: Vector3 = viewpoint.focus_point() if viewing else player_ground3() + Vector3.UP * Config.CAMERA_TARGET_HEIGHT_M
	focus += _right * (snappedf(focus.dot(_right), pixel) - focus.dot(_right))
	focus += _up * (snappedf(focus.dot(_up), pixel) - focus.dot(_up))
	camera.position = focus + _offset
	camera.look_at(focus, Vector3.UP)

func _update_actor() -> void:
	actor.pose(player_ground3() + Vector3.UP * 0.04, (int(animation_time * 6.0) % 4) if walking else 1, facing_left, sun)
	if readability != null:
		readability.follow(actor.render_foot, Vector3(camera.global_basis.z.x, 0.0, camera.global_basis.z.z).normalized())
	if session.has_aim:
		marker.position = Coords.ground3(Coords.logic_to_ground(session.aim), 0.03)
		marker.visible = true
	else:
		marker.visible = false

func game_time_text() -> String:
	var t: float = session.clock.elapsed
	return "%02d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]

func _refresh() -> void:
	if hud == null:
		return
	var res: Vector2i = current_resolution()
	var scale_: int = Config.integer_scale(res, window_size())
	var cell: Vector2i = Coords.logic_to_cell(session.position)
	var lines: PackedStringArray = []
	lines.append("解像度 %d×%d（窓 %d×%d, %d倍）　視野 %.1fm" % [res.x, res.y, window_size().x, window_size().y, scale_, camera.size])
	lines.append("論理 (%.1f, %.1f) セル (%d,%d)　ゲーム時刻 %s　時刻 %s　天気 %s%s ×%d%s" % [session.position.x, session.position.y, cell.x, cell.y, game_time_text(), env_view.hour_text(), session.weather_text(), "【デバッグ固定 1/2/3, 0=解除】" if session.weather.override_type >= 0 else "", int(session.multiplier), "　【展望中】" if is_viewing() else ("　【一時停止】" if session.paused else "")])
	var play: PlayState = session.play
	var status: String = "種 %d　水 %d/%d　HP %d/%d　選択 %s　緑化 %d%%（%d/%d）" % [play.seeds, roundi(play.water), roundi(play.tuning.water_max), play.hp, play.hp_max, session.selected_label(), session.greening_percent(), session.state.greened_count, session.state.target_count]
	if session.debug_refill_enabled:
		status += "　【デバッグ補給有効 F9】"
	lines.append(status)
	if session.enemies != null:
		lines.append(session.combat_status_text())
	lines.append(session.helper_status_text())
	lines.append("WASD=移動　左=種　右=水　Tab/ホイール=植物切替　E=調べる/持ち上げ/展望　Q=設置モード　Esc=メニュー　F2=解像度　F3=倍速　F5=保存　M=音")
	hud.text = "\n".join(lines)
	hud.visible = not is_viewing() # the panorama shows its own panel instead of the debug-style status lines
	ui.set_badge(session.greening_percent(), session.state.greened_count, session.state.target_count, zone_summary())
	pause_button.text = "再開" if session.paused else "停止"
	if is_viewing() and view_panel.label.text != viewpoint.panel_text(session):
		view_panel.show_text(viewpoint.panel_text(session), res)

# ---------------------------------------------------------------- input / picking

func toggle_pause() -> void:
	if is_viewing():
		return
	if menu == &"pause":
		close_menu()
		return
	session.paused = not session.paused
	_refresh()

func cycle_speed() -> void:
	var index: int = Config.MULTIPLIERS.find(session.multiplier)
	session.multiplier = Config.MULTIPLIERS[(index + 1) % Config.MULTIPLIERS.size()]
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"poc_mute", false, true):
		audio.toggle_mute()
		show_notice("音：" + ("消す" if audio.muted else "出す"))
		return
	if is_viewing():
		# The panorama: only Esc / E (back), F2 (resolution) and M (sound) do anything; clicks and the other keys are not game input.
		if event.is_action_pressed(&"poc_pause", false, true) or event.is_action_pressed(&"poc_interact", false, true):
			leave_viewpoint()
		elif event.is_action_pressed(&"poc_toggle_resolution", false, true):
			toggle_resolution()
		return
	if menu != &"":
		if event.is_action_pressed(&"poc_pause", false, true):
			_on_escape_in_menu()
		return
	if event.is_action_pressed(&"poc_pause", false, true):
		open_pause_menu()
	elif event.is_action_pressed(&"poc_quick_save", false, true):
		save_game()
	elif event.is_action_pressed(&"poc_toggle_resolution", false, true):
		toggle_resolution()
	elif event.is_action_pressed(&"poc_cycle_speed", false, true):
		cycle_speed()
	elif event.is_action_pressed(&"poc_plant_next", false, true) or event.is_action_pressed(&"poc_plant_wheel_next"):
		session.cycle_plant(1)
		_refresh()
	elif event.is_action_pressed(&"poc_plant_wheel_prev"):
		session.cycle_plant(-1)
		_refresh()
	elif event.is_action_pressed(&"poc_helper_mode", false, true):
		session.cycle_helper_mode()
		_refresh()
	elif event.is_action_pressed(&"poc_interact", false, true):
		interact()
	elif session.debug_weather_enabled and _debug_weather_key(event):
		pass
	elif event.is_action_pressed(&"poc_debug_refill", false, true):
		if not session.debug_refill():
			show_notice("デバッグ補給は無効です（--debug-refill で有効化）")
	elif event is InputEventMouseButton and event.is_action_pressed(&"poc_primary"):
		if session.helper_mode_active():
			click_place((event as InputEventMouseButton).position)
		else:
			click_fire((event as InputEventMouseButton).position, false)
	elif event is InputEventMouseButton and event.is_action_pressed(&"poc_secondary"):
		if session.helper_mode_active():
			session.end_helper_mode()
		else:
			click_fire((event as InputEventMouseButton).position, true)
	elif event is InputEventMouseMotion:
		place_aim_at((event as InputEventMouseMotion).position)

## WTH-01 development keys (only with --debug-weather): 1 clear, 2 cloudy, 3 rain, 0 back to the schedule. Never saved.
func _debug_weather_key(event: InputEvent) -> bool:
	var picked: int = -2
	if event.is_action_pressed(&"poc_debug_weather_clear", false, true):
		picked = 0
	elif event.is_action_pressed(&"poc_debug_weather_cloudy", false, true):
		picked = 1
	elif event.is_action_pressed(&"poc_debug_weather_rain", false, true):
		picked = 2
	elif event.is_action_pressed(&"poc_debug_weather_auto", false, true):
		picked = -1
	if picked == -2:
		return false
	session.set_debug_weather(picked)
	env_view.sync()
	_refresh()
	return true

func _over_ui(content_pos: Vector2) -> bool:
	for control: Control in ui_controls:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(content_pos):
			return true
	return false

## Content (root viewport) pixel -> ground. Rejects the letterbox margin, UI controls and points off the map.
## Returns {ok, reason, ground (X,Z m), logic (px)}.
func pick_ground(content_pos: Vector2) -> Dictionary:
	if is_viewing():
		return {"ok": false, "reason": "view"}
	if not Rect2(Vector2.ZERO, Vector2(render_view.size)).has_point(content_pos):
		return {"ok": false, "reason": "margin"}
	if _over_ui(content_pos):
		return {"ok": false, "reason": "ui"}
	var origin: Vector3 = camera.project_ray_origin(content_pos)
	var direction: Vector3 = camera.project_ray_normal(content_pos)
	if absf(direction.y) < 0.000001:
		return {"ok": false, "reason": "horizon"}
	var hit: Vector3 = origin + direction * (-origin.y / direction.y)
	var ground: Vector2 = Vector2(hit.x, hit.z)
	var logic: Vector2 = Coords.ground_to_logic(ground)
	var cell: Vector2i = Coords.logic_to_cell(logic)
	if not session.state.in_bounds(cell.x, cell.y):
		return {"ok": false, "reason": "outside", "ground": ground, "logic": logic}
	return {"ok": true, "reason": "", "ground": ground, "logic": logic}

func place_aim_at(content_pos: Vector2) -> bool:
	var result: Dictionary = pick_ground(content_pos)
	if not result["ok"]:
		return false
	session.set_aim(result["logic"])
	_update_actor()
	return true

## E: lifts a helper plant next to the player; otherwise describes the aimed cell (the old inspect).
func interact() -> void:
	if enter_viewpoint():
		return
	if session.helpers.is_carrying():
		show_notice("持ち上げ中（Qで設置モード→左クリックで置き直し）")
		return
	var lifted: Dictionary = session.lift_helper()
	if bool(lifted["ok"]):
		_refresh()
		return
	show_notice(session.inspect(session.aim if session.has_aim else session.position))

## Click in placement mode: aim there and try to place. Rejected UI / margin / off-map clicks place nothing.
func click_place(content_pos: Vector2) -> Dictionary:
	var result: Dictionary = pick_ground(content_pos)
	if not result["ok"]:
		return {"ok": false, "code": String(result["reason"]), "reason": "", "uid": 0}
	session.set_aim(result["logic"])
	var placed: Dictionary = session.place_helper(result["logic"])
	if bool(placed["ok"]):
		audio.play_action(&"place")
	_update_actor()
	_refresh()
	return placed

## Click at a content (root viewport) pixel: aim there and fire seed (water_shot false) or water. UI / margin / off-map
## clicks are rejected and fire nothing. Returns the session.fire() result plus the picked point.
func click_fire(content_pos: Vector2, water_shot: bool) -> Dictionary:
	var result: Dictionary = pick_ground(content_pos)
	if not result["ok"]:
		return {"ok": false, "reason": String(result["reason"])}
	session.set_aim(result["logic"])
	var fired: Dictionary = session.fire(water_shot, result["logic"])
	if bool(fired["ok"]):
		audio.play_action(&"water" if water_shot else &"seed")
	fired["logic"] = result["logic"]
	_update_actor()
	return fired

# ---------------------------------------------------------------- WTH-02 viewpoint

func is_viewing() -> bool:
	return viewpoint != null and viewpoint.active

## True while the world is stopped on purpose (pause / menu / panorama): ambient sound is softened and action sounds are not played.
func is_calm() -> bool:
	return session.paused or menu != &"" or is_viewing()

## E at the spot: the panorama (the world stops like a pause). Returns false away from the spot.
func enter_viewpoint() -> bool:
	if menu != &"" or not viewpoint.enter(session):
		return false
	_update_camera()
	_update_actor()
	if occlusion_view != null:
		occlusion_view.reset()
	_scale_cloud_shadow()
	view_panel.show_text(viewpoint.panel_text(session), current_resolution())
	_refresh()
	return true

func leave_viewpoint() -> bool:
	if not viewpoint.leave(session):
		return false
	view_panel.hide_panel()
	_scale_cloud_shadow()
	_update_camera()
	_update_actor()
	if occlusion_view != null:
		occlusion_view.reset()
	_update_occlusion(0.0)
	_refresh()
	return true

## The cloud-shadow quad (56 m) is widened for the wide view so its edge stays off screen (display only).
func _scale_cloud_shadow() -> void:
	if weather_view != null and weather_view.cloud_mesh != null:
		var factor: float = viewpoint.camera_size() / Config.CAMERA_SIZE_M if is_viewing() else 1.0
		weather_view.cloud_mesh.scale = Vector3(factor, 1.0, factor)

## One notice when the player walks up to the spot.
func _check_spot_hint() -> void:
	var near: bool = viewpoint.has_spot and not is_viewing() and viewpoint.is_near(session.position)
	if near and not _near_spot_prev:
		show_notice("E：%sから街を見渡す" % viewpoint.spot_name)
	_near_spot_prev = near

# ---------------------------------------------------------------- POC-08 menus, save and load

## "Safe zone  complete / Town  clearing ..." for the badge (the zone notices themselves stay the existing session messages).
func zone_summary() -> String:
	if session.zone_defs.is_empty():
		return ""
	var parts: PackedStringArray = []
	for def: ZoneDef in session.zone_defs:
		parts.append("%s:%s" % [ZoneHud.zone_name(session.zone_defs, def.id), ZoneHud.state_name(session.state.zone_state[def.id])])
	return "　".join(parts) + ("　【全地域緑化】" if session.state.cleared else "")

func _open_menu(name_: StringName) -> void:
	leave_viewpoint()
	if menu == &"":
		_menu_prev_paused = session.paused
	session.paused = true
	menu = name_

func open_title(message: String = "") -> void:
	_open_menu(&"title")
	ui.show_title(PocSave.slot_info(save_dir), message)
	_refresh()

func open_pause_menu(message: String = "") -> void:
	if menu != &"":
		return
	_open_menu(&"pause")
	ui.show_pause(PocSave.slot_info(save_dir), message)
	_refresh()

func open_help() -> void:
	_help_return = menu if menu != &"help" else _help_return
	menu = &"help"
	ui.show_help(_help_return)

func close_menu() -> void:
	ui.hide_menus()
	session.paused = _menu_prev_paused
	menu = &""
	_refresh()

func _on_escape_in_menu() -> void:
	if menu == &"pause":
		close_menu()
	elif menu == &"help":
		_help_back()

func _help_back() -> void:
	menu = _help_return
	if menu == &"title":
		ui.show_title(PocSave.slot_info(save_dir))
	else:
		ui.show_pause(PocSave.slot_info(save_dir))

func _on_ui_chosen(action: StringName) -> void:
	match action:
		&"new_game":
			new_game()
		&"continue":
			load_game(false)
		&"backup":
			load_game(true)
		&"resume":
			close_menu()
		&"save":
			ui.set_menu_message("保存中…")
			await get_tree().process_frame
			var result: Dictionary = save_game()
			ui.show_pause(PocSave.slot_info(save_dir), "保存しました" if bool(result["ok"]) else String(result["reason"]))
		&"load":
			load_game(false)
		&"help":
			open_help()
		&"help_back":
			_help_back()
		&"title":
			menu = &"title"
			ui.show_title(PocSave.slot_info(save_dir))

## Starts a new game (the untouched start-up session is reused, otherwise a fresh one is built).
func new_game() -> void:
	var untouched: bool = session.clock.elapsed == 0.0 and session.projectiles.launched == 0 and session.play.pickups.count() == 0
	if not untouched:
		replace_session(make_session())
	_menu_prev_paused = false
	close_menu()
	show_notice("新規開始")

## Manual save to the one slot (the previous slot becomes the backup). Shows the result; returns PocSave.save()'s result.
func save_game() -> Dictionary:
	if is_viewing():
		ui.show_toast("展望中は保存できません（Esc か E で戻る）")
		return PocSave.result_fail("viewpoint", "展望中は保存できません")
	var result: Dictionary = PocSave.save(session, save_dir, {"resolution_index": resolution_index})
	if bool(result["ok"]):
		ui.show_toast("保存しました（ゲーム時間 %s）" % game_time_text())
	else:
		ui.show_toast("保存できません：" + String(result["reason"]), 5.0)
	return result

## Loads the slot (or the backup). A new session is built and checked first; only a good one replaces the running session, so
## a rejected file leaves the game exactly as it is and the reason is shown in Japanese. Returns the PocSave result.
func load_game(use_backup: bool) -> Dictionary:
	var result: Dictionary = PocSave.load_slot(save_dir, use_backup, Callable(self, "make_session"), PocSave.map_id_of(session) if session.combat_mode else "town_01")
	if not bool(result["ok"]):
		var text: String = "読み込めません：" + String(result["reason"])
		if menu != &"":
			ui.set_menu_message(text)
			if menu == &"title":
				ui.show_title(PocSave.slot_info(save_dir), text)
			elif menu == &"pause":
				ui.show_pause(PocSave.slot_info(save_dir), text)
		else:
			ui.show_toast(text, 6.0)
		return result
	var loaded: RefCounted = result["session"]
	replace_session(loaded)
	var wanted: int = int((result["extras"] as Dictionary)["resolution_index"])
	if wanted != resolution_index:
		set_resolution(wanted)
	_menu_prev_paused = false
	if menu != &"":
		close_menu()
	ui.show_toast("読み込みました（ゲーム時間 %s）" % game_time_text())
	return result

func snapshot() -> Dictionary:
	return {
		"viewing": is_viewing(),
		"resolution": [current_resolution().x, current_resolution().y],
		"camera_size": camera.size,
		"session": session.snapshot(),
		"actor": actor.snapshot(),
	}
