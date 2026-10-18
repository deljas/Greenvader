extends SceneTree
## WTH-02 logic checks (headless OK): godot --headless --path <repo> --script res://tests/poc/view/logic.gd
## Viewpoint (enter near / not far, world stopped and nothing banked, clicks are not game input, panel values = session, camera back),
## sounds (which sound each operation requested, mute silences every category, calm drops action sounds, headless playback),
## display/sound do not change the simulation signature, 100 % still within far.completion_bound_seconds() on the changed town_01.
## Injected engine events only (no OS-level input). Own sound-setting file and save namespace; each condition runs once.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const Audio: GDScript = preload("res://scripts/poc/audio/poc_audio.gd")
const Day: GDScript = preload("res://scripts/poc/environment/poc_day.gd")
const SETTINGS: String = "user://poc_ui_settings_test_view.json"

var failures: int = 0
var passes: int = 0
var main: Node
var s: RefCounted
var sessions: Array[RefCounted] = []

func check(name: String, ok: bool, detail: String = "") -> void:
	print("PASS " if ok else "FAIL ", name, " ", detail)
	if ok:
		passes += 1
	else:
		failures += 1

func _init() -> void:
	_run.call_deferred()

func key(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event

func click(button: MouseButton, at: Vector2) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = at
	return event

func make_session() -> RefCounted:
	var size: Vector2i = Session.town_size()
	var made: RefCounted = Session.new(size.x, size.y)
	made.load_combat(Session.TOWN_SETUP)
	sessions.append(made)
	return made

func make_main() -> Node:
	var node: Node = load("res://scenes/poc.tscn").instantiate()
	node.set_meta(&"poc_town", true)
	root.add_child(node)
	node.auto_process = false
	node.window_size_override = Vector2i(1920, 1080)
	return node

func tick_n(count: int, delta: float = 0.25) -> void:
	for i: int in count:
		main.tick(delta, Vector2.ZERO)

func req(audio: Node) -> String:
	return ",".join(PackedStringArray(Array(audio.requested).map(func(n: StringName) -> String: return String(n))))

func at_spot() -> void:
	s.position = Coords.cell_center_logic(main.viewpoint.cell)

## Everything that moves in the simulation, as one text (clock, ticks, weather, shots, enemies, plants, saved state).
func world_text() -> String:
	return JSON.stringify([s.clock.elapsed, s.clock.growth_ticks, s.clock.spread_ticks, s.weather_text(), s.projectiles.shots, s.enemies.to_dict(), PocSave.signature(s)])

func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	Audio.use_settings_path(SETTINGS)
	main = make_main()
	await process_frame
	await process_frame
	s = main.session
	_spot()
	_enter_and_freeze()
	_clicks_and_panel()
	await _camera_and_leave()
	await _sounds()
	_mute()
	_signature()
	_hundred_percent()
	main.queue_free()
	await process_frame
	for made: RefCounted in sessions:
		made.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)

func _spot() -> void:
	var v: RefCounted = main.viewpoint
	check("spot.exists_in_town_data", v.has_spot and v.cell == Vector2i(78, 76), "%s %s" % [v.cell, v.spot_name])
	check("spot.cell_walkable_and_in_start_zone", s.state.is_walkable(v.cell.x, v.cell.y) and s.state.zone_at(s.state.index_of(v.cell.x, v.cell.y)) == 0)
	# walkable path from the player start (BFS over walkable cells)
	var start: Vector2i = Coords.logic_to_cell(s.position)
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n) and s.state.in_bounds(n.x, n.y) and s.state.is_walkable(n.x, n.y):
				seen[n] = true
				queue.append(n)
	check("spot.reachable_by_walking_from_start", seen.has(v.cell))
	check("spot.marker_in_world", main.viewpoint_view != null and main.viewpoint_view.get_child_count() >= 3)
	var far_pos: Vector2 = Coords.cell_center_logic(v.cell) + Vector2(60.0, 0.0)
	s.position = far_pos
	main._unhandled_input(key(KEY_E))
	check("spot.far_e_does_not_enter", not main.is_viewing() and not s.paused)
	s.position = Coords.cell_center_logic(v.cell) + Vector2(15.0, 0.0)
	check("spot.radius_edge_1p5m_inside", v.is_near(s.position) and not v.is_near(Coords.cell_center_logic(v.cell) + Vector2(19.0, 0.0)))

func _enter_and_freeze() -> void:
	at_spot()
	s.play.seeds = 5
	s.multiplier = 4.0
	main.tick(0.0, Vector2.ZERO)
	s.set_aim(s.position + Vector2(40.0, 0.0))
	var fired: Dictionary = s.fire(false, s.position + Vector2(40.0, 0.0))
	check("freeze.shot_in_flight_before", bool(fired["ok"]) and s.projectiles.shots.size() == 1)
	tick_n(2, 0.05)
	var before: String = world_text()
	var boars_before: int = s.enemies.boars.size()
	main._unhandled_input(key(KEY_E))
	check("enter.e_at_spot_enters_and_pauses", main.is_viewing() and s.paused and main.view_panel.visible)
	var elapsed: float = s.clock.elapsed
	tick_n(60, 0.25)
	check("freeze.clock_enemies_growth_weather_shots_unchanged", world_text() == before and s.enemies.boars.size() == boars_before, "elapsed %.2f" % s.clock.elapsed)
	# walking keys do nothing either
	var pos: Vector2 = s.position
	main.tick(0.25, Vector2(1, 0))
	check("freeze.player_does_not_walk", s.position == pos)
	main._unhandled_input(key(KEY_ESCAPE))
	check("leave.esc_returns_without_menu", not main.is_viewing() and not s.paused and main.menu == &"" and not main.view_panel.visible)
	s.multiplier = 1.0
	main.tick(0.25, Vector2.ZERO)
	check("leave.no_stopped_time_added", absf(s.clock.elapsed - elapsed - 0.25) < 0.0001, "advanced %.4f s in one 0.25 s frame after 15 s of stop" % (s.clock.elapsed - elapsed))
	main._unhandled_input(key(KEY_E))
	main._unhandled_input(key(KEY_E))
	check("leave.e_returns_too", not main.is_viewing())
	# a player pause (button) found before is restored
	main.toggle_pause()
	main._unhandled_input(key(KEY_E))
	var viewing_in_pause: bool = main.is_viewing()
	main._unhandled_input(key(KEY_ESCAPE))
	check("leave.restores_prior_player_pause", viewing_in_pause and not main.is_viewing() and s.paused and main.menu == &"")
	main.toggle_pause()
	check("leave.pause_released_normally", not s.paused)

func _clicks_and_panel() -> void:
	at_spot()
	s.play.seeds = 5
	s.play.water = 50.0
	# a known time and weather
	s.clock.load_dict({"version": 1, "elapsed": 330.0, "growth_ticks": int(330.0 / s.clock.growth_period), "spread_ticks": int(330.0 / s.clock.spread_period)})
	s.growth.ticks = s.clock.growth_ticks
	s.state.growth_tick = s.clock.growth_ticks
	s.set_debug_weather(2)
	main.tick(0.0, Vector2.ZERO)
	main._unhandled_input(key(KEY_E))
	var launched: int = s.projectiles.launched
	var seeds: int = s.play.seeds
	var water: float = s.play.water
	main._unhandled_input(click(MOUSE_BUTTON_LEFT, Vector2(320, 180)))
	main._unhandled_input(click(MOUSE_BUTTON_RIGHT, Vector2(300, 170)))
	var shot: Dictionary = main.click_fire(Vector2(320, 180), false)
	var placed: Dictionary = main.click_place(Vector2(320, 180))
	main._unhandled_input(key(KEY_Q))
	var kept_helper_mode: bool = s.helper_mode == -1
	check("view.clicks_and_keys_are_not_game_input", s.projectiles.launched == launched and s.play.seeds == seeds and s.play.water == water and not bool(shot["ok"]) and not bool(placed["ok"]) and kept_helper_mode, "%s / %s" % [shot, placed.get("code")])
	check("view.no_save_while_viewing", not bool(main.save_game()["ok"]) and not main.is_viewing() == false)
	var values: Dictionary = main.viewpoint.panel_values(s)
	var text: String = main.view_panel.label.text
	check("panel.values_equal_session", int(values["percent"]) == s.greening_percent() and int(values["greened"]) == s.state.greened_count and int(values["targets"]) == s.state.target_count and String(values["weather"]) == s.weather_text() and String(values["clock"]) == Day.clock_text(s.day_hour()), str(values))
	check("panel.text_japanese_with_rate_time_weather", text.contains("内部緑化率 %d％" % s.greening_percent()) and text.contains(String(values["clock"])) and text.contains("雨") and text.contains("展望"), text.replace("\n", " / "))
	main._unhandled_input(key(KEY_ESCAPE))
	s.set_debug_weather(-1)

func _camera_and_leave() -> void:
	at_spot()
	s.play.seeds = 5
	main.tick(0.0, Vector2.ZERO)
	var size_before: float = main.camera.size
	var pos_before: Vector3 = main.camera.position
	check("camera.normal_size_before", is_equal_approx(size_before, Config.CAMERA_SIZE_M))
	main._unhandled_input(key(KEY_E))
	main.tick(0.1, Vector2.ZERO)
	check("camera.view_size_wider_same_angle", is_equal_approx(main.camera.size, main.viewpoint.camera_size()) and main.camera.size > Config.CAMERA_SIZE_M and is_equal_approx(main.camera.rotation_degrees.x, -Config.ELEVATION_DEG) and main.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "size %.1f rot %s" % [main.camera.size, main.camera.rotation_degrees])
	for index: int in Config.RESOLUTIONS.size():
		main.set_resolution(index, Vector2i(1920, 1080))
		main.tick(0.0, Vector2.ZERO)
		var res: Vector2i = Config.RESOLUTIONS[index]
		var margin: float = 4.0
		var inside: bool = true
		for corner: Vector2 in [Vector2(0, 0), Vector2(112, 0), Vector2(0, 112), Vector2(112, 112)]:
			var ground: Vector2 = Coords.cell_center_ground(Vector2i(int(corner.x), int(corner.y)))
			var px: Vector2 = main.camera.unproject_position(Vector3(ground.x, 1.0, ground.y))
			inside = inside and px.x >= margin and px.y >= margin and px.x <= float(res.x) - margin and px.y <= float(res.y) - margin
		check("camera.view_%dx%d_whole_town_in_frame_integer_nearest" % [res.x, res.y], inside and main.render_view.size == res and main.view_rect.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and Config.integer_scale(res, Vector2i(1920, 1080)) >= 1 and main.is_viewing() and is_equal_approx(main.camera.size, main.viewpoint.camera_size()) and main.view_panel.visible)
	main.set_resolution(0, Vector2i(1920, 1080))
	main._unhandled_input(key(KEY_E))
	main.tick(0.0, Vector2.ZERO)
	check("leave.camera_size_and_follow_restored", is_equal_approx(main.camera.size, size_before) and main.camera.position.is_equal_approx(pos_before), "%s vs %s" % [main.camera.position, pos_before])
	# the camera follows the player again after leaving
	s.position += Vector2(40.0, 0.0)
	main.tick(0.0, Vector2.ZERO)
	check("leave.camera_follows_player_again", not main.camera.position.is_equal_approx(pos_before))
	s.position -= Vector2(40.0, 0.0)
	main.tick(0.0, Vector2.ZERO)

func _sounds() -> void:
	var audio: Node = main.audio
	check("audio.built_headless_no_error", audio != null and audio.playing_count() >= 1, "players playing %d" % audio.playing_count())
	audio.requested.clear()
	at_spot()
	s.position += Vector2(40.0, 0.0)
	s.play.seeds = 9
	s.play.water = 80.0
	main.tick(0.0, Vector2.ZERO)
	audio._last_seeds = s.play.seeds # direct test writes do not emit the signal
	audio.requested.clear()
	var seed_shot: Dictionary = main.click_fire(main.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(s.position + Vector2(-30.0, 14.0)), 0.0)), false)
	var water_shot: Dictionary = main.click_fire(main.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(s.position + Vector2(-26.0, 16.0)), 0.0)), true)
	check("audio.seed_and_water_requested", bool(seed_shot["ok"]) and bool(water_shot["ok"]) and req(audio) == "seed,water", str(audio.requested))
	var empty_seeds: int = s.play.seeds
	s.play.seeds = 0
	audio.requested.clear()
	main.click_fire(Vector2(320, 100), false)
	check("audio.failed_shot_is_silent", audio.requested.is_empty())
	s.play.seeds = empty_seeds
	audio._last_seeds = empty_seeds
	s.play.add_seeds(1)
	check("audio.pickup_on_seed_gain", req(audio) == "pickup", str(audio.requested))
	# helper placement through the normal click path
	audio.requested.clear()
	var origin: Vector2i = Vector2i(-1, -1)
	var around: Vector2i = Coords.logic_to_cell(s.position)
	for oy: int in range(around.y - 8, around.y + 8):
		for ox: int in range(around.x - 8, around.x + 8):
			var ok: bool = origin.x < 0
			for y: int in range(oy, oy + 4):
				for x: int in range(ox, ox + 4):
					var i: int = s.state.index_of(x, y)
					ok = ok and s.state.is_walkable(x, y) and s.state.target[i] == 1 and s.state.occupant[i] == 0 and s.state.stage[i] == WorldState.STAGE_MATURE
			if ok:
				origin = Vector2i(ox, oy)
	var centre: Vector2 = s.helpers.block_center_px(origin)
	s.position = centre + Vector2(8.0, 0.0)
	s.helpers.seeds = 6
	main.tick(0.0, Vector2.ZERO)
	main._unhandled_input(key(KEY_Q))
	main._unhandled_input(click(MOUSE_BUTTON_LEFT, main.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(centre)))))
	check("audio.place_requested", origin.x >= 0 and s.helpers.plants.size() == 1 and req(audio) == "place", str(audio.requested))
	main._unhandled_input(key(KEY_Q))
	while s.helper_mode >= 0:
		main._unhandled_input(key(KEY_Q))
	# enemy hit through a real shot at a boar standing next to the player
	audio.requested.clear()
	for boar: Boar in s.enemies.boars.duplicate():
		s.enemies.boars.erase(boar)
	var boar_: Boar = Boar.new()
	boar_.id = 9500
	boar_.zone = s.player_zone()
	boar_.hp = 3
	boar_.pos = s.position + Vector2(24.0, 0.0)
	s.enemies.boars.append(boar_)
	s.enemy_tuning.contact_damage = 0
	s.play.seeds = 9
	s.fire(false, boar_.pos)
	var guard: int = 0
	while s.combat.hits == 0 and guard < 40:
		main.tick(0.1, Vector2.ZERO)
		boar_.pos = s.position + Vector2(24.0, 0.0)
		guard += 1
	check("audio.enemy_hit_requested", s.combat.hits > 0 and audio.requested.has(&"hit"), "hits %d %s" % [s.combat.hits, str(audio.requested)])
	# nests and zone: the real destroy path
	audio.requested.clear()
	for nest: Nest in s.enemies.nests:
		s.enemies.damage_nest(nest, 99)
	var nests: int = audio.requested.count(&"nest")
	check("audio.nest_break_and_zone_change_requested", nests == 3 and audio.requested.has(&"zone"), str(audio.requested))
	# calm drops action sounds, ambient is softened
	var normal_wind: float = audio.last_levels["wind"]
	audio.requested.clear()
	var dropped: int = audio.dropped_calm
	main._unhandled_input(key(KEY_E)) if main.viewpoint.is_near(s.position) else at_spot()
	at_spot()
	main._unhandled_input(key(KEY_E))
	var played_in_view: bool = audio.play_action(&"seed")
	main.tick(0.1, Vector2.ZERO)
	check("audio.viewpoint_drops_action_sounds_and_softens_ambient", main.is_viewing() and not played_in_view and audio.requested.is_empty() and audio.dropped_calm == dropped + 1 and audio.last_levels["wind"] < normal_wind, "wind %.3f -> %.3f" % [normal_wind, audio.last_levels["wind"]])
	main._unhandled_input(key(KEY_ESCAPE))
	s.paused = true
	var played_paused: bool = audio.play_action(&"water")
	s.paused = false
	check("audio.pause_drops_action_sounds", not played_paused)
	# ambient: rain follows the weather, birds follow the greening
	s.set_debug_weather(2)
	for i: int in 3:
		main.tick(0.1, Vector2.ZERO)
	var rain_on: float = audio.last_levels["rain"]
	s.set_debug_weather(0)
	main.tick(0.1, Vector2.ZERO)
	var rain_off: float = audio.last_levels["rain"]
	s.set_debug_weather(-1)
	check("audio.rain_only_when_raining", rain_on > 0.05 and rain_off == 0.0, "%.3f vs %.3f" % [rain_on, rain_off])
	var bird_session: Node = Audio.new()
	root.add_child(bird_session)
	var counts: Array[int] = []
	for percent: int in [0, 50, 100]:
		var fake: RefCounted = make_session()
		fake.state.greened_count = int(float(fake.state.target_count) * float(percent) / 100.0)
		bird_session.attach(fake)
		bird_session.bird_count = 0
		bird_session._bird_wait = 0.0
		bird_session._rng.seed = 5
		for i: int in 1200:
			bird_session.update(0.05)
		counts.append(bird_session.bird_count)
	bird_session.detach()
	bird_session.free()
	check("audio.birds_more_often_when_greener", counts[0] == 0 and counts[1] > 0 and counts[2] > counts[1], str(counts))

func _mute() -> void:
	var audio: Node = main.audio
	audio.requested.clear()
	var started: int = audio.started_count
	main._unhandled_input(key(KEY_M))
	var muted_now: bool = audio.muted
	var tried: Array[bool] = []
	for sound: StringName in Audio.ACTIONS:
		tried.append(audio.play_action(sound))
	s.set_debug_weather(2)
	main.tick(0.1, Vector2.ZERO)
	s.set_debug_weather(-1)
	var levels: Dictionary = audio.last_levels
	check("mute.m_toggles_and_every_category_silent", muted_now and not tried.has(true) and audio.started_count == started and audio.requested.is_empty() and float(levels["wind"]) == 0.0 and float(levels["rain"]) == 0.0 and audio.category_gain("action") == 0.0 and audio.category_gain("birds") == 0.0 and audio.playing_count() == 0, "playing %d" % audio.playing_count())
	check("mute.saved_as_ui_setting", FileAccess.file_exists(SETTINGS) and bool((JSON.parse_string(FileAccess.get_file_as_string(SETTINGS)) as Dictionary)["muted"]))
	var again: Node = Audio.new()
	root.add_child(again)
	check("mute.restored_on_next_start", again.muted and again.playing_count() == 0)
	again.free()
	main._unhandled_input(key(KEY_M))
	check("mute.m_again_unmutes", not audio.muted and audio.play_action(&"seed"))
	# M must not collide with another action
	var owners: int = 0
	for action: StringName in InputMap.get_actions():
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_M:
				owners += 1
	check("input.m_only_poc_mute", owners == 1 and InputMap.has_action(&"poc_mute"), "owners=%d" % owners)

func _signature() -> void:
	# The same scripted play with and without the display/sound layer (view entered and left in between) ends identical.
	var plain: RefCounted = main.make_session()
	sessions.append(plain)
	var shown_main: Node = make_main()
	await_free(shown_main)
	var shown: RefCounted = shown_main.session
	var script_steps: Array = [[0, 40], [1, 0], [0, 80], [2, 0], [0, 120]]
	var spot: Vector2 = Coords.cell_center_logic(shown_main.viewpoint.cell)
	plain.position = spot
	shown.position = spot
	for session_: RefCounted in [plain, shown]:
		session_.play.seeds = 12
		session_.play.water = 60.0
	for step: Array in script_steps:
		var kind: int = step[0]
		if kind == 0:
			for i: int in int(step[1]):
				plain.advance_game(0.25)
				shown_main.tick(0.25, Vector2.ZERO)
		elif kind == 1:
			plain.fire(false, spot + Vector2(36.0, 20.0))
			shown.fire(false, spot + Vector2(36.0, 20.0))
		else:
			# the panorama is entered and left, the sound is muted and unmuted: no effect on the simulation
			shown_main._unhandled_input(key(KEY_E))
			for i: int in 30:
				shown_main.tick(0.25, Vector2.ZERO)
			shown_main._unhandled_input(key(KEY_ESCAPE))
			shown_main._unhandled_input(key(KEY_M))
			shown_main._unhandled_input(key(KEY_M))
	check("signature.same_with_and_without_view_and_sound", PocSave.signature(plain) == PocSave.signature(shown), "elapsed %.2f vs %.2f" % [plain.clock.elapsed, shown.clock.elapsed])
	shown_main.queue_free()

func await_free(_node: Node) -> void:
	pass

func _hundred_percent() -> void:
	var made: RefCounted = make_session()
	made.enemy_tuning.contact_damage = 0
	var bound: float = made.far.completion_bound_seconds()
	for nest: Nest in made.enemies.nests:
		made.enemies.damage_nest(nest, 99)
	var guard: int = 0
	while not made.enemies.boars.is_empty() and guard < 400:
		made.enemies.damage_boar(made.enemies.boars[0], 99)
		guard += 1
		made.advance_game(0.25)
	var steps: int = 0
	while made.state.zone_state[1] < WorldState.ZONE_STABLE and steps < 4000:
		made.advance_game(0.25)
		steps += 1
	var t_stable: float = float((made.zone_times[1] as Dictionary).get(WorldState.ZONE_STABLE, made.clock.elapsed))
	var done: float = -1.0
	while made.clock.elapsed <= t_stable + bound + 5.0:
		made.advance_game(0.25)
		if made.state.greened_count == made.state.target_count:
			done = made.clock.elapsed - t_stable
			break
	check("hundred.exact_100_within_bound_on_changed_town", done >= 0.0 and done <= bound, "after stable %.1f s of bound %.1f s, greened %d/%d" % [done, bound, made.state.greened_count, made.state.target_count])
