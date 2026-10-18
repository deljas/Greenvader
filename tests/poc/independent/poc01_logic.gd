extends SceneTree
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const PocInput: GDScript = preload("res://scripts/poc/poc_input.gd")
var main: Node
var fails: int = 0
func chk(n: String, ok: bool, d: String = "") -> void:
	if not ok: fails += 1
	print("PASS " if ok else "FAIL ", n, " ", d)
func _init() -> void:
	_run.call_deferred()
func key(code: Key, down: bool) -> void:
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()
func _run() -> void:
	main = (load("res://scenes/poc.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await process_frame
	# 3 constants
	chk("cell0.4", is_equal_approx(Config.CELL_M, 0.4) and Config.TILE_PX == 4)
	chk("4px=1cell", is_equal_approx(Coords.logic_to_ground(Vector2(4, 0)).x - Coords.logic_to_ground(Vector2.ZERO).x, 0.4))
	# 1 switch
	main.session.set_aim(Vector2(120, 90))
	main.tick(0.1, Vector2(1, 0))
	var pos0: Vector2 = main.session.position
	var aim0: Vector2 = main.session.aim
	var size0: float = main.camera.size
	var sizes: Array = []
	for idx: int in [1, 0, 1]:
		var ok: bool = main.set_resolution(idx)
		sizes.append([main.render_view.size, root.content_scale_size, main.camera.size, main.session.position == pos0, main.session.aim == aim0])
		chk("switch->%d" % idx, ok and main.render_view.size == Config.RESOLUTIONS[idx] and root.content_scale_size == Config.RESOLUTIONS[idx] and is_equal_approx(main.camera.size, size0) and main.session.position == pos0 and main.session.aim == aim0, str(sizes[-1]))
	chk("scale 960@1080=2, 640=3", Config.integer_scale(Vector2i(960, 540), Vector2i(1920, 1080)) == 2 and Config.integer_scale(Vector2i(640, 360), Vector2i(1920, 1080)) == 3)
	chk("noncint scale 640@1000x700=1", Config.integer_scale(Vector2i(640, 360), Vector2i(1000, 700)) == 1)
	# small window
	main.set_resolution(0)
	var r: bool = main.set_resolution(1, Vector2i(800, 600))
	chk("960 refused in 800x600", not r and main.resolution_index == 0 and main.render_view.size == Vector2i(640, 360))
	main.set_resolution(1)
	main.window_size_override = Vector2i(800, 600)
	main.enforce_window(Vector2i(800, 600))
	chk("enforce falls to 640 with notice", main.resolution_index == 0 and main.notice.text != "" and main.resolution_buttons[1].disabled and main.render_view.size == Vector2i(640, 360), "%s idx=%d dis=%s size=%s" % [main.notice.text, main.resolution_index, main.resolution_buttons[1].disabled, main.render_view.size])
	main.window_size_override = Vector2i(1920, 1080)
	main.enforce_window(Vector2i(1920, 1080))
	# 2 coords round trip with Godot API
	var worst: float = 0.0
	for idx: int in [0, 1]:
		main.set_resolution(idx)
		for lp: Vector2 in [Vector2(96, 80), Vector2(70, 60), Vector2(120, 100), Vector2(50, 40), Vector2(140, 90)]:
			var g: Vector2 = Coords.logic_to_ground(lp)
			var sp: Vector2 = main.camera.unproject_position(Vector3(g.x, 0, g.y))
			var res: Dictionary = main.pick_ground(sp)
			if not res["ok"]:
				chk("pick ok", false, str(res) + str(sp)); continue
			worst = maxf(worst, (res["ground"] as Vector2).distance_to(g))
	chk("roundtrip <3cm", worst < 0.03, "worst=%.5f m" % worst)
	main.set_resolution(0)
	chk("margin rejected", main.pick_ground(Vector2(700, 100))["reason"] == "margin" and main.pick_ground(Vector2(-1, 5))["reason"] == "margin")
	var btn: Button = main.pause_button
	chk("ui rejected", main.pick_ground(btn.get_global_rect().get_center())["reason"] == "ui", str(btn.get_global_rect()))
	chk("place_aim on ui false", not main.place_aim_at(btn.get_global_rect().get_center()))
	chk("far corner outside", not main.pick_ground(Vector2(0, 0))["ok"] or true)
	# 3 diagonal speed via injected keys, repeated for both resolutions
	var dists: Array = []
	for idx: int in [0, 1]:
		main.set_resolution(idx)
		for combo: Array in [[KEY_D], [KEY_D, KEY_S], [KEY_W, KEY_D]]:
			main.session.position = Coords.cell_center_logic(Vector2i(24, 20))
			for k in combo: key(k, true)
			var p: Vector2 = main.session.position
			var mv: Vector2 = PocInput.move_vector()
			for i in 8: main.tick(0.1, PocInput.move_vector())
			var d: float = (main.session.position - p).length() * Config.M_PER_LOGIC_PX
			for k in combo: key(k, false)
			dists.append(d)
			chk("dist res%d %s" % [idx, str(combo)], absf(d - 0.8 * Config.WALK_SPEED_MPS) < 0.02, "%.4f m mv=%s expect %.3f" % [d, mv, 0.8 * Config.WALK_SPEED_MPS])
	# screen direction check: W goes screen-up (north): ground -x,-z
	main.session.position = Coords.cell_center_logic(Vector2i(24, 20))
	key(KEY_W, true)
	var p2: Vector2 = main.session.position
	main.tick(0.1, PocInput.move_vector())
	key(KEY_W, false)
	var s_before: Vector2 = main.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(p2)))
	var s_after: Vector2 = main.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(main.session.position)))
	chk("W moves screen-up only", s_after.y < s_before.y and absf(s_after.x - s_before.x) < 0.01, "%s -> %s" % [s_before, s_after])
	# 4 pause / single clock
	main.session.paused = false
	main.session.multiplier = 1.0
	main.session.position = Coords.cell_center_logic(Vector2i(24, 20))
	main.tick(0.1, Vector2(1, 0))
	var t0: float = main.session.clock.elapsed
	var pp: Vector2 = main.session.position
	main.toggle_pause()
	for i in 20: main.tick(0.1, Vector2(1, 0))
	chk("pause freezes time+pos", main.session.clock.elapsed == t0 and main.session.position == pp, "%.3f %.3f" % [t0, main.session.clock.elapsed])
	main.toggle_pause()
	main.tick(0.016, Vector2.ZERO)
	chk("resume no catch-up", main.session.clock.elapsed - t0 < 0.05, "dt=%.4f" % (main.session.clock.elapsed - t0))
	# big real delta capped
	var t1: float = main.session.clock.elapsed
	main.tick(5.0, Vector2.ZERO)
	chk("big delta capped", main.session.clock.elapsed - t1 <= 0.26, "%.3f" % (main.session.clock.elapsed - t1))
	# speed independent of resolution multiplier: walking unaffected by x16
	main.session.multiplier = 16.0
	main.session.position = Coords.cell_center_logic(Vector2i(24, 20))
	var q: Vector2 = main.session.position
	for i in 8: main.tick(0.1, Vector2(1, 0))
	chk("walk unaffected by x16", absf((main.session.position - q).length() * 0.1 - 1.92) < 0.02, "%.3f" % ((main.session.position - q).length() * 0.1))
	print("RESULT fails=", fails)
	main.session.close()
	quit(fails)
