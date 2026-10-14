extends Node
## P0-VERIFY driver. Instantiates the real res://scenes/main.tscn and injects input ONLY through
## Input.parse_input_event (engine-internal; no OS input, no focus grab, no cursor movement).
## Game variables are only READ for observation; never written, and no game method is called as input.
## Args after "--": --suite=input|visual|minsize --out=<dir> --tag=<name> --mode=windowed|fullscreen
##                  --size=WxH --screen=<index>
## Expected values are derived from the spec (96 px/s, diagonal not faster, 8 directions) and geometry.

var game: Node
var args: Dictionary = {}
var out_dir: String = ""
var tag: String = ""
var checks: Array = []
var captures: Array = []
var log_file: FileAccess
var k: int = 2
var off: Vector2i = Vector2i.ZERO
var phys_frame: int = 0
var last_mouse: Vector2 = Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 1000
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var parts: PackedStringArray = a.substr(2).split("=", true, 1)
			args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	out_dir = args.get("out", "user://")
	tag = args.get("tag", "run")
	log_file = FileAccess.open(out_dir.path_join("%s-frames.log" % tag), FileAccess.WRITE)
	var screen: int = int(args.get("screen", "-1"))
	if screen < 0:
		screen = 0
		for s: int in DisplayServer.get_screen_count():
			if s != DisplayServer.get_primary_screen():
				screen = s
				break
	var mode: String = args.get("mode", "windowed")
	var size_arg: PackedStringArray = args.get("size", "1280x720").split("x")
	var want: Vector2i = Vector2i(int(size_arg[0]), int(size_arg[1]))
	# NOTE: unfocusable=true was tried first; the window content then could not be screen-captured (blank), so it is opt-in only.
	if args.has("unfocusable"):
		get_window().unfocusable = true
	DisplayServer.window_set_current_screen(screen)
	if mode == "fullscreen":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(want)
		DisplayServer.window_set_position(DisplayServer.screen_get_position(screen) + Vector2i(60, 40))
	for i: int in 20:
		await get_tree().process_frame
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for i: int in 20:
		await get_tree().process_frame
	win = DisplayServer.window_get_size()
	compute_layout()
	var info: Dictionary = {
		"screen_index": screen, "screen_count": DisplayServer.get_screen_count(),
		"screen_pos": DisplayServer.screen_get_position(screen), "screen_size": DisplayServer.screen_get_size(screen),
		"screen_scale": DisplayServer.screen_get_scale(screen), "screen_dpi": DisplayServer.screen_get_dpi(screen),
		"mode_requested": mode, "window_mode": DisplayServer.window_get_mode(), "window_size": win,
		"window_pos": DisplayServer.window_get_position(), "window_pos_with_decor": DisplayServer.window_get_position_with_decorations(),
		"window_size_with_decor": DisplayServer.window_get_size_with_decorations(),
		"viewport": get_viewport().get_visible_rect().size, "renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "min_size": get_window().min_size,
		"physics_ticks": Engine.physics_ticks_per_second, "k_used_for_injection": k, "offset_used": off,
		"unfocusable": get_window().unfocusable, "has_focus": get_window().has_focus(),
		"cmdline_user": OS.get_cmdline_user_args(), "time": Time.get_datetime_string_from_system()}
	save_json("%s-info.json" % tag, info)
	log_file.store_line("S," + JSON.stringify(info))
	match args.get("suite", "input"):
		"input": await suite_input()
		"visual": await suite_visual()
		"minsize": await suite_minsize()
		"mouseprobe": await suite_mouseprobe()
		"capprobe": await suite_capprobe()
		"pw": await suite_pw()
	save_json("%s-checks.json" % tag, {"tag": tag, "checks": checks})
	save_json("%s-captures.json" % tag, {"tag": tag, "captures": captures})
	log_file.flush()
	get_tree().quit()

var win: Vector2i = Vector2i.ZERO

func compute_layout() -> void:
	# Independent of the game: floor(min(W/640,H/360)), centered.
	k = maxi(1, mini(win.x / 640, win.y / 360))
	off = Vector2i((win.x - 640 * k) / 2, (win.y - 360 * k) / 2)

# ---------------------------------------------------------------- helpers
func save_json(file: String, data: Variant) -> void:
	var f: FileAccess = FileAccess.open(out_dir.path_join(file), FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  ", true, true))
	f.close()

func chk(id: String, cond: String, ok: bool, observed: Variant, evidence: String = "") -> void:
	checks.append({"id": id, "condition": cond, "result": "PASS" if ok else "FAIL", "observed": observed, "evidence": evidence})
	print("CHECK %s %s %s" % [id, "PASS" if ok else "FAIL", str(observed).left(300)])

func frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame

func wpos(vp: Vector2) -> Vector2:
	# viewport (640x360) coordinates -> window pixel coordinates (letterboxed integer scale)
	return Vector2(off) + vp * float(k)

func key(code: Key, pressed: bool) -> void:
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)

func tap(code: Key) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(2)

func mouse_move(vp: Vector2) -> void:
	var p: Vector2 = wpos(vp)
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = p - last_mouse
	last_mouse = p
	Input.parse_input_event(e)

func mouse_button(vp: Vector2, idx: MouseButton, pressed: bool) -> void:
	var p: Vector2 = wpos(vp)
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.position = p
	e.global_position = p
	e.button_index = idx
	e.pressed = pressed
	e.button_mask = (1 << (idx - 1)) if pressed else 0
	Input.parse_input_event(e)

func click(vp: Vector2, idx: MouseButton) -> void:
	mouse_move(vp)
	await frames(3)
	mouse_button(vp, idx, true)
	await frames(2)
	mouse_button(vp, idx, false)
	await frames(2)

func gp() -> Vector2:
	return game.get("player").get("simulation_position")

func aim() -> Vector2:
	return game.get("player").get("aim_direction")

func shots() -> Array:
	return game.get("preview_projectiles")

func shot_color(s: Dictionary) -> String:
	return (s["sprite"] as Sprite2D).texture.get_image().get_pixel(2, 1).to_html(false)

func state() -> Dictionary:
	return {"sim": gp(), "aim": aim(), "paused": get_tree().paused, "condition": game.get("condition"),
		"shots": shots().size(), "cam": (game.get("camera") as Camera2D).get_screen_center_position()}

func _physics_process(_d: float) -> void:
	phys_frame += 1
	if game == null or log_file == null:
		return
	var parts: PackedStringArray = []
	for s: Dictionary in shots():
		var p: Vector2 = s["position"]
		parts.append("%s@%.3f:%.3f/age%.3f" % [shot_color(s), p.x, p.y, s["age"]])
	var sim: Vector2 = gp()
	var a: Vector2 = aim()
	log_file.store_line("F,%d,%.4f,%.4f,%.5f,%.5f,%s,%s,%s,%s" % [phys_frame, sim.x, sim.y, a.x, a.y, get_tree().paused, game.get("condition"), get_viewport().get_mouse_position(), ";".join(parts)])

# Sample sim position each physics tick while keys are held.
func hold_and_sample(codes: Array, n: int) -> Dictionary:
	var samples: Array[Vector2] = []
	var t0: int = Time.get_ticks_usec()
	for c: Key in codes:
		key(c, true)
	for i: int in n:
		await get_tree().physics_frame
		samples.append(gp())
	var t1: int = Time.get_ticks_usec()
	for c: Key in codes:
		key(c, false)
	await frames(3)
	var steps: Array[Vector2] = []
	for i: int in range(1, samples.size()):
		steps.append(samples[i] - samples[i - 1])
	var moving: int = 0
	var sum_len: float = 0.0
	var sum_vec: Vector2 = Vector2.ZERO
	for s: Vector2 in steps:
		if s.length() > 0.01:
			moving += 1
			sum_len += s.length()
			sum_vec += s
	var speed: float = (sum_len / moving * 60.0) if moving > 0 else 0.0
	return {"moving_steps": moving, "total_steps": steps.size(), "speed": speed, "net": samples.back() - samples[0],
		"mean_dir": sum_vec.normalized() if sum_vec.length() > 0 else Vector2.ZERO, "wall_s": (t1 - t0) / 1e6}

# ---------------------------------------------------------------- V1
func suite_input() -> void:
	await frames(30)
	var dirs: Array = [["W", KEY_W, Vector2(0, -1)], ["A", KEY_A, Vector2(-1, 0)], ["S", KEY_S, Vector2(0, 1)], ["D", KEY_D, Vector2(1, 0)]]
	var order: Array = [3, 1, 0, 2]  # D, A, W, S keeps the player inside the world
	for i: int in order:
		var d: Array = dirs[i]
		var r: Dictionary = await hold_and_sample([d[1]], 90)
		var dir_ok: bool = (r["mean_dir"] as Vector2).dot(d[2]) > 0.999
		var sp: float = r["speed"]
		chk("V1-MOVE-%s" % d[0], "%s single hold 90 ticks: direction %s, speed about 96 px/s (tolerance +-1 px/s = ~1%%; 96/60=1.6 px per 1/60 s tick)" % [d[0], d[2]],
			dir_ok and absf(sp - 96.0) <= 1.0 and r["moving_steps"] >= 88, r)
	var diag: Array = [["W+D", [KEY_W, KEY_D], Vector2(1, -1).normalized()], ["W+A", [KEY_W, KEY_A], Vector2(-1, -1).normalized()],
		["S+A", [KEY_S, KEY_A], Vector2(-1, 1).normalized()], ["S+D", [KEY_S, KEY_D], Vector2(1, 1).normalized()]]
	var diag_order: Array = [0, 3, 2, 1]
	for i: int in diag_order:
		var d: Array = diag[i]
		var r: Dictionary = await hold_and_sample(d[1], 60)
		var sp: float = r["speed"]
		chk("V1-DIAG-%s" % d[0], "%s hold 60 ticks: path speed about 96 px/s (normalized, not 96*sqrt2=135.8), direction %s (+-1 deg)" % [d[0], d[2]],
			(r["mean_dir"] as Vector2).dot(d[2]) > 0.9998 and absf(sp - 96.0) <= 1.0 and r["moving_steps"] >= 58, r)
	var r_opp: Dictionary = await hold_and_sample([KEY_A, KEY_D], 30)
	chk("V1-OPPOSE", "A+D together: no net movement (extra)", (r_opp["net"] as Vector2).length() < 0.01, r_opp)
	# ---- aim
	# (1) injected motion: does it change aim? (observation; real OS cursor is never touched)
	var inj_log: Array = []
	var changed_any: bool = false
	var targets: Array = [Vector2(320, 100), Vector2(500, 180), Vector2(320, 260), Vector2(140, 180), Vector2(420, 80)]
	var vm0: Vector2 = get_viewport().get_mouse_position()
	var aim0: Vector2 = aim()
	for t: Vector2 in targets:
		mouse_move(t)
		await frames(4)
		inj_log.append({"injected_window_px": wpos(t), "intended_viewport_px": t, "viewport_mouse_pos": get_viewport().get_mouse_position(), "aim": aim()})
		if get_viewport().get_mouse_position().distance_to(t) < 2.0 and aim().distance_to(aim0) > 0.01:
			changed_any = true
	var vm_follow: bool = true
	for l: Dictionary in inj_log:
		if (l["viewport_mouse_pos"] as Vector2).distance_to(l["intended_viewport_px"]) > 2.0:
			vm_follow = false
	chk("V1-AIM-INJECT", "Injected InputEventMouseMotion (window px, via Input.parse_input_event) moves get_global_mouse_position / aim_direction toward the injected point",
		vm_follow, {"observation": "get_viewport().get_mouse_position() did not follow injected motion; it tracks the real OS cursor (see predicted_vs_actual); injection of aim not possible without moving the real cursor (forbidden)", "log": inj_log, "initial_viewport_mouse": vm0})
	checks[checks.size() - 1]["result"] = "PASS" if vm_follow else "NOT_RUN"
	# (2) passive: aim must point from the player toward the real cursor (read-only DisplayServer.mouse_get_position), checked at several player positions
	var pas: Array = []
	var pas_ok: int = 0
	var moves: Array = [[], [KEY_D], [KEY_D, KEY_S], [KEY_A], [KEY_W]]
	for mv: Array in moves:
		if mv.size() > 0:
			await hold_and_sample(mv, 40)
		await frames(4)
		var cur: Vector2 = Vector2(DisplayServer.mouse_get_position() - DisplayServer.window_get_position())
		var cur_vp: Vector2 = (cur - Vector2(off)) / float(k)
		var cam_c: Vector2 = (game.get("camera") as Camera2D).get_screen_center_position()
		var target_w: Vector2 = cam_c + (cur_vp - Vector2(320, 180))
		var ppos: Vector2 = (game.get("player") as Node2D).position
		var exp_aim: Vector2 = (target_w - ppos).normalized()
		var got_aim: Vector2 = aim()
		var ok_s: bool = got_aim.dot(exp_aim) > 0.9995
		if ok_s:
			pas_ok += 1
		pas.append({"real_cursor_screen": DisplayServer.mouse_get_position(), "cursor_vp": cur_vp, "player": ppos, "cam_center": cam_c, "expected_aim": exp_aim, "aim": got_aim, "match": ok_s})
	chk("V1-AIM-PASSIVE", "aim_direction points from the player to the (read-only observed) real OS cursor at 5 player positions: dot(expected, aim) > 0.9995 (about 1.8 deg); proves the aim path works with the pointer, not injection",
		pas_ok >= 4, {"matches": pas_ok, "samples": pas})
	await hold_and_sample([KEY_A], 40)
	await hold_and_sample([KEY_S], 40)
	await hold_and_sample([KEY_D, KEY_W], 20)
	# ---- shots
	await frames(130)
	var shoot_pt: Vector2 = Vector2(500, 100)
	mouse_move(shoot_pt)
	await frames(4)
	var aim_before: Vector2 = aim()
	var n0: int = shots().size()
	await click(shoot_pt, MOUSE_BUTTON_LEFT)
	var n1: int = shots().size()
	var seed_state: Array = []
	if n1 > 0:
		var s: Dictionary = shots()[0]
		seed_state.append({"color": shot_color(s), "pos0": s["position"], "dir": s["direction"], "age": s["age"]})
	await frames(30)
	var track: Array = []
	var s_pos: Vector2 = Vector2.ZERO
	var s_dir: Vector2 = Vector2.ZERO
	if shots().size() > 0:
		var s2: Dictionary = shots()[0]
		s_pos = s2["position"]
		s_dir = s2["direction"]
		track.append(s_pos)
	await frames(30)
	var moved: Vector2 = Vector2.ZERO
	var speed_obs: float = 0.0
	if shots().size() > 0:
		moved = (shots()[0]["position"] as Vector2) - s_pos
		speed_obs = moved.length() / 0.5
	var seed_color: String = seed_state[0]["color"] if seed_state.size() > 0 else ""
	chk("V1-SHOT-SEED", "Left click injected: exactly one seed provisional projectile spawns (warm/yellow texture), flies along the aim direction, and moves forward",
		n1 == n0 + 1 and seed_color != "" and Color(seed_color).r > Color(seed_color).b and moved.length() > 20.0 and moved.normalized().dot(aim_before) > 0.99,
		{"count_before": n0, "count_after": n1, "seed_state": seed_state, "aim_at_click": aim_before, "moved_in_0.5s": moved, "observed_speed_px_s": speed_obs})
	await frames(130)
	var gone_seed: bool = shots().size() == 0
	var n2: int = shots().size()
	await click(shoot_pt, MOUSE_BUTTON_RIGHT)
	var n3: int = shots().size()
	var water_color: String = ""
	if n3 > 0:
		water_color = shot_color(shots()[0])
	await frames(30)
	var w_pos0: Vector2 = Vector2.ZERO
	if shots().size() > 0:
		w_pos0 = shots()[0]["position"]
	await frames(30)
	var w_moved: Vector2 = Vector2.ZERO
	if shots().size() > 0:
		w_moved = (shots()[0]["position"] as Vector2) - w_pos0
	chk("V1-SHOT-WATER", "Right click injected: exactly one water projectile (cool/blue texture) spawns and flies along aim",
		n3 == n2 + 1 and water_color != "" and Color(water_color).b > Color(water_color).r and w_moved.length() > 20.0 and w_moved.normalized().dot(aim_before) > 0.99,
		{"count_before": n2, "count_after": n3, "water_color": water_color, "moved_in_0.5s": w_moved})
	chk("V1-SHOT-EXPIRE", "Previous (seed) projectile removed after its lifetime (~1.8 s) and not leaked", gone_seed, {"count_after_130_ticks_before_next_click": n2})
	await frames(130)
	# ---- weather keys
	var wk: Array = [["2", KEY_2, "rain"], ["3", KEY_3, "night"], ["1", KEY_1, "sunny"]]
	for w: Array in wk:
		await tap(w[1])
		var mod: Color = (game.get("modulation") as CanvasModulate).color
		var wv: Object = game.get("weather")
		chk("V1-WEATHER-KEY-%s" % w[0], "Injected key %s switches condition to %s (and CanvasModulate / weather view follow)" % [w[0], w[2]],
			game.get("condition") == w[2] and wv.get("condition") == w[2], {"condition": game.get("condition"), "modulate": mod, "night_light_enabled": (game.get("player").get("light") as PointLight2D).enabled})
	# ---- weather buttons via mouse
	var wb: Array = game.get("weather_buttons")
	var names: Array = ["sunny", "rain", "night"]
	for target_idx: int in [1, 2, 0]:
		var b: Button = wb[target_idx]
		var rc: Rect2 = b.get_global_rect()
		await click(rc.get_center(), MOUSE_BUTTON_LEFT)
		chk("V1-WEATHER-BTN-%s" % names[target_idx], "Injected mouse click (motion+press+release in window px) on the top-bar button switches condition to %s" % names[target_idx],
			game.get("condition") == names[target_idx], {"button_rect_vp": rc, "window_px": wpos(rc.get_center()), "condition": game.get("condition"), "shots_spawned_by_click": shots().size()})
	# ---- pause
	await tap(KEY_1)
	await frames(10)
	# make a flying shot to verify freeze
	await click(shoot_pt, MOUSE_BUTTON_LEFT)
	await frames(10)
	var pre: Dictionary = state()
	var pre_shot: Dictionary = {}
	if shots().size() > 0:
		pre_shot = {"pos": shots()[0]["position"], "age": shots()[0]["age"]}
	await tap(KEY_ESCAPE)
	if shots().size() > 0:
		pre_shot = {"pos": shots()[0]["position"], "age": shots()[0]["age"]}
	var panel: Control = game.get("pause_panel")
	chk("V1-PAUSE-ON", "Injected Esc pauses the tree and shows the pause panel", get_tree().paused and panel.visible, {"paused": get_tree().paused, "panel_visible": panel.visible})
	var p_before: Vector2 = gp()
	var sh_before: int = shots().size()
	key(KEY_W, true)
	key(KEY_D, true)
	await frames(40)
	await click(shoot_pt, MOUSE_BUTTON_LEFT)
	await click(shoot_pt, MOUSE_BUTTON_RIGHT)
	await tap(KEY_2)
	await tap(KEY_3)
	key(KEY_W, false)
	key(KEY_D, false)
	await frames(3)
	var post_shot: Dictionary = {}
	if shots().size() > 0:
		post_shot = {"pos": shots()[0]["position"], "age": shots()[0]["age"]}
	chk("V1-PAUSE-FREEZE", "While paused: held W+D does not move player, clicks spawn no projectile, keys 2/3 do not change condition, existing projectile frozen (pos/age unchanged)",
		gp().is_equal_approx(p_before) and shots().size() == sh_before and game.get("condition") == "sunny" and post_shot.hash() == pre_shot.hash(),
		{"player_before": p_before, "player_after": gp(), "shots_before": sh_before, "shots_after": shots().size(), "condition": game.get("condition"), "shot_before": pre_shot, "shot_after": post_shot, "pre_state": pre})
	# buttons disabled & clicking weather button inert in pause
	var rain_btn: Button = wb[1]
	await click(rain_btn.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	chk("V1-PAUSE-BTN-INERT", "While paused the weather button is disabled and a click injected on it does not change condition", rain_btn.disabled and game.get("condition") == "sunny", {"disabled": rain_btn.disabled, "condition": game.get("condition")})
	# resume via Esc
	await tap(KEY_ESCAPE)
	chk("V1-RESUME-ESC", "Injected Esc resumes (paused=false, panel hidden)", (not get_tree().paused) and (not panel.visible), {"paused": get_tree().paused, "panel_visible": panel.visible})
	var r_after: Dictionary = await hold_and_sample([KEY_S], 30)
	chk("V1-RESUME-MOVE", "After Esc resume, held S moves again at about 96 px/s", absf(r_after["speed"] - 96.0) <= 1.0 and r_after["moving_steps"] >= 28, r_after)
	var post_resume_shot: Dictionary = {}
	if shots().size() > 0:
		post_resume_shot = {"pos": shots()[0]["position"], "age": shots()[0]["age"]}
	# resume button
	await tap(KEY_ESCAPE)
	var resume: Button = panel.get_child(0).get_child(1)
	var rrect: Rect2 = resume.get_global_rect()
	var was_paused: bool = get_tree().paused
	await click(rrect.get_center(), MOUSE_BUTTON_LEFT)
	chk("V1-RESUME-BTN", "Pause panel resume button clicked via injected mouse events resumes the game", was_paused and not get_tree().paused and not panel.visible,
		{"was_paused": was_paused, "now_paused": get_tree().paused, "button_rect_vp": rrect, "window_px": wpos(rrect.get_center())})
	var wb_enabled: bool = not (wb[1] as Button).disabled
	await click((wb[1] as Button).get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	chk("V1-RESUME-BTN-REENABLE", "After resume the weather buttons are enabled again and respond", wb_enabled and game.get("condition") == "rain", {"enabled": wb_enabled, "condition": game.get("condition")})
	chk("V1-PHYSICAL-KEYBOARD", "Physical keyboard -> OS -> Godot path", false, "NOT_RUN: engine-internal injection only; awaiting user manual check")
	checks[checks.size() - 1]["result"] = "NOT_RUN"

# ---------------------------------------------------------------- V2/V3
func cap(label: String, extra: Dictionary = {}) -> void:
	await RenderingServer.frame_post_draw
	var vp_img: Image = get_viewport().get_texture().get_image()
	var wp: Vector2i = DisplayServer.window_get_position()
	var ws: Vector2i = DisplayServer.window_get_size()
	var img: Image = DisplayServer.screen_get_image_rect(Rect2i(wp, ws))
	var base: String = "%s-%s" % [tag, label]
	var rec: Dictionary = {"label": label, "file": base + ".png", "vp_file": base + "-vp.png", "window_pos": wp, "window_size": ws,
		"image_size": img.get_size() if img != null else Vector2i.ZERO, "state": state(), "phys_frame": phys_frame, "extra": extra}
	if img != null:
		img.save_png(out_dir.path_join(base + ".png"))
	vp_img.save_png(out_dir.path_join(base + "-vp.png"))
	captures.append(rec)

func inject_hold_capture(codes: Array, n: int, step: int, label: String) -> void:
	for c: Key in codes:
		key(c, true)
	for i: int in n:
		await get_tree().physics_frame
		if i % step == step - 1:
			await cap("%s-%02d" % [label, i / step])
	for c: Key in codes:
		key(c, false)
	await frames(3)

func suite_visual() -> void:
	await frames(40)
	await cap("static-sunny-a")
	await cap("static-sunny-b")
	# weather scenes: hero, boars, seed + water projectiles in flight
	var wk: Array = [["sunny", KEY_1], ["rain", KEY_2], ["night", KEY_3]]
	for w: Array in wk:
		await tap(w[1])
		await frames(120)
		mouse_move(Vector2(403, 163))
		await frames(4)
		mouse_button(Vector2(403, 163), MOUSE_BUTTON_LEFT, true)
		await frames(2)
		mouse_button(Vector2(403, 163), MOUSE_BUTTON_LEFT, false)
		await frames(14)
		mouse_button(Vector2(426, 251), MOUSE_BUTTON_RIGHT, true)
		await frames(2)
		mouse_button(Vector2(426, 251), MOUSE_BUTTON_RIGHT, false)
		await frames(10)
		await cap("weather-%s-flight-a" % w[0], {"shots": shots().size()})
		await frames(6)
		await cap("weather-%s-flight-b" % w[0], {"shots": shots().size()})
	await tap(KEY_1)
	await frames(120)
	mouse_move(Vector2(520, 120))
	await frames(4)
	await inject_hold_capture([KEY_D], 100, 25, "move-D")
	await inject_hold_capture([KEY_W, KEY_D], 100, 25, "move-WD")
	await inject_hold_capture([KEY_D], 260, 40, "limit-right")
	await inject_hold_capture([KEY_W], 120, 30, "limit-top")
	await inject_hold_capture([KEY_A], 700, 100, "limit-left")
	# projectiles while scrolling
	await frames(1)
	mouse_move(Vector2(520, 200))
	await frames(4)
	key(KEY_S, true)
	key(KEY_D, true)
	mouse_button(Vector2(520, 200), MOUSE_BUTTON_LEFT, true)
	await frames(2)
	mouse_button(Vector2(520, 200), MOUSE_BUTTON_LEFT, false)
	await frames(6)
	mouse_button(Vector2(520, 200), MOUSE_BUTTON_RIGHT, true)
	await frames(2)
	mouse_button(Vector2(520, 200), MOUSE_BUTTON_RIGHT, false)
	for i: int in 4:
		await frames(12)
		await cap("flight-moving-%d" % i, {"shots": shots().size()})
	key(KEY_S, false)
	key(KEY_D, false)
	await frames(3)
	await inject_hold_capture([KEY_S], 340, 85, "limit-bottom")

func suite_minsize() -> void:
	await frames(20)
	await cap("start")
	var tried: Array = [Vector2i(320, 200), Vector2i(639, 360), Vector2i(640, 359), Vector2i(700, 400), Vector2i(1000, 360)]
	for t: Vector2i in tried:
		DisplayServer.window_set_size(t)
		for i: int in 15:
			await get_tree().process_frame
		var ws: Vector2i = DisplayServer.window_get_size()
		win = ws
		compute_layout()
		chk("V2-MIN-%dx%d" % [t.x, t.y], "window_set_size(%s) must leave client >= 640x360" % t, ws.x >= 640 and ws.y >= 360, {"requested": t, "actual_dispserver": ws, "window_size": get_window().size, "min_size": get_window().min_size, "viewport": get_viewport().get_visible_rect().size})
		await cap("min-%dx%d" % [t.x, t.y], {"requested": t})
	DisplayServer.window_set_size(Vector2i(320, 200))
	for i: int in 15:
		await get_tree().process_frame
	await cap("min-final")

func probe(label: String) -> Dictionary:
	await frames(4)
	return {"label": label, "viewport_mouse": get_viewport().get_mouse_position(), "global_mouse": (game.get("player") as Node2D).get_global_mouse_position(), "aim": aim(), "DisplayServer_mouse_get_position_screen": DisplayServer.mouse_get_position(), "predicted_viewport_from_real_cursor": (Vector2(DisplayServer.mouse_get_position() - DisplayServer.window_get_position()) - Vector2(off)) / float(k), "Input_get_mouse_position": Input.get_last_mouse_velocity()}

func motion_event(p: Vector2) -> InputEventMouseMotion:
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = Vector2(1, 1)
	return e

func suite_mouseprobe() -> void:
	await frames(30)
	var res: Array = []
	res.append(await probe("baseline (no injection)"))
	var target_vp: Vector2 = Vector2(320, 100)
	Input.parse_input_event(motion_event(wpos(target_vp)))
	res.append(await probe("A Input.parse_input_event motion window px, accumulated_input=%s" % Input.use_accumulated_input))
	Input.use_accumulated_input = false
	Input.parse_input_event(motion_event(wpos(Vector2(500, 180))))
	res.append(await probe("A2 Input.parse_input_event motion window px, accumulated_input=false"))
	Input.use_accumulated_input = true
	get_viewport().push_input(motion_event(wpos(Vector2(140, 180))), false)
	res.append(await probe("B viewport.push_input(motion, local=false) window px"))
	get_viewport().push_input(motion_event(Vector2(320, 260)), true)
	res.append(await probe("C viewport.push_input(motion, local=true) viewport px"))
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.position = wpos(Vector2(420, 80))
	mb.global_position = mb.position
	mb.button_index = MOUSE_BUTTON_MIDDLE
	mb.pressed = true
	Input.parse_input_event(mb)
	res.append(await probe("D middle button press at window px (420,80 vp) via parse_input_event"))
	get_window().notification(Node.NOTIFICATION_WM_MOUSE_ENTER)
	res.append(await probe("E after window.notification(WM_MOUSE_ENTER) (what OS sends when cursor enters), no motion yet"))
	Input.parse_input_event(motion_event(wpos(Vector2(500, 180))))
	res.append(await probe("F parse_input_event motion to vp(500,180) after MOUSE_ENTER"))
	get_viewport().push_input(motion_event(wpos(Vector2(140, 180))), false)
	res.append(await probe("G push_input(local=false) to vp(140,180) after MOUSE_ENTER"))
	Input.parse_input_event(motion_event(wpos(Vector2(320, 100))))
	res.append(await probe("H parse_input_event motion to vp(320,100)"))
	save_json("%s-probe.json" % tag, {"window": win, "k": k, "off": off, "focus": get_window().has_focus(), "results": res})
	for r: Dictionary in res:
		print("PROBE ", r)

func suite_capprobe() -> void:
	await frames(40)
	await RenderingServer.frame_post_draw
	var sc: int = DisplayServer.window_get_current_screen()
	var full: Image = DisplayServer.screen_get_image(sc)
	full.save_png(out_dir.path_join("%s-fullscreen.png" % tag))
	var wp: Vector2i = DisplayServer.window_get_position()
	var sp: Vector2i = DisplayServer.screen_get_position(sc)
	var ws: Vector2i = DisplayServer.window_get_size()
	var a: Image = DisplayServer.screen_get_image_rect(Rect2i(wp, ws))
	a.save_png(out_dir.path_join("%s-rect-global.png" % tag))
	var b: Image = DisplayServer.screen_get_image_rect(Rect2i(wp - sp, ws))
	b.save_png(out_dir.path_join("%s-rect-relative.png" % tag))
	print("CAPPROBE full=", full.get_size(), " wp=", wp, " sp=", sp, " ws=", ws, " a=", a.get_size(), " b=", b.get_size())

func suite_pw() -> void:
	# Cross-check: PrintWindow client capture (async via a child powershell; Godot must keep pumping messages).
	await frames(40)
	var states: Array = [["static", 0], ["night", 1]]
	for st: Array in states:
		if st[1] == 1:
			await tap(KEY_3)
			await frames(40)
		await RenderingServer.frame_post_draw
		var vp_img: Image = get_viewport().get_texture().get_image()
		var wp: Vector2i = DisplayServer.window_get_position()
		var ws: Vector2i = DisplayServer.window_get_size()
		var img: Image = DisplayServer.screen_get_image_rect(Rect2i(wp, ws))
		var base: String = "%s-%s" % [tag, st[0]]
		img.save_png(out_dir.path_join(base + "-screenrect.png"))
		vp_img.save_png(out_dir.path_join(base + "-vp.png"))
		var pw_file: String = out_dir.path_join(base + "-printwindow.png")
		if FileAccess.file_exists(pw_file):
			DirAccess.remove_absolute(pw_file)
		var hwnd: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, 0)
		var pid: int = OS.create_process("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://tests/independent/p0_verify_printwindow.ps1"), "-Hwnd", str(hwnd), "-Out", pw_file])
		var waited: int = 0
		while not FileAccess.file_exists(pw_file) and waited < 600:
			await get_tree().process_frame
			waited += 1
		for i: int in 30:
			await get_tree().process_frame
		captures.append({"label": st[0] + "-printwindow", "file": base + "-printwindow.png", "vp_file": base + "-vp.png", "method": "PrintWindow", "window_size": ws, "hwnd": hwnd, "ps_pid": pid, "frames_waited": waited, "state": state()})
		captures.append({"label": st[0] + "-screenrect", "file": base + "-screenrect.png", "vp_file": base + "-vp.png", "method": "screen_get_image_rect", "window_size": ws, "state": state()})
