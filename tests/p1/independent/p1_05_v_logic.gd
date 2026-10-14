extends SceneTree
## Independent verifier for P1-05, logic level (headless, no scene). Expectations come from the spec (AUTO-001, P1-05 ticket,
## parent decisions) and from my own brute force, not from the implementation's formulas.
## Run: Godot --headless --path <project> --script res://tests/p1/independent/p1_05_v_logic.gd -- --only=<section>
## Sections: place, cost, occupy, carrot, kiwi, hp, rate, save, empty

const OUT: String = "res://evidence/p1/p1-05/independent/"
const TILE: int = 4
const W_WASTE: int = 0
const W_WATER: int = 3
const W_BUILD: int = 4
const THRESHOLD: int = 100000

var results: Array[Dictionary] = []
var observations: Dictionary = {}
var tun: SimTuning
var ptun_src: PlayTuning
var region_def: RegionDef

class Rig:
	var world: WorldState
	var clock: SimClock = SimClock.new()
	var growth: GrowthSim
	var spread: SpreadSim
	var play: PlayState
	var player_pos: Vector2 = Vector2(4000, 4000)
	var t: float = 0.0
	func _init(w: WorldState, st: SimTuning, pt: PlayTuning, defs: Array[PlantDef], sources: Array[Vector2], sync: bool = true) -> void:
		world = w
		clock.configure(st)
		growth = GrowthSim.new(w, st)
		spread = SpreadSim.new(w, st, sync)
		clock.growth_ticked.connect(func(_i: int) -> void: growth.tick())
		clock.spread_ticked.connect(func(_i: int) -> void: spread.tick())
		play = PlayState.new(w, pt, st, 4, sources, defs)
		play.cultivation.boost_sink = spread.set_speed_scale
	func step(dt: float) -> void:
		clock.advance(dt)
		play.advance(dt, player_pos)
		t += dt
	func run(seconds: float, dt: float = 0.25) -> void:
		var n: int = roundi(seconds / dt)
		for i: int in n:
			step(dt)

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func run() -> void:
	tun = load("res://data/sim_tuning.tres") as SimTuning
	ptun_src = load("res://data/play_tuning.tres") as PlayTuning
	region_def = load("res://data/region_01.tres") as RegionDef
	var only: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	var tests: Dictionary = {
		"place": t_place, "cost": t_cost, "occupy": t_occupy, "carrot": t_carrot, "kiwi": t_kiwi,
		"hp": t_hp, "rate": t_rate, "save": t_save, "save2": t_save2, "empty": t_empty,
	}
	for key: String in tests:
		if only != "" and only != key:
			continue
		print("--- section ", key)
		var t0: int = Time.get_ticks_msec()
		(tests[key] as Callable).call()
		print("--- section %s done in %d ms" % [key, Time.get_ticks_msec() - t0])
	var f: FileAccess = FileAccess.open(OUT + "checks_logic%s.json" % ("" if only == "" else "_" + only), FileAccess.WRITE)
	f.store_string(JSON.stringify({"results": results, "observations": observations}, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("V_RESULT total=%d fails=%d" % [results.size(), fails])
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------------------------------ helpers

func fresh_defs() -> Array[PlantDef]:
	var list: Array[PlantDef] = []
	for d: PlantDef in region_def.plants:
		list.append(d.duplicate() as PlantDef)
	return list

func make_world(w: int, h: int, terrain_prep: Callable = Callable(), stage_prep: Callable = Callable()) -> WorldState:
	var s: WorldState = WorldState.new(w, h, region_def.terrains, 12345)
	s.terrain.fill(W_WASTE)
	if terrain_prep.is_valid():
		terrain_prep.call(s)
	s.apply_terrain_defs()
	if stage_prep.is_valid():
		stage_prep.call(s)
	return s

func new_rig(s: WorldState, defs: Array[PlantDef] = [], sources: Array[Vector2] = [], sync: bool = true) -> Rig:
	var d: Array[PlantDef] = defs if not defs.is_empty() else fresh_defs()
	var pt: PlayTuning = ptun_src.duplicate() as PlayTuning
	var r: Rig = Rig.new(s, tun, pt, d, sources, sync)
	r.play.seeds = 20
	return r

func land(r: Rig, key: StringName, px: Vector2) -> CultivatedPlant:
	var def: PlantDef = r.play.def_by_key(key)
	r.play.reserve_plant(def)
	return r.play.land_plant(key, px)

func occ_sum(s: WorldState) -> int:
	var n: int = 0
	for v: int in s.occupant:
		if v != 0:
			n += 1
	return n

func world_hash(s: WorldState) -> String:
	return "%d/%d/%d/%d" % [hash(s.stage), hash(s.growth), hash(s.moisture), hash(s.natural)]

func block_center_px(o: Vector2i) -> Vector2:
	return Vector2(o.x + 1, o.y + 1) * TILE

# ------------------------------------------------------------------------------------------ placement

func t_place() -> void:
	# 1. positive placement on a mature field, plus counters
	var s: WorldState = make_world(40, 40, Callable(), func(w: WorldState) -> void: w.debug_fill_stage(Rect2i(15, 15, 10, 10), 4))
	var r: Rig = new_rig(s)
	var g0: int = s.greened_count
	var m0: int = s.mature_count
	var tc0: int = s.target_count
	var p: CultivatedPlant = land(r, &"carrot", Vector2(80, 80))
	rec("place.positive", "a carrot lands on a fully mature, free 2x2 and is planted there (origin (19,19) for a landing exactly on its centre)", p != null and p.tile == Vector2i(19, 19), "tile=%s" % [str(p.tile) if p != null else "null"])
	if p != null:
		var occ_ok: bool = true
		for y: int in range(19, 21):
			for x: int in range(19, 21):
				occ_ok = occ_ok and s.occupant[s.index_of(x, y)] != 0 and s.stage[s.index_of(x, y)] == 4
		rec("place.occupancy", "exactly the 4 footprint tiles are occupied and stay mature; nothing else is occupied", occ_ok and occ_sum(s) == 4, "occupied=%d" % occ_sum(s))
	rec("place.counters_unchanged", "planting does not change greened / mature / target counts, which match a recount", s.greened_count == g0 and s.mature_count == m0 and s.target_count == tc0 and s.counters_consistent(), "greened %d->%d mature %d->%d" % [g0, s.greened_count, m0, s.mature_count])
	# 2. nearest block first (my own geometry), 60 random landings with a unique nearest block
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 424242
	var checked: int = 0
	var bad: int = 0
	var first_bad: String = ""
	var guard: int = 0
	while checked < 60 and guard < 1000:
		guard += 1
		var px: Vector2 = Vector2(rng.randf_range(68.0, 92.0), rng.randf_range(68.0, 92.0))
		var tile: Vector2i = Vector2i(floori(px.x / TILE), floori(px.y / TILE))
		var best: Vector2i = Vector2i.ZERO
		var best_d: float = INF
		var second_d: float = INF
		for oy: int in [-1, 0]:
			for ox: int in [-1, 0]:
				var o: Vector2i = tile + Vector2i(ox, oy)
				var d: float = block_center_px(o).distance_to(px)
				if d < best_d:
					second_d = best_d
					best_d = d
					best = o
				elif d < second_d:
					second_d = d
		if second_d - best_d < 0.01:
			continue
		checked += 1
		var s2: WorldState = make_world(40, 40, Callable(), func(w: WorldState) -> void: w.debug_fill_stage(Rect2i(15, 15, 10, 10), 4))
		var r2: Rig = new_rig(s2)
		var q: CultivatedPlant = land(r2, &"kiwi", px)
		if q == null or q.tile != best:
			bad += 1
			if first_bad == "":
				first_bad = "px=%s expected=%s got=%s" % [str(px), str(best), str(q.tile) if q != null else "null"]
	rec("place.nearest_first", "with all four 2x2 blocks valid, the block whose centre is nearest to the landing point is chosen (60 random points)", checked == 60 and bad == 0, "checked=%d bad=%d %s" % [checked, bad, first_bad])
	# 3. exact tie is deterministic across fresh runs
	var tie_results: Array[String] = []
	for i: int in 4:
		var s3: WorldState = make_world(40, 40, Callable(), func(w: WorldState) -> void: w.debug_fill_stage(Rect2i(15, 15, 10, 10), 4))
		var r3: Rig = new_rig(s3)
		var q3: CultivatedPlant = land(r3, &"carrot", Vector2(82, 82))
		tie_results.append(str(q3.tile) if q3 != null else "null")
	rec("place.tie_deterministic", "a landing on a tile centre (four equally near blocks) picks the same block on every fresh run", tie_results[0] != "null" and tie_results.count(tie_results[0]) == 4, "results=%s" % str(tie_results))
	# 4. broken tiles: for each of the 4 tiles of an isolated mature 2x2 and each bad state, no landing may plant
	var states: Array[String] = ["empty", "seed", "sprout1", "sprout2", "water", "building", "occupied"]
	var attempts: int = 0
	var wrongly: int = 0
	var detail: String = ""
	for st: String in states:
		for k: int in 4:
			var broken: Vector2i = Vector2i(8 + (k & 1), 8 + (k >> 1))
			var tprep: Callable = func(w: WorldState) -> void:
				if st == "water":
					w.terrain[w.index_of(broken.x, broken.y)] = W_WATER
				elif st == "building":
					w.terrain[w.index_of(broken.x, broken.y)] = W_BUILD
			var sprep: Callable = func(w: WorldState) -> void:
				w.debug_fill_stage(Rect2i(8, 8, 2, 2), 4)
				var idx: int = w.index_of(broken.x, broken.y)
				match st:
					"empty":
						w.set_stage(idx, 0)
					"seed":
						w.set_stage(idx, 1)
					"sprout1":
						w.set_stage(idx, 2)
					"sprout2":
						w.set_stage(idx, 3)
					"occupied":
						w.occupy(Rect2i(broken.x, broken.y, 1, 1), 99)
			var points: Array[Vector2] = [Vector2(34, 34), Vector2(38, 34), Vector2(34, 38), Vector2(38, 38), Vector2(36, 36)]
			for pt: Vector2 in points:
				var sb: WorldState = make_world(20, 20, tprep, sprep)
				var rb: Rig = new_rig(sb)
				var occ_before: int = occ_sum(sb)
				var seeds_before: int = rb.play.seeds
				var got: CultivatedPlant = land(rb, &"carrot" if (k & 1) == 0 else &"kiwi", pt)
				attempts += 1
				if got != null or rb.play.seeds != seeds_before or rb.play.reserved_seeds != 0 or occ_sum(sb) != occ_before or rb.play.cultivation.plants.size() != 0 or rb.play.plant_failures != 1:
					wrongly += 1
					if detail == "":
						detail = "state=%s broken=%s pt=%s got=%s seeds=%d" % [st, str(broken), str(pt), str(got.tile) if got != null else "null", rb.play.seeds]
	rec("place.any_bad_tile_refuses", "an isolated mature 2x2 with ANY one tile empty / seed / sprout1 / sprout2 / water / building / occupied refuses planting (no plant, no seeds spent, nothing reserved, occupancy unchanged)", attempts == 7 * 4 * 5 and wrongly == 0, "attempts=%d wrongly=%d %s" % [attempts, wrongly, detail])
	# positive control of the same isolated world
	var sc: WorldState = make_world(20, 20, Callable(), func(w: WorldState) -> void: w.debug_fill_stage(Rect2i(8, 8, 2, 2), 4))
	var rc: Rig = new_rig(sc)
	var pc: CultivatedPlant = land(rc, &"kiwi", Vector2(36, 36))
	rec("place.isolated_control", "the isolated mature 2x2 with no defect does take a plant (the refusals above are caused by the defect)", pc != null and pc.tile == Vector2i(8, 8), "tile=%s" % [str(pc.tile) if pc != null else "null"])
	# 5. a defect in the middle of a big field: result is a valid fully mature block containing the landing tile, nearest-first when possible
	var fbad: int = 0
	var fchecked: int = 0
	var fdetail: String = ""
	var cases: Array[Vector2i] = [Vector2i(20, 20), Vector2i(19, 19), Vector2i(21, 20), Vector2i(20, 21), Vector2i(19, 21), Vector2i(21, 19), Vector2i(21, 21), Vector2i(19, 20), Vector2i(20, 19)]
	for ci: int in cases.size():
		for kind: int in 3:
			var broken: Vector2i = cases[ci]
			var sf: WorldState = make_world(40, 40, Callable(), func(w: WorldState) -> void:
				w.debug_fill_stage(Rect2i(15, 15, 10, 10), 4)
				w.set_stage(w.index_of(broken.x, broken.y), [0, 1, 2][kind]))
			var rf: Rig = new_rig(sf)
			var px: Vector2 = Vector2(82, 82)
			var tile: Vector2i = Vector2i(20, 20)
			var valid: Array[Vector2i] = []
			for oy: int in [-1, 0]:
				for ox: int in [-1, 0]:
					var o: Vector2i = tile + Vector2i(ox, oy)
					var ok: bool = true
					for dy: int in 2:
						for dx: int in 2:
							var tt: Vector2i = o + Vector2i(dx, dy)
							if tt == broken:
								ok = false
					if ok:
						valid.append(o)
			var got2: CultivatedPlant = land(rf, &"carrot", px)
			fchecked += 1
			if valid.is_empty():
				if got2 != null:
					fbad += 1
					fdetail = "expected none, got %s (broken %s)" % [str(got2.tile), str(broken)]
			else:
				if got2 == null or not (got2.tile in valid):
					fbad += 1
					fdetail = "broken %s: got %s valid %s" % [str(broken), str(got2.tile) if got2 != null else "null", str(valid)]
	rec("place.fallback_blocks", "when some of the 4 blocks around the landing tile contain a defect, a valid one is planted; none when all 4 do", fbad == 0, "cases=%d bad=%d %s" % [fchecked, fbad, fdetail])
	# 6. fallback is deterministic: same setup several times gives the same fallback block
	var fb: Array[String] = []
	for i: int in 4:
		var sf2: WorldState = make_world(40, 40, Callable(), func(w: WorldState) -> void:
			w.debug_fill_stage(Rect2i(15, 15, 10, 10), 4)
			w.set_stage(w.index_of(19, 19), 0))
		var rf2: Rig = new_rig(sf2)
		var got3: CultivatedPlant = land(rf2, &"carrot", Vector2(82, 82))
		fb.append(str(got3.tile) if got3 != null else "null")
	rec("place.fallback_deterministic", "the fallback choice is identical on repeated identical runs", fb[0] != "null" and fb.count(fb[0]) == 4, "results=%s" % str(fb))
	# 7. non-target tiles / world edge
	var se: WorldState = make_world(20, 20, Callable(), func(w: WorldState) -> void: w.debug_fill_stage(Rect2i(0, 0, 4, 4), 4))
	var re: Rig = new_rig(se)
	var pe: CultivatedPlant = land(re, &"carrot", Vector2(1, 1))
	rec("place.world_edge", "a landing at the world corner plants on the in-bounds block only (origin (0,0))", pe != null and pe.tile == Vector2i(0, 0), "tile=%s" % [str(pe.tile) if pe != null else "null"])
	var pe2: CultivatedPlant = land(re, &"carrot", Vector2(-20, -20))
	rec("place.outside_map", "a landing outside the map plants nothing and does not crash", pe2 == null, "result=%s" % [str(pe2)])

# ------------------------------------------------------------------------------------------ cost and limits

func t_cost() -> void:
	var s: WorldState = make_world(40, 40, Callable(), func(w: WorldState) -> void: w.debug_fill_stage(Rect2i(5, 5, 30, 30), 4))
	var defs: Array[PlantDef] = fresh_defs()
	var carrot: PlantDef = defs[1]
	var kiwi: PlantDef = defs[2]
	rec("cost.defs", "data: the carrot and kiwi cost an ordinary-seed amount > 0 (tuning value), footprint 2", carrot.seed_cost > 0 and kiwi.seed_cost > 0 and carrot.footprint_tiles == 2 and kiwi.footprint_tiles == 2, "carrot cost=%d kiwi cost=%d" % [carrot.seed_cost, kiwi.seed_cost])
	var cost: int = carrot.seed_cost
	var r: Rig = new_rig(s, defs)
	r.play.select_index(1)
	rec("cost.can_fire_start", "with 20 seeds the carrot may be fired", r.play.can_fire_plant(carrot), "available=%d" % r.play.available_seeds())
	r.play.reserve_plant(carrot)
	rec("cost.held_back_in_flight", "after firing, the cost is held back (available -cost) but seeds are not yet spent", r.play.available_seeds() == 20 - cost and r.play.seeds == 20, "seeds=%d available=%d reserved=%d" % [r.play.seeds, r.play.available_seeds(), r.play.reserved_seeds])
	var placed: CultivatedPlant = r.play.land_plant(&"carrot", Vector2(80, 80))
	rec("cost.spent_on_success", "the cost is spent exactly once when the plant is placed, nothing stays reserved", placed != null and r.play.seeds == 20 - cost and r.play.reserved_seeds == 0 and r.play.inflight.get(&"carrot", 0) == 0, "seeds=%d reserved=%d" % [r.play.seeds, r.play.reserved_seeds])
	# failure returns
	r.play.reserve_plant(carrot)
	var failed: CultivatedPlant = r.play.land_plant(&"carrot", Vector2(8, 8))
	rec("cost.returned_on_failure", "a landing on bad ground spends nothing and releases the held-back cost", failed == null and r.play.seeds == 20 - cost and r.play.available_seeds() == 20 - cost and r.play.reserved_seeds == 0, "seeds=%d available=%d" % [r.play.seeds, r.play.available_seeds()])
	# expiry / enemy hit -> cancel
	r.play.reserve_plant(kiwi)
	r.play.cancel_plant(&"kiwi")
	rec("cost.returned_on_cancel", "a shot that vanishes in the air gives the held-back cost back", r.play.seeds == 20 - cost and r.play.available_seeds() == 20 - cost and r.play.reserved_seeds == 0, "seeds=%d available=%d" % [r.play.seeds, r.play.available_seeds()])
	r.play.cancel_plant(&"kiwi")
	r.play.cancel_plant(&"carrot")
	rec("cost.cancel_idempotent", "cancelling with nothing in flight does not refund extra or go negative", r.play.reserved_seeds == 0 and r.play.available_seeds() == 20 - cost and r.play.seeds == 20 - cost, "reserved=%d available=%d" % [r.play.reserved_seeds, r.play.available_seeds()])
	# not enough seeds
	r.play.seeds = cost - 1
	rec("cost.not_enough_cannot_fire", "with fewer seeds than the cost the plant cannot be fired", not r.play.can_fire_plant(carrot) and not r.play.can_fire_plant(kiwi), "seeds=%d cost=%d" % [r.play.seeds, cost])
	r.play.seeds = 2 * cost - 1
	r.play.reserve_plant(carrot)
	rec("cost.second_shot_needs_seeds", "two shots in flight need two costs: with 2*cost-1 seeds the second cannot be fired", not r.play.can_fire_plant(carrot), "available=%d" % r.play.available_seeds())
	r.play.cancel_plant(&"carrot")
	# per kind limit (in-flight shots count)
	var defs2: Array[PlantDef] = fresh_defs()
	defs2[1].max_count = 2
	var s2: WorldState = make_world(60, 60, Callable(), func(w: WorldState) -> void: w.debug_fill_stage(Rect2i(5, 5, 50, 50), 4))
	var r2: Rig = new_rig(s2, defs2)
	r2.play.seeds = 40
	var flags: Array[bool] = []
	flags.append(r2.play.can_fire_plant(defs2[1]))
	r2.play.reserve_plant(defs2[1])
	flags.append(r2.play.can_fire_plant(defs2[1]))
	r2.play.reserve_plant(defs2[1])
	flags.append(r2.play.can_fire_plant(defs2[1]))
	rec("cost.limit_counts_inflight", "with max_count=2: fire 1 ok, fire 2 ok, fire 3 refused while 2 are in flight (nothing planted yet)", flags == [true, true, false], "flags=%s" % str(flags))
	rec("cost.limit_per_kind", "the carrot limit does not block the kiwi", r2.play.can_fire_plant(defs2[2]), "kiwi ok=%s" % r2.play.can_fire_plant(defs2[2]))
	var a1: CultivatedPlant = r2.play.land_plant(&"carrot", Vector2(100, 100))
	var a2: CultivatedPlant = r2.play.land_plant(&"carrot", Vector2(140, 100))
	rec("cost.limit_after_landing", "after both land, count 2 reaches the limit: still refused; planted count never exceeds 2", a1 != null and a2 != null and not r2.play.can_fire_plant(defs2[1]) and r2.play.cultivation.count(&"carrot") == 2, "count=%d" % r2.play.cultivation.count(&"carrot"))
	r2.play.reserve_plant(defs2[1])
	var a3: CultivatedPlant = r2.play.land_plant(&"carrot", Vector2(180, 100))
	rec("cost.limit_hard", "even if a third shot was fired, landing cannot exceed the kind limit, and it costs nothing", a3 == null and r2.play.cultivation.count(&"carrot") == 2 and r2.play.seeds == 40 - 2 * carrot.seed_cost, "count=%d seeds=%d" % [r2.play.cultivation.count(&"carrot"), r2.play.seeds])
	# the plain seed is untouched by cultivated reservation
	r2.play.seeds = 5
	r2.play.reserve_plant(defs2[2])
	rec("cost.plain_seed_uses_available", "can_fire_seed (ordinary seeds) respects held-back seeds too: 5 seeds, kiwi in flight costs 3 -> 2 available", r2.play.can_fire_seed() and r2.play.available_seeds() == 5 - kiwi.seed_cost, "available=%d" % r2.play.available_seeds())
	# selection cycle (state level)
	var s3: WorldState = make_world(10, 10)
	var r3: Rig = new_rig(s3)
	var seq: Array[int] = []
	for i: int in 4:
		seq.append(r3.play.cycle_selection(1))
	for i: int in 4:
		seq.append(r3.play.cycle_selection(-1))
	rec("cost.select_cycle", "forward: 1,2,0,1; backward from 1: 0,2,1,0 (3 kinds, wrapping)", seq == [1, 2, 0, 1, 0, 2, 1, 0], "seq=%s" % str(seq))
	rec("cost.select_defs", "the three kinds are normal (footprint 1), carrot, kiwi (footprint 2) in that order", r3.play.selectable.size() == 3 and r3.play.selectable[0].footprint_tiles == 1 and r3.play.selectable[1].key == &"carrot" and r3.play.selectable[2].key == &"kiwi", "keys=%s" % str(r3.play.selectable.map(func(d: PlantDef) -> String: return String(d.key))))

# ------------------------------------------------------------------------------------------ occupancy and greening

func t_occupy() -> void:
	var s: WorldState = make_world(60, 60, Callable(), func(w: WorldState) -> void: w.debug_fill_stage(Rect2i(28, 28, 2, 2), 4))
	var r: Rig = new_rig(s)
	var p: CultivatedPlant = land(r, &"carrot", Vector2(116, 116))
	var foot: Array[int] = []
	for y: int in range(28, 30):
		for x: int in range(28, 30):
			foot.append(s.index_of(x, y))
	# an empty tile occupied by something else, next to the plant
	var stray: int = s.index_of(31, 28)
	s.occupy(Rect2i(31, 28, 1, 1), 55)
	var hist: Dictionary = {"stage_changed": false, "occupant_changed": false}
	var g_before: int = s.greened_count
	var scattered: int = 0
	var recount_ok: bool = true
	for round: int in 40:
		var tiles: PackedInt32Array = r.play.land_seed(Vector2(116 + (round % 5), 116 - (round % 3)))
		scattered += tiles.size()
		for i: int in tiles:
			if i in foot or i == stray:
				hist["stage_changed"] = true
		r.run(2.0)
		for i: int in foot:
			if s.stage[i] != 4 or s.occupant[i] == 0:
				hist["occupant_changed"] = true
		if s.stage[stray] != 0 or s.occupant[stray] != 55:
			hist["stage_changed"] = true
		recount_ok = recount_ok and s.greened_count == s.recount_greened() and s.counters_consistent()
	rec("occupy.no_seed_in_footprint_or_occupied", "80 s of manual seed scattering at the plant and natural spread never plant into the footprint nor into another occupied empty tile", not bool(hist["stage_changed"]) and not bool(hist["occupant_changed"]), "scattered=%d hist=%s" % [scattered, str(hist)])
	rec("occupy.greened_matches_recount", "greened_count matches a full recount after every 2 s while seeds / sprouts / spread run beside the plant; the footprint (mature) is counted as greened", recount_ok and s.greened_count > g_before, "greened %d -> %d recount=%d" % [g_before, s.greened_count, s.recount_greened()])
	var footprint_counted: bool = true
	for i: int in foot:
		footprint_counted = footprint_counted and s.stage[i] >= WorldState.GREENED_MIN_STAGE and s.target[i] == 1
	rec("occupy.footprint_greened", "all 4 occupied tiles are target tiles at a greened stage", footprint_counted, "p=%s" % str(p.tile if p != null else null))
	# the pre-plant greened count equals post-plant count (exact)
	var s2: WorldState = make_world(40, 40, Callable(), func(w: WorldState) -> void: w.debug_fill_stage(Rect2i(10, 10, 8, 8), 4))
	var r2: Rig = new_rig(s2)
	var before: int = s2.greened_count
	for i: int in 5:
		land(r2, &"kiwi", Vector2(48 + 8 * i, 48))
	rec("occupy.count_exact", "after planting several plants the greening count is exactly what it was before (and equals a recount)", s2.greened_count == before and s2.recount_greened() == before and r2.play.cultivation.plants.size() >= 3, "before=%d after=%d plants=%d" % [before, s2.greened_count, r2.play.cultivation.plants.size()])
	# second plant cannot overlap the first
	var r3: Rig = new_rig(make_world(40, 40, Callable(), func(w: WorldState) -> void: w.debug_fill_stage(Rect2i(10, 10, 4, 2), 4)))
	var q1: CultivatedPlant = land(r3, &"carrot", Vector2(44, 44))
	var q2: CultivatedPlant = land(r3, &"carrot", Vector2(44, 44))
	rec("occupy.no_overlap", "a second plant aimed at the same spot does not overlap the first (placed beside it or refused)", q1 != null and (q2 == null or not Rect2i(q1.tile, Vector2i(2, 2)).intersects(Rect2i(q2.tile, Vector2i(2, 2)))), "q1=%s q2=%s" % [str(q1.tile), str(q2.tile) if q2 != null else "null"])

# ------------------------------------------------------------------------------------------ carrot

func carrot_scenario(mode: String) -> Dictionary:
	var W: int = 140
	var H: int = 40
	var s: WorldState = make_world(W, H, Callable(), func(w: WorldState) -> void:
		w.debug_fill_stage(Rect2i(10, 20, 2, 2), 4)
		w.debug_fill_stage(Rect2i(80, 20, 2, 2), 4)
		w.debug_fill_stage(Rect2i(82, 20, 40, 1), 4)
		w.debug_fill_stage(Rect2i(92, 22, 2, 2), 4))
	var r: Rig = new_rig(s)
	var gate: Array[bool] = [false]
	r.spread.allow_hook = func(_i: int) -> bool: return gate[0]
	var carriers: Array[Vector2] = []
	var a: CultivatedPlant = land(r, &"carrot", Vector2(324, 84))
	if a == null or a.tile != Vector2i(80, 20):
		return {"error": "carrot A not placed at (80,20)"}
	carriers.append(a.center_tiles())
	if mode == "overlap":
		var b: CultivatedPlant = land(r, &"carrot", Vector2(372, 92))
		if b == null or b.tile != Vector2i(92, 22):
			return {"error": "carrot B not placed"}
		carriers.append(b.center_tiles())
	var lift_time: float = 8.0 if mode == "young" else 40.0
	r.run(lift_time)
	var matured: bool = a.mature
	if mode == "young" and matured:
		return {"error": "young carrot already mature at 8 s"}
	if mode != "young" and not matured:
		return {"error": "carrot not mature at 40 s"}
	var lift_ticks: int = r.spread.ticks
	# my predictions (brute force): candidates = empty plantable target tiles with >=1 mature tile within dist<=2 (Euclid)
	var predicted: Dictionary = {}
	var info: Dictionary = {"m2": 0, "m1": 0}
	for y: int in H:
		for x: int in W:
			var idx: int = s.index_of(x, y)
			if s.stage[idx] != 0 or s.target[idx] == 0 or s.occupant[idx] != 0:
				continue
			var near: int = 0
			for dy: int in range(-2, 3):
				for dx: int in range(-2, 3):
					if (dx != 0 or dy != 0) and dx * dx + dy * dy <= 4:
						var ox: int = x + dx
						var oy: int = y + dy
						if ox >= 0 and oy >= 0 and ox < W and oy < H and s.stage[s.index_of(ox, oy)] == 4:
							near += 1
			if near == 0:
				continue
			var mult: int = 1
			if mode != "young":
				for c: Vector2 in carriers:
					var dxx: float = x + 0.5 - c.x
					var dyy: float = y + 0.5 - c.y
					if dxx * dxx + dyy * dyy <= 144.0 + 1e-9:
						mult = 2
			if mult == 2:
				info["m2"] += 1
			else:
				info["m1"] += 1
			var gain: int = (10000 + 2500 * (near - 1)) * mult
			predicted[idx] = lift_ticks + (THRESHOLD + gain - 1) / gain
	gate[0] = true
	var observed: Dictionary = {}
	var horizon: int = lift_ticks + 14
	var safety: int = 0
	while r.spread.ticks < horizon and safety < 400:
		safety += 1
		var before_ticks: int = r.spread.ticks
		r.step(0.25)
		if r.spread.ticks != before_ticks:
			for idx: int in s.tile_count():
				if s.stage[idx] == 1 and s.natural[idx] == 1 and not observed.has(idx):
					observed[idx] = r.spread.ticks
	var mismatch: int = 0
	var first: String = ""
	for idx: int in predicted:
		var exp_tick: int = predicted[idx]
		var got: int = int(observed.get(idx, -1))
		if got != exp_tick:
			mismatch += 1
			if first == "":
				first = "tile (%d,%d) expected %d got %d" % [idx % W, idx / W, exp_tick, got]
	var extra: int = 0
	for idx: int in observed:
		if not predicted.has(idx):
			extra += 1
	var out: Dictionary = {"predicted": predicted.size(), "observed": observed.size(), "mismatch": mismatch, "extra": extra, "first": first, "m2": info["m2"], "m1": info["m1"], "lift_ticks": lift_ticks}
	var ctrl: int = int(observed.get(s.index_of(9, 20), -1))
	var car: int = int(observed.get(s.index_of(79, 20), -1))
	out["control_tick"] = ctrl - lift_ticks
	out["carrot_tick"] = car - lift_ticks
	return out

func t_carrot() -> void:
	for mode: String in ["mature", "young", "overlap"]:
		var o: Dictionary = carrot_scenario(mode)
		observations["carrot_" + mode] = o
		if o.has("error"):
			rec("carrot.%s" % mode, "scenario runs", false, str(o))
			continue
		var cond: String = {
			"mature": "every spread candidate is seeded at exactly the tick I derive: ceil(100000 / (rate * m)) after the lift, m=2 only within 12 tiles (footprint centre to tile centre) of the mature carrot, m=1 elsewhere (including the far control block)",
			"young": "with the carrot still young (8 s old) every candidate, even next to it, follows the unboosted ticks (m=1 everywhere)",
			"overlap": "two mature carrots with overlapping radii: tiles covered by both use m=2 (the larger), not 4",
		}[mode]
		rec("carrot.%s" % mode, cond, int(o["mismatch"]) == 0 and int(o["extra"]) == 0 and int(o["predicted"]) > 20 and int(o["observed"]) == int(o["predicted"]), str(o))
	var m: Dictionary = observations["carrot_mature"]
	rec("carrot.speed_ratio", "same geometry, next to a mature carrot a candidate is seeded 7 -> 4 ticks (about 2x faster) than beside the control block", int(m.get("control_tick", -1)) == 7 and int(m.get("carrot_tick", -1)) == 4, "control=%s carrot=%s" % [str(m.get("control_tick")), str(m.get("carrot_tick"))])
	rec("carrot.coverage", "the mature scenario contains both boosted (in range) and unboosted (out of range) candidates", int(m.get("m2", 0)) >= 10 and int(m.get("m1", 0)) >= 10, "m2=%s m1=%s" % [str(m.get("m2")), str(m.get("m1"))])
	var y: Dictionary = observations["carrot_young"]
	rec("carrot.young_no_effect_ticks", "young scenario: the tile beside the carrot needs 7 ticks like the control block", int(y.get("control_tick", -1)) == 7 and int(y.get("carrot_tick", -1)) == 7, "control=%s carrot=%s" % [str(y.get("control_tick")), str(y.get("carrot_tick"))])
	# boost appears exactly when the carrot matures (planted at t=0, matured at 40.0)
	var s: WorldState = make_world(40, 40, Callable(), func(w: WorldState) -> void: w.debug_fill_stage(Rect2i(15, 15, 10, 10), 4))
	var r: Rig = new_rig(s)
	var p: CultivatedPlant = land(r, &"carrot", Vector2(80, 80))
	r.run(39.75)
	var before_ok: bool = not p.mature and r.play.cultivation.boost_at(s.index_of(19, 14)) == 1000
	r.run(0.25)
	var after_ok: bool = p.mature and r.play.cultivation.boost_at(s.index_of(19, 14)) == 2000 and r.spread.scale_for(s.index_of(19, 14)) == 2000
	rec("carrot.matures_at_40", "the carrot is young at 39.75 s (no boost) and mature with the boost installed at 40.0 s (grow_seconds=40)", before_ok and after_ok, "before_ok=%s after_ok=%s" % [before_ok, after_ok])

# ------------------------------------------------------------------------------------------ kiwi

func heal_items(r: Rig) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for it: Dictionary in r.play.pickups.items:
		if String(it["kind"]) == "heal_fruit":
			list.append(it)
	return list

func key_of(it: Dictionary) -> String:
	return "%.3f,%.3f" % [float(it["x"]), float(it["y"])]

func t_kiwi() -> void:
	var s: WorldState = make_world(40, 40, Callable(), func(w: WorldState) -> void: w.debug_fill_stage(Rect2i(15, 15, 10, 10), 4))
	var r: Rig = new_rig(s)
	var p: CultivatedPlant = land(r, &"kiwi", Vector2(80, 80))
	var appear: Array[float] = []
	var vanish: Array[float] = []
	var known: Dictionary = {}
	var max_on_ground: int = 0
	var mature_at: float = -1.0
	var near_origin: bool = true
	for i: int in 4 * 160:
		r.step(0.25)
		if mature_at < 0.0 and p.mature:
			mature_at = r.t
		var cur: Dictionary = {}
		for it: Dictionary in heal_items(r):
			cur[key_of(it)] = true
			if not known.has(key_of(it)):
				appear.append(r.t)
				var c: Vector2 = p.center_tiles() * TILE
				var dist: float = Vector2(float(it["x"]), float(it["y"])).distance_to(c)
				near_origin = near_origin and dist >= 5.99 and dist <= 12.01
		for k: String in known:
			if not cur.has(k):
				vanish.append(r.t)
		known = cur
		max_on_ground = maxi(max_on_ground, cur.size())
	observations["kiwi_timeline"] = {"mature_at": mature_at, "appear": appear, "vanish": vanish, "max_on_ground": max_on_ground}
	rec("kiwi.mature_time", "the kiwi becomes mature at 40 s of game time", absf(mature_at - 40.0) < 0.01, "mature_at=%.3f" % mature_at)
	rec("kiwi.first_fruit", "first fruit 20 s after maturity (t=60); second at t=80", appear.size() >= 2 and absf(appear[0] - 60.0) <= 0.26 and absf(appear[1] - 80.0) <= 0.26, "appear=%s" % str(appear))
	rec("kiwi.cap_per_plant", "never more than 2 fruits of one kiwi on the ground", max_on_ground == 2, "max=%d" % max_on_ground)
	rec("kiwi.lifetime", "each fruit disappears 30 s after it appeared (uncollected)", vanish.size() >= 2 and absf(vanish[0] - (appear[0] + 30.0)) <= 0.26 and absf(vanish[1] - (appear[1] + 30.0)) <= 0.26, "vanish=%s" % str(vanish))
	var gaps_ok: bool = true
	for i: int in range(1, appear.size()):
		gaps_ok = gaps_ok and appear[i] - appear[i - 1] >= 19.74
	rec("kiwi.interval", "consecutive drops of one kiwi are at least 20 s apart over 160 s", gaps_ok and appear.size() >= 3, "appear=%s" % str(appear))
	rec("kiwi.drop_near_plant", "fruits drop 6..12 px from the footprint centre", near_origin, "ok=%s" % near_origin)
	# before maturity nothing
	var early: bool = true
	for t: float in appear:
		early = early and t > 40.0
	rec("kiwi.none_before_mature", "no fruit before the kiwi is mature", early, "first=%.2f" % (appear[0] if appear.size() > 0 else -1.0))
	# total cap with many kiwis
	var s2: WorldState = make_world(80, 80, Callable(), func(w: WorldState) -> void: w.debug_fill_stage(Rect2i(4, 4, 70, 70), 4))
	var r2: Rig = new_rig(s2, [], [Vector2(300, 300)])
	r2.play.seeds = 40
	var kiwis: Array[CultivatedPlant] = []
	for i: int in 9:
		var q: CultivatedPlant = land(r2, &"kiwi", Vector2(40 + 32 * (i % 3), 40 + 32 * (i / 3)))
		if q != null:
			kiwis.append(q)
	r2.player_pos = Vector2(2000, 2000)
	var max_heal: int = 0
	var per_plant_ok: bool = true
	var seed_items_ok: bool = true
	var cap_steps: int = 0
	var source_mismatch: int = 0
	var ctl_world: WorldState = make_world(80, 80, Callable(), func(w: WorldState) -> void: w.debug_fill_stage(Rect2i(4, 4, 70, 70), 4))
	var ctl: Rig = new_rig(ctl_world, [], [Vector2(300, 300)])
	ctl.player_pos = Vector2(2000, 2000)
	for i: int in 4 * 200:
		r2.step(0.25)
		ctl.step(0.25)
		if r2.play.pickups.count_owned(1) != ctl.play.pickups.count_owned(1) or r2.play.sources[0].drops != ctl.play.sources[0].drops:
			source_mismatch += 1
		var items: Array[Dictionary] = heal_items(r2)
		max_heal = maxi(max_heal, items.size())
		if items.size() == 16:
			cap_steps += 1

		for q: CultivatedPlant in kiwis:
			if r2.play.pickups.count_owned(2000000 + q.uid) > 2:
				per_plant_ok = false
		seed_items_ok = seed_items_ok and r2.play.pickups.count_seed_items() <= r2.play.tuning.pickup_total_cap
	rec("kiwi.total_cap", "9 kiwis (18 fruits possible) never put more than the region-wide cap (16) of healing fruits on the ground, and the cap is reached", kiwis.size() == 9 and max_heal == 16, "kiwis=%d max_heal=%d" % [kiwis.size(), max_heal])
	rec("kiwi.cap_each_in_crowd", "in the crowd no kiwi exceeds its own cap of 2", per_plant_ok, "ok=%s" % per_plant_ok)
	# seed supply is not crowded out by 16 healing fruits
	var heal_now: int = heal_items(r2).size()
	var source_count: int = r2.play.pickups.count_owned(1)
	rec("kiwi.source_slots_kept", "the seed source behaves exactly as in an identical world without kiwis (fruit count and drops equal at every step of 200 s, 117+ of them with 16 healing fruits on the ground)", cap_steps > 10 and source_mismatch == 0, "steps_at_cap=%d steps where the seed source differs from an identical world without kiwis=%d (now: heal=%d source=%d)" % [cap_steps, source_mismatch, heal_now, source_count])
	rec("kiwi.seed_cap_independent", "seed fruit items stay within pickup_total_cap while healing fruits are separate", seed_items_ok, "ok=%s total_cap=%d" % [seed_items_ok, r2.play.tuning.pickup_total_cap])
	# plant seed fruits: player near mature tiles, far from fruits
	r2.player_pos = Vector2(260, 260)
	var plant_fruit_peak: int = 0
	for i: int in 4 * 120:
		r2.step(0.25)
		plant_fruit_peak = maxi(plant_fruit_peak, r2.play.pickups.count_plant_owned())
	rec("kiwi.plant_fruit_slots_kept", "with healing fruits at the cap, mature tiles near the player still drop their own seed fruits (plant slot not taken)", plant_fruit_peak > 0 and heal_items(r2).size() <= 16, "plant_fruit_peak=%d heal=%d" % [plant_fruit_peak, heal_items(r2).size()])
	# recovery from zero seeds
	var wait_guard: int = 0
	while heal_items(r2).size() < 16 and wait_guard < 4 * 300:
		r2.step(0.25)
		wait_guard += 1
	var heal_at_recovery_start: int = heal_items(r2).size()
	r2.play.seeds = 0
	r2.play.hp = r2.play.hp_max
	var src_pos: Vector2 = r2.play.sources[0].position
	r2.player_pos = src_pos
	for it2: Dictionary in r2.play.pickups.items:
		if int(it2["owner"]) == 1:
			r2.player_pos = Vector2(float(it2["x"]), float(it2["y"]))
			break
	var got_seed: bool = false
	for i: int in 4 * 20:
		r2.step(0.25)
		if r2.play.seeds > 0:
			got_seed = true
			break
	rec("kiwi.recover_from_zero", "from 0 seeds, standing at the seed source yields a seed within 20 s although 16 healing fruits are on the ground (HP full)", got_seed and heal_at_recovery_start == 16, "seeds=%d heal at start=%d" % [r2.play.seeds, heal_at_recovery_start])
	# the total heal count is released: free slots again after fruits vanish and plants refill
	# healing a player
	var s3: WorldState = make_world(40, 40, Callable(), func(w: WorldState) -> void: w.debug_fill_stage(Rect2i(15, 15, 10, 10), 4))
	var r3: Rig = new_rig(s3)
	var k3: CultivatedPlant = land(r3, &"kiwi", Vector2(80, 80))
	r3.run(81.0)
	var items3: Array[Dictionary] = heal_items(r3)
	rec("kiwi.two_fruits_ready", "81 s: two fruits lie around the kiwi", items3.size() == 2 and k3.mature, "items=%d" % items3.size())
	if items3.size() == 2:
		var fa: Vector2 = Vector2(float(items3[0]["x"]), float(items3[0]["y"]))
		var fb: Vector2 = Vector2(float(items3[1]["x"]), float(items3[1]["y"]))
		r3.play.hp = 5
		r3.player_pos = fa
		r3.step(0.25)
		rec("kiwi.heal_plus_two", "picking a fruit at HP 5 gives HP 7 and consumes the fruit", r3.play.hp == 7 and heal_items(r3).size() == 1, "hp=%d fruits=%d" % [r3.play.hp, heal_items(r3).size()])
		r3.play.hp = 9
		r3.player_pos = fb
		r3.step(0.25)
		rec("kiwi.heal_clamped", "at HP 9 a fruit (+2) brings HP to the maximum 10 only, and is consumed", r3.play.hp == 10 and heal_items(r3).size() == 0, "hp=%d fruits=%d" % [r3.play.hp, heal_items(r3).size()])
		# wait for a new fruit, stand on it at full HP
		r3.player_pos = Vector2(4000, 4000)
		var guard: int = 0
		while heal_items(r3).is_empty() and guard < 4 * 60:
			r3.step(0.25)
			guard += 1
		var fruit: Array[Dictionary] = heal_items(r3)
		if fruit.is_empty():
			rec("kiwi.full_hp_keeps_fruit", "a new fruit appears", false, "none after 60 s")
		else:
			r3.player_pos = Vector2(float(fruit[0]["x"]), float(fruit[0]["y"]))
			r3.run(3.0)
			rec("kiwi.full_hp_keeps_fruit", "at full HP standing on a fruit does not collect it", heal_items(r3).size() >= 1 and r3.play.hp == 10, "hp=%d fruits=%d" % [r3.play.hp, heal_items(r3).size()])
			r3.play.damage_player(3)
			r3.step(0.25)
			rec("kiwi.fruit_kept_then_used", "after taking damage the waiting fruit is picked up (+2)", r3.play.hp == 9, "hp=%d" % r3.play.hp)

# ------------------------------------------------------------------------------------------ hp

func t_hp() -> void:
	var r: Rig = new_rig(make_world(10, 10))
	var p: PlayState = r.play
	rec("hp.start", "HP starts at the maximum 10 / 10", p.hp == 10 and p.hp_max == 10, "hp=%d/%d" % [p.hp, p.hp_max])
	var lost: int = p.damage_player(3)
	var a: bool = lost == 3 and p.hp == 7
	var lost2: int = p.damage_player(100)
	var b: bool = lost2 == 7 and p.hp == 0
	var lost3: int = p.damage_player(2)
	var c: bool = lost3 == 0 and p.hp == 0
	var lost4: int = p.damage_player(-5)
	var d: bool = lost4 == 0 and p.hp == 0
	rec("hp.damage_floor", "damage lowers HP but never below 0; negative damage does nothing", a and b and c and d, "hp=%d" % p.hp)
	var g1: int = p.heal_player(2)
	var e: bool = g1 == 2 and p.hp == 2
	var g2: int = p.heal_player(100)
	var f: bool = g2 == 8 and p.hp == 10
	var g3: int = p.heal_player(2)
	var g: bool = g3 == 0 and p.hp == 10
	var g4: int = p.heal_player(-4)
	var h: bool = g4 == 0 and p.hp == 10
	rec("hp.heal_ceiling", "healing raises HP, never above 10; negative healing does nothing", e and f and g and h, "hp=%d" % p.hp)
	var signals: Array[int] = []
	p.hp_changed.connect(func(v: int) -> void: signals.append(v))
	p.damage_player(4)
	p.heal_player(1)
	p.heal_player(0)
	rec("hp.signal", "hp_changed fires on real changes only", signals == [6, 7], "signals=%s" % str(signals))
	# healing from 0
	p.hp = 0
	var s: WorldState = make_world(40, 40, Callable(), func(w: WorldState) -> void: w.debug_fill_stage(Rect2i(15, 15, 10, 10), 4))
	var r2: Rig = new_rig(s)
	land(r2, &"kiwi", Vector2(80, 80))
	r2.play.hp = 0
	r2.run(61.0)
	var it: Array[Dictionary] = heal_items(r2)
	if it.size() > 0:
		r2.player_pos = Vector2(float(it[0]["x"]), float(it[0]["y"]))
		r2.step(0.25)
	rec("hp.heal_from_zero", "from HP 0 a fruit heals to 2", r2.play.hp == 2, "hp=%d" % r2.play.hp)

# ------------------------------------------------------------------------------------------ frame-rate independence

func rate_snapshot(r: Rig) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append(world_hash(r.world))
	parts.append("spread %d/%d clock %d/%d" % [r.spread.total_planted, r.spread.queue_size(), r.clock.growth_ticks, r.clock.spread_ticks])
	for pl: CultivatedPlant in r.play.cultivation.plants:
		parts.append("%d:%s:%s:%d" % [pl.uid, pl.key, pl.mature, pl.drops])
	var pos: Array[String] = []
	for it: Dictionary in r.play.pickups.items:
		if String(it["kind"]) == "heal_fruit":
			pos.append("%.3f,%.3f,%d" % [float(it["x"]), float(it["y"]), roundi(float(it["age"]) * 2.0)])
	pos.sort()
	parts.append(str(pos))
	parts.append("hp %d seeds %d" % [r.play.hp, r.play.seeds])
	return "|".join(parts)

func t_rate() -> void:
	var snaps: Dictionary = {}
	for hz: int in [30, 60, 144]:
		var s: WorldState = make_world(100, 60, Callable(), func(w: WorldState) -> void:
			w.debug_fill_stage(Rect2i(10, 20, 6, 6), 4)
			w.debug_fill_stage(Rect2i(40, 20, 6, 6), 4))
		var r: Rig = new_rig(s)
		land(r, &"carrot", Vector2(48, 88))
		land(r, &"kiwi", Vector2(176, 88))
		land(r, &"kiwi", Vector2(184, 104))
		var dt: float = 1.0 / float(hz)
		var n: int = roundi(100.5 * hz)
		for i: int in n:
			r.step(dt)
		snaps[hz] = rate_snapshot(r)
		print("RATE hz=%d t=%.4f %s" % [hz, r.t, snaps[hz]])
	rec("rate.equal", "100.5 s at 30 / 60 / 144 Hz gives the same world, plants, drop counts, fruit positions, ticks", snaps[30] == snaps[60] and snaps[60] == snaps[144], str(snaps))

# ------------------------------------------------------------------------------------------ save

func build_save_rig() -> Rig:
	var s: WorldState = make_world(60, 60, Callable(), func(w: WorldState) -> void:
		w.debug_fill_stage(Rect2i(5, 5, 20, 20), 4))
	var r: Rig = new_rig(s, [], [Vector2(200, 200)])
	r.play.seeds = 30
	land(r, &"carrot", Vector2(40, 40))
	land(r, &"kiwi", Vector2(80, 40))
	land(r, &"kiwi", Vector2(40, 80))
	r.player_pos = Vector2(120, 120)
	r.run(75.0)
	r.play.hp = 6
	r.play.select_index(2)
	return r

func save_blob(r: Rig) -> String:
	return JSON.stringify({"world": r.world.to_dict(), "clock": r.clock.to_dict(), "growth": r.growth.to_dict(), "spread": r.spread.to_dict(), "play": r.play.to_dict()})

func restore_rig(blob: String) -> Rig:
	var parsed: Dictionary = JSON.parse_string(blob)
	var w2: WorldState = WorldState.from_dict(parsed["world"], region_def.terrains)
	var r: Rig = new_rig(w2, [], [Vector2(200, 200)], false)
	r.player_pos = Vector2(120, 120)
	r.clock.load_dict(parsed["clock"])
	r.growth.load_dict(parsed["growth"])
	r.spread.load_dict(parsed["spread"])
	r.play.seeds = 0
	var ok: bool = r.play.load_dict(parsed["play"])
	if not ok:
		print("RESTORE play.load_dict returned false")
	r.t = float(r.play.elapsed)
	return r

func play_json(r: Rig) -> String:
	return JSON.stringify(r.play.to_dict())

func t_save() -> void:
	var a: Rig = build_save_rig()
	var blob: String = save_blob(a)
	var b: Rig = restore_rig(blob)
	rec("save.restore_equal", "after save -> JSON -> load the play state (hp, plants, selection, pickups) equals the saved one", play_json(a) == play_json(b), "hp a=%d b=%d sel a=%d b=%d plants a=%d b=%d" % [a.play.hp, b.play.hp, a.play.selected_index, b.play.selected_index, a.play.cultivation.plants.size(), b.play.cultivation.plants.size()])
	rec("save.hp_selected", "HP 6 and the kiwi selection come back", b.play.hp == 6 and b.play.selected_index == 2 and b.play.selected_def().key == &"kiwi", "hp=%d sel=%d" % [b.play.hp, b.play.selected_index])
	rec("save.boost_rebuilt", "the carrot's per-tile boost is rebuilt on load and handed to the spread simulation", hash(a.spread.speed_scale) == hash(b.spread.speed_scale) and not b.spread.speed_scale.is_empty(), "a=%d b=%d" % [a.spread.speed_scale.size(), b.spread.speed_scale.size()])
	rec("save.world_consistent", "restored world counters and occupancy are consistent", b.world.counters_consistent() and occ_sum(b.world) == occ_sum(a.world) and b.world.occupancy_owners.size() == a.world.occupancy_owners.size(), "occ a=%d b=%d" % [occ_sum(a.world), occ_sum(b.world)])
	var same: bool = true
	var detail: String = ""
	for chunk: int in 6:
		var secs: float = 41.0 + chunk * 3.0
		a.run(secs)
		b.run(secs)
		var ha: String = "%s|%s" % [world_hash(a.world), play_json(a)]
		var hb: String = "%s|%s" % [world_hash(b.world), play_json(b)]
		if ha != hb:
			same = false
			detail += " chunk%d" % chunk
	rec("save.same_after_advance", "advancing the original and the restored copy by the same time (6 chunks, ~290 s) keeps world and play state identical", same, "diverged:%s" % detail)
	# reject bad data
	var base: Dictionary = JSON.parse_string(blob)
	var reject_cases: Dictionary = {}
	var variants: Array[String] = ["cult_version", "dup_uid", "unknown_key", "wrong_size", "uid_zero", "out_of_bounds", "entry_not_dict", "overlap", "heal_over_cap", "pickup_version"]
	for name: String in variants:
		var copy: Dictionary = JSON.parse_string(blob)
		mutate(name, copy)
		var target: Rig = restore_rig(blob)
		var before: String = "%s|%s" % [world_hash(target.world), play_json(target)]
		var plants_before: int = target.play.cultivation.plants.size()
		var occ_before: int = occ_sum(target.world)
		var ok: bool = target.play.load_dict(copy["play"])
		var after: String = "%s|%s" % [world_hash(target.world), play_json(target)]
		reject_cases[name] = {"accepted": ok, "unchanged": before == after, "plants_same": plants_before == target.play.cultivation.plants.size(), "occ_same": occ_before == occ_sum(target.world)}
	var all_ok: bool = true
	var bad_list: Array[String] = []
	for name: String in reject_cases:
		var rc: Dictionary = reject_cases[name]
		if bool(rc["accepted"]) or not bool(rc["unchanged"]) or not bool(rc["plants_same"]) or not bool(rc["occ_same"]):
			all_ok = false
			bad_list.append(name)
	rec("save.reject_invalid", "invalid cultivation / pickup data is refused (load returns false) and the state is left unchanged", all_ok, "bad=%s detail=%s" % [str(bad_list), str(reject_cases)])
	# tolerant fields
	var tol: Dictionary = JSON.parse_string(blob)
	tol["play"]["hp"] = 99
	tol["play"]["selected"] = "banana"
	var t1: Rig = restore_rig(blob)
	var ok_t: bool = t1.play.load_dict(tol["play"])
	rec("save.clamps", "an out-of-range HP is clamped to 10 and an unknown selection falls back to the first kind", ok_t and t1.play.hp == 10 and t1.play.selected_index == 0, "ok=%s hp=%d sel=%d" % [ok_t, t1.play.hp, t1.play.selected_index])
	tol["play"]["hp"] = -5
	var ok_t2: bool = t1.play.load_dict(tol["play"])
	rec("save.clamps_low", "a negative HP is clamped to 0", ok_t2 and t1.play.hp == 0, "ok=%s hp=%d" % [ok_t2, t1.play.hp])
	# plant data that does not fit the world's tiles (observation)
	var odd: Dictionary = JSON.parse_string(blob)
	var t2: Rig = restore_rig(blob)
	odd["play"]["cultivated"]["plants"][0]["x"] = 50
	odd["play"]["cultivated"]["plants"][0]["y"] = 50
	var ok_odd: bool = t2.play.load_dict(odd["play"])
	observations["plant_on_nonmature_ground_load"] = {"accepted": ok_odd, "stage_at_target": int(t2.world.stage[t2.world.index_of(50, 50)])}
	rec("save.plant_on_empty_ground", "loading a plant whose 2x2 is not mature ground in the restored world (inconsistent save) is refused", not ok_odd, "accepted=%s stage there=%d" % [ok_odd, int(t2.world.stage[t2.world.index_of(50, 50)])])

# ------------------------------------------------------------------------------------------ empty arrays in saves

func t_empty() -> void:
	var s: WorldState = make_world(30, 30)
	var r: Rig = new_rig(s)
	var sp: Dictionary = r.spread.to_dict()
	var gr: Dictionary = r.growth.to_dict()
	var wd: Dictionary = s.to_dict()
	print("EMPTY spread=%s growth=%s" % [JSON.stringify(sp), JSON.stringify(gr)])
	var blob: String = JSON.stringify({"world": wd, "spread": sp, "growth": gr, "clock": r.clock.to_dict(), "play": r.play.to_dict()})
	var parsed: Dictionary = JSON.parse_string(blob)
	var w2: WorldState = WorldState.from_dict(parsed["world"], region_def.terrains)
	var r2: Rig = new_rig(w2, [], [], false)
	var ok_s: bool = r2.spread.load_dict(parsed["spread"])
	var ok_g: bool = r2.growth.load_dict(parsed["growth"])
	var ok_p: bool = r2.play.load_dict(parsed["play"])
	rec("empty.roundtrip", "a world with nothing growing and no candidates saves (empty arrays) and loads back without error", w2 != null and ok_s and ok_g and ok_p, "world=%s spread=%s growth=%s play=%s" % [w2 != null, ok_s, ok_g, ok_p])
	rec("empty.zero_entries", "empty arrays are stored as zero-length entries, not as encoded garbage", int(sp["queue"]["n"]) == 0 and int(gr["active"]["n"]) == 0 and int(sp["pending"]["n"]) == 0, "queue n=%d active n=%d" % [int(sp["queue"]["n"]), int(gr["active"]["n"])])
	var restored_empty: bool = r2.spread.queue_size() == 0 and r2.world.active_tiles.size() == 0
	rec("empty.restored_empty", "the restored empty state is empty and keeps running", restored_empty, "queue=%d active=%d" % [r2.spread.queue_size(), r2.world.active_tiles.size()])
	r2.run(10.0)
	var direct: Dictionary = WorldState._pack_bytes(PackedByteArray())
	var back: PackedByteArray = WorldState._unpack_bytes(direct)
	rec("empty.pack_unpack", "_pack_bytes / _unpack_bytes of an empty array round-trips to an empty array", back.is_empty() and int(direct["n"]) == 0, str(direct))

func mutate(name: String, d: Dictionary) -> void:
	var plants: Array = d["play"]["cultivated"]["plants"]
	match name:
		"cult_version":
			d["play"]["cultivated"]["version"] = 2
		"dup_uid":
			plants[1]["uid"] = plants[0]["uid"]
		"unknown_key":
			plants[0]["key"] = "banana"
		"wrong_size":
			plants[0]["size"] = 3
		"uid_zero":
			plants[0]["uid"] = 0
		"out_of_bounds":
			plants[0]["x"] = 59
		"entry_not_dict":
			plants[0] = 5
		"overlap":
			plants[1]["x"] = plants[0]["x"]
			plants[1]["y"] = plants[0]["y"]
		"heal_over_cap":
			for i: int in 17:
				d["play"]["pickups"]["items"].append({"kind": "heal_fruit", "x": 1.0, "y": 1.0, "age": 0.0, "owner": 2000001})
		"pickup_version":
			d["play"]["pickups"]["version"] = 9

# ---- r2: scaffold / growth consistency rejection (after the F1 fix) -------------------------------------------
func t_save2() -> void:
	var a: Rig = build_save_rig()
	var blob: String = save_blob(a)
	var cases: Array[String] = ["stage_seed", "stage_sprout1", "stage_sprout2", "stage_empty", "water", "oob", "mature_but_young", "young_but_old_age", "age_over", "overlap_other", "moved_to_empty"]
	var bad: Array[String] = []
	var detail: Dictionary = {}
	for name: String in cases:
		var t: Rig = restore_rig(blob)
		var copy: Dictionary = JSON.parse_string(blob)
		var p0: Dictionary = copy["play"]["cultivated"]["plants"][0]
		var tx: int = int(p0["x"])
		var ty: int = int(p0["y"])
		var idx: int = t.world.index_of(tx, ty)
		match name:
			"stage_seed":
				t.world.set_stage(idx, 1)
			"stage_sprout1":
				t.world.set_stage(idx, 2)
			"stage_sprout2":
				t.world.set_stage(idx + 1, 3)
			"stage_empty":
				t.world.set_stage(idx + t.world.width, 0)
			"water":
				t.world.terrain[idx] = W_WATER
			"oob":
				p0["x"] = 59
				p0["y"] = 59
			"mature_but_young":
				p0["mature"] = true
				p0["age"] = 5.0
			"young_but_old_age":
				p0["mature"] = false
				p0["age"] = 45.0
			"age_over":
				p0["mature"] = true
				p0["age"] = 99.0
			"overlap_other":
				var p1: Dictionary = copy["play"]["cultivated"]["plants"][1]
				p1["x"] = tx + 1
				p1["y"] = ty
			"moved_to_empty":
				p0["x"] = 50
				p0["y"] = 50
		var before: String = "%s|%s" % [world_hash(t.world), play_json(t)]
		var occ_before: int = occ_sum(t.world)
		var n_before: int = t.play.cultivation.plants.size()
		var ok: bool = t.play.load_dict(copy["play"])
		var after: String = "%s|%s" % [world_hash(t.world), play_json(t)]
		detail[name] = {"accepted": ok, "unchanged": before == after, "occ_same": occ_before == occ_sum(t.world), "plants_same": n_before == t.play.cultivation.plants.size()}
		if ok or before != after or occ_before != occ_sum(t.world) or n_before != t.play.cultivation.plants.size():
			bad.append(name)
	rec("save2.reject_inconsistent", "plants on seed / sprout1 / sprout2 / empty scaffold, non-target ground, out of bounds, overlapping another plant, moved onto empty ground, and mature-vs-age contradictions are refused with state unchanged", bad.is_empty(), "bad=%s detail=%s" % [str(bad), str(detail)])
	# F1 reproduction exactly
	var t2: Rig = restore_rig(blob)
	var odd: Dictionary = JSON.parse_string(blob)
	odd["play"]["cultivated"]["plants"][0]["x"] = 50
	odd["play"]["cultivated"]["plants"][0]["y"] = 50
	rec("save2.f1_repro_rejected", "F1 reproduction (plants[0] x,y rewritten to empty ground) is now refused", not t2.play.load_dict(odd["play"]), "stage there=%d" % int(t2.world.stage[t2.world.index_of(50, 50)]))
	# normal restore again, into a fresh rig (world occupancy already present) and into the same rig twice
	var b: Rig = restore_rig(blob)
	var again: bool = b.play.load_dict(JSON.parse_string(blob)["play"])
	rec("save2.normal_reload_ok", "a valid save loads, also a second time into the same state", again and play_json(a) == play_json(b), "again=%s" % again)
