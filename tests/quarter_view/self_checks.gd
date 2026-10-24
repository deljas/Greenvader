extends SceneTree
## One bounded logic pass and optional real GPU/native captures. No OS input.
const Lab: GDScript = preload("res://scripts/quarter_view_lab/lab.gd")
const Proj: GDScript = preload("res://scripts/quarter_view_lab/projection.gd")
const OUT: String = "res://evidence/quarter-view/self/"
var lab: Node2D
var results: Array[Dictionary] = []
var failures: int = 0
var gpu: bool = false

func _initialize() -> void:
	root.unfocusable = true
	gpu = OS.get_cmdline_user_args().has("--gpu")
	run.call_deferred()

func check(ok: bool, name_: String, detail: String = "") -> void:
	results.append({"name": name_, "status": "PASS" if ok else "FAIL", "detail": detail})
	print("%s %s %s" % ["PASS" if ok else "FAIL", name_, detail])
	if not ok:
		failures += 1

func wait_frames(count: int = 3) -> void:
	for i: int in count:
		await process_frame

func capture(label_: String) -> Image:
	await wait_frames()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT + label_ + "_960.png"))
	check(image.get_size() == Vector2i(960, 540), label_ + "_internal_size")
	return image

func native_capture(label_: String, reference: Image) -> void:
	var path: String = ProjectSettings.globalize_path(OUT + label_ + "_native.png")
	var hwnd: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, 0)
	var helper: String = ProjectSettings.globalize_path("res://tests/independent/p0_verify_printwindow.ps1")
	var pid: int = OS.create_process("powershell", ["-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", helper, "-Hwnd", str(hwnd), "-Out", path])
	var elapsed: int = 0
	while pid > 0 and OS.is_process_running(pid) and elapsed < 600:
		await process_frame
		elapsed += 1
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	var native: Image = Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if native == null or native.get_size() != Vector2i(1920, 1080):
		results.append({"name": "1080_native", "status": "NOT_RUN", "detail": "PrintWindow missing or wrong size"})
		return
	var mismatch: int = 0
	var nonuniform: int = 0
	var colors: Dictionary = {}
	for y: int in 540:
		for x: int in 960:
			var first: Color = native.get_pixel(x * 2, y * 2)
			colors[first] = true
			if first != reference.get_pixel(x, y):
				mismatch += 1
			for dy: int in 2:
				for dx: int in 2:
					if native.get_pixel(x * 2 + dx, y * 2 + dy) != first:
						nonuniform += 1
	check(colors.size() > 8 and mismatch == 0 and nonuniform == 0, "1080_native_exact_2x", "mismatching blocks=%d nonuniform pixels=%d colors=%d" % [mismatch, nonuniform, colors.size()])

func run() -> void:
	lab = load("res://scenes/quarter_view_lab.tscn").instantiate()
	root.add_child(lab)
	lab.auto_input = false
	lab.set_physics_process(false)
	await wait_frames()
	check(lab.grid.width == 192 and lab.grid.target_count == 192 * 192 - 36 * 36 - 12 * 6, "grid_preserved_target_footprints")
	check(Proj.project(Vector2(4, 0)) == Vector2(4, 2) and Proj.project(Vector2(0, 4)) == Vector2(-4, 2), "known_4unit_cell_8x4_diamond")
	check(Proj.unproject(Vector2(100, 50)) == Vector2(100, 0), "known_inverse")
	var start: Vector2 = Vector2(600, 560)
	lab.logical_position = start
	lab.move_screen(Vector2.RIGHT, 0.5)
	var right: Vector2 = Proj.project(lab.logical_position) - Proj.project(start)
	lab.logical_position = start
	lab.move_screen(Vector2(1, -1), 0.5)
	var diagonal: Vector2 = Proj.project(lab.logical_position) - Proj.project(start)
	# Walker accumulates float32 substeps at map-scale coordinates (<0.02px here).
	check(right.distance_to(Vector2(50, 0)) < 0.02 and absf(diagonal.length() - 50) < 0.02 and diagonal.x > 0 and diagonal.y < 0, "screen_direction_diagonal_equal_speed", str([right, diagonal]))
	# Four direct wall approaches must stop exactly at footprint + existing feet.
	var approaches: Array[Vector2] = [Vector2(280, 340), Vector2(472, 340), Vector2(376, 248), Vector2(376, 440)]
	var motions: Array[Vector2] = [Vector2(60, 0), Vector2(-60, 0), Vector2(0, 60), Vector2(0, -60)]
	var expected: Array[Vector2] = [Vector2(302, 340), Vector2(450, 340), Vector2(376, 270), Vector2(376, 418)]
	var walls_ok: bool = true
	for i: int in 4:
		var stopped: Vector2 = Walker.move(lab.grid, 4, approaches[i], motions[i], Lab.HALF)
		walls_ok = walls_ok and stopped.distance_to(expected[i]) < 0.001
	check(walls_ok, "four_wall_contacts_match_feet")
	var route: Array[Vector2] = [Vector2(280, 248), Vector2(472, 248), Vector2(472, 440), Vector2(280, 440), Vector2(280, 248)]
	var cursor: Vector2 = route[0]
	var route_ok: bool = true
	for i: int in range(1, route.size()):
		cursor = Walker.move(lab.grid, 4, cursor, route[i] - cursor, Lab.HALF)
		route_ok = route_ok and cursor.distance_to(route[i]) < 0.001
	check(route_ok, "complete_building_circuit")
	var stopped_low: Vector2 = Walker.move(lab.grid, 4, Vector2(460, 330), Vector2(50, 0), Lab.HALF)
	check(stopped_low.distance_to(Vector2(478, 330)) < 0.001, "low_obstacle_contact")
	lab.logical_position = Lab.START
	lab.present()
	var target: Vector2 = Vector2(554, 470)
	var screen: Vector2 = root.get_canvas_transform() * Proj.project(target)
	lab.set_mouse_screen(screen)
	check(lab.marker_logical.distance_to(target) < 0.001 and lab.marker_cell == Vector2i(138, 117), "camera_mouse_inverse_cell", str(lab.marker_logical))
	check(lab.actors.z_index > lab.marker.z_index and lab.marker.z_index == 0, "ground_marker_actor_layers")
	# Engine-internal key event through the actual movement path (no OS keyboard).
	lab.logical_position = start
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_D
	key.keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	lab.auto_input = true
	lab._physics_process(0.25)
	key = InputEventKey.new()
	key.physical_keycode = KEY_D
	key.keycode = KEY_D
	key.pressed = false
	Input.parse_input_event(key)
	lab.auto_input = false
	check((Proj.project(lab.logical_position) - Proj.project(start)).distance_to(Vector2(25, 0)) < 0.02, "engine_key_injection", str(Proj.project(lab.logical_position) - Proj.project(start)))
	var points: Array[Vector2] = [Lab.START, Vector2(288, 256), Vector2(376, 432), Vector2(464, 344)]
	var labels: Array[String] = ["front", "behind_faded", "left_front", "right_front"]
	for i: int in points.size():
		lab.logical_position = points[i]
		lab.present()
		check(Walker.is_clear(lab.grid, 4, points[i], Lab.HALF), labels[i] + "_walkable")
		if i == 1:
			check(lab.occluded and lab.props[0].faded, "behind_fade_trigger")
		if gpu:
			await capture(labels[i])
		if i == 1 and gpu:
			lab.fade_enabled = false
			lab.present()
			await capture("behind_opaque")
			lab.fade_enabled = true
	# Fractional simulation coordinates must never become fractional raster transforms.
	lab.logical_position = Vector2(600.13, 560.27)
	lab.move_screen(Vector2(1, 1), 0.017)
	lab.present()
	check(lab.flower.position == lab.flower.position.round() and lab.camera.position == lab.camera.position.round() and lab.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "fractional_diagonal_camera_pixel_snap")
	if gpu:
		await capture("diagonal_camera")
		lab.logical_position = Lab.START
		lab.present()
		lab.set_mouse_screen(Vector2(600, 340))
		root.size = Vector2i(1920, 1080)
		await wait_frames(6)
		var reference: Image = await capture("overview_1080")
		await native_capture("overview_1080", reference)
	else:
		results.append({"name": "GPU_visual_and_native", "status": "NOT_RUN", "detail": "Logic-only pass; GPU pass is separate"})
	results.append({"name": "physical_OS_input", "status": "NOT_RUN", "detail": "User manual check only; no OS input sent"})
	var file: FileAccess = FileAccess.open(OUT + ("gpu-results.json" if gpu else "logic-results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": results, "failures": failures, "engine": Engine.get_version_info()}, "\t"))
	print("SELF_DONE failures=%d" % failures)
	quit(1 if failures else 0)
