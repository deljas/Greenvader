extends SceneTree
## HLP-02 independent verification (headless): condition 4 (place / lift / save round trip of the 3 kinds' extra state,
## out-of-range rejection, pause, strict 100 % within far.completion_bound_seconds()). Own save namespace.
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const DIR: String = "user://poc_saves_indep_hlp02/"
const OUT: String = "res://evidence/helper/02/independent/"
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

func info(text: String) -> void:
	lines.append("INFO " + text)
	print("INFO ", text)

func _init() -> void:
	_run.call_deferred()

func mk() -> RefCounted:
	var size: Vector2i = Session.town_size()
	var m: RefCounted = Session.new(size.x, size.y)
	m.paving = Session.paving_from(m.env_tuning)
	m.load_combat(Session.TOWN_SETUP)
	keep.append(m)
	return m

func cc(o: Vector2i) -> Vector2:
	return (Vector2(o) + Vector2(2, 2)) * 4.0

func mature_free(st: WorldState, o: Vector2i) -> bool:
	for y: int in range(o.y, o.y + 4):
		for x: int in range(o.x, o.x + 4):
			if not st.in_bounds(x, y): return false
			var i: int = st.index_of(x, y)
			if not st.is_walkable(x, y) or st.target[i] != 1 or st.occupant[i] != 0 or st.stage[i] != WorldState.STAGE_MATURE or st.zone_at(i) != 0: return false
	return true

func spots(st: WorldState, n: int, from: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy: int in range(0, 40):
		for dx: int in range(-30, 30):
			var o: Vector2i = from + Vector2i(dx, -dy)
			if out.size() < n and mature_free(st, o):
				var ok: bool = true
				for q: Vector2i in out:
					ok = ok and (absi(q.x - o.x) > 5 or absi(q.y - o.y) > 5)
				if ok: out.append(o)
	return out

func place(m: RefCounted, o: Vector2i, mode: int) -> Dictionary:
	m.helpers.add_seeds(5)
	m.position = cc(o)
	m.set_aim(cc(o))
	m.helper_mode = mode
	return m.place_helper()

func read_slot() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DIR + PocSave.SLOT_FILE))

func write_slot(d: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(DIR + PocSave.SLOT_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "", false, true))
	f.close()

func clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)

func recount(st: WorldState) -> int:
	var n: int = 0
	for i: int in st.tile_count():
		if st.target[i] != 0 and st.stage[i] >= 2: n += 1
	return n

func sig(m: RefCounted) -> String:
	var st: WorldState = m.state
	return JSON.stringify([hash(st.stage), hash(st.occupant), hash(st.moisture), st.greened_count, m.helpers.to_dict()])

func _run() -> void:
	clean()
	_roundtrip()
	_rejects()
	_pause()
	_hundred()
	clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var f: FileAccess = FileAccess.open(OUT + "common.log", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\nRESULT passes=%d failures=%d\n" % [passes, fails])
	f.close()
	print("RESULT passes=%d failures=%d" % [passes, fails])
	for m: RefCounted in keep: m.close()
	quit(1 if fails > 0 else 0)

func _setup3(m: RefCounted) -> Array[int]:
	var st: WorldState = m.state
	for n: Nest in m.enemies.nests.duplicate(): m.enemies.destroy_nest(n)
	for b: Boar in m.enemies.boars.duplicate(): m.enemies.remove_boar(b)
	var sp: Array[Vector2i] = spots(st, 3, Vector2i(96, 94))
	var uids: Array[int] = []
	for i: int in 3:
		var r: Dictionary = place(m, sp[i], i)
		uids.append(int(r["uid"]) if bool(r["ok"]) else 0)
	return uids

func _roundtrip() -> void:
	var m: RefCounted = mk()
	var uids: Array[int] = _setup3(m)
	check("rt.three_placed", uids.size() == 3 and not uids.has(0) and m.helpers.plants.size() == 3, str(uids))
	m.position = Vector2(88 * 4.0, 86 * 4.0)
	# let the gatlinger receive + have flights, the army move off its post for a decoy, the sprinkler spend water
	var army: Dictionary = m.helpers.plant_by_uid(uids[2])
	var spr: Dictionary = m.helpers.plant_by_uid(uids[1])
	var gat: Dictionary = m.helpers.plant_by_uid(uids[0])
	var saw_flight: bool = false
	for i: int in 400:
		m.advance_game(0.1)
		saw_flight = saw_flight or not m.helpers.flights.is_empty()
		if i > 200 and not m.helpers.flights.is_empty() and float(gat["stock"]) >= 1.0:
			break
	# the unit stands off its post (state injection: a real engagement needs a legal boar record that the save also accepts)
	var hc: Vector2 = m.helpers.plant_center_px(army)
	army["ax"] = hc.x + 9.5
	army["ay"] = hc.y + 14.25
	var d0: Dictionary = m.helpers.to_dict()
	info("state before save: gat stock %.1f flights %d, spr stock %.1f, army unit %s home %s" % [float(gat["stock"]), m.helpers.flights.size(), float(spr["stock"]), str(m.helpers.unit_pos(army)), str(m.helpers.plant_center_px(army))])
	check("rt.nontrivial_extra_state", float(gat["stock"]) > 0.0 or m.helpers.flights.size() > 0, "")
	check("rt.has_flights_in_air", not m.helpers.flights.is_empty(), "")
	check("rt.army_unit_displaced", m.helpers.unit_pos(army).distance_to(m.helpers.plant_center_px(army)) > 3.0)
	var sv: Dictionary = PocSave.save(m, DIR, {"resolution_index": 0})
	check("rt.save_ok", bool(sv["ok"]), str(sv.get("reason", "")))
	var ld: Dictionary = PocSave.load_slot(DIR, false, mk)
	check("rt.load_ok", bool(ld["ok"]), str(ld.get("reason", "")))
	var n: RefCounted = ld["session"]
	var dn: Dictionary = n.helpers.to_dict()
	check("rt.helpers_dict_identical", JSON.stringify(d0) == JSON.stringify(dn))
	check("rt.fields_per_kind", float(n.helpers.plant_by_uid(uids[0])["stock"]) == snappedf(float(gat["stock"]), 0.0001) and float(n.helpers.plant_by_uid(uids[1])["stock"]) == snappedf(float(spr["stock"]), 0.0001) and n.helpers.unit_pos(n.helpers.plant_by_uid(uids[2])).distance_to(m.helpers.unit_pos(army)) < 0.001 and n.helpers.flights.size() == m.helpers.flights.size())
	# continuing identical
	m.advance_game(10.0)
	n.advance_game(10.0)
	check("rt.continue_identical_10s", sig(m) == sig(n), "")
	# lift each kind: carried stock kept, re-place restores
	for k: int in 3:
		var plant: Dictionary = n.helpers.plant_by_uid(uids[k])
		var stock: float = float(plant["stock"])
		n.position = n.helpers.plant_center_px(plant)
		var lf: Dictionary = n.lift_helper()
		check("rt.lift_kind%d" % k, bool(lf["ok"]) and n.helpers.is_carrying() and absf(float(n.helpers.carried["stock"]) - stock) < 0.001, "carried stock %.2f vs %.2f" % [float(n.helpers.carried["stock"]), stock])
		var sv2: Dictionary = PocSave.save(n, DIR, {"resolution_index": 0})
		var ld2: Dictionary = PocSave.load_slot(DIR, false, mk)
		check("rt.carry_roundtrip_kind%d" % k, bool(sv2["ok"]) and bool(ld2["ok"]) and JSON.stringify(ld2["session"].helpers.to_dict()) == JSON.stringify(n.helpers.to_dict()), str(ld2.get("reason", "")))
		var o2: Vector2i = Vector2i(plant["x"], plant["y"])
		n.position = cc(o2)
		n.set_aim(cc(o2))
		n.helper_mode = k
		var rp: Dictionary = n.place_helper()
		var p2: Dictionary = n.helpers.plant_by_uid(uids[k])
		check("rt.replace_kind%d_stock_kept_unit_home" % k, bool(rp["ok"]) and not p2.is_empty() and absf(float(p2["stock"]) - stock) < 0.001 and n.helpers.unit_pos(p2).distance_to(n.helpers.plant_center_px(p2)) < 0.01)
	check("rt.counters", n.state.counters_consistent() and recount(n.state) == n.state.greened_count)

func _rejects() -> void:
	clean()
	var m: RefCounted = mk()
	var uids: Array[int] = _setup3(m)
	m.advance_game(5.0)
	PocSave.save(m, DIR, {"resolution_index": 0})
	var good: Dictionary = read_slot()
	write_slot(good)
	check("rej.control_loads", bool(PocSave.load_slot(DIR, false, mk)["ok"]))
	var P: String = "plants"
	var mutations: Array = [
		["gat_stock_over_max", func(d: Dictionary) -> void: d["helpers"][P][0]["stock"] = 13.0],
		["gat_stock_negative", func(d: Dictionary) -> void: d["helpers"][P][0]["stock"] = -1.0],
		["spr_stock_over_max", func(d: Dictionary) -> void: d["helpers"][P][1]["stock"] = 61.0],
		["spr_stock_negative", func(d: Dictionary) -> void: d["helpers"][P][1]["stock"] = -0.5],
		["army_unit_beyond_radius", func(d: Dictionary) -> void: d["helpers"][P][2]["ax"] = float(d["helpers"][P][2]["ax"]) + 60.0],
		["army_unit_far_away", func(d: Dictionary) -> void: d["helpers"][P][2]["ay"] = 9999.0],
		["timer_over_max", func(d: Dictionary) -> void: d["helpers"][P][0]["timer"] = 50.0],
		["timer_negative", func(d: Dictionary) -> void: d["helpers"][P][1]["timer"] = -2.0],
		["timer2_over_max", func(d: Dictionary) -> void: d["helpers"][P][0]["timer2"] = 99.0],
		["stock_missing", func(d: Dictionary) -> void: d["helpers"][P][0].erase("stock")],
		["flights_not_array", func(d: Dictionary) -> void: d["helpers"]["flights"] = 5],
		["flight_cell_out_of_map", func(d: Dictionary) -> void: d["helpers"]["flights"] = [{"ox": 1.0, "oy": 1.0, "cx": 999, "cy": 3, "age": 0.1, "dur": 1.0}]],
		["flight_age_ge_dur", func(d: Dictionary) -> void: d["helpers"]["flights"] = [{"ox": 1.0, "oy": 1.0, "cx": 10, "cy": 10, "age": 2.0, "dur": 1.0}]],
		["flight_dur_huge", func(d: Dictionary) -> void: d["helpers"]["flights"] = [{"ox": 1.0, "oy": 1.0, "cx": 10, "cy": 10, "age": 0.1, "dur": 500.0}]],
		["carried_stock_over", func(d: Dictionary) -> void: d["helpers"]["carried"] = {"uid": 77, "kind": "gatlinger", "hp": 3, "stock": 40.0}],
		["fire_serial_negative", func(d: Dictionary) -> void: d["helpers"]["fire_serial"] = -1],
	]
	for mut: Array in mutations:
		var d: Dictionary = JSON.parse_string(JSON.stringify(good))
		(mut[1] as Callable).call(d)
		write_slot(d)
		var before: String = sig(m)
		var res: Dictionary = PocSave.load_slot(DIR, false, mk)
		check("rej.%s" % mut[0], not bool(res["ok"]), "reason=%s" % str(res.get("reason", "")))
		check("rej.%s_live_untouched" % mut[0], sig(m) == before)
	write_slot(good)

func _pause() -> void:
	var m: RefCounted = mk()
	var uids: Array[int] = _setup3(m)
	m.position = Vector2(88 * 4.0, 86 * 4.0)
	var gat: Dictionary = m.helpers.plant_by_uid(uids[0])
	var spr: Dictionary = m.helpers.plant_by_uid(uids[1])
	var army: Dictionary = m.helpers.plant_by_uid(uids[2])
	var decoy: Boar = Boar.new()
	decoy.id = 9100; decoy.zone = 0; decoy.hp = 100
	decoy.pos = m.helpers.plant_center_px(army) + Vector2(0.0, 12.0)
	m.enemies.boars.append(decoy)
	var st: WorldState = m.state
	# seeds near the sprinkler so a pulse is due
	var c: Vector2 = m.helpers.plant_center_px(spr)
	for y: int in st.height:
		for x: int in st.width:
			var i: int = st.index_of(x, y)
			if Vector2((x + 0.5) * 4.0, (y + 0.5) * 4.0).distance_to(c) <= 25.0 and st.can_plant(i) and (x + y) % 3 == 0:
				st.set_stage(i, WorldState.STAGE_SEED)
	gat["stock"] = 5.0
	m.advance_game(1.0)
	m.paused = true
	var s0: String = sig(m)
	var fl0: int = m.helpers.fire_serial
	var hp0: int = decoy.hp
	var pulses0: int = m.helpers.pulses_total
	m.advance_game(60.0)
	m.advance(60.0)
	check("pause.no_work_at_all", sig(m) == s0 and m.helpers.fire_serial == fl0 and m.helpers.pulses_total == pulses0 and decoy.hp == hp0, "")
	m.paused = false
	m.advance_game(4.0)
	check("pause.resumes", m.helpers.fire_serial > fl0 or m.helpers.pulses_total > pulses0 or decoy.hp < hp0, "fire %d->%d pulses %d->%d decoy hp %d->%d" % [fl0, m.helpers.fire_serial, pulses0, m.helpers.pulses_total, hp0, decoy.hp])

func _hundred() -> void:
	var m: RefCounted = mk()
	var st: WorldState = m.state
	var uids: Array[int] = _setup3(m)
	check("hundred.three_placed", not uids.has(0))
	m.position = Vector2(88 * 4.0, 86 * 4.0)
	var guard: int = 0
	while int(st.zone_state[1]) < WorldState.ZONE_STABLE and guard < 400:
		m.advance_game(0.5)
		guard += 1
	var t_stable: float = m.clock.elapsed
	var bound: float = m.far.completion_bound_seconds()
	check("hundred.zones_stable", int(st.zone_state[0]) >= WorldState.ZONE_STABLE and int(st.zone_state[1]) >= WorldState.ZONE_STABLE, str(Array(st.zone_state)))
	info("hundred: stable at %.1f, bound %.1f, greened %d/%d, boars %d, nests %d" % [t_stable, bound, st.greened_count, st.target_count, m.enemies.boars.size(), m.enemies.alive_nest_count(-1)])
	var reached: float = -1.0
	var early: bool = false
	while m.clock.elapsed <= t_stable + bound + 1.0:
		m.advance_game(2.0)
		if st.greened_count == st.target_count:
			reached = m.clock.elapsed
			break
		if m.greening_percent() >= 100: early = true
	var not_green: int = 0
	var targets: int = 0
	for i: int in st.tile_count():
		if st.target[i] != 0:
			targets += 1
			if st.stage[i] < 2: not_green += 1
	check("hundred.reached_within_bound", reached >= 0.0, "after %.1fs of bound %.1fs" % [reached - t_stable, bound])
	check("hundred.own_recount_exact_100", not_green == 0 and targets == st.target_count and m.greening_percent() == 100 and not early, "targets %d not green %d" % [targets, not_green])
	check("hundred.three_kept_no_reinvasion", m.helpers.plants.size() == 3 and m.enemies.boars.is_empty() and m.enemies.alive_nest_count(-1) == 0 and st.counters_consistent())
