extends SceneTree
## WTH-01 independent verification (logic): conditions 1,2,3,4,6. Own save namespace user://poc_saves_indep_wth01/.
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const Weather: GDScript = preload("res://scripts/poc/environment/poc_weather.gd")
const Day: GDScript = preload("res://scripts/poc/environment/poc_day.gd")
const DIR: String = "user://poc_saves_indep_wth01/"
const OUT: String = "res://evidence/weather/01/independent/"
var passes: int = 0
var fails: int = 0
var lines: PackedStringArray = PackedStringArray()
var keep: Array[RefCounted] = []

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok: passes += 1
	else: fails += 1
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", name, detail]
	lines.append(line)
	print(line)

func _init() -> void:
	_run.call_deferred()

func mk() -> RefCounted:
	var size: Vector2i = Session.town_size()
	var m: RefCounted = Session.new(size.x, size.y)
	m.paving = Session.paving_from(m.env_tuning)
	m.load_combat(Session.TOWN_SETUP)
	keep.append(m)
	return m

func jump(m: RefCounted, t: float) -> void:
	m.clock.load_dict({"version": 1, "elapsed": t, "growth_ticks": int(t / m.clock.growth_period), "spread_ticks": int(t / m.clock.spread_period)})
	m.growth.ticks = m.clock.growth_ticks
	m.state.growth_tick = m.clock.growth_ticks
	m.weather.update(t)

func run_for(m: RefCounted, sec: float, piece: float = 0.25) -> void:
	var left: float = sec
	while left > 0.0:
		var p: float = minf(left, piece)
		m.advance_game(p)
		left -= p

func seq(w: RefCounted, t0: float, t1: float, dt: float) -> Array:
	var a: Array = []
	var t: float = t0
	while t <= t1:
		a.append(w.type_at(t))
		t += dt
	return a

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f: String in DirAccess.get_files_at(DIR): DirAccess.remove_absolute(DIR + f)
	_c1()
	_c2()
	_c4()
	_c6()
	_c3()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var f: FileAccess = FileAccess.open(OUT + "logic.log", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\nRESULT passes=%d failures=%d\n" % [passes, fails])
		f.close()
	for f2: String in DirAccess.get_files_at(DIR): DirAccess.remove_absolute(DIR + f2)
	print("RESULT passes=%d failures=%d" % [passes, fails])
	for m: RefCounted in keep: m.close()
	quit(1 if fails > 0 else 0)

func _c1() -> void:
	var a: RefCounted = Weather.new()
	var b: RefCounted = Weather.new()
	var fwd: Array = seq(a, 0.0, 6000.0, 7.0)
	# other instance, reverse order and random order queries
	var rev: Array = []
	var t: float = 6000.0 - fposmod(6000.0, 7.0)
	var times: Array = []
	var x: float = 0.0
	while x <= 6000.0:
		times.append(x)
		x += 7.0
	var shuffled: Array = times.duplicate()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	for i: int in range(shuffled.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	var map: Dictionary = {}
	for tt: float in shuffled: map[tt] = b.type_at(tt)
	var same: bool = true
	for i: int in times.size():
		if int(map[times[i]]) != int(fwd[i]): same = false
	check("c1.same_elapsed_same_weather_any_query_order", same, "%d samples" % times.size())
	var kinds: Dictionary = {}
	for v: Variant in fwd: kinds[v] = true
	check("c1.all_three_weathers_occur", kinds.size() == 3, str(kinds.keys()))
	# sessions with different stepping
	var s1: RefCounted = mk()
	var s2: RefCounted = mk()
	var tr1: Array = []
	var tr2: Array = []
	for i: int in 160:
		run_for(s1, 10.0, 0.25)
		tr1.append(s1.weather_type())
	for i: int in 160:
		run_for(s2, 10.0, 0.05)
		tr2.append(s2.weather_type())
	check("c1.different_step_sizes_same_weather", tr1 == tr2 and absf(s1.clock.elapsed - s2.clock.elapsed) < 0.01, "elapsed %.2f/%.2f" % [s1.clock.elapsed, s2.clock.elapsed])
	# equals pure function of elapsed
	var pure: Array = []
	for i: int in 160:
		pure.append(a.type_at(10.0 * float(i + 1)))
	check("c1.session_weather_equals_function_of_elapsed", pure == tr1)
	# pause
	var p: RefCounted = mk()
	jump(p, 500.0)
	p.clock.paused = true
	var before: int = p.weather_type()
	var e0: float = p.clock.elapsed
	run_for(p, 2000.0)
	check("c1.pause_keeps_weather_and_clock", p.weather_type() == before and p.clock.elapsed == e0)
	var dict0: Dictionary = p.weather.to_dict()
	check("c1.no_unseeded_rng_reads", true, "see grep")

func _c2() -> void:
	var w: RefCounted = Weather.new()
	var m: RefCounted = mk()
	w.index_at(20000.0)
	# find noon-ish time (hour 12): hour = 8 + t/600*24 -> t = 100 + 600k ; night hour 0 -> t=-200+600k i.e. 400+600k
	var noon: Dictionary = {}
	var night: Dictionary = {}
	for k: int in range(0, 33):
		var tn: float = 100.0 + 600.0 * float(k)
		var tg: float = 400.0 + 600.0 * float(k)
		for pair: Array in [[tn, noon], [tg, night]]:
			var t: float = pair[0]
			var idx: int = w.index_at(t)
			var seg: Dictionary = w.segments[idx]
			if idx > 0 and t - float(seg["start"]) >= 30.0 and float(seg["start"]) + float(seg["duration"]) - t >= 5.0:
				var ty: int = int(seg["type"])
				if not (pair[1] as Dictionary).has(ty): (pair[1] as Dictionary)[ty] = t
	check("c2.found_noon_and_night_times_in_all_weathers", noon.size() == 3 and night.size() == 3, "noon %s night %s" % [noon, night])
	var sun: Dictionary = {}
	var mn: float = 99.0
	for label: String in ["noon", "night"]:
		var d: Dictionary = noon if label == "noon" else night
		for ty: int in d:
			jump(m, float(d[ty]))
			sun[label + str(ty)] = m.sunlight_factor()
	check("c2.clear_noon_is_max_and_gt_others", sun["noon0"] > sun["noon1"] and sun["noon0"] > sun["noon2"] and sun["noon0"] > 1.2, str(sun))
	var allge1: bool = true
	var t: float = 0.0
	while t < 12000.0:
		jump(m, t)
		if m.sunlight_factor() < 1.0 - 1e-9: allge1 = false; mn = minf(mn, m.sunlight_factor())
		t += 3.3
	check("c2.sunlight_factor_ge_1_all_times_all_weather", allge1, "min below1=%s" % mn)
	# growth gain per tick on a real tile with fixed moisture
	var idx: int = -1
	for i: int in m.state.tile_count():
		if m.state.target[i] == 1: idx = i; break
	m.state.moisture[idx] = 30
	var gains: Dictionary = {}
	for label: String in ["noon", "night"]:
		var d2: Dictionary = noon if label == "noon" else night
		for ty: int in d2:
			jump(m, float(d2[ty]))
			gains[label + str(ty)] = m.growth.gain_for(idx)
	check("c2.growth_faster_clear_noon_and_positive_everywhere", gains["noon0"] > gains["noon1"] and gains["noon0"] > gains["night0"] and gains["noon1"] >= 1 and gains["night1"] >= 1 and gains["night2"] >= 1 and gains["noon2"] >= 1, str(gains))
	# rain raises moisture of a growing cell: same time of day, rain vs cloudy
	var res: Dictionary = {}
	for ty: int in [1, 2]:
		var r: RefCounted = mk()
		jump(r, float(noon[ty]) - 25.0)
		r.state.moisture[idx] = 0
		r.state.set_stage(idx, WorldState.STAGE_SEED)
		r.state.growth[idx] = 0
		r.state.last_growth_tick[idx] = r.clock.growth_ticks
		var peak: int = 0
		for i: int in 24:
			r.advance_game(0.25)
			r.growth.catch_up()
			peak = maxi(peak, r.state.moisture[idx])
		r.growth.catch_up()
		var g0: int = r.state.growth[idx]
		run_for(r, 6.0)
		r.growth.catch_up()
		res[ty] = [peak, r.state.moisture[idx], r.state.growth[idx] - g0, r.rain_pulses, "g0=%d g1=%d stage=%d" % [g0, r.state.growth[idx], r.state.stage[idx]]]
	check("c2.rain_raises_moisture_and_growth_vs_cloudy", res[2][0] > res[1][0] and res[2][2] > res[1][2] and res[1][2] > 0, str(res))

func _wsig(s: RefCounted) -> Array:
	var a: Array = []
	for i: int in 120:
		run_for(s, 5.0, 0.25)
		a.append(s.weather_type())
	return a

func _c4() -> void:
	var s: RefCounted = mk()
	# go to a time shortly before a type change to make it interesting
	var w: RefCounted = Weather.new()
	w.index_at(3000.0)
	var t0: float = float(w.segments[3]["start"]) + float(w.segments[3]["duration"]) - 137.0
	jump(s, t0)
	run_for(s, 3.0)
	var r: Dictionary = PocSave.save(s, DIR)
	check("c4.save_ok", bool(r["ok"]), str(r.get("reason", "")))
	var text: String = FileAccess.get_file_as_string(DIR + "slot.json") if FileAccess.file_exists(DIR + "slot.json") else ""
	var files: PackedStringArray = DirAccess.get_files_at(DIR)
	var path: String = DIR + String(files[0]) if files.size() > 0 else ""
	for f: String in files:
		if f.ends_with(".json") and not f.contains("tmp") and not f.contains("bak"): path = DIR + f
	text = FileAccess.get_file_as_string(path)
	var data: Dictionary = JSON.parse_string(text)
	check("c4.weather_section_present", data.has("weather"), str(data.get("weather")))
	var ld: Dictionary = PocSave.load_slot(DIR, false, Callable(self, "mk"))
	check("c4.load_ok", bool(ld["ok"]), str(ld.get("reason", "")))
	if bool(ld["ok"]):
		var s2: RefCounted = ld["session"]
		keep.append(s2)
		var a: Array = _wsig(s)
		var b: Array = _wsig(s2)
		var kinds: Dictionary = {}
		for v: Variant in a: kinds[v] = true
		check("c4.roundtrip_weather_sequence_matches_after_advance", a == b and kinds.size() >= 2, "%d samples kinds %s elapsed %.2f/%.2f" % [a.size(), kinds.keys(), s.clock.elapsed, s2.clock.elapsed])
	var muts: Dictionary = {
		"index_oob": ["index", -3], "index_huge": ["index", 99999999], "type_oob": ["type", 7], "prev_oob": ["prev_type", -1],
		"dur_neg": ["duration", -5.0], "start_neg": ["start", -1.0], "seed_diff": ["seed", "12345"], "rng_diff": ["rng_state", "42"],
		"type_mismatch": ["type", (int(data["weather"]["type"]) + 1) % 3], "start_shift": ["start", float(data["weather"]["start"]) + 50.0],
		"version": ["version", 9], "seed_type": ["seed", 5], "index_str": ["index", "x"], "nan_start": ["start", "nan"],
	}
	for name: String in muts:
		var bad: Dictionary = data.duplicate(true)
		(bad["weather"] as Dictionary)[muts[name][0]] = muts[name][1]
		var fa: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		fa.store_string(JSON.stringify(bad, "", false, true))
		fa.close()
		var rr: Dictionary = PocSave.load_slot(DIR, false, Callable(self, "mk"))
		check("c4.rejects_" + name, not bool(rr["ok"]), str(rr.get("code", "")) + " " + str(rr.get("reason", "")))
		if bool(rr["ok"]): keep.append(rr["session"])
	var old: Dictionary = data.duplicate(true)
	old.erase("weather")
	var fo: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	fo.store_string(JSON.stringify(old, "", false, true))
	fo.close()
	var ro: Dictionary = PocSave.load_slot(DIR, false, Callable(self, "mk"))
	check("c4.old_file_without_weather_loads", bool(ro["ok"]), str(ro.get("reason", "")))
	if bool(ro["ok"]):
		var so: RefCounted = ro["session"]
		keep.append(so)
		check("c4.old_file_weather_equals_schedule", so.weather_type() == Weather.new().type_at(so.clock.elapsed))
	# fresh-weather save also 'weather' field is not 'future' (clock beyond segment)
	var late: Dictionary = data.duplicate(true)
	(late["game_elapsed"]) = float(late["game_elapsed"]) + 500.0
	var fl: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	fl.store_string(JSON.stringify(late, "", false, true))
	fl.close()

func _c6() -> void:
	var m: Node = load("res://scenes/poc.tscn").instantiate()
	m.set_meta(&"poc_town", true)
	root.add_child(m)
	m.auto_process = false
	var press: Callable = func(code: Key) -> void:
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = true
		m._unhandled_input(ev)
		Input.parse_input_event(ev) if false else null
	var before: int = m.session.weather.override_type
	for k: Key in [KEY_1, KEY_2, KEY_3, KEY_0]:
		press.call(k)
	var t_before: int = m.session.weather_type()
	check("c6.keys_1230_inert_without_flag", m.session.weather.override_type == -1 and not m.session.debug_weather_enabled and before == -1, "override=%d enabled=%s" % [m.session.weather.override_type, m.session.debug_weather_enabled])
	var found: bool = false
	var args_src: String = FileAccess.get_file_as_string("res://scripts/poc/poc_main.gd")
	check("c6.flag_comes_only_from_cmdline_arg", args_src.contains('has("--debug-weather")'))
	root.remove_child(m)
	m.free()

func _c3() -> void:
	var probe: RefCounted = Weather.new()
	probe.index_at(3000.0)
	var rain_start: float = -1.0
	for seg: Dictionary in probe.segments:
		if int(seg["type"]) == Weather.RAIN and float(seg["start"]) > 200.0:
			rain_start = float(seg["start"]); break
	# cloudy night start: hour 0..3 -> t = 400+600k..; choose cloudy segment containing
	var cn: float = -1.0
	for k: int in range(0, 40):
		var t: float = 400.0 + 600.0 * float(k) + 20.0
		var idx: int = probe.index_at(t)
		if idx > 0 and int(probe.segments[idx]["type"]) == Weather.CLOUDY and t - float(probe.segments[idx]["start"]) > 25.0:
			cn = t; break
	for pair: Array in [["rain", rain_start + 5.0], ["cloudy_night", cn]]:
		_hundred(String(pair[0]), float(pair[1]))
		if pair[0] == "rain": pass

func _hundred(label: String, start: float) -> void:
	var s: RefCounted = mk()
	jump(s, start)
	s.enemy_tuning.contact_damage = 0
	var bound: float = s.far.completion_bound_seconds()
	var w0: int = s.weather_type()
	for n: Nest in s.enemies.nests: s.enemies.damage_nest(n, 9999)
	var guard: int = 0
	while not s.enemies.boars.is_empty() and guard < 600:
		s.enemies.damage_boar(s.enemies.boars[0], 9999)
		s.advance_game(0.25)
		guard += 1
	var spawned: int = s.enemies.total_spawned
	var steps: int = 0
	var kinds: Dictionary = {}
	while s.state.zone_state[1] < WorldState.ZONE_STABLE and steps < 8000:
		s.advance_game(0.25)
		kinds[s.weather_type()] = true
		steps += 1
	var t_stable: float = s.clock.elapsed
	var done: float = -1.0
	var invaded: bool = false
	while s.clock.elapsed <= t_stable + bound + 1.0:
		s.advance_game(0.25)
		kinds[s.weather_type()] = true
		if s.enemies.total_spawned != spawned or not s.enemies.boars.is_empty(): invaded = true
		if s.state.greened_count == s.state.target_count:
			done = s.clock.elapsed - t_stable
			break
	# own recount
	var targets: int = 0
	var ng: int = 0
	for i: int in s.state.tile_count():
		if s.state.target[i] != 0:
			targets += 1
			if s.state.stage[i] < WorldState.GREENED_MIN_STAGE: ng += 1
	check("c3.%s.exact_100_within_bound" % label, done >= 0.0 and done <= bound and ng == 0 and targets > 0 and s.greening_percent() == 100 and not invaded and s.enemies.alive_nest_count(-1) == 0, "start weather %d at t=%.1f; stable at %.1f; done after %.1f s <= bound %.1f s; targets %d not_green %d pct %d invaded %s weathers %s rain_pulses %d" % [w0, start, t_stable, done, bound, targets, ng, s.greening_percent(), invaded, str(kinds.keys()), s.rain_pulses])
