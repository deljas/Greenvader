extends SceneTree
## P1-03 headless checks: growth cycle, moisture, active set, seed production, caps, frame-rate independence,
## pause, save structure, performance, and the real-scene flow driven only by engine-internal input injection.
## Run: Godot --headless --path <project> --script res://tests/p1/p1_03_checks.gd
## Expected values come from the ticket / parent design, not from the implementation's formulas:
##   growth tick 0.5 s; dry seed -> mature about 60 s; fully wet about 30 s (speed factor 1.0 dry .. 2.0 wet, linear);
##   moisture falls 2 per second; stages seed -> sprout 1 -> sprout 2 -> mature at equal thirds of the way;
##   greened from sprout 1 on; production: tiles near the player * rate * interval, <= 3 per tick, plants <= 20 on the
##   ground, the seed source's 3 slots are never taken.
## Everything else is brute-force recounts written here.

const REGION_PATH: String = "res://data/region_01.tres"
const TILE: int = 4
const OUT: String = "res://evidence/p1/p1-05/independent/reg/self/"

var failures: int = 0
var checks: int = 0
var region_def: RegionDef
var sim_tuning: SimTuning
var play_tuning: PlayTuning
var perf: Dictionary = {}

class Rig:
	extends RefCounted
	var clock: SimClock = SimClock.new()
	var growth: GrowthSim

	func _init(world: WorldState, tuning: SimTuning) -> void:
		clock.configure(tuning)
		growth = GrowthSim.new(world, tuning)
		clock.growth_ticked.connect(func(_index: int) -> void: growth.tick())

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
	play_tuning = load("res://data/play_tuning.tres") as PlayTuning
	check(region_def != null and sim_tuning != null and play_tuning != null, "region, sim tuning and play tuning load")
	test_tuning_values()
	test_growth_timing()
	test_growth_floor_and_hooks()
	test_greening_counts()
	test_moisture()
	test_active_set()
	test_mature_chunk_counts()
	test_production_counts()
	test_production_rates()
	test_caps_and_reservation()
	test_frame_rate_independence()
	test_save_structure()
	test_performance()
	await test_scene_flow()
	print("PERF " + JSON.stringify(perf))
	print("P1_03_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

# ---- helpers ------------------------------------------------------------------------------

func c8(color: Color) -> Vector3i:
	return Vector3i(roundi(color.r * 255.0), roundi(color.g * 255.0), roundi(color.b * 255.0))

func terrain_id(key: StringName) -> int:
	for def: TerrainDef in region_def.terrains:
		if def.key == key:
			return def.id
	return -1

func small_state(rows: Array) -> WorldState:
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

func blank(width: int, height: int) -> WorldState:
	var rows: Array = []
	for y: int in height:
		rows.append(".".repeat(width))
	return small_state(rows)

func new_play(state: WorldState, sources: Array[Vector2] = [], tuning: PlayTuning = null) -> PlayState:
	return PlayState.new(state, tuning if tuning != null else play_tuning, sim_tuning, TILE, sources)

func tile_centre(state: WorldState, index: int) -> Vector2:
	return Vector2((index % state.width + 0.5) * TILE, (index / state.width + 0.5) * TILE)

## Seconds (observed at 1/60 s steps) at which `index` first reaches each stage 1..4. Missing = -1.
func stage_times(state: WorldState, index: int, rig: Rig, max_seconds: float) -> Array[float]:
	var times: Array[float] = [-1.0, -1.0, -1.0, -1.0, -1.0]
	for i: int in roundi(max_seconds * 60.0):
		rig.clock.advance(1.0 / 60.0)
		var s: int = state.stage[index]
		for level: int in range(1, 5):
			if s >= level and times[level] < 0.0:
				times[level] = rig.clock.elapsed
		if times[4] >= 0.0:
			break
	return times

func brute_active_expected(state: WorldState) -> Dictionary:
	var expected: Dictionary = {}
	for index: int in state.tile_count():
		var s: int = state.stage[index]
		if (s >= 1 and s <= 3) or state.moisture[index] > 0:
			expected[index] = true
	return expected

func active_exact(state: WorldState) -> bool:
	var expected: Dictionary = brute_active_expected(state)
	var seen: Dictionary = {}
	for index: int in state.active_tiles:
		seen[index] = true
	return seen.size() == state.active_tiles.size() and sets_equal(seen, expected, state.active_tiles.size())

func sets_equal(a: Dictionary, b: Dictionary, listed: int) -> bool:
	if a.size() != b.size() or a.size() != listed:
		return false
	for key: Variant in a:
		if not b.has(key):
			return false
	return true

# ---- tuning -------------------------------------------------------------------------------------

func test_tuning_values() -> void:
	var t: SimTuning = sim_tuning
	check(t.growth_tick_seconds == 0.5, "tuning: growth tick every 0.5 s")
	check(t.moisture_growth_min > 0.0 and t.moisture_growth_max > t.moisture_growth_min, "tuning: moisture factor has a positive floor and rises with moisture")
	check(t.sprout1_growth < t.sprout2_growth and t.sprout2_growth < t.mature_growth and t.sprout1_growth > 0, "tuning: stage thresholds rise in order")
	check(t.mature_growth / t.base_growth_per_tick == 120 and absf(t.moisture_growth_max / t.moisture_growth_min - 2.0) < 1.0e-6, "tuning: 120 base ticks to mature (60 s dry) and wet speed is twice the dry speed")
	check(t.moisture_decay_per_tick == 1 and t.moisture_max == 100, "tuning: moisture 0..100 falling 1 per 0.5 s tick (2 per second)")
	var p: PlayTuning = play_tuning
	check(p.plant_production_interval_seconds == 2.0 and p.plant_production_radius_px == 160.0 and p.plant_fruit_max_per_tick == 3, "tuning: production every 2 s within 160 px, at most 3 per tick")
	check(p.plant_fruit_cap == 20 and p.plant_fruit_lifetime_seconds > 0.0 and p.pickup_total_cap - p.plant_fruit_cap >= p.source_fruit_cap, "tuning: plant fruits capped at 20 with a lifetime; the rest of the total keeps the source's 3 slots")

# ---- growth timing ------------------------------------------------------------------------------

func test_growth_timing() -> void:
	# No decay: pure speed comparison. Spec: dry 60 s, fully wet 30 s, half wet (factor 1.5) 40 s.
	var steady: SimTuning = sim_tuning.duplicate() as SimTuning
	steady.moisture_decay_per_tick = 0
	var state: WorldState = blank(16, 16)
	var dry: int = state.index_of(2, 2)
	var half: int = state.index_of(4, 2)
	var wet: int = state.index_of(6, 2)
	for index: int in [dry, half, wet]:
		state.set_stage(index, WorldState.STAGE_SEED)
	state.set_moisture(half, 50)
	state.set_moisture(wet, 100)
	var rig: Rig = Rig.new(state, steady)
	rig.clock.advance(0.0)
	# One shared run records all three tiles.
	var times: Dictionary = {dry: [-1.0, -1.0, -1.0, -1.0, -1.0], half: [-1.0, -1.0, -1.0, -1.0, -1.0], wet: [-1.0, -1.0, -1.0, -1.0, -1.0]}
	for i: int in 60 * 70:
		rig.clock.advance(1.0 / 60.0)
		for index: int in times:
			for level: int in range(1, 5):
				if state.stage[index] >= level and times[index][level] < 0.0:
					times[index][level] = rig.clock.elapsed
	var dry_t: Array = times[dry]
	var half_t: Array = times[half]
	var wet_t: Array = times[wet]
	check(absf(dry_t[4] - 60.0) < 0.1 and dry_t[4] > 0.0, "no water at all: the seed still becomes mature, after 60 s (%.2f s)" % dry_t[4])
	check(absf(wet_t[4] - 30.0) < 0.1, "full moisture: mature after 30 s (%.2f s)" % wet_t[4])
	check(absf(half_t[4] - 40.0) < 0.1, "half moisture (speed factor 1.5): mature after 40 s (%.2f s)" % half_t[4])
	check(wet_t[4] < half_t[4] and half_t[4] < dry_t[4], "the more water, the sooner mature (%.1f < %.1f < %.1f s)" % [wet_t[4], half_t[4], dry_t[4]])
	check(absf(dry_t[4] / wet_t[4] - 2.0) < 0.1, "dry / wet time ratio equals the speed ratio 2.0 (%.3f)" % (dry_t[4] / wet_t[4]))
	check(absf(dry_t[2] - 20.0) < 0.1 and absf(dry_t[3] - 40.0) < 0.1 and absf(dry_t[4] - 60.0) < 0.1, "dry stages arrive at one third, two thirds, full (sprout 1 %.1f s, sprout 2 %.1f s)" % [dry_t[2], dry_t[3]])
	check(dry_t[1] <= 0.02 and dry_t[2] < dry_t[3] and dry_t[3] < dry_t[4], "stages come in order seed -> sprout 1 -> sprout 2 -> mature")
	# With the real decay a tile wetted to 100 slows down as it dries. Expected from the spec, in ticks:
	var expected_ticks: int = 0
	var gained: float = 0.0
	while gained < 120.0 - 1.0e-9:
		var moisture_now: float = maxf(100.0 - 1.0 * expected_ticks, 0.0)
		gained += 1.0 + moisture_now / 100.0
		expected_ticks += 1
	var state2: WorldState = blank(16, 16)
	var drying: int = state2.index_of(3, 3)
	state2.set_stage(drying, WorldState.STAGE_SEED)
	state2.set_moisture(drying, 100)
	var rig2: Rig = Rig.new(state2, sim_tuning)
	var mature_at: float = stage_times(state2, drying, rig2, 70.0)[4]
	check(absf(mature_at - expected_ticks * 0.5) < 0.6 and expected_ticks > 60 and expected_ticks < 120, "a single splash (100) that dries out: mature at about %.1f s (observed %.2f s), between 30 s and 60 s" % [expected_ticks * 0.5, mature_at])
	# Sunlight hook and fertility factor.
	var state3: WorldState = blank(16, 16)
	var shade: int = state3.index_of(3, 3)
	var rich: int = state3.index_of(6, 3)
	state3.set_stage(shade, WorldState.STAGE_SEED)
	state3.set_stage(rich, WorldState.STAGE_SEED)
	state3.fertility[rich] = 100
	var rig3: Rig = Rig.new(state3, sim_tuning)
	rig3.growth.sunlight_provider = func(index: int) -> float: return 0.5 if index == shade else 1.0
	rig3.run(39.0, 60)
	check(state3.stage[rich] < WorldState.STAGE_MATURE, "fertility 100 (factor 1.5, expected 40 s): not mature yet at 39 s")
	rig3.run(2.0, 60)
	check(state3.stage[rich] == WorldState.STAGE_MATURE and state3.stage[shade] < WorldState.STAGE_MATURE, "fertility 100: mature at 41 s, while the half-lit tile (sunlight hook 0.5, expected 120 s) is not")
	rig3.run(78.0, 60)
	check(state3.stage[shade] < WorldState.STAGE_MATURE, "sunlight hook 0.5: still growing at 119 s")
	rig3.run(2.0, 60)
	check(state3.stage[shade] == WorldState.STAGE_MATURE, "sunlight hook 0.5: mature at 121 s (twice as slow)")

func test_growth_floor_and_hooks() -> void:
	# Even a degenerate tuning (factor floor 0) never stops growth: every tick adds at least 1.
	var degenerate: SimTuning = sim_tuning.duplicate() as SimTuning
	degenerate.moisture_growth_min = 0.0
	degenerate.moisture_growth_max = 0.0
	var state: WorldState = blank(8, 8)
	var index: int = state.index_of(2, 2)
	state.set_stage(index, WorldState.STAGE_SEED)
	var growth: GrowthSim = GrowthSim.new(state, degenerate)
	var before: int = state.growth[index]
	growth.tick()
	growth.tick()
	growth.tick()
	check(state.growth[index] - before >= 3, "growth speed floor stays positive: +%d in 3 ticks even with factor 0" % (state.growth[index] - before))
	var normal: GrowthSim = GrowthSim.new(blank(8, 8), sim_tuning)
	check(normal.moisture_factor(0) == 1.0 and normal.moisture_factor(100) == 2.0 and normal.moisture_factor(50) == 1.5 and normal.sunlight_factor(0) == 1.0, "moisture factor 1.0 / 1.5 / 2.0 at 0 / 50 / 100; sunlight factor is 1 without a provider")

# ---- greening counts --------------------------------------------------------------------------------

func test_greening_counts() -> void:
	var state: WorldState = blank(24, 24)
	var rig: Rig = Rig.new(state, sim_tuning)
	var tiles: Array[int] = [state.index_of(3, 3), state.index_of(8, 3), state.index_of(12, 9)]
	for index: int in tiles:
		state.set_stage(index, WorldState.STAGE_SEED)
	check(state.greened_count == 0 and state.counters_consistent(), "seeds alone do not count as greened")
	var first_greened_tick: int = -1
	var consistent: bool = true
	var seeds_zero_before: bool = true
	var stages_before_first: Array = []
	for tick: int in 130:
		var before: int = state.greened_count
		rig.growth.tick()
		consistent = consistent and state.counters_consistent() and state.recount_greened() == state.greened_count
		if first_greened_tick < 0 and state.greened_count > 0:
			first_greened_tick = tick + 1
			stages_before_first = [before]
		if state.greened_count == 0:
			seeds_zero_before = seeds_zero_before and tick + 1 < 40
	check(first_greened_tick == 40 and stages_before_first == [0], "greening count rises at the sprout 1 tick (tick %d = 20 s), not before" % first_greened_tick)
	check(consistent, "the differential counters equal a full recount after every one of 130 ticks")
	check(state.greened_count == 3 and state.mature_count == 3 and state.target_count - state.greened_count > 0, "three plants end at mature: greened 3 (a mature plant still counts once)")
	check(seeds_zero_before, "greened count was 0 throughout the seed phase")
	# Staged check of sprout 2 / mature not double-counting.
	var state2: WorldState = blank(8, 8)
	var rig2: Rig = Rig.new(state2, sim_tuning)
	state2.set_stage(state2.index_of(2, 2), WorldState.STAGE_SEED)
	var counts: Array[int] = []
	for tick: int in 120:
		rig2.growth.tick()
		if tick + 1 in [39, 40, 79, 80, 119, 120]:
			counts.append(state2.greened_count)
	check(counts == [0, 1, 1, 1, 1, 1], "greened count at ticks 39/40/79/80/119/120 is 0/1/1/1/1/1 %s" % [counts])

# ---- moisture ------------------------------------------------------------------------------------------

func test_moisture() -> void:
	var state: WorldState = blank(12, 12)
	var rig: Rig = Rig.new(state, sim_tuning)
	var wet: int = state.index_of(4, 4)
	state.set_moisture(wet, 100)
	var checkpoints: Dictionary = {}
	for tick: int in range(1, 111):
		rig.growth.tick()
		if tick in [2, 10, 50, 100, 101, 110]:
			checkpoints[tick] = state.moisture[wet]
	check(checkpoints == {2: 98, 10: 90, 50: 50, 100: 0, 101: 0, 110: 0}, "moisture falls 2 per second: 100 -> 98 after 1 s, 90 after 5 s, 50 after 25 s, 0 after 50 s and never below 0 %s" % [checkpoints])
	check(not state.active_flag[wet] == 1 and state.active_tiles.is_empty(), "a dried bare tile leaves the active set")
	var odd: int = state.index_of(5, 5)
	state.set_moisture(odd, 3)
	rig.growth.tick()
	rig.growth.tick()
	check(state.moisture[odd] == 1, "moisture 3 -> 1 after two ticks (no underflow of the byte)")
	rig.growth.tick()
	check(state.moisture[odd] == 0, "moisture 1 -> 0 clamps at 0")
	var water_tile: WorldState = small_state(["~~~~", "~~~~"])
	check(not water_tile.set_moisture(1, 50) and water_tile.moisture[1] == 0, "water tiles cannot hold moisture")

# ---- active set ----------------------------------------------------------------------------------------

func test_active_set() -> void:
	var state: WorldState = blank(512, 512)
	var rig: Rig = Rig.new(state, sim_tuning)
	check(state.active_tiles.is_empty() and state.mature_count == 0, "an empty map has an empty active set")
	rig.growth.tick()
	check(rig.growth.last_visited == 0, "a tick on a 512x512 map with nothing growing visits 0 tiles (not %d)" % state.tile_count())
	state.set_stage(state.index_of(100, 100), WorldState.STAGE_SEED)
	state.set_stage(state.index_of(300, 200), WorldState.STAGE_SEED)
	state.set_moisture(state.index_of(10, 10), 40)
	rig.growth.tick()
	check(rig.growth.last_visited == 3, "3 growing or wet tiles -> exactly 3 tiles visited (%d)" % rig.growth.last_visited)
	check(active_exact(state), "the active set equals the brute-force set of growing or wet tiles")
	# Landing through the PlayState keeps the set right; a splash on non-target tiles adds nothing.
	var play: PlayState = new_play(small_state(["....~~....", "....~~....", "....~~....", "....##....", ".........."]))
	play.land_seed(Vector2(8, 8))
	play.land_water(Vector2(8, 8))
	play.land_water(Vector2(5 * TILE, 5))
	check(active_exact(play.world) and play.world.active_tiles.size() > 0, "after seed and water landings the active set is exact (%d tiles)" % play.world.active_tiles.size())
	var includes_nontarget: bool = false
	for index: int in play.world.active_tiles:
		includes_nontarget = includes_nontarget or play.world.target[index] == 0
	check(not includes_nontarget, "water and building tiles never enter the active set")
	# Run to the end: everything matures, the set drains, matches brute force at every 10 s.
	var drain: Rig = Rig.new(play.world, sim_tuning)
	var exact_always: bool = true
	for step: int in 16:
		drain.run(10.0, 30)
		exact_always = exact_always and active_exact(play.world)
	check(exact_always, "the active set matched the brute-force set every 10 s over 160 s")
	check(play.world.active_tiles.is_empty() and play.world.mature_count > 0 and play.world.counters_consistent(), "when all plants are mature and dry, the active set is empty again")

func test_mature_chunk_counts() -> void:
	var state: WorldState = blank(70, 50)
	check(state.chunks_x == 5 and state.chunks_y == 4, "70x50 tiles -> 5x4 chunks of 16 tiles")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	for i: int in 600:
		state.set_stage(rng.randi_range(0, state.tile_count() - 1), rng.randi_range(0, 4))
	var per_chunk: PackedInt32Array = PackedInt32Array()
	per_chunk.resize(state.chunks_x * state.chunks_y)
	for y: int in state.height:
		for x: int in state.width:
			if state.stage[y * state.width + x] == WorldState.STAGE_MATURE:
				per_chunk[(y / 16) * state.chunks_x + x / 16] += 1
	check(per_chunk == state.mature_chunk_count and state.counters_consistent(), "per-chunk mature counts equal a brute-force recount after 600 random stage changes")

# ---- production: counts ---------------------------------------------------------------------------------

func brute_count(state: WorldState, centre: Vector2, radius: float) -> int:
	var total: int = 0
	for y: int in state.height:
		for x: int in state.width:
			if state.stage[y * state.width + x] == WorldState.STAGE_MATURE and Vector2((x + 0.5) * TILE, (y + 0.5) * TILE).distance_to(centre) <= radius:
				total += 1
	return total

func test_production_counts() -> void:
	var state: WorldState = blank(120, 100)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	for i: int in 3000:
		state.set_stage(rng.randi_range(0, state.tile_count() - 1), WorldState.STAGE_MATURE)
	state.debug_fill_stage(Rect2i(40, 30, 30, 30), WorldState.STAGE_MATURE)
	var producer: PlantProducer = PlantProducer.new(state, play_tuning, TILE)
	var ok: bool = true
	var detail: String = ""
	var samples: int = 0
	for i: int in 60:
		var centre: Vector2 = Vector2(rng.randf_range(-40, 520), rng.randf_range(-40, 440))
		var radius: float = rng.randf_range(10, 200) if i > 3 else 160.0
		var got: int = producer.gather(centre, radius)
		var want: int = brute_count(state, centre, radius)
		samples += 1
		if got != want:
			ok = false
			detail = "centre %s radius %.1f got %d want %d" % [centre, radius, got, want]
	check(ok, "the chunk-based count of mature tiles within a radius equals brute force for %d random circles %s" % [samples, detail])
	# Every tile_at(k) is a distinct mature tile inside the circle.
	var centre: Vector2 = Vector2(260, 200)
	var count: int = producer.gather(centre, 160.0)
	var seen: Dictionary = {}
	var valid: bool = true
	for k: int in count:
		var index: int = producer.tile_at(k)
		seen[index] = true
		valid = valid and index >= 0 and state.stage[index] == WorldState.STAGE_MATURE and tile_centre(state, index).distance_to(centre) <= 160.0
	check(count > 100 and seen.size() == count and valid, "tile_at(0..count-1) lists each of the %d mature tiles in range exactly once" % count)
	# Whole region mature: the count equals the circle's tile count.
	var all: WorldState = blank(100, 100)
	all.debug_fill_stage(Rect2i(0, 0, 100, 100), WorldState.STAGE_MATURE)
	var all_producer: PlantProducer = PlantProducer.new(all, play_tuning, TILE)
	check(all_producer.gather(Vector2(200, 200), 160.0) == brute_count(all, Vector2(200, 200), 160.0), "all-mature map: the circle count equals brute force")

func test_production_rates() -> void:
	var rate: float = play_tuning.plant_fruit_rate_per_tile_second
	var interval: float = play_tuning.plant_production_interval_seconds
	# (a) nothing mature near the player: nothing is ever produced.
	var empty: WorldState = blank(200, 200)
	empty.debug_fill_stage(Rect2i(150, 150, 40, 40), WorldState.STAGE_MATURE)
	var far_producer: PlantProducer = PlantProducer.new(empty, play_tuning, TILE)
	var far_pool: GroundPickups = GroundPickups.new(100000, 60.0)
	var far_total: int = 0
	for i: int in 2000:
		far_total += far_producer.produce(far_pool, Vector2(100, 100))
	check(far_total == 0 and far_pool.count() == 0, "no mature tile within 160 px of the player: 0 fruits in 2000 production ticks (the mature field is 200+ px away)")
	var seeds_only: WorldState = blank(100, 100)
	for i: int in 40:
		seeds_only.set_stage(i * 7 + 500, WorldState.STAGE_SPROUT2)
	var seed_producer: PlantProducer = PlantProducer.new(seeds_only, play_tuning, TILE)
	var seed_total: int = 0
	for i: int in 2000:
		seed_total += seed_producer.produce(far_pool, Vector2(100, 100))
	check(seed_total == 0, "seeds and sprouts produce nothing: 0 fruits in 2000 ticks")
	# (b) fruits scale with the number of mature tiles around (expected = tiles * rate * interval per tick).
	var results: Array[int] = []
	var expectations: Array[float] = []
	for size: int in [4, 8, 16]:
		var state: WorldState = blank(200, 200)
		state.debug_fill_stage(Rect2i(98 - size / 2, 98 - size / 2, size, size), WorldState.STAGE_MATURE)
		var producer: PlantProducer = PlantProducer.new(state, play_tuning, TILE)
		var pool: GroundPickups = GroundPickups.new(100000, 60.0)
		var total: int = 0
		var ticks: int = 4000
		for i: int in ticks:
			pool.items.clear()
			total += producer.produce(pool, Vector2(400, 400))
		results.append(total)
		expectations.append(float(size * size) * rate * interval * ticks)
	var near_expected: bool = true
	for i: int in 3:
		near_expected = near_expected and absf(float(results[i]) - expectations[i]) <= maxf(expectations[i] * 0.15, 6.0 * sqrt(expectations[i]))
	check(near_expected and results[0] < results[1] and results[1] < results[2], "fruits grow with the mature area: 16 / 64 / 256 tiles gave %s in 4000 ticks (expected %s)" % [results, expectations])
	# (c) per-tick limit and drop positions.
	var big: WorldState = blank(200, 200)
	big.debug_fill_stage(Rect2i(60, 60, 80, 80), WorldState.STAGE_MATURE)
	var big_producer: PlantProducer = PlantProducer.new(big, play_tuning, TILE)
	var per_tick_max: int = 0
	var all_on_mature: bool = true
	var in_range: bool = true
	var owner_ok: bool = true
	var centre: Vector2 = Vector2(400, 400)
	for i: int in 300:
		var pool: GroundPickups = GroundPickups.new(100000, 60.0)
		var dropped: int = big_producer.produce(pool, centre)
		per_tick_max = maxi(per_tick_max, dropped)
		for item: Dictionary in pool.items:
			var tile: Vector2i = Vector2i(floori(float(item["x"]) / TILE), floori(float(item["y"]) / TILE))
			var index: int = tile.y * big.width + tile.x
			all_on_mature = all_on_mature and big.stage[index] == WorldState.STAGE_MATURE
			in_range = in_range and tile_centre(big, index).distance_to(centre) <= 160.0 + 0.001
			owner_ok = owner_ok and int(item["owner"]) == GroundPickups.PLANT_OWNER_BASE + index and String(item["kind"]) == GroundPickups.KIND_SEED_FRUIT
	check(per_tick_max == 3, "a huge mature field produces the per-tick maximum of 3 and never more (max %d)" % per_tick_max)
	check(all_on_mature and in_range and owner_ok, "every fruit lies on a mature tile within 160 px of the player and is owned by 1000000 + tile index")
	# (d) determinism.
	var run_a: Array = []
	var run_b: Array = []
	for run_list: Array in [run_a, run_b]:
		var d: WorldState = blank(100, 100)
		d.debug_fill_stage(Rect2i(30, 30, 20, 20), WorldState.STAGE_MATURE)
		var pr: PlantProducer = PlantProducer.new(d, play_tuning, TILE)
		var pool: GroundPickups = GroundPickups.new(100000, 60.0)
		for i: int in 200:
			pr.produce(pool, Vector2(160, 160))
		run_list.append(pool.to_dict())
	check(run_a == run_b and run_a[0]["items"].size() > 20, "production is deterministic: two identical runs drop identical fruits (%d)" % run_a[0]["items"].size())

# ---- production: caps -----------------------------------------------------------------------------------

func test_caps_and_reservation() -> void:
	# GroundPickups level: plants stop at the plant cap; the source still gets its slots.
	var pool: GroundPickups = GroundPickups.new(24, 60.0, 21, 45.0)
	var plants: int = 0
	for i: int in 40:
		if pool.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(i, 0), GroundPickups.PLANT_OWNER_BASE + i):
			plants += 1
	check(plants == 21 and pool.count() == 21, "pool: 40 plant fruits offered, only 21 (plant cap) are accepted")
	var sources: int = 0
	for i: int in 6:
		if pool.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(i, 9), 1):
			sources += 1
	check(sources == 3 and pool.count() == 24, "pool: the seed source still gets its 3 slots while plants are saturated (got %d), total 24" % sources)
	pool.advance(44.0)
	check(pool.count() == 24, "pool: nothing expires before the lifetime")
	pool.advance(1.5)
	check(pool.count_plant_owned() == 0 and pool.count() == 3, "pool: plant fruits live 45 s (shorter than the source's 60 s), then the source fruits remain")
	# PlayState level: a large mature field near the player, the player is far from the source.
	var state: WorldState = blank(220, 220)
	state.debug_fill_stage(Rect2i(60, 60, 100, 100), WorldState.STAGE_MATURE)
	var src: Array[Vector2] = [Vector2(40, 40)]
	var play: PlayState = new_play(state, src)
	play.seeds = play_tuning.seed_max
	var player_at: Vector2 = Vector2(440, 440)
	var max_plants: int = 0
	var max_total: int = 0
	var max_source: int = 0
	var source_ready_while_saturated: bool = false
	for i: int in 60 * 120:
		play.advance(1.0 / 60.0, player_at)
		max_plants = maxi(max_plants, play.pickups.count_plant_owned())
		max_total = maxi(max_total, play.pickups.count())
		max_source = maxi(max_source, play.pickups.count_owned(1))
		if play.pickups.count_plant_owned() >= 20 and play.pickups.count_owned(1) == 3:
			source_ready_while_saturated = true
	check(max_plants == 20, "plant fruits fill up to 20 on the ground and never exceed it (max %d)" % max_plants)
	check(max_total <= 24, "the region-wide total never exceeds 24 (max %d)" % max_total)
	check(max_source == 3 and source_ready_while_saturated, "with 20 plant fruits lying around, the seed source still drops all 3 of its fruits (max %d, both at once: %s)" % [max_source, source_ready_while_saturated])
	var oldest_plant: float = 0.0
	for item: Dictionary in play.pickups.items:
		if GroundPickups.is_plant_owner(int(item["owner"])):
			oldest_plant = maxf(oldest_plant, float(item["age"]))
	check(oldest_plant < play_tuning.plant_fruit_lifetime_seconds, "no plant fruit is older than its lifetime (oldest %.1f s)" % oldest_plant)
	# Empty-handed recovery with a saturated field: zero seeds, walk to a source fruit.
	var recover: PlayState = new_play(state, src)
	recover.seeds = 0
	for i: int in 60 * 60:
		recover.advance(1.0 / 60.0, player_at)
	check(recover.pickups.count_owned(1) == 3 and recover.pickups.count_plant_owned() == 20, "zero seeds, plants saturated: the source's fruits (3) are on the ground for the player to collect")
	var item_pos: Vector2 = Vector2(float(recover.pickups.items[0]["x"]), float(recover.pickups.items[0]["y"]))
	var source_item: Dictionary = {}
	for item: Dictionary in recover.pickups.items:
		if int(item["owner"]) == 1:
			source_item = item
	recover.advance(1.0 / 60.0, Vector2(float(source_item["x"]) + 3.0, float(source_item["y"])))
	check(recover.seeds >= 1, "standing at the source fruit collects a seed from zero (seeds %d)" % recover.seeds)
	# Collecting a plant fruit gives a seed too; a full pouch leaves it on the ground.
	var collect: PlayState = new_play(blank(40, 40))
	collect.seeds = 3
	collect.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(60, 60), GroundPickups.PLANT_OWNER_BASE + 99)
	collect.advance(1.0 / 60.0, Vector2(62, 60))
	check(collect.seeds == 4 and collect.pickups.count() == 0, "a plant fruit is collected like any seed fruit: +1 seed")
	collect.seeds = 40
	collect.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(60, 60), GroundPickups.PLANT_OWNER_BASE + 99)
	collect.advance(1.0 / 60.0, Vector2(62, 60))
	check(collect.seeds == 40 and collect.pickups.count() == 1, "with a full pouch the plant fruit stays")
	# One fruit per tile at most.
	var one: PlayState = new_play(blank(40, 40))
	one.world.set_stage(one.world.index_of(10, 10), WorldState.STAGE_MATURE)
	var tuning_hot: PlayTuning = play_tuning.duplicate() as PlayTuning
	tuning_hot.plant_fruit_rate_per_tile_second = 100.0
	var hot: PlayState = new_play(one.world, [], tuning_hot)
	hot.seeds = 40
	for i: int in 60 * 20:
		hot.advance(1.0 / 60.0, Vector2(100, 100))
	check(hot.pickups.count() == 1, "a single mature tile holds one fruit at a time, even at a huge rate (%d)" % hot.pickups.count())

# ---- frame rate independence ----------------------------------------------------------------------------

func make_mixed_state() -> WorldState:
	var state: WorldState = blank(48, 48)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 21
	for i: int in 400:
		var index: int = rng.randi_range(0, state.tile_count() - 1)
		state.set_stage(index, WorldState.STAGE_SEED)
		if rng.randf() < 0.5:
			state.set_moisture(index, rng.randi_range(1, 100))
		if rng.randf() < 0.2:
			state.fertility[index] = rng.randi_range(0, 100)
	for i: int in 60:
		state.set_moisture(rng.randi_range(0, state.tile_count() - 1), rng.randi_range(1, 100))
	return state

func test_frame_rate_independence() -> void:
	var hashes: Dictionary = {}
	var growth_hashes: Dictionary = {}
	for hz: int in [30, 60, 144]:
		var state: WorldState = make_mixed_state()
		var rig: Rig = Rig.new(state, sim_tuning)
		var snapshots: Array = []
		for slice: int in 4:
			rig.run(15.0, hz)
			snapshots.append(hash(state.stage) ^ hash(state.moisture) ^ hash(state.growth.to_byte_array()))
		hashes[hz] = snapshots
		growth_hashes[hz] = [state.greened_count, state.mature_count, rig.clock.growth_ticks]
	check(hashes[30] == hashes[60] and hashes[60] == hashes[144], "same game time at 30 / 60 / 144 Hz: stage, moisture and growth identical at 15, 30, 45 and 60 s")
	check(growth_hashes[30] == growth_hashes[60] and growth_hashes[60] == growth_hashes[144] and growth_hashes[60][1] > 0 and growth_hashes[60][2] == 120, "greened, mature and tick counts equal at all rates %s" % [growth_hashes])
	# Production through the PlayState.
	var counts: Dictionary = {}
	for hz: int in [30, 60, 144]:
		var state: WorldState = blank(100, 100)
		state.debug_fill_stage(Rect2i(30, 30, 40, 40), WorldState.STAGE_MATURE)
		var play: PlayState = new_play(state)
		play.seeds = 40
		for i: int in roundi(60.0 * hz):
			play.advance(1.0 / hz, Vector2(200, 200))
		counts[hz] = [play.production_ticks, play.producer.total_produced]
	check(counts[30][0] == 30 and counts[60][0] == 30 and counts[144][0] == 30, "30 production ticks in 60 s at every frame rate %s" % [counts])
	check(counts[30] == counts[60] and counts[60] == counts[144] and counts[60][1] > 5, "the same number of fruits at 30 / 60 / 144 Hz (%d)" % counts[60][1])

# ---- save structure --------------------------------------------------------------------------------------

func test_save_structure() -> void:
	var state: WorldState = make_mixed_state()
	var rig: Rig = Rig.new(state, sim_tuning)
	rig.run(31.3, 60)
	var text: String = JSON.stringify({"world": state.to_dict(), "clock": rig.clock.to_dict()})
	var parsed: Dictionary = JSON.parse_string(text)
	var restored: WorldState = WorldState.from_dict(parsed["world"], state.terrain_defs)
	check(restored != null and restored.counters_consistent(), "the grown world restores from JSON with consistent counters")
	check(restored.growth == state.growth and restored.moisture == state.moisture and restored.stage == state.stage, "growth amounts, moisture and stages survive to_dict / JSON / from_dict")
	var original_active: Array = Array(state.active_tiles)
	var restored_active: Array = Array(restored.active_tiles)
	original_active.sort()
	restored_active.sort()
	check(original_active == restored_active and active_exact(restored), "the rebuilt active set equals the original set (%d tiles)" % restored_active.size())
	check(restored.mature_chunk_count == state.mature_chunk_count and restored.mature_count == state.mature_count, "mature chunk counts are rebuilt identically")
	var rig2: Rig = Rig.new(restored, sim_tuning)
	check(rig2.clock.load_dict(parsed["clock"]) and rig2.clock.growth_ticks == rig.clock.growth_ticks, "the clock phase is restored")
	rig.run(40.0, 60)
	rig2.run(40.0, 60)
	check(restored.stage == state.stage and restored.growth == state.growth and restored.moisture == state.moisture and restored.greened_count == state.greened_count, "original and restored worlds stay identical over 40 more seconds")
	# PlayState with production state.
	var world_a: WorldState = blank(100, 100)
	world_a.debug_fill_stage(Rect2i(30, 30, 20, 20), WorldState.STAGE_MATURE)
	var play: PlayState = new_play(world_a)
	play.seeds = 40
	for i: int in 60 * 33:
		play.advance(1.0 / 60.0, Vector2(160, 160))
	var json_copy: PlayState = new_play(world_a)
	check(json_copy.load_dict(JSON.parse_string(JSON.stringify(play.to_dict()))) and json_copy.production_ticks == play.production_ticks and json_copy.pickups.count() == play.pickups.count(), "production state also survives the JSON text form")
	var twin: PlayState = new_play(world_a)
	check(twin.load_dict(play.to_dict()) and twin.production_ticks == play.production_ticks and twin.producer.ticks == play.producer.ticks, "production state (ticks, time) loads back")
	for i: int in 60 * 20:
		play.advance(1.0 / 60.0, Vector2(160, 160))
		twin.advance(1.0 / 60.0, Vector2(160, 160))
	check(JSON.stringify(twin.pickups.to_dict()) == JSON.stringify(play.pickups.to_dict()) and twin.producer.total_produced == play.producer.total_produced, "the restored production continues exactly like the original over 20 s")

# ---- performance ---------------------------------------------------------------------------------------------

func median(values: Array[float]) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]

func test_performance() -> void:
	# P1-04: these measurements are about one tick over the whole 10,000-tile active set, so the per-tick limit is lifted (0 = no limit).
	var unlimited: SimTuning = sim_tuning.duplicate() as SimTuning
	unlimited.max_growth_tiles_per_tick = 0
	var state: WorldState = blank(512, 512)
	var rig: Rig = Rig.new(state, unlimited)
	# 10,000 growing tiles with mixed moisture.
	for y: int in range(100, 200):
		for x: int in range(100, 200):
			var index: int = state.index_of(x, y)
			state.set_stage(index, WorldState.STAGE_SEED)
			state.set_moisture(index, (x * 7 + y * 3) % 101)
	var times: Array[float] = []
	var change_tick_us: float = 0.0
	for tick: int in 130:
		var t0: int = Time.get_ticks_usec()
		rig.growth.tick()
		var elapsed_us: float = float(Time.get_ticks_usec() - t0)
		times.append(elapsed_us)
		if rig.growth.last_stage_changes > 5000:
			change_tick_us = maxf(change_tick_us, elapsed_us)
	perf["growth_tick_10k_median_ms"] = snappedf(median(times) / 1000.0, 0.01)
	perf["growth_tick_10k_max_ms"] = snappedf(times.max() / 1000.0, 0.01)
	check(median(times) < 20000.0, "10,000 growing tiles: median growth tick %.2f ms, worst %.2f ms" % [median(times) / 1000.0, times.max() / 1000.0])
	# Same tiles, dry and steady (no stage changes), measured on a fresh seed layer.
	var steady: WorldState = blank(512, 512)
	var steady_rig: Rig = Rig.new(steady, unlimited)
	for y: int in range(100, 200):
		for x: int in range(100, 200):
			steady.set_stage(steady.index_of(x, y), WorldState.STAGE_SEED)
	var steady_times: Array[float] = []
	var visited_at_30: int = 0
	var worst_change_us: float = 0.0
	var worst_changes: int = 0
	for tick: int in 125:
		var t0: int = Time.get_ticks_usec()
		steady_rig.growth.tick()
		var took: float = float(Time.get_ticks_usec() - t0)
		if tick == 29:
			visited_at_30 = steady_rig.growth.last_visited
		if steady_rig.growth.last_stage_changes > 0:
			if took > worst_change_us:
				worst_change_us = took
				worst_changes = steady_rig.growth.last_stage_changes
		else:
			steady_times.append(took)
	perf["growth_tick_10k_dry_steady_median_ms"] = snappedf(median(steady_times) / 1000.0, 0.01)
	perf["growth_tick_10k_dry_all_change_stage_ms"] = snappedf(worst_change_us / 1000.0, 0.01)
	perf["growth_tick_10k_dry_all_change_stage_tiles"] = worst_changes
	check(visited_at_30 == 10000, "the tick visited exactly the 10,000 growing tiles, not the 262,144 of the map (dry steady tick %.2f ms)" % (median(steady_times) / 1000.0))
	check(worst_changes == 10000 and steady.mature_count == 10000 and steady.active_tiles.is_empty(), "10,000 tiles change stage in one tick (%.2f ms) and all end mature and out of the active set" % (worst_change_us / 1000.0))
	# Empty map tick.
	var idle_times: Array[float] = []
	var idle: Rig = Rig.new(blank(512, 512), sim_tuning)
	for tick: int in 30:
		var t0: int = Time.get_ticks_usec()
		idle.growth.tick()
		idle_times.append(float(Time.get_ticks_usec() - t0))
	perf["growth_tick_idle_median_ms"] = snappedf(median(idle_times) / 1000.0, 0.03)
	check(idle.growth.last_visited == 0, "an idle 512x512 map: tick visits 0 tiles (%.3f ms)" % (median(idle_times) / 1000.0))
	# Production tick on a fully mature map.
	var full: WorldState = blank(512, 512)
	var t_fill: int = Time.get_ticks_usec()
	full.debug_fill_stage(Rect2i(0, 0, 512, 512), WorldState.STAGE_MATURE)
	perf["fill_262k_mature_ms"] = snappedf(float(Time.get_ticks_usec() - t_fill) / 1000.0, 1.0)
	var producer: PlantProducer = PlantProducer.new(full, play_tuning, TILE)
	var pool: GroundPickups = GroundPickups.new(24, 60.0, 20, 45.0)
	var prod_times: Array[float] = []
	var count: int = 0
	for tick: int in 40:
		var t0: int = Time.get_ticks_usec()
		producer.produce(pool, Vector2(1000 + tick * 3, 1000))
		prod_times.append(float(Time.get_ticks_usec() - t0))
		count = producer.last_mature_count
	perf["production_tick_full_map_median_ms"] = snappedf(median(prod_times) / 1000.0, 0.01)
	perf["production_tick_full_map_max_ms"] = snappedf(prod_times.max() / 1000.0, 0.01)
	check(count == brute_count(full, Vector2(1000 + 39 * 3, 1000), 160.0) and count > 4000, "fully mature map (262,144 tiles): the production tick counted %d tiles in range, equal to brute force" % count)
	check(median(prod_times) < 10000.0, "fully mature map: production tick median %.2f ms, worst %.2f ms" % [median(prod_times) / 1000.0, prod_times.max() / 1000.0])
	check(full.counters_consistent(), "262,144 mature tiles: counters equal a recount")

# ---- real scene flow (main.tscn, injected input) ---------------------------------------------------------------

var main: Node
var player: FlowerPlayer
var mouse_screen: Vector2 = Vector2(320, 180)
var landing_sets: Array = []
var landing_times: Array[float] = []

func send_key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func wait_frames(count: int) -> void:
	for i: int in count:
		await physics_frame
	await process_frame

func aim_at(world_point: Vector2) -> Vector2:
	var guess: Vector2 = world_point - player.position + Vector2(320, 180)
	var achieved: Vector2 = Vector2.ZERO
	for attempt: int in 3:
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = guess
		motion.global_position = guess
		mouse_screen = guess
		Input.parse_input_event(motion)
		await process_frame
		achieved = player.get_global_mouse_position()
		if achieved.distance_to(world_point) < 0.6:
			break
		guess += world_point - achieved
	return achieved

func click(button: MouseButton) -> void:
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.button_index = button
	down.pressed = true
	down.position = mouse_screen
	down.global_position = mouse_screen
	Input.parse_input_event(down)
	await process_frame
	var up: InputEventMouseButton = InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	up.position = mouse_screen
	up.global_position = mouse_screen
	Input.parse_input_event(up)
	await process_frame

func teleport(location: Vector2) -> void:
	player.simulation_position = location
	await wait_frames(3)

func find_wasteland_block(state: WorldState, size: int) -> Vector2i:
	var wasteland: int = terrain_id(&"wasteland")
	for cx: int in range(40, 150, 6):
		for cy: int in range(40, 470, 6):
			var ok: bool = true
			for y: int in range(cy - size / 2, cy + size / 2):
				for x: int in range(cx - size / 2, cx + size / 2):
					if state.terrain[state.index_of(x, y)] != wasteland or state.stage[state.index_of(x, y)] != 0:
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector2i(cx, cy)
	return Vector2i(-1, -1)

func record_landing(kind: String, _point: Vector2) -> void:
	if kind == "seed":
		landing_sets.append(Array(main.play.last_scatter))
		landing_times.append(main.simulation.clock.elapsed)

func test_scene_flow() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	await wait_frames(3)
	player = main.player
	var play: PlayState = main.play
	var state: WorldState = main.grid
	var clock: SimClock = main.simulation.clock
	check(main.simulation.growth != null and clock.growth_period == 0.5, "scene: the simulation driver owns the growth tick (0.5 s clock)")
	var block: Vector2i = find_wasteland_block(state, 20)
	check(block.x >= 0, "scene: found a 20x20 open wasteland block at tile %s" % block)
	var centre: Vector2 = (Vector2(block) + Vector2(0.5, 0.5)) * TILE
	await teleport(centre)
	main.projectile_view.landed.connect(record_landing)
	# P1-04: this flow is about the player-planted tiles, so natural spread is switched off here (it would add greened tiles).
	main.simulation.spread.allow_hook = func(_index: int) -> bool: return false
	var greened_before: int = state.greened_count
	# ---- seeds in with injected clicks; all four land at one spot so enough plants stand together
	var aim_point: Vector2 = centre + Vector2(40, 0)
	var seeds_before: int = play.seeds
	for i: int in 4:
		var got: Vector2 = await aim_at(aim_point)
		await click(MOUSE_BUTTON_LEFT)
		await wait_frames(2)
	check(play.seeds == seeds_before - 4, "scene: four injected left clicks cost four seeds")
	await wait_frames(60)
	var planted: Dictionary = {}
	for set_list: Array in landing_sets:
		for index: int in set_list:
			planted[index] = true
	check(landing_sets.size() == 4 and planted.size() >= 12, "scene: the four landings planted %d seed tiles" % planted.size())
	check(state.greened_count == greened_before, "scene: placed seeds do not count as greened (greened %d)" % state.greened_count)
	# ---- grow with game time (time scale only speeds the wall clock; game time comes from the physics steps)
	var t_land: float = landing_times[0]
	var all_seed_stage: bool = true
	for index: int in planted:
		all_seed_stage = all_seed_stage and state.stage[index] == WorldState.STAGE_SEED
	check(all_seed_stage, "scene: 1.5 s after landing every planted tile is still a seed")
	var first_seen: Array[float] = [-1.0, -1.0, -1.0, -1.0, -1.0]
	var greened_flag_ok: bool = true
	var order_ok: bool = true
	Engine.time_scale = 6.0
	var guard: int = 0
	while clock.elapsed - t_land < 64.0 and guard < 40000:
		await physics_frame
		guard += 1
		var highest: int = 0
		var greened_now: int = 0
		for index: int in planted:
			highest = maxi(highest, state.stage[index])
			if state.stage[index] >= 2:
				greened_now += 1
		for level: int in range(1, 5):
			if highest >= level and first_seen[level] < 0.0:
				first_seen[level] = clock.elapsed - t_land
		greened_flag_ok = greened_flag_ok and state.greened_count - greened_before == greened_now
		if guard % 240 == 0:
			greened_flag_ok = greened_flag_ok and state.counters_consistent()
	Engine.time_scale = 1.0
	await wait_frames(2)
	check(absf(first_seen[2] - 20.0) < 1.5 and absf(first_seen[3] - 40.0) < 1.5, "scene: sprout 1 after about 20 s (%.1f s) and sprout 2 after about 40 s (%.1f s) of game time without water" % [first_seen[2], first_seen[3]])
	check(absf(first_seen[4] - 60.0) < 1.5, "scene: first mature plant after about 60 s of game time (%.1f s)" % first_seen[4])
	check(greened_flag_ok, "scene: the greened count grew exactly with the planted tiles at sprout 1 or later, the counters matched a recount every frame")
	var mature_planted: int = 0
	for index: int in planted:
		if state.stage[index] == WorldState.STAGE_MATURE:
			mature_planted += 1
	check(mature_planted == planted.size(), "scene: all %d planted tiles are mature" % mature_planted)
	check(state.greened_count - greened_before == planted.size(), "scene: greened count rose by %d (planted tiles)" % (state.greened_count - greened_before))
	# ---- fruit from the mature plants
	play.seeds = 0
	var waited: int = 0
	Engine.time_scale = 6.0
	var fruit: Dictionary = {}
	while fruit.is_empty() and waited < 40000 and clock.elapsed - t_land < 400.0:
		await physics_frame
		waited += 1
		for item: Dictionary in play.pickups.items:
			if GroundPickups.is_plant_owner(int(item["owner"])):
				fruit = item.duplicate()
				break
	Engine.time_scale = 1.0
	check(not fruit.is_empty(), "scene: a mature plant dropped a seed fruit (%.1f s after landing)" % (clock.elapsed - t_land))
	var fruit_tile_index: int = int(fruit["owner"]) - GroundPickups.PLANT_OWNER_BASE
	check(planted.has(fruit_tile_index) and state.stage[fruit_tile_index] == WorldState.STAGE_MATURE, "scene: the fruit belongs to one of the mature planted tiles")
	check(play.seeds == 0, "scene: the fruit lies on the ground, not yet collected (seeds %d)" % play.seeds)
	# Walk to it (teleport near it) and collect, then shoot again.
	await teleport(Vector2(float(fruit["x"]), float(fruit["y"])) + Vector2(5, 0))
	check(play.seeds >= 1, "scene: standing next to the fruit collects it automatically (seeds %d)" % play.seeds)
	play.seeds = 1
	var landings_before: int = landing_sets.size()
	await aim_at(player.simulation_position + Vector2(0, -40))
	await click(MOUSE_BUTTON_LEFT)
	await wait_frames(80)
	check(play.seeds == 0 and landing_sets.size() == landings_before + 1, "scene: the collected seed is fired again: seed -> sprout -> mature -> fruit -> collection -> shot is a closed loop")
	# ---- pause freezes growth, moisture, production and fruit ages
	var wet_tile: int = -1
	for index: int in landing_sets[landing_sets.size() - 1]:
		wet_tile = index
	await aim_at(player.simulation_position + Vector2(0, -40))
	await click(MOUSE_BUTTON_RIGHT)
	await wait_frames(30)
	var before: Dictionary = scene_snapshot(play, state, wet_tile)
	send_key(KEY_ESCAPE, true)
	send_key(KEY_ESCAPE, false)
	await wait_frames(2)
	check(paused and main.pause_panel.visible, "scene: Esc through the input pipeline pauses")
	var frozen: Dictionary = scene_snapshot(play, state, wet_tile)
	await wait_frames(90)
	var after: Dictionary = scene_snapshot(play, state, wet_tile)
	check(frozen == after, "scene: 1.5 s of pause: sim clock, growth amount, moisture, production ticks and fruit ages do not move %s" % [frozen == after])
	check(int(before["moisture"]) > 0, "scene: the water shot wetted the new plant (moisture %d) so that decay would show" % int(before["moisture"]))
	send_key(KEY_ESCAPE, true)
	send_key(KEY_ESCAPE, false)
	await wait_frames(2)
	check(not paused, "scene: Esc resumes")
	await wait_frames(6)
	var resumed: Dictionary = scene_snapshot(play, state, wet_tile)
	var gained: float = float(resumed["clock"]) - float(frozen["clock"])
	check(gained > 0.0 and gained < 0.25 and float(resumed["production_time"]) - float(frozen["production_time"]) < 0.25, "scene: after resume only the frames since resume count (%.3f s, not the 1.5 s pause)" % gained)
	main.queue_free()
	await process_frame

func scene_snapshot(play: PlayState, state: WorldState, tile: int) -> Dictionary:
	var ages: Array = []
	for item: Dictionary in play.pickups.items:
		ages.append(item["age"])
	return {"clock": main.simulation.clock.elapsed, "ticks": main.simulation.clock.growth_ticks, "growth": state.growth[tile], "moisture": state.moisture[tile], "stage": state.stage[tile], "production_time": play.production_time, "production_ticks": play.production_ticks, "ages": ages, "fruits": play.pickups.count(), "greened": state.greened_count}
