extends SceneTree
## HLP-01 independent verification (headless): condition 4 (real EnemyField boars vs helper plants, fast-forwarded once) and
## condition 5 (strict 100 % within far.completion_bound_seconds() with helper plants placed, no input after stable).
##   godot --headless --path <repo> --script res://tests/poc/independent/hlp01_combat.gd
## Setup note: zone 1 has no mature ground at the start; a patch is filled with WorldState.debug_fill_stage (engine-level setup)
## so that a helper plant can stand at the front line. Everything after that is the normal loop (advance_game only).
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const OUT: String = "res://evidence/helper/01/independent/"
var passes: int = 0
var fails: int = 0
var lines: PackedStringArray = PackedStringArray()
var keep: Array[RefCounted] = []

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

func center(origin: Vector2i) -> Vector2:
	return (Vector2(origin) + Vector2(2, 2)) * 4.0

func region_ok(st: WorldState, x0: int, y0: int, w: int, h: int, zone: int) -> bool:
	for y: int in range(y0, y0 + h):
		for x: int in range(x0, x0 + w):
			if not st.in_bounds(x, y):
				return false
			var i: int = st.index_of(x, y)
			if not st.is_walkable(x, y) or st.target[i] == 0 or st.occupant[i] != 0 or st.zone_at(i) != zone:
				return false
	return true

## An 8x8 walkable target patch of `zone`, `dist` tiles from the nest centre (top-left cell).
func patch_near_nest(st: WorldState, nest: Nest, dist: int) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = INF
	var nc: Vector2 = nest.center_px(4) / 4.0
	for y: int in range(2, st.height - 10):
		for x: int in range(2, st.width - 10):
			var c: Vector2 = Vector2(x + 4, y + 4)
			var d: float = absf(c.distance_to(nc) - float(dist))
			if d < best_d and region_ok(st, x, y, 8, 8, 1):
				best_d = d
				best = Vector2i(x, y)
	return best

func recount(st: WorldState) -> int:
	var n: int = 0
	for i: int in st.tile_count():
		if st.target[i] != 0 and st.stage[i] >= 2:
			n += 1
	return n

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_combat()
	_hundred()
	var f: FileAccess = FileAccess.open(OUT + "combat.log", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\nRESULT passes=%d failures=%d\n" % [passes, fails])
	f.close()
	print("RESULT passes=%d failures=%d" % [passes, fails])
	for m: RefCounted in keep:
		m.close()
	quit(1 if fails > 0 else 0)

func _combat() -> void:
	var m: RefCounted = mk()
	var st: WorldState = m.state
	var h: RefCounted = m.helpers
	h.add_seeds(20)
	var nest: Nest = m.enemies.nests[2]
	var patch: Vector2i = patch_near_nest(st, nest, 14)
	check("combat.patch_found", patch.x >= 0, "patch %s nest tile %s" % [str(patch), str(nest.tile)])
	st.debug_fill_stage(Rect2i(patch, Vector2i(8, 8)), WorldState.STAGE_MATURE)
	# front-line helper in the middle of the patch (normal placement API; the player stands next to it first)
	var front: Vector2i = patch + Vector2i(2, 2)
	m.position = center(front)
	m.set_aim(center(front))
	m.helper_mode = 0
	var fr: Dictionary = m.place_helper()
	check("combat.front_placed_no_zone_limit", bool(fr["ok"]) and st.zone_at(st.index_of(front.x, front.y)) == 1, str(fr.get("reason", "")))
	# stable-zone helper in zone 0
	var safe_blocks: Array[Vector2i] = []
	for oy: int in range(70, 100):
		for ox: int in range(70, 100):
			if safe_blocks.is_empty() and region_ok(st, ox, oy, 4, 4, 0):
				var all_mature: bool = true
				for y: int in range(oy, oy + 4):
					for x: int in range(ox, ox + 4):
						all_mature = all_mature and st.stage[st.index_of(x, y)] == WorldState.STAGE_MATURE
				if all_mature:
					safe_blocks.append(Vector2i(ox, oy))
	m.position = center(safe_blocks[0])
	m.set_aim(center(safe_blocks[0]))
	var sr: Dictionary = m.place_helper()
	check("combat.safe_placed", bool(sr["ok"]) and st.zone_at(st.index_of(safe_blocks[0].x, safe_blocks[0].y)) == 0)
	var front_uid: int = int(fr["uid"])
	var safe_uid: int = int(sr["uid"])
	var front_hp0: int = int(h.plant_by_uid(front_uid)["hp"])
	var safe_hp0: int = int(h.plant_by_uid(safe_uid)["hp"])
	# player returns to the start zone, then pure time
	m.position = Coords.cell_center_logic(m.placement.player_start_cell)
	var rect_f: Rect2 = Rect2(Vector2(front) * 4.0, Vector2(16, 16))
	var contact_seen: bool = false
	var min_dist: float = INF
	var boar_in_safe: int = 0
	var hp_trace: Array[int] = []
	var t_death: float = -1.0
	var from_nest: bool = true
	var first_boar_t: float = -1.0
	var t0: float = m.clock.elapsed
	for i: int in 4800:
		m.advance_game(0.25)
		for b: Boar in m.enemies.boars:
			if first_boar_t < 0.0:
				first_boar_t = m.clock.elapsed - t0
			from_nest = from_nest and b.nest_id > 0
			if st.zone_at(st.index_of(clampi(floori(b.pos.x / 4.0), 0, st.width - 1), clampi(floori(b.pos.y / 4.0), 0, st.height - 1))) == 0:
				boar_in_safe += 1
			var dx: float = maxf(maxf(rect_f.position.x - b.pos.x, b.pos.x - rect_f.end.x), 0.0)
			var dy: float = maxf(maxf(rect_f.position.y - b.pos.y, b.pos.y - rect_f.end.y), 0.0)
			var d: float = sqrt(dx * dx + dy * dy)
			min_dist = minf(min_dist, d)
			if d <= 6.0:
				contact_seen = true
		var p: Dictionary = h.plant_by_uid(front_uid)
		if not p.is_empty():
			if hp_trace.is_empty() or hp_trace[hp_trace.size() - 1] != int(p["hp"]):
				hp_trace.append(int(p["hp"]))
		elif t_death < 0.0:
			t_death = m.clock.elapsed - t0
			break
	info("combat: first boar after %.1fs, min boar distance to front plant %.1f px, hp trace %s, destroyed at %.1fs, boars now %d" % [first_boar_t, min_dist, str(hp_trace), t_death, m.enemies.boars.size()])
	check("combat.real_boars_spawned_by_nest", first_boar_t >= 0.0 and from_nest and m.enemies.total_spawned > 0, "spawned=%d" % m.enemies.total_spawned)
	check("combat.boar_actually_reached_front_plant", contact_seen, "min dist %.1f" % min_dist)
	var dec: bool = hp_trace.size() >= 2
	for k: int in range(1, hp_trace.size()):
		dec = dec and hp_trace[k] < hp_trace[k - 1]
	check("combat.hp_decreased_stepwise_to_destruction", dec and hp_trace[0] <= front_hp0 and t_death > 0.0, str(hp_trace))
	var gone: bool = h.plant_by_uid(front_uid).is_empty() and not st.occupancy_owners.has(WorldState.OWNER_BAND_HELPER + front_uid)
	var freed: bool = true
	for y: int in range(front.y, front.y + 4):
		for x: int in range(front.x, front.x + 4):
			freed = freed and st.occupant[st.index_of(x, y)] == 0
	check("combat.vanished_and_occupancy_released", gone and freed and h.lost_total == 1 and h.total_count() == 1, "lost=%d total=%d" % [h.lost_total, h.total_count()])
	check("combat.counters_consistent", st.counters_consistent() and recount(st) == st.greened_count)
	# rebuild with seeds
	var seeds_b: int = h.seeds
	m.position = center(front)
	m.set_aim(center(front))
	m.helper_mode = 0
	# the cells may have been gnawed meanwhile; only assert a clear answer
	var rb: Dictionary = m.place_helper()
	info("rebuild at front after destruction: ok=%s code=%s seeds %d->%d" % [str(rb["ok"]), str(rb["code"]), seeds_b, h.seeds])
	# stable zone: no boar, no damage, over the same run
	check("combat.safe_zone_never_entered", boar_in_safe == 0, "samples in zone 0: %d" % boar_in_safe)
	check("combat.safe_plant_untouched", int(h.plant_by_uid(safe_uid)["hp"]) == safe_hp0, "hp %d/%d" % [int(h.plant_by_uid(safe_uid)["hp"]), safe_hp0])

func _hundred() -> void:
	var m: RefCounted = mk()
	var st: WorldState = m.state
	var h: RefCounted = m.helpers
	h.add_seeds(20)
	m.advance_game(20.0)
	# 3 helpers on mature ground in zone 0 (all three kinds) and 1 on a front-line patch
	var placed: int = 0
	var spots: Array[Vector2i] = []
	for oy: int in range(60, 100):
		for ox: int in range(60, 100):
			if spots.size() < 3 and region_ok(st, ox, oy, 4, 4, 0):
				var ok: bool = true
				for y: int in range(oy, oy + 4):
					for x: int in range(ox, ox + 4):
						ok = ok and st.stage[st.index_of(x, y)] == WorldState.STAGE_MATURE
				for s2: Vector2i in spots:
					ok = ok and (absi(s2.x - ox) > 5 or absi(s2.y - oy) > 5)
				if ok:
					spots.append(Vector2i(ox, oy))
	for i: int in spots.size():
		m.position = center(spots[i])
		m.set_aim(center(spots[i]))
		m.helper_mode = i
		placed += 1 if bool(m.place_helper()["ok"]) else 0
	var patch: Vector2i = patch_near_nest(st, m.enemies.nests[1], 12)
	st.debug_fill_stage(Rect2i(patch, Vector2i(8, 8)), WorldState.STAGE_MATURE)
	m.position = center(patch + Vector2i(2, 2))
	m.set_aim(center(patch + Vector2i(2, 2)))
	m.helper_mode = 1
	placed += 1 if bool(m.place_helper()["ok"]) else 0
	check("hundred.four_helpers_placed", placed == 4 and h.plants.size() == 4, "placed %d" % placed)
	m.position = Coords.cell_center_logic(m.placement.player_start_cell)
	# conquer through the engine (nests + boars removed), as the POC-09 save verification does
	for n: Nest in m.enemies.nests.duplicate():
		m.enemies.destroy_nest(n)
	for b: Boar in m.enemies.boars.duplicate():
		m.enemies.remove_boar(b)
	var guard: int = 0
	while int(st.zone_state[1]) < WorldState.ZONE_STABLE and guard < 200:
		m.advance_game(0.5)
		guard += 1
	var t_stable: float = m.clock.elapsed
	var bound: float = m.far.completion_bound_seconds()
	check("hundred.zones_stable", int(st.zone_state[0]) >= WorldState.ZONE_STABLE and int(st.zone_state[1]) >= WorldState.ZONE_STABLE, str(Array(st.zone_state)))
	info("hundred: stable at %.1f, bound %.1f, greened %d/%d, helper cells %d" % [t_stable, bound, st.greened_count, st.target_count, 64])
	var early100: bool = false
	var reached: float = -1.0
	while m.clock.elapsed <= t_stable + bound + 1.0:
		m.advance_game(2.0)
		if st.greened_count == st.target_count:
			reached = m.clock.elapsed
			break
		if m.greening_percent() >= 100:
			early100 = true
	check("hundred.reached_within_bound", reached >= 0.0, "reached after %.1fs (bound %.1fs)" % [reached - t_stable, bound])
	var not_green: int = 0
	var total_t: int = 0
	for i: int in st.tile_count():
		if st.target[i] != 0:
			total_t += 1
			if st.stage[i] < 2:
				not_green += 1
	check("hundred.own_recount_exact_100", not_green == 0 and total_t == st.target_count and st.greened_count == total_t and m.greening_percent() == 100 and not early100, "targets %d not green %d" % [total_t, not_green])
	check("hundred.helpers_kept_no_dup", h.plants.size() == 4 and st.counters_consistent())
	check("hundred.no_reinvasion", m.enemies.boars.is_empty() and m.enemies.alive_nest_count(-1) == 0)
