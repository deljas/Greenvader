extends Node
## Composition root. P0 presentation (player, aim, weather, UI) plus the P1-01 region world.

const REGION_PATH: String = "res://data/region_01.tres"
const TUNING_PATH: String = "res://data/sim_tuning.tres"
const PLAY_TUNING_PATH: String = "res://data/play_tuning.tres"
const ENEMY_TUNING_PATH: String = "res://data/enemy_tuning.tres"
## The P0 decorative composition (trees, rocks, ruin sprite, samples) is placed shifted by this many pixels.
## It is scenery only and never defines greening targets.
const LANDSCAPE_OFFSET: Vector2 = Vector2(256, 384)

var world: Node2D
var region_def: RegionDef
var tuning: SimTuning
var play_tuning: PlayTuning
var play: PlayState
var play_driver: PlayDriver
var enemy_tuning: EnemyTuning
var enemies: EnemyField
var enemy_driver: EnemyDriver
var enemy_view: EnemyView
var pickup_view: PickupView
var cultivated_view: CultivatedView
var hud: PlayHud
var grid: WorldState
var region_view: RegionView
var simulation: SimulationDriver
var player: FlowerPlayer
var camera: Camera2D
var modulation: CanvasModulate
var weather: WeatherView
var condition_label: Label
var pause_panel: PanelContainer
var condition: String = "sunny"
## Legacy P0 name kept for the existing P0 checks: it is the live shot list of the real projectile field.
var preview_projectiles: Array[Dictionary] = []
var projectile_view: ProjectileField
var capture_path: String = ""
var auto_quit: bool = false
var frames: int = 0
var actors: Node2D
var ground_shadows: Node2D
var scenery: Array[LandscapeProp] = []
var weather_buttons: Array[Button] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().min_size = Vector2i(640, 360)
	configure_input()
	world = Node2D.new()
	world.name = "WorldView"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	region_def = load(REGION_PATH) as RegionDef
	tuning = load(TUNING_PATH) as SimTuning
	play_tuning = load(PLAY_TUNING_PATH) as PlayTuning
	enemy_tuning = load(ENEMY_TUNING_PATH) as EnemyTuning
	grid = RegionLoader.load_region(region_def)
	if grid == null:
		push_error("Region failed to load: %s" % REGION_PATH)
		return
	region_view = RegionView.new()
	region_view.name = "RegionView"
	region_view.setup(grid, tuning)
	world.add_child(region_view)
	simulation = SimulationDriver.new()
	simulation.name = "Simulation"
	simulation.setup(grid, tuning)
	world.add_child(simulation)
	ground_shadows = Node2D.new()
	world.add_child(ground_shadows)
	var source_positions: Array[Vector2] = []
	for tile: Vector2i in region_def.seed_source_tiles:
		source_positions.append((Vector2(tile) + Vector2(0.5, 0.5)) * region_def.tile_px)
	var plant_defs: Array[PlantDef] = []
	plant_defs.assign(region_def.plants)
	play = PlayState.new(grid, play_tuning, tuning, region_def.tile_px, source_positions, plant_defs)
	# Mature carrots speed up natural spread: the cultivation hands its per-tile multiplier to the spread simulation.
	play.cultivation.boost_sink = simulation.spread.set_speed_scale
	pickup_view = PickupView.new()
	pickup_view.name = "Pickups"
	pickup_view.setup(play)
	world.add_child(pickup_view)
	actors = Node2D.new()
	actors.name = "DepthSortedPresentation"
	actors.y_sort_enabled = true
	world.add_child(actors)
	player = FlowerPlayer.new()
	player.name = "Player"
	var region_px: Vector2 = Vector2(grid.width * region_def.tile_px, grid.height * region_def.tile_px)
	player.world_bounds = Rect2(Vector2(32, 32), region_px - Vector2(64, 64))
	player.simulation_position = Vector2(region_def.start_tile * region_def.tile_px) + Vector2(2, 2)
	player.walk_world = grid
	player.walk_tile_px = region_def.tile_px
	player.walk_half = Vector2(play_tuning.walk_half_width_px, play_tuning.walk_half_height_px)
	actors.add_child(player)
	cultivated_view = CultivatedView.new()
	cultivated_view.name = "CultivatedView"
	cultivated_view.setup(play.cultivation, actors, region_def.tile_px)
	world.add_child(cultivated_view)
	play_driver = PlayDriver.new()
	play_driver.name = "PlayDriver"
	play_driver.setup(play, player)
	world.add_child(play_driver)
	# Enemies (P2-01): nests of the unconquered zones and their boars. Natural spread must not enter a nest's tiles.
	enemies = EnemyField.new(grid, enemy_tuning, region_def.tile_px)
	enemies.setup_nests(region_def.zones)
	simulation.spread.allow_hook = enemies.spread_allows
	enemy_driver = EnemyDriver.new()
	enemy_driver.name = "EnemyDriver"
	enemy_driver.setup(enemies)
	world.add_child(enemy_driver)
	enemy_view = EnemyView.new()
	enemy_view.name = "EnemyView"
	enemy_view.setup(enemies, actors, region_def.tile_px)
	world.add_child(enemy_view)
	for source: SeedSource in play.sources:
		var source_sprite: Sprite2D = Sprite2D.new()
		source_sprite.name = "SeedSource%d" % source.id
		source_sprite.texture = PlayArt.source()
		source_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		source_sprite.centered = false
		source_sprite.offset = Vector2(-5, -9)
		source_sprite.position = source.position.round()
		actors.add_child(source_sprite)
	build_landscape()
	add_sample(PixelArt.boar(), Vector2(563, 351))
	add_sample(PixelArt.boar(), Vector2(586, 439))
	add_sample(PixelArt.seed(), Vector2(509, 351))
	add_sample(PixelArt.water(), Vector2(527, 372))
	camera = Camera2D.new()
	camera.position = player.position
	camera.position_smoothing_enabled = false
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = grid.width * region_def.tile_px
	camera.limit_bottom = grid.height * region_def.tile_px
	world.add_child(camera)
	player.presentation_updated.connect(func(location: Vector2) -> void: camera.position = location)
	modulation = CanvasModulate.new()
	world.add_child(modulation)
	projectile_view = ProjectileField.new()
	projectile_view.name = "Projectiles"
	projectile_view.setup(play_tuning)
	projectile_view.landed.connect(_on_projectile_landed)
	projectile_view.expired.connect(_on_projectile_ended)
	projectile_view.enemy_hit.connect(func(kind: String, _point: Vector2, _info: Dictionary) -> void: _on_projectile_ended(kind, Vector2.ZERO))
	world.add_child(projectile_view)
	preview_projectiles = projectile_view.shots
	var weather_canvas: CanvasLayer = CanvasLayer.new()
	weather_canvas.layer = 5
	weather_canvas.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(weather_canvas)
	weather = WeatherView.new()
	weather_canvas.add_child(weather)
	build_ui()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--condition="):
			condition = argument.trim_prefix("--condition=")
		elif argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		elif argument == "--auto-quit":
			auto_quit = true
		elif argument == "--debug-layout":
			var layout_origin: Vector2i = region_def.start_tile + Vector2i(-8, -28)
			DebugLayout.apply(grid, layout_origin)
			player.simulation_position = Vector2(layout_origin * region_def.tile_px) + Vector2(24, -8)
	set_condition(condition)
	print("P0_READY condition=%s renderer=%s viewport=%s window=%s" % [condition, RenderingServer.get_current_rendering_method(), get_viewport().get_visible_rect().size, get_window().size])

func configure_input() -> void:
	bind_key("move_left", KEY_A)
	bind_key("move_right", KEY_D)
	bind_key("move_up", KEY_W)
	bind_key("move_down", KEY_S)
	bind_key("pause", KEY_ESCAPE)
	bind_key("sunny", KEY_1)
	bind_key("rain", KEY_2)
	bind_key("night", KEY_3)
	bind_key("interact", KEY_E)
	bind_mouse("seed_preview", MOUSE_BUTTON_LEFT)
	bind_mouse("water_preview", MOUSE_BUTTON_RIGHT)
	# Plant selection (P1-05): wheel down / Tab = next kind, wheel up = previous kind.
	add_binding_key("plant_next", KEY_TAB)
	add_binding_mouse("plant_next", MOUSE_BUTTON_WHEEL_DOWN)
	add_binding_mouse("plant_prev", MOUSE_BUTTON_WHEEL_UP)

func bind_key(action: StringName, code: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = code
		InputMap.action_add_event(action, event)

## Adds another event to an action (creating the action when needed); unlike bind_key it never skips an existing action.
func add_binding_key(action: StringName, code: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	InputMap.action_add_event(action, event)

func add_binding_mouse(action: StringName, code: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = code
	InputMap.action_add_event(action, event)

func bind_mouse(action: StringName, code: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = code
		InputMap.action_add_event(action, event)

func add_sample(texture: Texture2D, location: Vector2) -> void:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.position = (location + LANDSCAPE_OFFSET).round()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	actors.add_child(sprite)

func build_landscape() -> void:
	var trees: Array[Texture2D] = [LandscapeArt.tree(0), LandscapeArt.tree(1), LandscapeArt.tree(2)]
	var positions: Array[Vector2] = [Vector2(176, 273), Vector2(214, 294), Vector2(265, 251), Vector2(317, 251), Vector2(372, 265), Vector2(426, 252), Vector2(478, 261), Vector2(532, 244), Vector2(641, 245), Vector2(691, 214), Vector2(758, 236), Vector2(791, 299), Vector2(224, 361), Vector2(190, 409), Vector2(267, 422), Vector2(221, 482), Vector2(285, 497), Vector2(194, 553), Vector2(245, 570), Vector2(305, 578), Vector2(357, 559), Vector2(481, 568), Vector2(532, 544), Vector2(584, 565), Vector2(638, 527), Vector2(691, 565), Vector2(806, 390), Vector2(838, 450)]
	for index: int in positions.size():
		var kind: int = 2 if index % 7 == 5 else index % 2
		add_prop(trees[kind], positions[index], true, 62)
	add_prop(LandscapeArt.ruin(), Vector2(334, 346), true, 92)
	var rocks: Array[Texture2D] = [LandscapeArt.rock(0), LandscapeArt.rock(1)]
	var locations: Array[Vector2] = [Vector2(305, 364), Vector2(331, 380), Vector2(610, 315), Vector2(644, 343), Vector2(259, 466), Vector2(569, 487), Vector2(683, 369), Vector2(742, 447), Vector2(708, 405)]
	for index: int in locations.size():
		add_prop(rocks[index % 2], locations[index], false, 36)
	var fern: Texture2D = LandscapeArt.fern()
	for location: Vector2 in [Vector2(296, 352), Vector2(351, 350), Vector2(241, 416), Vector2(592, 312), Vector2(639, 314), Vector2(669, 357), Vector2(708, 413), Vector2(615, 473), Vector2(512, 511), Vector2(360, 483), Vector2(571, 273)]:
		add_prop(fern, location, false, 22)

func add_prop(texture: Texture2D, base_location: Vector2, fades: bool, shadow_width: int) -> void:
	var location: Vector2 = base_location + LANDSCAPE_OFFSET
	var shadow: Sprite2D = Sprite2D.new()
	shadow.texture = LandscapeArt.shadow(shadow_width)
	shadow.position = location.round() + Vector2(8, 0)
	shadow.modulate.a = 0.72
	ground_shadows.add_child(shadow)
	var prop: LandscapeProp = LandscapeProp.new()
	prop.initialize(texture, location, player, fades)
	actors.add_child(prop)
	scenery.append(prop)

func build_ui() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	var theme: Theme = Theme.new()
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic", "Meiryo"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	theme.default_font = font
	theme.default_font_size = 12
	var top: PanelContainer = PanelContainer.new()
	top.position = Vector2(8, 8)
	top.size = Vector2(624, 24)
	top.theme = theme
	canvas.add_child(top)
	var row: HBoxContainer = HBoxContainer.new()
	top.add_child(row)
	var title: Label = Label.new()
	title.text = "  グリーンベーダー"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	condition_label = Label.new()
	row.add_child(condition_label)
	for mode: String in ["sunny", "rain", "night"]:
		var button: Button = Button.new()
		button.text = {"sunny": "晴れ [1]", "rain": "雨 [2]", "night": "夜 [3]"}[mode]
		button.pressed.connect(set_condition.bind(mode))
		row.add_child(button)
		button.focus_mode = Control.FOCUS_NONE
		weather_buttons.append(button)
	var footer: PanelContainer = PanelContainer.new()
	footer.position = Vector2(8, 333)
	footer.size = Vector2(624, 19)
	footer.theme = theme
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(footer)
	hud = PlayHud.new()
	footer.add_child(hud)
	hud.refresh(play, grid)
	pause_panel = PanelContainer.new()
	pause_panel.position = Vector2(188, 136)
	pause_panel.size = Vector2(264, 84)
	pause_panel.theme = theme
	pause_panel.visible = false
	canvas.add_child(pause_panel)
	var column: VBoxContainer = VBoxContainer.new()
	pause_panel.add_child(column)
	var pause_label: Label = Label.new()
	pause_label.text = "ポーズ中\nEsc で再開"
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(pause_label)
	var resume: Button = Button.new()
	resume.text = "再開"
	resume.focus_mode = Control.FOCUS_NONE
	resume.pressed.connect(toggle_pause)
	column.add_child(resume)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()
	if get_tree().paused:
		return
	for mode: String in ["sunny", "rain", "night"]:
		if event.is_action_pressed(mode):
			set_condition(mode)
	if event.is_action_pressed("plant_next"):
		play.cycle_selection(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("plant_prev"):
		play.cycle_selection(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("seed_preview"):
		fire(false)
	elif event.is_action_pressed("water_preview"):
		fire(true)

func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	pause_panel.visible = get_tree().paused
	for button: Button in weather_buttons:
		button.disabled = get_tree().paused

func set_condition(mode: String) -> void:
	if get_tree().paused:
		return
	condition = mode if mode in ["sunny", "rain", "night"] else "sunny"
	weather.condition = condition
	modulation.color = {"sunny": Color.WHITE, "rain": Color(0.72, 0.83, 0.87), "night": Color(0.44, 0.52, 0.70)}[condition]
	player.light.enabled = condition == "night"
	player.glow.visible = condition == "night"
	condition_label.text = {"sunny": "晴れの昼  ", "rain": "雨の昼  ", "night": "晴れの夜  "}[condition]

## Legacy P0 entry point (the P0 checks call it); fires a real shot.
func spawn_preview(water_shot: bool) -> void:
	fire(water_shot)

## Fires a seed (false) or water (true) shot toward the mouse. Returns false when nothing was fired:
## paused, no seed / not enough water, or the in-flight shot limit is reached. Nothing is spent then.
## `aim_override` replaces the mouse's world point (tests, and later non-mouse aiming).
func fire(water_shot: bool, aim_override: Vector2 = Vector2.INF) -> bool:
	if get_tree().paused or projectile_view.is_full():
		return false
	var plant: PlantDef = null if water_shot else play.selected_def()
	var cultivated: bool = plant != null and plant.is_cultivated()
	if water_shot and not play.can_fire_water():
		return false
	if cultivated and not play.can_fire_plant(plant):
		return false
	if not water_shot and not cultivated and not play.can_fire_seed():
		return false
	var kind: String = ProjectileField.KIND_WATER if water_shot else (String(plant.key) if cultivated else ProjectileField.KIND_SEED)
	var aim_point: Vector2 = player.get_global_mouse_position() if aim_override == Vector2.INF else aim_override
	var target: Vector2 = projectile_view.launch(kind, player.simulation_position, aim_point, player.aim_direction)
	if target == Vector2.INF:
		return false
	if water_shot:
		play.spend_water()
	elif cultivated:
		# The cost is held back now and spent only when the plant is really placed (given back when it does not fit).
		play.reserve_plant(plant)
	else:
		play.spend_seed()
	return true

func _on_projectile_landed(kind: String, point: Vector2) -> void:
	if kind == ProjectileField.KIND_WATER:
		play.land_water(point)
	elif kind == ProjectileField.KIND_SEED:
		play.land_seed(point)
	else:
		play.land_plant(StringName(kind), point)

## A cultivated shot that ended without landing (expired / hit): its held-back cost is released.
func _on_projectile_ended(kind: String, _point: Vector2) -> void:
	if kind != ProjectileField.KIND_WATER and kind != ProjectileField.KIND_SEED:
		play.cancel_plant(StringName(kind))

func _process(_delta: float) -> void:
	frames += 1
	if hud != null:
		hud.refresh(play, grid)
	if frames == 12 and not capture_path.is_empty():
		capture.call_deferred()
	elif frames == 30 and auto_quit and capture_path.is_empty():
		get_tree().quit()

func capture() -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var error: Error = image.save_png(capture_path)
	print("P0_CAPTURE path=%s size=%s result=%s screen_transform=%s" % [capture_path, image.get_size(), error, get_viewport().get_screen_transform()])
	if auto_quit:
		get_tree().quit(error)
