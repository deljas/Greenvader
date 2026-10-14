extends SceneTree
## P1-04 headless checks: natural spread, bounded per-tick work (spread B, growth G), split-growth correctness,
## greening counters, frame-rate independence, pause, save round trip, isolated land, region_01 front measurement,
## performance of the whole frame.
## Run: Godot --headless --path <project> --script res://tests/p1/p1_04_checks.gd
## Expected values come from the ticket / parent design and from brute-force recounts written here:
##   candidates = empty plantable tiles within 2 tiles (Euclidean) of a mature tile; targets only; no occupied tiles;
##   a hook refusal blocks planting; every connected target tile is reached within the bound computed from the
##   settings; a tile's growth over `n` ticks equals what `n` single ticks add (oracle loop in this file).

const REGION_PATH: String = "res://data/region_01.tres"
const OUT: String = "res://evidence/p1/p1-04/"
const RADIUS: float = 2.0

var failures: int = 0
var checks: int = 0
var region_def: RegionDef
var sim_tuning: SimTuning
var perf: Dictionary = {}
var info: Dictionary = {}

class Rig:
	extends RefCounted
	var clock: SimClock = SimClock.new()
	var growth: GrowthSim
	var spread: SpreadSim

	func _init(world: WorldState, tuning: SimTuning, sync: bool = true) -> void:
		clock.configure(tuning)
		growth = GrowthSim.new(world, tuning)
		spread = SpreadSim.new(world, tuning, sync)
		clock.growth_ticked.connect(func(_index: int) -> void: growth.tick())
		clock.spread_ticked.connect(func(_index: int) -> void: spread.tick())

	func step_second() -> void:
		for i: int in 4:
			clock.advance(0.25)

	func run(seconds: float, hz: int) -> void:
		for i: int in roundi(seconds * hz):
			clock.advance(1.0 / hz)

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", message])

func run() -> void:
	region_def = load(REGION_PATH) as RegionDef
	sim_tuning = load("res://data/sim_tuning.tres") as SimTuning
	check(region_def != null and sim_tuning != null, "region and sim tuning load")
	test_tuning_values()
	test_candidate_selection()
	test_fairness_and_limits()
	test_reach_bound_random_map()
	test_isolated_land()
	test_growth_split()
	test_counters()
	test_frame_rate_pause()
	test_save_round_trip()
	test_front_speed()
	test_region_01()
	test_performance()
	await test_scene_flow()
	print("PERF " + JSON.stringify(perf))
	print("INFO " + JSON.stringify(info))
	print("P1_04_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

# ---- helpers ------------------------------------------------------------------------------

func c8(color: Color) -> Vector3i:
	return Vector3i(roundi(color.r * 255.0), roundi(color.g * 255.0), roundi(color.b * 255.0))

func terrain_id(key: StringName) -> int:
	for def: TerrainDef in region_def.terrains:
		if def.key == key:
			return def.id
	return -1

func state_from_rows(rows: Array) -> WorldState:
	var def: RegionDef = RegionDef.new()
	def.width_tiles = String(rows[0]).length()
	def.height_tiles = rows.size()
	def.terrains = region_def.terrains
	def.sprout_seed = region_def.sprout_seed
	var image: Image = Image.create(def.width_tiles, def.height_tiles, false, Image.FORMAT_RGB8)
	var glyphs: Dictionary = {".": &"wasteland", "s": &"safe", ":": &"shore", "~": &"water", "#": &"building"}
	for y: int in rows.size():
		for x: int in String(rows[y]).length():
			var v: Vector3i = c8(region_def.terrains[terrain_id(glyphs[String(rows[y])[x]])].map_color)
			image.set_pixel(x, y, Color8(v.x, v.y, v.z))
	return RegionLoader.build_state(def, image)

func rows_of(width: int, height: int, fill: String = ".") -> Array:
	var rows: Array = []
	for y: int in height:
		rows.append(fill.repeat(width))
	return rows

func put(rows: Array, x: int, y: int, glyph: String) -> void:
	var line: String = rows[y]
	rows[y] = line.substr(0, x) + glyph + line.substr(x + 1)

func blank(width: int, height: int) -> WorldState:
	return state_from_rows(rows_of(width, height))

func fill_mature(state: WorldState, rect: Rect2i) -> void:
	state.debug_fill_stage(rect, WorldState.STAGE_MATURE)

func count_natural(state: WorldState) -> int:
	var total: int = 0
	for index: int in state.tile_count():
		total += state.natural[index]
	return total

func within_radius(state: WorldState, a: int, b: int) -> bool:
	var dx: int = a % state.width - b % state.width
	var dy: int = a / state.width - b / state.width
	return float(dx * dx + dy * dy) <= RADIUS * RADIUS + 1.0e-6

## Independent reachability: breadth-first search over plantable target tiles, step = any tile within RADIUS of the
## previous one. Returns a Dictionary tile -> hop depth (initial mature tiles = 0). Walks a window around each tile.
func reach_depths(state: WorldState, sources: Array[int]) -> Dictionary:
	var depth: Dictionary = {}
	var frontier: Array[int] = []
	for index: int in sources:
		depth[index] = 0
		frontier.append(index)
	var head: int = 0
	while head < frontier.size():
		var current: int = frontier[head]
		head += 1
		var cx: int = current % state.width
		var cy: int = current / state.width
		for dy: int in range(-2, 3):
			for dx: int in range(-2, 3):
				if dx * dx + dy * dy > 4 or (dx == 0 and dy == 0):
					continue
				var x: int = cx + dx
				var y: int = cy + dy
				if not state.in_bounds(x, y):
					continue
				var other: int = state.index_of(x, y)
				if depth.has(other) or state.target[other] == 0 or not state.terrain_defs[state.terrain[other]].plantable:
					continue
				depth[other] = int(depth[current]) + 1
				frontier.append(other)
	return depth

func percentile(values: Array[float], q: float) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[clampi(int(float(sorted.size() - 1) * q), 0, sorted.size() - 1)]

func dump(state: WorldState, rig: Rig) -> String:
	return JSON.stringify([state.to_dict(), rig.growth.to_dict(), rig.spread.to_dict()])

# ---- tuning ----------------------------------------------------------------------------------

func test_tuning_values() -> void:
	var t: SimTuning = sim_tuning
	check(t.spread_tick_seconds == 1.0 and t.growth_tick_seconds == 0.5, "tuning: spread tick 1.0 s, growth tick 0.5 s")
	check(t.max_growth_tiles_per_tick == 3000 and t.spread_candidates_per_tick == 1500, "tuning: growth limit G = 3000 and spread limit B = 1500 tiles per tick (lowered from the 4000 / 2000 proposal to meet the 16 ms frame target)")
	check(t.spread_radius_tiles == 2.0 and t.natural_growth_multiplier == 3.0, "tuning: spread radius 2 tiles, natural growth multiplier 3")
	check(t.spread_progress_per_tick > 0 and t.spread_progress_threshold > t.spread_progress_per_tick and t.spread_mature_events_per_tick > 0, "tuning: spread progress has a positive rate, a threshold above one tick and an event limit")

# ---- selection --------------------------------------------------------------------------------

func test_candidate_selection() -> void:
	var rows: Array = rows_of(24, 15)
	put(rows, 13, 6, "~")
	put(rows, 12, 7, "#")
	var state: WorldState = state_from_rows(rows)
	fill_mature(state, Rect2i(10, 6, 2, 2))
	var mature_before: Array[int] = []
	for index: int in state.tile_count():
		if state.stage[index] == WorldState.STAGE_MATURE:
			mature_before.append(index)
	check(mature_before.size() == 4, "selection map: four mature tiles")
	# Occupied tile, hook-refused tile, manually planted seed.
	check(state.occupy(Rect2i(9, 5, 1, 1), 7), "selection map: one tile occupied by a big plant")
	var occupied: int = state.index_of(9, 5)
	var denied_tile: int = state.index_of(10, 9)
	var manual: int = state.index_of(12, 6)
	state.set_stage(manual, WorldState.STAGE_SEED)
	var tuning: SimTuning = sim_tuning
	var rig: Rig = Rig.new(state, tuning)
	var hook_log: Array[int] = []
	rig.spread.allow_hook = func(index: int) -> bool:
		hook_log.append(index)
		return index != denied_tile
	# Expected set by brute force: target, plantable terrain, empty, unoccupied, not refused, within 2 tiles of mature.
	var expected: Dictionary = {}
	for index: int in state.tile_count():
		if state.target[index] == 1 and state.stage[index] == WorldState.STAGE_EMPTY and state.occupant[index] == 0 and index != denied_tile:
			for m: int in mature_before:
				if within_radius(state, index, m):
					expected[index] = true
					break
	check(expected.size() > 12, "selection map: %d tiles are expected to be planted" % expected.size())
	check(expected.has(state.index_of(8, 6)) and not expected.has(state.index_of(7, 6)), "selection map: the tile 2 tiles from the mature block is a candidate, 3 tiles away is not")
	check(rig.spread.queue_size() == expected.size() + 1, "candidate queue holds exactly the in-range empty plantable free tiles at start (%d = %d expected + the hook-refused one)" % [rig.spread.queue_size(), expected.size()])
	rig.run(12.0, 60)
	var planted: Dictionary = {}
	for index: int in state.tile_count():
		if state.natural[index] == 1:
			planted[index] = true
	var same: bool = planted.size() == expected.size()
	for index: int in expected:
		same = same and planted.has(index)
	check(same, "after one hop exactly the expected %d tiles were planted by spread (%d)" % [expected.size(), planted.size()])
	var all_seeds: bool = true
	for index: int in planted:
		all_seeds = all_seeds and state.stage[index] >= WorldState.STAGE_SEED and state.stage[index] <= WorldState.STAGE_SPROUT1
	check(all_seeds, "planted tiles are seeds (or just sprouting), not mature")
	check(state.stage[state.index_of(13, 6)] == WorldState.STAGE_EMPTY and state.stage[state.index_of(12, 7)] == WorldState.STAGE_EMPTY, "water and building tiles in range are not planted")
	check(state.stage[occupied] == WorldState.STAGE_EMPTY and state.stage[denied_tile] == WorldState.STAGE_EMPTY, "the occupied tile and the hook-refused tile are not planted")
	check(state.natural[manual] == 0 and state.stage[manual] >= WorldState.STAGE_SEED, "a manually planted seed is left alone and is not marked natural")
	check(hook_log.has(denied_tile) and not hook_log.has(state.index_of(7, 6)), "the hook was asked about the refused candidate but not about out-of-range tiles")
	rig.run(12.0, 60)
	check(state.stage[denied_tile] == WorldState.STAGE_EMPTY, "the refused tile stays empty as long as the hook refuses")
	rig.spread.allow_hook = Callable()
	rig.run(13.0, 60)
	check(state.natural[denied_tile] == 1, "once the hook allows it (empty Callable = always allowed) the tile is planted by itself")
	check(state.counters_consistent(), "counters consistent after the selection run")
	# Occupancy release makes a tile a candidate again.
	state.release(7)
	rig.run(15.0, 60)
	check(state.natural[occupied] == 1, "a tile freed from its occupant is planted by spread")

# ---- fairness and limits ------------------------------------------------------------------------

func test_fairness_and_limits() -> void:
	var state: WorldState = blank(30, 30)
	fill_mature(state, Rect2i(12, 12, 6, 6))
	var tuning: SimTuning = sim_tuning.duplicate() as SimTuning
	tuning.spread_candidates_per_tick = 7
	var rig: Rig = Rig.new(state, tuning)
	rig.spread.allow_hook = func(_index: int) -> bool: return false
	var q: int = rig.spread.queue_size()
	check(q > 40, "fairness map: %d candidates, B = 7" % q)
	var bound: int = rig.spread.visit_interval_bound(q)
	check(bound == (q + 6) / 7, "visit interval bound = ceil(Q / B) = %d ticks" % bound)
	var max_gap: int = 0
	var examined_ok: bool = true
	for tick: int in 60:
		var before: int = rig.spread.queue_size()
		rig.spread.tick()
		examined_ok = examined_ok and rig.spread.last_examined == mini(7, before)
		for index: int in state.tile_count():
			if rig.spread.queued_flag[index] == 1:
				max_gap = maxi(max_gap, rig.spread.ticks - rig.spread.last_visit[index])
	check(examined_ok, "every spread tick examined exactly min(B, queue size) candidates (limit B = 7)")
	check(max_gap <= bound, "no candidate waited more than ceil(Q/B) = %d ticks between visits (worst gap %d)" % [bound, max_gap])
	check(rig.spread.queue_size() == q and count_natural(state) == 0, "refusing hook: queue unchanged and nothing planted")
	rig.spread.allow_hook = Callable()
	var allowed_at: int = rig.spread.ticks
	var delay_bound: int = rig.spread.seed_delay_bound(q, 0)
	var done_at: int = -1
	var limit_ok: bool = true
	for tick: int in delay_bound + 5:
		var before: int = rig.spread.queue_size()
		rig.spread.tick()
		limit_ok = limit_ok and rig.spread.last_examined <= 7 and rig.spread.last_examined == mini(7, before)
		if done_at < 0 and rig.spread.queue_size() == 0:
			done_at = rig.spread.ticks - allowed_at
	check(limit_ok, "examination limit B held while planting")
	check(done_at > 0 and done_at <= delay_bound, "all %d candidates became seeds within the computed bound (%d ticks <= %d = events + progress + ceil(Q/B))" % [q, done_at, delay_bound])
	check(count_natural(state) == q, "every candidate was planted exactly once (%d)" % count_natural(state))
	# Mature-event limit P.
	var many: WorldState = blank(60, 60)
	var tuning_p: SimTuning = sim_tuning.duplicate() as SimTuning
	tuning_p.spread_mature_events_per_tick = 25
	var rig_p: Rig = Rig.new(many, tuning_p)
	fill_mature(many, Rect2i(10, 10, 20, 20))
	var events_ok: bool = true
	var pending_start: int = rig_p.spread.pending_size()
	for tick: int in 30:
		rig_p.spread.tick()
		events_ok = events_ok and rig_p.spread.last_events <= 25
	check(pending_start == 400 and events_ok and rig_p.spread.pending_size() == 0, "mature events: 400 new mature tiles applied at most 25 per tick (all applied after 16 ticks)")
	# Growth limit G.
	var grow_state: WorldState = blank(100, 100)
	var tuning_g: SimTuning = sim_tuning.duplicate() as SimTuning
	tuning_g.max_growth_tiles_per_tick = 300
	var grow: GrowthSim = GrowthSim.new(grow_state, tuning_g)
	for index: int in grow_state.tile_count():
		grow_state.set_stage(index, WorldState.STAGE_SEED)
	var g_ok: bool = true
	var visited_total: int = 0
	for tick: int in 34:
		grow.tick()
		g_ok = g_ok and grow.last_visited <= 300
		visited_total += grow.last_visited
	check(g_ok and visited_total == 10000, "growth tick visits at most G = 300 of 10,000 active tiles, and one sweep covers each exactly once (visited %d in 34 ticks)" % visited_total)
	check(grow.sweep_ticks() == 34, "sweep length = ceil(10,000 / 300) = 34 ticks")

# ---- reach bound on a fixed random map ----------------------------------------------------------------

func random_map_rows(seed_value: int, width: int, height: int, blocked_share: float) -> Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var rows: Array = rows_of(width, height)
	for y: int in height:
		for x: int in width:
			var roll: float = rng.randf()
			if roll < blocked_share * 0.5:
				put(rows, x, y, "~")
			elif roll < blocked_share:
				put(rows, x, y, "#")
	# A walled-in pocket: land 30..37 enclosed by a ring of water 2 tiles thick (3 apart across it = out of reach).
	for y: int in range(28, 40):
		for x: int in range(28, 40):
			put(rows, x, y, "." if x >= 30 and x < 38 and y >= 30 and y < 38 else "~")
	for y: int in range(1, 4):
		for x: int in range(1, 4):
			put(rows, x, y, "s")
	return rows

func test_reach_bound_random_map() -> void:
	var state: WorldState = state_from_rows(random_map_rows(20261015, 40, 40, 0.34))
	var sources: Array[int] = []
	for index: int in state.tile_count():
		if state.stage[index] == WorldState.STAGE_MATURE:
			sources.append(index)
	var depths: Dictionary = reach_depths(state, sources)
	var max_depth: int = 0
	var unreachable: int = 0
	for index: int in state.tile_count():
		if state.target[index] == 1 and state.terrain_defs[state.terrain[index]].plantable:
			if depths.has(index):
				max_depth = maxi(max_depth, int(depths[index]))
			else:
				unreachable += 1
	check(sources.size() == 9 and max_depth >= 8 and unreachable > 0, "random map (seed 20261015): %d start tiles, %d reachable target tiles, deepest %d hops, %d unreachable pockets" % [sources.size(), depths.size() - sources.size(), max_depth, unreachable])
	var rig: Rig = Rig.new(state, sim_tuning)
	var q_all: int = state.target_count
	var hop: int = rig.spread.hop_bound(q_all, q_all, q_all)
	var bound_ticks: int = max_depth * hop
	var first_seen: Dictionary = {}
	for second: int in bound_ticks:
		rig.step_second()
		for index: int in depths:
			if not first_seen.has(index) and state.stage[index] != WorldState.STAGE_EMPTY:
				first_seen[index] = second + 1
	var late: int = 0
	var missed: int = 0
	var worst_ratio: float = 0.0
	for index: int in depths:
		if int(depths[index]) == 0:
			continue
		if not first_seen.has(index):
			missed += 1
		else:
			var allowed: int = int(depths[index]) * hop
			if int(first_seen[index]) > allowed:
				late += 1
			worst_ratio = maxf(worst_ratio, float(first_seen[index]) / float(allowed))
	check(missed == 0, "every connected target tile (%d) was reached within the computed bound of %d ticks (%d hops x %d ticks per hop)" % [depths.size() - sources.size(), bound_ticks, max_depth, hop])
	check(late == 0, "every tile was reached no later than depth x per-hop bound (worst used %.0f%% of its bound)" % (worst_ratio * 100.0))
	var stray: int = 0
	for index: int in state.tile_count():
		if not depths.has(index) and state.stage[index] != WorldState.STAGE_EMPTY:
			stray += 1
	check(stray == 0, "tiles outside the connected area (unreachable pockets, water, buildings) were never planted")
	info["random_map_bound_ticks"] = bound_ticks
	info["random_map_max_depth"] = max_depth
	info["random_map_hop_bound_ticks"] = hop
	info["random_map_worst_ratio"] = snappedf(worst_ratio, 0.01)
	check(state.counters_consistent(), "random map: counters consistent after the run")

# ---- isolated land ---------------------------------------------------------------------------------

func test_isolated_land() -> void:
	# A water gap 1 tile wide is crossed (tiles 2 apart lie within the radius 2), 2 tiles wide is not (3 apart).
	for gap: int in [1, 2]:
		var rows: Array = rows_of(32, 7)
		for y: int in 7:
			for g: int in gap:
				put(rows, 12 + g, y, "~")
		var state: WorldState = state_from_rows(rows)
		fill_mature(state, Rect2i(0, 0, 2, 7))
		var rig: Rig = Rig.new(state, sim_tuning)
		var sources: Array[int] = []
		for index: int in state.tile_count():
			if state.stage[index] == WorldState.STAGE_MATURE:
				sources.append(index)
		var depths: Dictionary = reach_depths(state, sources)
		var max_depth: int = 0
		for index: int in depths:
			max_depth = maxi(max_depth, int(depths[index]))
		var time_needed: int = (max_depth + 2) * rig.spread.hop_bound(224, 224, 224)
		for second: int in time_needed:
			rig.step_second()
		var near_total: int = 0
		var near_planted: int = 0
		var far_planted: int = 0
		var far_total: int = 0
		for index: int in state.tile_count():
			var x: int = index % 32
			if state.target[index] == 0:
				continue
			if x < 12:
				near_total += 1
				if state.stage[index] != WorldState.STAGE_EMPTY:
					near_planted += 1
			elif x >= 12 + gap:
				far_total += 1
				if state.stage[index] != WorldState.STAGE_EMPTY:
					far_planted += 1
		if gap == 1:
			check(depths.size() == near_total + far_total and far_planted == far_total, "gap of 1 water tile: the far side is reached by spread (%d of %d tiles green)" % [far_planted, far_total])
		else:
			check(near_planted == near_total and far_planted == 0 and depths.size() == near_total, "gap of 2 water tiles: the near side is fully green (%d/%d) and the far side stays empty (%d of %d) after %d s" % [near_planted, near_total, far_planted, far_total, time_needed])
		check(state.counters_consistent() and state.greened_count <= state.target_count, "isolated-land map (gap %d): counters consistent" % gap)

# ---- growth split ----------------------------------------------------------------------------------

## Scalar oracle written from the spec: tick at which a seed with the given start moisture is mature, no fertility,
## growth per tick = round(1000 * (1 + moisture / 100)), moisture falls 1 per tick, mature at 120000.
func oracle_mature_tick(moisture: int) -> int:
	var growth_value: int = 0
	var m: int = moisture
	var tick: int = 0
	while growth_value < 120000:
		growth_value += maxi(roundi(1000.0 * (1.0 + float(m) / 100.0)), 1)
		m = maxi(m - 1, 0)
		tick += 1
	return tick

func seeded_world(width: int, height: int) -> WorldState:
	var state: WorldState = blank(width, height)
	for y: int in height:
		for x: int in width:
			var index: int = state.index_of(x, y)
			state.set_stage(index, WorldState.STAGE_SEED)
			state.set_moisture(index, (x * 7 + y * 3) % 101)
	return state

func test_growth_split() -> void:
	var unlimited: SimTuning = sim_tuning.duplicate() as SimTuning
	unlimited.max_growth_tiles_per_tick = 0
	var split_tuning: SimTuning = sim_tuning.duplicate() as SimTuning
	split_tuning.max_growth_tiles_per_tick = 500
	var whole: WorldState = seeded_world(60, 60)
	var split: WorldState = seeded_world(60, 60)
	var whole_growth: GrowthSim = GrowthSim.new(whole, unlimited)
	var split_growth: GrowthSim = GrowthSim.new(split, split_tuning)
	var whole_mature: PackedInt32Array = PackedInt32Array()
	var split_mature: PackedInt32Array = PackedInt32Array()
	whole_mature.resize(3600)
	split_mature.resize(3600)
	var max_sweep: int = 0
	var never_ahead: bool = true
	var at_100_equal: bool = false
	for tick: int in range(1, 161):
		max_sweep = maxi(max_sweep, split_growth.sweep_ticks())
		whole_growth.tick()
		split_growth.tick()
		for index: int in 3600:
			if whole_mature[index] == 0 and whole.stage[index] == WorldState.STAGE_MATURE:
				whole_mature[index] = tick
			if split_mature[index] == 0 and split.stage[index] == WorldState.STAGE_MATURE:
				split_mature[index] = tick
			never_ahead = never_ahead and split.growth[index] <= whole.growth[index]
		if tick == 100:
			split_growth.catch_up()
			at_100_equal = split.stage == whole.stage and split.growth == whole.growth and split.moisture == whole.moisture and split.greened_count == whole.greened_count and split.mature_count == whole.mature_count
			for index: int in 3600:
				if split_mature[index] == 0 and split.stage[index] == WorldState.STAGE_MATURE:
					split_mature[index] = tick
	check(max_sweep == 8, "split map: 3,600 active tiles with G = 500 are swept in 8 ticks (%d)" % max_sweep)
	var oracle_ok: bool = true
	var in_window: bool = true
	var worst_delay: int = 0
	for index: int in 3600:
		var m: int = ((index % 60) * 7 + (index / 60) * 3) % 101
		var expected: int = oracle_mature_tick(m)
		oracle_ok = oracle_ok and int(whole_mature[index]) == expected
		var delay: int = int(split_mature[index]) - expected
		worst_delay = maxi(worst_delay, delay)
		in_window = in_window and delay >= 0 and delay <= max_sweep
	check(oracle_ok, "unsplit growth matures every tile exactly at the tick the spec oracle gives (wet tiles 60..120 ticks)")
	check(in_window, "split growth: every tile matures no earlier than unsplit and at most one sweep (%d ticks) later (worst delay %d)" % [max_sweep, worst_delay])
	check(never_ahead, "split growth is never ahead of unsplit growth")
	check(at_100_equal, "after catch_up the split world equals the unsplit world exactly (stage, growth, moisture, counters at tick 100)")
	check(split.counters_consistent() and whole.counters_consistent() and split.mature_count == 3600, "split run ends with all tiles mature and consistent counters (%d)" % split.mature_count)
	# Set within the limit behaves exactly like before.
	var small_a: WorldState = seeded_world(30, 30)
	var small_b: WorldState = seeded_world(30, 30)
	var default_growth: GrowthSim = GrowthSim.new(small_a, sim_tuning)
	var unlimited_growth: GrowthSim = GrowthSim.new(small_b, unlimited)
	var identical: bool = true
	for tick: int in 140:
		default_growth.tick()
		unlimited_growth.tick()
		identical = identical and small_a.stage == small_b.stage and small_a.growth == small_b.growth and small_a.moisture == small_b.moisture and small_a.active_tiles == small_b.active_tiles and default_growth.last_visited == unlimited_growth.last_visited
	check(identical, "an active set within G behaves exactly like the unlimited tick (140 ticks, same arrays and order)")
	# Natural seeds grow faster by the multiplier, others do not.
	var mixed: WorldState = blank(8, 8)
	var natural_tile: int = mixed.index_of(2, 2)
	var player_tile: int = mixed.index_of(5, 5)
	mixed.set_stage(natural_tile, WorldState.STAGE_SEED)
	mixed.natural[natural_tile] = 1
	mixed.set_stage(player_tile, WorldState.STAGE_SEED)
	var mixed_growth: GrowthSim = GrowthSim.new(mixed, sim_tuning)
	for tick: int in 10:
		mixed_growth.tick()
	check(mixed.growth[natural_tile] == 3 * mixed.growth[player_tile] and mixed.growth[player_tile] == 10000, "natural seed grows 3x as fast as a player seed (%d vs %d after 10 ticks)" % [mixed.growth[natural_tile], mixed.growth[player_tile]])
	for tick: int in 30:
		mixed_growth.tick()
	check(mixed.stage[natural_tile] == WorldState.STAGE_MATURE and mixed.stage[player_tile] != WorldState.STAGE_MATURE, "natural seed is mature after 40 ticks = 20 s (dry), the player seed is not")
	mixed.set_stage(natural_tile, WorldState.STAGE_EMPTY)
	check(mixed.natural[natural_tile] == 0, "the natural mark is cleared when the tile becomes empty")

# ---- counters --------------------------------------------------------------------------------------

func test_counters() -> void:
	var state: WorldState = blank(48, 48)
	fill_mature(state, Rect2i(20, 20, 4, 4))
	var rig: Rig = Rig.new(state, sim_tuning)
	var ok: bool = true
	var greened_monotone: bool = true
	var last_greened: int = state.greened_count
	for second: int in 150:
		rig.step_second()
		if second % 5 == 0:
			ok = ok and state.counters_consistent() and state.recount_greened() == state.greened_count and state.recount_mature() == state.mature_count
		greened_monotone = greened_monotone and state.greened_count >= last_greened
		last_greened = state.greened_count
	check(ok, "counters (greened, mature, targets) equal a full recount every 5 s during 150 s of spreading")
	check(greened_monotone and state.greened_count > 16 and count_natural(state) > 0, "greening grew only upwards while spreading (%d greened, %d natural tiles)" % [state.greened_count, count_natural(state)])
	var percent: int = state.greening_percent_floor()
	check(state.greened_count * 100 / state.target_count == percent and not state.is_fully_greened(), "greening percent is the integer floor of greened / targets (%d %%)" % percent)
	# The listener-driven neighbour data matches a brute-force recount.
	rig.spread.tick()
	while rig.spread.pending_size() > 0:
		rig.spread.tick()
	var near_ok: bool = true
	for index: int in state.tile_count():
		var count: int = 0
		for other: int in state.tile_count():
			if other != index and state.stage[other] == WorldState.STAGE_MATURE and within_radius(state, index, other):
				count += 1
		near_ok = near_ok and rig.spread.mature_near[index] == count
		if not near_ok:
			break
	check(near_ok, "mature_near (incremental) equals a brute-force count of mature tiles within the radius for every tile")

# ---- frame rate, pause ----------------------------------------------------------------------------------

func frame_world() -> WorldState:
	var state: WorldState = blank(40, 40)
	fill_mature(state, Rect2i(18, 18, 3, 3))
	for i: int in 12:
		var index: int = state.index_of(4 + i * 3, 5 + (i % 4) * 7)
		state.set_stage(index, WorldState.STAGE_SEED)
		state.set_moisture(index, i * 8)
	return state

func test_frame_rate_pause() -> void:
	var tuning: SimTuning = sim_tuning.duplicate() as SimTuning
	tuning.max_growth_tiles_per_tick = 120
	tuning.spread_candidates_per_tick = 40
	var dumps: Array[String] = []
	var counts: Array[int] = []
	for hz: int in [30, 60, 144]:
		var state: WorldState = frame_world()
		var rig: Rig = Rig.new(state, tuning)
		rig.run(95.0, hz)
		dumps.append(dump(state, rig))
		counts.append(count_natural(state))
	check(counts[0] > 20 and counts[0] == counts[1] and counts[1] == counts[2], "30 / 60 / 144 Hz: same number of spread tiles after 95 s (%s)" % [counts])
	check(dumps[0] == dumps[1] and dumps[1] == dumps[2], "30 / 60 / 144 Hz: identical world, growth and spread state after 95 s")
	var state2: WorldState = frame_world()
	var rig2: Rig = Rig.new(state2, tuning)
	rig2.run(30.0, 60)
	var before: String = dump(state2, rig2)
	rig2.clock.paused = true
	rig2.run(40.0, 60)
	check(dump(state2, rig2) == before, "paused: 40 s of stepping changes neither growth nor spread nor the queue")
	var elapsed_paused: float = rig2.clock.elapsed
	rig2.clock.paused = false
	rig2.run(2.0 / 60.0, 60)
	check(absf(rig2.clock.elapsed - elapsed_paused - 2.0 / 60.0) < 1.0e-9, "after resuming only the two stepped frames of time were added")
	# Through the real driver node: the paused tree stops spread.
	var node_state: WorldState = frame_world()
	var driver: SimulationDriver = SimulationDriver.new()
	driver.setup(node_state, sim_tuning)
	check(driver.spread != null and driver.growth != null, "SimulationDriver owns the growth and the spread simulation")
	for i: int in 120:
		driver.clock.advance(0.25)
	check(driver.spread.ticks == 30 and driver.growth.ticks == 60, "driver: 30 s = 30 spread ticks and 60 growth ticks")
	driver.free()

# ---- save round trip ----------------------------------------------------------------------------------

func test_save_round_trip() -> void:
	var tuning: SimTuning = sim_tuning.duplicate() as SimTuning
	tuning.max_growth_tiles_per_tick = 20
	tuning.spread_candidates_per_tick = 8
	tuning.spread_mature_events_per_tick = 6
	var state: WorldState = blank(48, 48)
	fill_mature(state, Rect2i(20, 20, 4, 4))
	for i: int in 30:
		var index: int = state.index_of(2 + i, 3 + (i * 5) % 11)
		state.set_stage(index, WorldState.STAGE_SEED)
		state.set_moisture(index, (i * 13) % 101)
	var rig: Rig = Rig.new(state, tuning)
	rig.run(30.0, 60)
	var guard: int = 0
	while (rig.growth.cursor == 0 or rig.spread.pending_size() == 0) and guard < 400:
		rig.run(0.5, 60)
		guard += 1
	check(rig.growth.cursor > 0 and rig.growth.sweep_ticks() > 1, "save point is mid-sweep (growth cursor %d, sweep %d ticks)" % [rig.growth.cursor, rig.growth.sweep_ticks()])
	check(rig.spread.queue_size() > 8 and rig.spread.pending_size() > 0, "save point has a queue longer than B (%d candidates, %d pending events)" % [rig.spread.queue_size(), rig.spread.pending_size()])
	var world_data: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var growth_data: Dictionary = JSON.parse_string(JSON.stringify(rig.growth.to_dict()))
	var spread_data: Dictionary = JSON.parse_string(JSON.stringify(rig.spread.to_dict()))
	var clock_data: Dictionary = rig.clock.to_dict()
	var restored_state: WorldState = WorldState.from_dict(world_data, region_def.terrains)
	check(restored_state != null, "world state restores from its save data")
	var twin: Rig = Rig.new(restored_state, tuning, false)
	check(twin.growth.load_dict(growth_data) and twin.spread.load_dict(spread_data) and twin.clock.load_dict(clock_data), "growth, spread and clock restore")
	check(dump(restored_state, twin) == dump(state, rig), "right after restoring, the saved data equals the original (state, growth phase, queue, progress)")
	rig.run(45.0, 60)
	twin.run(45.0, 60)
	check(dump(restored_state, twin) == dump(state, rig), "restored and original run 45 s more with identical results")
	check(count_natural(state) > 30 and restored_state.counters_consistent(), "the continued run really spread (%d natural tiles) and the restored counters are consistent" % count_natural(state))

# ---- front speed ------------------------------------------------------------------------------------

func test_front_speed() -> void:
	var state: WorldState = blank(200, 12)
	fill_mature(state, Rect2i(0, 0, 2, 12))
	var rig: Rig = Rig.new(state, sim_tuning)
	var samples: Array[int] = []
	for minute: int in 11:
		var front: int = 0
		for x: int in 200:
			if state.stage[state.index_of(x, 6)] >= WorldState.GREENED_MIN_STAGE:
				front = x
		samples.append(front)
		for second: int in 60:
			rig.step_second()
	var speed: float = float(samples[10] - samples[2]) / 8.0
	info["front_green_tiles_per_minute"] = snappedf(speed, 0.01)
	info["front_samples_per_minute"] = samples
	var mature_front: int = 0
	for x: int in 200:
		if state.stage[state.index_of(x, 6)] == WorldState.STAGE_MATURE:
			mature_front = x
	check(speed >= 2.0 and speed <= 8.0, "flat front: natural spread advances %.2f tiles per minute (green front %s)" % [speed, samples])
	# Manual seeding reaches projectile_range tiles away and is mature after mature_growth / base seconds.
	var play_tuning: PlayTuning = load("res://data/play_tuning.tres") as PlayTuning
	var manual_reach_tiles: float = play_tuning.projectile_range_px / 4.0
	var manual_seconds: float = float(sim_tuning.mature_growth) / float(sim_tuning.base_growth_per_tick) * sim_tuning.growth_tick_seconds
	var manual_speed: float = manual_reach_tiles / (manual_seconds / 60.0)
	info["manual_front_tiles_per_minute"] = manual_speed
	check(manual_speed > speed * 3.0, "a manual shot lays a front %.0f tiles away that is mature in %.0f s (= %.1f tiles/min), far faster than natural spread (%.2f)" % [manual_reach_tiles, manual_seconds, manual_speed, speed])
	check(mature_front >= samples[10] - 6, "the mature front follows the green front closely (%d vs %d)" % [mature_front, samples[10]])

# ---- real region -------------------------------------------------------------------------------------

func test_region_01() -> void:
	var state: WorldState = RegionLoader.load_region(region_def)
	var sources: Array[int] = []
	for index: int in state.tile_count():
		if state.stage[index] == WorldState.STAGE_MATURE:
			sources.append(index)
	var depths: Dictionary = reach_depths(state, sources)
	var plantable_targets: int = 0
	for index: int in state.tile_count():
		if state.target[index] == 1 and state.terrain_defs[state.terrain[index]].plantable:
			plantable_targets += 1
	var isolated: int = plantable_targets - depths.size()
	var max_depth: int = 0
	for index: int in depths:
		max_depth = maxi(max_depth, int(depths[index]))
	info["region_targets"] = state.target_count
	info["region_start_mature"] = sources.size()
	info["region_connected_from_start"] = depths.size()
	info["region_isolated_plantable"] = isolated
	info["region_max_hops"] = max_depth
	check(sources.size() > 0 and depths.size() > sources.size(), "region_01: %d mature start tiles, %d target tiles connected to them, %d isolated target tiles (%d hops deepest)" % [sources.size(), depths.size(), isolated, max_depth])
	var rig: Rig = Rig.new(state, sim_tuning)
	var start_percent: float = 100.0 * state.greened_count / state.target_count
	var timeline: Dictionary = {}
	var spread_times: Array[float] = []
	var growth_times: Array[float] = []
	var checkpoints: Array[int] = [30, 60, 120, 180, 300, 600, 900, 1200, 1800]
	for second: int in range(1, 1801):
		for step: int in 4:
			rig.clock.advance(0.25)
		if checkpoints.has(second):
			timeline[str(second)] = {"greened_pct": snappedf(100.0 * state.greened_count / state.target_count, 0.01), "greened": state.greened_count, "natural_planted": rig.spread.total_planted, "queue": rig.spread.queue_size(), "active": state.active_tiles.size()}
			if second == 300:
				check(state.counters_consistent(), "region_01: counters equal a full recount after 5 min of natural spread only")
				var stray: int = 0
				for index: int in state.tile_count():
					if not depths.has(index) and state.stage[index] != WorldState.STAGE_EMPTY:
						stray += 1
				check(stray == 0, "region_01: after 5 min no isolated, water or building tile was planted")
				var grown: float = 100.0 * state.greened_count / state.target_count - start_percent
				check(grown > 0.0 and rig.spread.total_planted > 100, "region_01: 5 min of spread alone grows the greening rate from %.2f %% to %.2f %% (%d tiles planted)" % [start_percent, start_percent + grown, rig.spread.total_planted])
	info["region_timeline"] = timeline
	var stray_end: int = 0
	for index: int in state.tile_count():
		if not depths.has(index) and state.stage[index] != WorldState.STAGE_EMPTY:
			stray_end += 1
	check(stray_end == 0 and state.counters_consistent(), "region_01: after 30 min still nothing planted outside the connected area; counters consistent")

# ---- performance ----------------------------------------------------------------------------------------

## Repaints the remaining dirty tiles frame by frame (render_tiles_per_frame each). Returns [slowest frame ms, frames].
func drain_frames(view: RegionView, state: WorldState) -> Array:
	var worst: float = 0.0
	var frames: int = 0
	while not state.dirty_tiles.is_empty():
		var t0: int = Time.get_ticks_usec()
		view.flush(sim_tuning.render_tiles_per_frame)
		worst = maxf(worst, float(Time.get_ticks_usec() - t0) / 1000.0)
		frames += 1
	return [snappedf(worst, 0.01), frames]

func hashed(index: int) -> int:
	var h: int = (index * 0x9E3779B1) & 0xFFFFFFFF
	h ^= h >> 15
	h = (h * 0x2C1B3C6D) & 0xFFFFFFFF
	h ^= h >> 13
	return h

func test_performance() -> void:
	var state: WorldState = blank(512, 512)
	var growth_start: SimTuning = sim_tuning
	var grow_def: GrowthSim = GrowthSim.new(state, growth_start)
	for y: int in 512:
		for x: int in 512:
			var column: int = x % 16
			var index: int = state.index_of(x, y)
			if column < 4:
				state.set_stage(index, WorldState.STAGE_MATURE)
			elif column >= 8:
				var g: int = hashed(index) % (sim_tuning.mature_growth - 1)
				state.set_stage(index, grow_def.stage_for_growth(g))
				state.growth[index] = g
				if hashed(index + 7) % 3 == 0:
					state.set_moisture(index, hashed(index + 13) % 101)
	var spread_sim: SpreadSim = SpreadSim.new(state, sim_tuning)
	var view: RegionView = RegionView.new()
	view.setup(state, sim_tuning)
	var active_start: int = state.active_tiles.size()
	var queue_start: int = spread_sim.queue_size()
	var half: bool = active_start * 100 >= state.tile_count() * 45
	check(half, "performance map: %d of %d tiles growing (%.0f %%), %d spread candidates queued" % [active_start, state.tile_count(), 100.0 * active_start / state.tile_count(), queue_start])
	var frame_us: Array[float] = []
	var both_us: Array[float] = []
	var growth_only_us: Array[float] = []
	var spread_only_us: Array[float] = []
	var idle_us: Array[float] = []
	var growth_us: Array[float] = []
	var spread_us: Array[float] = []
	var flush_us: Array[float] = []
	var worst_flush_tiles: int = 0
	var clock: SimClock = SimClock.new()
	clock.configure(sim_tuning)
	var measured_growth: GrowthSim = grow_def
	var measured_spread: SpreadSim = spread_sim
	var growth_cost: Array = [0.0]
	var spread_cost: Array = [0.0]
	clock.growth_ticked.connect(func(_i: int) -> void:
		var t0: int = Time.get_ticks_usec()
		measured_growth.tick()
		growth_cost[0] = float(Time.get_ticks_usec() - t0))
	clock.spread_ticked.connect(func(_i: int) -> void:
		var t0: int = Time.get_ticks_usec()
		measured_spread.tick()
		spread_cost[0] = float(Time.get_ticks_usec() - t0))
	var max_visited: int = 0
	var max_examined: int = 0
	for frame: int in 1500:
		var g_before: int = clock.growth_ticks
		var s_before: int = clock.spread_ticks
		growth_cost[0] = 0.0
		spread_cost[0] = 0.0
		var t0: int = Time.get_ticks_usec()
		clock.advance(1.0 / 60.0)
		var t1: int = Time.get_ticks_usec()
		view.flush(sim_tuning.render_tiles_per_frame)
		var t2: int = Time.get_ticks_usec()
		var total: float = float(t2 - t0)
		frame_us.append(total)
		flush_us.append(float(t2 - t1))
		worst_flush_tiles = maxi(worst_flush_tiles, view.last_flush_tiles)
		var grew: bool = clock.growth_ticks != g_before
		var spread: bool = clock.spread_ticks != s_before
		if grew:
			growth_us.append(growth_cost[0])
			max_visited = maxi(max_visited, measured_growth.last_visited)
		if spread:
			spread_us.append(spread_cost[0])
			max_examined = maxi(max_examined, measured_spread.last_examined)
		if grew and spread:
			both_us.append(total)
		elif grew:
			growth_only_us.append(total)
		elif spread:
			spread_only_us.append(total)
		else:
			idle_us.append(total)
	perf["frame_ms_max"] = snappedf(frame_us.max() / 1000.0, 0.01)
	perf["frame_ms_p99"] = snappedf(percentile(frame_us, 0.99) / 1000.0, 0.01)
	perf["frame_ms_mean"] = snappedf(frame_us.reduce(func(a: float, b: float) -> float: return a + b, 0.0) / frame_us.size() / 1000.0, 0.01)
	perf["frame_both_ticks_ms_max"] = snappedf(both_us.max() / 1000.0, 0.01)
	perf["frame_both_ticks_ms_median"] = snappedf(percentile(both_us, 0.5) / 1000.0, 0.01)
	perf["frame_growth_only_ms_max"] = snappedf(growth_only_us.max() / 1000.0, 0.01)
	perf["frame_spread_only_ms_max"] = snappedf(spread_only_us.max() / 1000.0, 0.01) if not spread_only_us.is_empty() else 0.0
	perf["frame_idle_ms_max"] = snappedf(idle_us.max() / 1000.0, 0.01)
	perf["growth_tick_ms_max"] = snappedf(growth_us.max() / 1000.0, 0.01)
	perf["growth_tick_ms_median"] = snappedf(percentile(growth_us, 0.5) / 1000.0, 0.01)
	perf["spread_tick_ms_max"] = snappedf(spread_us.max() / 1000.0, 0.01)
	perf["spread_tick_ms_median"] = snappedf(percentile(spread_us, 0.5) / 1000.0, 0.01)
	perf["flush_ms_max"] = snappedf(flush_us.max() / 1000.0, 0.01)
	perf["flush_tiles_max"] = worst_flush_tiles
	perf["perf_active_tiles_start"] = active_start
	perf["perf_queue_start"] = queue_start
	check(max_visited <= sim_tuning.max_growth_tiles_per_tick and max_examined <= sim_tuning.spread_candidates_per_tick, "performance run respected G (max visited %d) and B (max examined %d)" % [max_visited, max_examined])
	check(frame_us.max() < 16000.0, "frame total (growth tick + spread tick + RegionView flush) stays under 16 ms: max %.2f ms, p99 %.2f ms, both-ticks max %.2f ms" % [frame_us.max() / 1000.0, percentile(frame_us, 0.99) / 1000.0, both_us.max() / 1000.0])
	check(state.counters_consistent(), "performance map: counters consistent after 25 s")
	# Large stage changes in one tick.
	var burst: WorldState = blank(512, 512)
	var burst_tuning: SimTuning = sim_tuning
	var burst_growth: GrowthSim = GrowthSim.new(burst, burst_tuning)
	var burst_view: RegionView = RegionView.new()
	burst_view.setup(burst, burst_tuning)
	var block_tiles: Array[int] = []
	for y: int in range(100, 163):
		for x: int in range(100, 163):
			block_tiles.append(burst.index_of(x, y))
	var scattered: Array[int] = []
	for y: int in range(200, 456, 4):
		for x: int in range(100, 356, 4):
			scattered.append(burst.index_of(x, y))
	for list: Variant in [block_tiles, scattered]:
		for index: int in (list as Array):
			burst.set_stage(index, WorldState.STAGE_SPROUT2)
			burst.growth[index] = burst_tuning.mature_growth - 100
		burst_view.flush()
	var t_g0: int = Time.get_ticks_usec()
	var pre_ticks: int = burst_growth.ticks
	# Tick until the contiguous block (first in the active list) went mature: one window of G tiles.
	burst_growth.tick()
	var t_g1: int = Time.get_ticks_usec()
	var changes_first: int = burst_growth.last_stage_changes
	burst_view.flush(sim_tuning.render_tiles_per_frame)
	var t_g2: int = Time.get_ticks_usec()
	perf["burst_contiguous_changes"] = changes_first
	perf["burst_contiguous_growth_tick_ms"] = snappedf(float(t_g1 - t_g0) / 1000.0, 0.01)
	perf["burst_contiguous_flush_ms"] = snappedf(float(t_g2 - t_g1) / 1000.0, 0.01)
	perf["burst_contiguous_flush_tiles"] = burst_view.last_flush_tiles
	var drain_contiguous: Array = drain_frames(burst_view, burst)
	perf["burst_contiguous_drain_frames_after"] = drain_contiguous[1]
	perf["burst_contiguous_drain_frame_ms_max"] = drain_contiguous[0]
	var t_s0: int = Time.get_ticks_usec()
	burst_growth.tick()
	var t_s1: int = Time.get_ticks_usec()
	var changes_second: int = burst_growth.last_stage_changes
	burst_view.flush(sim_tuning.render_tiles_per_frame)
	var t_s2: int = Time.get_ticks_usec()
	perf["burst_scattered_changes"] = changes_second
	perf["burst_scattered_growth_tick_ms"] = snappedf(float(t_s1 - t_s0) / 1000.0, 0.01)
	perf["burst_scattered_flush_ms"] = snappedf(float(t_s2 - t_s1) / 1000.0, 0.01)
	perf["burst_scattered_flush_tiles"] = burst_view.last_flush_tiles
	var drain_scattered: Array = drain_frames(burst_view, burst)
	perf["burst_scattered_drain_frames_after"] = drain_scattered[1]
	perf["burst_scattered_drain_frame_ms_max"] = drain_scattered[0]
	check(changes_first + changes_second > 0 and pre_ticks + 2 == burst_growth.ticks, "burst: %d + %d tiles changed stage in two single ticks" % [changes_first, changes_second])
	check(float(t_g2 - t_g0) < 16000.0 and float(t_s2 - t_s0) < 16000.0, "burst frames under 16 ms: contiguous %.2f ms (tick %.2f + flush %.2f), scattered %.2f ms (tick %.2f + flush %.2f)" % [float(t_g2 - t_g0) / 1000.0, float(t_g1 - t_g0) / 1000.0, float(t_g2 - t_g1) / 1000.0, float(t_s2 - t_s0) / 1000.0, float(t_s1 - t_s0) / 1000.0, float(t_s2 - t_s1) / 1000.0])
	# Spread burst: B candidates planted in one tick.
	var plant: WorldState = blank(512, 512)
	fill_mature(plant, Rect2i(100, 100, 300, 3))
	var plant_spread: SpreadSim = SpreadSim.new(plant, sim_tuning)
	var plant_view: RegionView = RegionView.new()
	plant_view.setup(plant, sim_tuning)
	while plant_spread.pending_size() > 0:
		plant_spread.tick()
	plant_view.flush()
	var queued_now: PackedInt32Array = plant_spread.queue.slice(plant_spread.head)
	for index: int in queued_now:
		plant_spread.progress[index] = sim_tuning.spread_progress_threshold
	var p0: int = Time.get_ticks_usec()
	plant_spread.tick()
	var p1: int = Time.get_ticks_usec()
	plant_view.flush(sim_tuning.render_tiles_per_frame)
	var p2: int = Time.get_ticks_usec()
	perf["spread_burst_planted"] = plant_spread.last_planted
	perf["spread_burst_tick_ms"] = snappedf(float(p1 - p0) / 1000.0, 0.01)
	perf["spread_burst_flush_ms"] = snappedf(float(p2 - p1) / 1000.0, 0.01)
	check(plant_spread.last_planted == mini(sim_tuning.spread_candidates_per_tick, queued_now.size()), "spread burst: B = %d candidates planted in one tick (queue held %d)" % [plant_spread.last_planted, queued_now.size()])
	check(float(p2 - p0) < 16000.0, "spread burst frame (tick %.2f ms + flush %.2f ms) under 16 ms" % [float(p1 - p0) / 1000.0, float(p2 - p1) / 1000.0])
	view.free()
	burst_view.free()
	plant_view.free()

# ---- scene ----------------------------------------------------------------------------------------------

func test_scene_flow() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var state: WorldState = main.grid
	var simulation: SimulationDriver = main.simulation
	check(simulation.spread != null and simulation.clock.spread_period == 1.0, "scene: the simulation driver owns the spread tick (1.0 s clock)")
	var natural_before: int = count_natural(state)
	var greened_before: int = state.greened_count
	for step: int in 240:
		simulation.clock.advance(0.25)
	check(count_natural(state) > natural_before and state.greened_count >= greened_before and state.counters_consistent(), "scene: 60 s of game time spread green from the safe zone (%d natural tiles) with consistent counters" % count_natural(state))
	main.queue_free()
	await process_frame
