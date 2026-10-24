extends SceneTree
## Focus-safe check of the configured normal entry; never reads or writes a save.
const OUT: String = "res://evidence/poc3/source/self/"
var checks: Array[Dictionary] = []
var main: Node
var gpu: bool = false

func _init() -> void:
	root.unfocusable = true
	call_deferred("run")

func check(label: String, passed: bool, detail: String = "") -> void:
	checks.append({"name": label, "status": "PASS" if passed else "FAIL", "detail": detail})
	print(checks.back())

func frames(count: int = 3) -> void:
	for index: int in count:
		await process_frame
	if gpu:
		await RenderingServer.frame_post_draw

func key(code: int, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	root.push_input(event, true)

func capture(label: String) -> void:
	if not gpu:
		return
	await frames()
	var image: Image = root.get_texture().get_image()
	check(label + "_capture", image.save_png(OUT + label + ".png") == OK)

func run() -> void:
	gpu = DisplayServer.get_name() != "headless"
	var configured: String = ProjectSettings.get_setting("application/run/main_scene", "")
	check("configured_latest_entry", configured == "res://scenes/poc2.tscn", configured)
	var error: Error = change_scene_to_file(configured)
	check("configured_scene_loads", error == OK, str(error))
	await frames()
	main = current_scene
	if main != null:
		main.auto_process = false
		check("normal_title_is_paused", main.menu == "title" and main.session.paused and main.ui.menu.visible)
		check("latest_world_224", main.session.state.width == 224 and main.session.state.height == 224)
		check("save_namespace_preserved", main.save_dir == "user://poc2_saves", main.save_dir)
		check("integer_nearest_640", root.content_scale_size == Vector2i(640,360) and root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER and main.render_view.size == Vector2i(640,360) and main.view_rect.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
		await capture("title")
		if gpu:
			# Activate the normal New button with an engine event; no OS input or focus changes.
			var button: Button = main.ui.menu.get_child(0).get_child(1)
			var event: InputEventMouseButton = InputEventMouseButton.new()
			event.position = button.get_global_rect().get_center()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = true
			root.push_input(event, true)
			await frames(1)
			event = event.duplicate()
			event.pressed = false
			root.push_input(event, true)
			await frames()
			check("engine_new_button_starts", main.menu == "" and not main.session.paused)
			await capture("play")
			var elapsed: float = main.session.clock.elapsed
			key(KEY_M, true)
			key(KEY_M, false)
			await frames()
			main.tick(0.25)
			check("engine_map_pauses", main.ui.map.expanded and main.session.paused and main.session.clock.elapsed == elapsed)
			await capture("map")
	var failures: int = 0
	for result: Dictionary in checks:
		if result.status == "FAIL":
			failures += 1
	var mode: String = "gpu" if gpu else "headless"
	var output: Dictionary = {"mode": mode, "checks": checks, "failures": failures, "user_data": OS.get_user_data_dir(), "saves_accessed": false, "not_run": ["physical_input", "lab_runtime", "broad_gameplay_regression"]}
	var file: FileAccess = FileAccess.open(OUT + mode + "_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  "))
	file.close()
	if main != null:
		main.session.close()
	quit(1 if failures > 0 else 0)
