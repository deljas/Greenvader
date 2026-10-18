extends SceneTree
## WTH-02 GPU captures (real renderer, NOT --headless): godot --path <repo> --script res://tests/poc/view/gpu.gd
## No OS-level input / cursor / foregrounding (root.unfocusable); the viewpoint is entered through PocMain's own handler with an
## injected key event. Images are the root viewport (3D picture + panel) -> evidence/weather/02/*.png.
## view_day / view_night x 640 / 960 (night with about half of the town greened), marker_640 (+ x4 crop of the spot).
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/weather/02/"
var main: Node
var s: RefCounted
var failures: int = 0
var passes: int = 0

func check(name: String, ok: bool, detail: String = "") -> void:
	print("PASS " if ok else "FAIL ", name, " ", detail)
	if ok:
		passes += 1
	else:
		failures += 1

func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()

func _frames(n: int) -> void:
	for i: int in n:
		await process_frame
	await RenderingServer.frame_post_draw

func key(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event

func set_time(t: float) -> void:
	s.clock.load_dict({"version": 1, "elapsed": t, "growth_ticks": int(t / s.clock.growth_period), "spread_ticks": int(t / s.clock.spread_period)})
	s.growth.ticks = s.clock.growth_ticks
	s.state.growth_tick = s.clock.growth_ticks
	s.weather.update(t)

func grab() -> Image:
	await _frames(3)
	return root.get_texture().get_image()

func diff_fraction(a: Image, b: Image, rect: Rect2i, threshold: float = 0.06) -> float:
	var count: int = 0
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var ca: Color = a.get_pixel(x, y)
			var cb: Color = b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > threshold * 3.0:
				count += 1
	return float(count) / float(maxi(rect.size.x * rect.size.y, 1))

func save(image: Image, file: String) -> void:
	image.save_png(ProjectSettings.globalize_path(OUT + file + ".png"))

func settle(res_index: int, t: float, weather_type: int) -> void:
	main.set_resolution(res_index, Vector2i(1920, 1080))
	s.set_debug_weather(weather_type)
	set_time(t)
	for i: int in 10:
		main.tick(0.05, Vector2.ZERO)
	await _frames(2)

func green_half() -> void:
	var n: int = 0
	for index: int in s.state.tile_count():
		if s.state.target[index] == 1:
			n += 1
			if n % 2 == 0 and s.state.stage[index] != WorldState.STAGE_MATURE:
				s.state.set_stage(index, WorldState.STAGE_MATURE)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN gpu (headless display server)")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	print("renderer=", RenderingServer.get_video_adapter_name(), " window=", root.size)
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(3)
	s = main.session
	var spot: Vector2 = Coords.cell_center_logic(main.viewpoint.cell)
	# the marker, seen from the safe zone (the player stands 2.4 m away), 640
	s.position = spot + Vector2(0.0, 24.0)
	await settle(0, 100.0, 0)
	var with_marker: Image = await grab()
	save(with_marker, "marker_640")
	var ground: Vector2 = Coords.cell_center_ground(main.viewpoint.cell)
	var px: Vector2 = main.camera.unproject_position(Vector3(ground.x, 0.5, ground.y))
	var crop_origin: Vector2i = Vector2i(clampi(int(px.x) - 40, 0, 560), clampi(int(px.y) - 50, 0, 280))
	var crop: Image = with_marker.get_region(Rect2i(crop_origin, Vector2i(80, 80)))
	crop.resize(320, 320, Image.INTERPOLATE_NEAREST)
	save(crop, "marker_640_zoom")
	main.viewpoint_view.visible = false
	var without_marker: Image = await grab()
	main.viewpoint_view.visible = true
	var marker_diff: float = diff_fraction(with_marker, without_marker, Rect2i(crop_origin, Vector2i(80, 80)))
	check("marker.visible_on_the_ground_day", marker_diff > 0.05, "%.1f%% of the 80x80 window differ" % (marker_diff * 100.0))
	s.position = spot
	var plan: Array = [["view_day_640", 0, 100.0, 0, false], ["view_day_960", 1, 100.0, 0, false], ["view_night_640", 0, 400.0, 0, true], ["view_night_960", 1, 400.0, 0, true]]
	for entry: Array in plan:
		var res_index: int = int(entry[1])
		if bool(entry[4]) and s.state.greened_count * 4 < s.state.target_count:
			green_half()
		await settle(res_index, float(entry[2]), int(entry[3]))
		if not main.is_viewing():
			main._unhandled_input(key(KEY_E))
		await settle(res_index, float(entry[2]), int(entry[3]))
		var image: Image = await grab()
		save(image, String(entry[0]))
		var res: Vector2i = Config.RESOLUTIONS[res_index]
		check(String(entry[0]) + ".viewing_and_image_size_exact", main.is_viewing() and image.get_width() == res.x and image.get_height() == res.y, "%s %s" % [main.is_viewing(), image.get_size()])
		var panel_rect: Rect2i = Rect2i(Vector2i(main.view_panel.position), Vector2i(main.view_panel.size))
		main.view_panel.visible = false
		var no_panel: Image = await grab()
		main.view_panel.visible = true
		var panel_diff: float = diff_fraction(image, no_panel, panel_rect, 0.02)
		check(String(entry[0]) + ".panel_text_drawn", panel_diff > 0.03, "%.1f%% of the panel rect %s" % [panel_diff * 100.0, panel_rect])
		print("INFO ", entry[0], " greened=", s.greening_percent(), "% hour=", snappedf(s.day_hour(), 0.01), " weather=", s.weather_text(), " camera.size=", main.camera.size, " panel=", main.view_panel.label.text.replace("\n", " / "))
		main._unhandled_input(key(KEY_E))
	check("camera_back_after_views", not main.is_viewing() and is_equal_approx(main.camera.size, Config.CAMERA_SIZE_M))
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
