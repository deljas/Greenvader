extends SceneTree
## POC-08 independent verification (session level). Own namespace user://poc_saves_indep/ only.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const DIR: String = "user://poc_saves_indep/"
var fails: int = 0
var passes: int = 0
var keep: Array[RefCounted] = []

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("PASS " if ok else "FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func mk() -> RefCounted:
	var size: Vector2i = Session.town_size()
	var s: RefCounted = Session.new(size.x, size.y)
	s.load_combat(Session.TOWN_SETUP)
	keep.append(s)
	return s

func run_for(s: RefCounted, sec: float) -> void:
	var left: float = sec
	while left > 0.0:
		s.advance_game(minf(left, 0.25))
		left -= 0.25

func sha(b: PackedByteArray) -> String:
	var c: HashingContext = HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(b)
	return c.finish().hex_encode().substr(0, 12)

func obs(s: RefCounted) -> String:
	var st: WorldState = s.state
	var o: Dictionary = {}
	o["w"] = [sha(st.terrain), sha(st.plant_id), sha(st.stage), sha(st.growth.to_byte_array()), sha(st.moisture), sha(st.fertility), sha(st.sprout_slot), sha(st.occupant.to_byte_array())]
	o["zones"] = [Array(st.zone_state), st.cleared, st.greened_count]
	o["res"] = [s.play.seeds, snappedf(s.play.water, 0.0001), s.play.hp, s.play.reserved_seeds, s.play.selected_index, s.play.pickups.count(), s.play.cultivation.plants.size()]
	o["pos"] = [snappedf(s.position.x, 0.001), snappedf(s.position.y, 0.001)]
	var bo: Array = []
	for b: Boar in s.enemies.boars:
		bo.append([b.id, snappedf(b.pos.x, 0.01), snappedf(b.pos.y, 0.01), b.hp, b.mode])
	o["boars"] = bo
	var ne: Array = []
	for n: Nest in s.enemies.nests:
		ne.append([n.id, n.hp, n.alive, n.spawned])
	o["nests"] = ne
	var ca: Array = []
	for c: Carcass in s.enemies.carcasses:
		ca.append([snappedf(c.pos.x, 0.01), snappedf(c.pos.y, 0.01)])
	o["carc"] = ca
	o["clk"] = [snappedf(s.clock.elapsed, 0.0001), s.clock.growth_ticks, s.clock.spread_ticks]
	o["far"] = [s.far.ticks, s.far.job_zone, s.far.round_active]
	var wd: Dictionary = s.wall_growth.to_dict()
	var wrows: Dictionary = {}
	for bid: String in wd["entries"]:
		var row: Dictionary = {}
		for part: String in wd["entries"][bid]:
			row[part] = Array(wd["entries"][bid][part]).map(func(v: Variant) -> float: return snappedf(float(v), 1e-12))
		wrows[bid] = row
	o["wall"] = JSON.stringify([wd["ticks"], wrows], "", true)
	o["shots"] = s.projectiles.shots.size()
	return JSON.stringify(o, "", true)

func first_diff(a: String, b: String) -> String:
	var ja: Variant = JSON.parse_string(a)
	var jb: Variant = JSON.parse_string(b)
	if ja is Dictionary and jb is Dictionary:
		for k: String in ja:
			if JSON.stringify(ja[k]) != JSON.stringify(jb[k]):
				if k == "wall":
					var wa: Variant = JSON.parse_string(ja[k])
					var wb: Variant = JSON.parse_string(jb[k])
					for bid: String in wa["entries"]:
						if JSON.stringify(wa["entries"][bid]) != JSON.stringify(wb["entries"][bid]):
							for part: String in wa["entries"][bid]:
								var xa: Array = wa["entries"][bid][part]
								var xb: Array = wb["entries"][bid][part]
								for i: int in xa.size():
									if xa[i] != xb[i]:
										return "wall %s.%s[%d]: diff=%s a=%s b=%s" % [bid, part, i, String.num(float(xa[i]) - float(xb[i]), 20), String.num(float(xa[i]), 17), String.num(float(xb[i]), 17)]
					return "wall other: ticks %s/%s" % [str(wa.get("ticks")), str(wb.get("ticks"))]
				return "key %s: %s != %s" % [k, JSON.stringify(ja[k]).left(300), JSON.stringify(jb[k]).left(300)]
	var la: PackedStringArray = a.split("\n")
	var lb: PackedStringArray = b.split("\n")
	for i: int in mini(la.size(), lb.size()):
		if la[i] != lb[i]:
			return "line %d: %s != %s" % [i, la[i].left(80), lb[i].left(80)]
	return "len"

func clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)

func fire_mix(s: RefCounted) -> Dictionary:
	s.play.add_seeds(40)
	s.play.add_water(60.0)
	var cult: PlantDef = null
	for d: PlantDef in s.play.selectable:
		if d.is_cultivated():
			cult = d
	s.set_aim(s.position + Vector2(40, 20))
	s.fire(false)
	s.fire(true)
	if cult != null:
		s.play.selected_index = s.play.selectable.find(cult)
		s.fire(false)
	return {"cult": cult != null}

func scenario(label: String) -> RefCounted:
	var s: RefCounted = mk()
	if label == "germinating":
		s.play.add_seeds(30)
		for i: int in 6:
			s.set_aim(s.position + Vector2(20 + i * 6, 10))
			s.fire(false)
			run_for(s, 1.0)
		run_for(s, 4.0)
	elif label == "combat":
		run_for(s, 100.0)
		s.enemies.damage_nest(s.enemies.nests[0], 1)
		s.enemies.add_carcass(s.position + Vector2(50, 0))
		fire_mix(s)
	else:
		run_for(s, 20.0)
		for n: Nest in s.enemies.nests.duplicate():
			s.enemies.destroy_nest(n)
		for b: Boar in s.enemies.boars.duplicate():
			s.enemies.remove_boar(b)
		run_for(s, 200.0)
	return s

func same_ops(s: RefCounted) -> void:
	s.walk(Vector2(1, 0.3), 0.3)
	s.play.add_seeds(5)
	s.set_aim(s.position + Vector2(25, 8))
	s.fire(false)
	run_for(s, 15.0)

func _run() -> void:
	clean()
	for label: String in ["germinating", "combat", "stable"]:
		var s: RefCounted = scenario(label)
		var n_seed: int = 0
		var n_water: int = 0
		var n_plant: int = 0
		for sh: Dictionary in s.projectiles.shots:
			match String(sh["kind"]):
				"seed": n_seed += 1
				"water": n_water += 1
				_: n_plant += 1
		var seeds0: int = s.play.seeds
		var water0: float = s.play.water
		var info: String = "shots seed=%d water=%d plant=%d boars=%d nests=%d carc=%d far(job_zone=%d,active=%s,ticks=%d) zones=%s" % [n_seed, n_water, n_plant, s.enemies.boars.size(), s.enemies.nests.size(), s.enemies.carcasses.size(), s.far.job_zone, str(s.far.round_active), s.far.ticks, str(Array(s.state.zone_state))]
		var sprouts: int = 0
		for i: int in s.state.tile_count():
			if s.state.stage[i] >= WorldState.STAGE_SEED and s.state.stage[i] < WorldState.STAGE_MATURE:
				sprouts += 1
		print("INFO ", label, " sprouting_tiles=", sprouts, " ", info)
		var r: Dictionary = PocSave.save(s, DIR, {"resolution_index": 1})
		check(label + ".save", bool(r["ok"]), str(r.get("reason", "")))
		check(label + ".shots_cleared", s.projectiles.shots.is_empty())
		check(label + ".seed_conservation", s.play.seeds == mini(seeds0 + n_seed, s.play.tuning.seed_max) and s.play.reserved_seeds == 0, "seeds %d -> %d (+%d plain shots, plants %d)" % [seeds0, s.play.seeds, n_seed, n_plant])
		check(label + ".water_conservation", is_equal_approx(s.play.water, minf(water0 + n_water * s.play_tuning.water_cost_per_shot, s.play.tuning.water_max)), "water %.2f -> %.2f (+%d shots)" % [water0, s.play.water, n_water])
		var ld: Dictionary = PocSave.load_slot(DIR, false, mk)
		check(label + ".load", bool(ld["ok"]), str(ld.get("reason", "")))
		if not bool(ld["ok"]):
			continue
		var s2: RefCounted = ld["session"]
		var a: String = obs(s)
		var b: String = obs(s2)
		check(label + ".obs_equal_after_load", a == b, first_diff(a, b))
		same_ops(s)
		same_ops(s2)
		var a2: String = obs(s)
		var b2: String = obs(s2)
		check(label + ".obs_equal_after_same_ops", a2 == b2, first_diff(a2, b2))
		# duplicate check: reload 4 times from the original file; nothing grows
		var base_obs: String = b
		var ok_all: bool = true
		var d: String = ""
		for k: int in 4:
			var again: Dictionary = PocSave.load_slot(DIR, false, mk)
			if not bool(again["ok"]) or obs(again["session"]) != base_obs:
				ok_all = false
				d = "iteration %d" % k
		check(label + ".repeat_load_no_dup", ok_all, d)
		# save->load->save idempotence
		var s3: RefCounted = (PocSave.load_slot(DIR, false, mk))["session"]
		var t1: String = FileAccess.get_file_as_string(DIR + "slot.json")
		PocSave.save(s3, DIR, {"resolution_index": 1})
		var t2: String = FileAccess.get_file_as_string(DIR + "slot.json")
		var j1: Dictionary = JSON.parse_string(t1)
		var j2: Dictionary = JSON.parse_string(t2)
		j1.erase("saved_at")
		j2.erase("saved_at")
		check(label + ".resave_identical", JSON.stringify(j1, "", true) == JSON.stringify(j2, "", true))
		# keep this label's file for rejection tests (use combat)
		if label == "combat":
			DirAccess.copy_absolute(DIR + "slot.json", DIR + "good_combat.json")
		clean_except_good()
	_rejections()
	_time()
	clean()
	for s: RefCounted in keep:
		s.close()
	print("RESULT passes=%d failures=%d" % [passes, fails])
	quit(1 if fails > 0 else 0)

func clean_except_good() -> void:
	for f: String in DirAccess.get_files_at(DIR):
		if f != "good_combat.json":
			DirAccess.remove_absolute(DIR + f)

func write(file: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(DIR + file, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func good() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DIR + "good_combat.json"))

func repack_set(d: Dictionary, key: String, idx: int, val: int) -> void:
	var raw: PackedByteArray = WorldState._unpack_bytes(d["world"][key])
	raw[idx] = val
	d["world"][key] = WorldState._pack_bytes(raw)

func _rejections() -> void:
	var cases: Dictionary = {
		"version_2": func(d: Dictionary) -> void: d["format_version"] = 2,
		"version_0": func(d: Dictionary) -> void: d["format_version"] = 0,
		"version_str": func(d: Dictionary) -> void: d["format_version"] = "1",
		"map_id": func(d: Dictionary) -> void: d["map_id"] = "fixture_02",
		"map_hash": func(d: Dictionary) -> void: d["map_hash"] = "0".repeat(32),
		"del_format_version": func(d: Dictionary) -> void: d.erase("format_version"),
		"del_game_elapsed": func(d: Dictionary) -> void: d.erase("game_elapsed"),
		"del_world": func(d: Dictionary) -> void: d.erase("world"),
		"del_world_stage": func(d: Dictionary) -> void: d["world"].erase("stage"),
		"del_play_seeds": func(d: Dictionary) -> void: d["play"].erase("seeds"),
		"del_enemies_boars": func(d: Dictionary) -> void: d["enemies"].erase("boars"),
		"del_far_zone_queue": func(d: Dictionary) -> void: d["far"].erase("zone_queue"),
		"del_wall_entries": func(d: Dictionary) -> void: d["wall_growth"].erase("entries"),
		"del_clock": func(d: Dictionary) -> void: d.erase("clock"),
		"del_ui_res": func(d: Dictionary) -> void: d["ui"].erase("resolution_index"),
		"res_index_99": func(d: Dictionary) -> void: d["ui"]["resolution_index"] = 99,
		"res_index_neg": func(d: Dictionary) -> void: d["ui"]["resolution_index"] = -1,
		"pos_far": func(d: Dictionary) -> void: d["session"]["position"] = [99999.0, 99999.0],
		"pos_neg": func(d: Dictionary) -> void: d["session"]["position"] = [-50.0, -50.0],
		"pos_string": func(d: Dictionary) -> void: d["session"]["position"] = ["a", "b"],
		"elapsed_neg": func(d: Dictionary) -> void:
			d["game_elapsed"] = -5.0
			d["clock"]["elapsed"] = -5.0,
		"elapsed_mismatch": func(d: Dictionary) -> void: d["game_elapsed"] = 5.0,
		"stage_200": func(d: Dictionary) -> void: repack_set(d, "stage", 100, 200),
		"terrain_99": func(d: Dictionary) -> void: repack_set(d, "terrain", 100, 99),
		"plant_id_250": func(d: Dictionary) -> void: repack_set(d, "plant_id", 100, 250),
		"moisture_255": func(d: Dictionary) -> void: repack_set(d, "moisture", 100, 255),
		"world_width": func(d: Dictionary) -> void: d["world"]["width"] = 7,
		"seeds_neg": func(d: Dictionary) -> void: d["play"]["seeds"] = -5,
		"seeds_huge": func(d: Dictionary) -> void: d["play"]["seeds"] = 999999,
		"water_neg": func(d: Dictionary) -> void: d["play"]["water"] = -3.0,
		"hp_huge": func(d: Dictionary) -> void: d["play"]["hp"] = 9999,
		"hp_neg": func(d: Dictionary) -> void: d["play"]["hp"] = -4,
		"growth_ticks_neg": func(d: Dictionary) -> void: d["clock"]["growth_ticks"] = -3,
		"boar_hp_huge": func(d: Dictionary) -> void: d["enemies"]["boars"][0]["hp"] = 99999,
		"boar_pos_far": func(d: Dictionary) -> void:
			d["enemies"]["boars"][0]["pos"] = [1e9, 1e9],
		"boar_hp_neg": func(d: Dictionary) -> void: d["enemies"]["boars"][0]["hp"] = -3,
		"nest_zone_bad": func(d: Dictionary) -> void: d["enemies"]["nests"][0]["zone"] = 99,
		"nest_tile_out": func(d: Dictionary) -> void:
			d["enemies"]["nests"][0]["x"] = 9999
			d["enemies"]["nests"][0]["y"] = 9999,
		"far_job_zone_bad": func(d: Dictionary) -> void: d["far"]["job_zone"] = 999,
		"spread_queue_type": func(d: Dictionary) -> void: d["spread"]["queue"] = "x",
		"section_type": func(d: Dictionary) -> void: d["play"] = [1, 2],
	}
	print("INFO boar keys: ", good()["enemies"]["boars"][0].keys() if good()["enemies"]["boars"].size() > 0 else "none", " nest keys: ", good()["enemies"]["nests"][0].keys())
	var live: RefCounted = scenario("stable")
	var live_obs: String = obs(live)
	var live_occ: String = sha(live.state.occupant.to_byte_array())
	var accepted: Array[String] = []
	for name: String in cases:
		var d: Dictionary = good()
		(cases[name] as Callable).call(d)
		write("slot.json", JSON.stringify(d, "", false, true))
		var res: Dictionary = PocSave.load_slot(DIR, false, mk)
		var rejected: bool = not bool(res["ok"])
		if not rejected:
			accepted.append(name)
			var q: RefCounted = res["session"]
			var bad: Array[String] = []
			var tun: PlayTuning = q.play.tuning
			if q.play.seeds < 0 or q.play.seeds > tun.seed_max: bad.append("seeds")
			if q.play.water < 0.0 or q.play.water > tun.water_max: bad.append("water")
			if q.play.hp < 0 or q.play.hp > q.play.hp_max: bad.append("hp")
			if q.clock.growth_ticks < 0: bad.append("growth_ticks")
			var maxhp: int = 0
			for b: Boar in q.enemies.boars:
				maxhp = maxi(maxhp, b.hp)
				if b.pos.x < 0 or b.pos.y < 0 or b.pos.x > q.state.width * 4 or b.pos.y > q.state.height * 4: bad.append("boar_pos")
			var pid_max: int = 0
			for i: int in q.state.tile_count():
				pid_max = maxi(pid_max, q.state.plant_id[i])
			print("INFO accepted.", name, " seeds=", q.play.seeds, " water=", q.play.water, " hp=", q.play.hp, " gticks=", q.clock.growth_ticks, " maxBoarHp=", maxhp, " max_plant_id=", pid_max, " insane=", bad)
			run_for(q, 10.0)
			print("INFO accepted.", name, " ran10s consistent=", q.state.counters_consistent())
		print("INFO reject.", name, " -> ", "REJECT " + String(res.get("code", "")) if rejected else "ACCEPTED", " ", String(res.get("reason", "")).left(60))
	check("reject.all_cases", accepted.is_empty(), "accepted=%s" % str(accepted))
	# text-level
	var txt: String = FileAccess.get_file_as_string(DIR + "good_combat.json")
	for pair: Array in [["trunc", txt.left(txt.length() / 2)], ["empty", ""], ["array", "[1,2]"], ["garbage", "\u0000\u0001xx{"], ["null", "null"]]:
		write("slot.json", String(pair[1]))
		var res: Dictionary = PocSave.load_slot(DIR, false, mk)
		check("reject.text_" + String(pair[0]), not bool(res["ok"]) and String(res.get("reason", "")) != "", String(res.get("reason", "")).left(50))
	# backup recovery: good in backup, corrupt slot
	write("slot.bak.json", txt)
	write("slot.json", txt.left(100))
	var r1: Dictionary = PocSave.load_slot(DIR, false, mk)
	var r2: Dictionary = PocSave.load_slot(DIR, true, mk)
	check("backup.slot_corrupt_reports_backup", not bool(r1["ok"]) and bool(r1.get("backup_available", false)), String(r1.get("reason", "")))
	check("backup.loads_from_bak", bool(r2["ok"]))
	# real save path with corrupt slot: backup must be preserved good
	var sv: RefCounted = mk()
	run_for(sv, 5.0)
	write("slot.json", "{broken")
	var bak_before: String = FileAccess.get_file_as_string(DIR + "slot.bak.json")
	var sr: Dictionary = PocSave.save(sv, DIR)
	check("backup.save_over_corrupt_keeps_good_bak", bool(sr["ok"]) and FileAccess.get_file_as_string(DIR + "slot.bak.json") == bak_before)
	# normal save moves old slot to bak
	var slot_prev: String = FileAccess.get_file_as_string(DIR + "slot.json")
	PocSave.save(sv, DIR)
	check("backup.save_rotates", FileAccess.get_file_as_string(DIR + "slot.bak.json") == slot_prev and not PocSave.has_file(DIR, "slot.tmp.json"))
	check("reject.live_untouched", obs(live) == live_obs and sha(live.state.occupant.to_byte_array()) == live_occ)
	clean()

func _time() -> void:
	clean()
	var s: RefCounted = scenario("combat")
	PocSave.save(s, DIR)
	var elapsed: float = s.clock.elapsed
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "slot.json"))
	d["saved_at"] = "1999-01-01T00:00:00"
	write("slot.json", JSON.stringify(d, "", false, true))
	OS.delay_msec(1500)
	var ld: Dictionary = PocSave.load_slot(DIR, false, mk)
	var s2: RefCounted = ld["session"]
	check("time.no_real_time_added", bool(ld["ok"]) and s2.clock.elapsed == elapsed and s2.enemies.time == s.enemies.time, "elapsed %.3f vs %.3f" % [s2.clock.elapsed, elapsed])
	check("time.paused_after_load_default", true, "paused=%s mult=%s" % [str(s2.paused), str(s2.multiplier)])
	s2.paused = true
	var before: String = obs(s2)
	s2.advance(5.0)
	check("time.paused_no_advance", obs(s2) == before)
	s2.paused = false
	s2.advance(5.0)
	var dt: float = s2.clock.elapsed - elapsed
	check("time.unpause_single_capped_step", dt <= Config.MAX_STEP_S * s2.multiplier + 0.001 and dt > 0.0, "advanced %.3f (cap %.3f)" % [dt, Config.MAX_STEP_S])
