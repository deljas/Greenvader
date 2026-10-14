extends SceneTree

var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	print("%s %s" % ["PASS" if value else "FAIL", message])
	if not value:
		failures += 1

func wait_ticks(count: int) -> void:
	for tick: int in count:
		await physics_frame
		await process_frame

func run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node = scene.instantiate()
	root.add_child(main)
	await wait_ticks(2)
	var player: FlowerPlayer = main.player
	check(root.content_scale_size == Vector2i(640, 360), "internal viewport 640x360")
	check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT, "viewport stretch")
	check(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP, "aspect keep")
	check(root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER, "integer stretch")
	check(root.min_size == Vector2i(640, 360), "minimum window 640x360")
	player.simulation_position = Vector2(480, 368)
	Input.action_press("move_right")
	await wait_ticks(60)
	Input.action_release("move_right")
	var cardinal_distance: float = player.simulation_position.distance_to(Vector2(480, 368))
	check(absf(cardinal_distance - 96.0) < 0.05, "one second cardinal motion reaches 96px: %.4f" % cardinal_distance)
	player.simulation_position = Vector2(480, 368)
	Input.action_press("move_right")
	Input.action_press("move_down")
	await wait_ticks(60)
	Input.action_release("move_right")
	Input.action_release("move_down")
	var diagonal_distance: float = player.simulation_position.distance_to(Vector2(480, 368))
	check(absf(diagonal_distance - cardinal_distance) < 0.05, "diagonal distance equals cardinal: %.4f" % diagonal_distance)
	check(player.position == player.position.round(), "sprite uses integer presentation coordinates")
	await wait_ticks(1)
	check(main.camera.position == main.camera.position.round(), "camera uses integer presentation coordinates")
	check(main.camera.position == player.position, "camera and sprite share the same frame and pixel grid")
	main.spawn_preview(false)
	main.toggle_pause()
	var paused_position: Vector2 = player.simulation_position
	var paused_weather: float = main.weather.elapsed
	var paused_age: float = main.preview_projectiles[0]["age"]
	Input.action_press("move_left")
	await wait_ticks(12)
	Input.action_release("move_left")
	check(player.simulation_position == paused_position, "pause freezes player")
	check(main.weather.elapsed == paused_weather, "pause freezes weather animation")
	check(main.preview_projectiles[0]["age"] == paused_age, "pause freezes preview projectile")
	main.toggle_pause()
	main.set_condition("night")
	check(main.player.light.enabled and main.player.glow.visible, "night enables PointLight2D and separate additive glow")
	main.set_condition("rain")
	check(main.weather.condition == "rain" and not main.player.light.enabled, "rain selection")
	print("NOT_RUN real window rendering, outer letterbox pixels, Japanese legibility and human input")
	print("P0_SELF_RESULT failures=%d" % failures)
	quit(failures)
