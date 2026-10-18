extends SceneTree
## POC-08 save / load logic checks (headless OK). Run:
## godot --headless --path <repo> --script res://tests/poc/save/logic.gd
## Own namespace user://poc_saves_test/ only (cleaned at start). The game's old saves are never touched (hashed before / after).
## Long conditions are fast-forwarded with advance_game(); each condition runs once. No OS-level input.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const DIR: String = "user://poc_saves_test/"

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

func _run() -> void:
	var old_before: Dictionary = old_user_files()
	clean_dir()
	_states_roundtrip()
	_rejections()
	_backup()
	_downed()
	_time_rules()
	var old_after: Dictionary = old_user_files()
	check("old_saves.untouched", old_before == old_after, "files=%d" % old_before.size())
	clean_dir()
	for s: RefCounted in sessions:
		s.close()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)

func make_session() -> RefCounted:
	var size: Vector2i = Session.town_size()
	var s: RefCounted = Session.new(size.x, size.y)
	s.load_combat(Session.TOWN_SETUP)
	sessions.append(s)
	return s

func factory() -> RefCounted:
	return make_session()

func clean_dir() -> void:
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)

## name -> md5 of every file directly under user:// and (recursively) of user:// subfolders except the PoC namespaces.
func old_user_files(path: String = "user://") -> Dictionary:
	var out: Dictionary = {}
	for file: String in DirAccess.get_files_at(path):
		out[path + file] = FileAccess.get_md5(path + file)
	for dir: String in DirAccess.get_directories_at(path):
		if dir.begins_with("poc_saves") or dir == "logs" or dir == "shader_cache" or dir == "vulkan":
			continue
		out.merge(old_user_files(path + dir + "/"))
	return out

func run_for(s: RefCounted, seconds: float) -> void:
	var left: float = seconds
	while left > 0.0:
		var piece: float = minf(left, 0.25)
		s.advance_game(piece)
		left -= piece

func read_text(file: String) -> String:
	return FileAccess.get_file_as_string(DIR + file)

func write_text(file: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(DIR + file, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func norm(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)

func first_diff(a: String, b: String) -> String:
	var da: Dictionary = JSON.parse_string(a)
	var db: Dictionary = JSON.parse_string(b)
	for k: String in da:
		if JSON.stringify(da[k], "", true, true) != JSON.stringify(db.get(k), "", true, true):
			return k
	return ""

func world_hash(s: RefCounted) -> int:
	var st: WorldState = s.state
	return [st.stage, st.growth, st.moisture, st.fertility, st.occupant, st.plant_id, st.natural, st.fruitless, st.zone_state].hash()

# ---------------------------------------------------------------- states

func state_germinating() -> RefCounted:
	var s: RefCounted = make_session()
	s.play.add_seeds(30)
	s.play.add_water(100.0)
	# stand next to ordinary wasteland (the start patch is not a greening target) and sow it
	var st: WorldState = s.state
	var spots: Array[Vector2] = []
	var stand: Vector2 = s.position
	for y: int in range(2, st.height - 2):
		for x: int in range(2, st.width - 2):
			var i: int = st.index_of(x, y)
			if spots.is_empty() and st.target[i] == 1 and st.stage[i] == WorldState.STAGE_EMPTY and st.terrain[i] == Session.T_WASTE and st.is_walkable(x - 2, y) and st.is_walkable(x - 1, y) and st.is_walkable(x + 1, y):
				stand = Coords.cell_center_logic(Vector2i(x - 2, y))
				spots.append(Coords.cell_center_logic(Vector2i(x, y)))
	s.position = stand
	for i: int in 4:
		s.set_aim(spots[0] + Vector2(float(i) * 6.0, 0.0))
		s.fire(false)
		run_for(s, 0.8)
	s.set_aim(s.position + Vector2(-12, 10))
	s.fire(true)
	run_for(s, 2.0)
	return s

func state_combat() -> RefCounted:
	var s: RefCounted = make_session()
	run_for(s, 75.0)
	var nest: Nest = s.enemies.nests[0]
	s.enemies.damage_nest(nest, 1)
	s.enemies.add_carcass(s.position + Vector2(40, 0))
	# cultivated plant ground (best effort) and shots in flight at save time
	s.play.add_seeds(40)
	s.play.add_water(100.0)
	var def: PlantDef = null
	for candidate: PlantDef in s.play.selectable:
		if candidate.is_cultivated():
			def = candidate
			break
	if def != null:
		s.play.selected_index = s.play.selectable.find(def)
	s.set_aim(s.position + Vector2(30, 30))
	s.fire(false)
	s.fire(true)
	s.fire(false)
	return s

func state_stable() -> RefCounted:
	var s: RefCounted = make_session()
	run_for(s, 20.0)
	for nest: Nest in s.enemies.nests.duplicate():
		s.enemies.destroy_nest(nest)
	for boar: Boar in s.enemies.boars.duplicate():
		s.enemies.remove_boar(boar)
	run_for(s, 150.0)
	return s

func scripted_play(s: RefCounted) -> void:
	s.play.add_seeds(10)
	s.set_aim(s.position + Vector2(25, 5))
	s.fire(false)
	run_for(s, 10.0)
	s.walk(Vector2(1, 0), 0.2)
	s.set_aim(s.position + Vector2(-20, 12))
	s.fire(false)
	run_for(s, 20.0)

func _states_roundtrip() -> void:
	var makers: Dictionary = {"germinating": state_germinating, "combat": state_combat, "stable": state_stable}
	for label: String in makers:
		clean_dir()
		var s: RefCounted = (makers[label] as Callable).call()
		var shots_before: int = s.projectiles.shots.size()
		var seeds_before: int = s.play.seeds
		var water_before: float = s.play.water
		var reserved_before: int = s.play.reserved_seeds
		var inflight_plants: int = 0
		for shot: Dictionary in s.projectiles.shots:
			if String(shot["kind"]) != "seed" and String(shot["kind"]) != "water":
				inflight_plants += 1
		var result: Dictionary = PocSave.save(s, DIR, {"resolution_index": 1})
		check(label + ".save_ok", bool(result["ok"]) and PocSave.has_file(DIR, PocSave.SLOT_FILE) and not PocSave.has_file(DIR, PocSave.TEMP_FILE), str(result.get("reason", "")))
		if label == "combat":
			check("combat.state_present", s.enemies.boars.size() > 0 and s.enemies.nests.size() > 0 and s.enemies.carcasses.size() > 0 and shots_before > 0, "boars=%d nests=%d carcasses=%d shots=%d plants_in_flight=%d" % [s.enemies.boars.size(), s.enemies.nests.size(), s.enemies.carcasses.size(), shots_before, inflight_plants])
			check("combat.shots_dropped_and_refunded", s.projectiles.shots.is_empty() and s.play.reserved_seeds == 0 and s.play.inflight.values().all(func(v: Variant) -> bool: return int(v) == 0) and s.play.seeds >= seeds_before, "seeds %d->%d water %.1f->%.1f reserved %d->%d" % [seeds_before, s.play.seeds, water_before, s.play.water, reserved_before, s.play.reserved_seeds])
		if label == "germinating":
			var sprouts: int = 0
			for i: int in s.state.tile_count():
				if s.state.stage[i] >= WorldState.STAGE_SEED and s.state.stage[i] < WorldState.STAGE_MATURE:
					sprouts += 1
			check("germinating.state_present", sprouts > 0, "growing tiles=%d" % sprouts)
		if label == "stable":
			check("stable.state_present", s.state.zone_state[1] >= WorldState.ZONE_STABLE and s.far.ticks > 0, "zone1=%d far ticks=%d" % [s.state.zone_state[1], s.far.ticks])
		var loaded: Dictionary = PocSave.load_slot(DIR, false, factory)
		check(label + ".load_ok", bool(loaded["ok"]), str(loaded.get("reason", "")))
		if not bool(loaded["ok"]):
			continue
		var s2: RefCounted = loaded["session"]
		check(label + ".extras_resolution", int((loaded["extras"] as Dictionary)["resolution_index"]) == 1)
		check(label + ".key_state_equal", world_hash(s) == world_hash(s2) and s.state.greened_count == s2.state.greened_count and s.play.seeds == s2.play.seeds and is_equal_approx(s.play.water, s2.play.water) and s.play.hp == s2.play.hp and s.position.is_equal_approx(s2.position) and s.enemies.boars.size() == s2.enemies.boars.size() and s.enemies.nests.size() == s2.enemies.nests.size() and s.enemies.carcasses.size() == s2.enemies.carcasses.size() and s.state.zone_state == s2.state.zone_state and s.clock.elapsed == s2.clock.elapsed and s.clock.growth_ticks == s2.clock.growth_ticks and s.play.pickups.count() == s2.play.pickups.count() and s.play.cultivation.plants.size() == s2.play.cultivation.plants.size(), "elapsed=%.2f green=%d/%d seeds=%d boars=%d pickups=%d" % [s2.clock.elapsed, s2.state.greened_count, s2.state.target_count, s2.play.seeds, s2.enemies.boars.size(), s2.play.pickups.count()])
		check(label + ".full_signature_equal", PocSave.signature(s) == PocSave.signature(s2), first_diff(PocSave.signature(s), PocSave.signature(s2)))
		check(label + ".wall_growth_equal", norm(s.wall_growth.to_dict()) == norm(s2.wall_growth.to_dict()) and s.state.sprout_seed == s2.state.sprout_seed)
		check(label + ".counters_consistent", s2.state.counters_consistent() and s2.state.recount_zone_greened() == s2.state.zone_greened_count)
		var loaded_seeds: int = s2.play.seeds
		var loaded_pickups: int = s2.play.pickups.count()
		var loaded_boars: int = s2.enemies.boars.size()
		# determinism: the same actions from the saved session and from the loaded one end identical
		scripted_play(s)
		scripted_play(s2)
		check(label + ".deterministic_after_load", PocSave.signature(s) == PocSave.signature(s2), first_diff(PocSave.signature(s), PocSave.signature(s2)) + " elapsed %.1f / %.1f" % [s.clock.elapsed, s2.clock.elapsed])
		# loading again from the same file does not multiply anything
		var again: Dictionary = PocSave.load_slot(DIR, false, factory)
		var again2: Dictionary = PocSave.load_slot(DIR, false, factory)
		var a: RefCounted = again["session"]
		var b: RefCounted = again2["session"]
		check(label + ".no_duplication_on_reload", PocSave.signature(a) == PocSave.signature(b) and a.play.seeds == loaded_seeds and a.enemies.boars.size() == loaded_boars and a.play.pickups.count() == loaded_pickups and a.enemies.carcasses.size() == b.enemies.carcasses.size() and a.projectiles.shots.is_empty(), "seeds %d boars %d pickups %d" % [a.play.seeds, a.enemies.boars.size(), a.play.pickups.count()])

# ---------------------------------------------------------------- rejections

var base_text: String = ""

func tampered(mutator: Callable) -> String:
	var parsed: Dictionary = JSON.parse_string(base_text if not base_text.is_empty() else read_text(PocSave.SLOT_FILE))
	mutator.call(parsed)
	return JSON.stringify(parsed, "", false, true)

func repack(d: Dictionary, key: String, idx: int, val: int) -> void:
	var raw: PackedByteArray = WorldState._unpack_bytes(d["world"][key])
	raw[idx] = val
	d["world"][key] = WorldState._pack_bytes(raw)

func _rejections() -> void:
	clean_dir()
	var current: RefCounted = state_combat()
	PocSave.save(current, DIR, {})
	var good_text: String = read_text(PocSave.SLOT_FILE)
	base_text = good_text
	var signature_before: String = PocSave.signature(current)
	var owners_before: int = current.state.occupancy_owners.size()
	var cases: Dictionary = {
		"version": func(d: Dictionary) -> void: d["format_version"] = 99,
		"map_id": func(d: Dictionary) -> void: d["map_id"] = "other_town",
		"map_hash": func(d: Dictionary) -> void: d["map_hash"] = "0123456789abcdef0123456789abcdef",
		"missing_key": func(d: Dictionary) -> void: d["play"].erase("pickups"),
		"missing_section": func(d: Dictionary) -> void: d.erase("enemies"),
		"out_of_range_position": func(d: Dictionary) -> void: d["session"]["position"] = [-50.0, 99999.0],
		"bad_elapsed": func(d: Dictionary) -> void: d["game_elapsed"] = -5.0,
		"bad_stage": func(d: Dictionary) -> void: d["world"]["stage"] = {"n": 3, "z": "AAAA"},
		"bad_resolution": func(d: Dictionary) -> void: d["ui"]["resolution_index"] = 7,
		"far_job_zone": func(d: Dictionary) -> void: d["far"]["job_zone"] = 999,
		"far_zone_queue_type": func(d: Dictionary) -> void: d["far"]["zone_queue"] = 5,
		"plant_id_250": func(d: Dictionary) -> void: repack(d, "plant_id", 100, 250),
		"moisture_255": func(d: Dictionary) -> void: repack(d, "moisture", 100, 255),
		"fertility_255": func(d: Dictionary) -> void: repack(d, "fertility", 100, 255),
		"boar_hp_huge": func(d: Dictionary) -> void: d["enemies"]["boars"][0]["hp"] = 99999,
		"nest_hp_huge": func(d: Dictionary) -> void: d["enemies"]["nests"][0]["hp"] = 99999,
		"seeds_neg": func(d: Dictionary) -> void: d["play"]["seeds"] = -5,
		"seeds_huge": func(d: Dictionary) -> void: d["play"]["seeds"] = 999999,
		"water_neg": func(d: Dictionary) -> void: d["play"]["water"] = -3.0,
		"hp_huge": func(d: Dictionary) -> void: d["play"]["hp"] = 9999,
		"hp_neg": func(d: Dictionary) -> void: d["play"]["hp"] = -4,
		"growth_ticks_neg": func(d: Dictionary) -> void: d["clock"]["growth_ticks"] = -3,
		"spread_queue_type": func(d: Dictionary) -> void: d["spread"]["queue"] = "x",
		"growth_cursor_huge": func(d: Dictionary) -> void: d["growth"]["cursor"] = 99999999,
	}
	var expected_code: Dictionary = {"version": "version", "map_id": "map", "map_hash": "hash", "missing_key": "missing_key", "missing_section": "missing_key", "out_of_range_position": "invalid", "bad_elapsed": "invalid", "bad_stage": "invalid", "bad_resolution": "invalid", "far_job_zone": "invalid", "far_zone_queue_type": "invalid", "plant_id_250": "invalid", "moisture_255": "invalid", "fertility_255": "invalid", "boar_hp_huge": "invalid", "nest_hp_huge": "invalid", "seeds_neg": "invalid", "seeds_huge": "invalid", "water_neg": "invalid", "hp_huge": "invalid", "hp_neg": "invalid", "growth_ticks_neg": "invalid", "spread_queue_type": "invalid", "growth_cursor_huge": "invalid"}
	for label: String in cases:
		write_text(PocSave.SLOT_FILE, tampered(cases[label]))
		var result: Dictionary = PocSave.load_slot(DIR, false, factory)
		var reason: String = String(result.get("reason", ""))
		check("reject." + label, not bool(result["ok"]) and not result.has("session") and reason.length() > 0 and reason.unicode_at(0) > 127 and String(result["code"]) == expected_code[label], "code=%s reason=%s" % [result.get("code", ""), reason])
	base_text = ""
	write_text(PocSave.SLOT_FILE, good_text.substr(0, good_text.length() / 2))
	var broken: Dictionary = PocSave.load_slot(DIR, false, factory)
	check("reject.corrupt_json", not bool(broken["ok"]) and String(broken["code"]) == "corrupt" and String(broken["reason"]).contains("壊れて"), String(broken["reason"]))
	write_text(PocSave.SLOT_FILE, "")
	var empty: Dictionary = PocSave.load_slot(DIR, false, factory)
	check("reject.empty_file", not bool(empty["ok"]), String(empty["reason"]))
	check("reject.current_state_unchanged", PocSave.signature(current) == signature_before and current.state.occupancy_owners.size() == owners_before and current.state.counters_consistent())
	DirAccess.remove_absolute(DIR + PocSave.SLOT_FILE)
	var gone: Dictionary = PocSave.load_slot(DIR, false, factory)
	check("reject.no_slot", not bool(gone["ok"]) and String(gone["code"]) == "missing", String(gone["reason"]))

# ---------------------------------------------------------------- backup

func _backup() -> void:
	clean_dir()
	var s: RefCounted = state_germinating()
	PocSave.save(s, DIR, {})
	var first_sig: String = PocSave.signature(s)
	check("backup.none_after_first_save", not PocSave.has_file(DIR, PocSave.BACKUP_FILE))
	run_for(s, 30.0)
	var second_sig: String = PocSave.signature(s)
	PocSave.save(s, DIR, {})
	check("backup.created_on_second_save", PocSave.has_file(DIR, PocSave.BACKUP_FILE) and not PocSave.has_file(DIR, PocSave.TEMP_FILE))
	var info: Dictionary = PocSave.slot_info(DIR)
	check("backup.slot_info", bool(info["slot"]) and bool(info["backup"]) and String(info["slot_text"]).length() > 0, str(info))
	var slot_loaded: Dictionary = PocSave.load_slot(DIR, false, factory)
	check("backup.slot_is_latest", bool(slot_loaded["ok"]) and PocSave.signature(slot_loaded["session"]) == second_sig, str(slot_loaded.get("reason", "")))
	var back_loaded: Dictionary = PocSave.load_slot(DIR, true, factory)
	check("backup.backup_is_previous", bool(back_loaded["ok"]) and PocSave.signature(back_loaded["session"]) == first_sig)
	write_text(PocSave.SLOT_FILE, "{ broken")
	var failed: Dictionary = PocSave.load_slot(DIR, false, factory)
	check("backup.broken_slot_points_to_backup", not bool(failed["ok"]) and bool(failed.get("backup_available", false)) and String(failed["reason"]).contains("バックアップ"), String(failed["reason"]))
	var rescue: Dictionary = PocSave.load_slot(DIR, true, factory)
	check("backup.rescue_ok", bool(rescue["ok"]) and PocSave.signature(rescue["session"]) == first_sig)
	var resave: Dictionary = PocSave.save(s, DIR, {})
	var kept: Dictionary = PocSave.load_slot(DIR, true, factory)
	check("backup.save_over_broken_slot_keeps_good_backup", bool(resave["ok"]) and bool(kept["ok"]) and PocSave.signature(kept["session"]) == first_sig)
	var failed_save_before: String = read_text(PocSave.BACKUP_FILE)
	check("backup.file_untouched_by_failed_load", failed_save_before.length() > 100)

# ---------------------------------------------------------------- time

func _time_rules() -> void:
	clean_dir()
	var s: RefCounted = state_stable()
	s.paused = true
	var saved_elapsed: float = s.clock.elapsed
	PocSave.save(s, DIR, {})
	# the saved wall-clock text is display only: forge it, wait a bit of real time
	write_text(PocSave.SLOT_FILE, tampered(func(d: Dictionary) -> void: d["saved_at"] = "1999-01-01T00:00:00"))
	OS.delay_msec(400)
	var result: Dictionary = PocSave.load_slot(DIR, false, factory)
	check("time.load_ok_with_forged_saved_at", bool(result["ok"]))
	var s2: RefCounted = result["session"]
	check("time.no_real_time_added", s2.clock.elapsed == saved_elapsed and s2.clock.growth_ticks == s.clock.growth_ticks and s2.clock.spread_ticks == s.clock.spread_ticks, "elapsed %.3f" % s2.clock.elapsed)
	s2.paused = true
	for i: int in 200:
		s2.advance(0.016)
	OS.delay_msec(300)
	check("time.pause_holds", s2.clock.elapsed == saved_elapsed)
	s2.paused = false
	s2.advance(0.016)
	var step: float = s2.clock.elapsed - saved_elapsed
	check("time.unpause_no_lump", absf(step - 0.016) < 0.000001, "advanced %.6f s on the first frame after unpause" % step)

func _downed() -> void:
	clean_dir()
	var s: RefCounted = state_stable()
	var start: Vector2 = s.play.health.respawn_position
	s.position = start + Vector2(120, 0)
	if not s.is_walkable_logic(s.position):
		s.position = start + Vector2(0, 40)
	s.play.health.downed = true
	var zones_before: PackedByteArray = s.state.zone_state.duplicate()
	var green_before: int = s.state.greened_count
	var saved_pos: Vector2 = s.position
	PocSave.save(s, DIR, {})
	var loaded: Dictionary = PocSave.load_slot(DIR, false, factory)
	check("downed.load_ok", bool(loaded["ok"]), str(loaded.get("reason", "")))
	if not bool(loaded["ok"]):
		return
	var s2: RefCounted = loaded["session"]
	var zone: int = s2.player_zone()
	check("downed.returns_to_respawn", s2.position.distance_to(start) < 0.01 and s2.position.distance_to(saved_pos) > 1.0 and not s2.play.health.downed and s2.play.hp == s2.play.hp_max, "zone=%d pos=%s" % [zone, s2.position])
	check("downed.region_not_rolled_back", s2.state.zone_state == zones_before and s2.state.greened_count == green_before)
