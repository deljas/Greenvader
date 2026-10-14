extends SceneTree
## Independent regression observations for tasks/P0_ART.md.
## Run only after the parent grants execution ownership and freezes the sources.
## Expectations come from docs/01_GAME_DESIGN.md and docs/02_TECH_AND_ART.md.
## This is not a native UI or raster-art acceptance test.

var game: Node
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func expect(ok: bool, description: String, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print("INDEPENDENT_%s %s %s" % ["PASS" if ok else "FAIL", description, detail])

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		expect(false, "main scene loads")
		quit(1)
		return
	game = scene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	expect(game.get("player") != null and game.get("camera") != null and game.get("weather") != null,
		"real main scene creates player camera weather")
	if game.get("player") == null or game.get("weather") == null:
		quit(1)
		return
	_check_bindings()
	_check_display_configuration()
	_check_movement()
	await _check_props()
	await _check_pause()
	paused = false
	_release_movement()
	game.queue_free()
	print("INDEPENDENT_SUMMARY checks=%d failures=%d native_ui=NOT_RUN raster_art=NOT_RUN" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check_bindings() -> void:
	var expected_keys: Dictionary = {
		"move_left": KEY_A, "move_right": KEY_D, "move_up": KEY_W,
		"move_down": KEY_S, "pause": KEY_ESCAPE, "interact": KEY_E
	}
	for action: String in expected_keys:
		var found: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				var key: InputEventKey = event as InputEventKey
				found = found or key.physical_keycode == expected_keys[action] or key.keycode == expected_keys[action]
		expect(found, "InputMap key " + action)
	var expected_mouse: Dictionary = {"seed_preview": MOUSE_BUTTON_LEFT, "water_preview": MOUSE_BUTTON_RIGHT}
	for action: String in expected_mouse:
		var found: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventMouseButton:
				found = found or (event as InputEventMouseButton).button_index == expected_mouse[action]
		expect(found, "InputMap mouse " + action)

func _check_display_configuration() -> void:
	expect(int(ProjectSettings.get_setting("display/window/size/viewport_width")) == 640
		and int(ProjectSettings.get_setting("display/window/size/viewport_height")) == 360,
		"internal dimensions 640x360")
	expect(ProjectSettings.get_setting("display/window/stretch/mode") == "viewport"
		and ProjectSettings.get_setting("display/window/stretch/aspect") == "keep"
		and ProjectSettings.get_setting("display/window/stretch/scale_mode") == "integer",
		"viewport integer scaling configured (actual raster NOT_RUN)")
	expect(root.min_size.x >= 640 and root.min_size.y >= 360, "minimum window forbids downscaling")
	var player: Node2D = game.get("player") as Node2D
	var visual: Sprite2D = player.get("visual") as Sprite2D
	expect(visual != null and visual.texture != null and visual.texture.get_width() == 16
		and visual.texture.get_height() == 16, "flower source remains 16x16")
	expect(player.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "player selects Nearest")

func _release_movement() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)

func _check_movement() -> void:
	var player: Node2D = game.get("player") as Node2D
	var camera: Camera2D = game.get("camera") as Camera2D
	var original: Vector2 = player.get("simulation_position")
	var original_physics: bool = player.is_physics_processing()
	player.set_physics_process(false)
	# An interior origin avoids boundary clipping. Same duration for all 8 directions.
	# Compare observed lengths; do not derive an expected distance from SPEED or normalization code.
	var directions: Array[Array] = [
		["move_right"], ["move_left"], ["move_up"], ["move_down"],
		["move_right", "move_up"], ["move_right", "move_down"],
		["move_left", "move_up"], ["move_left", "move_down"]
	]
	var distances: Array[float] = []
	var grid_ok: bool = true
	var camera_ok: bool = true
	var continuous_observed: bool = false
	for actions: Array in directions:
		_release_movement()
		player.set("simulation_position", Vector2(480.25, 368.25))
		var start: Vector2 = player.get("simulation_position")
		for action: String in actions:
			Input.action_press(action)
		for step: int in 60:
			player.call("_physics_process", 1.0 / 60.0)
			var simulation: Vector2 = player.get("simulation_position")
			continuous_observed = continuous_observed or absf(simulation.x - roundf(simulation.x)) > 0.01
			grid_ok = grid_ok and is_equal_approx(player.position.x, roundf(player.position.x))
			grid_ok = grid_ok and is_equal_approx(player.position.y, roundf(player.position.y))
			camera_ok = camera_ok and camera.position.is_equal_approx(player.position)
		var finish: Vector2 = player.get("simulation_position")
		distances.append(start.distance_to(finish))
	var equal_distances: bool = distances[0] > 0.0
	for distance: float in distances:
		equal_distances = equal_distances and absf(distance - distances[0]) < 0.02
	expect(equal_distances, "eight directions travel equal distance over 1 second", str(distances))
	expect(grid_ok and camera_ok, "presentation camera share integer pixel grid through movement")
	expect(continuous_observed, "simulation retains fractional coordinates")
	_release_movement()
	player.set("simulation_position", original)
	player.call("_physics_process", 0.0)
	player.set_physics_process(original_physics)

func _find_button(node: Node, prefix: String) -> Button:
	if node is Button and (node as Button).text.begins_with(prefix):
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find_button(child, prefix)
		if found != null:
			return found
	return null

func _check_props() -> void:
	var player: Node2D = game.get("player") as Node2D
	var actors: Node2D = game.get("actors") as Node2D
	var props: Array = game.get("scenery")
	expect(actors != null and actors.y_sort_enabled and player.get_parent() == actors,
		"player and scenery use one depth-sorted parent (render order NOT_RUN)")
	if props.is_empty():
		expect(false, "scenery exists")
		return
	var prop: Node2D
	for candidate: Node2D in props:
		if bool(candidate.get("fades_for_player")):
			prop = candidate
			break
	expect(prop != null, "occluding scenery available")
	if prop == null:
		return
	var sprite: Sprite2D = prop.get("sprite") as Sprite2D
	var original: Vector2 = player.get("simulation_position")
	var original_physics: bool = player.is_physics_processing()
	player.set_physics_process(false)
	# Probe visible overlap, front, and lateral separation. No production rectangle formula copied.
	player.set("simulation_position", prop.global_position + Vector2(0, -20))
	player.call("_physics_process", 0.0)
	await process_frame
	await process_frame
	expect(sprite.modulate.a > 0.0 and sprite.modulate.a < 1.0,
		"scenery becomes translucent behind overlap", str(sprite.modulate.a))
	var faded_count: int = 0
	for candidate: Node2D in props:
		if (candidate.get("sprite") as Sprite2D).modulate.a < 1.0:
			faded_count += 1
	expect(faded_count > 0 and faded_count < props.size(), "translucency stays local", str(faded_count))
	player.set("simulation_position", prop.global_position + Vector2(0, 12))
	player.call("_physics_process", 0.0)
	await process_frame
	await process_frame
	expect(is_equal_approx(sprite.modulate.a, 1.0), "scenery opaque when player is in front")
	player.set("simulation_position", prop.global_position + Vector2(100, -20))
	player.call("_physics_process", 0.0)
	await process_frame
	await process_frame
	expect(is_equal_approx(sprite.modulate.a, 1.0), "scenery opaque when lateral overlap ends")
	player.set("simulation_position", original)
	player.call("_physics_process", 0.0)
	player.set_physics_process(original_physics)
	var seed: Image = PixelArt.seed().get_image()
	expect(seed.save_png("res://evidence/p1/p1-05/independent/reg/self/seed-source.png") == OK,
		"runtime seed raster saved for visual check (outline acceptance is manual)")

func _send_escape() -> void:
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_ESCAPE
	key.keycode = KEY_ESCAPE
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	var release: InputEventKey = InputEventKey.new()
	release.physical_keycode = KEY_ESCAPE
	release.keycode = KEY_ESCAPE
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame

func _pause_snapshot() -> Dictionary:
	var weather: Node = game.get("weather")
	var player: Node2D = game.get("player") as Node2D
	var shots: Array = game.get("preview_projectiles")
	var projectile_states: Array[Dictionary] = []
	for shot: Dictionary in shots:
		projectile_states.append({"position": shot["position"], "age": shot["age"],
			"display": (shot["sprite"] as Sprite2D).position})
	return {"condition": game.get("condition"), "weather": weather.get("condition"),
		"elapsed": weather.get("elapsed"), "player_sim": player.get("simulation_position"),
		"player_display": player.position, "shots": projectile_states}

func _check_pause() -> void:
	var rain: Button = _find_button(game, "雨")
	expect(rain != null, "rain comparison button exists")
	if rain == null:
		return
	# Exercise the production input callback to create a real preview projectile.
	var shot_event: InputEventAction = InputEventAction.new()
	shot_event.action = "seed_preview"
	shot_event.pressed = true
	game.call("_unhandled_input", shot_event)
	await create_timer(0.10, true).timeout
	var shots: Array = game.get("preview_projectiles")
	expect(not shots.is_empty(), "production input callback creates projectile before pause")
	await _send_escape()
	expect(paused, "Esc event through Input pipeline enters pause")
	if not paused:
		return
	var before: Dictionary = _pause_snapshot()
	rain.pressed.emit()
	Input.action_press("move_right")
	await create_timer(0.20, true).timeout
	_release_movement()
	var after: Dictionary = _pause_snapshot()
	expect(before["condition"] == after["condition"] and before["weather"] == after["weather"],
		"S02 rain button callback cannot change paused weather", "%s -> %s" % [before, after])
	expect(before["elapsed"] == after["elapsed"], "weather elapsed is frozen during pause")
	expect(before["player_sim"] == after["player_sim"] and before["player_display"] == after["player_display"],
		"movement input cannot advance paused player")
	expect(before["shots"] == after["shots"], "projectile position age count freeze during pause")
	await _send_escape()
	expect(not paused, "Esc event resumes paused scene")
	if paused:
		paused = false
		return
	rain.pressed.emit()
	expect(game.get("condition") == "rain" and (game.get("weather") as Node).get("condition") == "rain",
		"rain button callback works after resume")
	var resume_elapsed: float = float((game.get("weather") as Node).get("elapsed"))
	await create_timer(0.05, true).timeout
	var next_elapsed: float = float((game.get("weather") as Node).get("elapsed"))
	expect(next_elapsed > resume_elapsed, "weather clock resumes")
	# No expectation of an exact frame duration; catch adding the paused interval at resume.
	expect(next_elapsed - float(before["elapsed"]) < 0.20,
		"resume does not bulk-advance the 0.20-second pause", str(next_elapsed - float(before["elapsed"])))
