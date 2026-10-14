extends Node
## P0 composition only. Resource/territory simulation belongs to later stages.

var world: Node2D
var player: FlowerPlayer
var camera: Camera2D
var modulation: CanvasModulate
var weather: WeatherView
var condition_label: Label
var pause_panel: PanelContainer
var condition: String = "sunny"
var preview_projectiles: Array[Dictionary] = []
var projectile_view: Node2D
var capture_path: String = ""
var auto_quit: bool = false
var frames: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().min_size = Vector2i(640, 360)
	configure_input()
	world = Node2D.new()
	world.name = "WorldView"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	world.add_child(DemoTerrain.new())
	for index: int in 48:
		var location: Vector2 = Vector2(330 + (index * 61) % 260, 290 + (index * 43) % 190)
		add_sample(PixelArt.mature() if index % 3 == 0 else PixelArt.sprout(), location)
	add_sample(PixelArt.boar(), Vector2(555, 350))
	add_sample(PixelArt.boar(), Vector2(570, 430))
	add_sample(PixelArt.seed(), Vector2(510, 344))
	add_sample(PixelArt.water(), Vector2(530, 375))
	add_sample(PixelArt.seed(), Vector2(415, 355))
	player = FlowerPlayer.new()
	player.name = "Player"
	world.add_child(player)
	camera = Camera2D.new()
	camera.position = player.position
	camera.position_smoothing_enabled = false
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = DemoTerrain.SIZE.x * DemoTerrain.TILE
	camera.limit_bottom = DemoTerrain.SIZE.y * DemoTerrain.TILE
	world.add_child(camera)
	player.presentation_updated.connect(func(location: Vector2) -> void: camera.position = location)
	modulation = CanvasModulate.new()
	world.add_child(modulation)
	projectile_view = Node2D.new()
	world.add_child(projectile_view)
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

func bind_key(action: StringName, code: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = code
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
	sprite.position = location.round()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world.add_child(sprite)

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
	top.size = Vector2(624, 32)
	top.theme = theme
	canvas.add_child(top)
	var row: HBoxContainer = HBoxContainer.new()
	top.add_child(row)
	var title: Label = Label.new()
	title.text = "  グリーンベーダー  |  画面試作"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	condition_label = Label.new()
	row.add_child(condition_label)
	for mode: String in ["sunny", "rain", "night"]:
		var button: Button = Button.new()
		button.text = {"sunny": "晴れ [1]", "rain": "雨 [2]", "night": "夜 [3]"}[mode]
		button.pressed.connect(set_condition.bind(mode))
		row.add_child(button)
	var footer: PanelContainer = PanelContainer.new()
	footer.position = Vector2(8, 314)
	footer.size = Vector2(624, 38)
	footer.theme = theme
	canvas.add_child(footer)
	var instructions: Label = Label.new()
	instructions.text = "  WASD 移動  /  マウス 照準  /  Esc ポーズ\n  左クリック 種の仮表示  /  右クリック 水の仮表示  /  成長・戦闘は後続段階"
	footer.add_child(instructions)
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
	if event.is_action_pressed("seed_preview"):
		spawn_preview(false)
	elif event.is_action_pressed("water_preview"):
		spawn_preview(true)

func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	pause_panel.visible = get_tree().paused

func set_condition(mode: String) -> void:
	condition = mode if mode in ["sunny", "rain", "night"] else "sunny"
	weather.condition = condition
	modulation.color = {"sunny": Color.WHITE, "rain": Color(0.72, 0.83, 0.87), "night": Color(0.44, 0.52, 0.70)}[condition]
	player.light.enabled = condition == "night"
	player.glow.visible = condition == "night"
	condition_label.text = {"sunny": "晴れの昼  ", "rain": "雨の昼  ", "night": "晴れの夜  "}[condition]

func spawn_preview(water_shot: bool) -> void:
	if preview_projectiles.size() >= 64:
		return
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = PixelArt.water() if water_shot else PixelArt.seed()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	projectile_view.add_child(sprite)
	preview_projectiles.append({"position": player.simulation_position, "direction": player.aim_direction, "age": 0.0, "sprite": sprite})

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	for index: int in range(preview_projectiles.size() - 1, -1, -1):
		var shot: Dictionary = preview_projectiles[index]
		shot["age"] += delta
		shot["position"] += shot["direction"] * 160.0 * delta
		var sprite: Sprite2D = shot["sprite"]
		sprite.position = Vector2(shot["position"]).round()
		if shot["age"] > 1.8:
			sprite.queue_free()
			preview_projectiles.remove_at(index)

func _process(_delta: float) -> void:
	frames += 1
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
