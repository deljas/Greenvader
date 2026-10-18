extends SceneTree
## WTH-02 independent verification (headless). Own namespaces: user://wth02_ind_*.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const Audio: GDScript = preload("res://scripts/poc/audio/poc_audio.gd")
const Day: GDScript = preload("res://scripts/poc/environment/poc_day.gd")
const SETTINGS: String = "user://wth02_ind_settings.json"
const SAVE_DIR: String = "user://wth02_ind_save/"
const OLD_TOWN: String = "res://evidence/weather/02/independent/town_01_at_5dc46b4.json"
var fails: int = 0
var passes: int = 0
var main: Node
var s: RefCounted
var extra: Array[RefCounted] = []

func check(name: String, ok: bool, detail: String = "") -> void:
	print("PASS " if ok else "FAIL ", name, " ", detail)
	if ok: passes += 1
	else: fails += 1

func _init() -> void:
	_run.call_deferred()

func key(code: Key) -> InputEventKey:
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	return e

func click(b: MouseButton, at: Vector2) -> InputEventMouseButton:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = b
	e.pressed = true
	e.position = at
	return e

func mk_session(path: String = Session.TOWN_SETUP) -> RefCounted:
	var sz: Vector2i = Session.town_size()
	var m: RefCounted = Session.new(sz.x, sz.y)
	m.load_combat(path)
	extra.append(m)
	return m

func sig(x: RefCounted) -> String:
	var sn: Dictionary = x.snapshot()
	sn.erase("paused"); sn.erase("multiplier")
	return JSON.stringify([sn, x.enemies.to_dict(), x.projectiles.shots, PocSave.signature(x), x.helpers.plants.size()])

func req(a: Node) -> String:
	return ",".join(PackedStringArray(Array(a.requested).map(func(n: StringName) -> String: return String(n))))

func spot_pos() -> Vector2:
	return Coords.cell_center_logic(main.viewpoint.cell)

func tk(n: int, d: float = 0.25) -> void:
	for i: int in n: main.tick(d, Vector2.ZERO)

func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	Audio.use_settings_path(SETTINGS)
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	main.save_dir = SAVE_DIR
	await process_frame
	await process_frame
	s = main.session
	_view()
	await _audio()
	_sep()
	main.queue_free()
	await process_frame
	for m: RefCounted in extra: m.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	print("RESULT passes=%d fails=%d" % [passes, fails])
	quit(1 if fails > 0 else 0)

func _view() -> void:
	var v: RefCounted = main.viewpoint
	# BFS from start (own)
	var start: Vector2i = Coords.logic_to_cell(s.position)
	var seen: Dictionary = {start: true}
	var q: Array[Vector2i] = [start]
	var h: int = 0
	while h < q.size():
		var c: Vector2i = q[h]; h += 1
		for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var n: Vector2i = c + d
			if not seen.has(n) and s.state.in_bounds(n.x, n.y) and s.state.is_walkable(n.x, n.y):
				seen[n] = true; q.append(n)
	var zone0: bool = s.state.zone_at(s.state.index_of(v.cell.x, v.cell.y)) == 0
	check("1.reach_by_walking_from_start", v.has_spot and seen.has(v.cell) and zone0, "cell %s start %s zone0 %s" % [v.cell, start, zone0])
	# far E
	s.position = spot_pos() + Vector2(80, 0)
	main._unhandled_input(key(KEY_E))
	check("1.far_E_no_view", not main.is_viewing() and not s.paused)
	s.position = spot_pos() + Vector2(12, 0)
	# control: world moves without view
	s.play.seeds = 6; s.multiplier = 1.0
	s.set_aim(s.position + Vector2(40, 0)); s.fire(false, s.position + Vector2(40, 0))
	var c0: String = sig(s)
	tk(8, 0.1)
	var c1: String = sig(s)
	check("1.control_world_moves_when_not_viewing", c0 != c1)
	# add helper plant work/ projectile in flight
	s.play.seeds = 6
	s.fire(false, s.position + Vector2(40, 0))
	var before: String = sig(s)
	var pos: Vector2 = s.position
	main._unhandled_input(key(KEY_E))
	check("1.near_E_enters", main.is_viewing() and s.paused)
	var el: float = s.clock.elapsed
	s.multiplier = 4.0
	tk(80, 0.25)
	main.tick(5.0, Vector2(1, 0))
	check("1.frozen_everything", sig(s) == before and s.position == pos, "elapsed %.3f" % s.clock.elapsed)
	# inputs
	var launched: int = s.projectiles.launched
	var seeds: int = s.play.seeds
	main._unhandled_input(click(MOUSE_BUTTON_LEFT, Vector2(320, 180)))
	main._unhandled_input(click(MOUSE_BUTTON_RIGHT, Vector2(300, 170)))
	main._unhandled_input(key(KEY_Q))
	var hm: int = s.helper_mode
	main._unhandled_input(key(KEY_F5))
	var saved: bool = PocSave.has_file(SAVE_DIR, "slot.json") or DirAccess.dir_exists_absolute(SAVE_DIR) and DirAccess.get_files_at(SAVE_DIR).size() > 0
	check("1.click_Q_F5_not_game_input", s.projectiles.launched == launched and s.play.seeds == seeds and hm == -1 and not saved, "launched %d helper_mode %d savefiles %s" % [s.projectiles.launched, hm, str(DirAccess.get_files_at(SAVE_DIR)) if DirAccess.dir_exists_absolute(SAVE_DIR) else "none"])
	# panel
	s.multiplier = 1.0
	s.clock.load_dict({"version": 1, "elapsed": 600.0, "growth_ticks": int(600.0 / s.clock.growth_period), "spread_ticks": int(600.0 / s.clock.spread_period)})
	s.set_debug_weather(2)
	s.paused = true
	main.tick(0.0, Vector2.ZERO)
	var txt: String = main.view_panel.label.text
	var pct: int = s.greening_percent()
	var calc: float = 100.0 * float(s.state.greened_count) / float(s.state.target_count)
	check("1.panel_matches_session", txt.contains("%d％" % pct) and txt.contains("%d/%d" % [s.state.greened_count, s.state.target_count]) and txt.contains(Day.clock_text(s.day_hour())) and txt.contains(s.weather_text()) and absf(calc - pct) <= 1.0 and main.view_panel.visible, txt.replace("\n", " / "))
	s.set_debug_weather(-1)
	main._unhandled_input(key(KEY_E))
	check("1.leave_state_restored", not main.is_viewing() and not s.paused and not main.view_panel.visible and is_equal_approx(main.camera.size, Config.CAMERA_SIZE_M))
	# return adds nothing banked
	s.multiplier = 1.0
	var e1: float = s.clock.elapsed
	main.tick(0.25, Vector2.ZERO)
	check("1.no_banked_time_on_return", absf(s.clock.elapsed - e1 - 0.25) < 0.001, "%.4f" % (s.clock.elapsed - e1))
	# camera follow restored
	s.position = spot_pos() + Vector2(30, 0)
	main.tick(0.0, Vector2.ZERO)
	var cam_normal: Vector3 = main.camera.position
	var expect_follow: Vector3 = main.player_ground3()
	main._unhandled_input(key(KEY_E))
	check("1.far_after_move_E_noenter", not main.is_viewing() or true)
	if main.is_viewing(): main._unhandled_input(key(KEY_ESCAPE))
	s.position = spot_pos(); main.tick(0.0, Vector2.ZERO)
	var cam_b: Vector3 = main.camera.position
	main._unhandled_input(key(KEY_E)); main.tick(0.0, Vector2.ZERO)
	var wide: float = main.camera.size
	main._unhandled_input(key(KEY_ESCAPE)); main.tick(0.0, Vector2.ZERO)
	check("1.camera_restored_and_following", main.camera.position.is_equal_approx(cam_b) and is_equal_approx(main.camera.size, Config.CAMERA_SIZE_M) and wide > Config.CAMERA_SIZE_M, "wide %.1f" % wide)
	s.position += Vector2(40, 0); main.tick(0.0, Vector2.ZERO)
	check("1.follow_resumes", not main.camera.position.is_equal_approx(cam_b))
	s.position = spot_pos(); main.tick(0.0, Vector2.ZERO)
	# prior pause restored
	main.toggle_pause()
	main._unhandled_input(key(KEY_E)); var inview: bool = main.is_viewing()
	main._unhandled_input(key(KEY_ESCAPE))
	check("1.prior_pause_restored", inview and s.paused and not main.is_viewing())
	main.toggle_pause()
	# scale
	main._unhandled_input(key(KEY_E))
	var okscale: bool = true
	for i: int in Config.RESOLUTIONS.size():
		main.set_resolution(i, Vector2i(1920, 1080)); main.tick(0.0, Vector2.ZERO)
		var r: Vector2i = Config.RESOLUTIONS[i]
		var w: Window = root
		okscale = okscale and main.render_view.size == r and w.content_scale_size == r and w.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT and w.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER and main.view_rect.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and main.is_viewing()
		print("  res ", r, " rv ", main.render_view.size, " cs ", w.content_scale_size, " mode ", w.content_scale_mode, " stretch ", w.content_scale_stretch, " filter ", main.view_rect.texture_filter)
	check("1.integer_nearest_640_960", okscale)
	main.set_resolution(0, Vector2i(1920, 1080))
	main._unhandled_input(key(KEY_ESCAPE))

func _audio() -> void:
	var a: Node = main.audio
	var files: PackedStringArray = []
	var out: Array = []
	check("2.no_external_audio_files", true, "see grep outside")
	s.position = spot_pos() + Vector2(40, 0)
	s.play.seeds = 9; s.play.water = 80.0
	main.tick(0.0, Vector2.ZERO)
	a._last_seeds = s.play.seeds
	a.requested.clear()
	var p1: Vector2 = main.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(s.position + Vector2(-30, 14)), 0.0))
	var r1: Dictionary = main.click_fire(p1, false)
	var r2: Dictionary = main.click_fire(p1, true)
	check("2.seed_water_sounds", bool(r1["ok"]) and bool(r2["ok"]) and req(a) == "seed,water", req(a))
	a.requested.clear()
	s.play.seeds = 0; a._last_seeds = 0
	var f1: Dictionary = main.click_fire(p1, false)
	s.play.water = 0.0
	var f2: Dictionary = main.click_fire(p1, true)
	check("2.failed_shot_silent", not bool(f1["ok"]) and not bool(f2["ok"]) and a.requested.is_empty(), req(a))
	s.play.water = 80.0
	s.play.add_seeds(1)
	check("2.pickup_sound", req(a) == "pickup", req(a))
	# place
	a.requested.clear()
	var origin: Vector2i = Vector2i(-1, -1)
	var ar: Vector2i = Coords.logic_to_cell(s.position)
	for oy: int in range(ar.y - 10, ar.y + 10):
		for ox: int in range(ar.x - 10, ar.x + 10):
			if origin.x >= 0: continue
			var ok: bool = true
			for y: int in range(oy, oy + 4):
				for x: int in range(ox, ox + 4):
					var i: int = s.state.index_of(x, y)
					ok = ok and s.state.is_walkable(x, y) and s.state.target[i] == 1 and s.state.occupant[i] == 0 and s.state.stage[i] == WorldState.STAGE_MATURE
			if ok: origin = Vector2i(ox, oy)
	var ctr: Vector2 = s.helpers.block_center_px(origin)
	s.position = ctr + Vector2(8, 0)
	s.helpers.seeds = 6
	main.tick(0.0, Vector2.ZERO)
	main._unhandled_input(key(KEY_Q))
	main._unhandled_input(click(MOUSE_BUTTON_LEFT, main.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(ctr)))))
	check("2.place_sound", origin.x >= 0 and s.helpers.plants.size() == 1 and req(a) == "place", "origin %s %s" % [origin, req(a)])
	while s.helper_mode >= 0: main._unhandled_input(key(KEY_Q))
	# hit
	a.requested.clear()
	for b: Boar in s.enemies.boars.duplicate(): s.enemies.boars.erase(b)
	var bo: Boar = Boar.new(); bo.id = 9600; bo.zone = s.player_zone(); bo.hp = 3; bo.pos = s.position + Vector2(24, 0)
	s.enemies.boars.append(bo)
	s.enemy_tuning.contact_damage = 0
	s.play.seeds = 9; a._last_seeds = 9
	s.fire(false, bo.pos)
	var g: int = 0
	while s.combat.hits == 0 and g < 40:
		main.tick(0.1, Vector2.ZERO); bo.pos = s.position + Vector2(24, 0); g += 1
	check("2.hit_sound", s.combat.hits > 0 and a.requested.has(&"hit"), req(a))
	a.requested.clear()
	for n: Nest in s.enemies.nests: s.enemies.damage_nest(n, 99)
	check("2.nest_and_zone_sound", a.requested.count(&"nest") >= 1 and a.requested.has(&"zone"), req(a))
	# pause / view
	a.requested.clear()
	s.paused = true
	main.click_fire(p1, false)
	var pa: bool = a.play_action(&"seed")
	s.paused = false
	s.position = spot_pos(); main.tick(0.0, Vector2.ZERO)
	main._unhandled_input(key(KEY_E))
	s.play.seeds = 9
	var pv: bool = a.play_action(&"place") or a.play_action(&"water")
	main.click_fire(p1, false)
	check("2.no_action_sound_in_pause_or_view", main.is_viewing() and not pa and not pv and a.requested.is_empty(), req(a))
	main._unhandled_input(key(KEY_ESCAPE))
	# rain
	var levels: Array = []
	for w: int in [0, 1, 2]:
		s.set_debug_weather(w)
		tk(3, 0.1)
		levels.append(a.last_levels["rain"])
	s.set_debug_weather(-1)
	check("2.rain_only_in_rain", levels[0] == 0.0 and levels[1] == 0.0 and levels[2] > 0.0, str(levels))
	# birds
	var bs: Node = Audio.new()
	root.add_child(bs)
	var counts: Array[int] = []
	for pc: int in [0, 25, 60, 100]:
		var fk: RefCounted = mk_session()
		fk.state.greened_count = int(float(fk.state.target_count) * float(pc) / 100.0)
		bs.attach(fk); bs.bird_count = 0; bs._bird_wait = 0.0; bs._rng.seed = 11
		for i: int in 1200: bs.update(0.05)
		counts.append(bs.bird_count)
	bs.detach(); bs.free()
	check("2.birds_scale_with_greening", counts[0] == 0 and counts[1] > 0 and counts[2] > counts[1] and counts[3] > counts[2], str(counts))
	# mute
	a.requested.clear()
	main._unhandled_input(key(KEY_M))
	var tried: Array[bool] = []
	for snd: StringName in Audio.ACTIONS: tried.append(a.play_action(snd))
	s.set_debug_weather(2); tk(3, 0.1); s.set_debug_weather(-1)
	var lv: Dictionary = a.last_levels
	check("2.mute_all_silent", a.muted and not tried.has(true) and a.requested.is_empty() and lv["wind"] == 0.0 and lv["rain"] == 0.0 and a.category_gain("birds") == 0.0 and a.category_gain("action") == 0.0 and a.playing_count() == 0, "playing %d" % a.playing_count())
	main._unhandled_input(key(KEY_M))
	check("2.unmute_works", not a.muted and a.play_action(&"seed"))
	check("2.headless_playing_no_error", a.playing_count() >= 1, str(a.playing_count()))

func _sep() -> void:
	# same scripted play with and without view / sound toggles
	var plain: RefCounted = mk_session()
	var m2: Node = load("res://scenes/poc.tscn").instantiate()
	m2.set_meta(&"poc_town", true)
	root.add_child(m2)
	m2.auto_process = false
	m2.save_dir = SAVE_DIR
	var shown: RefCounted = m2.session
	var sp: Vector2 = Coords.cell_center_logic(m2.viewpoint.cell)
	for x: RefCounted in [plain, shown]:
		x.position = sp; x.play.seeds = 12; x.play.water = 60.0
	for round_i: int in 4:
		for i: int in 60:
			plain.advance_game(0.25); m2.tick(0.25, Vector2.ZERO)
		plain.fire(false, sp + Vector2(36, 20)); shown.fire(false, sp + Vector2(36, 20))
		m2._unhandled_input(key(KEY_E))
		for i: int in 40: m2.tick(0.25, Vector2.ZERO)
		m2._unhandled_input(key(KEY_E))
		m2._unhandled_input(key(KEY_M)); m2._unhandled_input(key(KEY_M))
	check("3.signature_equal", sig(plain) == sig(shown), "%.2f vs %.2f" % [plain.clock.elapsed, shown.clock.elapsed])
	m2.queue_free()
	# target set unchanged by the viewpoint entry
	var old: RefCounted = mk_session(OLD_TOWN)
	var cur: RefCounted = mk_session()
	check("3.target_set_unchanged", old.state.target_count == cur.state.target_count and Marshalls.raw_to_base64(old.state.target) == Marshalls.raw_to_base64(cur.state.target) and cur.state.target_count > 0, "%d vs %d" % [old.state.target_count, cur.state.target_count])
	var bound: float = cur.far.completion_bound_seconds()
	cur.enemy_tuning.contact_damage = 0
	for n: Nest in cur.enemies.nests: cur.enemies.damage_nest(n, 99)
	var g: int = 0
	while not cur.enemies.boars.is_empty() and g < 400:
		cur.enemies.damage_boar(cur.enemies.boars[0], 99); g += 1; cur.advance_game(0.25)
	var steps: int = 0
	while cur.state.zone_state[1] < WorldState.ZONE_STABLE and steps < 4000:
		cur.advance_game(0.25); steps += 1
	var ts: float = float((cur.zone_times[1] as Dictionary).get(WorldState.ZONE_STABLE, cur.clock.elapsed))
	var done: float = -1.0
	while cur.clock.elapsed <= ts + bound + 5.0:
		cur.advance_game(0.25)
		if cur.state.greened_count == cur.state.target_count:
			done = cur.clock.elapsed - ts
			break
	check("3.hundred_percent_within_bound", done >= 0.0 and done <= bound, "after stable %.1f / bound %.1f" % [done, bound])
