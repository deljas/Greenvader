extends SceneTree
## POL-01 independent check 1: walking speed via injected WASD/F3 (Input.parse_input_event), thin-wall tunnelling at the 0.25 s frame cap.
##   godot --headless --path <repo> --script res://tests/poc/independent/pol01_move.gd
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
var passes: int = 0
var fails: int = 0
var main: Node

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("PASS " if ok else "FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func key(code: int, pressed: bool) -> void:
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = code as Key
	e.keycode = code as Key
	e.pressed = pressed
	Input.parse_input_event(e)

func tap(code: int) -> void:
	key(code, true)
	await process_frame
	await process_frame
	key(code, false)
	await process_frame
	await process_frame

func measure(codes: Array[int], want_walk_s: float) -> Dictionary:
	var s: RefCounted = main.session
	s.position = Coords.cell_center_logic(Vector2i(87, 85))
	await process_frame
	await process_frame
	var p0: Vector2 = s.position
	var a0: float = main.animation_time
	var g0: float = s.clock.elapsed
	for c: int in codes:
		key(c, true)
	var guard: int = 0
	while main.animation_time - a0 < want_walk_s and guard < 2000:
		await process_frame
		guard += 1
	for c: int in codes:
		key(c, false)
	await process_frame
	await process_frame
	await process_frame
	var dt: float = main.animation_time - a0
	var disp_m: float = (s.position - p0).length() * 0.1
	return {"speed": disp_m / maxf(dt, 0.0001), "dt": dt, "game_rate": (s.clock.elapsed - g0) / maxf(dt, 0.0001), "disp": s.position - p0}

func _run() -> void:
	change_scene_to_file("res://scenes/poc.tscn")
	for i: int in 6:
		await process_frame
	main = current_scene
	(main.ui.title_buttons[&"new_game"] as Button).pressed.emit()
	for i: int in 4:
		await process_frame
	check("started", main.menu == &"" and main.auto_process, "menu=%s" % str(main.menu))
	check("config_speed", Config.WALK_SPEED_MPS == 4.8 and absf(Config.walk_speed_px() - 48.0) < 0.001)
	var cases: Dictionary = {
		"W": [KEY_W], "S": [KEY_S], "A": [KEY_A], "D": [KEY_D],
		"W+D": [KEY_W, KEY_D], "W+A": [KEY_W, KEY_A], "S+D": [KEY_S, KEY_D], "S+A": [KEY_S, KEY_A], "UP+RIGHT": [KEY_UP, KEY_RIGHT],
	}
	for res_idx: int in [0, 1]:
		check("set_res_%d" % res_idx, main.set_resolution(res_idx, Vector2i(1920, 1080)))
		for mult_step: int in 3:
			# mult_step 0: x1, then F3 -> x4, F3 -> x16
			for name: String in cases:
				if mult_step > 0 and name != "W" and name != "W+D":
					continue
				var codes: Array[int] = []
				for c: int in cases[name]:
					codes.append(c)
				var m: Dictionary = await measure(codes, 0.45)
				var expect_mult: float = [1.0, 4.0, 16.0][mult_step]
				check("speed_res%d_x%d_%s" % [res_idx, int(expect_mult), name], absf(float(m["speed"]) - 4.8) < 0.15 and absf(main.session.multiplier - expect_mult) < 0.01, "speed %.3f m/s over %.3f s, game_rate %.2f, mult %.0f" % [m["speed"], m["dt"], m["game_rate"], main.session.multiplier])
			await tap(KEY_F3)
		# cycle back to x1 (after 3 taps the cycle returns to x1)
		check("mult_back_x1_res%d" % res_idx, main.session.multiplier == 1.0, str(main.session.multiplier))
	_thin_walls()
	print("RESULT pass=%d fail=%d" % [passes, fails])
	quit(1 if fails > 0 else 0)

func _thin_walls() -> void:
	var s: RefCounted = main.session
	var st: WorldState = s.state
	var half: Vector2 = Config.player_half_px()
	var configs: int = 0
	var tunnels: int = 0
	var overlaps: int = 0
	var maxstep: float = 0.0
	var dirs: Array[Vector2] = [Vector2(1, 0), Vector2(1, 1), Vector2(1, -1), Vector2(0, 1), Vector2(1, 2), Vector2(2, 1)]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var cands: Array[Vector3i] = []
	for y: int in range(2, st.height - 2):
		for x: int in range(2, st.width - 2):
			if st.is_walkable(x, y):
				continue
			# thin in x: walkable both sides with the rows around them clear
			if st.is_walkable(x - 1, y) and st.is_walkable(x + 1, y) and st.is_walkable(x - 1, y - 1) and st.is_walkable(x - 1, y + 1) and st.is_walkable(x + 1, y - 1) and st.is_walkable(x + 1, y + 1):
				cands.append(Vector3i(x, y, 0))
			if st.is_walkable(x, y - 1) and st.is_walkable(x, y + 1) and st.is_walkable(x - 1, y - 1) and st.is_walkable(x + 1, y - 1) and st.is_walkable(x - 1, y + 1) and st.is_walkable(x + 1, y + 1):
				cands.append(Vector3i(x, y, 1))
	print("INFO thin wall candidates: ", cands.size())
	var sample: int = mini(cands.size(), 400)
	for k: int in sample:
		var cnd: Vector3i = cands[rng.randi_range(0, cands.size() - 1)]
		var axis_x: bool = cnd.z == 0
		for d0: Vector2 in dirs:
			var d: Vector2 = d0.normalized()
			if not axis_x:
				d = Vector2(d.y, d.x)
			for sign_: float in [1.0, -1.0]:
				# start flush against the wall's near face, other-axis centred on the wall cell
				var pos: Vector2
				if axis_x:
					pos = Vector2(float(cnd.x * 4) - half.x - 0.001 if sign_ > 0 else float((cnd.x + 1) * 4) + half.x + 0.001, float(cnd.y * 4) + 2.0)
				else:
					pos = Vector2(float(cnd.x * 4) + 2.0, float(cnd.y * 4) - half.y - 0.001 if sign_ > 0 else float((cnd.y + 1) * 4) + half.y + 0.001)
				if not Walker.is_clear(st, 4, pos, half):
					continue
				s.position = pos
				configs += 1
				var motion: Vector2 = d * sign_
				var ground: Vector2 = Coords.ground_dir_to_screen(motion)
				for f: int in 8:
					var before: Vector2 = s.position
					s.walk(ground, 10.0) # absurd delta: must be capped at 0.25 s
					maxstep = maxf(maxstep, (s.position - before).length())
					if not Walker.is_clear(st, 4, s.position, half):
						overlaps += 1
					var cross: bool = (s.position.x > float((cnd.x + 1) * 4) - half.x * 0.0 and sign_ > 0 and axis_x) or (s.position.x < float(cnd.x * 4) and sign_ < 0 and axis_x) or (s.position.y > float((cnd.y + 1) * 4) and sign_ > 0 and not axis_x) or (s.position.y < float(cnd.y * 4) and sign_ < 0 and not axis_x)
					# crossing means feet centre past the far face of the wall cell while overlapping its row/col range
					if cross:
						var row_hit: bool = s.position.y > float(cnd.y * 4) - half.y and s.position.y < float((cnd.y + 1) * 4) + half.y if axis_x else s.position.x > float(cnd.x * 4) - half.x and s.position.x < float((cnd.x + 1) * 4) + half.x
						if row_hit:
							tunnels += 1
	check("thin_wall_no_tunnel", configs > 100 and tunnels == 0 and overlaps == 0, "configs %d tunnels %d overlaps %d max step per capped frame %.3f px (cap 12.0)" % [configs, tunnels, overlaps, maxstep])
	check("frame_cap_step", maxstep <= 12.0 + 0.001, "%.3f" % maxstep)
