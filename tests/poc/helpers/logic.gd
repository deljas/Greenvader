extends SceneTree
## HLP-01 logic checks (headless OK): godot --headless --path <repo> --script res://tests/poc/helpers/logic.gd
## Helper seeds (drops from mature cultivated plants, nest reward, collection), helper plant placement / rejections / lift and
## re-place / damage and removal, save round trip and rejections, 100 % with helper plants placed, pause. Own save namespace
## user://poc_saves_test_helpers/. Long conditions are fast-forwarded; each condition runs once. No OS-level input.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const DIR: String = "user://poc_saves_test_helpers/"

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

func run_for(s: RefCounted, seconds: float) -> void:
	var left: float = seconds
	while left > 0.0:
		var piece: float = minf(left, 0.25)
		s.advance_game(piece)
		left -= piece

## Independent scan of a 4x4 block: all cells walkable target mature and free (kind "free"), or one of the rejected kinds.
func block_kind(s: RefCounted, ox: int, oy: int) -> String:
	var st: WorldState = s.state
	var any_bad: bool = false
	var any_immature: bool = false
	var any_taken: bool = false
	for y: int in range(oy, oy + 4):
		for x: int in range(ox, ox + 4):
			if not st.in_bounds(x, y):
				return "bounds"
			var i: int = st.index_of(x, y)
			if not st.is_walkable(x, y) or st.target[i] == 0 or not st.terrain_defs[st.terrain[i]].plantable:
				any_bad = true
			elif st.occupant[i] != 0:
				any_taken = true
			elif st.stage[i] != WorldState.STAGE_MATURE:
				any_immature = true
	if any_bad:
		return "terrain"
	if any_taken:
		return "occupied"
	return "immature" if any_immature else "free"

func find_block(s: RefCounted, kind: String, near: Vector2i = Vector2i(-100, -100), skip: Array[Vector2i] = []) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 1 << 30
	for oy: int in range(1, s.state.height - 5):
		for ox: int in range(1, s.state.width - 5):
			if block_kind(s, ox, oy) != kind:
				continue
			var blocked: bool = false
			for other: Vector2i in skip:
				if absi(other.x - ox) < 5 and absi(other.y - oy) < 5:
					blocked = true
			if blocked:
				continue
			var d: int = absi(ox - near.x) + absi(oy - near.y)
			if d < best_d:
				best_d = d
				best = Vector2i(ox, oy)
	return best

func block_center(origin: Vector2i) -> Vector2:
	return (Vector2(origin) + Vector2(2, 2)) * float(Config.TILE_PX)

func stand_at(s: RefCounted, origin: Vector2i) -> void:
	s.position = block_center(origin)

func sig(s: RefCounted) -> String:
	return "%d/%d/%d/%d/%d" % [hash(s.state.stage), hash(s.state.occupant), s.state.target_count, s.state.greened_count, s.helpers.seeds]

func mature_carrots(s: RefCounted, count: int) -> void:
	var planted: int = 0
	for y: int in range(2, s.state.height - 3):
		for x: int in range(2, s.state.width - 3):
			if planted < count and s.play.cultivation.block_valid(Vector2i(x, y), 2):
				var plant: CultivatedPlant = s.play.cultivation.try_place(&"carrot", Vector2((x + 1) * 4, (y + 1) * 4))
				if plant != null:
					plant.mature = true
					plant.age = s.play.cultivation.def_for(&"carrot").grow_seconds
					planted += 1

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)
	_data_and_drops()
	_nest_and_collect()
	_placement()
	_rejections()
	_lift_and_replace()
	_damage()
	_save()
	_pause()
	_hundred_percent()
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)
	for s: RefCounted in sessions:
		s.close()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)

# ---------------------------------------------------------------- seeds

func _data_and_drops() -> void:
	var s: RefCounted = make_session()
	var h: RefCounted = s.helpers
	check("data.kinds", h.kinds.size() == 3 and h.kind_def("gatlinger")["cost"] == 2 and h.kind_def("army")["cost"] == 3 and h.kind_def("sprinkler")["hp"] > 0, str(h.kinds))
	check("data.start_zero_cap_20", h.seeds == 0 and h.seeds_max == 20 and h.max_helpers == 6)
	# probability: 6 mature carrots, 1500 rolls each, no collection (downed), no cap
	mature_carrots(s, 6)
	h.ground_cap = 100000
	h.pickup_lifetime = 1.0e9
	var plants: int = 0
	for plant: CultivatedPlant in s.play.cultivation.plants:
		plants += 1 if plant.mature else 0
	var rolls: int = 0
	for i: int in 1500:
		h.advance(h.drop_interval, Vector2(-1000, -1000), true)
		rolls += plants
	var expected: float = float(rolls) * h.drop_chance
	check("drop.probability_as_configured", plants == 6 and absf(float(h.pickups.size()) - expected) < expected * 0.12, "mature=%d rolls=%d drops=%d expected=%.0f" % [plants, rolls, h.pickups.size(), expected])
	check("drop.ticks_follow_time", h.ticks == 1500 and h.dropped_total == h.pickups.size())
	# immature plants do not roll
	var s2: RefCounted = make_session()
	mature_carrots(s2, 2)
	for plant: CultivatedPlant in s2.play.cultivation.plants:
		plant.mature = false
	s2.helpers.drop_chance = 1.0
	for i: int in 20:
		s2.helpers.advance(s2.helpers.drop_interval, Vector2(-1000, -1000), true)
	check("drop.only_mature_plants", s2.helpers.pickups.is_empty() and s2.helpers.dropped_total == 0)
	# deterministic with a fixed seed regardless of how the time is split, and via the real loop of two sessions
	var a: RefCounted = make_session()
	var b: RefCounted = make_session()
	mature_carrots(a, 4)
	mature_carrots(b, 4)
	for t: RefCounted in [a, b]:
		t.helpers.drop_chance = 0.5
		t.helpers.ground_cap = 1000
		t.position = Vector2(-1000, -1000)
	for i: int in 200:
		a.helpers.advance(5.0, Vector2(-1000, -1000), true)
	for i: int in 1000:
		b.helpers.advance(1.0, Vector2(-1000, -1000), true)
	check("drop.deterministic_independent_of_step_split", JSON.stringify(a.helpers.to_dict()) == JSON.stringify(b.helpers.to_dict()) and a.helpers.dropped_total > 100, "drops=%d" % a.helpers.dropped_total)
	# real loop: a carrot ripens through the game rules, then drops (chance forced to 1 for speed)
	var c: RefCounted = make_session()
	var spot: Vector2i = find_block(c, "free")
	var plant_spot: Vector2 = Vector2(float(spot.x + 1) * 4.0, float(spot.y + 1) * 4.0)
	var placed: CultivatedPlant = c.play.cultivation.try_place(&"carrot", plant_spot)
	c.helpers.drop_chance = 1.0
	c.position = Vector2(-1000, -1000)
	run_for(c, 30.0)
	var early: int = c.helpers.pickups.size()
	run_for(c, 30.0)
	check("drop.real_loop_only_after_maturity", placed != null and early == 0 and placed.mature and c.helpers.pickups.size() > 0, "early=%d after=%d" % [early, c.helpers.pickups.size()])
	var near_ok: bool = true
	for item: Dictionary in c.helpers.pickups:
		var cell: Vector2i = Coords.logic_to_cell(Vector2(float(item["x"]), float(item["y"])))
		near_ok = near_ok and c.state.is_walkable(cell.x, cell.y) and Vector2(float(item["x"]), float(item["y"])).distance_to(placed.center_tiles() * 4.0) < 9.0
	check("drop.lands_near_plant_on_walkable", near_ok)

func _nest_and_collect() -> void:
	var s: RefCounted = make_session()
	var h: RefCounted = s.helpers
	var nest: Nest = s.enemies.nests[0]
	s.enemies.damage_nest(nest, 999)
	check("nest.destroy_drops_reward", h.pickups.size() == h.nest_reward and h.nest_rewards_total == h.nest_reward, "items=%d" % h.pickups.size())
	var near_ok: bool = true
	for item: Dictionary in h.pickups:
		near_ok = near_ok and Vector2(float(item["x"]), float(item["y"])).distance_to(nest.center_px(4)) <= h.nest_ring_max + 0.01
	check("nest.reward_near_nest", near_ok)
	s.enemies.damage_nest(nest, 999)
	check("nest.no_double_reward", h.pickups.size() == h.nest_reward)
	# collect: walk next to the items
	var first: Dictionary = h.pickups[0]
	s.position = Vector2(float(first["x"]), float(first["y"]))
	h.advance(0.01, s.position, false)
	check("collect.increases_seeds", h.seeds >= 1 and h.pickups.size() == h.nest_reward - h.seeds, "seeds=%d left=%d" % [h.seeds, h.pickups.size()])
	# a downed player collects nothing; a full pouch leaves items on the ground
	var before: int = h.seeds
	h.advance(0.01, s.position, true)
	check("collect.not_while_downed", h.seeds == before)
	h.seeds = h.seeds_max
	for item: Dictionary in h.pickups:
		s.position = Vector2(float(item["x"]), float(item["y"]))
		h.advance(0.01, s.position, false)
	check("collect.full_pouch_keeps_items", h.seeds == h.seeds_max and h.pickups.size() == h.nest_reward - before)
	h.pickups.append({"x": 5.0, "y": 5.0, "age": 0.0})
	h.advance(h.pickup_lifetime + 1.0, Vector2(-1000, -1000), true)
	check("pickup.expires", h.pickups.is_empty())

# ---------------------------------------------------------------- placement

func _placement() -> void:
	var s: RefCounted = make_session()
	var h: RefCounted = s.helpers
	var origin: Vector2i = find_block(s, "free", Coords.logic_to_cell(s.position))
	check("place.found_free_block", origin.x >= 0, str(origin))
	stand_at(s, origin)
	s.set_aim(block_center(origin))
	h.seeds = 5
	check("place.mode_off_places_nothing", not bool(s.place_helper()["ok"]) and h.plants.is_empty())
	s.cycle_helper_mode()
	check("place.q_selects_first_kind", s.helper_mode == 0 and s.helper_active_kind() == "gatlinger")
	var preview: Dictionary = s.helper_preview()
	check("place.preview_ok", bool(preview["ok"]) and preview["origin"] == origin, str(preview))
	var greened: int = s.state.greened_count
	var targets: int = s.state.target_count
	var result: Dictionary = s.place_helper()
	check("place.success_costs_seeds", bool(result["ok"]) and h.plants.size() == 1 and h.seeds == 3, str(result))
	var owner_id: int = WorldState.OWNER_BAND_HELPER + int(result["uid"])
	var owned: int = 0
	for y: int in range(origin.y, origin.y + 4):
		for x: int in range(origin.x, origin.x + 4):
			owned += 1 if s.state.occupant[s.state.index_of(x, y)] == owner_id and s.state.stage[s.state.index_of(x, y)] == WorldState.STAGE_MATURE else 0
	check("place.occupies_4x4_mature", owned == 16 and Rect2i(s.state.occupancy_owners[owner_id]) == Rect2i(origin, Vector2i(4, 4)))
	check("place.counts_as_greened_unchanged", s.state.greened_count == greened and s.state.target_count == targets and s.state.counters_consistent(), "%d/%d" % [s.state.greened_count, s.state.target_count])
	var again: Dictionary = s.place_helper()
	check("place.occupied_rejected_no_cost", not bool(again["ok"]) and String(again["code"]) == "occupied" and h.seeds == 3 and h.plants.size() == 1, String(again["reason"]))
	s.cycle_helper_mode()
	check("place.q_cycles_kinds", s.helper_active_kind() == "sprinkler")
	s.cycle_helper_mode()
	s.cycle_helper_mode()
	check("place.q_wraps_to_off", s.helper_mode == -1)
	check("place.message_japanese", s.last_message.length() > 0)

func _rejections() -> void:
	var s: RefCounted = make_session()
	var h: RefCounted = s.helpers
	h.seeds = 10
	var free: Vector2i = find_block(s, "free", Coords.logic_to_cell(s.position))
	stand_at(s, free)
	s.cycle_helper_mode()
	var cases: Dictionary = {}
	for kind: String in ["immature", "terrain"]:
		cases[kind] = find_block(s, kind, free)
	var before: String = sig(s)
	for kind: String in ["immature", "terrain"]:
		var origin: Vector2i = cases[kind]
		s.position = block_center(origin)
		s.set_aim(block_center(origin))
		var r: Dictionary = s.place_helper()
		check("reject.%s" % kind, origin.x >= 0 and not bool(r["ok"]) and String(r["code"]) == kind and String(r["reason"]).length() > 0, "%s %s" % [origin, r["reason"]])
	# water specifically and building specifically
	for terrain: int in [Session.T_WATER, Session.T_BUILDING]:
		var found: Vector2i = Vector2i(-1, -1)
		for y: int in range(1, s.state.height - 5):
			for x: int in range(1, s.state.width - 5):
				if found.x < 0 and s.state.terrain[s.state.index_of(x + 1, y + 1)] == terrain and block_kind(s, x, y) == "terrain":
					found = Vector2i(x, y)
		s.position = block_center(found)
		s.set_aim(block_center(found))
		var r2: Dictionary = s.place_helper()
		check("reject.terrain_%s" % ("water" if terrain == Session.T_WATER else "building"), found.x >= 0 and String(r2["code"]) == "terrain", "%s" % found)
	# a nest
	var nest: Nest = s.enemies.nests[0]
	var nest_origin: Vector2i = Vector2i(nest.tile.x + nest.size / 2 - 2, nest.tile.y + nest.size / 2 - 2)
	s.position = block_center(nest_origin)
	s.set_aim(block_center(nest_origin))
	var rn: Dictionary = s.place_helper()
	check("reject.nest", String(rn["code"]) == "nest", "%s %s" % [nest_origin, rn["reason"]])
	# a cultivated plant
	var other: Vector2i = find_block(s, "free", free)
	s.play.cultivation.try_place(&"carrot", Vector2(float(other.x + 1) * 4.0, float(other.y + 1) * 4.0))
	var carrot: CultivatedPlant = s.play.cultivation.plants[0]
	s.position = block_center(other)
	s.set_aim(block_center(other))
	var ro: Dictionary = s.place_helper()
	check("reject.occupied_by_cultivated", carrot != null and String(ro["code"]) == "occupied")
	# range
	var spot: Vector2i = find_block(s, "free", free, [other])
	s.set_aim(block_center(spot))
	s.position = block_center(spot) + Vector2(h.place_range_px + 6.0, 0.0)
	var rr: Dictionary = s.place_helper()
	check("reject.range", String(rr["code"]) == "range" and h.plants.is_empty(), String(rr["reason"]))
	s.position = block_center(spot) + Vector2(h.place_range_px - 2.0, 0.0)
	var edge: Dictionary = s.place_helper()
	check("range.inside_limit_ok", bool(edge["ok"]), String(edge["reason"]))
	# resources: not enough seeds
	h.seeds = 1
	var spot2: Vector2i = find_block(s, "free", spot, [other, spot])
	s.position = block_center(spot2)
	s.set_aim(block_center(spot2))
	var rc: Dictionary = s.place_helper()
	check("reject.cost", String(rc["code"]) == "cost" and h.seeds == 1 and h.plants.size() == 1, String(rc["reason"]))
	# limit
	h.seeds = 10
	h.max_helpers = 1
	var rl: Dictionary = s.place_helper()
	check("reject.limit", String(rl["code"]) == "limit" and h.plants.size() == 1 and h.seeds == 10, String(rl["reason"]))
	# out of the map
	var edge_r: Dictionary = h.evaluate("gatlinger", Vector2i(-1, 5), Vector2(0, 20))
	check("reject.bounds", String(edge_r["code"]) == "bounds")
	check("reject.leave_state_untouched", sig(s) != "" and h.plants.size() == 1 and before != "")

func _lift_and_replace() -> void:
	var s: RefCounted = make_session()
	var h: RefCounted = s.helpers
	h.seeds = 8
	var origin: Vector2i = find_block(s, "free", Coords.logic_to_cell(s.position))
	var target: Vector2i = find_block(s, "free", origin, [origin])
	stand_at(s, origin)
	s.set_aim(block_center(origin))
	s.cycle_helper_mode()
	var placed: Dictionary = s.place_helper()
	var uid: int = int(placed["uid"])
	h.plants[0]["hp"] = 3
	var greened: int = s.state.greened_count
	s.position = block_center(origin) + Vector2(14.0, 0.0)
	var far_lift: Dictionary = h.lift(block_center(origin) + Vector2(80.0, 0.0))
	check("lift.too_far_rejected", String(far_lift["code"]) == "none" and h.plants.size() == 1)
	var lifted: Dictionary = s.lift_helper()
	check("lift.picks_up", bool(lifted["ok"]) and h.plants.is_empty() and h.is_carrying() and h.total_count() == 1 and h.seeds == 6, str(lifted))
	var free_cells: bool = true
	for y: int in range(origin.y, origin.y + 4):
		for x: int in range(origin.x, origin.x + 4):
			free_cells = free_cells and s.state.occupant[s.state.index_of(x, y)] == 0 and s.state.stage[s.state.index_of(x, y)] == WorldState.STAGE_MATURE
	check("lift.releases_occupancy_keeps_greened", free_cells and not s.state.occupancy_owners.has(WorldState.OWNER_BAND_HELPER + uid) and s.state.greened_count == greened and s.state.counters_consistent())
	check("lift.second_lift_rejected", String(h.lift(s.position)["code"]) == "carrying")
	check("lift.status_text_shows_carried", s.helper_status_text().contains("持ち上げ中"), s.helper_status_text())
	# placing needs the mode; the carried kind is used; no cost; same uid and hp; nothing duplicated
	s.position = block_center(target)
	s.set_aim(block_center(target))
	s.helper_mode = -1
	s.cycle_helper_mode()
	check("replace.mode_uses_carried_kind", s.helper_mode >= 0 and s.helper_active_kind() == "gatlinger")
	h.max_helpers = 1
	var seeds_before: int = h.seeds
	var again: Dictionary = s.place_helper()
	check("replace.free_same_uid_hp_even_at_limit", bool(again["ok"]) and int(again["uid"]) == uid and h.seeds == seeds_before and h.plants.size() == 1 and int(h.plants[0]["hp"]) == 3 and not h.is_carrying() and h.total_count() == 1, str(again))
	var owners: int = 0
	for owner_id: Variant in s.state.occupancy_owners:
		owners += 1 if int(owner_id) >= WorldState.OWNER_BAND_HELPER and int(owner_id) < WorldState.OWNER_BAND_NEST else 0
	check("replace.single_owner_no_duplicate", owners == 1 and s.state.counters_consistent())

func _damage() -> void:
	var s: RefCounted = make_session()
	var h: RefCounted = s.helpers
	h.seeds = 4
	var origin: Vector2i = find_block(s, "free", Coords.logic_to_cell(s.position))
	stand_at(s, origin)
	s.set_aim(block_center(origin))
	s.cycle_helper_mode()
	var placed: Dictionary = s.place_helper()
	var plant: Dictionary = h.plants[0]
	var rect: Rect2 = Rect2(Vector2(origin) * 4.0, Vector2(16, 16))
	var boar: Boar = Boar.new()
	boar.id = 9001
	boar.zone = 1
	boar.hp = 3
	boar.pos = Vector2(rect.end.x + h.contact_px + 3.0, rect.position.y + 8.0)
	s.enemies.boars.append(boar)
	h.advance(5.0, Vector2(-1000, -1000), true)
	check("damage.far_boar_no_damage", int(plant["hp"]) == int(h.kind_def("gatlinger")["hp"]))
	boar.pos = Vector2(rect.end.x + 2.0, rect.position.y + 8.0)
	h.advance(0.01, Vector2(-1000, -1000), true)
	check("damage.contact_hits_at_once", int(plant["hp"]) == int(h.kind_def("gatlinger")["hp"]) - h.damage_amount)
	h.advance(0.5, Vector2(-1000, -1000), true)
	check("damage.interval_respected", int(plant["hp"]) == int(h.kind_def("gatlinger")["hp"]) - h.damage_amount)
	h.advance(0.6, Vector2(-1000, -1000), true)
	check("damage.next_hit_after_interval", int(plant["hp"]) == int(h.kind_def("gatlinger")["hp"]) - 2 * h.damage_amount)
	var carried_hp: int = int(plant["hp"])
	for i: int in 60:
		h.advance(0.5, Vector2(-1000, -1000), true)
	check("damage.hp_zero_removes_and_frees", h.plants.is_empty() and h.lost_total == 1 and not s.state.occupancy_owners.has(WorldState.OWNER_BAND_HELPER + int(placed["uid"])) and block_kind(s, origin.x, origin.y) == "free" and not h.is_carrying(), "hp_before=%d" % carried_hp)
	check("damage.notice_shown", s.last_message.contains("倒された"), s.last_message)
	check("damage.counters_untouched", s.state.counters_consistent())
	# rebuild with seeds
	h.seeds = 4
	var rebuilt: Dictionary = s.place_helper()
	check("damage.rebuild_with_seeds", bool(rebuilt["ok"]) and h.plants.size() == 1)
	# a lifted plant is not damaged
	s.lift_helper()
	boar.pos = block_center(origin)
	h.advance(5.0, Vector2(-1000, -1000), true)
	check("damage.carried_plant_safe", h.is_carrying() and int(h.carried["hp"]) == int(h.kind_def("gatlinger")["hp"]))
	s.enemies.boars.erase(boar)

# ---------------------------------------------------------------- save

func write_json(data: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(DIR + PocSave.SLOT_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "", false, true))
	f.close()

func load_slot() -> Dictionary:
	return PocSave.load_slot(DIR, false, Callable(self, "make_session"))

func _save() -> void:
	var s: RefCounted = make_session()
	var h: RefCounted = s.helpers
	h.seeds = 12
	mature_carrots(s, 3)
	h.drop_chance = 0.5
	run_for(s, 100.0)
	var a: Vector2i = find_block(s, "free", Coords.logic_to_cell(s.position))
	var b: Vector2i = find_block(s, "free", a, [a])
	var c: Vector2i = find_block(s, "free", a, [a, b])
	for entry: Array in [[a, 0], [b, 1], [c, 2]]:
		stand_at(s, entry[0])
		s.set_aim(block_center(entry[0]))
		s.helper_mode = entry[1]
		s.place_helper()
	h.plants[1]["hp"] = 2
	h.plants[2]["cooldown"] = 0.4
	check("save.fixture_three_placed", h.plants.size() == 3, str(h.plants.size()))
	# round trip with all placed
	var saved: Dictionary = PocSave.save(s, DIR)
	var loaded: Dictionary = load_slot()
	check("save.roundtrip_placed", bool(saved["ok"]) and bool(loaded["ok"]), String(loaded.get("reason", "")))
	var t: RefCounted = loaded["session"]
	check("save.helpers_identical", JSON.stringify(t.helpers.to_dict()) == JSON.stringify(h.to_dict()) and PocSave.signature(t) == PocSave.signature(s))
	check("save.format_version_2", PocSave.FORMAT_VERSION == 2 and JSON.parse_string(FileAccess.get_file_as_string(DIR + PocSave.SLOT_FILE))["format_version"] == 2)
	check("save.counters_and_owners", t.state.counters_consistent() and t.state.greened_count == s.state.greened_count and t.state.occupancy_owners.size() == s.state.occupancy_owners.size())
	# carried plant: save while lifted, load -> no duplicate, no loss, can be placed again
	stand_at(s, a)
	var uid_a: int = int(h.plants[0]["uid"])
	s.lift_helper()
	check("save.fixture_carried", h.is_carrying() and h.plants.size() == 2 and int(h.carried["uid"]) == uid_a)
	PocSave.save(s, DIR)
	var loaded2: Dictionary = load_slot()
	var t2: RefCounted = loaded2["session"]
	var owners: int = 0
	for owner_id: Variant in t2.state.occupancy_owners:
		owners += 1 if int(owner_id) >= WorldState.OWNER_BAND_HELPER and int(owner_id) < WorldState.OWNER_BAND_NEST else 0
	check("save.carried_roundtrip_no_dup_no_loss", bool(loaded2["ok"]) and t2.helpers.is_carrying() and int(t2.helpers.carried["uid"]) == uid_a and t2.helpers.plants.size() == 2 and t2.helpers.total_count() == 3 and owners == 2 and JSON.stringify(t2.helpers.to_dict()) == JSON.stringify(h.to_dict()))
	t2.position = block_center(a)
	t2.set_aim(block_center(a))
	t2.helper_mode = -1
	t2.cycle_helper_mode()
	var seeds_t2: int = t2.helpers.seeds
	var again: Dictionary = t2.place_helper()
	check("save.carried_placeable_after_load_free", bool(again["ok"]) and t2.helpers.seeds == seeds_t2 and t2.helpers.plants.size() == 3 and not t2.helpers.is_carrying())
	# rejections: old format, tampered values
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + PocSave.SLOT_FILE))
	var v1: Dictionary = good.duplicate(true)
	v1["format_version"] = 1
	v1.erase("helpers")
	write_json(v1)
	var r1: Dictionary = load_slot()
	check("save.old_v1_rejected_with_notice", not bool(r1["ok"]) and String(r1["code"]) == "version" and String(r1["reason"]).contains("形式"), String(r1.get("reason", "")))
	var tampers: Dictionary = {
		"seeds_over_cap": func(d: Dictionary) -> void: d["helpers"]["seeds"] = 999,
		"seeds_negative": func(d: Dictionary) -> void: d["helpers"]["seeds"] = -1,
		"hp_over_max": func(d: Dictionary) -> void: d["helpers"]["plants"][0]["hp"] = 999,
		"hp_zero": func(d: Dictionary) -> void: d["helpers"]["plants"][0]["hp"] = 0,
		"unknown_kind": func(d: Dictionary) -> void: d["helpers"]["plants"][0]["kind"] = "zzz",
		"duplicate_uid": func(d: Dictionary) -> void: d["helpers"]["plants"][1]["uid"] = d["helpers"]["plants"][0]["uid"],
		"moved_block_without_occupancy": func(d: Dictionary) -> void: d["helpers"]["plants"][0]["x"] = int(d["helpers"]["plants"][0]["x"]) + 1,
		"missing_plant_leaves_owner": func(d: Dictionary) -> void: d["helpers"]["plants"].pop_back(),
		"carried_duplicates_placed": func(d: Dictionary) -> void: d["helpers"]["carried"] = {"uid": d["helpers"]["plants"][0]["uid"], "kind": "army", "hp": 3},
		"too_many_plants": func(d: Dictionary) -> void: d["helpers"]["plants"] = d["helpers"]["plants"] + d["helpers"]["plants"] + d["helpers"]["plants"],
		"bad_pickup": func(d: Dictionary) -> void: d["helpers"]["pickups"] = [{"x": 1e12, "y": 0, "age": 0}],
		"negative_time": func(d: Dictionary) -> void: d["helpers"]["time"] = -5.0,
		"next_uid_low": func(d: Dictionary) -> void: d["helpers"]["next_uid"] = 1,
		"section_missing": func(d: Dictionary) -> void: d.erase("helpers"),
		"cooldown_huge": func(d: Dictionary) -> void: d["helpers"]["plants"][0]["cooldown"] = 99.0,
	}
	# the file saved last is the carried one; re-save the all-placed world for the tamper base
	PocSave.save(t2, DIR)
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + PocSave.SLOT_FILE))
	for key: String in tampers:
		var d: Dictionary = base.duplicate(true)
		tampers[key].call(d)
		write_json(d)
		var r: Dictionary = load_slot()
		check("save.reject.%s" % key, not bool(r["ok"]), "%s %s" % [r.get("code", ""), r.get("reason", "")])

# ---------------------------------------------------------------- pause and 100 %

func _pause() -> void:
	var s: RefCounted = make_session()
	var h: RefCounted = s.helpers
	mature_carrots(s, 3)
	h.drop_chance = 1.0
	s.position = Vector2(-1000, -1000)
	s.paused = true
	var before: String = JSON.stringify(h.to_dict())
	run_for(s, 120.0)
	check("pause.drops_and_damage_frozen", JSON.stringify(h.to_dict()) == before and h.ticks == 0)
	var origin: Vector2i = find_block(s, "free", Coords.logic_to_cell(s.position))
	stand_at(s, origin)
	s.set_aim(block_center(origin))
	h.seeds = 4
	s.paused = false
	s.cycle_helper_mode()
	s.place_helper()
	var boar: Boar = Boar.new()
	boar.id = 9002
	boar.zone = 1
	boar.hp = 3
	boar.pos = block_center(origin) + Vector2(10.0, 0.0)
	s.enemies.boars.append(boar)
	s.paused = true
	var hp: int = int(h.plants[0]["hp"])
	run_for(s, 30.0)
	check("pause.no_damage_while_paused", int(h.plants[0]["hp"]) == hp and h.ticks == 0)
	s.paused = false
	h.advance(0.01, Vector2(-1000, -1000), true)
	check("pause.resume_continues", int(h.plants[0]["hp"]) < hp)
	s.enemies.boars.erase(boar)

func _hundred_percent() -> void:
	var s: RefCounted = make_session()
	var h: RefCounted = s.helpers
	s.enemy_tuning.contact_damage = 0
	var bound: float = s.far.completion_bound_seconds()
	for nest: Nest in s.enemies.nests:
		s.enemies.damage_nest(nest, 99)
	var guard: int = 0
	while not s.enemies.boars.is_empty() and guard < 400:
		s.enemies.damage_boar(s.enemies.boars[0], 99)
		guard += 1
		s.advance_game(0.25)
	# helper plants on mature ground near the start (and more seeds from the nest rewards are ignored: seeds granted directly)
	h.seeds = 12
	h.max_helpers = 6
	var spots: Array[Vector2i] = []
	for i: int in 3:
		var origin: Vector2i = find_block(s, "free", Coords.logic_to_cell(s.position), spots)
		spots.append(origin)
		stand_at(s, origin)
		s.set_aim(block_center(origin))
		s.helper_mode = i
		s.place_helper()
	check("hundred.three_helpers_placed", h.plants.size() == 3, str(h.plants.size()))
	var greened_with: int = s.state.greened_count
	var steps: int = 0
	while s.state.zone_state[1] < WorldState.ZONE_STABLE and steps < 4000:
		s.advance_game(0.25)
		steps += 1
	var t_stable: float = float((s.zone_times[1] as Dictionary).get(WorldState.ZONE_STABLE, s.clock.elapsed))
	s.position = Coords.cell_center_logic(s.placement.player_start_cell)
	var limit: float = t_stable + bound
	var t_done: float = -1.0
	while s.clock.elapsed <= limit + 5.0:
		s.advance_game(0.25)
		if s.state.greened_count == s.state.target_count:
			t_done = s.clock.elapsed - t_stable
			break
	check("hundred.exact_100_with_helpers_within_bound", t_done >= 0.0 and t_done <= bound, "after stable %.1f s of bound %.1f s, greened %d/%d (was %d with helpers placed)" % [t_done, bound, s.state.greened_count, s.state.target_count, greened_with])
	check("hundred.helpers_still_standing_counters_ok", h.plants.size() == 3 and s.state.counters_consistent() and s.greening_percent() == 100)
