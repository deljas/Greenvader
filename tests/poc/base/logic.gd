extends SceneTree
## POC-01 logic checks (headless OK). Run:
## godot --headless --path <repo> --script res://tests/poc/base/logic.gd
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocInput: GDScript = preload("res://scripts/poc/poc_input.gd")

var failures: int = 0
var passes: int = 0

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
		print("PASS ", name, " ", detail)
	else:
		failures += 1
		print("FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	_coords()
	_session()
	await _main_checks()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)

func _coords() -> void:
	var worst: float = 0.0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in 1000:
		var logic: Vector2 = Vector2(rng.randf_range(0, 192), rng.randf_range(0, 160))
		var back: Vector2 = Coords.ground_to_logic(Coords.logic_to_ground(logic))
		worst = maxf(worst, back.distance_to(logic))
		var ground: Vector2 = Vector2(rng.randf_range(-9, 9), rng.randf_range(-8, 8))
		worst = maxf(worst, Coords.logic_to_ground(Coords.ground_to_logic(ground)).distance_to(ground) / Config.M_PER_LOGIC_PX)
	check("coords.roundtrip", worst < 1e-3, "worst=" + str(worst) + " px")
	check("coords.scale", is_equal_approx(Config.M_PER_LOGIC_PX * Config.TILE_PX, Config.CELL_M) and is_equal_approx(Config.m_to_px(0.4), 4.0), "4px = 0.4m")
	check("coords.cell", Coords.logic_to_cell(Vector2(3.99, 4.0)) == Vector2i(0, 1) and Coords.ground_to_cell(Coords.cell_center_ground(Vector2i(7, 9))) == Vector2i(7, 9) and Coords.cell_center_logic(Vector2i(2, 3)) == Vector2(10, 14))
	check("coords.origin", Coords.logic_to_ground(Vector2(96, 80)).is_equal_approx(Vector2(0, 0)), "world centre")
	var up: Vector2 = Coords.screen_dir_to_ground(Vector2(0, -1))
	var right: Vector2 = Coords.screen_dir_to_ground(Vector2(1, 0))
	var down: Vector2 = Coords.screen_dir_to_ground(Vector2(0, 1))
	check("coords.screen_dirs", up.is_equal_approx(Vector2(-1, -1).normalized()) and right.is_equal_approx(Vector2(1, -1).normalized()) and down.is_equal_approx(Vector2(1, 1).normalized()), "up=%s right=%s down=%s" % [up, right, down])
	var diag: Vector2 = Coords.screen_dir_to_ground(Vector2(1, 1))
	check("coords.diagonal_unit", is_equal_approx(diag.length(), 1.0) and is_equal_approx(Coords.screen_dir_to_ground(Vector2(5, 0)).length(), 1.0), "len=%f" % diag.length())
	check("coords.ground_to_screen", Coords.ground_dir_to_screen(right).is_equal_approx(Vector2(1, 0)))

func _session() -> void:
	var a: RefCounted = Session.new()
	var b: RefCounted = Session.new()
	var start: Vector2 = a.position
	a.walk(Vector2(1, 0), 0.2)
	b.walk(Vector2(1, 1), 0.2)
	var d_axis: float = a.position.distance_to(start)
	var d_diag: float = b.position.distance_to(start)
	check("session.diagonal_speed", absf(d_axis - d_diag) < 1e-3 and absf(d_axis - Config.walk_speed_px() * 0.2) < 1e-3, "axis=%f diag=%f expected=%f" % [d_axis, d_diag, Config.walk_speed_px() * 0.2])
	a.walk(Vector2(0, -1), 0.2)
	check("session.up_moves_north", a.position.y < start.y + 0.0 or a.position.x < start.x + d_axis, "screen up goes toward ground(-1,-1)")
	# wall block (10..13, 8..11): its right edge is x=14 cells = 56 px. Walk ground -X into it.
	var c: RefCounted = Session.new()
	c.position = Coords.cell_center_logic(Vector2i(17, 9))
	var screen_west: Vector2 = Coords.ground_dir_to_screen(Vector2(-1, 0))
	for i: int in 200:
		c.walk(screen_west, 0.05)
	var expected_x: float = 14.0 * Config.TILE_PX + Config.player_half_px().x
	check("session.wall_stop", absf(c.position.x - expected_x) < 0.01 and Walker.is_clear(c.state, Config.TILE_PX, c.position, Config.player_half_px()), "x=%f expected=%f" % [c.position.x, expected_x])
	var edge: RefCounted = Session.new()
	for i: int in 800:
		edge.walk(Coords.ground_dir_to_screen(Vector2(-1, -1).normalized()), 0.05)
	check("session.border_blocks", Walker.is_clear(edge.state, Config.TILE_PX, edge.position, Config.player_half_px()) and edge.position.x >= 4.0 + 2.8 - 0.01 and edge.position.y >= 4.0 + 2.8 - 0.01, "pos=%s" % edge.position)
	# pause
	var p: RefCounted = Session.new()
	p.paused = true
	var before: Vector2 = p.position
	p.advance_game(5.0)
	p.advance(1.0)
	var moved: Vector2 = p.walk(Vector2(1, 0), 1.0)
	check("session.pause", p.clock.elapsed == 0.0 and p.position == before and moved == Vector2.ZERO and p.clock.paused, "elapsed=%f" % p.clock.elapsed)
	p.paused = false
	p.advance_game(1.0)
	check("session.resume", is_equal_approx(p.clock.elapsed, 1.0), "elapsed=%f" % p.clock.elapsed)
	# fast forward independence
	var big: RefCounted = Session.new()
	var small: RefCounted = Session.new()
	big.advance_game(60.0)
	for i: int in 240:
		small.advance_game(0.25)
	check("session.fast_forward_split", absf(big.clock.elapsed - small.clock.elapsed) < 1e-6 and big.clock.growth_ticks == small.clock.growth_ticks and big.clock.spread_ticks == small.clock.spread_ticks and big.clock.growth_ticks == 120 and big.clock.spread_ticks == 60, "elapsed=%f/%f growth=%d/%d spread=%d/%d" % [big.clock.elapsed, small.clock.elapsed, big.clock.growth_ticks, small.clock.growth_ticks, big.clock.spread_ticks, small.clock.spread_ticks])
	var m: RefCounted = Session.new()
	m.multiplier = 16.0
	m.advance(10.0)
	check("session.real_delta_cap_and_multiplier", is_equal_approx(m.clock.elapsed, 0.25 * 16.0), "elapsed=%f" % m.clock.elapsed)
	var snap: Dictionary = a.to_dict()
	check("session.snapshot", snap.has("clock") and snap["version"] == 1 and JSON.stringify(snap).length() > 10)
	for s: RefCounted in [a, b, c, edge, p, big, small, m]:
		s.close()

func _frames(n: int) -> void:
	for i: int in n:
		await process_frame

func _main_checks() -> void:
	PocInput.register()
	check("input.actions", InputMap.has_action(&"poc_up") and InputMap.has_action(&"poc_primary") and InputMap.has_action(&"poc_pause") and InputMap.has_action(&"poc_toggle_resolution") and InputMap.has_action(&"ui_accept"))
	var scene: PackedScene = load("res://scenes/poc.tscn")
	var main: Node = scene.instantiate()
	root.add_child(main)
	await _frames(2)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	var res0: Vector2i = main.current_resolution()
	check("main.default_resolution", res0 == Vector2i(640, 360) and main.render_view.size == res0 and root.content_scale_size == res0)
	# keyboard through InputMap (in-engine injection)
	var w: InputEventKey = InputEventKey.new()
	w.physical_keycode = KEY_W
	w.pressed = true
	Input.parse_input_event(w)
	var d: InputEventKey = InputEventKey.new()
	d.physical_keycode = KEY_D
	d.pressed = true
	Input.parse_input_event(d)
	await _frames(1)
	var v: Vector2 = PocInput.move_vector()
	check("input.wasd_diagonal", is_equal_approx(v.length(), 1.0) and v.x > 0.5 and v.y < -0.5, "vector=%s" % v)
	w.pressed = false
	d.pressed = false
	Input.parse_input_event(w)
	Input.parse_input_event(d)
	await _frames(1)
	check("input.release", PocInput.move_vector() == Vector2.ZERO)
	# state before switching
	main.session.position = Coords.cell_center_logic(Vector2i(24, 20)) + Vector2(1.3, 0.7)
	main.session.set_aim(Vector2(120.0, 90.0))
	main.tick(0.0, Vector2.ZERO)
	var pos0: Vector2 = main.session.position
	var aim0: Vector2 = main.session.aim
	var size0: float = main.camera.size
	var center0: Dictionary = main.pick_ground(Vector2(320, 180))
	var expected: Vector2 = Vector2(main.player_ground3().x, main.player_ground3().z) + Vector2(-1, -1).normalized() * (Config.CAMERA_TARGET_HEIGHT_M / tan(deg_to_rad(Config.ELEVATION_DEG)))
	check("pick.center_640", center0["ok"] and (center0["ground"] as Vector2).distance_to(expected) < 0.08, "hit=%s expected=%s" % [center0.get("ground"), expected])
	var back: Vector2 = main.camera.unproject_position(Vector3(center0["ground"].x, 0, center0["ground"].y))
	check("pick.unproject_roundtrip", back.distance_to(Vector2(320, 180)) < 0.01, "back=%s" % back)
	var small_window: Vector2i = Vector2i(800, 450)
	var denied: bool = main.set_resolution(1, small_window)
	check("res.unfit_denied", not denied and main.current_resolution() == res0 and main.notice.text.length() > 0 and main.session.position == pos0, main.notice.text)
	main.enforce_window(small_window)
	check("res.buttons_disabled_when_small", main.resolution_buttons[1].disabled and not main.resolution_buttons[0].disabled)
	var ok: bool = main.set_resolution(1, Vector2i(1920, 1080))
	main.tick(0.0, Vector2.ZERO)
	check("res.switch_960", ok and main.render_view.size == Vector2i(960, 540) and root.content_scale_size == Vector2i(960, 540))
	check("res.keeps_state", main.session.position == pos0 and main.session.aim == aim0 and main.camera.size == size0 and main.snapshot()["session"]["aim_logic"][0] == aim0.x, "camera.size=%f" % main.camera.size)
	var center1: Dictionary = main.pick_ground(Vector2(480, 270))
	check("pick.center_960_same_world_point", center1["ok"] and (center1["ground"] as Vector2).distance_to(center0["ground"]) < 0.1, "640=%s 960=%s" % [center0["ground"], center1["ground"]])
	var marker_before: Vector3 = main.marker.position
	main.set_resolution(0, Vector2i(1920, 1080))
	check("res.aim_marker_unmoved", main.marker.position == marker_before and main.marker.visible)
	check("res.scale_factors", Config.integer_scale(Vector2i(640, 360), Vector2i(1920, 1080)) == 3 and Config.integer_scale(Vector2i(960, 540), Vector2i(1920, 1080)) == 2 and Config.integer_scale(Vector2i(640, 360), Vector2i(1366, 768)) == 2)
	# rejection: margin and UI
	check("pick.reject_margin", not main.pick_ground(Vector2(-3, 100))["ok"] and not main.pick_ground(Vector2(640, 100))["ok"] and not main.pick_ground(Vector2(100, 361))["ok"], main.pick_ground(Vector2(-3, 100))["reason"])
	var ui_point: Vector2 = main.pause_button.get_global_rect().get_center()
	var ui_result: Dictionary = main.pick_ground(ui_point)
	check("pick.reject_ui", not ui_result["ok"] and ui_result["reason"] == "ui", "at %s" % ui_point)
	var aim_before: Vector2 = main.session.aim
	check("pick.place_rejected_keeps_aim", not main.place_aim_at(ui_point) and main.session.aim == aim_before)
	check("pick.place_ok", main.place_aim_at(Vector2(300, 220)) and main.session.aim != aim_before)
	# injected click through the viewport (engine-internal)
	var before_click: Vector2 = main.session.aim
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(200, 150)
	click.global_position = click.position
	Input.parse_input_event(click)
	await _frames(2)
	var expected_click: Dictionary = main.pick_ground(Vector2(200, 150))
	check("input.click_places_aim", main.session.aim != before_click and (main.session.aim as Vector2).distance_to(expected_click["logic"]) < 0.01, "aim=%s expected=%s" % [main.session.aim, expected_click.get("logic")])
	click.pressed = false
	Input.parse_input_event(click)
	# pause through the Esc action
	var esc: InputEventKey = InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(2)
	check("input.esc_pauses_single_clock", main.session.paused and main.session.clock.paused)
	var t0: float = main.session.clock.elapsed
	var p0: Vector2 = main.session.position
	for i: int in 20:
		main.tick(0.1, Vector2(1, 0))
	check("main.paused_no_progress", main.session.clock.elapsed == t0 and main.session.position == p0)
	esc.pressed = false
	Input.parse_input_event(esc)
	main.toggle_pause()
	for i: int in 10:
		main.tick(0.1, Vector2(1, 0))
	check("main.resumes", main.session.clock.elapsed > t0 and main.session.position != p0 and main.walking)
	var snap: Dictionary = main.snapshot()
	check("actor.synced", snap["actor"]["matching_texture"] and snap["actor"]["matching_feet"] and snap["actor"]["matching_flip"] and snap["actor"]["shaded"], str(snap["actor"]))
	main.set_resolution(1, Vector2i(1920, 1080))
	main.tick(0.0, Vector2.ZERO)
	var s2: Dictionary = main.snapshot()["actor"]
	var s1_height: float = snap["actor"]["height_m"]
	check("actor.height_same_both_res", absf(s2["height_m"] - s1_height) < 1e-6 and s2["texels"] == [24, 36] and snap["actor"]["texels"] == [16, 24], "640=%f 960=%f pixel=%f" % [s1_height, s2["height_m"], s2["pixel_size"]])
	var feet: Vector2 = s2["foot_screen"]
	check("actor.feet_on_pixel_grid", absf(feet.x - roundf(feet.x)) < 0.01 and absf(feet.y - roundf(feet.y)) < 0.01, "foot_screen=%s" % feet)
	main.queue_free()
	await _frames(2)
