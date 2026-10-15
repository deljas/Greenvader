extends SceneTree
## P2-01 headless checks: zones (layer PNG, states, per-zone counters), nests (occupancy, bands, spread / seeds / cultivated
## plants refused), spawning (interval, per-nest and global limits, 30 minutes of idle time), boars (zone, tether, terrain,
## stable zones, gnawing, counters, safe zone), pause, frame-rate independence (30 / 60 / 144 Hz), save round trips, hit shapes.
## Run: Godot --headless --path <project> --script res://tests/p2/p2_01_checks.gd [-- --skip-long]
## Expected values come from the ticket (12 s interval, limits 4 / 40, tether 48 tiles, 15 nests) and from geometry written
## here (band cuts, zone colours and terrain keys are written below, not read from the game's own tables).

const REGION_PATH: String = "res://data/region_01.tres"
const TILE: int = 4
## Zone layer legend written independently of the ZoneDef resources: RGB hex -> zone id.
const ZONE_COLORS: Dictionary = {0x60b060: 0, 0xe08060: 1, 0xe0c040: 2, 0xc060a0: 3, 0x60a0e0: 4, 0xa080e0: 5, 0x40c0c0: 6}
## Band cuts of the zone layer (rows) written from the zone design: west bank 1 | 0 | 2 | 3, east bank 4 | 5 | 6.
const WEST_CUTS: Array[int] = [125, 260, 390]
const WEST_IDS: Array[int] = [1, 0, 2, 3]
const EAST_CUTS: Array[int] = [180, 340]
const EAST_IDS: Array[int] = [4, 5, 6]
const C_WASTELAND: int = 0xb0a060
const C_SAFE: int = 0x60b060
const C_SHORE: int = 0xe0d090

var failures: int = 0
var checks: int = 0
var region_def: RegionDef
var sim_tuning: SimTuning
var play_tuning: PlayTuning
var enemy_tuning: EnemyTuning
var info: Dictionary = {}
var skip_long: bool = false

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
	play_tuning = load("res://data/play_tuning.tres") as PlayTuning
	enemy_tuning = load("res://data/enemy_tuning.tres") as EnemyTuning
	check(region_def != null and enemy_tuning != null, "region and enemy tuning load")
	test_tuning_values()
	test_zone_layer()
	test_zone_counters()
	test_world_save_zones()
	test_nests()
	test_nest_exclusion()
	test_nest_destroy()
	test_spawn_interval_and_caps()
	test_boar_confinement()
	test_gnaw_and_counters()
	test_stable_zone()
	test_border_safety()
	test_hit_shapes()
	test_field_save()
	test_frame_rates()
	await test_scene_pause()
	if not skip_long:
		test_long_run()
	print("INFO " + JSON.stringify(info))
	print("P2_01_RESULT checks=%d failures=%d" % [checks, failures])
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path("res://evidence/p2/p2-01/checks_info.json"), FileAccess.WRITE)
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

func tune(overrides: Dictionary = {}) -> EnemyTuning:
	var copy: EnemyTuning = enemy_tuning.duplicate() as EnemyTuning
	for key: String in overrides:
		copy.set(key, overrides[key])
	return copy

## Small world from rows of glyphs ('.' wasteland, '~' water, '#' building) through the real loader; zone 0 = x < split
## (unconquered), zone 1 = x >= split (state `right_state`).
func small_world(rows: Array, split: int, right_state: int = WorldState.ZONE_STABLE) -> WorldState:
	var def: RegionDef = RegionDef.new()
	def.width_tiles = String(rows[0]).length()
	def.height_tiles = rows.size()
	def.terrains = region_def.terrains
	def.sprout_seed = region_def.sprout_seed
	var image: Image = Image.create(def.width_tiles, def.height_tiles, false, Image.FORMAT_RGB8)
	var glyphs: Dictionary = {".": &"wasteland", "~": &"water", "#": &"building", ":": &"shore"}
	for y: int in rows.size():
		for x: int in String(rows[y]).length():
			var v: Vector3i = c8(terrain_def(glyphs[String(rows[y])[x]]).map_color)
			image.set_pixel(x, y, Color8(v.x, v.y, v.z))
	var world: WorldState = RegionLoader.build_state(def, image)
	var ids: PackedByteArray = PackedByteArray()
	ids.resize(world.tile_count())
	for index: int in world.tile_count():
		ids[index] = 0 if index % world.width < split else 1
	world.set_zones(ids, PackedByteArray([WorldState.ZONE_UNCONQUERED, right_state]))
	return world

func open_rows(width: int, height: int) -> Array:
	var rows: Array = []
	for y: int in height:
		rows.append(".".repeat(width))
	return rows

## Plants (mature) every free tile of the rectangle (tiles under an occupant are skipped, like a real landing would).
func fill_plants(world: WorldState, rect: Rect2i, stage: int = WorldState.STAGE_MATURE) -> int:
	var count: int = 0
	for y: int in range(maxi(rect.position.y, 0), mini(rect.end.y, world.height)):
		for x: int in range(maxi(rect.position.x, 0), mini(rect.end.x, world.width)):
			var index: int = world.index_of(x, y)
			if world.occupant[index] == 0 and world.stage[index] == WorldState.STAGE_EMPTY and world.set_stage(index, stage):
				count += 1
	return count

func real_world() -> WorldState:
	return RegionLoader.load_region(region_def)

## Reason string when the boar breaks a standing rule (zone, tether, terrain), "" when fine. Terrain uses the keys of the
## legend (water / building are blocked), not the walkable flags.
func violation(world: WorldState, boar: Boar, tuning: EnemyTuning) -> String:
	var p: Vector2 = boar.pos
	if p.distance_to(boar.home) > float(tuning.tether_tiles * TILE) + 0.01:
		return "tether %.3f" % p.distance_to(boar.home)
	var hx: float = tuning.boar_half_width_px
	var hy: float = tuning.boar_half_height_px
	for y: int in range(floori((p.y - hy + 1.0e-3) / TILE), ceili((p.y + hy - 1.0e-3) / TILE)):
		for x: int in range(floori((p.x - hx + 1.0e-3) / TILE), ceili((p.x + hx - 1.0e-3) / TILE)):
			if not world.in_bounds(x, y):
				return "bounds"
			var index: int = world.index_of(x, y)
			var key: StringName = world.terrain_defs[world.terrain[index]].key
			if key == &"water" or key == &"building":
				return "terrain %s at %d,%d" % [key, x, y]
			if world.zone_of[index] != boar.zone:
				return "zone %d != %d at %d,%d" % [world.zone_of[index], boar.zone, x, y]
	return ""

# ---- tuning ----------------------------------------------------------------------------------------------------------

func test_tuning_values() -> void:
	check(enemy_tuning.spawn_interval_seconds == 12.0 and enemy_tuning.nest_boar_cap == 4 and enemy_tuning.boar_cap == 40, "tuning: 12 s interval, 4 per nest, 40 in total")
	check(enemy_tuning.tether_tiles == 48 and enemy_tuning.nest_size_tiles == 4 and enemy_tuning.nest_max_count == 15, "tuning: tether 48 tiles, nest 4x4, at most 15 nests")
	check(enemy_tuning.arrival_px <= enemy_tuning.gnaw_radius_tiles * TILE, "tuning: a reached plant is inside the gnaw radius (no endless re-choice)")

# ---- zones -----------------------------------------------------------------------------------------------------------

func test_zone_layer() -> void:
	check(region_def.zones.size() >= 6 and region_def.zones.size() <= 8, "the region has %d zones (about six)" % region_def.zones.size())
	var world: WorldState = real_world()
	check(world != null and world.zone_count == region_def.zones.size(), "the loader builds the zone layer (%d zones)" % world.zone_count)
	# Independent read of the layer PNG: every pixel has a legend colour; the loader's zone ids equal the legend ids.
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(region_def.zone_map_path))
	image.convert(Image.FORMAT_RGB8)
	check(image.get_width() == 512 and image.get_height() == 512, "the zone layer is 512x512 (1 px = 1 tile)")
	var unknown: int = 0
	var wrong: int = 0
	var per_zone: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	for y: int in 512:
		for x: int in 512:
			var c: Color = image.get_pixel(x, y)
			var key: int = (roundi(c.r * 255.0) << 16) | (roundi(c.g * 255.0) << 8) | roundi(c.b * 255.0)
			if not ZONE_COLORS.has(key):
				unknown += 1
				continue
			per_zone[ZONE_COLORS[key]] += 1
			if world.zone_of[y * 512 + x] != ZONE_COLORS[key]:
				wrong += 1
	check(unknown == 0, "every tile of the zone layer has a legend colour (unknown: %d)" % unknown)
	check(wrong == 0, "WorldState.zone_of equals the legend id of every pixel (mismatches: %d)" % wrong)
	var all_used: bool = true
	for count: int in per_zone:
		all_used = all_used and count > 5000
	check(all_used, "every zone is a real area (tiles per zone %s)" % per_zone)
	info["zone_tiles"] = Array(per_zone)
	# Band geometry written from the design: far west column x=10 and far east column x=500 follow the cuts.
	var band_errors: int = 0
	for y: int in 512:
		var west: int = 0
		while west < WEST_CUTS.size() and y >= WEST_CUTS[west]:
			west += 1
		var east: int = 0
		while east < EAST_CUTS.size() and y >= EAST_CUTS[east]:
			east += 1
		if world.zone_of[y * 512 + 10] != WEST_IDS[west] or world.zone_of[y * 512 + 500] != EAST_IDS[east]:
			band_errors += 1
	check(band_errors == 0, "west and east bands follow the cuts (rows with a wrong zone: %d)" % band_errors)
	# The river separates the banks: a tile west of the river is never in an east zone and vice versa on every row.
	var bank_errors: int = 0
	for y: int in 512:
		if world.zone_of[y * 512 + 150] > 3 or world.zone_of[y * 512 + 380] < 4:
			bank_errors += 1
	check(bank_errors == 0, "west of the river only zones 0-3, east of it only zones 4-6 (bad rows: %d)" % bank_errors)
	# States: the zone of the start tile is stable from the beginning, the others are unconquered.
	var start_zone: int = world.zone_of[world.index_of(region_def.start_tile.x, region_def.start_tile.y)]
	check(start_zone == 0 and world.zone_state[0] == WorldState.ZONE_STABLE, "the start tile lies in zone 0, which is stable from the start")
	var others_ok: bool = true
	for zone: int in range(1, world.zone_count):
		others_ok = others_ok and world.zone_state[zone] == WorldState.ZONE_UNCONQUERED
	check(others_ok, "all other zones start unconquered")
	# Counters: per-zone targets add up to the total, equal the recount and the independent PNG count; greened likewise.
	var sum_targets: int = 0
	var sum_greened: int = 0
	for zone: int in world.zone_count:
		sum_targets += world.zone_target_count[zone]
		sum_greened += world.zone_greened_count[zone]
	var terrain_image: Image = Image.load_from_file(ProjectSettings.globalize_path(region_def.map_path))
	terrain_image.convert(Image.FORMAT_RGB8)
	var png_targets: int = 0
	var png_targets_by_zone: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	var png_safe: int = 0
	for y: int in 512:
		for x: int in 512:
			var c: Color = terrain_image.get_pixel(x, y)
			var key: int = (roundi(c.r * 255.0) << 16) | (roundi(c.g * 255.0) << 8) | roundi(c.b * 255.0)
			if key == C_WASTELAND or key == C_SAFE or key == C_SHORE:
				png_targets += 1
				png_targets_by_zone[world.zone_of[y * 512 + x]] += 1
				png_safe += 1 if key == C_SAFE else 0
	check(sum_targets == world.target_count and sum_targets == png_targets, "zone target counts add up to the total (%d), which equals the PNG's target pixels (%d)" % [sum_targets, png_targets])
	check(png_targets_by_zone == world.zone_target_count, "per-zone target counts equal an independent PNG count")
	check(sum_greened == world.greened_count and world.zone_greened_count[0] == png_safe, "greened counts add up (%d); all of them are the start zone's %d mature safe tiles" % [sum_greened, png_safe])
	check(world.counters_consistent(), "all counters (greening, mature, plants, zones) match a full recount at load")
	var determinism: Array = []
	var out_path: String = ProjectSettings.globalize_path("user://p2_01_regen_zones.png")
	var code: int = OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/tools/gen_zones_region_01.gd", "--", "--out=" + out_path], determinism, true)
	var original: String = FileAccess.get_sha256(ProjectSettings.globalize_path(region_def.zone_map_path))
	var regenerated: String = FileAccess.get_sha256(out_path)
	check(code == 0 and original == regenerated and not original.is_empty(), "regenerating the zone layer gives byte-identical data/region_01_zones.png (sha256 %s)" % original.substr(0, 16))
	info["zone_map_sha256"] = original

func test_zone_counters() -> void:
	var world: WorldState = real_world()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 77
	var stages: Array[int] = [0, 1, 2, 3, 4]
	var consistent: bool = true
	var greened_before: int = world.greened_count
	for step: int in 30000:
		var index: int = rng.randi_range(0, world.tile_count() - 1)
		# Concentrate on the zones' tiles near the middle of the map as well as anywhere (water is refused by set_stage).
		world.set_stage(index, stages[rng.randi_range(0, 4)])
		if step % 10000 == 9999:
			consistent = consistent and world.counters_consistent() and world.plant_chunk_count == world.recount_plant_chunks()
	check(consistent and world.greened_count != greened_before, "30,000 random stage changes: greening, mature, plant, per-zone and per-chunk counters stay equal to the recounts")
	var sum: int = 0
	for zone: int in world.zone_count:
		sum += world.zone_greened_count[zone]
	check(sum == world.greened_count, "per-zone greened counts still add up to the total (%d)" % sum)

func test_world_save_zones() -> void:
	var world: WorldState = real_world()
	world.set_zone_state(3, WorldState.ZONE_CLEARING)
	world.set_zone_state(5, WorldState.ZONE_STABLE)
	fill_plants(world, Rect2i(60, 300, 20, 20), WorldState.STAGE_SPROUT1)
	var saved: Dictionary = world.to_dict()
	var copy: WorldState = WorldState.from_dict(saved, world.terrain_defs)
	check(copy != null and copy.zone_of == world.zone_of and copy.zone_state == world.zone_state and copy.zone_count == world.zone_count, "a saved world restores zone ids, count and states")
	check(copy != null and copy.zone_target_count == world.zone_target_count and copy.zone_greened_count == world.zone_greened_count and copy.counters_consistent(), "a restored world has the same per-zone counters (and they match a recount)")
	var json_text: String = JSON.stringify(saved)
	var parsed: Variant = JSON.parse_string(json_text)
	var from_json: WorldState = WorldState.from_dict(parsed, world.terrain_defs) if parsed is Dictionary else null
	check(from_json != null and from_json.zone_state == world.zone_state and from_json.zone_of == world.zone_of and from_json.stage == world.stage, "the zone data survives a JSON text round trip")
	var bad: Dictionary = saved.duplicate(true)
	bad["zones"]["state"] = [0, 9, 0, 0, 0, 0, 0]
	check(WorldState.from_dict(bad, world.terrain_defs) == null, "a saved zone state out of range is refused")
	var old_format: Dictionary = saved.duplicate(true)
	old_format.erase("zones")
	var legacy: WorldState = WorldState.from_dict(old_format, world.terrain_defs)
	check(legacy != null and legacy.zone_count == 1 and legacy.counters_consistent(), "a save without zones (older format) loads as one unconquered zone")

# ---- nests -----------------------------------------------------------------------------------------------------------

func real_field(overrides: Dictionary = {}) -> Array:
	var world: WorldState = real_world()
	var field: EnemyField = EnemyField.new(world, tune(overrides), TILE)
	field.setup_nests(region_def.zones)
	return [world, field]

func test_nests() -> void:
	var rig: Array = real_field()
	var world: WorldState = rig[0]
	var field: EnemyField = rig[1]
	check(field.nests.size() == 15 and field.alive_nest_count() == 15, "15 nests are placed (the allowed maximum)")
	var per_zone: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	var owners_ok: bool = true
	var inside_ok: bool = true
	var bands_ok: bool = true
	var ids: Dictionary = {}
	for nest: Nest in field.nests:
		per_zone[nest.zone] += 1
		ids[nest.owner_id()] = true
		bands_ok = bands_ok and nest.owner_id() >= 1000000
		for y: int in range(nest.tile.y, nest.tile.y + 4):
			for x: int in range(nest.tile.x, nest.tile.x + 4):
				var index: int = world.index_of(x, y)
				owners_ok = owners_ok and world.occupant[index] == nest.owner_id() and world.target[index] == 1
				inside_ok = inside_ok and world.zone_of[index] == nest.zone
	check(per_zone[0] == 0, "no nest in the stable start zone")
	var counts_ok: bool = true
	for zone: int in range(1, 7):
		counts_ok = counts_ok and per_zone[zone] >= 1 and per_zone[zone] <= 3
	check(counts_ok, "every unconquered zone has 1 to 3 nests (per zone %s)" % per_zone)
	check(owners_ok and inside_ok, "every nest occupies its 4x4 block of greening-target tiles, completely inside its own zone")
	check(ids.size() == 15 and bands_ok, "15 distinct owner ids, all in the nest band (>= 1,000,000)")
	check(WorldState.OWNER_BAND_CULTIVATED == Cultivation.OWNER_BASE and Cultivation.OWNER_BASE < WorldState.OWNER_BAND_HELPER and WorldState.OWNER_BAND_HELPER < WorldState.OWNER_BAND_NEST, "owner id bands are ordered: cultivated < helper < nest")
	var occupied_tiles: int = 0
	for index: int in world.tile_count():
		occupied_tiles += 1 if world.occupant[index] != 0 else 0
	check(occupied_tiles == 15 * 16, "exactly 15 x 16 tiles are occupied (%d)" % occupied_tiles)
	# Nest tiles count as targets: the zone totals did not change by placing the nests.
	var reference: WorldState = real_world()
	check(reference.zone_target_count == world.zone_target_count and reference.target_count == world.target_count, "nest tiles stay in the greening-target counts (they can be greened once the nest is gone)")
	# A site that does not fit is refused: inside the water of the river / over another nest / across a zone border.
	var bad_water: Nest = field.add_nest(1, Vector2i(255, 100))
	var overlap: Nest = field.add_nest(field.nests[0].zone, field.nests[0].tile + Vector2i(2, 2))
	var across: Nest = field.add_nest(1, Vector2i(100, 122))
	check(bad_water == null and overlap == null and across == null, "nest sites in the water, overlapping a nest or crossing a zone border are refused")
	check(world.counters_consistent(), "counters still match a recount with the nests in place")

func nest_tiles(nest: Nest) -> PackedInt32Array:
	var tiles: PackedInt32Array = PackedInt32Array()
	for y: int in range(nest.tile.y, nest.tile.y + nest.size):
		for x: int in range(nest.tile.x, nest.tile.x + nest.size):
			tiles.append(y * 512 + x)
	return tiles

func test_nest_exclusion() -> void:
	var rig: Array = real_field()
	var world: WorldState = rig[0]
	var field: EnemyField = rig[1]
	var spread: SpreadSim = SpreadSim.new(world, sim_tuning)
	spread.allow_hook = field.spread_allows
	var nest: Nest = field.nests[0]
	var tiles: PackedInt32Array = nest_tiles(nest)
	var around: Rect2i = Rect2i(nest.tile.x - 6, nest.tile.y - 6, 16, 16)
	fill_plants(world, around)
	var planted_inside: int = 0
	for index: int in tiles:
		planted_inside += 1 if world.stage[index] != WorldState.STAGE_EMPTY else 0
	check(planted_inside == 0, "a mature field around the nest leaves the nest's own tiles free")
	var can_plant_any: bool = false
	var hook_any: bool = false
	for index: int in tiles:
		can_plant_any = can_plant_any or world.can_plant(index)
		hook_any = hook_any or field.spread_allows(index)
	check(not can_plant_any and not hook_any, "can_plant and the spread hook both refuse every nest tile")
	check(field.spread_allows(world.index_of(nest.tile.x - 10, nest.tile.y)) and field.spread_allows(world.index_of(nest.tile.x - 3, nest.tile.y)), "the hook allows ground next to the nest (unconquered zones can be spread into)")
	# Manual seeds: landings on the nest and on its edge never plant a nest tile.
	var seeds_in_nest: int = 0
	var landing_seed: int = 5
	for offset: Vector2 in [Vector2(8, 8), Vector2(0, 0), Vector2(16, 16), Vector2(0, 8), Vector2(8, 16), Vector2(4, 4)]:
		landing_seed += 1
		var point: Vector2 = Vector2(nest.tile) * TILE + offset
		for index: int in Landing.scatter_seeds(world, TILE, point, 10.0, 6, landing_seed):
			seeds_in_nest += 1 if world.occupant[index] != 0 else 0
	check(seeds_in_nest == 0, "seed landings on / beside the nest never plant a nest tile")
	# Natural spread: 200 spread ticks with mature ground all around.
	for tick: int in 200:
		spread.tick()
	var spread_in_nest: int = 0
	for index: int in tiles:
		spread_in_nest += 1 if world.stage[index] != WorldState.STAGE_EMPTY else 0
	check(spread.total_planted > 0 and spread_in_nest == 0, "natural spread kept planting around the nest (%d seeds) but never inside it" % spread.total_planted)
	# Cultivated plants: shots on the nest and next to it never place a block that touches the nest.
	var cultivation: Cultivation = Cultivation.new(world, play_tuning, TILE, _plant_defs())
	var touched: int = 0
	var placed: int = 0
	for offset: Vector2 in [Vector2(8, 8), Vector2(-2, 8), Vector2(8, -2), Vector2(18, 18), Vector2(0, 0)]:
		var plant: CultivatedPlant = cultivation.try_place(&"carrot", Vector2(nest.tile) * TILE + offset)
		if plant != null:
			placed += 1
			for index: int in tiles:
				touched += 1 if world.occupant[index] != nest.owner_id() else 0
	check(touched == 0 and placed >= 1, "carrot shots around the nest were placed (%d) without ever covering a nest tile" % placed)
	check(world.occupancy_owners.has(nest.owner_id()) and Rect2i(world.occupancy_owners[nest.owner_id()]) == nest.rect(), "the nest's occupancy block is unchanged")

func _plant_defs() -> Array[PlantDef]:
	var defs: Array[PlantDef] = []
	defs.assign(region_def.plants)
	return defs

func test_nest_destroy() -> void:
	var rig: Array = real_field()
	var world: WorldState = rig[0]
	var field: EnemyField = rig[1]
	var spread: SpreadSim = SpreadSim.new(world, sim_tuning)
	spread.allow_hook = field.spread_allows
	var nest: Nest = field.nests[1]
	var tiles: PackedInt32Array = nest_tiles(nest)
	fill_plants(world, Rect2i(nest.tile.x - 6, nest.tile.y - 6, 16, 16))
	check(field.damage_nest(nest, 5) == false and nest.hp == nest.hp_max - 5 and nest.alive, "damage below the hit points leaves the nest standing")
	check(field.damage_nest(nest, 1000) == true and not nest.alive and nest.hp == 0, "enough damage destroys the nest")
	var free: bool = true
	for index: int in tiles:
		free = free and world.can_plant(index) and field.spread_allows(index) and world.occupant[index] == 0
	check(free and not world.occupancy_owners.has(nest.owner_id()), "a destroyed nest frees its tiles: plantable again, spread allowed")
	for tick: int in 120:
		spread.tick()
	var planted_after: int = 0
	for index: int in tiles:
		planted_after += 1 if world.stage[index] != WorldState.STAGE_EMPTY else 0
	check(planted_after > 0, "after the nest is gone natural spread plants its tiles (%d of 16 in 120 ticks)" % planted_after)
	check(field.damage_nest(nest, 1) == false and field.alive_nest_count() == 14, "a destroyed nest cannot be destroyed twice; 14 nests are left")
	check(world.counters_consistent(), "counters match a recount after a nest was destroyed and planted over")

# ---- spawning --------------------------------------------------------------------------------------------------------

## One nest on an open small world (zone 0), returns [world, field, nest].
func single_nest(overrides: Dictionary = {}) -> Array:
	var world: WorldState = small_world(open_rows(120, 60), 120)
	var field: EnemyField = EnemyField.new(world, tune(overrides), TILE)
	var nest: Nest = field.add_nest(0, Vector2i(30, 28))
	return [world, field, nest]

func test_spawn_interval_and_caps() -> void:
	var rig: Array = single_nest()
	var field: EnemyField = rig[1]
	var nest: Nest = rig[2]
	check(nest != null, "a nest is placed on the open test map")
	var first_at: float = -1.0
	var second_at: float = -1.0
	var max_boars: int = 0
	var dt: float = 1.0 / 60.0
	var spawned_before: int = 0
	for step: int in range(1, 60 * 130):
		field.advance(dt)
		max_boars = maxi(max_boars, field.boars.size())
		if field.total_spawned != spawned_before:
			spawned_before = field.total_spawned
			if first_at < 0.0:
				first_at = float(step) * dt
			elif second_at < 0.0:
				second_at = float(step) * dt
		if first_at < 0.0:
			if field.boars.size() != 0:
				check(false, "no boar before the interval")
				break
	check(absf(first_at - 12.0) < 0.02 and absf(second_at - 24.0) < 0.02, "the first boar appears at 12 s (%.3f) and the second at 24 s (%.3f)" % [first_at, second_at])
	check(field.boars.size() == 4 and max_boars == 4 and nest.boar_count == 4 and nest.spawned == 4, "the nest stops at its limit of 4 boars after 130 s (%d, max %d)" % [field.boars.size(), max_boars])
	# A kill frees a slot: the next boar comes one full interval later (the timer did not run while the nest was full).
	var victim: Boar = field.boars[0]
	check(field.damage_boar(victim, 99) and field.boars.size() == 3 and nest.boar_count == 3 and field.total_killed == 1, "a killed boar leaves the list and frees its nest slot")
	var at: float = 0.0
	var respawn_at: float = -1.0
	while at < 40.0 and respawn_at < 0.0:
		field.advance(dt)
		at += dt
		if field.boars.size() == 4:
			respawn_at = at
	check(absf(respawn_at - 12.0) < 0.05, "the replacement boar comes one interval after the kill (%.3f s)" % respawn_at)
	# Without a nest nothing appears: a destroyed nest, a field without nests, a nest whose zone became stable.
	var rig2: Array = single_nest()
	var field2: EnemyField = rig2[1]
	field2.destroy_nest(rig2[2])
	for i: int in 60 * 60:
		field2.advance(dt)
	check(field2.boars.is_empty() and field2.total_spawned == 0, "a destroyed nest spawns nothing in 60 s")
	var world3: WorldState = small_world(open_rows(60, 40), 60)
	var field3: EnemyField = EnemyField.new(world3, tune(), TILE)
	for i: int in 60 * 60:
		field3.advance(dt)
	check(field3.boars.is_empty(), "a field without any nest spawns nothing in 60 s")
	var rig4: Array = single_nest()
	var field4: EnemyField = rig4[1]
	for i: int in 60 * 30:
		field4.advance(dt)
	var before_stable: int = field4.boars.size()
	rig4[0].set_zone_state(0, WorldState.ZONE_STABLE)
	for i: int in 60 * 60:
		field4.advance(dt)
	# P2-04: the boars of a zone that becomes stable vanish at once (they no longer stand still), and its nest spawns nothing more.
	check(before_stable == 2 and field4.boars.is_empty() and field4.total_spawned == before_stable, "a nest in a stable zone stops spawning (%d boars before, %d after, %d spawned in total); the boars left with the state change (P2-04)" % [before_stable, field4.boars.size(), field4.total_spawned])
	# Disabled switch.
	var rig5: Array = single_nest({"enabled": false})
	for i: int in 60 * 30:
		rig5[1].advance(dt)
	check(rig5[1].boars.is_empty() and rig5[1].steps_done == 0, "enabled = false: the enemy simulation does nothing")
	# Spawn positions: walkable target ground on the ring around the nest, outside the block.
	var rig6: Array = single_nest()
	for i: int in 60 * 50:
		rig6[1].advance(dt)
	var pos_ok: bool = true
	var outside: bool = true
	for boar: Boar in rig6[1].boars:
		pos_ok = pos_ok and violation(rig6[0], boar, rig6[1].tuning) == ""
	check(rig6[1].boars.size() == 4 and pos_ok, "spawned boars stand on walkable ground in their zone")
	var probe_nest: Nest = rig6[1].add_nest(0, Vector2i(80, 10))
	for i: int in 60 * 13:
		rig6[1].advance(dt)
	var spawn_boar: Boar = null
	for candidate: Boar in rig6[1].boars:
		if candidate.nest_id == probe_nest.id:
			spawn_boar = candidate
	var ring: float = spawn_boar.pos.distance_to(probe_nest.center_px(TILE)) if spawn_boar != null else -1.0
	outside = spawn_boar != null and not probe_nest.rect().has_point(Vector2i(floori(spawn_boar.pos.x / TILE), floori(spawn_boar.pos.y / TILE))) and ring > 8.0 and ring < 30.0
	check(outside, "a boar appears next to the nest, outside its block (distance %.1f px)" % ring)

# ---- boar rules on small maps ----------------------------------------------------------------------------------------

## Boar of a fresh nest, with its decisions switched off (it only follows the goal set by the test).
func forced_boar(world: WorldState, field: EnemyField, nest: Nest) -> Boar:
	var dt: float = 1.0 / 60.0
	for i: int in 60 * 13:
		field.advance(dt)
	var boar: Boar = field.boars[0]
	boar.think = 1000000
	boar.wait = 0
	boar.goal_tile = -1
	boar.mode = Boar.MODE_WANDER
	return boar

func run_forced(world: WorldState, field: EnemyField, boar: Boar, start: Vector2, goal: Vector2, seconds: float, tuning: EnemyTuning) -> Dictionary:
	boar.pos = start
	boar.goal = goal
	boar.window_pos = start
	boar.window_steps = 0
	var dt: float = 1.0 / 60.0
	var bad: String = ""
	var farthest: Vector2 = start
	for i: int in int(seconds * 60.0):
		field.advance(dt)
		boar.think = 1000000
		var why: String = violation(world, boar, tuning)
		if why != "" and bad == "":
			bad = "t=%.2f %s at %s" % [float(i) * dt, why, boar.pos]
		if boar.goal == Vector2.INF and why == "":
			break
		if (boar.pos - start).length() > (farthest - start).length():
			farthest = boar.pos
	return {"bad": bad, "pos": boar.pos}

func test_boar_confinement() -> void:
	var tuning: EnemyTuning = tune({"spawn_interval_seconds": 12.0})
	# 1. Water: a river column on x = 20..21 (rows 0..39); the boar west of it aims straight across.
	var rows: Array = open_rows(100, 60)
	for y: int in 40:
		rows[y] = ".".repeat(20) + "~~" + ".".repeat(78)
	var world: WorldState = small_world(rows, 100)
	var field: EnemyField = EnemyField.new(world, tuning, TILE)
	var nest: Nest = field.add_nest(0, Vector2i(6, 18))
	var boar: Boar = forced_boar(world, field, nest)
	var result: Dictionary = run_forced(world, field, boar, Vector2(60, 100), Vector2(150, 100), 12.0, tuning)
	check(result["bad"] == "" and boar.pos.x <= 20.0 * TILE - tuning.boar_half_width_px + 0.01, "a boar aiming across water stops at the bank and never overlaps water (x=%.2f, bank edge %.2f) %s" % [boar.pos.x, 20.0 * TILE - tuning.boar_half_width_px, result["bad"]])
	# 2. Building block: a wall on x = 30..33, rows 0..39.
	var rows2: Array = open_rows(100, 60)
	for y: int in 40:
		rows2[y] = ".".repeat(30) + "####" + ".".repeat(66)
	var world2: WorldState = small_world(rows2, 100)
	var field2: EnemyField = EnemyField.new(world2, tuning, TILE)
	var nest2: Nest = field2.add_nest(0, Vector2i(8, 18))
	var boar2: Boar = forced_boar(world2, field2, nest2)
	var result2: Dictionary = run_forced(world2, field2, boar2, Vector2(80, 100), Vector2(200, 100), 12.0, tuning)
	check(result2["bad"] == "" and boar2.pos.x <= 30.0 * TILE - tuning.boar_half_width_px + 0.01, "a boar aiming through a building stops at its wall (x=%.2f) %s" % [boar2.pos.x, result2["bad"]])
	# 3. Zone border into a stable zone at x = 60.
	var world3: WorldState = small_world(open_rows(120, 60), 60)
	var field3: EnemyField = EnemyField.new(world3, tuning, TILE)
	var nest3: Nest = field3.add_nest(0, Vector2i(40, 28))
	var boar3: Boar = forced_boar(world3, field3, nest3)
	var result3: Dictionary = run_forced(world3, field3, boar3, Vector2(50 * TILE, 120), Vector2(80 * TILE, 120), 12.0, tuning)
	check(result3["bad"] == "" and boar3.pos.x <= 60.0 * TILE - tuning.boar_half_width_px + 0.01 and boar3.pos.x > 55.0 * TILE, "a boar aiming into a stable zone stops at the zone border (x=%.2f, border %d) %s" % [boar3.pos.x, 60 * TILE, result3["bad"]])
	# 4. Tether: the border is far away (x = 120), the nest at x = 4; the goal lies 80 tiles east.
	var world4: WorldState = small_world(open_rows(140, 30), 120)
	var field4: EnemyField = EnemyField.new(world4, tuning, TILE)
	var nest4: Nest = field4.add_nest(0, Vector2i(2, 12))
	var boar4: Boar = forced_boar(world4, field4, nest4)
	var result4: Dictionary = run_forced(world4, field4, boar4, Vector2(40, 60), Vector2(100 * TILE, 60), 20.0, tuning)
	var limit_x: float = nest4.center_px(TILE).x + float(tuning.tether_tiles * TILE)
	check(result4["bad"] == "" and boar4.pos.x > limit_x - 10.0 and boar4.pos.x <= limit_x + 0.01, "a boar aiming far away stops at the tether (x=%.2f, tether end %.2f) %s" % [boar4.pos.x, limit_x, result4["bad"]])
	# 5. The boar's own zone being the target, a plant in the stable zone is not chosen even when it is the nearest one.
	var world5: WorldState = small_world(open_rows(120, 60), 60)
	var field5: EnemyField = EnemyField.new(world5, tuning, TILE)
	var nest5: Nest = field5.add_nest(0, Vector2i(40, 28))
	fill_plants(world5, Rect2i(62, 20, 20, 20))
	fill_plants(world5, Rect2i(30, 8, 4, 4))
	var stable_before: PackedByteArray = world5.stage.duplicate()
	var dt: float = 1.0 / 60.0
	for i: int in 60 * 60:
		field5.advance(dt)
	var changed_in_stable: int = 0
	for index: int in world5.tile_count():
		if world5.zone_of[index] == 1 and world5.stage[index] != stable_before[index]:
			changed_in_stable += 1
	var far_plants_gone: bool = true
	for y: int in range(8, 12):
		for x: int in range(30, 34):
			far_plants_gone = far_plants_gone and world5.stage[world5.index_of(x, y)] == WorldState.STAGE_EMPTY
	check(changed_in_stable == 0 and field5.total_gnawed > 0 and far_plants_gone, "boars eat the plants of their own zone (%d tiles gnawed, the far patch is gone) and leave the nearer stable zone's untouched (changes: %d)" % [field5.total_gnawed, changed_in_stable])
	var every_ok: bool = true
	for boar5: Boar in field5.boars:
		every_ok = every_ok and violation(world5, boar5, tuning) == ""
	check(every_ok, "all boars of that run stand in their zone, inside the tether, on dry ground")

func test_gnaw_and_counters() -> void:
	var tuning: EnemyTuning = tune()
	var world: WorldState = small_world(open_rows(100, 50), 100)
	var field: EnemyField = EnemyField.new(world, tuning, TILE)
	var nest: Nest = field.add_nest(0, Vector2i(10, 20))
	var planted: int = fill_plants(world, Rect2i(18, 14, 26, 18))
	var greened_before: int = world.greened_count
	check(planted == 26 * 18 and greened_before == planted, "the test field has %d mature tiles, all greened" % planted)
	var dt: float = 1.0 / 60.0
	var min_greened: int = greened_before
	for i: int in 60 * 150:
		field.advance(dt)
		min_greened = mini(min_greened, world.greened_count)
	check(field.total_gnawed > 0 and world.greened_count == greened_before - field.total_gnawed, "boars bite plants: %d tiles gnawed in 150 s, and the greening count fell by exactly that (%d -> %d)" % [field.total_gnawed, greened_before, world.greened_count])
	check(world.counters_consistent() and world.zone_greened_count[0] == world.greened_count, "greening, per-zone and per-chunk counters equal a full recount after the gnawing")
	var left: int = world.recount_plants()
	check(left == world.plant_count and left < planted, "plants left: %d of %d (plant counter agrees)" % [left, planted])
	# A gnawed tile only becomes empty: it keeps its terrain and is plantable again, and nothing else changed.
	var empty_plantable: bool = true
	for y: int in range(14, 32):
		for x: int in range(18, 44):
			var index: int = world.index_of(x, y)
			if world.stage[index] == WorldState.STAGE_EMPTY:
				empty_plantable = empty_plantable and world.can_plant(index) and world.plant_id[index] == WorldState.PLANT_NONE
	check(empty_plantable, "gnawed tiles are empty, plantable ground again")
	# Seeds and sprouts are eaten too (any stage from seed to mature).
	var world2: WorldState = small_world(open_rows(60, 40), 60)
	var field2: EnemyField = EnemyField.new(world2, tuning, TILE)
	field2.add_nest(0, Vector2i(10, 16))
	fill_plants(world2, Rect2i(20, 14, 8, 4), WorldState.STAGE_SEED)
	fill_plants(world2, Rect2i(20, 18, 8, 4), WorldState.STAGE_SPROUT2)
	for i: int in 60 * 100:
		field2.advance(dt)
	var remaining_young: int = 0
	for y: int in range(14, 22):
		for x: int in range(20, 28):
			remaining_young += 1 if world2.stage[world2.index_of(x, y)] != WorldState.STAGE_EMPTY else 0
	check(field2.total_gnawed > 0 and remaining_young < 64, "seeds and sprouts are eaten as well (%d of 64 left)" % remaining_young)
	# Gnawed tiles return to the spread candidate queue (P1-04), with the nest tiles excluded by the hook.
	var world3: WorldState = small_world(open_rows(100, 50), 100)
	var field3: EnemyField = EnemyField.new(world3, tuning, TILE)
	field3.add_nest(0, Vector2i(10, 20))
	fill_plants(world3, Rect2i(18, 14, 26, 18))
	var spread: SpreadSim = SpreadSim.new(world3, sim_tuning)
	spread.allow_hook = field3.spread_allows
	var before: PackedByteArray = world3.stage.duplicate()
	for i: int in 60 * 40:
		field3.advance(dt)
	var cleared: PackedInt32Array = PackedInt32Array()
	for index: int in world3.tile_count():
		if before[index] != WorldState.STAGE_EMPTY and world3.stage[index] == WorldState.STAGE_EMPTY:
			cleared.append(index)
	spread._apply_events(1000000)
	var queued: int = 0
	var not_queued_ok: bool = true
	for index: int in cleared:
		if spread.queued_flag[index] == 1:
			queued += 1
		elif spread.mature_near[index] > 0 and world3.can_plant(index):
			not_queued_ok = false
	check(cleared.size() > 0 and queued > 0 and not_queued_ok, "the %d tiles the boars cleared went back to the spread queue (%d queued, the rest have no mature tile near)" % [cleared.size(), queued])
	# Cultivated plants are not bitten: their tiles are occupied.
	var world4: WorldState = small_world(open_rows(80, 40), 80)
	var field4: EnemyField = EnemyField.new(world4, tuning, TILE)
	field4.add_nest(0, Vector2i(10, 16))
	fill_plants(world4, Rect2i(20, 14, 12, 12))
	var cultivation: Cultivation = Cultivation.new(world4, play_tuning, TILE, _plant_defs())
	var carrot: CultivatedPlant = cultivation.try_place(&"carrot", Vector2(24.5, 18.5) * TILE)
	for i: int in 60 * 120:
		field4.advance(dt)
	var carrot_ok: bool = carrot != null
	if carrot != null:
		for y: int in range(carrot.tile.y, carrot.tile.y + carrot.size):
			for x: int in range(carrot.tile.x, carrot.tile.x + carrot.size):
				carrot_ok = carrot_ok and world4.stage[world4.index_of(x, y)] == WorldState.STAGE_MATURE
	check(carrot_ok and world4.counters_consistent() and field4.total_gnawed > 0, "a cultivated plant's tiles stay mature while the plants around it are eaten")

func test_stable_zone() -> void:
	var tuning: EnemyTuning = tune()
	var world: WorldState = small_world(open_rows(100, 50), 100)
	var field: EnemyField = EnemyField.new(world, tuning, TILE)
	field.add_nest(0, Vector2i(10, 20))
	fill_plants(world, Rect2i(18, 14, 26, 18))
	var dt: float = 1.0 / 60.0
	for i: int in 60 * 40:
		field.advance(dt)
	check(field.boars.size() >= 3 and field.total_gnawed > 0, "before: %d boars are eating (%d tiles)" % [field.boars.size(), field.total_gnawed])
	# P2-04: the boars of a zone that turns stable are removed at once (no standing still), so nothing bites and nothing spawns.
	var gnawed: int = field.total_gnawed
	var plants: PackedByteArray = world.stage.duplicate()
	var count: int = field.boars.size()
	var gone: bool = false
	world.set_zone_state(0, WorldState.ZONE_STABLE)
	gone = field.boars.is_empty()
	for i: int in 60 * 60:
		field.advance(dt)
	check(count >= 3 and gone and field.boars.is_empty() and field.total_gnawed == gnawed and world.stage == plants, "when its zone turns stable the %d boars are gone at once, nothing is bitten and nothing new spawns" % count)
	# Complete behaves the same.
	world.set_zone_state(0, WorldState.ZONE_COMPLETE)
	for i: int in 60 * 20:
		field.advance(dt)
	check(field.total_gnawed == gnawed and field.boars.is_empty() and field.total_spawned >= count, "a complete zone is closed to enemies as well (no boar, nothing bitten)")
	# A clearing zone (all nests destroyed, boars left) is still open: remaining boars keep working until killed.
	var world2: WorldState = small_world(open_rows(100, 50), 100)
	var field2: EnemyField = EnemyField.new(world2, tuning, TILE)
	var nest2: Nest = field2.add_nest(0, Vector2i(10, 20))
	fill_plants(world2, Rect2i(18, 14, 26, 18))
	for i: int in 60 * 30:
		field2.advance(dt)
	field2.destroy_nest(nest2)
	world2.set_zone_state(0, WorldState.ZONE_CLEARING)
	var count2: int = field2.boars.size()
	var gnawed2: int = field2.total_gnawed
	for i: int in 60 * 60:
		field2.advance(dt)
	check(field2.boars.size() == count2 and field2.total_gnawed > gnawed2, "in a clearing zone no boar is added, and the remaining boars still gnaw (%d -> %d tiles)" % [gnawed2, field2.total_gnawed])

func test_hit_shapes() -> void:
	var world: WorldState = small_world(open_rows(100, 50), 100)
	var field: EnemyField = EnemyField.new(world, tune(), TILE)
	var nest: Nest = field.add_nest(0, Vector2i(10, 20))
	var dt: float = 1.0 / 60.0
	for i: int in 60 * 13:
		field.advance(dt)
	var boar: Boar = field.boars[0]
	var body: Vector2 = field.boar_body_center(boar)
	var radius: float = field.tuning.hit_radius_px
	var hit: Dictionary = field.hit_test(body + Vector2(-40, 0), body + Vector2(40, 0))
	check(hit.get("kind", "") == "boar" and hit["boar"] == boar and absf((hit["point"] as Vector2).x - (body.x - radius)) < 0.01, "a segment through a boar hits its body circle at the near edge")
	var miss: Dictionary = field.hit_test(body + Vector2(-40, radius + 3.0), body + Vector2(40, radius + 3.0))
	check(miss.is_empty() or miss.get("kind", "") != "boar", "a segment passing just outside the circle misses the boar")
	var rect_px: Rect2 = Rect2(Vector2(nest.tile) * TILE, Vector2(16, 16))
	var from: Vector2 = Vector2(rect_px.position.x - 30.0, rect_px.position.y + 8.0)
	var nest_hit: Dictionary = field.hit_test(from, from + Vector2(60, 0))
	check(nest_hit.get("kind", "") == "nest" and absf((nest_hit["point"] as Vector2).x - rect_px.position.x) < 0.01, "a segment into the nest block hits the block's edge")
	field.destroy_nest(nest)
	var after: Dictionary = field.hit_test(from, from + Vector2(60, 0))
	check(after.is_empty() or after.get("kind", "") != "nest", "a destroyed nest cannot be hit")
	var provider: Callable = field.hit_test
	check(provider.is_valid(), "hit_test has the shape of ProjectileField.enemy_hit_provider (from, to) -> {point, ...} (the connection is P2-02)")

## Boars of the zone north of the start zone with plants only along the border (both sides): they come to the border and
## chew the strip on their side, and never a single plant of the stable start zone on the other side.
func test_border_safety() -> void:
	var rig: Array = real_field()
	var world: WorldState = rig[0]
	var field: EnemyField = rig[1]
	var strip: Rect2i = Rect2i(130, 112, 110, 13)
	var bait: Rect2i = Rect2i(130, 125, 110, 25)
	fill_plants(world, strip)
	fill_plants(world, bait)
	var before: PackedByteArray = PackedByteArray()
	var tiles: PackedInt32Array = PackedInt32Array()
	for index: int in world.tile_count():
		if world.zone_of[index] == 0:
			tiles.append(index)
			before.append(world.stage[index])
	var dt: float = 1.0 / 30.0
	var at_border: int = 0
	var bad: int = 0
	var gnawed_strip: int = 0
	var strip_filled: int = world.recount_plants()
	for i: int in range(1, 30 * 300 + 1):
		field.advance(dt)
		if i % 150 == 0:
			fill_plants(world, strip)
		for boar: Boar in field.boars:
			if boar.zone == 1 and boar.pos.y > 125.0 * TILE - 12.0 and boar.pos.x > 130.0 * TILE and boar.pos.x < 240.0 * TILE:
				at_border += 1
			if violation(world, boar, field.tuning) != "":
				bad += 1
	var after: PackedByteArray = PackedByteArray()
	for index: int in tiles:
		after.append(world.stage[index])
	check(at_border > 100, "the border test is meaningful: boars stood within 12 px of the start zone's border (%d boar-frames)" % at_border)
	check(after == before and bad == 0, "5 minutes with bait on both sides of the border: not one plant of the stable zone was bitten, no rule broken")
	check(field.total_gnawed > 100 and world.counters_consistent(), "the strip on the boars' side was eaten (%d tiles) and the counters match a recount" % field.total_gnawed)

# ---- save and frame rates --------------------------------------------------------------------------------------------

func feed_plants(world: WorldState, field: EnemyField) -> void:
	for nest: Nest in field.nests:
		fill_plants(world, Rect2i(nest.tile.x - 14, nest.tile.y - 14, 32, 32))

func run_scenario(hz: int, seconds: float, setup_feed: bool) -> Array:
	var rig: Array = real_field()
	var world: WorldState = rig[0]
	var field: EnemyField = rig[1]
	feed_plants(world, field)
	var frames: int = roundi(seconds * float(hz))
	var dt: float = 1.0 / float(hz)
	for i: int in range(1, frames + 1):
		field.advance(dt)
		if setup_feed and i % (hz * 5) == 0:
			feed_plants(world, field)
	return rig

func state_text(field: EnemyField) -> String:
	var data: Dictionary = field.to_dict()
	data.erase("time")
	return JSON.stringify(data)

func test_frame_rates() -> void:
	var results: Dictionary = {}
	for hz: int in [30, 60, 144]:
		results[hz] = run_scenario(hz, 60.0, true)
	var base: EnemyField = results[60][1]
	var base_world: WorldState = results[60][0]
	check(base.boars.size() >= 15 and base.total_gnawed > 0, "frame-rate scenario: %d boars and %d tiles gnawed in 60 s" % [base.boars.size(), base.total_gnawed])
	var same_30: bool = state_text(results[30][1]) == state_text(base) and results[30][0].stage == base_world.stage
	var same_144: bool = state_text(results[144][1]) == state_text(base) and results[144][0].stage == base_world.stage
	check(same_30 and same_144, "30 / 60 / 144 Hz give the same boars, nests, positions and plants after 60 s (steps %d / %d / %d)" % [results[30][1].steps_done, base.steps_done, results[144][1].steps_done])
	check(base.steps_done == 3600 and results[30][1].steps_done == 3600 and results[144][1].steps_done == 3600, "all three ran exactly 3600 fixed steps")
	# Splitting differently within a frame (a 0.25 s hitch frame) equals many small frames.
	var rig: Array = real_field()
	feed_plants(rig[0], rig[1])
	for i: int in 240:
		rig[1].advance(0.25)
		if i % 20 == 19:
			feed_plants(rig[0], rig[1])
	var rig2: Array = real_field()
	feed_plants(rig2[0], rig2[1])
	for i: int in 240 * 15:
		rig2[1].advance(1.0 / 60.0)
		if i % 300 == 299:
			feed_plants(rig2[0], rig2[1])
	check(state_text(rig[1]) == state_text(rig2[1]) and rig[0].stage == rig2[0].stage, "60 s as 240 frames of 0.25 s equals 3600 frames of 1/60 s")
	# Pause: nothing moves without advance(); a zero or negative delta is ignored and no time is banked.
	var steps: int = base.steps_done
	var dict_before: String = state_text(base)
	base.advance(0.0)
	base.advance(-5.0)
	check(base.steps_done == steps and state_text(base) == dict_before, "advance(0) and advance(<0) change nothing")

func test_field_save() -> void:
	var rig: Array = run_scenario(60, 45.0, true)
	var world: WorldState = rig[0]
	var field: EnemyField = rig[1]
	var saved_world: Dictionary = world.to_dict()
	var saved_field: Dictionary = field.to_dict()
	var world2: WorldState = WorldState.from_dict(saved_world, world.terrain_defs)
	var field2: EnemyField = EnemyField.new(world2, tune(), TILE)
	check(world2 != null and field2.load_dict(saved_field), "the saved nests and boars load onto the restored world")
	check(JSON.stringify(field2.to_dict()) == JSON.stringify(saved_field) and field2.nests.size() == 15 and field2.boars.size() == field.boars.size(), "nests (hit points, timers), boars (positions, goals, timers, random state) and counters survive the round trip (%d boars)" % field.boars.size())
	var nests_released: bool = true
	for nest: Nest in field2.nests:
		nests_released = nests_released and world2.occupancy_owners.has(nest.owner_id())
	check(nests_released, "the restored nests occupy their blocks again")
	# Continue both for 30 s with the same feeding: identical.
	var dt: float = 1.0 / 60.0
	for i: int in range(1, 60 * 30 + 1):
		field.advance(dt)
		field2.advance(dt)
		if i % 300 == 0:
			feed_plants(world, field)
			feed_plants(world2, field2)
	check(state_text(field) == state_text(field2) and world.stage == world2.stage, "after loading, the next 30 s run exactly like the original")
	# JSON text round trip.
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved_field))
	var world3: WorldState = WorldState.from_dict(saved_world, world.terrain_defs)
	var field3: EnemyField = EnemyField.new(world3, tune(), TILE)
	var loaded_json: bool = parsed is Dictionary and field3.load_dict(parsed)
	check(loaded_json and field3.boars.size() == field2.boars.size() - field2.boars.size() + saved_field["boars"].size(), "the enemy data loads from JSON text too")
	var exact: bool = loaded_json and JSON.stringify(field3.to_dict()) == JSON.stringify(saved_field)
	info["json_round_trip_exact"] = exact
	# Mismatching data is refused and leaves the field unchanged (a fresh field on a world that holds the saved occupancy).
	var world4: WorldState = WorldState.from_dict(saved_world, world.terrain_defs)
	var field4: EnemyField = EnemyField.new(world4, tune(), TILE)
	var before: String = JSON.stringify(field4.to_dict())
	var bad: Dictionary = saved_field.duplicate(true)
	bad["nests"][0]["x"] = 5
	check(not field4.load_dict(bad) and JSON.stringify(field4.to_dict()) == before and world4.occupancy_owners.size() == world.occupancy_owners.size(), "a nest saved at a place that does not match the world is refused; the state stays as it was")
	var bad_boar: Dictionary = saved_field.duplicate(true)
	bad_boar["boars"][0]["hp"] = 0
	check(not field4.load_dict(bad_boar) and JSON.stringify(field4.to_dict()) == before, "a dead boar in the data is refused")
	var bad_zone: Dictionary = saved_field.duplicate(true)
	bad_zone["boars"][0]["zone"] = 99
	check(not field4.load_dict(bad_zone), "a boar of an unknown zone is refused")
	check(field4.load_dict(saved_field) and JSON.stringify(field4.to_dict()) == JSON.stringify(saved_field), "after the refusals the valid data still loads")

# ---- scene -------------------------------------------------------------------------------------------------------------

func test_scene_pause() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var enemies: EnemyField = main.enemies
	check(enemies != null and enemies.nests.size() == 15 and main.simulation.spread.allow_hook.is_valid(), "the scene creates 15 nests and connects the spread hook")
	check(main.enemy_view != null and main.enemy_view.nest_sprites.size() == 15, "the scene shows 15 nest sprites")
	for i: int in 30:
		await physics_frame
	var steps: int = enemies.steps_done
	check(steps > 0, "the enemy simulation runs in the scene (%d steps)" % steps)
	paused = true
	for i: int in 40:
		await physics_frame
	var frozen: int = enemies.steps_done
	check(frozen == steps, "while paused the enemy steps stand still (%d == %d)" % [frozen, steps])
	# Jump to the first spawn while paused: nothing happens, and resuming does not bank the pause.
	paused = false
	for i: int in 30:
		await physics_frame
	check(enemies.steps_done > frozen and enemies.steps_done - frozen <= 40, "after resuming it continues without banked time (%d new steps)" % (enemies.steps_done - frozen))
	# Pause around a spawn: freeze at 11 s, wait, resume.
	enemies.time = 11.5
	enemies.steps_done = 690
	for nest: Nest in enemies.nests:
		nest.spawn_steps = 690
	for i: int in 3:
		await physics_frame
	var boars_before: int = enemies.boars.size()
	paused = true
	for i: int in 120:
		await physics_frame
	check(enemies.boars.size() == boars_before, "no boar appears while paused, even past the spawn time")
	paused = false
	for i: int in 60:
		await physics_frame
	check(enemies.boars.size() > boars_before, "the boars appear once the game runs again (%d -> %d)" % [boars_before, enemies.boars.size()])
	var views_ok: bool = main.enemy_view.boar_sprites.size() == enemies.boars.size()
	check(views_ok, "one boar sprite per boar (%d)" % main.enemy_view.boar_sprites.size())
	main.queue_free()
	await process_frame

# ---- long idle run ---------------------------------------------------------------------------------------------------

func test_long_run() -> void:
	var rig: Array = real_field()
	var world: WorldState = rig[0]
	var field: EnemyField = rig[1]
	var tuning: EnemyTuning = field.tuning
	feed_plants(world, field)
	# Bait in the stable start zone just below its north border (row 125), planted once and never refilled, so a bite would show.
	fill_plants(world, Rect2i(130, 125, 110, 25))
	var zone0_before: PackedByteArray = PackedByteArray()
	var zone0_tiles: PackedInt32Array = PackedInt32Array()
	for index: int in world.tile_count():
		if world.zone_of[index] == 0:
			zone0_tiles.append(index)
			zone0_before.append(world.stage[index])
	# Start zone plants: also a patch of plants right at its north border (zone 0 next to the zone-1 nest area).
	var dt: float = 1.0 / 30.0
	var frames: int = 30 * 60 * 30
	var max_boars: int = 0
	var max_per_nest: int = 0
	var violations: int = 0
	var first_violation: String = ""
	var in_zone0: int = 0
	var stable_zone: int = 5
	var frozen_positions: Dictionary = {}
	var frozen_moved: int = 0
	var started: int = Time.get_ticks_msec()
	var frame_checks: int = 0
	for i: int in range(1, frames + 1):
		field.advance(dt)
		if i % 150 == 0:
			feed_plants(world, field)
		if i == frames / 2:
			for boar: Boar in field.boars:
				if boar.zone == stable_zone:
					frozen_positions[boar.id] = boar.pos
			world.set_zone_state(stable_zone, WorldState.ZONE_STABLE)
		max_boars = maxi(max_boars, field.boars.size())
		for nest: Nest in field.nests:
			max_per_nest = maxi(max_per_nest, nest.boar_count)
		for boar: Boar in field.boars:
			frame_checks += 1
			var why: String = violation(world, boar, tuning)
			if why != "":
				violations += 1
				if first_violation == "":
					first_violation = "frame %d boar %d: %s" % [i, boar.id, why]
			if boar.zone == 0:
				in_zone0 += 1
			if frozen_positions.has(boar.id) or (i > frames / 2 and boar.zone == stable_zone):
				frozen_moved += 1
	var cpu_seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	check(max_boars == 40, "30 minutes idle: the region-wide limit holds and is reached (max %d boars, limit 40)" % max_boars)
	check(max_per_nest <= 4 and field.boars.size() <= 40, "no nest ever had more than 4 boars (max %d); %d boars at the end" % [max_per_nest, field.boars.size()])
	check(violations == 0, "all %d boar positions of every frame were in their own zone, inside the 48-tile tether and on dry ground %s" % [frame_checks, first_violation])
	check(in_zone0 == 0, "no boar was ever in the stable start zone")
	var zone0_after: PackedByteArray = PackedByteArray()
	for index: int in zone0_tiles:
		zone0_after.append(world.stage[index])
	check(zone0_after == zone0_before, "the plants of the stable start zone were never touched (%d tiles)" % zone0_tiles.size())
	check(frozen_positions.size() > 0 and frozen_moved == 0, "%d boars of the zone that turned stable at 15 min vanished at once and none of them (or any other boar of that zone) was seen again (frames seen: %d)" % [frozen_positions.size(), frozen_moved])
	check(world.counters_consistent() and field.total_gnawed > 1000, "after 30 minutes the counters equal a full recount; %d tiles were gnawed in total" % field.total_gnawed)
	var spawn_per_zone: Dictionary = {}
	for nest: Nest in field.nests:
		spawn_per_zone[nest.zone] = int(spawn_per_zone.get(nest.zone, 0)) + nest.spawned
	info["long_run"] = {"game_minutes": 30, "frames": frames, "max_boars": max_boars, "max_per_nest": max_per_nest, "boar_frames_checked": frame_checks, "violations": violations, "tiles_gnawed": field.total_gnawed, "spawned_total": field.total_spawned, "spawned_per_zone": spawn_per_zone, "cpu_seconds": cpu_seconds}
