extends SceneTree
## Independent verifier for P1-04, logic level (headless, no scene). Expectations come from the spec/settings and from
## my own brute force (BFS, recounts), not from the implementation's formulas.
## Run: Godot --headless --path <project> --script res://tests/p1/independent/p1_04_v_logic.gd -- --only=<section>

const OUT: String = "res://evidence/p1/p1-04/independent/"
const W_WASTE: int = 0
const W_SAFE: int = 1
const W_SHORE: int = 2
const W_WATER: int = 3
const W_BUILD: int = 4

var results: Array[Dictionary] = []
var observations: Dictionary = {}
var tun: SimTuning
var region_def: RegionDef

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func run() -> void:
	tun = load("res://data/sim_tuning.tres") as SimTuning
	region_def = load("res://data/region_01.tres") as RegionDef
	var only: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	var tests: Dictionary = {
		"target": t_target, "reach": t_reach, "stress": t_stress, "split": t_split, "front": t_front,
		"save": t_save, "dt": t_dt, "perf": t_perf, "region": t_region,
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

func make_world(w: int, h: int, fill: int = W_WASTE) -> WorldState:
	var s: WorldState = WorldState.new(w, h, region_def.terrains, 12345)
	s.terrain.fill(fill)
	return s

func finish(s: WorldState) -> void:
	s.apply_terrain_defs()

func driver_for(s: WorldState, t: SimTuning) -> SimulationDriver:
	var d: SimulationDriver = SimulationDriver.new()
	d.setup(s, t)
	return d

func run_seconds(d: SimulationDriver, seconds: float) -> void:
	var steps: int = roundi(seconds / 0.25)
	for i: int in steps:
		d.clock.advance(0.25)

func recount_green(s: WorldState) -> int:
	var n: int = 0
	for i: int in s.tile_count():
		if s.target[i] == 1 and s.stage[i] >= 2:
			n += 1
	return n

func count_stage(s: WorldState, st: int) -> int:
	var n: int = 0
	for i: int in s.tile_count():
		if s.stage[i] == st:
			n += 1
	return n

func count_natural(s: WorldState) -> int:
	var n: int = 0
	for i: int in s.tile_count():
		n += s.natural[i]
	return n

func world_hash(s: WorldState) -> String:
	return "%d/%d/%d/%d" % [hash(s.stage), hash(s.growth), hash(s.moisture), hash(s.natural)]

# ------------------------------------------------------------------------------------------ 1 target selection

func t_target() -> void:
	var s: WorldState = make_world(41, 41)
	var c: Vector2i = Vector2i(20, 20)
	s.terrain[s.index_of(22, 20)] = W_WATER
	s.terrain[s.index_of(20, 22)] = W_BUILD
	s.terrain[s.index_of(20, 18)] = W_SHORE
	finish(s)
	s.set_stage(s.index_of(c.x, c.y), 4)
	s.set_stage(s.index_of(19, 19), 3)
	s.set_stage(s.index_of(20, 19), 1)
	s.occupy(Rect2i(21, 20, 1, 1), 7)
	s.clear_dirty()
	var d: SimulationDriver = driver_for(s, tun)
	var refuse: Dictionary = {s.index_of(18, 20): true}
	d.spread.allow_hook = func(i: int) -> bool: return not refuse.has(i)
	run_seconds(d, 9.0)
	var early: int = count_natural(s)
	rec("target.not_before_min_time", "with 1 mature neighbour the rate is threshold/rate = 10 ticks: no natural seed before tick 10", early == 0, "natural tiles at 9 s = %d" % early)
	run_seconds(d, 6.0)
	var want: Dictionary = {}
	for dy: int in range(-3, 4):
		for dx: int in range(-3, 4):
			if (dx != 0 or dy != 0) and dx * dx + dy * dy <= 4:
				want[Vector2i(c.x + dx, c.y + dy)] = true
	for t: Vector2i in [Vector2i(22, 20), Vector2i(20, 22), Vector2i(21, 20), Vector2i(19, 19), Vector2i(20, 19), Vector2i(18, 20)]:
		want.erase(t)
	var got: Dictionary = {}
	var stray: PackedStringArray = PackedStringArray()
	for y: int in 41:
		for x: int in 41:
			var i: int = s.index_of(x, y)
			if s.natural[i] == 1:
				got[Vector2i(x, y)] = true
			elif s.stage[i] != 0 and Vector2i(x, y) not in [c, Vector2i(19, 19), Vector2i(20, 19)]:
				stray.append(str(Vector2i(x, y)))
	var same: bool = got.size() == want.size()
	for k: Vector2i in want:
		if not got.has(k):
			same = false
	rec("target.exact_set", "at 15 s the naturally planted tiles are exactly the free plantable target tiles within Euclid 2 of the mature tile (12 offsets minus water, building, occupied, existing seed/sprout, hook-refused = 6)", same and stray.is_empty(), "got %d want %d stray=%s" % [got.size(), want.size(), str(stray)])
	rec("target.no_outside_radius", "tiles at distance sqrt5 / 3 are not planted", s.stage[s.index_of(22, 21)] == 0 and s.stage[s.index_of(18, 21)] == 0 and s.stage[s.index_of(23, 20)] == 0 and s.stage[s.index_of(20, 17)] == 0, "ok")
	rec("target.existing_untouched", "pre-existing player seed/sprout keep natural=0 and are not reset; non-target tiles stay empty", s.natural[s.index_of(19, 19)] == 0 and s.natural[s.index_of(20, 19)] == 0 and s.stage[s.index_of(19, 19)] >= 3 and s.stage[s.index_of(22, 20)] == 0 and s.stage[s.index_of(20, 22)] == 0, "stage(19,19)=%d stage(20,19)=%d" % [s.stage[s.index_of(19, 19)], s.stage[s.index_of(20, 19)]])
	rec("target.counter_seed_not_counted", "greened counter == recount; the 6 natural seeds are not counted", s.greened_count == recount_green(s) and count_stage(s, 1) >= 6 and s.counters_consistent(), "greened=%d recount=%d seeds=%d" % [s.greened_count, recount_green(s), count_stage(s, 1)])
	var refused_before: int = s.stage[s.index_of(18, 20)]
	refuse.clear()
	s.release(7)
	for i: int in 12:
		run_seconds(d, 1.0)
	rec("target.hook_lift_spreads", "refused tile stays empty while refused, and is planted (naturally) within 12 ticks after the hook allows it", refused_before == 0 and s.stage[s.index_of(18, 20)] >= 1 and s.natural[s.index_of(18, 20)] == 1, "before=%d stage=%d natural=%d" % [refused_before, s.stage[s.index_of(18, 20)], s.natural[s.index_of(18, 20)]])
	rec("target.release_spreads", "a released occupied tile becomes a candidate and is planted", s.stage[s.index_of(21, 20)] >= 1, "stage=%d" % s.stage[s.index_of(21, 20)])
	var s2: WorldState = make_world(21, 21)
	finish(s2)
	s2.set_stage(s2.index_of(10, 10), 4)
	var d2: SimulationDriver = driver_for(s2, tun)
	d2.spread.allow_hook = func(_i: int) -> bool: return false
	run_seconds(d2, 120.0)
	rec("target.hook_blocks_all", "a hook that refuses everything: nothing spreads in 120 s, candidates stay queued", count_stage(s2, 1) + count_stage(s2, 2) + count_stage(s2, 3) == 0 and d2.spread.queue_size() == 12, "queue=%d" % d2.spread.queue_size())
	d.free()
	d2.free()

# ------------------------------------------------------------------------------------------ 2 reach, fairness, determinism

func build_reach_map() -> WorldState:
	var s: WorldState = make_world(120, 60, W_BUILD)
	var rects: Array[Rect2i] = [
		Rect2i(2, 2, 29, 29),    # A
		Rect2i(31, 16, 30, 1),   # corridor width 1
		Rect2i(61, 6, 20, 21),   # B
		Rect2i(82, 6, 14, 21),   # C behind a 1-wide water gap at x=81
		Rect2i(98, 6, 12, 21),   # D behind a 2-wide water gap at x=96,97
		Rect2i(100, 40, 15, 15), # G closed island
		Rect2i(2, 50, 30, 8),    # F reached by the diagonal chain
	]
	for r: Rect2i in rects:
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x):
				s.terrain[s.index_of(x, y)] = W_WASTE
	for y: int in range(6, 27):
		s.terrain[s.index_of(81, y)] = W_WATER
		s.terrain[s.index_of(96, y)] = W_WATER
		s.terrain[s.index_of(97, y)] = W_WATER
	for k: int in 19:
		s.terrain[s.index_of(4 + k, 32 + k)] = W_SHORE
	for x: int in range(10, 14):
		s.terrain[s.index_of(x, 10)] = W_SHORE
	finish(s)
	return s

func offsets_r2() -> Array[Vector2i]:
	var offs: Array[Vector2i] = []
	for dy: int in range(-2, 3):
		for dx: int in range(-2, 3):
			if (dx != 0 or dy != 0) and dx * dx + dy * dy <= 4:
				offs.append(Vector2i(dx, dy))
	return offs

func bfs_depths(s: WorldState, starts: Array) -> Dictionary:
	var depth: Dictionary = {}
	var frontier: Array = []
	for st: int in starts:
		depth[st] = 0
		frontier.append(st)
	var offs: Array[Vector2i] = offsets_r2()
	while not frontier.is_empty():
		var next: Array = []
		for i: int in frontier:
			var x: int = i % s.width
			var y: int = i / s.width
			for o: Vector2i in offs:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx < 0 or ny < 0 or nx >= s.width or ny >= s.height:
					continue
				var j: int = ny * s.width + nx
				if depth.has(j) or s.target[j] == 0 or not s.terrain_defs[s.terrain[j]].plantable:
					continue
				depth[j] = int(depth[i]) + 1
				next.append(j)
		frontier = next
	return depth

func run_reach(record_gap: bool) -> Dictionary:
	var s: WorldState = build_reach_map()
	var start: int = s.index_of(5, 5)
	s.set_stage(start, 4)
	var d: SimulationDriver = driver_for(s, tun)
	var visits: Dictionary = {}
	var res: Dictionary = {"gap_max": 0}
	if record_gap:
		d.spread.allow_hook = func(i: int) -> bool:
			var now: int = d.spread.ticks
			if visits.has(i):
				var gap: int = now - int(visits[i])
				if gap > int(res["gap_max"]):
					res["gap_max"] = gap
			visits[i] = now
			return true
	var arrival: Dictionary = {}
	var depth: Dictionary = bfs_depths(s, [start])
	var qmax: int = 0
	var amax: int = 0
	var emax: int = 0
	var max_depth: int = 0
	for k: int in depth:
		max_depth = maxi(max_depth, int(depth[k]))
	var green_bad: int = 0
	var seconds: int = 0
	var limit_s: int = 60 * 60 * 3
	while seconds < limit_s:
		run_seconds(d, 1.0)
		seconds += 1
		qmax = maxi(qmax, d.spread.queue_size())
		amax = maxi(amax, s.active_tiles.size())
		emax = maxi(emax, d.spread.pending_size())
		if seconds % 20 == 0:
			if s.greened_count != recount_green(s) or not s.counters_consistent():
				green_bad += 1
		if seconds % 5 == 0:
			for k: int in depth:
				if not arrival.has(k) and s.stage[k] != 0:
					arrival[k] = seconds
			if arrival.size() == depth.size() and s.mature_count == depth.size():
				break
	res["arrival"] = arrival
	res["hash"] = world_hash(s)
	res["qmax"] = qmax
	res["amax"] = amax
	res["emax"] = emax
	res["depth"] = depth
	res["max_depth"] = max_depth
	res["seconds"] = seconds
	res["green_bad"] = green_bad
	res["world"] = s
	d.free()
	return res

func t_reach() -> void:
	var r1: Dictionary = run_reach(true)
	var s: WorldState = r1["world"]
	var depth: Dictionary = r1["depth"]
	var arrival: Dictionary = r1["arrival"]
	var unreachable_touched: int = 0
	var unreachable_total: int = 0
	for i: int in s.tile_count():
		if s.target[i] == 1 and not depth.has(i):
			unreachable_total += 1
			if s.stage[i] != 0:
				unreachable_touched += 1
	var q: int = int(r1["qmax"])
	var e: int = int(r1["emax"])
	var a: int = int(r1["amax"])
	var seed_wait: int = (e + tun.spread_mature_events_per_tick - 1) / tun.spread_mature_events_per_tick + int(ceil(float(tun.spread_progress_threshold) / float(tun.spread_progress_per_tick))) + (q + tun.spread_candidates_per_tick - 1) / tun.spread_candidates_per_tick + 1
	var grow_ticks: int = int(ceil(float(tun.mature_growth) / (float(tun.base_growth_per_tick) * tun.moisture_growth_min * tun.natural_growth_multiplier))) + (a + tun.max_growth_tiles_per_tick - 1) / tun.max_growth_tiles_per_tick + 1
	var hop_s: float = float(seed_wait) * tun.spread_tick_seconds + float(grow_ticks) * tun.growth_tick_seconds
	var late: int = 0
	var missing: int = 0
	var worst_ratio: float = 0.0
	for k: int in depth:
		if int(depth[k]) == 0:
			continue
		if not arrival.has(k):
			missing += 1
			continue
		var limit: float = float(depth[k]) * hop_s + 5.0
		if float(arrival[k]) > limit:
			late += 1
		worst_ratio = maxf(worst_ratio, float(arrival[k]) / limit)
	observations["reach"] = {"reachable_targets": depth.size(), "unreachable_targets": unreachable_total, "max_depth": r1["max_depth"], "hop_bound_s": hop_s, "seconds": r1["seconds"], "qmax": q, "emax": e, "amax": a, "worst_arrival_over_bound": worst_ratio}
	rec("reach.all_connected_reached", "every tile connected to the start through radius-2 plantable hops (by my BFS) is planted", missing == 0 and depth.size() > 1500, "reachable=%d missing=%d max_depth=%d finished at %d s" % [depth.size(), missing, r1["max_depth"], r1["seconds"]])
	rec("reach.within_bound", "each reached tile at BFS depth d was planted within d x (own per-hop bound %.1f s from settings) + 5 s" % hop_s, late == 0, "late=%d worst arrival/bound=%.3f" % [late, worst_ratio])
	rec("reach.unreachable_untouched", "tiles beyond a 2-wide water gap, beyond building gaps >= 3 and the closed island never get any stage", unreachable_touched == 0 and unreachable_total > 100, "unreachable targets=%d touched=%d" % [unreachable_total, unreachable_touched])
	rec("reach.narrow_features", "1-wide corridor, 1-wide water gap (dx=2) and the diagonal chain are crossed; 2-wide gap is not", arrival.has(s.index_of(60, 16)) and arrival.has(s.index_of(82, 16)) and arrival.has(s.index_of(95, 10)) and arrival.has(s.index_of(22, 50)) and s.stage[s.index_of(98, 16)] == 0 and s.stage[s.index_of(105, 45)] == 0, "t(60,16)=%s t(82,16)=%s t(chain end)=%s D=%d G=%d" % [str(arrival.get(s.index_of(60, 16))), str(arrival.get(s.index_of(82, 16))), str(arrival.get(s.index_of(22, 50))), s.stage[s.index_of(98, 16)], s.stage[s.index_of(105, 45)]])
	var gap_bound: int = (q + tun.spread_candidates_per_tick - 1) / tun.spread_candidates_per_tick
	rec("reach.fairness_gap", "no candidate waits more than ceil(Qmax/B) = %d spread ticks between two examinations (measured through the hook)" % gap_bound, int(r1["gap_max"]) <= gap_bound, "max gap=%d (Qmax=%d)" % [r1["gap_max"], q])
	rec("reach.counters", "greened/mature/target counters equal recount every 20 s during the whole natural spread", int(r1["green_bad"]) == 0 and s.counters_consistent(), "mismatch checks=%d final greened=%d target=%d" % [r1["green_bad"], s.greened_count, s.target_count])
	var r2: Dictionary = run_reach(false)
	rec("reach.deterministic", "second identical run gives identical world state and identical arrival times (no randomness)", r1["hash"] == r2["hash"] and arrival == r2["arrival"], "hash %s vs %s, arrival maps equal=%s" % [r1["hash"], r2["hash"], str(arrival == r2["arrival"])])

# ------------------------------------------------------------------------------------------ stress: many candidates, per-tick limits

func t_stress() -> void:
	var s: WorldState = make_world(300, 300)
	finish(s)
	var matures: int = 0
	for j: int in 40:
		for i: int in 40:
			s.set_stage(s.index_of(5 * i + 2, 5 * j + 2), 4)
			matures += 1
	var d: SimulationDriver = driver_for(s, tun)
	var first_visit: Dictionary = {}
	var visits_gap: Dictionary = {"max": 0}
	var last_seen: Dictionary = {}
	d.spread.allow_hook = func(i: int) -> bool:
		var now: int = d.spread.ticks
		if not first_visit.has(i):
			first_visit[i] = now
		if last_seen.has(i):
			visits_gap["max"] = maxi(int(visits_gap["max"]), now - int(last_seen[i]))
		last_seen[i] = now
		return true
	var own: Dictionary = {"max": 0}
	d.clock.growth_ticked.connect(func(_i: int) -> void:
		var processed: int = 0
		for t: int in s.active_tiles:
			if s.last_growth_tick[t] == d.growth.ticks:
				processed += 1
		own["max"] = maxi(int(own["max"]), processed))
	var exam_max: int = 0
	var ev_max: int = 0
	var gv_max: int = 0
	var gv_when_big: int = 0
	var big_ticks: int = 0
	var qmax: int = d.spread.queue_size()
	var emax: int = d.spread.pending_size()
	var amax: int = 0
	var green_bad: int = 0
	var spread_ticks_seen: int = 0
	for step: int in 4 * 150:
		var g0: int = d.clock.growth_ticks
		var sp0: int = d.clock.spread_ticks
		d.clock.advance(0.25)
		if d.clock.spread_ticks != sp0:
			spread_ticks_seen += 1
			exam_max = maxi(exam_max, d.spread.last_examined)
			ev_max = maxi(ev_max, d.spread.last_events)
			qmax = maxi(qmax, d.spread.queue_size())
			emax = maxi(emax, d.spread.pending_size())
		if d.clock.growth_ticks != g0:
			var act: int = s.active_tiles.size()
			amax = maxi(amax, act)
			gv_max = maxi(gv_max, d.growth.last_visited)
			if act > tun.max_growth_tiles_per_tick:
				big_ticks += 1
				gv_when_big = maxi(gv_when_big, d.growth.last_visited)
		if step % 40 == 39 and (s.greened_count != recount_green(s) or not s.counters_consistent()):
			green_bad += 1
	var q_bound: int = (qmax + tun.spread_candidates_per_tick - 1) / tun.spread_candidates_per_tick
	var e_bound: int = (emax + tun.spread_mature_events_per_tick - 1) / tun.spread_mature_events_per_tick
	var worst_first: int = 0
	var initial_missing: int = 0
	var initial_n: int = 0
	var seen_init: Dictionary = {}
	for j: int in 40:
		for i: int in 40:
			for o: Vector2i in offsets_r2():
				seen_init[s.index_of(5 * i + 2 + o.x, 5 * j + 2 + o.y)] = true
	for k: int in seen_init:
		if (k % 300) % 5 == 2 and (k / 300) % 5 == 2:
			continue
		initial_n += 1
		if not first_visit.has(k):
			initial_missing += 1
		else:
			worst_first = maxi(worst_first, int(first_visit[k]))
	var never: int = 0
	for i: int in s.tile_count():
		if s.natural[i] == 1 and not first_visit.has(i):
			never += 1
	observations["stress"] = {"matures": matures, "qmax": qmax, "emax": emax, "amax": amax, "worst_first_visit_tick": worst_first, "gap_max": visits_gap["max"], "exam_max": exam_max, "ev_max": ev_max, "gv_max": gv_max, "big_ticks": big_ticks, "natural_tiles": count_natural(s), "spread_ticks": spread_ticks_seen}
	rec("stress.queue_is_large", "scenario really has more candidates than B (so the budget binds)", qmax > 3 * tun.spread_candidates_per_tick, "Qmax=%d B=%d" % [qmax, tun.spread_candidates_per_tick])
	rec("stress.examined_le_B", "every spread tick examines <= B=%d candidates (and the cap is hit) and applies <= %d mature events" % [tun.spread_candidates_per_tick, tun.spread_mature_events_per_tick], exam_max == tun.spread_candidates_per_tick and ev_max <= tun.spread_mature_events_per_tick and ev_max > 0, "max examined=%d, max events=%d, spread ticks=%d" % [exam_max, ev_max, spread_ticks_seen])
	rec("stress.growth_le_G", "every growth tick processes <= G=%d active tiles (own count via last_growth_tick and reported last_visited), active set up to %d" % [tun.max_growth_tiles_per_tick, amax], gv_max <= tun.max_growth_tiles_per_tick and int(own["max"]) <= tun.max_growth_tiles_per_tick and big_ticks > 5 and gv_when_big == tun.max_growth_tiles_per_tick, "max visited=%d own-count max=%d ticks with active>G=%d (visited then=%d)" % [gv_max, int(own["max"]), big_ticks, gv_when_big])
	rec("stress.fairness", "gap between two examinations of one candidate <= ceil(Qmax/B)=%d; first examination within events wait + that" % q_bound, int(visits_gap["max"]) <= q_bound and worst_first <= e_bound + q_bound + 1 and initial_missing == 0, "gap max=%d bound=%d; %d initial candidates, never examined %d, worst first-visit tick=%d (limit %d)" % [visits_gap["max"], q_bound, initial_n, initial_missing, worst_first, e_bound + q_bound + 1])
	rec("stress.no_never_visited", "every naturally planted tile was examined before", never == 0, "never=%d" % never)
	rec("stress.counters", "counters equal recount during the run", green_bad == 0 and s.counters_consistent(), "bad=%d" % green_bad)
	d.free()

# ------------------------------------------------------------------------------------------ 4 split correctness

func make_growth_world(count: int, seed_value: int) -> WorldState:
	var s: WorldState = make_world(200, 100)
	finish(s)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var placed: int = 0
	while placed < count:
		var i: int = rng.randi_range(0, s.tile_count() - 1)
		if s.stage[i] != 0:
			continue
		var st: int = rng.randi_range(1, 3)
		s.set_stage(i, st)
		s.fertility[i] = rng.randi_range(0, 100)
		s.natural[i] = rng.randi_range(0, 1)
		if st == 2:
			s.growth[i] = 40000 + rng.randi_range(0, 30000)
		elif st == 3:
			s.growth[i] = 80000 + rng.randi_range(0, 30000)
		if rng.randi_range(0, 2) == 0:
			s.set_moisture(i, rng.randi_range(1, 100))
		placed += 1
	for k: int in 300:
		var j: int = rng.randi_range(0, s.tile_count() - 1)
		s.set_moisture(j, rng.randi_range(1, 100))
	return s

func t_split() -> void:
	var unl: SimTuning = tun.duplicate() as SimTuning
	unl.max_growth_tiles_per_tick = 0
	var big: SimTuning = tun.duplicate() as SimTuning
	big.max_growth_tiles_per_tick = 1 << 30
	var wa: WorldState = make_growth_world(8000, 77)
	var wb: WorldState = make_growth_world(8000, 77)
	var wc: WorldState = make_growth_world(8000, 77)
	var wd: WorldState = make_growth_world(8000, 77)
	var split_a: GrowthSim = GrowthSim.new(wa, tun)
	var unl_b: GrowthSim = GrowthSim.new(wb, unl)
	var split_c: GrowthSim = GrowthSim.new(wc, tun)
	var big_d: GrowthSim = GrowthSim.new(wd, big)
	var active0: int = wa.active_tiles.size()
	var sweep: int = (active0 + tun.max_growth_tiles_per_tick - 1) / tun.max_growth_tiles_per_tick
	var tracked: PackedInt32Array = PackedInt32Array()
	for i: int in wa.tile_count():
		if wa.stage[i] in [1, 2, 3]:
			tracked.append(i)
	var mat_a: Dictionary = {}
	var mat_b: Dictionary = {}
	var catch_bad: int = 0
	var catch_checks: int = 0
	var first_bad: String = ""
	var ticks_total: int = 400
	for t: int in range(1, ticks_total + 1):
		split_a.tick()
		unl_b.tick()
		split_c.tick()
		big_d.tick()
		for i: int in tracked:
			if not mat_a.has(i) and wa.stage[i] == 4:
				mat_a[i] = t
			if not mat_b.has(i) and wb.stage[i] == 4:
				mat_b[i] = t
		if t % 37 == 0 or t == ticks_total:
			split_c.catch_up()
			catch_checks += 1
			if world_hash(wc) != world_hash(wb) or wc.greened_count != wb.greened_count or wc.mature_count != wb.mature_count:
				catch_bad += 1
				if first_bad == "":
					first_bad = "tick %d" % t
		if t % 50 == 0 and world_hash(wd) != world_hash(wb):
			catch_bad += 1000
	var diff_max: int = 0
	var neg: int = 0
	var missing: int = 0
	var hist: Dictionary = {}
	for i: int in mat_b:
		if not mat_a.has(i):
			missing += 1
			continue
		var df: int = int(mat_a[i]) - int(mat_b[i])
		hist[df] = int(hist.get(df, 0)) + 1
		if df < 0:
			neg += 1
		diff_max = maxi(diff_max, df)
	rec("split.active_above_G", "scenario: active set %d > G=%d so the sweep really splits (sweep period %d ticks)" % [active0, tun.max_growth_tiles_per_tick, sweep], active0 > tun.max_growth_tiles_per_tick and sweep >= 3, "active0=%d" % active0)
	rec("split.maturity_delta", "tile by tile, maturity tick (G=3000) - maturity tick (unlimited) is in [0, sweep period=%d]" % sweep, missing == 0 and neg == 0 and diff_max <= sweep and mat_b.size() > 2000, "tiles matured=%d missing=%d negative=%d max diff=%d hist=%s" % [mat_b.size(), missing, neg, diff_max, str(hist)])
	rec("split.catch_up_exact", "after catch_up (every 37 ticks and at the end) stage/growth/moisture/natural/counters equal the unlimited run exactly; a huge G equals unlimited every 50 ticks", catch_bad == 0, "checks=%d bad=%d %s" % [catch_checks, catch_bad, first_bad])
	var w1: WorldState = make_growth_world(2500, 5)
	var w2: WorldState = make_growth_world(2500, 5)
	var g1: GrowthSim = GrowthSim.new(w1, tun)
	var g2: GrowthSim = GrowthSim.new(w2, unl)
	var same_ticks: int = 0
	var peak: int = 0
	for t: int in 250:
		peak = maxi(peak, w1.active_tiles.size())
		g1.tick()
		g2.tick()
		if world_hash(w1) == world_hash(w2):
			same_ticks += 1
	rec("split.under_G_identical", "active set (peak %d) <= G: identical to the unlimited run after every one of 250 ticks, without catch_up" % peak, same_ticks == 250 and peak <= tun.max_growth_tiles_per_tick, "identical ticks=%d/250" % same_ticks)
	var w3: WorldState = make_growth_world(3000, 9)
	var w4: WorldState = make_growth_world(3000, 9)
	var g3: GrowthSim = GrowthSim.new(w3, tun)
	var g4: GrowthSim = GrowthSim.new(w4, unl)
	var eq_edge: int = 0
	for t: int in 40:
		g3.tick()
		g4.tick()
		if world_hash(w3) == world_hash(w4):
			eq_edge += 1
	g3.catch_up()
	rec("split.boundary_exactly_G", "active set starts at exactly G=3000 (wet tiles push it above): tick-by-tick equal while <= G, and catch_up equal afterwards", world_hash(w3) == world_hash(w4), "tick-equal ticks=%d/40, after catch_up equal=%s" % [eq_edge, str(world_hash(w3) == world_hash(w4))])
	var back: int = 0
	var w5: WorldState = make_growth_world(6000, 21)
	var g5: GrowthSim = GrowthSim.new(w5, tun)
	var prev: PackedByteArray = w5.stage.duplicate()
	for t: int in 200:
		g5.tick()
		for i: int in w5.tile_count():
			if w5.stage[i] < prev[i]:
				back += 1
		prev = w5.stage.duplicate()
	rec("split.no_regress", "no tile's stage ever decreases while swept", back == 0, "regressions=%d" % back)

# ------------------------------------------------------------------------------------------ 6 manual vs natural

func front_x(s: WorldState) -> int:
	var best: int = -1
	for i: int in s.tile_count():
		if s.stage[i] == 4:
			best = maxi(best, i % s.width)
	return best

func strip_world() -> WorldState:
	var s: WorldState = make_world(400, 20)
	finish(s)
	for y: int in 20:
		for x: int in range(0, 4):
			s.set_stage(s.index_of(x, y), 4)
	return s

func t_front() -> void:
	var s: WorldState = strip_world()
	var d: SimulationDriver = driver_for(s, tun)
	var samples: Dictionary = {}
	var t_s: int = 0
	for target: int in [60, 120, 300, 600, 900, 1200]:
		run_seconds(d, float(target - t_s))
		t_s = target
		samples[target] = front_x(s)
	observations["front_natural"] = samples
	var speed: float = float(int(samples[1200]) - int(samples[300])) / (900.0 / 60.0)
	rec("front.speed", "natural front speed between 300 s and 1200 s (tiles/min); implementer claims about 4", speed > 3.0 and speed < 5.0, "front x at s: %s -> %.2f tiles/min" % [str(samples), speed])
	var m: WorldState = strip_world()
	var dm: SimulationDriver = driver_for(m, tun)
	var placed: PackedInt32Array = Landing.scatter_seeds(m, 4, Vector2((4 + 30) * 4.0, 10 * 4.0), 10.0, 6, 99)
	run_seconds(dm, 64.0)
	var manual_mature: int = 0
	for i: int in placed:
		if m.stage[i] == 4:
			manual_mature += 1
	var s2: WorldState = strip_world()
	var d2: SimulationDriver = driver_for(s2, tun)
	run_seconds(d2, 64.0)
	var natural_at_64: int = front_x(s2)
	var manual_far: int = front_x(m)
	rec("front.manual_one_shot", "one manual seed shot (up to 6 seeds, 30 tiles = projectile range away) becomes a mature patch in ~60 s while the natural-only front in the same 64 s advanced only %d tiles from the block edge (x=3)" % (natural_at_64 - 3), placed.size() >= 4 and manual_mature == placed.size() and manual_far >= 30 and natural_at_64 - 3 <= 6, "seeds placed=%d mature=%d; farthest mature x manual=%d natural=%d" % [placed.size(), manual_mature, manual_far, natural_at_64])
	var ratio: float = float(manual_far - 3) / maxf(float(natural_at_64 - 3), 1.0)
	rec("front.manual_faster", "distance reached in 64 s: manual shot is at least 4x the natural-only spread", ratio >= 4.0, "manual %d tiles vs natural %d tiles (ratio %.1f)" % [manual_far - 3, natural_at_64 - 3, ratio])
	var one: WorldState = make_world(20, 20)
	finish(one)
	one.set_stage(one.index_of(5, 5), 1)
	one.set_stage(one.index_of(10, 10), 1)
	one.natural[one.index_of(10, 10)] = 1
	var gs: GrowthSim = GrowthSim.new(one, tun)
	var t_manual: int = 0
	var t_nat: int = 0
	for t: int in range(1, 200):
		gs.tick()
		if t_manual == 0 and one.stage[one.index_of(5, 5)] == 4:
			t_manual = t
		if t_nat == 0 and one.stage[one.index_of(10, 10)] == 4:
			t_nat = t
	rec("front.growth_multiplier", "dry manual seed matures in 120 growth ticks (60 s); natural seed in 40 (20 s) = natural_growth_multiplier 3", t_manual == 120 and t_nat == 40, "manual %d ticks natural %d ticks" % [t_manual, t_nat])
	d.free()
	dm.free()
	d2.free()

# ------------------------------------------------------------------------------------------ 7 save round trip and dt independence

class Rig:
	var world: WorldState
	var clock: SimClock = SimClock.new()
	var growth: GrowthSim
	var spread: SpreadSim
	func _init(w: WorldState, t: SimTuning, restore: Dictionary = {}) -> void:
		world = w
		clock.configure(t)
		growth = GrowthSim.new(w, t)
		spread = SpreadSim.new(w, t, restore.is_empty())
		if not restore.is_empty():
			clock.load_dict(restore["clock"])
			var ok_g: bool = growth.load_dict(restore["growth"])
			var ok_s: bool = spread.load_dict(restore["spread"])
			print("RESTORE growth=%s spread=%s" % [ok_g, ok_s])
		clock.growth_ticked.connect(func(_i: int) -> void: growth.tick())
		clock.spread_ticked.connect(func(_i: int) -> void: spread.tick())
	func save() -> String:
		return JSON.stringify({"world": world.to_dict(), "clock": clock.to_dict(), "growth": growth.to_dict(), "spread": spread.to_dict()})

func rig_hash(r: Rig) -> String:
	return "%s/q%d/%d/%d" % [world_hash(r.world), r.spread.queue_size(), hash(r.spread.mature_near), r.spread.total_planted]

func t_save() -> void:
	var s: WorldState = make_world(160, 60)
	for x: int in range(100, 104):
		for y: int in 60:
			s.terrain[s.index_of(x, y)] = W_WATER
	finish(s)
	for y: int in range(25, 35):
		for x: int in range(2, 8):
			s.set_stage(s.index_of(x, y), 4)
	for k: int in 12:
		s.set_stage(s.index_of(60 + k * 3, 10 + k), 1)
		s.set_moisture(s.index_of(60 + k * 3, 10 + k), 50)
	var a: Rig = Rig.new(s, tun)
	for i: int in 4 * 137:
		a.clock.advance(0.25)
	var blob: String = a.save()
	var parsed: Dictionary = JSON.parse_string(blob)
	var w2: WorldState = WorldState.from_dict(parsed["world"], region_def.terrains)
	var b: Rig = Rig.new(w2, tun, parsed)
	rec("save.restore_equal", "restored state equals the saved one (world, queue, mature_near, tick counts)", rig_hash(a) == rig_hash(b) and b.clock.growth_ticks == a.clock.growth_ticks and b.clock.spread_ticks == a.clock.spread_ticks and w2.counters_consistent(), "A %s | B %s" % [rig_hash(a), rig_hash(b)])
	var ok_all: bool = true
	var detail: String = ""
	for chunk: int in 6:
		for i: int in 4 * 41 + chunk:
			a.clock.advance(0.25)
			b.clock.advance(0.25)
		if rig_hash(a) != rig_hash(b):
			ok_all = false
			detail += " chunk%d" % chunk
	rec("save.same_after_advance", "after save->JSON->load, advancing both by the same time (6 chunks, ~250 s) keeps them identical", ok_all, "diverged:%s hashA=%s hashB=%s" % [detail, rig_hash(a), rig_hash(b)])
	rec("save.counters", "restored world counters consistent after the advance", b.world.counters_consistent() and a.world.counters_consistent() and b.world.greened_count == a.world.greened_count, "greened a=%d b=%d" % [a.world.greened_count, b.world.greened_count])

func t_dt() -> void:
	var hashes: Dictionary = {}
	for hz: int in [30, 60, 144]:
		var s: WorldState = make_world(100, 40)
		finish(s)
		for y: int in range(10, 30):
			for x: int in range(2, 6):
				s.set_stage(s.index_of(x, y), 4)
		var r: Rig = Rig.new(s, tun)
		var dt: float = 1.0 / float(hz)
		for i: int in hz * 200:
			r.clock.advance(dt)
		hashes[hz] = "%s ticks=%d/%d" % [rig_hash(r), r.clock.growth_ticks, r.clock.spread_ticks]
	rec("dt.rates_equal", "200 s of game time advanced in 1/30, 1/60, 1/144 s steps gives the same world, queue and tick counts", hashes[30] == hashes[60] and hashes[60] == hashes[144], str(hashes))

# ------------------------------------------------------------------------------------------ 8 performance

func perf_once(times: Array[float], parts: Array, info: Dictionary) -> void:
	var s: WorldState = make_world(512, 512)
	finish(s)
	for y: int in 256:
		for x: int in 512:
			s.set_stage(s.index_of(x, y), 1 + (x + y) % 3)
			s.fertility[s.index_of(x, y)] = (x * 7 + y * 3) % 101
	for y: int in range(256, 512):
		for x: int in 512:
			if x % 3 == 0 and y % 3 == 0:
				s.set_stage(s.index_of(x, y), 4)
	var d: SimulationDriver = driver_for(s, tun)
	var view: RegionView = RegionView.new()
	view.setup(s, tun)
	var worst_parts: Array = parts
	for frame: int in 60:
		var t0: int = Time.get_ticks_usec()
		d.growth.tick()
		var t1: int = Time.get_ticks_usec()
		d.spread.tick()
		var t2: int = Time.get_ticks_usec()
		view.flush(tun.render_tiles_per_frame)
		var t3: int = Time.get_ticks_usec()
		var total: float = float(t3 - t0) / 1000.0
		times.append(total)
		if frame > 5 and (worst_parts.is_empty() or total > float(worst_parts[0])):
			worst_parts = [total, float(t1 - t0) / 1000.0, float(t2 - t1) / 1000.0, float(t3 - t2) / 1000.0, view.last_flush_tiles, view.last_flush_blocks]
		if s.dirty_tiles.size() < tun.render_tiles_per_frame:
			s.mark_all_dirty()
	parts.assign(worst_parts)
	info["active_end"] = s.active_tiles.size()
	info["queue_end"] = d.spread.queue_size()
	info["growing_end"] = count_stage(s, 1) + count_stage(s, 2) + count_stage(s, 3)
	view.free()
	d.free()

func t_perf() -> void:
	var times: Array[float] = []
	var parts: Array = []
	var infos: Array = []
	for rep: int in 4:
		var info: Dictionary = {}
		perf_once(times, parts, info)
		infos.append(info)
	var sorted: Array[float] = times.duplicate()
	sorted.sort()
	var med: float = sorted[sorted.size() / 2]
	var mx: float = sorted[sorted.size() - 1]
	var p99: float = sorted[int(sorted.size() * 0.99)]
	observations["perf"] = {"median_ms": med, "p99_ms": p99, "max_ms": mx, "worst_parts_ms[total,growth,spread,flush,tiles,blocks]": parts, "end_state": infos}
	rec("perf.worst_frame", "worst case (131k growing tiles = half the map, ~130k candidates, dirty budget full, growth+spread+flush in the SAME frame, 4 x 60 frames, headless CPU only; end of each run still has half the map growing): median and max total < 16 ms", med < 16.0 and mx < 16.0, "median %.2f ms, p99 %.2f, max %.2f ms, worst frame parts %s, end states %s" % [med, p99, mx, str(parts), str(infos)])

# ------------------------------------------------------------------------------------------ 9 region_01 reach

func t_region() -> void:
	var s: WorldState = RegionLoader.load_region(region_def)
	var starts: Array = []
	for i: int in s.tile_count():
		if s.stage[i] == 4:
			starts.append(i)
	var depth: Dictionary = bfs_depths(s, starts)
	var reach_total: int = depth.size()
	var reach_new: int = reach_total - starts.size()
	var targets: int = s.target_count
	var unreached: Dictionary = {}
	for i: int in s.tile_count():
		if s.target[i] == 1 and not depth.has(i):
			unreached[i] = true
	var comp: Dictionary = {}
	var comps: Array = []
	var offs: Array[Vector2i] = offsets_r2()
	for i: int in unreached:
		if comp.has(i):
			continue
		var cid: int = comps.size()
		var members: Array = [i]
		comp[i] = cid
		var qi: int = 0
		while qi < members.size():
			var cur: int = members[qi]
			qi += 1
			for o: Vector2i in offs:
				var nx: int = cur % s.width + o.x
				var ny: int = cur / s.width + o.y
				if nx < 0 or ny < 0 or nx >= s.width or ny >= s.height:
					continue
				var j: int = ny * s.width + nx
				if unreached.has(j) and not comp.has(j) and s.terrain_defs[s.terrain[j]].plantable:
					comp[j] = cid
					members.append(j)
		comps.append(members)
	var near_by_k: Dictionary = {}
	for c: int in comps.size():
		var found_k: int = -1
		var members: Array = comps[c]
		for k: int in range(3, 12):
			var hit: bool = false
			for i: int in members:
				var x: int = i % s.width
				var y: int = i / s.width
				for dy: int in range(-k, k + 1):
					for dx: int in range(-k, k + 1):
						var nx: int = x + dx
						var ny: int = y + dy
						if nx >= 0 and ny >= 0 and nx < s.width and ny < s.height and depth.has(ny * s.width + nx):
							hit = true
							break
					if hit:
						break
				if hit:
					break
			if hit:
				found_k = k
				break
		near_by_k[c] = found_k
	var sizes: Array = []
	for c: int in comps.size():
		sizes.append([(comps[c] as Array).size(), int(near_by_k[c])])
	sizes.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var top: Array = sizes.slice(0, 12)
	var river_side: int = 0
	var closed: int = 0
	for e: Array in sizes:
		if int(e[1]) > 0:
			river_side += int(e[0])
		else:
			closed += int(e[0])
	observations["region_reach"] = {"targets": targets, "initially_mature": starts.size(), "reachable_incl_start": reach_total, "reachable_excl_start": reach_new, "unreached": unreached.size(), "components": comps.size(), "top_components_[size,bridged_at_chebyshev_k_or_-1]": top, "unreached_bridgeable_by_gap_3_to_11": river_side, "unreached_closed_islands": closed}
	print("REGION ", JSON.stringify(observations["region_reach"]))
	rec("region.reach_count", "my BFS from the initial mature (safe zone) tiles, radius 2 over plantable targets, reaches 125,670 targets (implementer's figure; incl. or excl. the start tiles)", reach_total == 125670 or reach_new == 125670, "reach incl start=%d excl start=%d (start tiles=%d) unreached=%d targets=%d" % [reach_total, reach_new, starts.size(), unreached.size(), targets])
	rec("region.isolated_count", "unreached targets = 119,176 (implementer's figure)", unreached.size() == 119176 or targets - reach_total == 119176, "unreached=%d, targets-reach=%d" % [unreached.size(), targets - reach_total])
	var d: SimulationDriver = driver_for(s, tun)
	var green_bad: int = 0
	var t0: int = Time.get_ticks_msec()
	for sec: int in 900:
		run_seconds(d, 1.0)
		if sec % 100 == 99:
			if s.greened_count != recount_green(s) or not s.counters_consistent():
				green_bad += 1
	var wall_per_s: float = float(Time.get_ticks_msec() - t0) / 900.0
	var new_planted: int = 0
	var bad_outside: int = 0
	for i: int in s.tile_count():
		if s.natural[i] == 1:
			new_planted += 1
			if not depth.has(i):
				bad_outside += 1
	rec("region.sim_900s", "900 s of natural spread on region_01 from the safe zone: natural tiles only in the reachable set, counters match recount every 100 s", bad_outside == 0 and green_bad == 0 and new_planted > 100, "natural tiles=%d outside reachable=%d counter mismatches=%d greened=%d (%.2f%%) wall %.2f ms per game second" % [new_planted, bad_outside, green_bad, s.greened_count, 100.0 * s.greened_count / s.target_count, wall_per_s])
	d.free()
