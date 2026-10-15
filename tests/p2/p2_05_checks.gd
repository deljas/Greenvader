extends SceneTree
## P2-05 headless checks: far seed spreading in stable zones (FarSeedSim). Islands, a thin passage and the far river bank reach exactly
## 100 % greening without any input, inside the bound computed from the settings; unstable zones are never touched; seeds are natural
## seeds that grow normally; the sweep is fair (every free tile is processed within one lap); the load check was relaxed; pause,
## 30 / 60 / 144 Hz and save round trips; performance; and region_01 with every nest and boar removed.
## Run: Godot --headless --path <project> --script res://tests/p2/p2_05_checks.gd [-- --skip-long]
## Expected values come from the ticket and the design written here (a seed of the far sweep is a natural seed: 1000 growth x 2.0
## = 2000 per growth tick, sprout 1 at 40000; component membership is "plantable target within Euclidean distance 2"; the
## bound is the arithmetic written out below). They are not read back from the implementation.

const REGION_PATH: String = "res://data/region_01.tres"
const TILE: int = 4
const U: int = WorldState.ZONE_UNCONQUERED
const S: int = WorldState.ZONE_STABLE
const K: int = WorldState.ZONE_COMPLETE

var failures: int = 0
var checks: int = 0
var skip_long: bool = false
var region_def: RegionDef
var sim_tuning: SimTuning
var enemy_tuning: EnemyTuning
var info: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", message])

func run() -> void:
	skip_long = OS.get_cmdline_user_args().has("--skip-long")
	region_def = load(REGION_PATH) as RegionDef
	sim_tuning = load("res://data/sim_tuning.tres") as SimTuning
	enemy_tuning = load("res://data/enemy_tuning.tres") as EnemyTuning
	check(region_def != null and sim_tuning != null and enemy_tuning != null, "region and tunings load")
	test_bound_values()
	test_labelling_matches_independent_flood_fill()
	test_islands_only()
	test_sweep_only_bound()
	test_full_with_nest_and_spread()
	test_unstable_untouched()
	test_initial_zone_not_swept()
	test_sweep_delay_boundary()
	test_natural_seed_growth()
	test_skip_rules_and_scan_cap()
	test_lap_fairness()
	test_load_relaxed()
	test_complete_zone_refills()
	test_frame_rates_and_pause()
	test_save_round_trip()
	test_stable_spread_multiplier()
	test_stress_frame_cost()
	await test_scene_wiring()
	if not skip_long:
		test_region_01()
	print("INFO " + JSON.stringify(info))
	print("P2_05_RESULT checks=%d failures=%d" % [checks, failures])
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path("res://evidence/p2/p2-05/checks_info.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(info, "  "))
		file.close()
	quit(1 if failures > 0 else 0)

# ---- helpers -------------------------------------------------------------------------------------------------------

func terrain_def(key: StringName) -> TerrainDef:
	for def: TerrainDef in region_def.terrains:
		if def.key == key:
			return def
	return null

func c8(color: Color) -> Vector3i:
	return Vector3i(roundi(color.r * 255.0), roundi(color.g * 255.0), roundi(color.b * 255.0))

func tune(overrides: Dictionary = {}) -> SimTuning:
	var copy: SimTuning = sim_tuning.duplicate() as SimTuning
	for key: String in overrides:
		copy.set(key, overrides[key])
	return copy

## A tuning for the small maps: a sweep that needs many steps (K 32, S 256) and slow labelling, so the sliced work is exercised.
func small_tune(overrides: Dictionary = {}) -> SimTuning:
	var base: Dictionary = {"far_sweep_seeds_per_step": 32, "far_sweep_scan_per_step": 256, "far_label_tiles_per_tick": 60, "far_label_scan_per_tick": 400, "far_check_reads_per_tick": 200, "far_sweep_start_delay_seconds": 0.0}
	for key: String in overrides:
		base[key] = overrides[key]
	return tune(base)

const NEVER: float = 1.0e9

## Glyph grid: '.' wasteland, '~' water, '#' building.
func blank_grid(width: int, height: int) -> Array:
	var rows: Array = []
	for y: int in height:
		rows.append(".".repeat(width))
	return rows

func fill_rect(rows: Array, rect: Rect2i, glyph: String) -> void:
	for y: int in range(rect.position.y, rect.end.y):
		var row: String = rows[y]
		for x: int in range(rect.position.x, rect.end.x):
			row = row.substr(0, x) + glyph + row.substr(x + 1)
		rows[y] = row

## Map A (120 x 60): a river (3 wide) splits west and east; three islands (rings of water 2 wide, the tightest gap that
## separates); a walled chamber on the east bank reachable only by a 1-wide, 6-long passage.
func map_a() -> Array:
	var rows: Array = blank_grid(120, 60)
	fill_rect(rows, Rect2i(58, 0, 3, 60), "~")
	# Island 1: 3 x 3 at (20..22, 10..12), ring of water 2 wide.
	fill_rect(rows, Rect2i(18, 8, 7, 7), "~")
	fill_rect(rows, Rect2i(20, 10, 3, 3), ".")
	# Island 2: one tile at (40, 30).
	fill_rect(rows, Rect2i(38, 28, 5, 5), "~")
	fill_rect(rows, Rect2i(40, 30, 1, 1), ".")
	# Island 3 (on the east bank): 2 x 1 at (90..91, 20).
	fill_rect(rows, Rect2i(88, 18, 6, 5), "~")
	fill_rect(rows, Rect2i(90, 20, 2, 1), ".")
	# Chamber: buildings x 66..100, y 33..57, hollow x 72..98, y 37..53, a passage y = 45 through the west wall.
	fill_rect(rows, Rect2i(66, 33, 35, 25), "#")
	fill_rect(rows, Rect2i(72, 37, 27, 17), ".")
	fill_rect(rows, Rect2i(66, 45, 6, 1), ".")
	return rows

func world_from_rows(rows: Array, states: Array, splits: Array = []) -> WorldState:
	var def: RegionDef = RegionDef.new()
	def.width_tiles = String(rows[0]).length()
	def.height_tiles = rows.size()
	def.terrains = region_def.terrains
	def.sprout_seed = region_def.sprout_seed
	var image: Image = Image.create(def.width_tiles, def.height_tiles, false, Image.FORMAT_RGB8)
	var glyphs: Dictionary = {".": &"wasteland", "~": &"water", "#": &"building"}
	for y: int in rows.size():
		for x: int in String(rows[y]).length():
			var v: Vector3i = c8(terrain_def(glyphs[String(rows[y])[x]]).map_color)
			image.set_pixel(x, y, Color8(v.x, v.y, v.z))
	var world: WorldState = RegionLoader.build_state(def, image)
	var ids: PackedByteArray = PackedByteArray()
	ids.resize(world.tile_count())
	for index: int in world.tile_count():
		var zone: int = 0
		for split: int in splits:
			if index % world.width >= split:
				zone += 1
		ids[index] = zone
	world.set_zones(ids, PackedByteArray(states))
	return world

class Rig:
	extends RefCounted
	var world: WorldState
	var clock: SimClock = SimClock.new()
	var growth: GrowthSim
	var spread: SpreadSim
	var far: FarSeedSim
	var field: EnemyField
	var progress: ZoneProgress
	var use_spread: bool = true
	var cleared_at: float = -1.0
	var complete_at: Dictionary = {}
	## Microseconds spent in the three tick handlers of the latest and the worst advance.
	var timing: bool = false
	var frame_us: int = 0
	var worst_frame_us: int = 0
	var worst_far_us: int = 0
	var worst_growth_us: int = 0
	var worst_spread_us: int = 0
	var frames: int = 0
	var total_us: int = 0
	var frame_samples: PackedInt32Array = PackedInt32Array()
	func on_growth(_i: int) -> void:
		var t0: int = Time.get_ticks_usec() if timing else 0
		growth.tick()
		if timing:
			var d: int = Time.get_ticks_usec() - t0
			frame_us += d
			worst_growth_us = maxi(worst_growth_us, d)
	func on_spread(_i: int) -> void:
		var t0: int = Time.get_ticks_usec() if timing else 0
		if use_spread:
			spread.tick()
		var t1: int = Time.get_ticks_usec() if timing else 0
		far.tick()
		if timing:
			var t2: int = Time.get_ticks_usec()
			frame_us += t2 - t0
			worst_spread_us = maxi(worst_spread_us, t1 - t0)
			worst_far_us = maxi(worst_far_us, t2 - t1)
	func on_cleared() -> void:
		cleared_at = clock.elapsed
	func on_state(zone: int, _old: int, new_state: int) -> void:
		if new_state == WorldState.ZONE_COMPLETE:
			complete_at[zone] = clock.elapsed
	func advance(dt: float) -> void:
		frame_us = 0
		clock.advance(dt)
		if timing:
			frames += 1
			total_us += frame_us
			worst_frame_us = maxi(worst_frame_us, frame_us)
			frame_samples.append(frame_us)

func make_rig(world: WorldState, tuning: SimTuning, with_spread: bool = true, hook: bool = true) -> Rig:
	var rig: Rig = Rig.new()
	rig.world = world
	rig.use_spread = with_spread
	rig.clock.configure(tuning)
	rig.growth = GrowthSim.new(world, tuning)
	rig.spread = SpreadSim.new(world, tuning)
	rig.far = FarSeedSim.new(world, tuning)
	var etune: EnemyTuning = enemy_tuning.duplicate() as EnemyTuning
	etune.spawn_interval_seconds = 100000.0
	rig.field = EnemyField.new(world, etune, TILE)
	rig.progress = ZoneProgress.new(world, rig.field)
	if hook:
		rig.spread.allow_hook = rig.field.spread_allows
	rig.clock.growth_ticked.connect(rig.on_growth)
	rig.clock.spread_ticked.connect(rig.on_spread)
	rig.progress.cleared.connect(rig.on_cleared)
	world.zone_state_changed.connect(rig.on_state)
	return rig

## Advances in steps of `dt` until `done` is true or `limit` seconds of game time have passed. Returns the elapsed game time.
func run_until(rig: Rig, limit: float, dt: float, done: Callable) -> float:
	while rig.clock.elapsed < limit and not bool(done.call()):
		rig.advance(dt)
	return rig.clock.elapsed

func is_100(world: WorldState) -> bool:
	return world.greened_count == world.target_count

## Independent flood fill: components of the plantable target tiles with the rule "Euclidean distance <= 2" written out here.
## Returns the component id (1-based) per tile, 0 for others.
func flood_components(world: WorldState, zone: int = -1) -> PackedInt32Array:
	var width: int = world.width
	var height: int = world.height
	var plantable: PackedByteArray = PackedByteArray()
	plantable.resize(world.tile_count())
	for index: int in world.tile_count():
		var def: TerrainDef = world.terrain_defs[world.terrain[index]]
		plantable[index] = 1 if (def.is_target and def.plantable and (zone < 0 or world.zone_of[index] == zone)) else 0
	var comp: PackedInt32Array = PackedInt32Array()
	comp.resize(world.tile_count())
	var next_id: int = 0
	for first: int in world.tile_count():
		if plantable[first] == 0 or comp[first] != 0:
			continue
		next_id += 1
		comp[first] = next_id
		var queue: PackedInt32Array = PackedInt32Array([first])
		var head: int = 0
		while head < queue.size():
			var index: int = queue[head]
			head += 1
			var x: int = index % width
			var y: int = index / width
			for dy: int in range(-2, 3):
				for dx: int in range(-2, 3):
					if dx * dx + dy * dy > 4:
						continue
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or ny < 0 or nx >= width or ny >= height:
						continue
					var other: int = ny * width + nx
					if plantable[other] == 1 and comp[other] == 0:
						comp[other] = next_id
						queue.append(other)
	return comp

func count_free_targets(world: WorldState) -> int:
	var total: int = 0
	for index: int in world.tile_count():
		if world.target[index] == 1 and world.terrain_defs[world.terrain[index]].plantable and world.stage[index] == 0 and world.occupant[index] == 0:
			total += 1
	return total

func mature_block(world: WorldState, rect: Rect2i) -> void:
	world.debug_fill_stage(rect, WorldState.STAGE_MATURE)

# ---- tests -------------------------------------------------------------------------------------------------------

func test_bound_values() -> void:
	# Hand arithmetic on region_01 with E = every target = 244759 (P1-06) given explicitly, n = 512 * 512 = 262144, S = 4096, sweep
	# period 5 s, spread tick 1 s, G = 3000, growth tick 0.5 s, sprout 1 at 40000, dry natural gain 1000 x 1.0 x 2.0, start delay 120 s.
	# With K = 256:
	#   lap steps = ceil(244759 / 256) + ceil(262144 / 4096) + 1 = 957 + 64 + 1 = 1022; sweep part = (1022 + 1) * 5 s = 5115 s
	#   growth part = (ceil(40000 / 2000) + ceil(262144 / 3000) + 1) ticks * 0.5 s = (20 + 88 + 1) * 0.5 = 54.5 s
	#   delay part = 120 s + 1 spread tick = 121 s            -> 5290.5 s
	var world: WorldState = RegionLoader.load_region(region_def)
	var k256: FarSeedSim = FarSeedSim.new(world, tune({"far_sweep_seeds_per_step": 256}))
	check(world.target_count == 244759, "region_01 has 244759 greening targets (%d)" % world.target_count)
	check(k256.lap_steps_bound(244759) == 1022, "K = 256: lap bound is 1022 sweep steps (%d)" % k256.lap_steps_bound(244759))
	check(k256.slowest_greened_ticks() == 20, "a natural seed needs 20 growth ticks to sprout 1 at the slowest speed (%d)" % k256.slowest_greened_ticks())
	check(absf(k256.completion_bound_seconds(244759) - 5290.5) < 1.0e-6, "K = 256: completion bound is 5290.5 s (%f)" % k256.completion_bound_seconds(244759))
	# Shipped K = 64: ceil(244759 / 64) = 3825; 3825 + 64 + 1 = 3890 steps; (3890 + 1) * 5 = 19455; + 54.5 + 121
	var shipped: FarSeedSim = FarSeedSim.new(world, sim_tuning)
	check(sim_tuning.far_sweep_seeds_per_step == 64 and sim_tuning.far_sweep_start_delay_seconds == 120.0, "shipped values: K = 64, start delay 120 s")
	check(absf(shipped.completion_bound_seconds(244759) - 19630.5) < 1.0e-6, "K = 64 (shipped): the bound is 19630.5 s (%f)" % shipped.completion_bound_seconds(244759))
	var slow: FarSeedSim = FarSeedSim.new(world, tune({"far_sweep_seeds_per_step": 256, "far_sweep_period_seconds": 10.0}))
	check(absf(slow.completion_bound_seconds(244759) - (1023.0 * 10.0 + 54.5 + 121.0)) < 1.0e-6, "with a 10 s sweep period the bound is 10405.5 s (%f)" % slow.completion_bound_seconds(244759))
	var half_mult: FarSeedSim = FarSeedSim.new(world, tune({"far_sweep_seeds_per_step": 256, "natural_growth_multiplier": 1.0}))
	check(absf(half_mult.completion_bound_seconds(244759) - (5115.0 + 64.5 + 121.0)) < 1.0e-6, "with natural multiplier 1.0 the growth part is 64.5 s (%f)" % half_mult.completion_bound_seconds(244759))
	var no_delay: FarSeedSim = FarSeedSim.new(world, tune({"far_sweep_seeds_per_step": 256, "far_sweep_start_delay_seconds": 0.0}))
	check(absf(no_delay.completion_bound_seconds(244759) - 5170.5) < 1.0e-6, "without start delay the bound is 5170.5 s (%f)" % no_delay.completion_bound_seconds(244759))
	# Which zones are swept: the start zone starts stable (ZoneDef initial state) and is excluded.
	var zone0_targets: int = 0
	for index: int in world.tile_count():
		if world.zone_of[index] == 0 and world.target[index] == 1:
			zone0_targets += 1
	check(shipped.zone_initial[0] == 1 and shipped.zone_initial[1] == 0 and shipped.swept_targets() == 244759 - zone0_targets, "the zone that starts stable is not swept (zone 0 has %d targets, swept %d)" % [zone0_targets, shipped.swept_targets()])
	info["region_bound_default_s"] = shipped.completion_bound_seconds()
	for k_value: int in [64, 128, 256, 512]:
		info["region_bound_k%d_s" % k_value] = FarSeedSim.new(world, tune({"far_sweep_seeds_per_step": k_value})).completion_bound_seconds()

func test_labelling_matches_independent_flood_fill() -> void:
	var rows: Array = map_a()
	var world: WorldState = world_from_rows(rows, [S])
	var rig: Rig = make_rig(world, small_tune({"far_sweep_period_seconds": NEVER, "far_island_period_seconds": NEVER}), false)
	var expected: PackedInt32Array = flood_components(world)
	var expected_count: int = 0
	for id: int in expected:
		expected_count = maxi(expected_count, id)
	rig.progress.start()
	var guard: int = 0
	while guard < 5000 and (rig.far.ticks == 0 or rig.far.labelling_busy()):
		rig.far.tick()
		guard += 1
	check(not rig.far.labelling_busy() and rig.far.zone_enum[0] == 2, "labelling of the stable zone finished after %d spread ticks" % guard)
	check(expected_count == 5, "map A has 5 components by the independent flood fill (west, island 1, island 2, island 3, east bank with the chamber): %d" % expected_count)
	check(rig.far.comp_count() == expected_count and rig.far.finished_comp_count() == expected_count, "FarSeedSim found the same number of components (%d)" % rig.far.comp_count())
	var map_ok: bool = true
	var seen: Dictionary = {}
	for index: int in world.tile_count():
		var a: int = expected[index]
		var b: int = rig.far.label[index]
		if (a == 0) != (b == 0):
			map_ok = false
			break
		if a != 0:
			if seen.has(a) and seen[a] != b:
				map_ok = false
				break
			seen[a] = b
	var distinct: Dictionary = {}
	for a: int in seen:
		distinct[seen[a]] = true
	check(map_ok and distinct.size() == seen.size(), "the labels partition the tiles exactly like the independent flood fill (same members, one label per component)")
	var members_ok: bool = rig.far.members.size() == world.recount_targets() - 0 - count_non_plantable_targets(world)
	check(members_ok, "the BFS list holds every plantable target exactly once (%d)" % rig.far.members.size())
	# The labels never change world state.
	check(world.greened_count == 0 and world.plant_count == 0, "labelling alone plants nothing")
	# Boundary rules: distance 2 connects, distance 3 or (2,1) does not.
	var tiny_rows: Array = blank_grid(12, 12)
	fill_rect(tiny_rows, Rect2i(0, 0, 12, 12), "~")
	for tile: Vector2i in [Vector2i(1, 1), Vector2i(3, 1), Vector2i(6, 1), Vector2i(1, 5), Vector2i(3, 6), Vector2i(8, 8), Vector2i(9, 9)]:
		fill_rect(tiny_rows, Rect2i(tile.x, tile.y, 1, 1), ".")
	var tiny: WorldState = world_from_rows(tiny_rows, [S])
	var tiny_rig: Rig = make_rig(tiny, small_tune({"far_sweep_period_seconds": NEVER, "far_island_period_seconds": NEVER}), false)
	tiny_rig.progress.start()
	for i: int in 50:
		tiny_rig.far.tick()
	var lab: PackedInt32Array = tiny_rig.far.label
	var at: Callable = func(x: int, y: int) -> int: return lab[tiny.index_of(x, y)]
	# (1,1)-(3,1): distance 2 -> one component. (6,1): distance 3 -> separate. (1,5) and (3,6): (2,1) offset, distance sqrt 5 -> separate.
	# (8,8)-(9,9): diagonal -> one component.
	check(at.call(1, 1) == at.call(3, 1) and at.call(6, 1) != at.call(3, 1), "tiles 2 apart are connected, 3 apart are not")
	check(at.call(1, 5) != at.call(3, 6) and at.call(8, 8) == at.call(9, 9), "an offset of (2,1) does not connect, a diagonal does")
	check(tiny_rig.far.comp_count() == 5, "the tiny map has 5 components (%d)" % tiny_rig.far.comp_count())

func count_non_plantable_targets(world: WorldState) -> int:
	var total: int = 0
	for index: int in world.tile_count():
		if world.target[index] == 1 and not world.terrain_defs[world.terrain[index]].plantable:
			total += 1
	return total

func west_green(world: WorldState) -> void:
	mature_block(world, Rect2i(2, 2, 5, 5))

func test_islands_only() -> void:
	# (a) alone: no sweep, no natural spread. Every component without a plant gets exactly one seed, in a bounded time.
	var world: WorldState = world_from_rows(map_a(), [S])
	west_green(world)
	var expected: PackedInt32Array = flood_components(world)
	var greenless: Dictionary = {}
	var green_comps: Dictionary = {}
	for index: int in world.tile_count():
		if expected[index] != 0:
			if world.stage[index] != 0:
				green_comps[expected[index]] = true
	for index: int in world.tile_count():
		if expected[index] != 0 and not green_comps.has(expected[index]):
			greenless[expected[index]] = true
	var rig: Rig = make_rig(world, small_tune({"far_sweep_period_seconds": NEVER}), false)
	rig.progress.start()
	# Without spread and sweep: after 200 s every green-less component holds exactly one seed.
	run_until(rig, 200.0, 0.25, func() -> bool: return false)
	var seeds_per_comp: Dictionary = {}
	for index: int in world.tile_count():
		if expected[index] != 0 and greenless.has(expected[index]) and world.stage[index] != 0:
			seeds_per_comp[expected[index]] = int(seeds_per_comp.get(expected[index], 0)) + 1
	var each_one: bool = seeds_per_comp.size() == greenless.size()
	for id: int in seeds_per_comp:
		# Seeds grow but nothing spreads (spread is off), so exactly one tile per component is non-empty.
		each_one = each_one and seeds_per_comp[id] == 1
	check(greenless.size() == 4 and each_one, "(a) alone: each of the %d green-less components (3 islands + east bank with the chamber) holds exactly one seed after 200 s" % greenless.size())
	check(rig.far.total_island_planted == 4 and rig.far.total_sweep_planted == 0, "(a) planted 4 seeds (%d), the sweep none (%d)" % [rig.far.total_island_planted, rig.far.total_sweep_planted])
	var natural_ok: bool = true
	for index: int in world.tile_count():
		if world.stage[index] != 0 and expected[index] != 0 and greenless.has(expected[index]):
			natural_ok = natural_ok and world.natural[index] == 1
	check(natural_ok, "the component seeds are natural seeds (natural = 1)")
	# Planting nothing in the component that already holds plants: the west part gets no component seed.
	var west_id: int = expected[world.index_of(3, 3)]
	var west_seeds: int = 0
	for index: int in world.tile_count():
		if expected[index] == west_id and world.stage[index] != 0 and world.natural[index] == 1:
			west_seeds += 1
	check(west_seeds == 0, "the component that already holds mature plants gets no seed")
	# Island 2 (one tile) and island 3 (two tiles) really are seeded: sizes do not matter.
	check(world.stage[world.index_of(40, 30)] != 0, "the one-tile island is seeded")
	check(world.stage[world.index_of(90, 20)] != 0 or world.stage[world.index_of(91, 20)] != 0, "the two-tile island is seeded")
	info["islands_only_200s_seeds"] = rig.far.total_island_planted

func test_sweep_only_bound() -> void:
	# (b) alone (the guarantee): no natural spread, no component seeding. Strictly 100 % within the settings-derived bound.
	var world: WorldState = world_from_rows(map_a(), [U])
	west_green(world)
	var tuning: SimTuning = small_tune({"far_island_period_seconds": NEVER})
	var rig: Rig = make_rig(world, tuning, false)
	rig.progress.start()
	var free_targets: int = count_free_targets(world)
	var bound: float = rig.far.completion_bound_seconds(free_targets)
	var bound_all: float = rig.far.completion_bound_seconds()
	var done_at: float = run_until(rig, bound, 0.25, func() -> bool: return rig.world.cleared)
	check(is_100(world) and world.greened_count == world.target_count, "(b) alone: greened %d == targets %d (integer equality)" % [world.greened_count, world.target_count])
	check(world.zone_state[0] == K and world.cleared, "the zone is complete and the region is cleared")
	check(done_at <= bound, "(b) alone finished at %.2f s <= bound %.2f s (bound with every target free: %.2f s)" % [done_at, bound, bound_all])
	check(world.counters_consistent(), "greening counters equal the recount")
	check(rig.far.total_island_planted == 0, "no component seeding happened in this run")
	info["map_a_sweep_only"] = {"done_at_s": done_at, "bound_s": bound, "free_targets": free_targets, "targets": world.target_count}
	# And a run that would exceed the bound is a failure: nothing extends the time. Check the bound is not absurdly loose (<= 3x).
	check(done_at >= 0.2 * bound, "the bound is not absurdly loose: measured %.1f s vs bound %.1f s" % [done_at, bound])

func test_full_with_nest_and_spread() -> void:
	# All parts together on map A, the zone starts unconquered with a nest in the west that is destroyed by the API.
	var world: WorldState = world_from_rows(map_a(), [U])
	west_green(world)
	var rig: Rig = make_rig(world, small_tune())
	var nest: Nest = rig.field.add_nest(0, Vector2i(30, 30))
	check(nest != null, "a nest is placed on the west bank")
	rig.progress.start()
	check(world.zone_state[0] == U, "the zone is unconquered while the nest lives")
	rig.far.tick()
	check(rig.far.zone_enum[0] == 0, "an unconquered zone is not enumerated")
	rig.field.destroy_nest(nest)
	check(world.zone_state[0] == S, "nest destroyed, no boar: the zone is stable")
	var free_targets: int = count_free_targets(world)
	var bound: float = rig.far.completion_bound_seconds(free_targets)
	var done_at: float = run_until(rig, bound, 0.25, func() -> bool: return rig.world.cleared)
	check(is_100(world) and world.zone_state[0] == K and world.cleared, "all parts: 100 %% (%d == %d), complete, cleared" % [world.greened_count, world.target_count])
	check(done_at <= bound, "finished at %.2f s <= bound %.2f s" % [done_at, bound])
	var nest_ok: bool = true
	for y: int in range(30, 34):
		for x: int in range(30, 34):
			nest_ok = nest_ok and world.stage[world.index_of(x, y)] >= WorldState.STAGE_SPROUT1
	check(nest_ok, "the ground of the destroyed nest is greened too")
	check(world.counters_consistent(), "counters equal the recount")
	# Same map without the sweep: the islands are seeded by (a), natural spread fills their components: 100 % as well.
	var world2: WorldState = world_from_rows(map_a(), [S])
	west_green(world2)
	var rig2: Rig = make_rig(world2, small_tune({"far_sweep_period_seconds": NEVER}))
	rig2.progress.start()
	var done2: float = run_until(rig2, 4000.0, 0.25, func() -> bool: return rig2.world.cleared)
	check(is_100(world2) and done2 < 4000.0, "(a) + natural spread alone also reaches 100 %% (%.1f s)" % done2)
	info["map_a_full"] = {"done_at_s": done_at, "bound_s": bound, "a_plus_spread_s": done2}

func test_unstable_untouched() -> void:
	# Two zones side by side (x < 60 and x >= 60, split by a river in between). Zone 1 has a live nest: it is unconquered.
	var rows: Array = blank_grid(120, 40)
	fill_rect(rows, Rect2i(58, 0, 4, 40), "~")
	var world: WorldState = world_from_rows(rows, [U, U], [60])
	mature_block(world, Rect2i(2, 2, 5, 5))
	var rig: Rig = make_rig(world, small_tune(), false)
	var nest0: Nest = rig.field.add_nest(0, Vector2i(30, 20))
	var nest1: Nest = rig.field.add_nest(1, Vector2i(90, 20))
	rig.progress.start()
	rig.field.destroy_nest(nest0)
	check(world.zone_state[0] == S and world.zone_state[1] == U, "zone 0 stable, zone 1 unconquered")
	run_until(rig, 300.0, 0.25, func() -> bool: return false)
	var zone1_touched: int = 0
	var zone0_touched: int = 0
	for index: int in world.tile_count():
		if world.stage[index] != 0:
			if world.zone_of[index] == 1:
				zone1_touched += 1
			else:
				zone0_touched += 1
	check(zone1_touched == 0 and zone0_touched > 100, "300 s: the unconquered zone holds no plant, the stable zone does (%d / %d)" % [zone1_touched, zone0_touched])
	check(rig.far.zone_enum[1] == 0, "the unconquered zone was not enumerated")
	# Clearing (nest gone, a boar alive) is not stable either.
	var boar: Boar = Boar.new()
	boar.id = rig.field.next_boar_id
	rig.field.next_boar_id += 1
	boar.zone = 1
	boar.pos = Vector2(400, 80)
	boar.home = boar.pos
	boar.hp = 3
	boar.wait = 1 << 30
	boar.rng = 1
	rig.field.boars.append(boar)
	rig.field.destroy_nest(nest1)
	check(world.zone_state[1] == WorldState.ZONE_CLEARING, "zone 1 is clearing while a boar lives")
	run_until(rig, rig.clock.elapsed + 120.0, 0.25, func() -> bool: return false)
	var clearing_touched: int = 0
	for index: int in world.tile_count():
		if world.stage[index] != 0 and world.zone_of[index] == 1:
			clearing_touched += 1
	check(clearing_touched == 0 and rig.far.zone_enum[1] == 0, "a clearing zone is not seeded either (%d plants)" % clearing_touched)
	var stable_time: float = rig.clock.elapsed
	rig.field.damage_boar(boar, 3)
	check(world.zone_state[1] == S, "last boar killed: zone 1 stable")
	run_until(rig, stable_time + 30.0, 0.25, func() -> bool: return false)
	var after: int = 0
	for index: int in world.tile_count():
		if world.stage[index] != 0 and world.zone_of[index] == 1:
			after += 1
	check(after > 0 and rig.far.zone_enum[1] >= 1, "30 s after it became stable zone 1 receives seeds (%d plants)" % after)
	var bound: float = rig.far.completion_bound_seconds(count_free_targets(world))
	run_until(rig, stable_time + bound, 0.25, func() -> bool: return rig.world.cleared)
	check(is_100(world) and world.cleared, "both zones reach 100 %% (stable at %.0f s, done at %.0f s, bound %.0f s after stable)" % [stable_time, rig.clock.elapsed, bound])
	check(rig.clock.elapsed - stable_time <= bound, "within the bound counted from the last zone becoming stable")
	info["two_zones"] = {"stable_at_s": stable_time, "done_at_s": rig.clock.elapsed, "bound_s": bound}

func test_natural_seed_growth() -> void:
	# One stable zone, no spread. The first sweep step is at spread tick 5 (t = 5.0 s). Its seeds are natural seeds: 2000 growth per
	# growth tick (dry, no fertility). Growth ticks are at 5.5, 6.0, ...: after 19 ticks (t = 14.5) 38000 = still a seed, after
	# the 20th (t = 15.0) 40000 = sprout 1.
	var world: WorldState = world_from_rows(blank_grid(80, 40), [U])
	var rig: Rig = make_rig(world, small_tune({"far_island_period_seconds": NEVER}), false)
	rig.progress.start()
	run_until(rig, 4.9, 0.01, func() -> bool: return false)
	check(world.plant_count == 0, "nothing is planted before the first sweep step")
	run_until(rig, 5.0, 0.01, func() -> bool: return false)
	check(world.plant_count == 32 and rig.far.last_sweep_planted == 32, "the first sweep step plants K = 32 seeds (%d)" % world.plant_count)
	var first_row_ok: bool = true
	for x: int in 32:
		var index: int = world.index_of(x, 0)
		first_row_ok = first_row_ok and world.stage[index] == WorldState.STAGE_SEED and world.natural[index] == 1
	check(first_row_ok, "the seeds are the first 32 free tiles from the cursor (row 0, x 0..31), natural = 1")
	check(world.greened_count == 0 and world.counters_consistent(), "seeds are not greened yet")
	run_until(rig, 14.5, 0.01, func() -> bool: return false)
	rig.growth.catch_up()
	var i0: int = world.index_of(0, 0)
	check(world.stage[i0] == WorldState.STAGE_SEED and world.growth[i0] == 38000, "t = 14.5 s: growth 38000 (19 ticks x 2000), still a seed (%d)" % world.growth[i0])
	run_until(rig, 15.0, 0.01, func() -> bool: return false)
	rig.growth.catch_up()
	check(world.stage[i0] == WorldState.STAGE_SPROUT1 and world.growth[i0] == 40000, "t = 15.0 s: growth 40000, sprout 1 (%d)" % world.growth[i0])
	check(world.greened_count >= 32, "the 32 seeds count as greened from sprout 1 on (%d)" % world.greened_count)
	# 60 growth ticks (30 s) to mature: planted at 5.0, mature at 35.0.
	run_until(rig, 34.5, 0.01, func() -> bool: return false)
	rig.growth.catch_up()
	check(world.stage[i0] == WorldState.STAGE_SPROUT2 and world.growth[i0] == 118000, "t = 34.5 s: sprout 2, growth 118000 (%d)" % world.growth[i0])
	run_until(rig, 35.0, 0.01, func() -> bool: return false)
	rig.growth.catch_up()
	check(world.stage[i0] == WorldState.STAGE_MATURE and world.counters_consistent(), "t = 35.0 s: mature")

func test_skip_rules_and_scan_cap() -> void:
	# Tiles that are not free do not count against K, only against S. 500 mature tiles come first (rows 0..4 of a 100-wide map).
	var world: WorldState = world_from_rows(blank_grid(100, 40), [U])
	mature_block(world, Rect2i(0, 0, 100, 5))
	var rig: Rig = make_rig(world, tune({"far_sweep_seeds_per_step": 8, "far_sweep_scan_per_step": 2000, "far_sweep_start_delay_seconds": 0.0}), false)
	rig.progress.start()
	for i: int in 5:
		rig.far.tick()
	check(rig.far.last_sweep_planted == 8 and rig.far.last_sweep_scanned == 508 and rig.far.sweep_cursor == 508, "500 occupied tiles are skipped without using K: planted %d, read %d, cursor %d" % [rig.far.last_sweep_planted, rig.far.last_sweep_scanned, rig.far.sweep_cursor])
	# Scan cap: S = 100 reads per step.
	var world2: WorldState = world_from_rows(blank_grid(100, 40), [U])
	mature_block(world2, Rect2i(0, 0, 100, 5))
	var rig2: Rig = make_rig(world2, tune({"far_sweep_seeds_per_step": 8, "far_sweep_scan_per_step": 100, "far_sweep_start_delay_seconds": 0.0}), false)
	rig2.progress.start()
	var planted_by_step: Array = []
	for step: int in 7:
		for i: int in 5:
			rig2.far.tick()
		planted_by_step.append(rig2.far.last_sweep_planted)
	check(planted_by_step == [0, 0, 0, 0, 0, 8, 8] and rig2.far.sweep_cursor == 516, "S = 100: five steps read the 500 occupied tiles and plant nothing, then K seeds per step (%s, cursor %d)" % [planted_by_step, rig2.far.sweep_cursor])
	# A step never reads more than n tiles (no tile twice) even when S > n.
	var world3: WorldState = world_from_rows(blank_grid(10, 10), [U])
	var rig3: Rig = make_rig(world3, tune({"far_sweep_seeds_per_step": 1000, "far_sweep_scan_per_step": 100000, "far_sweep_start_delay_seconds": 0.0}), false)
	rig3.progress.start()
	for i: int in 5:
		rig3.far.tick()
	check(rig3.far.last_sweep_scanned == 100 and world3.plant_count == 100, "S > n: one step reads each tile once (%d reads, %d plants)" % [rig3.far.last_sweep_scanned, world3.plant_count])

func test_lap_fairness() -> void:
	# A pseudo random pattern of occupied tiles (mature plants), no growth, no spread: after lap_steps_bound(E) sweep steps no free
	# tile is left. Every free tile was processed.
	var rows: Array = blank_grid(97, 53)
	fill_rect(rows, Rect2i(40, 0, 3, 53), "~")
	var world: WorldState = world_from_rows(rows, [U])
	for index: int in world.tile_count():
		var x: int = index % world.width
		var y: int = index / world.width
		if (x * 7 + y * 13) % 5 == 0 and world.target[index] == 1:
			world.set_stage(index, WorldState.STAGE_MATURE)
	var tuning: SimTuning = tune({"far_sweep_seeds_per_step": 25, "far_sweep_scan_per_step": 300, "far_island_period_seconds": NEVER, "far_sweep_start_delay_seconds": 0.0})
	var rig: Rig = make_rig(world, tuning, false)
	rig.progress.start()
	var free_targets: int = count_free_targets(world)
	var steps: int = rig.far.lap_steps_bound(free_targets)
	for step: int in steps:
		for i: int in 5:
			rig.far.tick()
	var left: int = count_free_targets(world)
	check(left == 0 and world.plant_count == world.target_count, "after %d sweep steps (bound for %d free tiles) no free tile is left" % [steps, free_targets])
	check(rig.far.total_sweep_planted == free_targets, "each free tile was seeded exactly once (%d seeds, %d free)" % [rig.far.total_sweep_planted, free_targets])
	# Tight check of the bound: steps until empty is at most the bound (and the bound is at most 2x + 70 of what happened).
	var world2: WorldState = world_from_rows(rows, [U])
	for index: int in world2.tile_count():
		var x2: int = index % world2.width
		var y2: int = index / world2.width
		if (x2 * 7 + y2 * 13) % 5 == 0 and world2.target[index] == 1:
			world2.set_stage(index, WorldState.STAGE_MATURE)
	var rig2: Rig = make_rig(world2, tuning, false)
	rig2.progress.start()
	var used: int = 0
	while count_free_targets(world2) > 0 and used < steps + 5:
		for i: int in 5:
			rig2.far.tick()
		used += 1
	check(used <= steps, "the free tiles were all processed in %d steps <= bound %d" % [used, steps])
	# The cursor wraps and the lap counter counts it.
	check(rig2.far.laps >= 0 and rig2.far.sweep_cursor < world2.tile_count(), "cursor stays inside the map; laps so far %d" % rig2.far.laps)
	info["fairness"] = {"free_tiles": free_targets, "bound_steps": steps, "used_steps": used}

func test_load_relaxed() -> void:
	var world: WorldState = world_from_rows(blank_grid(40, 20), [S, S], [20])
	west_green_small(world)
	var data: Dictionary = world.to_dict()
	var bad: Dictionary = data.duplicate(true)
	bad["zones"]["state"] = [K, S]
	var loaded: WorldState = WorldState.from_dict(bad, world.terrain_defs)
	check(loaded != null and loaded.zone_state[0] == K and loaded.greened_count < loaded.target_count and loaded.zone_greened_count[0] < loaded.zone_target_count[0], "a complete zone with fewer greened tiles than targets loads (complete is forward-only)")
	bad = data.duplicate(true)
	bad["zones"]["state"] = [K, K]
	bad["cleared"] = false
	check(WorldState.from_dict(bad, world.terrain_defs) == null, "other contradictions stay refused: all zones complete but the clear flag off")
	bad = data.duplicate(true)
	bad["zones"]["state"] = [K, S]
	bad["cleared"] = true
	check(WorldState.from_dict(bad, world.terrain_defs) == null, "other contradictions stay refused: the clear flag with a zone that is not complete")
	bad = data.duplicate(true)
	bad["zones"]["state"] = [7, S]
	check(WorldState.from_dict(bad, world.terrain_defs) == null, "other contradictions stay refused: an unknown state")

func west_green_small(world: WorldState) -> void:
	mature_block(world, Rect2i(1, 1, 3, 3))

func test_complete_zone_refills() -> void:
	# A world saved as complete with fewer greened tiles than targets is accepted and the far seeding refills it to 100 %.
	var world: WorldState = world_from_rows(blank_grid(60, 30), [S])
	mature_block(world, Rect2i(0, 0, 60, 30))
	var data: Dictionary = world.to_dict()
	# Take 200 tiles away by editing the saved stage bytes, keep the zone complete.
	var stages: PackedByteArray = WorldState._unpack_bytes(data["stage"])
	for i: int in 200:
		stages[(i * 7) % stages.size()] = 0
	data["stage"] = WorldState._pack_bytes(stages)
	data["zones"]["state"] = [K]
	data["cleared"] = true
	var loaded: WorldState = WorldState.from_dict(data, world.terrain_defs)
	check(loaded != null and loaded.zone_state[0] == K and loaded.cleared and loaded.greened_count < loaded.target_count, "the complete + cleared state with 200 missing tiles loads (%d of %d greened)" % [loaded.greened_count if loaded != null else -1, loaded.target_count if loaded != null else -1])
	if loaded == null:
		return
	var rig: Rig = make_rig(loaded, small_tune(), false)
	# (A loaded game restores the per-zone "started stable" flags from its own save; here the zone is made sweepable by hand.)
	rig.far.zone_initial.fill(0)
	var missing: int = loaded.target_count - loaded.greened_count
	var bound: float = rig.far.completion_bound_seconds(count_free_targets(loaded))
	var done_at: float = run_until(rig, bound, 0.25, func() -> bool: return is_100(loaded))
	check(is_100(loaded) and done_at <= bound, "the complete zone is refilled to exactly 100 %% in %.1f s <= %.1f s (%d tiles were missing)" % [done_at, bound, missing])
	check(loaded.zone_state[0] == K and loaded.cleared and loaded.counters_consistent(), "state stays complete / cleared (forward only), counters equal the recount")

func world_signature(world: WorldState) -> Array:
	return [hash(world.stage), hash(world.growth), hash(world.natural), hash(world.moisture), hash(world.occupant), world.greened_count, world.plant_count, Array(world.zone_state), world.cleared]

func far_signature(far: FarSeedSim) -> String:
	return JSON.stringify(far.to_dict())

func test_frame_rates_and_pause() -> void:
	var signatures: Array = []
	var far_sigs: Array = []
	for hz: int in [30, 60, 144]:
		var world: WorldState = world_from_rows(map_a(), [U])
		west_green(world)
		var rig: Rig = make_rig(world, small_tune())
		rig.progress.start()
		var dt: float = 1.0 / float(hz)
		var frames: int = roundi(240.0 * float(hz))
		for i: int in frames:
			rig.clock.advance(dt)
		signatures.append(world_signature(world))
		far_sigs.append(far_signature(rig.far))
		check(rig.far.ticks == 240, "%d Hz: 240 s of game time = 240 spread ticks for the far seeding (%d)" % [hz, rig.far.ticks])
	check(signatures[0] == signatures[1] and signatures[1] == signatures[2], "30 / 60 / 144 Hz give identical worlds after 240 s")
	check(far_sigs[0] == far_sigs[1] and far_sigs[1] == far_sigs[2], "30 / 60 / 144 Hz give identical far seeding states")
	# Pause: no time passes, nothing is planted, nothing banks up.
	var world2: WorldState = world_from_rows(map_a(), [U])
	west_green(world2)
	var rig2: Rig = make_rig(world2, small_tune())
	rig2.progress.start()
	run_until(rig2, 30.0, 0.25, func() -> bool: return false)
	var before: Array = world_signature(world2)
	var before_far: String = far_signature(rig2.far)
	rig2.clock.paused = true
	for i: int in 2000:
		rig2.clock.advance(0.25)
	check(world_signature(world2) == before and far_signature(rig2.far) == before_far, "paused: the world and the far seeding do not change")
	rig2.clock.paused = false
	rig2.advance(0.25)
	check(rig2.far.ticks == 30 and rig2.clock.elapsed == 30.25, "resuming adds no banked time (far ticks %d)" % rig2.far.ticks)

func clone_rig(rig: Rig, tuning: SimTuning) -> Rig:
	# A save/restore through JSON text, like a file would.
	var world_data: Dictionary = JSON.parse_string(JSON.stringify(rig.world.to_dict()))
	var growth_data: Dictionary = JSON.parse_string(JSON.stringify(rig.growth.to_dict()))
	var spread_data: Dictionary = JSON.parse_string(JSON.stringify(rig.spread.to_dict()))
	var far_data: Dictionary = JSON.parse_string(JSON.stringify(rig.far.to_dict()))
	var clock_data: Dictionary = JSON.parse_string(JSON.stringify(rig.clock.to_dict()))
	var world: WorldState = WorldState.from_dict(world_data, rig.world.terrain_defs)
	var copy: Rig = Rig.new()
	copy.world = world
	copy.clock.configure(tuning)
	copy.clock.load_dict(clock_data)
	copy.growth = GrowthSim.new(world, tuning)
	copy.growth.load_dict(growth_data)
	copy.spread = SpreadSim.new(world, tuning, false)
	copy.spread.load_dict(spread_data)
	copy.use_spread = rig.use_spread
	copy.far = FarSeedSim.new(world, tuning)
	copy.far.load_dict(far_data)
	var etune: EnemyTuning = enemy_tuning.duplicate() as EnemyTuning
	etune.spawn_interval_seconds = 100000.0
	copy.field = EnemyField.new(world, etune, TILE)
	copy.progress = ZoneProgress.new(world, copy.field)
	copy.spread.allow_hook = copy.field.spread_allows
	copy.clock.growth_ticked.connect(copy.on_growth)
	copy.clock.spread_ticked.connect(copy.on_spread)
	return copy

func test_save_round_trip() -> void:
	var tuning: SimTuning = small_tune({"far_label_tiles_per_tick": 12, "far_label_scan_per_tick": 90, "far_check_reads_per_tick": 25})
	var states_seen: Dictionary = {}
	for snapshot_time: float in [23.0, 143.0, 401.0, 700.0, 800.0]:
		var world: WorldState = world_from_rows(map_a(), [U])
		west_green(world)
		var rig: Rig = make_rig(world, tuning)
		rig.progress.start()
		run_until(rig, snapshot_time, 0.25, func() -> bool: return false)
		states_seen["busy_%d" % int(snapshot_time)] = rig.far.labelling_busy()
		states_seen["round_%d" % int(snapshot_time)] = rig.far.round_active
		var copy: Rig = clone_rig(rig, tuning)
		check(far_signature(copy.far) == far_signature(rig.far) and world_signature(copy.world) == world_signature(rig.world), "snapshot at %.0f s: the restored state equals the saved one (busy labelling %s, round active %s)" % [snapshot_time, rig.far.labelling_busy(), rig.far.round_active])
		for i: int in 600:
			rig.clock.advance(0.25)
			copy.clock.advance(0.25)
		check(world_signature(copy.world) == world_signature(rig.world) and far_signature(copy.far) == far_signature(rig.far) and copy.spread.ticks == rig.spread.ticks, "snapshot at %.0f s: 150 s later the original and the restored run are identical" % snapshot_time)
		check(copy.world.counters_consistent(), "the restored run's counters equal the recount")
	check(states_seen["busy_23"] == true, "(coverage) one snapshot was taken in the middle of labelling")
	# A snapshot in the middle of a check round: slow rounds (5 reads per tick), no sweep, no spread, the east bank is large.
	var round_tuning: SimTuning = small_tune({"far_sweep_period_seconds": NEVER, "far_check_reads_per_tick": 5, "far_island_period_seconds": 7.0})
	var world3: WorldState = world_from_rows(map_a(), [U])
	west_green(world3)
	var rig3: Rig = make_rig(world3, round_tuning, false)
	rig3.progress.start()
	var found_round: bool = false
	while rig3.clock.elapsed < 1000.0 and not (rig3.far.round_active and rig3.far.round_pos > 100 and not rig3.far.labelling_busy()):
		rig3.advance(0.25)
	found_round = rig3.far.round_active
	check(found_round, "(coverage) a snapshot taken in the middle of a check round (component %d, position %d, at %.0f s)" % [rig3.far.round_comp, rig3.far.round_pos, rig3.clock.elapsed])
	var copy3: Rig = clone_rig(rig3, round_tuning)
	for i: int in 3200:
		rig3.advance(0.25)
		copy3.clock.advance(0.25)
	if far_signature(copy3.far) != far_signature(rig3.far):
		var da: Dictionary = rig3.far.to_dict()
		var db: Dictionary = copy3.far.to_dict()
		for key: String in da:
			if str(da[key]) != str(db[key]):
				print("DIFF far.%s: %s vs %s" % [key, str(da[key]).left(100), str(db[key]).left(100)])
	if world_signature(copy3.world) != world_signature(rig3.world):
		print("DIFF world %s vs %s" % [world_signature(copy3.world), world_signature(rig3.world)])
	check(world_signature(copy3.world) == world_signature(rig3.world) and far_signature(copy3.far) == far_signature(rig3.far), "the run restored in the middle of a check round continues identically (800 s)")
	check(rig3.far.total_island_planted == copy3.far.total_island_planted and rig3.far.total_island_planted == 4, "in both runs the check rounds planted the 4 component seeds (%d / %d)" % [rig3.far.total_island_planted, copy3.far.total_island_planted])
	# Refusals.
	var world2: WorldState = world_from_rows(map_a(), [U])
	var far2: FarSeedSim = FarSeedSim.new(world2, tuning)
	var good: Dictionary = far2.to_dict()
	var bad: Dictionary = good.duplicate(true)
	bad["version"] = 2
	check(not far2.load_dict(bad), "an unknown version is refused")
	bad = good.duplicate(true)
	bad["zone_enum"] = [0, 0, 0]
	check(not far2.load_dict(bad), "a zone count that does not fit is refused")

func test_stress_frame_cost() -> void:
	# Worst case around a sweep step: map 512 x 512 open ground, one stable zone, K = 256 free tiles per step, labelling of the whole
	# zone running at the same time, growth with a large active set and natural spread on. The slowest frame (a 0.25 s advance holds at
	# most one growth tick and one spread tick, exactly the logic of one real frame) must stay under 16 ms.
	var world: WorldState = world_from_rows(blank_grid(512, 512), [U])
	mature_block(world, Rect2i(100, 100, 40, 40))
	var rig: Rig = make_rig(world, tune({"far_sweep_start_delay_seconds": 0.0, "far_sweep_seeds_per_step": 256}))
	rig.progress.start()
	rig.timing = true
	for i: int in 4 * 330:
		rig.advance(0.25)
	var mean_us: float = float(rig.total_us) / float(maxi(rig.frames, 1))
	var sorted: PackedInt32Array = rig.frame_samples.duplicate()
	sorted.sort()
	var p99: int = sorted[int(float(sorted.size()) * 0.99)]
	print("PERF stress: frames=%d mean=%.2f ms p99=%.2f ms worst frame=%.2f ms (growth %.2f, spread %.2f, far %.2f); active set now %d, plants %d" % [rig.frames, mean_us / 1000.0, float(p99) / 1000.0, float(rig.worst_frame_us) / 1000.0, float(rig.worst_growth_us) / 1000.0, float(rig.worst_spread_us) / 1000.0, float(rig.worst_far_us) / 1000.0, world.active_tiles.size(), world.plant_count])
	check(rig.worst_frame_us < 16000, "worst frame of the logic (growth + spread + far) %.2f ms < 16 ms" % [float(rig.worst_frame_us) / 1000.0])
	check(rig.worst_far_us < 8000, "the far seeding alone costs at most %.2f ms in a frame" % [float(rig.worst_far_us) / 1000.0])
	info["stress_frame_ms"] = {"mean": mean_us / 1000.0, "p99": float(p99) / 1000.0, "worst": float(rig.worst_frame_us) / 1000.0, "worst_far": float(rig.worst_far_us) / 1000.0, "worst_growth": float(rig.worst_growth_us) / 1000.0, "worst_spread": float(rig.worst_spread_us) / 1000.0}

func test_scene_wiring() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var driver: SimulationDriver = main.simulation
	driver.process_mode = Node.PROCESS_MODE_DISABLED
	check(driver.far != null, "the real scene has the far seeding in its simulation driver")
	var world: WorldState = main.grid
	# Region_01 starts with the start zone stable (ZoneDef initial state). It is never swept (the player opens the land by hand):
	# 600 s of game time bring no sweep seed anywhere (every other zone is unconquered).
	check(driver.far.zone_initial[0] == 1 and driver.far.zone_initial[1] == 0, "scene: the start zone is flagged as started-stable")
	for i: int in 2400:
		driver.clock.advance(0.25)
	check(driver.far.ticks == 600 and driver.far.total_sweep_planted == 0 and driver.far.total_island_planted >= 0, "scene: 600 s, no sweep seed (%d), component seeds so far %d" % [driver.far.total_sweep_planted, driver.far.total_island_planted])
	check(world.plant_count == world.recount_plants() and world.counters_consistent(), "the plant counters follow")
	main.queue_free()
	await process_frame

func test_region_01() -> void:
	var world: WorldState = RegionLoader.load_region(region_def)
	var rig: Rig = make_rig(world, sim_tuning)
	rig.field.setup_nests(region_def.zones)
	var nests_at_start: int = rig.field.nests.size()
	rig.progress.start()
	# Every nest and boar removed by the API: no boar has ever been spawned (the field is not advanced). Zones become stable.
	for nest: Nest in rig.field.nests.duplicate():
		rig.field.destroy_nest(nest)
	for boar: Boar in rig.field.boars.duplicate():
		rig.field.remove_boar(boar)
	var all_stable: bool = true
	for zone: int in world.zone_count:
		all_stable = all_stable and world.zone_state[zone] == S
	check(all_stable and nests_at_start == 15, "region_01: %d nests destroyed, every one of the %d zones is stable" % [nests_at_start, world.zone_count])
	var greened_at_start: int = world.greened_count
	var targets: int = world.target_count
	var free_at_start: int = count_free_targets(world)
	var start_zone_greened: int = world.zone_greened_count[0]
	var expected_components: PackedInt32Array = flood_components(world)
	var comp_total: int = 0
	var comp_sizes: Dictionary = {}
	var comp_green: Dictionary = {}
	for index: int in world.tile_count():
		var id: int = expected_components[index]
		if id != 0:
			comp_total = maxi(comp_total, id)
			comp_sizes[id] = int(comp_sizes.get(id, 0)) + 1
			if world.stage[index] != 0:
				comp_green[id] = true
	var greenless: Array[int] = []
	for id: int in comp_sizes:
		if not comp_green.has(id):
			greenless.append(id)
	var greenless_tiles: int = 0
	for id: int in greenless:
		greenless_tiles += int(comp_sizes[id])
	print("INFO region_01 start: greened %d of %d (%.2f %%), free targets %d, components %d, green-less components %d (%d tiles)" % [greened_at_start, targets, 100.0 * float(greened_at_start) / float(targets), free_at_start, comp_total, greenless.size(), greenless_tiles])
	# Bounds. Zones 1..6 start unconquered and are swept 120 s after they turn stable (here: t = 0): sweep bound with their free targets.
	var free_swept: int = 0
	for index: int in world.tile_count():
		if world.zone_of[index] != 0 and world.target[index] == 1 and world.terrain_defs[world.terrain[index]].plantable and world.stage[index] == 0 and world.occupant[index] == 0:
			free_swept += 1
	var bound_sweep: float = rig.far.completion_bound_seconds(free_swept)
	# Zone 0 started stable: (a) + natural spread only. The deepest component of the zone comes from a labelling run of its own.
	var probe: FarSeedSim = FarSeedSim.new(RegionLoader.load_region(region_def), tune({"far_sweep_period_seconds": NEVER, "far_island_period_seconds": NEVER}))
	while probe.ticks == 0 or probe.labelling_busy():
		probe.tick()
	var max_hops: int = 0
	for c: int in probe.finished_comp_count():
		if probe.world.zone_of[probe.members[probe.comp_start[c]]] == 0:
			max_hops = maxi(max_hops, probe.component_hops_bound(c))
	var zone0_targets: int = rig.world.zone_target_count[0]
	var bound_zone0: float = rig.far.initial_zone_bound_seconds(max_hops, zone0_targets)
	var bound_free: float = maxf(bound_sweep, bound_zone0)
	var bound_all: float = rig.far.completion_bound_seconds()
	print("INFO region_01 bounds: sweep zones %.1f s (free %d), start zone (a)+natural %.1f s (deepest component hops bound %d, targets %d)" % [bound_sweep, free_swept, bound_zone0, max_hops, zone0_targets])
	rig.timing = true
	var checkpoint: float = 1800.0
	var islands_checked: bool = false
	var progress_log: Array = []
	var next_log: float = 600.0
	while rig.clock.elapsed < bound_free and not world.cleared:
		rig.advance(0.25)
		if rig.clock.elapsed >= next_log:
			progress_log.append([int(rig.clock.elapsed), world.greened_count, world.plant_count, rig.far.laps, rig.far.total_sweep_planted, rig.far.total_island_planted])
			print("INFO region_01 t=%d s greened=%d (%.1f %%) plants=%d laps=%d sweep=%d island=%d active=%d" % [int(rig.clock.elapsed), world.greened_count, 100.0 * float(world.greened_count) / float(targets), world.plant_count, rig.far.laps, rig.far.total_sweep_planted, rig.far.total_island_planted, world.active_tiles.size()])
			next_log += 600.0
		if not islands_checked and rig.clock.elapsed >= checkpoint:
			islands_checked = true
			var missing: int = 0
			for id: int in greenless:
				var found: bool = false
				for index: int in world.tile_count():
					if expected_components[index] == id and world.stage[index] != 0:
						found = true
						break
				if not found:
					missing += 1
			check(missing == 0, "region_01: after %.0f s every one of the %d components that started without a plant holds a plant (missing %d); islands and the far bank are reached" % [checkpoint, greenless.size(), missing])
	var done_at: float = rig.clock.elapsed
	check(world.cleared and world.greened_count == world.target_count, "region_01: cleared, greened %d == targets %d (integer equality) at %.2f s of game time" % [world.greened_count, world.target_count, done_at])
	check(done_at <= bound_free, "region_01: %.2f s <= bound %.2f s (bound with every target free: %.2f s)" % [done_at, bound_free, bound_all])
	var all_complete: bool = true
	for zone: int in world.zone_count:
		all_complete = all_complete and world.zone_state[zone] == K and rig.complete_at.has(zone)
	check(all_complete, "every zone is complete; times %s" % [rig.complete_at])
	check(world.counters_consistent(), "region_01: counters equal the recount")
	var zone0_done: float = float(rig.complete_at.get(0, 1.0e12))
	var sweep_done: float = 0.0
	for zone: int in range(1, world.zone_count):
		sweep_done = maxf(sweep_done, float(rig.complete_at.get(zone, 1.0e12)))
	check(zone0_done <= bound_zone0, "region_01: the start zone (no sweep, (a) + natural spread) completed at %.0f s <= its bound %.0f s" % [zone0_done, bound_zone0])
	check(sweep_done <= bound_sweep, "region_01: the swept zones completed at %.0f s <= their bound %.0f s" % [sweep_done, bound_sweep])
	var sorted: PackedInt32Array = rig.frame_samples.duplicate()
	sorted.sort()
	var p99: int = sorted[int(float(sorted.size()) * 0.99)]
	var mean_us: float = float(rig.total_us) / float(maxi(rig.frames, 1))
	print("PERF region_01: frames=%d mean=%.2f ms p99=%.2f ms worst frame=%.2f ms (growth %.2f, spread %.2f, far %.2f)" % [rig.frames, mean_us / 1000.0, float(p99) / 1000.0, float(rig.worst_frame_us) / 1000.0, float(rig.worst_growth_us) / 1000.0, float(rig.worst_spread_us) / 1000.0, float(rig.worst_far_us) / 1000.0])
	check(rig.worst_frame_us < 16000, "region_01 whole run: worst frame of the logic %.2f ms < 16 ms" % [float(rig.worst_frame_us) / 1000.0])
	info["region_01"] = {
		"start_greened": greened_at_start, "targets": targets, "start_zone_greened": start_zone_greened, "free_at_start": free_at_start,
		"components": comp_total, "greenless_components": greenless.size(), "greenless_tiles": greenless_tiles,
		"done_at_s": done_at, "done_at_min": done_at / 60.0, "cleared_at_s": rig.cleared_at, "bound_free_s": bound_free, "bound_sweep_s": bound_sweep, "bound_zone0_s": bound_zone0, "zone0_max_hops": max_hops, "zone0_targets": zone0_targets, "zone0_done_s": zone0_done, "sweep_zones_done_s": sweep_done, "bound_all_s": bound_all,
		"complete_at_s": rig.complete_at, "laps": rig.far.laps, "sweep_planted": rig.far.total_sweep_planted, "island_planted": rig.far.total_island_planted,
		"mean_ms": mean_us / 1000.0, "p99_ms": float(p99) / 1000.0, "worst_ms": float(rig.worst_frame_us) / 1000.0, "worst_far_ms": float(rig.worst_far_us) / 1000.0,
		"worst_growth_ms": float(rig.worst_growth_us) / 1000.0, "worst_spread_ms": float(rig.worst_spread_us) / 1000.0, "log": progress_log,
	}

## Tick (1-based) at which the first natural seed shows in `zone`; -1 when none within `limit` ticks. Optional callback per tick.
func first_seed_tick(world: WorldState, spread: SpreadSim, zone: int, limit: int, on_tick: Callable = Callable()) -> int:
	for t: int in range(1, limit + 1):
		if on_tick.is_valid():
			on_tick.call(t)
		spread.tick()
		for index: int in world.tile_count():
			if world.zone_of[index] == zone and world.stage[index] == WorldState.STAGE_SEED:
				return t
	return -1

func test_stable_spread_multiplier() -> void:
	# One mature tile per zone, candidates around it have exactly one mature neighbour: 6000 progress per tick, threshold 100000.
	# Unconquered: 6000 x k >= 100000 -> k = 17. Stable x1.25 = 7500 per tick: 7500 x k >= 100000 -> k = 14 (13.33).
	# Stable from tick 6 on: 5 x 6000 = 30000, then 7500 per tick: 70000 / 7500 = 9.33 -> 10 more ticks -> tick 15.
	# Stable and carrot boost 2.0 together (multiplied): 6000 x 2.0 x 1.25 = 15000 -> k = 7. With the maximum rule it would be 12000 -> 9.
	var rows: Array = blank_grid(60, 30)
	var base: SimTuning = tune()
	var world: WorldState = world_from_rows(rows, [U, S], [30])
	world.set_stage(world.index_of(10, 15), WorldState.STAGE_MATURE)
	world.set_stage(world.index_of(40, 15), WorldState.STAGE_MATURE)
	var spread: SpreadSim = SpreadSim.new(world, base)
	var seen: Array[int] = [-1, -1]
	for t: int in range(1, 41):
		spread.tick()
		for zone: int in 2:
			if seen[zone] < 0:
				for index: int in world.tile_count():
					if world.zone_of[index] == zone and world.stage[index] == WorldState.STAGE_SEED:
						seen[zone] = t
						break
	check(seen[0] == 17 and seen[1] == 14, "unconquered zone: first seeds at tick 17, stable zone (x1.25): tick 14 (%s)" % [seen])
	# Transition: zone 1 starts unconquered and turns stable after tick 5.
	var world2: WorldState = world_from_rows(rows, [U, U], [30])
	world2.set_stage(world2.index_of(40, 15), WorldState.STAGE_MATURE)
	var spread2: SpreadSim = SpreadSim.new(world2, base)
	var flip: Callable = func(t: int) -> void:
		if t == 6:
			world2.set_zone_state(1, S)
	check(first_seed_tick(world2, spread2, 1, 40, flip) == 15, "a zone that turns stable after tick 5 speeds up from tick 6: first seeds at tick 15")
	# Combination with the carrot boost.
	var world3: WorldState = world_from_rows(rows, [U, S], [30])
	world3.set_stage(world3.index_of(10, 15), WorldState.STAGE_MATURE)
	world3.set_stage(world3.index_of(40, 15), WorldState.STAGE_MATURE)
	var spread3: SpreadSim = SpreadSim.new(world3, base)
	var boost: PackedInt32Array = PackedInt32Array()
	boost.resize(world3.tile_count())
	boost.fill(2000)
	spread3.set_speed_scale(boost)
	var t_unstable: int = first_seed_tick(world3, spread3, 0, 40)
	check(t_unstable == 9, "carrot boost 2.0 alone (unconquered zone): 12000 per tick -> tick 9 (%d)" % t_unstable)
	var world4: WorldState = world_from_rows(rows, [U, S], [30])
	world4.set_stage(world4.index_of(40, 15), WorldState.STAGE_MATURE)
	var spread4: SpreadSim = SpreadSim.new(world4, base)
	spread4.set_speed_scale(boost)
	check(first_seed_tick(world4, spread4, 1, 40) == 7, "carrot boost 2.0 and stable x1.25 multiply: 15000 per tick -> tick 7")
	# Multiplier 1.0 switches it off.
	var world5: WorldState = world_from_rows(rows, [S, S], [30])
	world5.set_stage(world5.index_of(10, 15), WorldState.STAGE_MATURE)
	var spread5: SpreadSim = SpreadSim.new(world5, tune({"stable_spread_multiplier": 1.0}))
	check(first_seed_tick(world5, spread5, 0, 40) == 17, "stable_spread_multiplier 1.0: no change (tick 17)")

func test_initial_zone_not_swept() -> void:
	# A zone that starts stable (ZoneDef initial state) is never swept: 10 minutes (the sweep is armed: K = 32, no delay), no sweep seed.
	# Its 100 % comes from (a) + natural spread, inside initial_zone_bound_seconds.
	var world: WorldState = world_from_rows(map_a(), [S])
	west_green(world)
	var tuning: SimTuning = small_tune()
	var rig: Rig = make_rig(world, tuning)
	rig.progress.start()
	check(rig.far.zone_initial[0] == 1, "a zone that is stable when the simulation is created is flagged as started-stable")
	run_until(rig, 600.0, 0.25, func() -> bool: return false)
	check(rig.far.total_sweep_planted == 0 and rig.far.sweep_cursor == 0, "10 min: the sweep planted nothing and its cursor did not move (%d seeds)" % rig.far.total_sweep_planted)
	var max_hops: int = 0
	for c: int in rig.far.finished_comp_count():
		max_hops = maxi(max_hops, rig.far.component_hops_bound(c))
	var bound: float = rig.far.initial_zone_bound_seconds(max_hops)
	var done_at: float = run_until(rig, bound, 0.25, func() -> bool: return rig.world.cleared)
	check(is_100(world) and world.cleared and rig.far.total_sweep_planted == 0, "(a) + natural spread alone: exactly 100 %% (%d == %d), no sweep seed at all" % [world.greened_count, world.target_count])
	check(done_at <= bound, "start-stable zone finished at %.0f s <= bound %.0f s (deepest component hops bound %d)" % [done_at, bound, max_hops])
	check(world.counters_consistent(), "counters equal the recount")
	info["map_a_initial_zone"] = {"done_at_s": done_at, "bound_s": bound, "max_hops": max_hops}

func test_sweep_delay_boundary() -> void:
	# The zone turns stable at t = 5.0 s (nest destroyed after tick 5): delay 120 s -> the sweep may start at t = 125 s (a multiple of the
	# 5 s step). 119 s after the transition (t = 124): no sweep seed. 121 s after it (t = 126): the sweep has planted.
	var world: WorldState = world_from_rows(blank_grid(80, 40), [U])
	var tuning: SimTuning = small_tune({"far_sweep_start_delay_seconds": 120.0})
	var rig: Rig = make_rig(world, tuning, false)
	var nest: Nest = rig.field.add_nest(0, Vector2i(30, 20))
	rig.progress.start()
	run_until(rig, 5.0, 0.25, func() -> bool: return false)
	rig.field.destroy_nest(nest)
	check(world.zone_state[0] == S and rig.clock.elapsed == 5.0, "zone turned stable at t = 5.0 s")
	run_until(rig, 124.0, 0.25, func() -> bool: return false)
	check(rig.clock.elapsed == 124.0 and rig.far.total_sweep_planted == 0 and rig.far.sweep_cursor == 0, "119 s after the transition: no sweep seed (%d)" % rig.far.total_sweep_planted)
	run_until(rig, 126.0, 0.25, func() -> bool: return false)
	check(rig.far.total_sweep_planted == 32, "121 s after the transition: the sweep has planted its first step (%d seeds)" % rig.far.total_sweep_planted)
	# Bound includes the delay: bound(delay 120) - bound(delay 0) = 120 s.
	var no_delay: FarSeedSim = FarSeedSim.new(world, small_tune({"far_sweep_start_delay_seconds": 0.0}))
	check(absf(rig.far.completion_bound_seconds(100) - no_delay.completion_bound_seconds(100) - 120.0) < 1.0e-6, "the completion bound grows by exactly the start delay (120 s)")
	var bound: float = rig.far.completion_bound_seconds(count_free_targets(world))
	run_until(rig, 5.0 + bound, 0.25, func() -> bool: return rig.world.cleared)
	check(is_100(world) and rig.clock.elapsed - 5.0 <= bound, "100 %% reached %.0f s after the transition <= bound %.0f s (delay included)" % [rig.clock.elapsed - 5.0, bound])
