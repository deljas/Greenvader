extends SceneTree
## WTH-03 independent: combined save/load (helper plants + one carried + rain + gatlinger flight + combat), and no progress while closed.
## Own save namespace user://poc_saves_indep_wth03/. Helper seeds are granted with helpers.add_seeds (state setup for the save test only).
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const DIR: String = "user://poc_saves_indep_wth03/"
const OUT: String = "res://evidence/weather/03/independent/"
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

func obs(m: RefCounted) -> Dictionary:
	var st: WorldState = m.state
	var boars: Array = []
	for b: Boar in m.enemies.boars:
		boars.append([b.id, snappedf(b.pos.x, 0.001), snappedf(b.pos.y, 0.001), b.hp, b.mode])
	var nests: Array = []
	for n: Nest in m.enemies.nests:
		nests.append([n.id, n.hp, n.alive, n.spawned])
	var lv: Dictionary = m.weather.levels_at(m.clock.elapsed)
	return {
		"world": [hash(st.stage), hash(st.growth), hash(st.moisture), hash(st.occupant), hash(st.plant_id), st.greened_count],
		"res": [m.play.seeds, snappedf(m.play.water, 0.001), m.play.hp, m.helpers.seeds, m.helpers.pickups.size(), m.play.pickups.count()],
		"helpers": JSON.stringify(snap([m.helpers.plants, m.helpers.carried, m.helpers.flights, m.helpers.pickups, m.helpers.fire_serial, m.helpers.seeded_total, m.helpers.wasted_total])),
		"weather": [m.weather_type(), JSON.stringify(lv)],
		"enemies": JSON.stringify([boars, nests]),
		"clock": [m.clock.elapsed, m.clock.growth_ticks, m.clock.spread_ticks],
		"pos": [m.position.x, m.position.y],
	}

func snap(v: Variant) -> Variant:
	if v is float: return snappedf(v, 0.001)
	if v is Array:
		var a: Array = []
		for e: Variant in v: a.append(snap(e))
		return a
	if v is Dictionary:
		var d: Dictionary = {}
		for k: Variant in v: d[k] = snap(v[k])
		return d
	return v

func diff(a: Dictionary, b: Dictionary) -> String:
	var bad: PackedStringArray = PackedStringArray()
	for k: String in a:
		if str(a[k]) != str(b[k]): bad.append(k)
	return ",".join(bad)

func run_for(m: RefCounted, seconds: float) -> void:
	var left: float = seconds
	while left > 0.0:
		m.advance_game(0.1)
		left -= 0.1

func free_cells(m: RefCounted, o: Vector2i) -> int:
	var c: Vector2 = m.helpers.block_center_px(o)
	var n: int = 0
	for y: int in range(o.y - 8, o.y + 12):
		for x: int in range(o.x - 8, o.x + 12):
			if m.state.in_bounds(x, y) and Vector2((x + 0.5) * 4.0, (y + 0.5) * 4.0).distance_to(c) <= 60.0 and m.state.can_plant(m.state.index_of(x, y)):
				n += 1
	return n

func find_block(m: RefCounted, kind: String, near: Vector2i) -> Vector2i:
	var hp: RefCounted = m.helpers
	var best: Vector2i = Vector2i(-9999, -9999)
	var bd: float = 1.0e12
	for oy: int in range(near.y - 30, near.y + 30):
		for ox: int in range(near.x - 30, near.x + 30):
			var o: Vector2i = Vector2i(ox, oy)
			var c: Vector2 = hp.block_center_px(o)
			if not bool(hp.evaluate(kind, o, c)["ok"]): continue
			var score: float = c.distance_to(m.position)
			if kind == "gatlinger":
				if free_cells(m, o) < 30: continue
				score = -float(free_cells(m, o))
			if score < bd:
				bd = score
				best = o
	return best

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f: String in DirAccess.get_files_at(DIR): DirAccess.remove_absolute(DIR + f)
	if OS.get_cmdline_user_args().has("--round"): variant = "round"
	if OS.get_cmdline_user_args().has("--nohelp"): variant = "nohelp"
	if OS.get_cmdline_user_args().has("--nogat"): variant = "nogat"
	_cond2()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var f: FileAccess = FileAccess.open(OUT + "save_" + variant + ".log", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\nRESULT passes=%d failures=%d\n" % [passes, fails])
	f.close()
	for f2: String in DirAccess.get_files_at(DIR): DirAccess.remove_absolute(DIR + f2)
	print("RESULT passes=%d failures=%d" % [passes, fails])
	for m: RefCounted in keep: m.close()
	quit(1 if fails > 0 else 0)

var variant: String = "plain"
func _cond2() -> void:
	var m: RefCounted = mk()
	if variant == "nohelp": m.position = Coords.cell_center_logic(Vector2i(86, 84))
	var start_cell: Vector2i = Coords.logic_to_cell(m.position)
	# natural weather: advance to 25 s into the first rain segment (no input)
	var rain_t: float = -1.0
	var t: float = 0.0
	t = 400.0
	while t < 6000.0:
		if m.weather.type_at(t) == 2 and m.weather.type_at(t - 40.0) != 2:
			rain_t = t
			break
		t += 5.0
	check("s.rain_exists_in_schedule", rain_t >= 0.0, "first rain at %.0fs" % rain_t)
	run_for(m, rain_t + 25.0)
	check("s.is_raining", m.weather_type() == 2, "t=%.1f type=%d" % [m.clock.elapsed, m.weather_type()])
	# helper seeds (state setup) then place
	if variant != "nohelp": m.helpers.add_seeds(9)
	var order: Array = ["sprinkler", "army"] if variant == "nogat" else ["gatlinger", "sprinkler", "army"]
	var uids: Dictionary = {}
	for kind: String in order:
		var o: Vector2i = find_block(m, kind, Coords.logic_to_cell(m.position))
		check("s.block_for_" + kind, o.x != -9999, str(o))
		if o.x == -9999: continue
		var c: Vector2 = m.helpers.block_center_px(o)
		m.position = c + Vector2(0, 12)
		while m.helper_mode != -1: m.cycle_helper_mode()
		var g: int = 0
		while m.helper_active_kind() != kind and g < 6:
			m.cycle_helper_mode(); g += 1
		var r: Dictionary = m.place_helper(c)
		m.end_helper_mode()
		uids[kind] = int(r["uid"])
		check("s.place_" + kind, bool(r["ok"]), str(r["code"]))
	# lift the army (nearest to the player: stand next to it)
	var army: Dictionary = m.helpers.plant_by_uid(int(uids.get("army", 0)))
	if not army.is_empty(): m.position = m.helpers.plant_center_px(army) + Vector2(0, 10)
	var lr: Dictionary = m.lift_helper()
	check("s.lift_one", bool(lr["ok"]) and m.helpers.is_carrying() and int(m.helpers.carried["uid"]) == int(uids.get("army", -1)), str(lr["code"]))
	# let the gatlinger fill & fire; step finely until a flight exists
	var t0: float = m.clock.elapsed
	while m.helpers.flights.is_empty() and m.clock.elapsed - t0 < 90.0:
		m.advance_game(0.05)
	check("s.gatlinger_flight_in_air", not m.helpers.flights.is_empty(), "flights=%d after %.1fs" % [m.helpers.flights.size(), m.clock.elapsed - t0])
	# combat: wait (fine steps) until boars exist; the rain must still be on
	var combat: bool = m.enemies.boars.size() > 0
	var summary: String = "t=%.1f type=%d boars=%d flights=%d plants=%d carried=%s seeds_h=%d" % [m.clock.elapsed, m.weather_type(), m.enemies.boars.size(), m.helpers.flights.size(), m.helpers.plants.size(), str(m.helpers.is_carrying()), m.helpers.seeds]
	check("s.combined_state_reached", combat and m.weather_type() == 2 and not m.helpers.flights.is_empty() and m.helpers.is_carrying() and m.helpers.plants.size() == 2, summary)
	if variant == "round":
		for fl: Dictionary in m.helpers.flights: fl["dur"] = snappedf(float(fl["dur"]), 0.0001) if false else float(str(snappedf(float(fl["dur"]), 0.0001)))
		print("DIAG variant round: live flight dur rounded to 4 decimals before saving")
	print("DIAG pos=", m.position, " cell=", Coords.logic_to_cell(m.position), " walkable=", m.is_walkable_logic(m.position), " downed=", m.play.health.downed, " hp=", m.play.hp)
	var saved: Dictionary = PocSave.save(m, DIR, {"resolution_index": 0})
	check("s.save_ok", bool(saved["ok"]), str(saved.get("reason", "")))
	var loaded: Dictionary = PocSave.load_slot(DIR, false, Callable(self, "mk"))
	check("s.load_ok", bool(loaded["ok"]), str(loaded.get("reason", "")))
	if not (bool(saved["ok"]) and bool(loaded["ok"])): return
	var c: RefCounted = loaded["session"]
	keep.append(c)
	if diff(obs(m), obs(c)) != "":
		var ja: Array = JSON.parse_string(obs(m)["helpers"]); var jb: Array = JSON.parse_string(obs(c)["helpers"])
		print("(rounded helpers differ at load)")
		for i: int in 7: if JSON.stringify(ja[i]) != JSON.stringify(jb[i]): print("HDIFF ", i, "\n ", JSON.stringify(ja[i]), "\n ", JSON.stringify(jb[i]))
	var oa: Dictionary = obs(m)
	var ob: Dictionary = obs(c)
	check("s.equal_at_load", diff(oa, ob) == "", "diff=[%s] flights saved=%d loaded=%d carried=%s/%s rain=%d/%d" % [diff(oa, ob), m.helpers.flights.size(), c.helpers.flights.size(), str(m.helpers.is_carrying()), str(c.helpers.is_carrying()), m.weather_type(), c.weather_type()])
	if OS.get_cmdline_user_args().has("--bisect"):
		var tt: float = 0.0
		while tt < 12.0:
			m.advance_game(0.05); c.advance_game(0.05); tt += 0.05
			var dd: String = diff(obs(m), obs(c))
			if dd != "":
				print("BISECT first diff at +%.2fs keys=[%s]" % [tt, dd])
				print(" A helpers ", str(obs(m)["helpers"]).substr(0, 900))
				print(" B helpers ", str(obs(c)["helpers"]).substr(0, 900))
				print(" A world ", obs(m)["world"], " B world ", obs(c)["world"])
				break
	for step_s: float in [10.0, 50.0, 120.0, 200.0]:
		run_for(m, step_s)
		run_for(c, step_s)
		var da: Dictionary = obs(m)
		var db: Dictionary = obs(c)
		if diff(da, db) != "" and step_s == 10.0:
			for k: String in da:
				if str(da[k]) != str(db[k]): print("DIFFKEY ", k, "\n ", str(da[k]).substr(0, 700), "\n ", str(db[k]).substr(0, 700))
		check("s.equal_after_%d" % int(m.clock.elapsed - float(oa["clock"][0])), diff(da, db) == "", "diff=[%s] t=%.1f rain=%d greened=%d boars=%d weather %s" % [diff(da, db), m.clock.elapsed, m.weather_type(), m.state.greened_count, m.enemies.boars.size(), str(da["weather"][0])])
	# cond 4: closed time. Tamper saved_at, wait real time, load: clock identical to the saved elapsed.
	var m2: RefCounted = mk()
	run_for(m2, 123.4)
	var e_save: float = m2.clock.elapsed
	var sv: Dictionary = PocSave.save(m2, DIR, {"resolution_index": 0})
	var path: String = DIR + PocSave.SLOT_FILE
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	data["saved_at"] = "1999-01-01T00:00:00"
	var fw: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	fw.store_string(JSON.stringify(data, "", false, true)); fw.close()
	OS.delay_msec(3000)
	var l2: Dictionary = PocSave.load_slot(DIR, false, Callable(self, "mk"))
	check("c4.load_after_tamper_and_wait", bool(sv["ok"]) and bool(l2["ok"]), str(l2.get("reason", "")))
	if bool(l2["ok"]):
		var r2: RefCounted = l2["session"]
		keep.append(r2)
		check("c4.clock_unchanged", r2.clock.elapsed == e_save and r2.clock.growth_ticks == m2.clock.growth_ticks and r2.helpers.time == m2.helpers.time, "saved %.3f loaded %.3f" % [e_save, r2.clock.elapsed])
		OS.delay_msec(2000)
		check("c4.no_progress_without_advance", r2.clock.elapsed == e_save and diff(obs(r2), obs(m2)) == "", "after 2s real wait clock %.3f" % r2.clock.elapsed)
		var before: float = r2.clock.elapsed
		r2.advance(3600.0)
		check("c4.huge_real_delta_is_capped", r2.clock.elapsed - before <= Config.MAX_STEP_S * r2.multiplier + 0.001, "advanced %.3f game s from a 3600 s frame (cap %.2f x%.0f)" % [r2.clock.elapsed - before, Config.MAX_STEP_S, r2.multiplier])
