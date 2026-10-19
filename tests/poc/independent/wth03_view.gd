extends SceneTree
## WTH-03 independent: viewpoint stops everything, no bulk catch-up on return, hint cleared while viewing, no progress while real time passes.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const Audio: GDScript = preload("res://scripts/poc/audio/poc_audio.gd")
const SETTINGS: String = "user://wth03_ind_settings.json"
const SAVE_DIR: String = "user://wth03_ind_save/"
const OUT: String = "res://evidence/weather/03/independent/"
var fails: int = 0
var passes: int = 0
var lines: PackedStringArray = PackedStringArray()
var main: Node
var s: RefCounted

func check(name: String, ok: bool, detail: String = "") -> void:
	var l: String = "%s %s %s" % ["PASS" if ok else "FAIL", name, detail]
	print(l); lines.append(l)
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

func sig() -> String:
	var sn: Dictionary = s.snapshot()
	sn.erase("paused"); sn.erase("multiplier")
	var boars: Array = []
	for b: Boar in s.enemies.boars: boars.append([b.id, b.pos.x, b.pos.y, b.hp])
	return JSON.stringify([sn, boars, s.helpers.plants, s.helpers.flights, s.helpers.pickups, s.helpers.time, s.play.pickups.count(), hash(s.state.stage), hash(s.state.moisture), hash(s.state.growth), s.weather_type(), s.clock.elapsed, s.position.x, s.position.y])

func tk(n: int, d: float = 0.25, dir: Vector2 = Vector2.ZERO) -> void:
	for i: int in n: main.tick(d, dir)

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
	var v: RefCounted = main.viewpoint
	# bring the world to a busy moment: rain (first rain at 1520 s), boars, a helper plant with flights
	s.advance_game(1545.0)
	s.helpers.add_seeds(4)
	var best: Vector2i = Vector2i(-9999, -9999)
	var bscore: int = 0
	for oy: int in range(40, 140):
		for ox: int in range(40, 140):
			var o: Vector2i = Vector2i(ox, oy)
			var c0: Vector2 = s.helpers.block_center_px(o)
			if not bool(s.helpers.evaluate("gatlinger", o, c0)["ok"]): continue
			var n: int = 0
			for y: int in range(o.y - 8, o.y + 12):
				for x: int in range(o.x - 8, o.x + 12):
					if s.state.in_bounds(x, y) and Vector2((x + 0.5) * 4.0, (y + 0.5) * 4.0).distance_to(c0) <= 60.0 and s.state.can_plant(s.state.index_of(x, y)): n += 1
			if n > bscore:
				bscore = n; best = o
	var bc: Vector2 = s.helpers.block_center_px(best)
	s.position = bc + Vector2(0, 12)
	while s.helper_mode != -1: s.cycle_helper_mode()
	var g: int = 0
	while s.helper_active_kind() != "gatlinger" and g < 6:
		s.cycle_helper_mode(); g += 1
	var pr: Dictionary = s.place_helper(bc)
	s.end_helper_mode()
	var t0: float = s.clock.elapsed
	while s.helpers.flights.is_empty() and s.clock.elapsed - t0 < 60.0: s.advance_game(0.05)
	check("v.busy_world", s.weather_type() == 2 and s.enemies.boars.size() > 0 and not s.helpers.flights.is_empty(), "place=%s rain=%d boars=%d flights=%d" % [pr["ok"], s.weather_type(), s.enemies.boars.size(), s.helpers.flights.size()])
	# walk to the spot (set position: the walk itself was checked by WTH-02), hint appears, enter
	s.position = Coords.cell_center_logic(v.cell) + Vector2(14, 0)
	tk(2, 0.1)
	var hint_before: String = main.notice.text
	main.show_notice("E：テスト案内")
	check("v.notice_visible_before", main.notice.text != "" and main.notice_time > 0.0, "text='%s'" % main.notice.text)
	main._unhandled_input(key(KEY_E))
	check("v.entered", main.is_viewing() and s.paused, "viewing=%s paused=%s" % [main.is_viewing(), s.paused])
	check("v.notice_cleared_on_enter", main.notice.text == "" and main.notice_time == 0.0, "text='%s'" % main.notice.text)
	var a: String = sig()
	var a_time: float = s.clock.elapsed
	# everything the player can do while viewing + ticks + real time
	s.multiplier = 16.0
	main._unhandled_input(key(KEY_F3))
	main._unhandled_input(key(KEY_Q))
	main._unhandled_input(key(KEY_TAB))
	main._unhandled_input(click(MOUSE_BUTTON_LEFT, Vector2(900, 400)))
	main._unhandled_input(click(MOUSE_BUTTON_RIGHT, Vector2(900, 400)))
	tk(400, 0.25, Vector2(1, 0))
	OS.delay_msec(1500)
	tk(40, 0.25)
	s.advance(10.0)
	s.advance_game(5.0)
	var b: String = sig()
	check("v.world_frozen_in_view", a == b, "elapsed %.3f -> %.3f" % [a_time, s.clock.elapsed])
	check("v.notice_still_empty_in_view", main.notice.text == "", "text='%s'" % main.notice.text)
	check("v.panel_shown", main.view_panel.visible and main.viewpoint.panel_text(s).length() > 10, main.viewpoint.panel_text(s).replace("\n", " | "))
	# save refused in view
	var sv: Dictionary = main.save_game() if main.has_method("save_game") else {"ok": null}
	check("v.save_refused_in_view", not bool(sv.get("ok", false)), str(sv.get("code", sv.get("reason", "?"))))
	# leave
	main._unhandled_input(key(KEY_ESCAPE))
	check("v.left", not main.is_viewing() and not s.paused, "viewing=%s paused=%s" % [main.is_viewing(), s.paused])
	check("v.no_catchup_on_return", s.clock.elapsed == a_time and sig() == a, "elapsed %.3f vs %.3f" % [s.clock.elapsed, a_time])
	s.multiplier = 1.0
	tk(4, 0.25)
	check("v.resumes_normally", absf(s.clock.elapsed - a_time - 1.0) < 0.001, "advanced %.3f for 1.0 s of ticks" % (s.clock.elapsed - a_time))
	# was the world moving outside the view (control)?
	check("v.control_world_moves", sig() != a)
	# prior pause state restored: pause, enter, leave -> still paused
	s.position = Coords.cell_center_logic(v.cell) + Vector2(14, 0)
	s.paused = true
	var pe: bool = main.enter_viewpoint()
	var pl: bool = main.leave_viewpoint()
	check("v.prior_pause_restored", pe and pl and s.paused, "enter=%s leave=%s paused=%s" % [pe, pl, s.paused])
	s.paused = false
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var f: FileAccess = FileAccess.open(OUT + "view.log", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\nRESULT passes=%d failures=%d\n" % [passes, fails])
	f.close()
	print("RESULT passes=%d fails=%d" % [passes, fails])
	quit(1 if fails > 0 else 0)
