extends SceneTree
## P1-02 headless checks: seed / water resources, projectile flight, landing scatter, refill, seed source,
## ground pickups, pause, save structure, and real-scene scenarios driven only by engine-internal input injection.
## Run: Godot --headless --path <project> --script res://tests/p1/p1_02_checks.gd
## Expected values come from the ticket / parent design (20 seeds, cap 40, gauge 0..100, range 120 px, scatter
## radius 10 px, max 6, splash radius 12 px, refill within 2 tiles, drop every 8 s, cap 3, collect radius 12 px)
## and from brute-force recounts written independently of the implementation.

const REGION_PATH: String = "res://data/region_01.tres"
const TILE: int = 4

var failures: int = 0
var checks: int = 0
var region_def: RegionDef
var sim_tuning: SimTuning
var play_tuning: PlayTuning

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
	test_resources()
	test_landing_seed()
	test_landing_water()
	test_determinism_and_fairness()
	test_non_target_aim_on_real_map()
	test_refill()
	test_pickups_and_source()
	test_save_structure()
	test_source_placement()
	await test_projectiles()
	await test_scene_scenarios()
	print("P1_02_RESULT checks=%d failures=%d" % [checks, failures])
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

func blank_rows(width: int, height: int) -> Array:
	var rows: Array = []
	for y: int in height:
		rows.append(".".repeat(width))
	return rows

func new_play(state: WorldState, sources: Array[Vector2] = []) -> PlayState:
	return PlayState.new(state, play_tuning, sim_tuning, TILE, sources)

## Brute force: plantable free target tiles whose centre lies within radius of point.
func brute_candidates(state: WorldState, point: Vector2, radius: float) -> Array[int]:
	var result: Array[int] = []
	for y: int in state.height:
		for x: int in state.width:
			var index: int = y * state.width + x
			var centre: Vector2 = Vector2(x * TILE + 2.0, y * TILE + 2.0)
			if centre.distance_to(point) > radius:
				continue
			var def: TerrainDef = state.terrain_defs[state.terrain[index]]
			if def.is_target and def.plantable and state.stage[index] == 0 and state.occupant[index] == 0:
				result.append(index)
	return result

func count_stage(state: WorldState, wanted: int) -> int:
	var total: int = 0
	for index: int in state.tile_count():
		if state.stage[index] == wanted:
			total += 1
	return total

# ---- tuning -------------------------------------------------------------------------------------

func test_tuning_values() -> void:
	var t: PlayTuning = play_tuning
	check(t.seed_start == 20 and t.seed_max == 40, "tuning: 20 seeds at start, cap 40")
	check(t.water_max == 100.0 and t.water_start == 100.0, "tuning: water gauge 0..100, full at start")
	check(t.projectile_range_px == 120.0 and t.max_projectiles == 64, "tuning: range 120 px, at most 64 shots in flight")
	check(t.seed_scatter_radius_px == 10.0 and t.seed_scatter_max == 6, "tuning: scatter radius 10 px (2.5 tiles), at most 6 seeds")
	check(t.water_splash_radius_px == 12.0 and t.water_refill_distance_tiles == 2.0, "tuning: splash radius 12 px (3 tiles), refill within 2 tiles")
	check(t.source_interval_seconds == 8.0 and t.source_fruit_cap == 3 and t.pickup_collect_radius_px == 12.0, "tuning: drop every 8 s, cap 3 around a source, collect within 12 px")
	check(t.pickup_lifetime_seconds > 0.0 and t.pickup_total_cap > 0, "tuning: pickups have a lifetime and a region-wide cap")

# ---- resources ----------------------------------------------------------------------------------

func test_resources() -> void:
	var play: PlayState = new_play(small_state(blank_rows(8, 8)))
	check(play.seeds == 20 and play.water == 100.0, "start: 20 seeds, water 100")
	var spent: int = 0
	for i: int in 25:
		if play.spend_seed():
			spent += 1
	check(spent == 20 and play.seeds == 0, "20 seeds can be spent, then nothing more (spent %d, left %d)" % [spent, play.seeds])
	check(not play.can_fire_seed() and not play.spend_seed() and play.seeds == 0, "at zero seeds a spend is refused and the count stays 0 (never negative)")
	check(play.add_seeds(15) == 15 and play.seeds == 15, "seeds can be added")
	check(play.add_seeds(100) == 25 and play.seeds == 40, "adding beyond the cap stops at 40 and reports what was added")
	check(play.add_seeds(1) == 0 and play.seeds == 40 and play.add_seeds(-5) == 0 and play.seeds == 40, "a full pouch takes nothing; negative amounts are ignored")
	var shots: int = 0
	for i: int in 20:
		if play.spend_water():
			shots += 1
	check(shots == 10 and play.water == 0.0, "100 water pays 10 shots of 10 (got %d, left %.2f)" % [shots, play.water])
	check(not play.can_fire_water() and not play.spend_water() and play.water == 0.0, "an empty gauge refuses a water shot and stays at 0")
	play.water = 7.5
	check(not play.can_fire_water() and not play.spend_water() and play.water == 7.5, "insufficient water (7.5 < 10) refuses the shot and keeps the gauge")
	play.water = 99.0
	check(play.add_water(50.0) == 1.0 and play.water == 100.0, "water refill stops at 100")

# ---- landing: seeds -------------------------------------------------------------------------------

func test_landing_seed() -> void:
	var rows: Array = blank_rows(24, 24)
	# Non-target column (building) and a water column through the landing area.
	for y: int in 24:
		rows[y] = String(rows[y]).substr(0, 9) + "#" + String(rows[y]).substr(10)
		rows[y] = String(rows[y]).substr(0, 15) + "~" + String(rows[y]).substr(16)
	var state: WorldState = small_state(rows)
	var point: Vector2 = Vector2(12 * TILE + 2.0, 12 * TILE + 2.0)
	state.set_stage(state.index_of(12, 12), WorldState.STAGE_MATURE)
	state.set_stage(state.index_of(13, 12), WorldState.STAGE_SPROUT2)
	state.set_stage(state.index_of(11, 12), WorldState.STAGE_SEED)
	check(state.occupy(Rect2i(11, 13, 2, 2), 7), "an occupied 2x2 block is set up next to the landing point")
	var before_stage: PackedByteArray = state.stage.duplicate()
	var greened_before: int = state.greened_count
	var candidates: Array[int] = brute_candidates(state, point, 10.0)
	var placed: PackedInt32Array = Landing.scatter_seeds(state, TILE, point, 10.0, 6, 99)
	check(candidates.size() > 6, "more free candidate tiles than the maximum exist (%d), so the limit matters" % candidates.size())
	check(placed.size() == 6, "exactly the maximum of 6 seeds is placed (placed %d)" % placed.size())
	var all_valid: bool = true
	var unique: Dictionary = {}
	for index: int in placed:
		unique[index] = true
		all_valid = all_valid and candidates.has(index) and state.stage[index] == WorldState.STAGE_SEED
	check(all_valid and unique.size() == placed.size(), "every placed seed lies on a free plantable target tile inside the radius, no duplicates")
	var untouched: bool = true
	for index: int in state.tile_count():
		if not placed.has(index) and state.stage[index] != before_stage[index]:
			untouched = false
	check(untouched, "no other tile changed (planted, occupied, building, water and out-of-range tiles keep their stage)")
	check(state.stage[state.index_of(12, 12)] == WorldState.STAGE_MATURE and state.stage[state.index_of(13, 12)] == WorldState.STAGE_SPROUT2 and state.stage[state.index_of(11, 12)] == WorldState.STAGE_SEED, "existing plants and seeds are not overwritten")
	check(state.occupant[state.index_of(11, 13)] == 7 and state.stage[state.index_of(11, 13)] == 0 and state.stage[state.index_of(12, 14)] == 0, "occupied tiles get no seed")
	check(state.stage[state.index_of(9, 12)] == 0 and state.stage[state.index_of(15, 12)] == 0, "building and water tiles stay empty")
	check(state.greened_count == greened_before, "seeds alone do not raise the greening count (%d stays)" % greened_before)
	check(state.counters_consistent(), "differential counters equal a full recount after landing")
	# Fewer candidates than N: all of them are planted.
	var tiny_rows: Array = blank_rows(24, 24)
	for y: int in 24:
		for x: int in 24:
			if not (x in [12, 13] and y in [12, 13]):
				tiny_rows[y] = String(tiny_rows[y]).substr(0, x) + "#" + String(tiny_rows[y]).substr(x + 1)
	var tiny: WorldState = small_state(tiny_rows)
	var tiny_placed: PackedInt32Array = Landing.scatter_seeds(tiny, TILE, Vector2(52, 52), 10.0, 6, 5)
	check(tiny_placed.size() == 4 and count_stage(tiny, WorldState.STAGE_SEED) == 4, "with only 4 free tiles around, all 4 get a seed and no more")
	# Nothing plantable at all: nothing happens, seeds are not refunded.
	var play: PlayState = new_play(small_state(["~~~~", "~~~~", "~~~~", "~~~~"]))
	var before_seeds: int = play.seeds
	play.spend_seed()
	var lost: PackedInt32Array = play.land_seed(Vector2(8, 8))
	check(lost.is_empty() and play.seeds == before_seeds - 1 and count_stage(play.world, WorldState.STAGE_SEED) == 0, "a seed landing on water wastes the seed: no tile changes, the seed is not refunded")
	# Radius is a true circle on tile centres: a tile centre exactly at 10 px is in, 10.2 px is out.
	var edge: WorldState = small_state(blank_rows(24, 24))
	var edge_candidates: Array[int] = brute_candidates(edge, Vector2(50, 50), 10.0)
	var edge_tiles: PackedInt32Array = Landing.tiles_in_radius(edge, TILE, Vector2(50, 50), 10.0)
	var same_set: bool = edge_tiles.size() == edge_candidates.size()
	for index: int in edge_tiles:
		same_set = same_set and edge_candidates.has(index)
	check(same_set and edge_tiles.size() > 12, "tiles_in_radius equals the brute-force set (%d tiles)" % edge_tiles.size())

# ---- landing: water -------------------------------------------------------------------------------

func test_landing_water() -> void:
	var rows: Array = blank_rows(24, 24)
	for y: int in 24:
		rows[y] = String(rows[y]).substr(0, 14) + "~~" + String(rows[y]).substr(16)
		if y in [10, 11, 12]:
			rows[y] = String(rows[y]).substr(0, 10) + "###" + String(rows[y]).substr(13)
	var state: WorldState = small_state(rows)
	var point: Vector2 = Vector2(12 * TILE + 2.0, 12 * TILE + 2.0)
	var changed: int = Landing.splash_water(state, TILE, point, 12.0, 40, 100)
	var expected_tiles: int = 0
	var nontarget_wet: int = 0
	var out_of_range_wet: int = 0
	for y: int in 24:
		for x: int in 24:
			var index: int = y * 24 + x
			var inside: bool = Vector2(x * TILE + 2.0, y * TILE + 2.0).distance_to(point) <= 12.0
			var is_target: bool = state.terrain_defs[state.terrain[index]].is_target
			if inside and is_target:
				expected_tiles += 1
				if state.moisture[index] != 40:
					out_of_range_wet += 1
			elif state.moisture[index] != 0:
				nontarget_wet += 1
	check(changed == expected_tiles and expected_tiles >= 10, "water wets exactly the target tiles in radius 12 px (%d tiles)" % changed)
	check(out_of_range_wet == 0 and nontarget_wet == 0, "in-range targets got +40; water, buildings and tiles out of range stay at 0")
	Landing.splash_water(state, TILE, point, 12.0, 40, 100)
	Landing.splash_water(state, TILE, point, 12.0, 40, 100)
	var peak: int = 0
	for index: int in state.tile_count():
		peak = maxi(peak, state.moisture[index])
	check(peak == 100, "repeated splashes cap the moisture at 100 (peak %d)" % peak)
	check(Landing.splash_water(state, TILE, point, 12.0, 40, 100) == 0, "a fully wet area changes nothing more")
	var snapshot: PackedByteArray = state.stage.duplicate()
	check(state.stage == snapshot and state.counters_consistent() and state.greened_count == 0, "water never changes stages or the greening count")

# ---- determinism and fairness -------------------------------------------------------------------------

func test_determinism_and_fairness() -> void:
	var point: Vector2 = Vector2(50, 50)
	var a: WorldState = small_state(blank_rows(24, 24))
	var b: WorldState = small_state(blank_rows(24, 24))
	var pa: PackedInt32Array = Landing.scatter_seeds(a, TILE, point, 10.0, 6, 1234)
	var pb: PackedInt32Array = Landing.scatter_seeds(b, TILE, point, 10.0, 6, 1234)
	check(pa == pb and pa.size() == 6, "same world, point and seed give the same 6 tiles")
	var c: WorldState = small_state(blank_rows(24, 24))
	var pc: PackedInt32Array = Landing.scatter_seeds(c, TILE, point, 10.0, 6, 1235)
	check(pc != pa, "a different seed gives a different choice")
	# Whole PlayState sequence is reproducible.
	var one: PlayState = new_play(small_state(blank_rows(40, 40)))
	var two: PlayState = new_play(small_state(blank_rows(40, 40)))
	var seq_one: Array = []
	var seq_two: Array = []
	for i: int in 8:
		seq_one.append(Array(one.land_seed(Vector2(40 + i * 11, 60))))
		seq_two.append(Array(two.land_seed(Vector2(40 + i * 11, 60))))
	check(seq_one == seq_two and one.landing_counter == 8, "the fixed seed reproduces a whole sequence of 8 landings")
	check(one.world.stage == two.world.stage and one.world.counters_consistent(), "resulting maps are identical and consistent")
	# Fairness: with many seeds every candidate is eventually chosen.
	var base: WorldState = small_state(blank_rows(24, 24))
	var cands: Array[int] = brute_candidates(base, point, 10.0)
	var hit: Dictionary = {}
	for s: int in 300:
		var fresh: WorldState = small_state(blank_rows(24, 24)) if s == 0 else base
		var picked: PackedInt32Array = Landing.scatter_seeds(fresh, TILE, point, 10.0, 6, s)
		for index: int in picked:
			hit[index] = true
			fresh.set_stage(index, WorldState.STAGE_EMPTY)
	check(hit.size() == cands.size(), "over 300 landings every one of the %d candidate tiles gets chosen at least once (%d)" % [cands.size(), hit.size()])

# ---- non-target aiming on the real map --------------------------------------------------------------------

func test_non_target_aim_on_real_map() -> void:
	var state: WorldState = RegionLoader.load_region(region_def)
	var play: PlayState = new_play(state)
	var base_hash: int = hash(state.stage)
	var greened: int = state.greened_count
	# Find points with no target tile within 4 tiles: deep water and building interiors.
	var deep_water: Vector2i = find_isolated(state, terrain_id(&"water"))
	var deep_building: Vector2i = find_isolated(state, terrain_id(&"building"))
	check(deep_water.x >= 0 and deep_building.x >= 0, "found a deep water point %s and a building interior %s on the real map" % [deep_water, deep_building])
	for tile: Vector2i in [deep_water, deep_building]:
		for i: int in 10:
			play.land_seed((Vector2(tile) + Vector2(0.5, 0.5)) * TILE)
			play.land_water((Vector2(tile) + Vector2(0.5, 0.5)) * TILE)
	check(hash(state.stage) == base_hash and state.greened_count == greened and state.counters_consistent(), "20 seed and 20 water landings deep in water or a building change no stage and no greening count")
	var moisture_total: int = 0
	for index: int in state.tile_count():
		moisture_total += state.moisture[index]
	check(moisture_total == 0, "and add no moisture anywhere")
	# At the water's edge seeds may land on neighbouring target tiles, but never on water or buildings, and the rate is unchanged.
	var edge_tile: Vector2i = find_edge(state)
	var planted: int = 0
	for i: int in 30:
		planted += play.land_seed((Vector2(edge_tile) + Vector2(0.5, 0.5)) * TILE).size()
	var bad: int = 0
	for index: int in state.tile_count():
		if state.stage[index] != 0 and not state.terrain_defs[state.terrain[index]].is_target:
			bad += 1
	check(bad == 0 and state.greened_count == greened and state.counters_consistent(), "shooting at a water edge %s planted %d seeds only on target tiles; greening count stays %d" % [edge_tile, planted, greened])

## First tile of terrain `id` with no target tile within 4 tiles.
func find_isolated(state: WorldState, id: int) -> Vector2i:
	for y: int in range(8, state.height - 8):
		for x: int in range(8, state.width - 8):
			if state.terrain[state.index_of(x, y)] != id:
				continue
			var ok: bool = true
			for dy: int in range(-4, 5):
				for dx: int in range(-4, 5):
					if state.target[state.index_of(x + dx, y + dy)] == 1:
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

## A non-target tile that has a target neighbour.
func find_edge(state: WorldState) -> Vector2i:
	for y: int in range(8, state.height - 8):
		for x: int in range(8, state.width - 8):
			if state.target[state.index_of(x, y)] == 0 and state.target[state.index_of(x + 1, y)] == 1:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

# ---- refill ----------------------------------------------------------------------------------------------------

func test_refill() -> void:
	# 40x40 map: water at x 20..22 (all rows), shore either side is wasteland here, so refill must come from water tiles themselves.
	var rows: Array = blank_rows(40, 40)
	for y: int in 40:
		rows[y] = String(rows[y]).substr(0, 20) + "~~~" + String(rows[y]).substr(23)
	var state: WorldState = small_state(rows)
	var play: PlayState = new_play(state)
	play.water = 0.0
	# Tile distance 3 from the water tile column 20 (x=17 -> dx=3): out of range.
	var far: Vector2 = Vector2(17 * TILE + 2.0, 10 * TILE + 2.0)
	for i: int in 60:
		play.advance(1.0 / 60.0, far)
	check(play.water == 0.0 and not play.refilling, "3 tiles from water the gauge does not refill")
	var near_exact: Vector2 = Vector2(18 * TILE + 2.0, 10 * TILE + 2.0)
	for i: int in 60:
		play.advance(1.0 / 60.0, near_exact)
	check(play.refilling and absf(play.water - 25.0) < 0.01, "2 tiles from water the gauge refills 25 per second (%.3f after 1 s)" % play.water)
	for i: int in 60 * 10:
		play.advance(1.0 / 60.0, near_exact)
	check(play.water == 100.0, "refill stops at the cap of 100 (%.3f)" % play.water)
	# Diagonal 2,2 is 2.83 tiles: out of range; 1,1 in range.
	play.water = 0.0
	play.advance(1.0 / 60.0, Vector2(18 * TILE + 2.0, 10 * TILE + 2.0))
	var gained_straight: float = play.water
	play.water = 0.0
	var state2: WorldState = small_state(blank_rows(40, 40))
	state2.terrain[state2.index_of(20, 20)] = terrain_id(&"shore")
	var play2: PlayState = new_play(state2)
	play2.water = 0.0
	play2.advance(1.0 / 60.0, Vector2(18 * TILE + 2.0, 18 * TILE + 2.0))
	check(gained_straight > 0.0 and play2.water == 0.0, "refill range is a circle in tile units: (2,0) tiles refills, (2,2) tiles does not")
	play2.advance(1.0 / 60.0, Vector2(19 * TILE + 2.0, 19 * TILE + 2.0))
	check(play2.water > 0.0, "a shore tile (is_waterside) alone also refills when within range")
	# Pause semantics at the class level: no time passes without advance(); a huge delta is capped.
	var capped: PlayState = new_play(small_state(rows))
	capped.water = 0.0
	capped.advance(100.0, Vector2(21 * TILE, 10 * TILE))
	check(absf(capped.water - 25.0 * 0.25) < 0.01 and absf(capped.elapsed - 0.25) < 1.0e-9, "one huge delta is capped to 0.25 s (water %.3f)" % capped.water)

# ---- pickups and the seed source ---------------------------------------------------------------------------------

func make_source_play(tile_rows: Array = []) -> PlayState:
	var rows: Array = tile_rows if not tile_rows.is_empty() else blank_rows(64, 64)
	var sources: Array[Vector2] = [Vector2(128, 128)]
	return new_play(small_state(rows), sources)

func run_source(step: float, seconds: float, away: Vector2 = Vector2(5000, 5000)) -> PlayState:
	var play: PlayState = make_source_play()
	var steps: int = roundi(seconds / step)
	for i: int in steps:
		play.advance(step, away)
	return play

func test_pickups_and_source() -> void:
	var early: PlayState = run_source(1.0 / 60.0, 7.9)
	check(early.pickups.count() == 0, "no fruit before the 8 s interval (7.9 s: %d)" % early.pickups.count())
	var first: PlayState = run_source(1.0 / 60.0, 8.2)
	check(first.pickups.count() == 1 and first.sources[0].drops == 1, "first fruit after 8 s")
	var item: Dictionary = first.pickups.items[0]
	var dist: float = Vector2(float(item["x"]), float(item["y"])).distance_to(Vector2(128, 128))
	check(dist >= 10.0 - 0.001 and dist <= 18.0 + 0.001 and int(item["owner"]) == 1, "the fruit lands 10..18 px around its source (%.2f px)" % dist)
	var results: Array[int] = []
	for rate: int in [30, 60, 144]:
		results.append(run_source(1.0 / rate, 25.0).pickups.count())
	check(results == [3, 3, 3], "25 s at 30 / 60 / 144 Hz all hold 3 fruits %s" % [results])
	# Cap of 3 around one source, lifetime 60 s, replacement afterwards.
	var play: PlayState = make_source_play()
	var max_seen: int = 0
	var seen_at_50: int = 0
	for i: int in 60 * 120:
		play.advance(1.0 / 60.0, Vector2(5000, 5000))
		max_seen = maxi(max_seen, play.pickups.count_owned(1))
		if i == 60 * 50:
			seen_at_50 = play.pickups.count()
	check(max_seen == 3 and seen_at_50 == 3, "never more than 3 fruits of one source on the ground (max %d)" % max_seen)
	check(play.sources[0].drops > 3, "fruits expire after their lifetime and are replaced (drops after 120 s: %d)" % play.sources[0].drops)
	var oldest_age: float = 0.0
	for it: Dictionary in play.pickups.items:
		oldest_age = maxf(oldest_age, float(it["age"]))
	check(oldest_age < play_tuning.pickup_lifetime_seconds, "no fruit older than the lifetime remains (oldest %.1f s)" % oldest_age)
	# Region-wide cap.
	var pool: GroundPickups = GroundPickups.new(24, 60.0)
	var accepted: int = 0
	for i: int in 30:
		if pool.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(i, 0), 1000000 + i):
			accepted += 1
	check(accepted == 24 and pool.count() == 24, "the region-wide pickup cap of 24 refuses further drops (accepted %d)" % accepted)
	pool.advance(59.0)
	check(pool.count() == 24 and pool.advance(1.5) == 24 and pool.count() == 0, "pickups vanish after the lifetime (all 24 expired together)")
	# A full cap holds a source's timer; room afterwards drops again.
	var crowded: PlayState = make_source_play()
	for i: int in 24:
		crowded.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(900 + i, 900), 5000 + i)
	for i: int in 60 * 20:
		crowded.advance(1.0 / 60.0, Vector2(5000, 5000))
	check(crowded.sources[0].drops == 0 and crowded.pickups.count_owned(1) == 0, "with the region cap full the source drops nothing")
	# Auto collection.
	var collect: PlayState = make_source_play()
	collect.seeds = 5
	collect.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(300, 300), 1)
	collect.advance(1.0 / 60.0, Vector2(300 + 13, 300))
	check(collect.seeds == 5 and collect.pickups.count() == 1, "a fruit 13 px away is not collected (radius 12)")
	collect.advance(1.0 / 60.0, Vector2(300 + 11, 300))
	check(collect.seeds == 6 and collect.pickups.count() == 0, "a fruit 11 px away is collected automatically: +1 seed")
	var full: PlayState = make_source_play()
	full.seeds = 40
	full.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(300, 300), 1)
	for i: int in 30:
		full.advance(1.0 / 60.0, Vector2(300, 300))
	check(full.seeds == 40 and full.pickups.count() == 1, "with 40 seeds a fruit is not collected and stays on the ground")
	full.spend_seed()
	full.advance(1.0 / 60.0, Vector2(300, 300))
	check(full.seeds == 40 and full.pickups.count() == 0, "after spending one seed the waiting fruit is collected (back to 40, never above)")
	var many: PlayState = make_source_play()
	many.seeds = 38
	for i: int in 5:
		many.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(300 + i, 300), 1)
	many.advance(1.0 / 60.0, Vector2(300, 300))
	check(many.seeds == 40 and many.pickups.count() == 3, "five fruits at 38 seeds: 2 collected, 3 remain, cap 40 not exceeded")
	check(SeedSource.INDESTRUCTIBLE and not SeedSource.new().has_method("take_damage"), "the seed source is flagged indestructible and has no damage entry")

# ---- save structure ------------------------------------------------------------------------------------------------

func test_save_structure() -> void:
	var play: PlayState = make_source_play()
	for i: int in 60 * 30:
		play.advance(1.0 / 60.0, Vector2(5000, 5000))
	play.seeds = 17
	play.water = 42.5
	play.land_seed(Vector2(40, 40))
	var text: String = JSON.stringify(play.to_dict())
	var restored: PlayState = make_source_play()
	var ok: bool = restored.load_dict(JSON.parse_string(text))
	check(ok and JSON.stringify(restored.to_dict()) == text, "resources, landing counter, source timer and ground fruits survive to_dict / JSON / from_dict")
	check(restored.seeds == 17 and restored.water == 42.5 and restored.pickups.count() == play.pickups.count() and restored.sources[0].drops == play.sources[0].drops and restored.landing_counter == 1, "restored values match")
	# The restored game continues exactly like the original (restored from the exact dictionary, not through text).
	var twin: PlayState = make_source_play()
	check(twin.load_dict(play.to_dict()), "state loads from the dictionary")
	for i: int in 60 * 15:
		play.advance(1.0 / 60.0, Vector2(5000, 5000))
		twin.advance(1.0 / 60.0, Vector2(5000, 5000))
	check(JSON.stringify(twin.to_dict()) == JSON.stringify(play.to_dict()), "original and restored states stay identical over 15 more seconds")
	var bad: Dictionary = play.to_dict()
	bad["version"] = 9
	check(not restored.load_dict(bad), "unknown version is rejected")
	var bad_sources: Dictionary = play.to_dict()
	bad_sources["sources"] = []
	check(not restored.load_dict(bad_sources), "a different number of sources is rejected")
	var extreme: Dictionary = play.to_dict()
	extreme["seeds"] = 9999
	extreme["water"] = -50
	check(restored.load_dict(extreme) and restored.seeds == 40 and restored.water == 0.0, "out-of-range saved resources are clamped to 0..cap")

func test_source_placement() -> void:
	var state: WorldState = RegionLoader.load_region(region_def)
	check(region_def.seed_source_tiles.size() >= 1, "the region defines at least one seed source")
	var all_safe: bool = true
	var far_ok: bool = true
	for tile: Vector2i in region_def.seed_source_tiles:
		all_safe = all_safe and state.terrain[state.index_of(tile.x, tile.y)] == terrain_id(&"safe")
		# Fruits fall up to 18 px (5 tiles) away: all of the ring must be safe terrain.
		for angle_step: int in 36:
			var angle: float = angle_step * TAU / 36.0
			for radius: float in [10.0, 18.0]:
				var p: Vector2 = (Vector2(tile) + Vector2(0.5, 0.5)) * TILE + Vector2(cos(angle), sin(angle)) * radius
				far_ok = far_ok and state.terrain[state.index_of(floori(p.x / TILE), floori(p.y / TILE))] == terrain_id(&"safe")
	check(all_safe, "every seed source stands on a safe-zone tile")
	check(far_ok, "every possible fruit position (10..18 px around the source) lies on safe terrain")

# ---- projectiles -------------------------------------------------------------------------------------------------------

func test_projectiles() -> void:
	var field: ProjectileField = ProjectileField.new()
	field.setup(play_tuning)
	root.add_child(field)
	var landings: Array[Dictionary] = []
	field.landed.connect(func(kind: String, point: Vector2) -> void: landings.append({"kind": kind, "point": point}))
	var origin: Vector2 = Vector2(100, 100)
	# Far target: clipped to 120 px along the aim direction.
	var target: Vector2 = field.launch(ProjectileField.KIND_SEED, origin, Vector2(400, 100), Vector2.RIGHT)
	check(target == Vector2(220, 100), "a target 300 px away lands at the range limit 120 px along the aim (%s)" % target)
	var steps: int = 0
	while not field.shots.is_empty() and steps < 200:
		field.advance(1.0 / 60.0)
		steps += 1
	check(landings.size() == 1 and landings[0]["point"] == Vector2(220, 100) and landings[0]["kind"] == "seed", "the shot lands exactly on the limit point")
	check(steps >= 45 and steps <= 46, "120 px at 160 px/s takes 45 physics steps (%d)" % steps)
	# Near target: lands on the aim point itself.
	landings.clear()
	var near_target: Vector2 = field.launch(ProjectileField.KIND_WATER, origin, Vector2(130, 140), Vector2.RIGHT)
	check(near_target.distance_to(Vector2(130, 140)) < 0.001, "a target within range is hit exactly (%s)" % near_target)
	for i: int in 60:
		field.advance(1.0 / 60.0)
	check(landings.size() == 1 and Vector2(landings[0]["point"]).distance_to(Vector2(130, 140)) < 0.001 and landings[0]["kind"] == "water", "the water shot lands on the aim point")
	# Diagonal aim keeps the direction.
	landings.clear()
	var diagonal: Vector2 = field.launch(ProjectileField.KIND_SEED, origin, origin + Vector2(300, 300), Vector2.RIGHT)
	check(diagonal.is_equal_approx(origin + Vector2(1, 1).normalized() * 120.0), "a far diagonal target is clipped to 120 px along the diagonal")
	for i: int in 60:
		field.advance(1.0 / 60.0)
	# Aim point on the origin: still a valid shot (lands at once on the shooter).
	landings.clear()
	field.launch(ProjectileField.KIND_SEED, origin, origin, Vector2.LEFT)
	field.advance(1.0 / 60.0)
	check(landings.size() == 1 and landings[0]["point"] == origin, "an aim point on the shooter lands on the shooter")
	# In-flight limit.
	landings.clear()
	var accepted: int = 0
	for i: int in 70:
		if field.launch(ProjectileField.KIND_SEED, origin, origin + Vector2(80, 0), Vector2.RIGHT) != Vector2.INF:
			accepted += 1
	check(accepted == 64 and field.is_full(), "at most 64 shots fly at once (accepted %d of 70)" % accepted)
	for i: int in 120:
		field.advance(1.0 / 60.0)
	check(field.shots.is_empty() and landings.size() == 64, "all 64 shots land and the list empties")
	# Enemy hit entry.
	landings.clear()
	var hits: Array[Dictionary] = []
	field.enemy_hit.connect(func(kind: String, point: Vector2, info: Dictionary) -> void: hits.append({"kind": kind, "point": point, "info": info}))
	field.enemy_hit_provider = func(_shot: Dictionary, _from: Vector2, to: Vector2) -> Dictionary:
		return {"point": to, "enemy": 42} if to.x >= 150.0 else {}
	field.launch(ProjectileField.KIND_SEED, origin, origin + Vector2(100, 0), Vector2.RIGHT)
	for i: int in 60:
		field.advance(1.0 / 60.0)
	check(hits.size() == 1 and hits[0]["kind"] == "seed" and int(hits[0]["info"]["enemy"]) == 42 and hits[0]["point"].x >= 150.0 and landings.is_empty() and field.shots.is_empty(), "the enemy hit entry ends the shot, reports the hit and skips the ground landing")
	field.enemy_hit_provider = Callable()
	field.launch(ProjectileField.KIND_SEED, origin, origin + Vector2(100, 0), Vector2.RIGHT)
	for i: int in 60:
		field.advance(1.0 / 60.0)
	check(landings.size() == 1 and hits.size() == 1, "without a provider nothing is ever hit and the shot lands normally")
	field.queue_free()

# ---- scene scenarios (real main.tscn, injected input) ---------------------------------------------------------------------------

var main: Node
var player: FlowerPlayer

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

## Moves the injected mouse so that the world point under it is `world_point`. Returns the achieved world point.
var mouse_screen: Vector2 = Vector2(320, 180)

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

## Centre tile of a block of `size` x `size` tiles that are all plain wasteland and empty.
func find_wasteland_block(state: WorldState, size: int) -> Vector2i:
	var wasteland: int = terrain_id(&"wasteland")
	for cy: int in range(40, 470, 6):
		for cx: int in range(40, 150, 6):
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

func test_scene_scenarios() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	await wait_frames(3)
	player = main.player
	var play: PlayState = main.play
	var state: WorldState = main.grid
	check(play.seeds == 20 and play.water == 100.0 and state.counters_consistent(), "scene: starts with 20 seeds and 100 water")
	check(main.weather_buttons.size() == 3 and main.hud != null, "scene: the weather buttons are kept and the new HUD exists")
	check(main.preview_projectiles == main.projectile_view.shots, "scene: the P0 preview list is the live shot list of the real projectile field")
	# ---- A: seeds, all 20, scattered on open wasteland
	var block: Vector2i = find_wasteland_block(state, 36)
	check(block.x >= 0, "scene: found a 36x36 open wasteland block at tile %s" % block)
	var centre: Vector2 = (Vector2(block) + Vector2(0.5, 0.5)) * TILE
	await teleport(centre)
	var greened_before: int = state.greened_count
	var landing_sizes: Array[int] = []
	scene_landing_sizes = landing_sizes
	main.projectile_view.landed.connect(record_seed_landing)
	var shot_ok: bool = true
	var targets_ok: bool = true
	for i: int in 20:
		var angle: float = i * TAU / 20.0
		var want: Vector2 = centre + Vector2(cos(angle), sin(angle)) * 60.0
		var got: Vector2 = await aim_at(want)
		var before_seeds: int = play.seeds
		await click(MOUSE_BUTTON_LEFT)
		shot_ok = shot_ok and play.seeds == before_seeds - 1 and not main.projectile_view.shots.is_empty()
		var shot: Dictionary = main.projectile_view.shots[main.projectile_view.shots.size() - 1]
		targets_ok = targets_ok and Vector2(shot["target"]).distance_to(got) < 0.01
	check(shot_ok, "scene: each of 20 left clicks fires one shot and costs exactly one seed")
	check(targets_ok, "scene: each shot's landing point is the mouse's world point (within range)")
	check(play.seeds == 0, "scene: 20 shots leave 0 seeds")
	var shots_before_empty: int = main.projectile_view.shots.size()
	await click(MOUSE_BUTTON_LEFT)
	var shots_after_empty: int = main.projectile_view.shots.size()
	await wait_frames(150)
	check(play.seeds == 0 and landing_sizes.size() == 20, "scene: the 21st click with 0 seeds fires nothing (seeds %d, landings %d)" % [play.seeds, landing_sizes.size()])
	var max_landing: int = 0
	var min_landing: int = 99
	for n: int in landing_sizes:
		max_landing = maxi(max_landing, n)
		min_landing = mini(min_landing, n)
	var seed_tiles: int = count_stage(state, WorldState.STAGE_SEED)
	check(max_landing <= 6 and min_landing >= 1, "scene: each landing planted between 1 and 6 seeds (min %d, max %d)" % [min_landing, max_landing])
	check(seed_tiles >= 20 and seed_tiles <= 120 and seed_tiles == sum_of(landing_sizes), "scene: %d seed tiles equal the sum of the landings (%d)" % [seed_tiles, sum_of(landing_sizes)])
	check(state.greened_count == greened_before and state.counters_consistent(), "scene: seeds alone leave the greening count at %d" % greened_before)
	check(shots_after_empty <= shots_before_empty, "scene: the click with 0 seeds created no shot")
	# ---- B: with 0 seeds, the source supplies one and the player shoots again
	Engine.time_scale = 3.0
	var waited: int = 0
	while play.pickups.count() == 0 and waited < 1500:
		await physics_frame
		waited += 1
	Engine.time_scale = 1.0
	check(play.pickups.count() >= 1, "scene: a fruit dropped near the source after about 8 s of game time (elapsed %.2f s)" % play.elapsed)
	check(play.seeds == 0, "scene: far from the source the seed count stays 0")
	var fruit: Dictionary = play.pickups.items[0]
	var fruit_position: Vector2 = Vector2(float(fruit["x"]), float(fruit["y"]))
	await teleport(fruit_position + Vector2(6, 0))
	check(play.seeds >= 1, "scene: walking up to the fruit collects it automatically (seeds %d)" % play.seeds)
	var before_second: int = play.seeds
	await aim_at(player.simulation_position + Vector2(40, 0))
	await click(MOUSE_BUTTON_LEFT)
	check(play.seeds == before_second - 1 and not main.projectile_view.shots.is_empty(), "scene: with a collected seed the player can shoot again")
	await wait_frames(60)
	# ---- C: water to zero, then recovery at the waterside
	await teleport(centre)
	var water_greened: int = state.greened_count
	await aim_at(centre + Vector2(50, 0))
	var water_ok: bool = true
	for i: int in 10:
		var before: float = play.water
		await click(MOUSE_BUTTON_RIGHT)
		water_ok = water_ok and absf(before - play.water - 10.0) < 0.001
	check(water_ok and play.water == 0.0, "scene: 10 right clicks cost 10 water each and empty the gauge")
	var shots_before: int = main.projectile_view.shots.size()
	await click(MOUSE_BUTTON_RIGHT)
	check(main.projectile_view.shots.size() == shots_before and play.water == 0.0, "scene: with 0 water a right click fires nothing and the gauge stays 0")
	await wait_frames(90)
	check(play.water == 0.0 and not play.refilling, "scene: far from the water the gauge stays at 0 for 1.5 s")
	var wet_tiles: int = 0
	for index: int in state.tile_count():
		if state.moisture[index] > 0:
			wet_tiles += 1
	check(wet_tiles > 0 and state.greened_count == water_greened, "scene: the water shots wetted %d tiles and changed no greening count" % wet_tiles)
	var water_start: Vector2i = find_waterside_east(state, block.y)
	check(water_start.x > block.x + 20, "scene: found waterside tile %s east of the player's row" % water_start)
	await teleport(Vector2((water_start.x - 14) * TILE + 2.0, block.y * TILE + 2.0))
	Input.action_press("move_right")
	var steps: int = 0
	var early_refill: bool = false
	while play.water == 0.0 and steps < 240:
		await physics_frame
		steps += 1
		if play.refilling and not play.is_near_water(player.simulation_position):
			early_refill = true
	var first_gain_water: float = play.water
	var at_start: float = play.water
	await wait_frames(30)
	Input.action_release("move_right")
	var gained: float = play.water - at_start
	check(play.water > 0.0 and not early_refill and steps < 240, "scene: walking east with injected input reaches the waterside and the gauge starts to recover (after %d steps)" % steps)
	check(gained > 10.5 and gained < 14.5, "scene: recovery is about 25 per second (%.2f over ~0.5 s, first tick %.2f)" % [gained, first_gain_water])
	var shots_c: int = main.projectile_view.shots.size()
	await aim_at(player.simulation_position + Vector2(-40, 0))
	await click(MOUSE_BUTTON_RIGHT)
	check(main.projectile_view.shots.size() == shots_c + 1, "scene: once recovered above the cost a right click fires water again")
	play.water = 95.0
	await wait_frames(60)
	check(play.water == 100.0, "scene: the gauge never exceeds 100")
	await wait_frames(60)
	# ---- D: shots at water and building interiors change nothing
	play.seeds = 10
	play.water = 100.0
	var deep_water: Vector2i = find_isolated(state, terrain_id(&"water"))
	var deep_building: Vector2i = find_isolated(state, terrain_id(&"building"))
	var stage_hash: int = hash(state.stage)
	var greened_d: int = state.greened_count
	var moisture_before: PackedByteArray = state.moisture.duplicate()
	# Growth and moisture decay run in the real scene (P1-03): compare only the non-target tiles (water, buildings).
	var nontarget_stage: Dictionary = {}
	var nontarget_moisture: Dictionary = {}
	for i: int in state.tile_count():
		if state.target[i] == 0:
			nontarget_stage[i] = state.stage[i]
			nontarget_moisture[i] = state.moisture[i]
	for tile: Vector2i in [deep_water, deep_building]:
		var tile_centre: Vector2 = (Vector2(tile) + Vector2(0.5, 0.5)) * TILE
		await teleport(tile_centre + Vector2(-50, 0))
		var got: Vector2 = await aim_at(tile_centre)
		for i: int in 3:
			await click(MOUSE_BUTTON_LEFT)
		await click(MOUSE_BUTTON_RIGHT)
		check(got.distance_to(tile_centre) < 1.0, "scene: aimed at the middle of %s" % ("water" if tile == deep_water else "a building"))
	await wait_frames(120)
	var nontarget_stage_ok: bool = true
	var nontarget_moisture_ok: bool = true
	for i: int in nontarget_stage:
		nontarget_stage_ok = nontarget_stage_ok and state.stage[i] == nontarget_stage[i]
		nontarget_moisture_ok = nontarget_moisture_ok and state.moisture[i] == nontarget_moisture[i]
	check(nontarget_stage_ok and state.greened_count >= greened_d and state.counters_consistent(), "scene: seeds shot at deep water and a building interior change no non-target stage, and the greening count only grows with the planted target tiles (counters match a recount)")
	check(nontarget_moisture_ok, "scene: water shot there wets no non-target tile")
	# ---- E: pause freezes resources, shots, source timers and fruits; resume adds no stopped time
	var water_edge: Vector2i = find_waterside_east(state, block.y)
	await teleport(Vector2(water_edge.x * TILE + 2.0, block.y * TILE + 2.0))
	play.water = 50.0
	play.seeds = 10
	await aim_at(player.simulation_position + Vector2(-110, 0))
	await click(MOUSE_BUTTON_LEFT)
	await wait_frames(4)
	check(not main.projectile_view.shots.is_empty(), "scene: a shot is in flight before the pause")
	send_key(KEY_ESCAPE, true)
	send_key(KEY_ESCAPE, false)
	await wait_frames(2)
	check(paused and main.pause_panel.visible, "scene: Esc through the input pipeline pauses")
	var seeds_at_pause: int = play.seeds
	play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, player.simulation_position + Vector2(4, 0), 1)
	var snap_before: Dictionary = pause_snapshot(play)
	await wait_frames(75)
	var snap_after: Dictionary = pause_snapshot(play)
	check(snap_before == snap_after, "scene: for 1.25 s of pause the seeds, water, elapsed time, source timers, fruit ages and shots do not move")
	check(int(snap_after["fruits"]) >= 1 and play.seeds == seeds_at_pause, "scene: a fruit right next to the paused player is not collected")
	send_key(KEY_ESCAPE, true)
	send_key(KEY_ESCAPE, false)
	await wait_frames(2)
	check(not paused, "scene: Esc resumes")
	await wait_frames(6)
	var resumed: Dictionary = pause_snapshot(play)
	var gained_time: float = float(resumed["elapsed"]) - float(snap_before["elapsed"])
	check(gained_time > 0.0 and gained_time < 0.25, "scene: after resume only the frames since resume count (%.3f s, not the 1.25 s pause)" % gained_time)
	check(float(resumed["source_timer"]) - float(snap_before["source_timer"]) < 0.25 and float(resumed["water"]) - float(snap_before["water"]) < 25.0 * 0.25 + 0.01, "scene: source timer and refill did not receive the stopped time")
	check(play.seeds == seeds_at_pause + 1, "scene: after resume the fruit next to the player is collected")
	# ---- F: HUD text follows the values
	await teleport(centre)
	await wait_frames(3)
	var hud: PlayHud = main.hud
	var percent: int = state.greened_count * 100 / state.target_count
	check(hud.seed_label.text.contains("%d/40" % play.seeds) and hud.seed_label.text.contains("種"), "HUD seed text '%s' shows the seed count" % hud.seed_label.text)
	check(hud.water_label.text == "水分 %d" % floori(play.water), "HUD water text '%s' follows the gauge" % hud.water_label.text)
	check(hud.green_label.text == "緑化 %d％" % percent, "HUD greening text '%s' is the floored percentage" % hud.green_label.text)
	var seeds_text: String = hud.seed_label.text
	play.seeds = 3
	state.set_stage(state.index_of(block.x, block.y), WorldState.STAGE_SPROUT1)
	await wait_frames(3)
	check(hud.seed_label.text != seeds_text and hud.seed_label.text.contains("3/40") and state.greened_count > greened_d, "HUD updates when the values change")
	var glyph_check: Label = hud.green_label
	check(glyph_check.get_theme_default_font() != null, "HUD uses a theme font")
	main.queue_free()
	await process_frame

var scene_landing_sizes: Array[int] = []

func record_seed_landing(kind: String, _point: Vector2) -> void:
	if kind == "seed":
		scene_landing_sizes.append(main.play.last_scatter.size())

func sum_of(values: Array[int]) -> int:
	var total: int = 0
	for value: int in values:
		total += value
	return total

func find_waterside_east(state: WorldState, row: int) -> Vector2i:
	for x: int in range(60, state.width):
		if state.terrain_defs[state.terrain[state.index_of(x, row)]].is_waterside and x > 200:
			return Vector2i(x, row)
	return Vector2i(-1, -1)

func pause_snapshot(play: PlayState) -> Dictionary:
	var shot_states: Array = []
	for shot: Dictionary in main.projectile_view.shots:
		shot_states.append([shot["position"], shot["age"], shot["traveled"]])
	var ages: Array = []
	for item: Dictionary in play.pickups.items:
		ages.append(item["age"])
	return {"seeds": play.seeds, "water": play.water, "elapsed": play.elapsed, "source_timer": play.sources[0].timer, "drops": play.sources[0].drops, "fruits": play.pickups.count(), "ages": ages, "shots": shot_states, "landings": play.landing_counter}
