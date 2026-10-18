extends SceneTree
## WTH-01 logic checks (headless OK): godot --headless --path <repo> --script res://tests/poc/weather/logic.gd
## Weather schedule (clock-only, step independent, deterministic), sunlight factor, rain wetting, growth under every weather,
## save round trip / rejections, debug keys default off, 100 % within far.completion_bound_seconds(). Own save namespace
## user://poc_saves_test_weather/. Long conditions are fast-forwarded, each condition runs once. No OS-level input.
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const Weather: GDScript = preload("res://scripts/poc/environment/poc_weather.gd")
const Day: GDScript = preload("res://scripts/poc/environment/poc_day.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const DIR: String = "user://poc_saves_test_weather/"

var failures: int = 0
var passes: int = 0
var sessions: Array[RefCounted] = []

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
		print("PASS ", name, " ", detail)
	else:
		failures += 1
		print("FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func make_session() -> RefCounted:
	var size: Vector2i = Session.town_size()
	var s: RefCounted = Session.new(size.x, size.y)
	s.load_combat(Session.TOWN_SETUP)
	sessions.append(s)
	return s

func run_for(s: RefCounted, seconds: float, piece: float = 0.25) -> void:
	var left: float = seconds
	while left > 0.0:
		var step: float = minf(left, piece)
		s.advance_game(step)
		left -= step

## Puts the clock at game time `t` consistently (ticks follow the time), without running the simulation in between.
func set_time(s: RefCounted, t: float) -> void:
	s.clock.load_dict({"version": 1, "elapsed": t, "growth_ticks": int(t / s.clock.growth_period), "spread_ticks": int(t / s.clock.spread_period)})
	s.growth.ticks = s.clock.growth_ticks
	s.state.growth_tick = s.clock.growth_ticks
	s.weather.update(t)

## First time of the form `offset + 600 k` (same time of the game day) inside a settled segment of `type` (blend finished).
func find_time(w: RefCounted, type: int, offset: float, margin: float = 70.0) -> float:
	for k: int in 400:
		var t: float = offset + 600.0 * float(k)
		var index: int = w.index_at(t)
		var segment: Dictionary = w.segments[index]
		if index > 0 and int(segment["type"]) == type and t - float(segment["start"]) >= 25.0 and float(segment["start"]) + float(segment["duration"]) - t >= margin:
			return t
	return -1.0

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)
	_schedule()
	_clock_only()
	_sunlight()
	_rain_and_growth()
	_save()
	_debug_keys()
	var probe: RefCounted = Weather.new()
	var rain_start: float = 0.0
	probe.index_at(3000.0)
	for seg: Dictionary in probe.segments:
		if int(seg["type"]) == Weather.RAIN:
			rain_start = float(seg["start"])
			break
	_hundred_percent("from_start", 0.0)
	_hundred_percent("from_rain", maxf(rain_start - 10.0, 0.0))
	_hundred_percent("from_cloudy_night", find_time(probe, Weather.CLOUDY, 400.0, 100.0) - 20.0)
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)
	for s: RefCounted in sessions:
		s.close()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)

func _schedule() -> void:
	var a: RefCounted = Weather.new()
	var b: RefCounted = Weather.new()
	var seen: Dictionary = {}
	var same: bool = true
	var t: float = 0.0
	while t < 14400.0:
		var ta: int = a.type_at(t)
		seen[ta] = true
		if ta != b.type_at(14400.0 - t):
			pass
		t += 7.3
	# b queried in reverse order from far ahead: identical answers (no dependence on the query history)
	t = 14400.0
	while t > 0.0:
		if b.type_at(t) != Weather.new().type_at(t):
			same = false
		t -= 61.7
	var c: RefCounted = Weather.new()
	t = 0.0
	while t < 14400.0:
		if a.type_at(t) != c.type_at(t):
			same = false
		t += 13.1
	check("schedule.deterministic_any_query_order", same)
	check("schedule.all_three_weathers_in_4h", seen.has(Weather.CLEAR) and seen.has(Weather.CLOUDY) and seen.has(Weather.RAIN), str(seen.keys()))
	check("schedule.starts_clear", a.type_at(0.0) == Weather.CLEAR)
	var ok_range: bool = true
	var no_repeat: bool = true
	var rain_max: float = 0.0
	var rain_min: float = INF
	for i: int in a.segments.size():
		var seg: Dictionary = a.segments[i]
		var key: String = Weather.KEYS[int(seg["type"])]
		var range_: Array = a.tuning["durations"][key]
		if float(seg["duration"]) < float(range_[0]) - 0.0001 or float(seg["duration"]) > float(range_[1]) + 0.0001:
			ok_range = false
		if i > 0 and int(a.segments[i - 1]["type"]) == int(seg["type"]):
			no_repeat = false
		if int(seg["type"]) == Weather.RAIN:
			rain_max = maxf(rain_max, float(seg["duration"]))
			rain_min = minf(rain_min, float(seg["duration"]))
	check("schedule.durations_in_data_ranges", ok_range, "%d segments" % a.segments.size())
	check("schedule.no_same_weather_twice", no_repeat)
	check("schedule.rain_is_minutes_not_hours", rain_min >= 60.0 and rain_max <= 300.0, "rain %.0f..%.0f s" % [rain_min, rain_max])
	# levels blend smoothly between segments
	var first_change: float = float(a.segments[1]["start"])
	var before: Dictionary = a.levels_at(first_change - 0.01)
	var at: Dictionary = a.levels_at(first_change + 0.01)
	var settled: Dictionary = a.levels_at(first_change + 60.0)
	check("schedule.levels_blend_continuously", absf(float(before["overcast"]) - float(at["overcast"])) < 0.01 and absf(float(before["rain"]) - float(at["rain"])) < 0.01 and float(settled["overcast"]) == float(a.tuning["overcast"][Weather.KEYS[int(a.segments[1]["type"])]]), "%s -> %s" % [str(before), str(at)])

func _clock_only() -> void:
	var s1: RefCounted = make_session()
	var s2: RefCounted = make_session()
	run_for(s1, 700.0, 0.25)
	run_for(s2, 700.0, 0.0625)
	check("clock.same_elapsed_same_weather_any_step", absf(s1.clock.elapsed - s2.clock.elapsed) < 0.001 and s1.weather_type() == s2.weather_type() and JSON.stringify(s1.weather.to_dict()) == JSON.stringify(s2.weather.to_dict()), "%s %s" % [s1.weather_text(), JSON.stringify(s1.weather.to_dict())])
	s1.weather.update(s1.clock.elapsed)
	var before: String = JSON.stringify(s1.weather.to_dict())
	var rain_before: int = s1.rain_pulses
	s1.paused = true
	run_for(s1, 400.0)
	s1.weather.update(s1.clock.elapsed)
	check("clock.pause_freezes_weather", JSON.stringify(s1.weather.to_dict()) == before and s1.rain_pulses == rain_before)
	s1.paused = false
	# split independence of the whole result including rain wetting
	var s3: RefCounted = make_session()
	var s4: RefCounted = make_session()
	var t: float = find_time(s3.weather, Weather.RAIN, 100.0, 40.0)
	set_time(s3, t - 5.0)
	set_time(s4, t - 5.0)
	run_for(s3, 30.0, 0.25)
	run_for(s4, 30.0, 0.05)
	check("clock.rain_wetting_independent_of_step", s3.rain_pulses == s4.rain_pulses and s3.rain_wetted == s4.rain_wetted and s3.rain_pulses > 0, "%d/%d pulses, %d wetted" % [s3.rain_pulses, s4.rain_pulses, s3.rain_wetted])

func _sunlight() -> void:
	var s: RefCounted = make_session()
	var w: RefCounted = s.weather
	var day_max: float = float(s.env_tuning["sunlight"]["day_max"])
	var t_clear: float = find_time(w, Weather.CLEAR, 100.0)
	var t_cloudy: float = find_time(w, Weather.CLOUDY, 100.0)
	var t_rain: float = find_time(w, Weather.RAIN, 100.0)
	var t_night_clear: float = find_time(w, Weather.CLEAR, 400.0)
	check("sun.found_times", t_clear >= 0.0 and t_cloudy >= 0.0 and t_rain >= 0.0 and t_night_clear >= 0.0, "%s %s %s %s" % [t_clear, t_cloudy, t_rain, t_night_clear])
	set_time(s, t_clear)
	var f_clear: float = s.sunlight_factor()
	set_time(s, t_cloudy)
	var f_cloudy: float = s.sunlight_factor()
	set_time(s, t_rain)
	var f_rain: float = s.sunlight_factor()
	set_time(s, t_night_clear)
	var f_night: float = s.sunlight_factor()
	check("sun.clear_noon_is_maximum", absf(f_clear - day_max) < 0.0001 and f_clear > f_cloudy, "%.4f" % f_clear)
	check("sun.cloudy_rain_night_are_exactly_1", f_cloudy == 1.0 and f_rain == 1.0 and f_night == 1.0, "%.6f %.6f %.6f" % [f_cloudy, f_rain, f_night])
	var low: float = 10.0
	var t: float = 0.0
	while t < 7200.0:
		set_time(s, t)
		low = minf(low, s.sunlight_factor())
		t += 3.7
	check("sun.never_below_1_all_weather_all_hours", low >= 1.0, "min %.6f" % low)

func _first_target_index(s: RefCounted) -> int:
	for index: int in s.state.tile_count():
		if s.state.can_plant(index):
			return index
	return -1

func _rain_and_growth() -> void:
	# --- rain raises moisture of growing cells up to the cap; a clear day does not; mature cells are left alone
	var s: RefCounted = make_session()
	var cell: int = _first_target_index(s)
	var mature: int = -1
	for index: int in s.state.tile_count():
		if s.state.stage[index] == WorldState.STAGE_MATURE and s.state.target[index] == 1:
			mature = index
			break
	var t_rain: float = find_time(s.weather, Weather.RAIN, 100.0, 80.0)
	set_time(s, t_rain)
	s.state.set_stage(cell, WorldState.STAGE_SEED)
	var top: int = s.sim_tuning.moisture_max
	run_for(s, 3.0)
	var m3: int = s.state.moisture[cell]
	run_for(s, 50.0)
	var m50: int = s.state.moisture[cell]
	check("rain.raises_moisture", m3 > 0 and m50 >= m3 and m50 <= top, "%d -> %d (max %d)" % [m3, m50, top])
	check("rain.cap_respected_everywhere", s.state.moisture.size() > 0 and _max_moisture(s) <= top, "max %d" % _max_moisture(s))
	check("rain.mature_cells_untouched", mature < 0 or s.state.moisture[mature] == 0, "mature index %d" % mature)
	var s2: RefCounted = make_session()
	var cell2: int = _first_target_index(s2)
	set_time(s2, find_time(s2.weather, Weather.CLEAR, 100.0, 80.0))
	s2.state.set_stage(cell2, WorldState.STAGE_SEED)
	run_for(s2, 20.0)
	check("rain.clear_day_does_not_wet", s2.rain_pulses == 0 and s2.state.moisture[cell2] == 0, "pulses %d moisture %d" % [s2.rain_pulses, s2.state.moisture[cell2]])
	# --- gain per tick ordering: watered clear noon > watered cloud > dry; always >= 1
	s2.state.moisture[cell2] = top
	var gain_wet_clear: int = s2.growth.gain_for(cell2)
	s2.state.moisture[cell2] = 0
	var gain_dry_clear: int = s2.growth.gain_for(cell2)
	var s3: RefCounted = make_session()
	var cell3: int = _first_target_index(s3)
	set_time(s3, find_time(s3.weather, Weather.CLOUDY, 100.0, 40.0))
	s3.state.moisture[cell3] = top
	var gain_wet_cloudy: int = s3.growth.gain_for(cell3)
	s3.state.moisture[cell3] = 0
	var gain_dry_cloudy: int = s3.growth.gain_for(cell3)
	check("growth.watering_worth_more_on_a_clear_day", gain_wet_clear > gain_wet_cloudy and gain_wet_clear - gain_dry_clear > gain_wet_cloudy - gain_dry_cloudy, "clear %d/%d cloudy %d/%d" % [gain_wet_clear, gain_dry_clear, gain_wet_cloudy, gain_dry_cloudy])
	# --- growth is positive in the worst case: night, cloudy, dry
	var s4: RefCounted = make_session()
	var cell4: int = _first_target_index(s4)
	var worst: float = -1.0
	for k: int in 400:
		var t: float = 400.0 + 600.0 * float(k)
		var seg: Dictionary = s4.weather.segments[s4.weather.index_at(t)]
		if int(seg["type"]) == Weather.CLOUDY and float(seg["start"]) + float(seg["duration"]) - t > 20.0 and t - float(seg["start"]) > 25.0:
			worst = t
			break
	set_time(s4, worst)
	s4.state.set_stage(cell4, WorldState.STAGE_SEED)
	var g0: int = s4.state.growth[cell4]
	run_for(s4, 10.0)
	s4.growth.catch_up()
	check("growth.positive_night_cloudy_dry", worst >= 0.0 and s4.state.growth[cell4] > g0 and s4.growth.gain_for(cell4) >= 1, "growth %d -> %d, gain %d" % [g0, s4.state.growth[cell4], s4.growth.gain_for(cell4)])

func _max_moisture(s: RefCounted) -> int:
	var m: int = 0
	for v: int in s.state.moisture:
		m = maxi(m, v)
	return m

func write_json(data: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(DIR + PocSave.SLOT_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "", false, true))
	f.close()

func load_slot() -> Dictionary:
	return PocSave.load_slot(DIR, false, Callable(self, "make_session"))

func _save() -> void:
	var s: RefCounted = make_session()
	set_time(s, find_time(s.weather, Weather.RAIN, 100.0, 40.0) + 3.0)
	run_for(s, 2.0)
	var type_at_save: int = s.weather_type()
	var saved: Dictionary = PocSave.save(s, DIR)
	check("save.written", bool(saved["ok"]), str(saved.get("reason", "")))
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + PocSave.SLOT_FILE))
	check("save.has_weather_section", good.has("weather") and (good["weather"] as Dictionary).has("rng_state") and int(good["format_version"]) == PocSave.FORMAT_VERSION, JSON.stringify(good["weather"]))
	var loaded: Dictionary = load_slot()
	check("save.round_trip", bool(loaded["ok"]) and PocSave.signature(loaded["session"]) == PocSave.signature(s) and (loaded["session"] as RefCounted).weather_type() == s.weather_type(), str(loaded.get("reason", "")))
	if bool(loaded["ok"]):
		var t: RefCounted = loaded["session"]
		run_for(s, 120.0)
		run_for(t, 120.0)
		check("save.continues_identically", t.weather_type() == s.weather_type() and JSON.stringify(t.weather.to_dict()) == JSON.stringify(s.weather.to_dict()))
	# old file without the section still loads (the schedule follows from seed and clock)
	var old: Dictionary = good.duplicate(true)
	old.erase("weather")
	write_json(old)
	var r_old: Dictionary = load_slot()
	check("save.file_without_weather_loads", bool(r_old["ok"]) and (r_old["session"] as RefCounted).weather_type() == type_at_save, str(r_old.get("reason", "")))
	var mutations: Dictionary = {
		"type_out_of_range": ["type", 9],
		"prev_type_negative": ["prev_type", -1],
		"index_huge": ["index", 99999999],
		"index_negative": ["index", -3],
		"start_negative": ["start", -5.0],
		"duration_zero": ["duration", 0.0],
		"duration_huge": ["duration", 1.0e12],
		"rng_state_text": ["rng_state", "abc"],
		"rng_state_other": ["rng_state", "12345"],
		"seed_other": ["seed", "7"],
		"version_other": ["version", 5],
		"type_string": ["type", "rain"],
		"start_elsewhere": ["start", 99999.0],
	}
	for name: String in mutations:
		var bad: Dictionary = good.duplicate(true)
		(bad["weather"] as Dictionary)[mutations[name][0]] = mutations[name][1]
		write_json(bad)
		var r: Dictionary = load_slot()
		check("save.rejects_" + name, not bool(r["ok"]) and String(r["code"]) == "invalid", str(r.get("reason", "")))
	var missing: Dictionary = good.duplicate(true)
	(missing["weather"] as Dictionary).erase("rng_state")
	write_json(missing)
	check("save.rejects_missing_field", not bool(load_slot()["ok"]))
	var not_dict: Dictionary = good.duplicate(true)
	not_dict["weather"] = [1, 2]
	write_json(not_dict)
	check("save.rejects_wrong_container", not bool(load_slot()["ok"]))

func _debug_keys() -> void:
	var s: RefCounted = make_session()
	check("debug.session_default_off", not s.debug_weather_enabled)
	var main: Node = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	check("debug.main_default_off", not main.session.debug_weather_enabled)
	var press: Callable = func(code: Key) -> void:
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = code
		ev.pressed = true
		main._unhandled_input(ev)
	press.call(KEY_3)
	press.call(KEY_2)
	check("debug.keys_ignored_by_default", main.session.weather.override_type == -1)
	main.session.debug_weather_enabled = true
	press.call(KEY_3)
	var raining: bool = main.session.weather_type() == Weather.RAIN and main.env_view.last_weather["rain"] == 1.0
	press.call(KEY_1)
	var clear: bool = main.session.weather_type() == Weather.CLEAR
	press.call(KEY_0)
	check("debug.keys_work_when_enabled", raining and clear and main.session.weather.override_type == -1)
	main.tick(0.05, Vector2.ZERO)
	check("debug.hud_shows_weather", main.hud.text.contains("天気 " + main.session.weather_text()), main.hud.text.split("\n")[1])
	root.remove_child(main)
	main.free()

func _hundred_percent(label: String, start_time: float) -> void:
	var s: RefCounted = make_session()
	if start_time > 0.0:
		set_time(s, start_time)
	s.enemy_tuning.contact_damage = 0
	var bound: float = s.far.completion_bound_seconds()
	for nest: Nest in s.enemies.nests:
		s.enemies.damage_nest(nest, 99)
	var guard: int = 0
	while not s.enemies.boars.is_empty() and guard < 400:
		s.enemies.damage_boar(s.enemies.boars[0], 99)
		guard += 1
		s.advance_game(0.25)
	var steps: int = 0
	var kinds: Dictionary = {}
	while s.state.zone_state[1] < WorldState.ZONE_STABLE and steps < 4000:
		s.advance_game(0.25)
		kinds[s.weather_type()] = true
		steps += 1
	var t_stable: float = float((s.zone_times[1] as Dictionary).get(WorldState.ZONE_STABLE, s.clock.elapsed))
	var limit: float = t_stable + bound
	var t_done: float = -1.0
	var wet_run: int = s.rain_pulses
	while s.clock.elapsed <= limit + 5.0:
		s.advance_game(0.25)
		kinds[s.weather_type()] = true
		if s.state.greened_count == s.state.target_count:
			t_done = s.clock.elapsed - t_stable
			break
	check("hundred." + label + ".exact_100_within_bound_with_weather", t_done >= 0.0 and t_done <= bound, "after stable %.1f s of bound %.1f s, greened %d/%d, weathers seen %s, rain pulses %d" % [t_done, bound, s.state.greened_count, s.state.target_count, str(kinds.keys()), s.rain_pulses])
