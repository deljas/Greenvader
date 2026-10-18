extends SceneTree
## HLP-01 independent verification (headless): conditions 1, 2, 3 and the pause / save parts of 5.
##   godot --headless --path <repo> --script res://tests/poc/independent/hlp01_core.gd
## Own save namespace user://poc_saves_indep_hlp01/. Costs / hp / counts are read from data/poc/helpers.json by this test itself.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const DIR: String = "user://poc_saves_indep_hlp01/"
const OUT: String = "res://evidence/helper/01/independent/"
var passes: int = 0
var fails: int = 0
var lines: PackedStringArray = PackedStringArray()
var keep: Array[RefCounted] = []
var cfg: Dictionary = {}

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
	else:
		fails += 1
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

func run_for(m: RefCounted, sec: float) -> void:
	var left: float = sec
	while left > 0.0:
		m.advance_game(minf(left, 0.25))
		left -= 0.25

func kind_cfg(key: String) -> Dictionary:
	for k: Variant in cfg["kinds"]:
		if String(k["key"]) == key:
			return k
	return {}

func cell_center(origin: Vector2i) -> Vector2:
	return (Vector2(origin) + Vector2(2, 2)) * 4.0

## Own classification of a 4x4 block from the world arrays: "free" (walkable target plantable, mature, unoccupied) or the first problem.
func classify(st: WorldState, ox: int, oy: int) -> String:
	var immature: bool = false
	var taken: bool = false
	for y: int in range(oy, oy + 4):
		for x: int in range(ox, ox + 4):
			if not st.in_bounds(x, y):
				return "bounds"
			var i: int = st.index_of(x, y)
			if not st.is_walkable(x, y) or st.target[i] == 0:
				return "bad_ground"
			if st.occupant[i] != 0:
				taken = true
			elif st.stage[i] != WorldState.STAGE_MATURE:
				immature = true
	if taken:
		return "taken"
	return "immature" if immature else "free"

func find_blocks(st: WorldState, kind: String, near: Vector2i, count: int, avoid: Array[Vector2i] = []) -> Array[Vector2i]:
	var cands: Array[Vector2i] = []
	for oy: int in range(1, st.height - 5):
		for ox: int in range(1, st.width - 5):
			if classify(st, ox, oy) == kind:
				cands.append(Vector2i(ox, oy))
	cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - near).length_squared() < (b - near).length_squared())
	var out: Array[Vector2i] = []
	for c: Vector2i in cands:
		var clash: bool = false
		for o: Vector2i in out + avoid:
			if absi(o.x - c.x) < 6 and absi(o.y - c.y) < 6:
				clash = true
				break
		if not clash:
			out.append(c)
			if out.size() >= count:
				break
	return out

func sig(m: RefCounted) -> String:
	var st: WorldState = m.state
	return JSON.stringify([hash(st.stage), hash(st.occupant), hash(st.terrain), hash(st.plant_id), st.greened_count, st.target_count, m.play.seeds, snappedf(m.play.water, 0.001), m.play.cultivation.plants.size(), m.helpers.to_dict()])

func recount_green(st: WorldState) -> int:
	var n: int = 0
	for i: int in st.tile_count():
		if st.target[i] != 0 and st.stage[i] >= 2:
			n += 1
	return n

func helper_owner_count(st: WorldState) -> int:
	var n: int = 0
	for o: Variant in st.occupancy_owners:
		if int(o) >= WorldState.OWNER_BAND_HELPER and int(o) < WorldState.OWNER_BAND_NEST:
			n += 1
	return n

func clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)

func walk_towards(m: RefCounted, target: Vector2, max_steps: int) -> void:
	for i: int in max_steps:
		var d: Vector2 = target - m.position
		if d.length() < 3.0:
			return
		m.walk(Coords.ground_dir_to_screen(d.normalized()), 0.1)
		m.advance_game(0.1)

func read_slot() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DIR + PocSave.SLOT_FILE))

func write_slot(d: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(DIR + PocSave.SLOT_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "", false, true))
	f.close()

func _run() -> void:
	clean()
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/poc/helpers.json"))
	_drops()
	_place_and_reject()
	_lift_and_save()
	_pause()
	_save_rejects()
	clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var f: FileAccess = FileAccess.open(OUT + "core.log", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\nRESULT passes=%d failures=%d\n" % [passes, fails])
	f.close()
	print("RESULT passes=%d failures=%d" % [passes, fails])
	for m: RefCounted in keep:
		m.close()
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------ 1: acquisition
func _make_farm() -> RefCounted:
	var m: RefCounted = mk()
	var spots: Array[Vector2i] = find_blocks(m.state, "free", Vector2i(60, 60), 4)
	var kinds: Array[StringName] = [&"carrot", &"carrot", &"kiwi", &"carrot"]
	var placed: int = 0
	for i: int in spots.size():
		if m.play.cultivation.try_place(kinds[i], Vector2(float(spots[i].x + 2) * 4.0, float(spots[i].y + 2) * 4.0)) != null:
			placed += 1
	info("farm: %d cultivated plants placed" % placed)
	return m

func _drops() -> void:
	var a: RefCounted = _make_farm()
	var b: RefCounted = _make_farm()
	check("drop.farm_placed", a.play.cultivation.plants.size() == 4)
	run_for(a, 5.0)
	var any_mature: bool = false
	for p: CultivatedPlant in a.play.cultivation.plants:
		any_mature = any_mature or p.mature
	check("drop.none_before_maturity", not any_mature and a.helpers.dropped_total == 0 and a.helpers.pickups.is_empty(), "t=5s")
	run_for(b, 5.0)
	var first_drop_t: float = -1.0
	for i: int in 6000:
		a.advance_game(0.25)
		b.advance_game(0.25)
		if first_drop_t < 0.0 and a.helpers.dropped_total > 0:
			first_drop_t = a.clock.elapsed
	var mature_n: int = 0
	for p: CultivatedPlant in a.play.cultivation.plants:
		mature_n += 1 if p.mature else 0
	var rolls_max: int = mature_n * int(a.clock.elapsed / float(cfg["drop"]["interval_seconds"]))
	info("drops: t=%.0f mature=%d dropped=%d on_ground=%d first_drop_t=%.0f rolls<=%d chance=%s" % [a.clock.elapsed, mature_n, a.helpers.dropped_total, a.helpers.pickups.size(), first_drop_t, rolls_max, str(cfg["drop"]["chance"])])
	check("drop.mature_plants_drop_rarely", mature_n == 4 and a.helpers.dropped_total >= 5 and float(a.helpers.dropped_total) < 0.3 * float(rolls_max), "dropped=%d of <=%d rolls" % [a.helpers.dropped_total, rolls_max])
	check("drop.deterministic_same_seed_same_steps", JSON.stringify(a.helpers.to_dict()) == JSON.stringify(b.helpers.to_dict()))
	check("drop.ground_cap_respected", a.helpers.pickups.size() <= int(cfg["drop"]["ground_cap"]))
	# distinguishable resource: collecting changes helper seeds only
	var s: RefCounted = a
	var item: Dictionary = s.helpers.pickups[0]
	var item_pos: Vector2 = Vector2(float(item["x"]), float(item["y"]))
	var plain_seeds: int = s.play.seeds
	var plain_pick: int = s.play.pickups.count()
	var hs0: int = s.helpers.seeds
	var n0: int = s.helpers.pickups.size()
	# start a few tiles away on walkable ground (in the safe zone farm), then walk
	var start: Vector2 = item_pos + Vector2(26.0, 0.0)
	if not s.is_walkable_logic(start):
		start = item_pos + Vector2(-26.0, 0.0)
	s.position = start
	s.advance_game(0.05)
	var still: bool = false
	for q: Dictionary in s.helpers.pickups:
		still = still or Vector2(float(q["x"]), float(q["y"])).distance_to(item_pos) < 0.01
	check("collect.not_from_afar", still and s.position.distance_to(item_pos) > 20.0, "dist=%.1f" % s.position.distance_to(item_pos))
	walk_towards(s, item_pos, 80)
	check("collect.walk_up_increases_helper_seeds", s.helpers.seeds >= hs0 + 1, "helper seeds %d -> %d, dist %.1f" % [hs0, s.helpers.seeds, s.position.distance_to(item_pos)])
	info("farm collect: play.seeds %d->%d play.pickups %d->%d (ordinary fruit may be picked on the way)" % [plain_seeds, s.play.seeds, plain_pick, s.play.pickups.count()])
	# nest reward
	var m: RefCounted = mk()
	var nest: Nest = m.enemies.nests[1]
	var seeds_before: int = m.helpers.seeds
	var plain_before: int = m.play.seeds
	m.enemies.damage_nest(nest, 99999)
	var ordinary_drop: int = m.play.pickups.count()
	var reward: int = int(cfg["drop"]["nest_reward"])
	check("nest.reward_items_appear", m.helpers.pickups.size() == reward and m.helpers.seeds == seeds_before, "items=%d (data %d)" % [m.helpers.pickups.size(), reward])
	var near_nest: bool = true
	for it: Dictionary in m.helpers.pickups:
		near_nest = near_nest and Vector2(float(it["x"]), float(it["y"])).distance_to(nest.center_px(4)) < 20.0
	check("nest.reward_near_nest", near_nest)
	m.enemies.damage_nest(nest, 99999)
	check("nest.no_second_reward", m.helpers.pickups.size() == reward)
	for it: Dictionary in m.helpers.pickups.duplicate():
		walk_towards(m, Vector2(float(it["x"]), float(it["y"])) + Vector2(10, 0), 1)
		m.position = Vector2(float(it["x"]), float(it["y"])) + Vector2(8, 0)
		m.advance_game(0.1)
	check("nest.reward_collectable", m.helpers.seeds == seeds_before + reward, "helper seeds %d" % m.helpers.seeds)
	check("nest.helper_seed_separate_from_ordinary_seed", ordinary_drop != reward and m.play.seeds - plain_before == ordinary_drop and m.helpers.seeds == reward, "ordinary fruit dropped %d -> play.seeds +%d; helper seeds %d" % [ordinary_drop, m.play.seeds - plain_before, m.helpers.seeds])

# ------------------------------------------------------------------ 2: placement and rejection
func _place_and_reject() -> void:
	var m: RefCounted = mk()
	var h: RefCounted = m.helpers
	var st: WorldState = m.state
	h.add_seeds(20)
	var start_cell: Vector2i = Coords.logic_to_cell(m.position)
	var blocks: Array[Vector2i] = find_blocks(st, "free", start_cell, 7)
	check("place.free_blocks_found", blocks.size() == 7)
	var green0: int = st.greened_count
	var target0: int = st.target_count
	var uids: Array[int] = []
	var keys: Array[String] = ["gatlinger", "sprinkler", "army"]
	for i: int in 3:
		var key: String = keys[i]
		m.position = cell_center(blocks[i])
		m.set_aim(cell_center(blocks[i]))
		m.helper_mode = i
		var seeds_before: int = h.seeds
		var r: Dictionary = m.place_helper()
		var kc: Dictionary = kind_cfg(key)
		check("place.%s_ok_cost" % key, bool(r["ok"]) and seeds_before - h.seeds == int(kc["cost"]) and h.plant_by_uid(int(r["uid"])).get("hp", 0) == int(kc["hp"]), "cost %d" % (seeds_before - h.seeds))
		var uid: int = int(r["uid"])
		uids.append(uid)
		var owned: int = 0
		var outside: int = 0
		for y: int in range(blocks[i].y - 1, blocks[i].y + 5):
			for x: int in range(blocks[i].x - 1, blocks[i].x + 5):
				var inside: bool = x >= blocks[i].x and x < blocks[i].x + 4 and y >= blocks[i].y and y < blocks[i].y + 4
				var occ: int = st.occupant[st.index_of(x, y)]
				if inside and occ == WorldState.OWNER_BAND_HELPER + uid:
					owned += 1
				if not inside and occ == WorldState.OWNER_BAND_HELPER + uid:
					outside += 1
		check("place.%s_occupies_4x4_helper_band" % key, owned == 16 and outside == 0 and st.occupancy_owners.has(WorldState.OWNER_BAND_HELPER + uid))
	check("place.green_and_target_unchanged", st.greened_count == green0 and st.target_count == target0 and recount_green(st) == st.greened_count, "%d/%d recount %d" % [st.greened_count, st.target_count, recount_green(st)])
	# rejections: state must be bit-identical
	m.helper_mode = 0
	var base: String = sig(m)
	var cases: Dictionary = {}
	# occupied by helper
	m.position = cell_center(blocks[0])
	m.set_aim(cell_center(blocks[0]))
	cases["occupied_helper"] = m.place_helper()
	# partially overlapping a helper block
	m.set_aim(cell_center(blocks[0]) + Vector2(8, 0))
	cases["occupied_overlap"] = m.place_helper()
	# immature
	var imm: Array[Vector2i] = find_blocks(st, "immature", start_cell, 1)
	if imm.size() > 0:
		m.position = cell_center(imm[0])
		m.set_aim(cell_center(imm[0]))
		cases["immature"] = m.place_helper()
	# building and water
	for t: Array in [["building", Session.T_BUILDING], ["water", Session.T_WATER]]:
		var found: Vector2i = Vector2i(-1, -1)
		for y: int in range(1, st.height - 5):
			if found.x >= 0:
				break
			for x: int in range(1, st.width - 5):
				if st.terrain[st.index_of(x + 1, y + 1)] == int(t[1]):
					found = Vector2i(x, y)
					break
		if found.x >= 0:
			m.position = cell_center(found)
			m.set_aim(cell_center(found))
			cases[String(t[0])] = m.place_helper()
	# nest
	var nest: Nest = m.enemies.nests[0]
	var nest_origin: Vector2i = nest.tile - Vector2i(0, 0)
	m.position = cell_center(nest_origin)
	m.set_aim(cell_center(nest_origin))
	cases["nest"] = m.place_helper()
	# cultivated plant
	var cp: Array[Vector2i] = find_blocks(st, "free", start_cell, 1, blocks)
	m.play.cultivation.try_place(&"carrot", Vector2(float(cp[0].x + 2) * 4.0, float(cp[0].y + 2) * 4.0))
	base = sig(m)
	m.position = cell_center(cp[0])
	m.set_aim(cell_center(cp[0]))
	cases["occupied_cultivated"] = m.place_helper()
	# range
	var rb: Vector2i = blocks[3]
	m.position = cell_center(rb) + Vector2(60.0, 0.0)
	m.set_aim(cell_center(rb))
	cases["range"] = m.place_helper()
	# cost
	var saved_seeds: int = h.seeds
	h.seeds = 1
	m.position = cell_center(rb)
	m.set_aim(cell_center(rb))
	base = sig(m)
	cases["cost"] = m.place_helper()
	h.seeds = saved_seeds
	for k: String in cases:
		var r2: Dictionary = cases[k]
		info("reject %s -> code=%s reason=%s" % [k, str(r2["code"]), str(r2["reason"])])
		check("reject.%s_refused_with_reason" % k, not bool(r2["ok"]) and String(r2["reason"]).length() > 0)
	check("reject.all_cases_present", cases.has("immature") and cases.has("building") and cases.has("water") and cases.has("nest") and cases.size() == 9, str(cases.keys()))
	# state unchanged around each class (re-run singly with before/after signatures)
	var singles: Array = [["nest", cell_center(nest_origin), cell_center(nest_origin)], ["helper", cell_center(blocks[1]), cell_center(blocks[1])], ["range", cell_center(rb) + Vector2(60, 0), cell_center(rb)]]
	for sgl: Array in singles:
		m.position = sgl[1]
		m.set_aim(sgl[2])
		var before: String = sig(m)
		m.place_helper()
		check("reject.state_unchanged_%s" % sgl[0], sig(m) == before)
	h.seeds = 1
	m.position = cell_center(rb)
	m.set_aim(cell_center(rb))
	var b2: String = sig(m)
	m.place_helper()
	check("reject.state_unchanged_cost", sig(m) == b2)
	h.seeds = 20
	# limit: place until the data limit, then one more is refused
	var limit: int = int(cfg["place"]["max_helpers"])
	var more: Array[Vector2i] = find_blocks(st, "free", start_cell, 8, blocks.slice(0, 3) + cp)
	var placed_total: int = h.plants.size()
	for b: Vector2i in more:
		if placed_total >= limit:
			break
		m.position = cell_center(b)
		m.set_aim(cell_center(b))
		if bool(m.place_helper()["ok"]):
			placed_total += 1
	check("limit.reaches_data_limit", h.plants.size() == limit, "plants=%d limit=%d" % [h.plants.size(), limit])
	var extra: Array[Vector2i] = find_blocks(st, "free", start_cell, 1, blocks.slice(0, 3) + cp + more)
	var before_limit: String = ""
	if extra.size() > 0:
		h.seeds = 20
		m.position = cell_center(extra[0])
		m.set_aim(cell_center(extra[0]))
		before_limit = sig(m)
		var rl: Dictionary = m.place_helper()
		check("limit.refused_and_unchanged", not bool(rl["ok"]) and sig(m) == before_limit and String(rl["reason"]).length() > 0)
	else:
		check("limit.refused_and_unchanged", false, "no extra block")
	check("place.counters_consistent", st.counters_consistent() and recount_green(st) == st.greened_count and helper_owner_count(st) == limit)

# ------------------------------------------------------------------ 3: lift, replace, save
func _lift_and_save() -> void:
	clean()
	var m: RefCounted = mk()
	var h: RefCounted = m.helpers
	var st: WorldState = m.state
	h.add_seeds(12)
	var blocks: Array[Vector2i] = find_blocks(st, "free", Coords.logic_to_cell(m.position), 3)
	m.position = cell_center(blocks[0])
	m.set_aim(cell_center(blocks[0]))
	m.helper_mode = 2
	var r: Dictionary = m.place_helper()
	var uid: int = int(r["uid"])
	h.plants[0]["hp"] = 5
	var seeds_after_place: int = h.seeds
	var green: int = st.greened_count
	var lifted: Dictionary = m.lift_helper()
	check("lift.ok_no_cost_no_dup", bool(lifted["ok"]) and h.seeds == seeds_after_place and h.plants.size() == 0 and h.is_carrying() and h.total_count() == 1 and helper_owner_count(st) == 0)
	check("lift.cells_free_and_still_green", classify(st, blocks[0].x, blocks[0].y) == "free" and st.greened_count == green and recount_green(st) == green)
	# save while carrying
	var sv: Dictionary = PocSave.save(m, DIR, {"resolution_index": 0})
	check("saveCarry.save_ok", bool(sv["ok"]), str(sv.get("reason", "")))
	var ld: Dictionary = PocSave.load_slot(DIR, false, mk)
	check("saveCarry.load_ok", bool(ld["ok"]), str(ld.get("reason", "")))
	var n: RefCounted = ld["session"]
	check("saveCarry.no_dup_no_loss", n.helpers.is_carrying() and n.helpers.plants.size() == 0 and n.helpers.total_count() == 1 and helper_owner_count(n.state) == 0 and int(n.helpers.carried["uid"]) == uid and int(n.helpers.carried["hp"]) == 5 and n.helpers.seeds == seeds_after_place)
	# re-place after load (the carried one) at the second block: free, same uid, hp kept
	n.position = cell_center(blocks[1])
	n.set_aim(cell_center(blocks[1]))
	n.helper_mode = n.helpers.kind_index(String(n.helpers.carried["kind"]))
	var seeds_n: int = n.helpers.seeds
	var rp: Dictionary = n.place_helper()
	check("replaceAfterLoad.free_same_uid_hp", bool(rp["ok"]) and int(rp["uid"]) == uid and n.helpers.seeds == seeds_n and n.helpers.plants.size() == 1 and not n.helpers.is_carrying() and n.helpers.total_count() == 1 and int(n.helpers.plants[0]["hp"]) == 5 and helper_owner_count(n.state) == 1)
	# replace in the original session as well (E then place)
	m.position = cell_center(blocks[2])
	m.set_aim(cell_center(blocks[2]))
	m.helper_mode = 2
	var rp2: Dictionary = m.place_helper()
	check("replace.free_same_uid", bool(rp2["ok"]) and int(rp2["uid"]) == uid and h.seeds == seeds_after_place and h.total_count() == 1 and helper_owner_count(st) == 1)
	# save with a placed plant -> reload identical
	var sv2: Dictionary = PocSave.save(m, DIR, {"resolution_index": 0})
	var ld2: Dictionary = PocSave.load_slot(DIR, false, mk)
	check("savePlaced.roundtrip", bool(sv2["ok"]) and bool(ld2["ok"]) and JSON.stringify(ld2["session"].helpers.to_dict()) == JSON.stringify(h.to_dict()) and helper_owner_count(ld2["session"].state) == 1, str(ld2.get("reason", "")))
	# lift far away is refused
	m.position = cell_center(blocks[2]) + Vector2(100, 0)
	check("lift.too_far_refused", not bool(m.lift_helper()["ok"]) and h.plants.size() == 1)

# ------------------------------------------------------------------ 5 (part): pause
func _pause() -> void:
	var m: RefCounted = mk()
	var h: RefCounted = m.helpers
	m.enemies.damage_nest(m.enemies.nests[1], 99999)
	var it: Dictionary = h.pickups[0]
	m.position = Vector2(float(it["x"]), float(it["y"]))
	m.paused = true
	var ticks0: int = h.ticks
	var age0: float = float(h.pickups[0]["age"])
	m.advance_game(60.0)
	m.advance(60.0)
	check("pause.no_collect_no_age_no_roll", h.seeds == 0 and h.pickups.size() == int(cfg["drop"]["nest_reward"]) and h.ticks == ticks0 and float(h.pickups[0]["age"]) == age0)
	m.paused = false
	m.advance_game(0.2)
	check("pause.resumes_collect", h.seeds >= 1)
	# damage frozen while paused (boar placed beside a plant: pause test only)
	h.add_seeds(5)
	var blk: Array[Vector2i] = find_blocks(m.state, "free", Vector2i(80, 80), 1)
	m.position = cell_center(blk[0])
	m.set_aim(cell_center(blk[0]))
	m.helper_mode = 0
	var pr: Dictionary = m.place_helper()
	var plant: Dictionary = h.plant_by_uid(int(pr["uid"]))
	var hp0: int = int(plant["hp"])
	var boar: Boar = Boar.new()
	boar.id = 7001
	boar.zone = 1
	boar.hp = 3
	boar.pos = Vector2(float(blk[0].x + 4) * 4.0 + 2.0, float(blk[0].y + 2) * 4.0)
	m.enemies.boars.append(boar)
	m.paused = true
	m.advance_game(30.0)
	check("pause.no_damage", int(plant["hp"]) == hp0, "hp %d" % int(plant["hp"]))
	m.paused = false
	m.advance_game(0.1)
	check("pause.damage_resumes", int(plant["hp"]) < hp0, "hp %d -> %d" % [hp0, int(plant["hp"])])
	m.enemies.boars.erase(boar)

# ------------------------------------------------------------------ 5 (part): save v1 / out of range
func _save_rejects() -> void:
	clean()
	var m: RefCounted = mk()
	var h: RefCounted = m.helpers
	h.add_seeds(10)
	var blk: Array[Vector2i] = find_blocks(m.state, "free", Coords.logic_to_cell(m.position), 1)
	m.position = cell_center(blk[0])
	m.set_aim(cell_center(blk[0]))
	m.helper_mode = 0
	m.place_helper()
	PocSave.save(m, DIR, {"resolution_index": 0})
	var good: Dictionary = read_slot()
	info("slot top-level keys: %s format_version=%s" % [str(good.keys()), str(good.get("format_version"))])
	write_slot(good)
	var control: Dictionary = PocSave.load_slot(DIR, false, mk)
	check("saveReject.control_unmodified_loads", bool(control["ok"]), str(control.get("reason", "")))
	var mutations: Array = [
		["version_1", func(d: Dictionary) -> void: d["format_version"] = 1],
		["version_3", func(d: Dictionary) -> void: d["format_version"] = 3],
		["no_helpers_section", func(d: Dictionary) -> void: d.erase("helpers")],
		["seeds_over_max", func(d: Dictionary) -> void: d["helpers"]["seeds"] = 999],
		["seeds_negative", func(d: Dictionary) -> void: d["helpers"]["seeds"] = -3],
		["plant_hp_over_max", func(d: Dictionary) -> void: d["helpers"]["plants"][0]["hp"] = 999],
		["plant_hp_zero", func(d: Dictionary) -> void: d["helpers"]["plants"][0]["hp"] = 0],
		["plant_out_of_map", func(d: Dictionary) -> void: d["helpers"]["plants"][0]["x"] = 500],
		["plant_unknown_kind", func(d: Dictionary) -> void: d["helpers"]["plants"][0]["kind"] = "bogus"],
		["plant_moved_off_occupancy", func(d: Dictionary) -> void: d["helpers"]["plants"][0]["x"] = int(d["helpers"]["plants"][0]["x"]) + 6],
		["duplicate_plant", func(d: Dictionary) -> void: d["helpers"]["plants"].append(d["helpers"]["plants"][0].duplicate())],
		["pickup_out_of_range", func(d: Dictionary) -> void: d["helpers"]["pickups"].append({"x": 99999.0, "y": 5.0, "age": 0.0})],
		["carried_and_placed_same_uid", func(d: Dictionary) -> void: d["helpers"]["carried"] = {"uid": d["helpers"]["plants"][0]["uid"], "kind": "gatlinger", "hp": 3}],
	]
	for mut: Array in mutations:
		var d: Dictionary = JSON.parse_string(JSON.stringify(good))
		(mut[1] as Callable).call(d)
		write_slot(d)
		var before: String = sig(m)
		var res: Dictionary = PocSave.load_slot(DIR, false, mk)
		check("saveReject.%s" % mut[0], not bool(res["ok"]), "code=%s reason=%s" % [str(res.get("code", "")), str(res.get("reason", ""))])
		check("saveReject.%s_live_untouched" % mut[0], sig(m) == before)
	write_slot(good)
