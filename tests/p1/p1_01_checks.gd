extends SceneTree
## P1-01 headless checks: region load, greening rate, clock, pause, render pixels, save structure, performance.
## Run: Godot --headless --path <project> --script res://tests/p1/p1_01_checks.gd
## Expectations are derived from the spec / independent counts (png_counts.json made by tests/p1/count_png.py),
## not copied from the implementation.

const REGION_PATH: String = "res://data/region_01.tres"
const COUNTS_PATH: String = "res://evidence/p1/p1-06/png_counts.json"

var failures: int = 0
var checks: int = 0
var region_def: RegionDef

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", message])

func c8(color: Color) -> Vector3i:
	return Vector3i(roundi(color.r * 255.0), roundi(color.g * 255.0), roundi(color.b * 255.0))

## 8-bit comparison with +-1 tolerance per channel (float to byte rounding of the same colour).
func near(a: Color, b: Color, tolerance: int = 1) -> bool:
	var va: Vector3i = c8(a)
	var vb: Vector3i = c8(b)
	return absi(va.x - vb.x) <= tolerance and absi(va.y - vb.y) <= tolerance and absi(va.z - vb.z) <= tolerance

func legend_hex(color: Color) -> String:
	var v: Vector3i = c8(color)
	return "%02x%02x%02x" % [v.x, v.y, v.z]

func now_ms() -> float:
	return Time.get_ticks_usec() / 1000.0

func run() -> void:
	region_def = load(REGION_PATH) as RegionDef
	check(region_def != null and region_def.terrains.size() == 6, "region definition loads with 6 terrains (wasteland, safe, shore, water, building, shallows)")
	test_region_load()
	test_greening_small_map()
	test_greening_real_map_rounding_and_diff()
	test_hash_slots()
	test_clock()
	await test_pause_in_tree()
	test_occupancy_and_save()
	test_render_pixels()
	test_render_dirty_blocks()
	test_performance()
	print("P1_01_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

# ---- helpers ------------------------------------------------------------------------------

func terrain_id(key: StringName) -> int:
	for def: TerrainDef in region_def.terrains:
		if def.key == key:
			return def.id
	return -1

## Small state from rows of terrain keys, built through the real loader path (legend colours in a PNG-like Image).
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

func test_region_load() -> void:
	var started: float = now_ms()
	var state: WorldState = RegionLoader.load_region(region_def)
	print("INFO region load ms=%.1f" % (now_ms() - started))
	check(state != null, "region_01 loads")
	if state == null:
		return
	check(state.width == 512 and state.height == 512, "map is 512x512 tiles (%dx%d)" % [state.width, state.height])
	check(region_def.tile_px == 4 and state.width * region_def.tile_px == 2048, "4x4 px tiles, region 2048x2048 px")
	# Independent expectation: python PNG decoder output.
	var file: FileAccess = FileAccess.open(COUNTS_PATH, FileAccess.READ)
	check(file != null, "independent count file exists")
	if file != null:
		var expected: Dictionary = JSON.parse_string(file.get_as_text())
		var expected_counts: Dictionary = expected["counts"]
		var expected_targets: int = 0
		var all_match: bool = true
		for def: TerrainDef in region_def.terrains:
			var counted: int = 0
			for index: int in state.tile_count():
				if state.terrain[index] == def.id:
					counted += 1
			var want: int = int(expected_counts.get(legend_hex(def.map_color), -1))
			print("INFO terrain %s id=%d tiles=%d independent_png_count=%d target=%s" % [def.key, def.id, counted, want, def.is_target])
			if counted != want:
				all_match = false
			if def.is_target:
				expected_targets += want
		check(all_match, "per-terrain tile counts equal the independent PNG count")
		check(state.target_count == expected_targets, "target count %d equals independent count %d" % [state.target_count, expected_targets])
		var non_target_total: int = 512 * 512 - expected_targets
		check(state.target_count + non_target_total == 512 * 512 and non_target_total > 0, "non-target tiles exist and are outside the denominator (%d)" % non_target_total)
	# Texture import path equals the raw file bytes (lossless).
	var from_file: Image = Image.load_from_file(region_def.map_path)
	var from_import: Image = RegionLoader.load_map_image(region_def.map_path)
	from_file.convert(Image.FORMAT_RGBA8)
	from_import.convert(Image.FORMAT_RGBA8)
	check(from_file.get_data() == from_import.get_data(), "imported texture pixels equal raw PNG pixels")
	# Safe zone starts mature and counts as greened.
	var safe_tiles: int = 0
	var all_mature: bool = true
	for index: int in state.tile_count():
		if state.terrain[index] == terrain_id(&"safe"):
			safe_tiles += 1
			if state.stage[index] != WorldState.STAGE_MATURE:
				all_mature = false
	check(safe_tiles > 0 and all_mature and state.greened_count == safe_tiles, "safe zone is fully mature at start (%d tiles) and is the only greened set" % safe_tiles)
	var start_index: int = state.index_of(region_def.start_tile.x, region_def.start_tile.y)
	check(state.terrain[start_index] == terrain_id(&"safe"), "start tile lies in the safe zone")
	check(state.counters_consistent(), "differential counters equal recount after load")
	# Wrong size / unknown colour are rejected.
	var bad_def: RegionDef = RegionDef.new()
	bad_def.width_tiles = 4
	bad_def.height_tiles = 4
	bad_def.terrains = region_def.terrains
	var bad_image: Image = Image.create(4, 4, false, Image.FORMAT_RGB8)
	bad_image.fill(Color8(1, 2, 3))
	check(RegionLoader.build_state(bad_def, bad_image) == null, "map with a colour outside the legend is rejected (expected ERROR line above)")
	var wrong_size: Image = Image.create(5, 4, false, Image.FORMAT_RGB8)
	check(RegionLoader.build_state(bad_def, wrong_size) == null, "map with the wrong size is rejected (expected ERROR line above)")

func test_greening_small_map() -> void:
	var state: WorldState = small_state(["....", "~#:s", "..~."])
	check(state != null and state.target_count == 9, "small map: 9 targets, water and building excluded from the denominator")
	check(state.greened_count == 1 and state.greening_percent_floor() == 11, "small map: only the mature safe tile is greened at start (1/9, floor 11 percent)")
	var water: int = state.index_of(0, 1)
	var building: int = state.index_of(1, 1)
	check(not state.set_stage(water, WorldState.STAGE_MATURE) and not state.set_stage(building, WorldState.STAGE_SPROUT1), "non-target tiles refuse every stage")
	check(state.greened_count == 1 and state.target_count == 9 and state.stage[water] == 0, "refused writes change nothing")
	check(not state.can_plant(water) and not state.can_plant(building), "non-target tiles cannot be planted")
	state.set_stage(state.index_of(0, 0), WorldState.STAGE_SEED)
	state.set_stage(state.index_of(1, 0), WorldState.STAGE_SEED)
	check(state.greened_count == 1, "seeds do not count as greened")
	state.set_stage(state.index_of(0, 0), WorldState.STAGE_SPROUT1)
	state.set_stage(state.index_of(1, 0), WorldState.STAGE_SPROUT2)
	check(state.greened_count == 3 and state.greening_percent_floor() == 33, "sprout1 and above count: 3/9, floor 33 percent")
	check(not state.is_fully_greened(), "3/9 is not fully greened")
	for y: int in 3:
		for x: int in 4:
			state.set_stage(state.index_of(x, y), WorldState.STAGE_MATURE)
	check(state.greened_count == 9 and state.is_fully_greened() and state.greening_percent_floor() == 100, "all 9 targets mature: 9/9 full")
	state.set_stage(state.index_of(3, 2), WorldState.STAGE_SEED)
	check(state.greened_count == 8 and not state.is_fully_greened() and state.greening_percent_floor() == 88, "regressing one tile gives 8/9, not full")
	check(state.counters_consistent(), "small map counters equal recount")
	var empty_state: WorldState = small_state(["~#", "#~"])
	check(empty_state.target_count == 0 and not empty_state.is_fully_greened() and empty_state.greening_percent_floor() == 0, "a map without targets is never 100 percent")

func test_greening_real_map_rounding_and_diff() -> void:
	var state: WorldState = RegionLoader.load_region(region_def)
	var targets: PackedInt32Array = PackedInt32Array()
	for index: int in state.tile_count():
		if state.terrain_def_at(index).is_target:
			targets.append(index)
	for index: int in targets:
		state.set_stage(index, WorldState.STAGE_MATURE)
	check(state.is_fully_greened() and state.greened_count == targets.size(), "real map: every target mature gives exact full integer equality")
	state.set_stage(targets[targets.size() / 2], WorldState.STAGE_SEED)
	var ratio: float = float(state.greened_count) / float(state.target_count)
	check(not state.is_fully_greened() and state.greening_percent_floor() == 99, "one tile short is 99 percent and not full, although the float ratio is %.6f" % ratio)
	print("INFO a rounded display (%.2f percent) would have claimed 100 here; the integer test does not" % (ratio * 100.0))
	check(state.counters_consistent(), "counters equal recount after mass change")
	# Random stage changes, including non-target tiles; own recount from the definitions.
	var fresh: WorldState = RegionLoader.load_region(region_def)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 77
	var refused_ok: bool = true
	var consistent: bool = true
	for step: int in 60000:
		var index: int = rng.randi_range(0, fresh.tile_count() - 1)
		var wanted: int = rng.randi_range(0, 4)
		var accepted: bool = fresh.set_stage(index, wanted)
		if fresh.terrain_def_at(index).is_target != accepted:
			refused_ok = false
		if step % 10000 == 9999:
			var own_greened: int = 0
			var own_targets: int = 0
			for i: int in fresh.tile_count():
				if fresh.terrain_def_at(i).is_target:
					own_targets += 1
					if fresh.stage[i] >= 2:
						own_greened += 1
			if own_greened != fresh.greened_count or own_targets != fresh.target_count or not fresh.counters_consistent():
				consistent = false
	check(refused_ok, "set_stage is accepted exactly on target tiles")
	check(consistent, "after 60000 random stage changes the counters equal an independent recount (checked every 10000)")

func test_hash_slots() -> void:
	var counts: Array[int] = [0, 0, 0, 0]
	for index: int in 100000:
		counts[WorldState.slot_for(index, 5)] += 1
	var balanced: bool = true
	for slot: int in 4:
		if counts[slot] < 24000 or counts[slot] > 26000:
			balanced = false
	check(balanced, "sprout slots are evenly spread over the 4 centre candidates %s" % [counts])
	var same: bool = true
	var different: int = 0
	for index: int in 1000:
		if WorldState.slot_for(index, 5) != WorldState.slot_for(index, 5):
			same = false
		if WorldState.slot_for(index, 5) != WorldState.slot_for(index, 6):
			different += 1
	check(same and different > 500, "slots are deterministic per (tile, seed) and change with the seed")

func run_clock(step: float, total_steps: int) -> SimClock:
	var clock: SimClock = SimClock.new()
	for i: int in total_steps:
		clock.advance(step)
	return clock

func test_clock() -> void:
	var tuning: SimTuning = load("res://data/sim_tuning.tres") as SimTuning
	check(tuning.growth_tick_seconds == 0.5 and tuning.spread_tick_seconds == 1.0, "tuning periods are 0.5 s growth and 1.0 s spread")
	for seconds: float in [7.3, 30.0, 30.3, 120.0]:
		var results: Array[Vector2i] = []
		for rate: int in [30, 60, 144]:
			var clock: SimClock = run_clock(1.0 / rate, roundi(seconds * rate))
			results.append(Vector2i(clock.growth_ticks, clock.spread_ticks))
		var want: Vector2i = Vector2i(int(floor(seconds / 0.5 + 1.0e-6)), int(floor(seconds / 1.0 + 1.0e-6)))
		check(results[0] == results[1] and results[1] == results[2] and results[0] == want, "game time %.1f s: growth/spread ticks %s at 30/60/144 Hz equal the expected %s" % [seconds, results, want])
	# Irregular frame times.
	var irregular: SimClock = SimClock.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var total: float = 0.0
	while total < 100.0:
		var dt: float = rng.randf_range(0.001, 0.2)
		total += irregular.advance(dt)
	check(irregular.growth_ticks == int(floor(irregular.elapsed / 0.5 + 1.0e-6)) and irregular.spread_ticks == int(floor(irregular.elapsed + 1.0e-6)), "irregular frame times: ticks follow elapsed game time (%d/%d at %.3f s)" % [irregular.growth_ticks, irregular.spread_ticks, irregular.elapsed])
	# Signals and ordering.
	var clock: SimClock = SimClock.new()
	var order: Array[String] = []
	clock.growth_ticked.connect(func(_i: int) -> void: order.append("G"))
	clock.spread_ticked.connect(func(_i: int) -> void: order.append("S"))
	for i: int in 120:
		clock.advance(1.0 / 60.0)
	check("".join(order) == "GGSGGS" and clock.growth_ticks == 4 and clock.spread_ticks == 2, "signals fire in time order, growth first on ties: %s" % "".join(order))
	# Hitch guard.
	var hitch: SimClock = SimClock.new()
	var used: float = hitch.advance(5.0)
	check(used == hitch.max_advance and hitch.growth_ticks == 0 and absf(hitch.elapsed - 0.25) < 1.0e-9, "a single huge delta is capped at max_advance")
	# Pause.
	var paused_clock: SimClock = SimClock.new()
	for i: int in 90:
		paused_clock.advance(1.0 / 60.0)
	var before: Vector3 = Vector3(paused_clock.elapsed, paused_clock.growth_ticks, paused_clock.spread_ticks)
	paused_clock.paused = true
	for i: int in 600:
		paused_clock.advance(1.0 / 60.0)
	check(Vector3(paused_clock.elapsed, paused_clock.growth_ticks, paused_clock.spread_ticks) == before, "paused clock: no time and no ticks while stopped")
	paused_clock.paused = false
	paused_clock.advance(1.0 / 60.0)
	check(absf(paused_clock.elapsed - before.x - 1.0 / 60.0) < 1.0e-9 and paused_clock.growth_ticks == int(before.y) and paused_clock.spread_ticks == int(before.z), "resume adds one step only, the stopped 10 s are not added in bulk")

func test_pause_in_tree() -> void:
	var tuning: SimTuning = load("res://data/sim_tuning.tres") as SimTuning
	var driver: SimulationDriver = SimulationDriver.new()
	driver.setup(WorldState.new(1, 1, region_def.terrains, 1), tuning)
	root.add_child(driver)
	for i: int in 40:
		await physics_frame
	var running: float = driver.clock.elapsed
	check(running > 0.3, "driver advances game time in physics steps (%.3f s after 40 frames)" % running)
	paused = true
	await physics_frame
	var at_pause: float = driver.clock.elapsed
	var growth_at_pause: int = driver.clock.growth_ticks
	for i: int in 60:
		await physics_frame
	check(driver.clock.elapsed == at_pause and driver.clock.growth_ticks == growth_at_pause, "SceneTree pause freezes the driver clock for 60 frames")
	paused = false
	var frames_after: int = 30
	for i: int in frames_after:
		await physics_frame
	var gained: float = driver.clock.elapsed - at_pause
	check(gained > 0.0 and gained <= (frames_after + 2) / 60.0 + 1.0e-6, "after resume only the frames since resume count (%.3f s over %d frames)" % [gained, frames_after])
	driver.queue_free()

func test_occupancy_and_save() -> void:
	var state: WorldState = small_state(["....", "~#:s", "..~."])
	check(state.occupy(Rect2i(2, 0, 2, 2), 1), "2x2 occupancy on free plantable tiles")
	check(not state.occupy(Rect2i(3, 0, 1, 2), 2) and not state.occupy(Rect2i(2, 0, 2, 2), 1), "overlap and owner reuse are refused")
	check(not state.occupy(Rect2i(0, 1, 2, 2), 3), "occupancy over water or building is refused")
	check(not state.occupy(Rect2i(3, 2, 2, 2), 4), "occupancy beyond the map is refused")
	check(state.owner_at(state.index_of(2, 0)) == 1 and state.owner_at(state.index_of(0, 0)) == 0, "owner lookup")
	check(not state.can_plant(state.index_of(2, 0)), "an occupied tile cannot be planted")
	state.set_stage(state.index_of(3, 0), WorldState.STAGE_SPROUT2)
	state.growth[5] = 123
	state.moisture[2] = 55
	state.fertility[3] = 9
	var text: String = JSON.stringify(state.to_dict())
	var restored: WorldState = WorldState.from_dict(JSON.parse_string(text), region_def.terrains)
	check(restored != null, "to_dict / JSON / from_dict round trip")
	if restored != null:
		var same: bool = restored.terrain == state.terrain and restored.stage == state.stage and restored.plant_id == state.plant_id and restored.growth == state.growth
		same = same and restored.moisture == state.moisture and restored.fertility == state.fertility and restored.sprout_slot == state.sprout_slot and restored.occupant == state.occupant
		check(same, "every per-tile array survives the round trip")
		check(restored.occupancy_owners == state.occupancy_owners and restored.greened_count == state.greened_count and restored.target_count == state.target_count and restored.counters_consistent(), "owners, counters and consistency survive")
	check(state.release(1) and state.owner_at(state.index_of(2, 0)) == 0 and not state.release(1), "release frees the tiles once")
	var broken: Dictionary = state.to_dict()
	broken["width"] = 99
	check(WorldState.from_dict(broken, region_def.terrains) == null, "inconsistent save data is rejected")
	# Full-size round trip.
	var big: WorldState = RegionLoader.load_region(region_def)
	big.set_stage(big.index_of(50, 50), WorldState.STAGE_SPROUT2)
	var started: float = now_ms()
	var packed: String = JSON.stringify(big.to_dict())
	var big_restored: WorldState = WorldState.from_dict(JSON.parse_string(packed), region_def.terrains)
	print("INFO full-region to_dict+JSON+from_dict ms=%.1f json_bytes=%d" % [now_ms() - started, packed.length()])
	check(big_restored != null and big_restored.stage == big.stage and big_restored.greened_count == big.greened_count, "full 512x512 region round trip")

# ---- render ----------------------------------------------------------------------------------

func make_view(state: WorldState, tuning: SimTuning) -> RegionView:
	var view: RegionView = RegionView.new()
	view.setup(state, tuning)
	return view

func tile_pixels(view: RegionView, tx: int, ty: int) -> Array[Color]:
	var image: Image = view.block_images[view.block_of_tile(tx, ty)]
	var result: Array[Color] = []
	for j: int in 4:
		for i: int in 4:
			result.append(image.get_pixel((tx % 64) * 4 + i, (ty % 64) * 4 + j))
	return result

func test_render_pixels() -> void:
	var tuning: SimTuning = SimTuning.new()
	var wasteland: TerrainDef = region_def.terrains[terrain_id(&"wasteland")]
	var ground: Color = wasteland.ground_color
	var expected_edge: Color = ground.lerp(tuning.mature_color, tuning.edge_alpha)
	var rows: Array = []
	for y: int in 8:
		rows.append("........")
	var state: WorldState = small_state(rows)
	var view: RegionView = make_view(state, tuning)
	check(view.block_images.size() == 1 and view.block_images[0].get_size() == Vector2i(256, 256), "a block image is 256x256 px (64x64 tiles)")
	var untouched: Array[Color] = tile_pixels(view, 0, 0)
	var uniform: bool = true
	for pixel: Color in untouched:
		uniform = uniform and near(pixel, ground, 1)
	check(uniform, "empty tile: 16 ground pixels")
	# Stage pixels for every slot.
	var by_slot: Dictionary = {}
	for index: int in 64:
		var slot: int = state.sprout_slot[index]
		if not by_slot.has(slot):
			by_slot[slot] = index
	check(by_slot.size() == 4, "all 4 sprout slots occur on the 8x8 test map")
	for slot: int in by_slot:
		var index: int = by_slot[slot]
		var tx: int = index % 8
		var ty: int = index / 8
		var px: int = 1 + (slot & 1)
		var py: int = 1 + (slot >> 1)
		for stage: int in [1, 2, 3]:
			state.set_stage(index, stage)
			view.flush()
			var pixels: Array[Color] = tile_pixels(view, tx, ty)
			var lit: Array[Vector2i] = []
			for j: int in 4:
				for i: int in 4:
					if not near(pixels[j * 4 + i], ground, 1):
						lit.append(Vector2i(i, j))
			var want_color: Color = tuning.seed_color if stage == 1 else tuning.sprout_color
			var want: Array[Vector2i] = [Vector2i(px, py)]
			if stage == 3:
				want = [Vector2i(px, py - 1), Vector2i(px, py)]
			var colors_ok: bool = true
			for p: Vector2i in lit:
				colors_ok = colors_ok and near(pixels[p.y * 4 + p.x], want_color, 1)
			check(lit == want and colors_ok, "slot %d stage %d: lit pixels %s (want %s), colour ok=%s" % [slot, stage, lit, want, colors_ok])
		state.set_stage(index, 0)
		view.flush()
	# Isolated mature tile at (3,3).
	var mature_index: int = state.index_of(3, 3)
	state.set_stage(mature_index, WorldState.STAGE_MATURE)
	view.flush()
	var m: Array[Color] = tile_pixels(view, 3, 3)
	var inner_ok: bool = true
	var ring_ok: bool = true
	for j: int in 4:
		for i: int in 4:
			var is_inner: bool = i >= 1 and i <= 2 and j >= 1 and j <= 2
			if is_inner:
				inner_ok = inner_ok and near(m[j * 4 + i], tuning.mature_color, 1)
			else:
				ring_ok = ring_ok and near(m[j * 4 + i], expected_edge, 1)
	check(inner_ok, "isolated mature tile: inner 2x2 is opaque mature green")
	check(ring_ok, "isolated mature tile: all 12 outer ring pixels are the half-transparent green composited on the ground")
	check(not near(m[0], ground, 3) and not near(m[0], tuning.mature_color, 3) and m[0].a == 1.0, "ring colour lies strictly between ground and mature and is stored opaque")
	# Pixels around the tile are untouched.
	var around_ok: bool = true
	for p: Vector2i in [Vector2i(2, 3), Vector2i(4, 3), Vector2i(3, 2), Vector2i(3, 4), Vector2i(2, 2), Vector2i(4, 4)]:
		for pixel: Color in tile_pixels(view, p.x, p.y):
			around_ok = around_ok and near(pixel, ground, 1)
	check(around_ok, "neighbouring tiles keep their ground pixels (the ring is inside the tile, nothing bleeds out)")
	# Adjacent mature tile: the shared side becomes opaque on both tiles.
	state.set_stage(state.index_of(4, 3), WorldState.STAGE_MATURE)
	view.flush()
	var a: Array[Color] = tile_pixels(view, 3, 3)
	var b: Array[Color] = tile_pixels(view, 4, 3)
	var shared_ok: bool = near(a[1 * 4 + 3], tuning.mature_color, 1) and near(a[2 * 4 + 3], tuning.mature_color, 1) and near(b[1 * 4 + 0], tuning.mature_color, 1) and near(b[2 * 4 + 0], tuning.mature_color, 1)
	check(shared_ok, "two adjacent mature tiles: the shared side is opaque on both (neighbour was repainted)")
	var other_ok: bool = near(a[0 * 4 + 1], expected_edge, 1) and near(a[3 * 4 + 1], expected_edge, 1) and near(a[1 * 4 + 0], expected_edge, 1) and near(b[0 * 4 + 2], expected_edge, 1) and near(b[3 * 4 + 2], expected_edge, 1) and near(b[1 * 4 + 3], expected_edge, 1)
	check(other_ok, "two adjacent mature tiles: the other sides stay half-transparent")
	var corner_ok: bool = near(a[0 * 4 + 3], expected_edge, 1) and near(a[3 * 4 + 3], expected_edge, 1) and near(b[0 * 4 + 0], expected_edge, 1) and near(b[3 * 4 + 0], expected_edge, 1)
	check(corner_ok, "corner pixels on the shared side stay half-transparent (they lie on the top / bottom ring)")
	# Back to a sprout: both rings are isolated again.
	state.set_stage(state.index_of(4, 3), WorldState.STAGE_SPROUT1)
	view.flush()
	a = tile_pixels(view, 3, 3)
	check(near(a[1 * 4 + 3], expected_edge, 1) and near(a[2 * 4 + 3], expected_edge, 1), "when the neighbour stops being mature the shared side becomes half-transparent again")
	# Diagonal neighbours do not count.
	var diagonal: WorldState = small_state(rows)
	var diagonal_view: RegionView = make_view(diagonal, tuning)
	diagonal.set_stage(diagonal.index_of(2, 2), WorldState.STAGE_MATURE)
	diagonal.set_stage(diagonal.index_of(3, 3), WorldState.STAGE_MATURE)
	diagonal_view.flush()
	var d: Array[Color] = tile_pixels(diagonal_view, 3, 3)
	var diagonal_ok: bool = true
	for j: int in 4:
		for i: int in 4:
			var is_inner: bool = i >= 1 and i <= 2 and j >= 1 and j <= 2
			diagonal_ok = diagonal_ok and near(d[j * 4 + i], tuning.mature_color if is_inner else expected_edge, 1)
	check(diagonal_ok, "diagonal mature neighbour does not change the edge (full ring still half-transparent)")
	# 3x3 block: only the outer ring of the block is half-transparent.
	var block: WorldState = small_state(rows)
	var block_view: RegionView = make_view(block, tuning)
	block.debug_fill_stage(Rect2i(2, 2, 3, 3), WorldState.STAGE_MATURE)
	block_view.flush()
	var centre: Array[Color] = tile_pixels(block_view, 3, 3)
	var centre_ok: bool = true
	for pixel: Color in centre:
		centre_ok = centre_ok and near(pixel, tuning.mature_color, 1)
	check(centre_ok, "centre tile of a 3x3 mature block is fully opaque")
	# Ground composite honours the terrain: a mature tile on the shore blends with the shore colour.
	var shore_state: WorldState = small_state([":."])
	var shore_view: RegionView = make_view(shore_state, tuning)
	shore_state.set_stage(0, WorldState.STAGE_MATURE)
	shore_view.flush()
	var shore_ground: Color = region_def.terrains[terrain_id(&"shore")].ground_color
	check(near(tile_pixels(shore_view, 0, 0)[0], shore_ground.lerp(tuning.mature_color, tuning.edge_alpha), 1), "edge is composited over the tile's own terrain ground colour")

func test_render_dirty_blocks() -> void:
	var tuning: SimTuning = load("res://data/sim_tuning.tres") as SimTuning
	var state: WorldState = RegionLoader.load_region(region_def)
	var view: RegionView = make_view(state, tuning)
	check(view.block_images.size() == 64 and view.blocks_x == 8 and view.blocks_y == 8, "512x512 tiles make 8x8 = 64 blocks")
	view.flush()
	check(view.last_flush_tiles == 0 and view.last_flush_blocks == 0, "a flush with no change repaints and uploads nothing")
	var wasteland: int = terrain_id(&"wasteland")
	check(state.terrain[state.index_of(10, 10)] == wasteland and state.terrain[state.index_of(62, 10)] == wasteland and state.terrain[state.index_of(64, 10)] == wasteland and state.terrain[state.index_of(63, 10)] == wasteland, "test tiles are wasteland")
	state.set_stage(state.index_of(10, 10), WorldState.STAGE_SPROUT1)
	view.flush()
	check(view.last_flush_tiles == 1 and view.last_flush_blocks == 1, "one non-mature change repaints 1 tile and uploads 1 block (%d/%d)" % [view.last_flush_tiles, view.last_flush_blocks])
	state.set_stage(state.index_of(63, 10), WorldState.STAGE_MATURE)
	view.flush()
	check(view.last_flush_tiles == 5 and view.last_flush_blocks == 2, "a mature tile on a block boundary repaints itself and 4 neighbours, uploading exactly the 2 touched blocks (%d/%d)" % [view.last_flush_tiles, view.last_flush_blocks])
	var start: Vector2i = region_def.start_tile
	var start_pixels: Array[Color] = tile_pixels(view, start.x, start.y)
	var interior_ok: bool = true
	for pixel: Color in start_pixels:
		interior_ok = interior_ok and near(pixel, tuning.mature_color, 1)
	check(interior_ok, "the start tile (inside the mature safe zone) is fully green")

func test_performance() -> void:
	var tuning: SimTuning = load("res://data/sim_tuning.tres") as SimTuning
	var t0: float = now_ms()
	var state: WorldState = RegionLoader.load_region(region_def)
	var t1: float = now_ms()
	var view: RegionView = make_view(state, tuning)
	var t2: float = now_ms()
	print("PERF load_region_ms=%.1f initial_full_render_ms=%.1f total_init_ms=%.1f" % [t1 - t0, t2 - t1, t2 - t0])
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	var picked: Array[int] = []
	while picked.size() < 1000:
		var index: int = rng.randi_range(0, state.tile_count() - 1)
		if state.target[index] == 1 and state.stage[index] == 0:
			picked.append(index)
	var t3: float = now_ms()
	for index: int in picked:
		state.set_stage(index, WorldState.STAGE_SPROUT1)
	view.flush()
	var t4: float = now_ms()
	print("PERF scattered_1000_sprout1_set_and_render_ms=%.2f tiles=%d blocks_uploaded=%d" % [t4 - t3, view.last_flush_tiles, view.last_flush_blocks])
	var t5: float = now_ms()
	for index: int in picked:
		state.set_stage(index, WorldState.STAGE_MATURE)
	view.flush()
	var t6: float = now_ms()
	print("PERF scattered_1000_mature_set_and_render_ms=%.2f tiles=%d blocks_uploaded=%d" % [t6 - t5, view.last_flush_tiles, view.last_flush_blocks])
	# A clustered change (a 32x32 patch) for comparison.
	var t7: float = now_ms()
	state.debug_fill_stage(Rect2i(160, 150, 32, 32), WorldState.STAGE_MATURE)
	view.flush()
	var t8: float = now_ms()
	print("PERF clustered_1024_mature_patch_ms=%.2f tiles=%d blocks_uploaded=%d" % [t8 - t7, view.last_flush_tiles, view.last_flush_blocks])
	var t9: float = now_ms()
	view.flush()
	print("PERF idle_flush_ms=%.3f" % (now_ms() - t9))
	check(t2 - t0 < 3000.0, "region initialisation (load + first full render) stays under 3 s (%.0f ms)" % (t2 - t0))
	check(t6 - t5 < 500.0, "1000 scattered changes are set and repainted in under 500 ms (%.0f ms)" % (t6 - t5))
