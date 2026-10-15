extends SceneTree
## P1-05 headless checks: plant selection, 2x2 carrot / kiwi placement, carrot spread boost, kiwi healing fruits, HP,
## pause, frame-rate independence, save round trip, the real main.tscn with injected input, SpreadSim empty-array save.
## Run: Godot --headless --path <project> --script res://tests/p1/p1_05_checks.gd
## Expected values come from the ticket / parent design (3 seeds per carrot / kiwi, 40 s to mature, radius 12 tiles,
## multiplier 2.0, a kiwi fruit every 20 s, 2 fruits per kiwi, +2 HP, HP 10, 32 plants per kind) and from brute-force
## recounts written in this file:
##   a spread candidate with n mature tiles within 2 tiles needs ceil(100000 / (floor((10000 + 2500 (n - 1)) * m))) ticks,
##   m = 1 normally and m = 2 inside the radius of a mature carrot.

const REGION_PATH: String = "res://data/region_01.tres"
const TILE: int = 4
const FAR: Vector2 = Vector2(100000, 100000)

var failures: int = 0
var checks: int = 0
var region_def: RegionDef
var sim_tuning: SimTuning
## The tuning as shipped in data/ (not pinned).
var shipped_tuning: SimTuning
var play_tuning: PlayTuning
var defs: Array[PlantDef] = []
var info: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", message])

func run() -> void:
	region_def = load(REGION_PATH) as RegionDef
	# P1-06 retuned the shipped natural-spread speed (data/sim_tuning.gd). These checks verify mechanisms against the
	# P1-04 reference values (their oracles and run lengths are written for them), so the values are pinned here.
	shipped_tuning = load("res://data/sim_tuning.tres") as SimTuning
	sim_tuning = shipped_tuning.duplicate() as SimTuning
	pin_reference_spread(sim_tuning)
	play_tuning = load("res://data/play_tuning.tres") as PlayTuning
	check(region_def != null and sim_tuning != null and play_tuning != null, "region and tunings load")
	defs.assign(region_def.plants)
	test_data()
	test_selection()
	test_hp()
	test_empty_pack()
	test_placement()
	test_cost_and_limits()
	test_occupied_not_planted()
	test_carrot()
	test_kiwi()
	test_budget()
	test_frame_rate()
	test_save()
	await test_scene()
	print("INFO " + JSON.stringify(info))
	print("P1_05_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

## The P1-04 reference natural-spread values the oracles of this file are written for.
func pin_reference_spread(tuning: SimTuning) -> void:
	tuning.spread_progress_per_tick = 10000
	tuning.spread_progress_per_extra_neighbor = 2500
	tuning.natural_growth_multiplier = 3.0

# ---- helpers ---------------------------------------------------------------------------------------------------

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

func blank(width: int, height: int) -> WorldState:
	var rows: Array = []
	for y: int in height:
		rows.append(".".repeat(width))
	return state_from_rows(rows)

func make_play(state: WorldState, plant_defs: Array[PlantDef] = defs, sources: Array[Vector2] = []) -> PlayState:
	return PlayState.new(state, play_tuning, sim_tuning, TILE, sources, plant_defs)

func tile_point(x: int, y: int, px: float, py: float) -> Vector2:
	return Vector2(x * TILE + px, y * TILE + py)

func run_play(play: PlayState, seconds: float, hz: int, player: Vector2 = FAR) -> void:
	for i: int in roundi(seconds * hz):
		play.advance(1.0 / hz, player)

func owners_all(state: WorldState, rect: Rect2i, owner_id: int) -> bool:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if state.occupant[state.index_of(x, y)] != owner_id:
				return false
	return true

func first_heal(play: PlayState) -> Dictionary:
	for item: Dictionary in play.pickups.items:
		if String(item["kind"]) == GroundPickups.KIND_HEAL_FRUIT:
			return item
	return {}

# ---- data --------------------------------------------------------------------------------------------------------

func test_data() -> void:
	var keys: Array[StringName] = []
	for def: PlantDef in defs:
		keys.append(def.key)
	check(keys == [&"normal", &"carrot", &"kiwi"], "region plant list in selection order: normal, carrot, kiwi (%s)" % [keys])
	var carrot: PlantDef = defs[1]
	var kiwi: PlantDef = defs[2]
	check(carrot.footprint_tiles == 2 and kiwi.footprint_tiles == 2 and defs[0].footprint_tiles == 1, "footprints: normal 1, carrot 2, kiwi 2 tiles")
	check(carrot.seed_cost == 3 and kiwi.seed_cost == 3 and carrot.max_count == 32 and kiwi.max_count == 32, "cost 3 seeds, limit 32 per kind")
	check(carrot.grow_seconds == 40.0 and kiwi.grow_seconds == 40.0, "40 s from young to mature")
	check(carrot.effect == PlantDef.EFFECT_SPREAD_BOOST and carrot.effect_radius_tiles == 12.0 and carrot.effect_multiplier == 2.0, "carrot: spread boost, radius 12 tiles, x2.0")
	check(kiwi.effect == PlantDef.EFFECT_HEAL_FRUIT and kiwi.fruit_interval_seconds == 20.0 and kiwi.fruit_cap == 2 and kiwi.fruit_heal == 2 and kiwi.fruit_lifetime_seconds == 30.0, "kiwi: a fruit every 20 s, 2 per plant, +2 HP, fruit lifetime 30 s")
	check(play_tuning.hp_max == 10 and play_tuning.hp_start == 10 and play_tuning.heal_fruit_total_cap == 16, "HP 10, healing fruits capped at 16 in the region")
	check(sim_tuning.spread_progress_threshold == 100000 and sim_tuning.spread_progress_per_tick == 10000 and sim_tuning.spread_progress_per_extra_neighbor == 2500 and sim_tuning.spread_radius_tiles == 2.0, "spread constants used by the oracle below: threshold 100000, +10000 / tick, +2500 per extra neighbour, radius 2")

# ---- selection ---------------------------------------------------------------------------------------------------

func test_selection() -> void:
	var play: PlayState = make_play(blank(10, 10))
	check(play.selected_index == 0 and play.selected_def().key == &"normal", "selection starts at the ordinary plant")
	var seen: Array[StringName] = []
	var signals: Array[int] = []
	play.selection_changed.connect(func(index: int) -> void: signals.append(index))
	for i: int in 4:
		play.cycle_selection(1)
		seen.append(play.selected_def().key)
	check(seen == [&"carrot", &"kiwi", &"normal", &"carrot"], "next x4 cycles carrot, kiwi, normal, carrot (%s)" % [seen])
	check(play.cycle_selection(-1) == 0 and play.cycle_selection(-1) == 2, "previous goes back and wraps from the first to the last")
	check(signals.size() == 6, "every change reports selection_changed (%d)" % signals.size())
	play.select_index(1)
	check(PlayHud.selection_text(play) == "植物 通常 [にんじん:3] キウイ", "HUD text marks the current plant with its cost: %s" % PlayHud.selection_text(play))
	play.select_index(2)
	check(PlayHud.selection_text(play) == "植物 通常 にんじん [キウイ:3]", "HUD text follows the selection: %s" % PlayHud.selection_text(play))
	var lonely: PlayState = make_play(blank(10, 10), [] as Array[PlantDef])
	check(lonely.selectable.size() == 1 and lonely.selected_def().key == &"normal", "without plant data there is still the ordinary plant")
	# A plant added only by data: a third cultivated def appears in the selection and in the HUD without code.
	var extra: PlantDef = defs[1].duplicate() as PlantDef
	extra.key = &"beet"
	extra.display_name = "ビート"
	var more: Array[PlantDef] = defs.duplicate()
	more.append(extra)
	var wide: PlayState = make_play(blank(10, 10), more)
	check(wide.selectable.size() == 4 and PlayHud.selection_text(wide).ends_with("ビート"), "a plant added as data shows up in the selection (%s)" % PlayHud.selection_text(wide))

# ---- HP --------------------------------------------------------------------------------------------------------------

func test_hp() -> void:
	var play: PlayState = make_play(blank(10, 10))
	var seen: Array[int] = []
	play.hp_changed.connect(func(value: int) -> void: seen.append(value))
	check(play.hp == 10 and play.hp_max == 10, "HP starts full at 10")
	check(play.damage_player(3) == 3 and play.hp == 7, "damage_player(3): HP 7")
	check(play.damage_player(-5) == 0 and play.hp == 7, "negative damage does nothing")
	check(play.heal_player(2) == 2 and play.hp == 9 and play.heal_player(5) == 1 and play.hp == 10, "healing never goes above the maximum (9 + 5 -> 10, 1 gained)")
	check(play.heal_player(2) == 0 and play.hp == 10, "healing at full HP gains nothing")
	check(play.damage_player(99) == 10 and play.hp == 0 and play.damage_player(1) == 0, "damage never goes below 0")
	check(seen == [7, 9, 10, 0], "hp_changed is reported for real changes only (%s)" % [seen])

func test_empty_pack() -> void:
	var packed: Dictionary = WorldState._pack_bytes(PackedByteArray())
	check(WorldState._unpack_bytes(packed).is_empty(), "an empty array packs and unpacks without engine errors")
	var state: WorldState = blank(12, 12)
	var spread: SpreadSim = SpreadSim.new(state, sim_tuning)
	var data: Dictionary = JSON.parse_string(JSON.stringify(spread.to_dict()))
	check(spread.queue_size() == 0 and WorldState._unpack_bytes(data["queue"]).is_empty(), "SpreadSim.to_dict with an empty queue works")
	var twin: SpreadSim = SpreadSim.new(blank(12, 12), sim_tuning, false)
	check(twin.load_dict(data) and twin.queue_size() == 0 and twin.ticks == spread.ticks, "SpreadSim.load_dict restores the empty save")
	var growth: GrowthSim = GrowthSim.new(state, sim_tuning)
	var growth_data: Dictionary = JSON.parse_string(JSON.stringify(growth.to_dict()))
	check(growth.load_dict(growth_data), "GrowthSim.to_dict / load_dict with an empty active set works")

# ---- placement -------------------------------------------------------------------------------------------------

func test_placement() -> void:
	var state: WorldState = blank(30, 30)
	state.debug_fill_stage(Rect2i(5, 5, 6, 6), WorldState.STAGE_MATURE)
	var play: PlayState = make_play(state)
	var greened_before: int = state.greened_count
	var mature_before: int = state.mature_count
	# Four blocks contain the landing tile; the one whose centre is nearest to the point is tried first.
	var first: CultivatedPlant = play.cultivation.try_place(&"carrot", tile_point(7, 7, 3.5, 3.5))
	check(first != null and first.tile == Vector2i(7, 7) and first.size == 2, "landing in the lower right of tile (7,7): the block (7,7)-(8,8) is chosen")
	check(owners_all(state, Rect2i(7, 7, 2, 2), 1000 + first.uid) and state.occupant[state.index_of(9, 7)] == 0 and state.occupant[state.index_of(6, 7)] == 0, "exactly the 2x2 footprint is occupied by the plant")
	check(state.greened_count == greened_before and state.mature_count == mature_before and state.counters_consistent(), "the footprint was green ground already: greened count %d unchanged, counters match a recount" % state.greened_count)
	var all_mature: bool = true
	for index: int in [state.index_of(7, 7), state.index_of(8, 7), state.index_of(7, 8), state.index_of(8, 8)]:
		all_mature = all_mature and state.stage[index] == WorldState.STAGE_MATURE
	check(all_mature, "the occupied tiles stay mature ground")
	# Landing on an occupied tile can never place anything (all four blocks contain it).
	var count: int = play.cultivation.plants.size()
	for quarter: Vector2 in [Vector2(0.5, 0.5), Vector2(3.5, 0.5), Vector2(0.5, 3.5), Vector2(3.5, 3.5)]:
		check(play.cultivation.try_place(&"kiwi", tile_point(7, 7, quarter.x, quarter.y)) == null, "landing on an occupied tile places nothing (corner %s)" % quarter)
	check(play.cultivation.plants.size() == count, "no plant was added by the refused landings")
	# The nearest block is invalid -> the fixed order up-left, up-right, down-left, down-right takes over.
	var fallback: CultivatedPlant = play.cultivation.try_place(&"kiwi", tile_point(10, 10, 3.5, 3.5))
	check(fallback != null and fallback.tile == Vector2i(9, 9), "nearest block (10,10) reaches into empty ground, so the up-left block (9,9) is used")
	var fixed_order: Array[Vector2i] = play.cultivation.candidate_origins(2, tile_point(12, 12, 3.5, 3.5))
	check(fixed_order == [Vector2i(12, 12), Vector2i(11, 11), Vector2i(12, 11), Vector2i(11, 12)], "try order: nearest block, then up-left, up-right, down-left (%s)" % [fixed_order])
	var other_order: Array[Vector2i] = play.cultivation.candidate_origins(2, tile_point(12, 12, 0.5, 3.5))
	check(other_order == [Vector2i(11, 12), Vector2i(11, 11), Vector2i(12, 11), Vector2i(12, 12)], "point in the lower left: block (11,12) first, then the fixed order of the rest (%s)" % [other_order])
	# Empty ground.
	check(play.cultivation.try_place(&"carrot", tile_point(20, 20, 2.0, 2.0)) == null, "empty ground: nothing is planted")
	check(play.cultivation.try_place(&"carrot", tile_point(0, 0, 2.0, 2.0)) == null and play.cultivation.try_place(&"carrot", Vector2(-50, -50)) == null and play.cultivation.try_place(&"carrot", Vector2(30 * TILE + 3, 30 * TILE + 3)) == null, "the map corner and points outside the map plant nothing")
	check(play.cultivation.try_place(&"normal", tile_point(6, 6, 2.0, 2.0)) == null and play.cultivation.try_place(&"nonsense", tile_point(6, 6, 2.0, 2.0)) == null, "the ordinary plant and unknown kinds are not cultivated plants")
	# Defective blocks: a 4x4 mature field with one defective tile in the middle; the landing tile's four blocks all reach
	# the defective tile or the field's border.
	var defects: Array[String] = ["empty", "seed", "sprout1", "sprout2", "water", "building", "occupied"]
	for defect: String in defects:
		var rows: Array = []
		for y: int in 12:
			rows.append(".".repeat(12))
		if defect == "water" or defect == "building":
			var line: String = rows[6]
			rows[6] = line.substr(0, 6) + ("~" if defect == "water" else "#") + line.substr(7)
		var s2: WorldState = state_from_rows(rows)
		s2.debug_fill_stage(Rect2i(5, 5, 3, 3), WorldState.STAGE_MATURE)
		var middle: int = s2.index_of(6, 6)
		match defect:
			"empty":
				s2.set_stage(middle, WorldState.STAGE_EMPTY)
			"seed":
				s2.set_stage(middle, WorldState.STAGE_SEED)
			"sprout1":
				s2.set_stage(middle, WorldState.STAGE_SPROUT1)
			"sprout2":
				s2.set_stage(middle, WorldState.STAGE_SPROUT2)
			"occupied":
				s2.occupy(Rect2i(6, 6, 1, 1), 99)
		var p2: PlayState = make_play(s2)
		var before_stage: PackedByteArray = s2.stage.duplicate()
		var before_occupant: PackedInt32Array = s2.occupant.duplicate()
		var results: Array[bool] = []
		for tile: Vector2i in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 7), Vector2i(6, 6), Vector2i(7, 5), Vector2i(5, 7)]:
			results.append(p2.cultivation.try_place(&"carrot", tile_point(tile.x, tile.y, 2.0, 2.0)) != null)
		check(not results.has(true) and p2.cultivation.plants.is_empty() and s2.stage == before_stage and s2.occupant == before_occupant, "3x3 mature field with a '%s' middle tile: no 2x2 fits anywhere, nothing changes" % defect)
	# Control: the same 3x3 field without a defect accepts a plant.
	var clean: WorldState = blank(12, 12)
	clean.debug_fill_stage(Rect2i(5, 5, 3, 3), WorldState.STAGE_MATURE)
	check(make_play(clean).cultivation.try_place(&"carrot", tile_point(6, 6, 0.5, 0.5)) != null, "control: the clean 3x3 field accepts a carrot")
	# A 1-tile-wide strip never fits.
	var strip: WorldState = blank(12, 12)
	strip.debug_fill_stage(Rect2i(2, 5, 8, 1), WorldState.STAGE_MATURE)
	check(make_play(strip).cultivation.try_place(&"kiwi", tile_point(5, 5, 2.0, 2.0)) == null, "a mature strip one tile wide is too narrow")
	# Safe-zone tiles are mature target ground and accept a plant.
	var rows_safe: Array = []
	for y: int in 8:
		rows_safe.append("ssssssss")
	var safe_state: WorldState = state_from_rows(rows_safe)
	check(make_play(safe_state).cultivation.try_place(&"kiwi", tile_point(3, 3, 1.0, 1.0)) != null, "the safe zone (mature at the start) accepts a kiwi")
	# Water / building tiles beside a mature block are not touched.
	var rows_edge: Array = []
	for y: int in 8:
		rows_edge.append("...~~...")
	var edge_state: WorldState = state_from_rows(rows_edge)
	edge_state.debug_fill_stage(Rect2i(0, 0, 3, 8), WorldState.STAGE_MATURE)
	check(make_play(edge_state).cultivation.try_place(&"carrot", tile_point(2, 3, 3.5, 3.5)) != null and edge_state.stage[edge_state.index_of(3, 3)] == WorldState.STAGE_EMPTY, "a block at the edge of the mature area plants (fallback to the in-field block) and leaves the water alone")

func test_cost_and_limits() -> void:
	var state: WorldState = blank(60, 60)
	state.debug_fill_stage(Rect2i(2, 2, 50, 50), WorldState.STAGE_MATURE)
	var play: PlayState = make_play(state)
	play.seeds = 20
	var carrot: PlantDef = play.def_by_key(&"carrot")
	check(play.can_fire_plant(carrot) and not play.can_fire_plant(play.def_by_key(&"normal")), "a carrot can be fired with 20 seeds; the ordinary plant is not a cultivated shot")
	play.reserve_plant(carrot)
	check(play.seeds == 20 and play.reserved_seeds == 3 and play.available_seeds() == 17, "firing holds 3 seeds back (seeds %d, available %d)" % [play.seeds, play.available_seeds()])
	var planted: CultivatedPlant = play.land_plant(&"carrot", tile_point(10, 10, 0.0, 0.0))
	check(planted != null and play.seeds == 17 and play.reserved_seeds == 0 and play.plant_landings == 1, "a successful landing spends exactly 3 seeds (20 -> %d)" % play.seeds)
	play.reserve_plant(carrot)
	var failed: CultivatedPlant = play.land_plant(&"carrot", tile_point(57, 57, 1.0, 1.0))
	check(failed == null and play.seeds == 17 and play.reserved_seeds == 0 and play.available_seeds() == 17 and play.plant_failures == 1, "a landing on ground that does not fit spends nothing and gives the held-back seeds back")
	play.reserve_plant(carrot)
	play.cancel_plant(&"carrot")
	check(play.reserved_seeds == 0 and int(play.inflight.get(&"carrot", 0)) == 0, "a shot that ends in the air (cancel) releases its seeds")
	play.seeds = 2
	check(not play.can_fire_plant(carrot) and not play.can_fire_plant(play.def_by_key(&"kiwi")), "with 2 seeds neither cultivated plant can be fired")
	play.seeds = 5
	check(play.can_fire_plant(carrot), "with 5 seeds a carrot can be fired")
	play.reserve_plant(carrot)
	check(not play.can_fire_plant(carrot) and play.available_seeds() == 2, "while a shot is in flight only 2 seeds are free: no second cultivated shot")
	check(play.available_seeds() == 2 and play.can_fire_seed() and not play.can_fire_plant(carrot), "the 2 free seeds still allow ordinary seed shots but not another carrot")
	play.cancel_plant(&"carrot")
	# Limit of 32 per kind (counting shots in flight).
	var big: WorldState = blank(80, 80)
	big.debug_fill_stage(Rect2i(0, 0, 80, 80), WorldState.STAGE_MATURE)
	var rich: PlayState = make_play(big)
	rich.seeds = 1000
	var placed: int = 0
	for i: int in 40:
		var plant: CultivatedPlant = rich.cultivation.try_place(&"carrot", tile_point(2 + (i % 8) * 3 + 1, 2 + (i / 8) * 3 + 1, 0.0, 0.0))
		if plant != null:
			placed += 1
	check(placed == 32 and rich.cultivation.count(&"carrot") == 32, "at most 32 carrots are placed (%d of 40 tries)" % placed)
	check(not rich.can_fire_plant(rich.def_by_key(&"carrot")) and rich.can_fire_plant(rich.def_by_key(&"kiwi")), "at the limit no carrot can be fired, kiwis still can (the limit is per kind)")
	var kiwi_def: PlantDef = rich.def_by_key(&"kiwi")
	var small: Array[PlantDef] = defs.duplicate()
	small[2] = kiwi_def.duplicate() as PlantDef
	small[2].max_count = 2
	var big2: WorldState = blank(80, 80)
	big2.debug_fill_stage(Rect2i(0, 0, 80, 80), WorldState.STAGE_MATURE)
	var limited: PlayState = make_play(big2, small)
	limited.seeds = 100
	limited.reserve_plant(limited.def_by_key(&"kiwi"))
	var one: CultivatedPlant = limited.land_plant(&"kiwi", tile_point(60, 60, 0.0, 0.0))
	limited.reserve_plant(limited.def_by_key(&"kiwi"))
	check(one != null and limited.cultivation.count(&"kiwi") == 1 and not limited.can_fire_plant(limited.def_by_key(&"kiwi")), "limit 2: one placed + one in flight reaches the limit, a third cannot be fired")
	limited.cancel_plant(&"kiwi")
	check(limited.can_fire_plant(limited.def_by_key(&"kiwi")) and limited.reserved_seeds == 0, "after the shots end the limit frees up again")

func test_occupied_not_planted() -> void:
	var state: WorldState = blank(40, 40)
	state.debug_fill_stage(Rect2i(14, 14, 2, 2), WorldState.STAGE_MATURE)
	var play: PlayState = make_play(state)
	var plant: CultivatedPlant = play.cultivation.try_place(&"carrot", tile_point(15, 15, 0.0, 0.0))
	check(plant != null and plant.tile == Vector2i(14, 14), "carrot placed on a mature 2x2 patch surrounded by empty ground")
	var tiles: Array[int] = []
	for y: int in range(plant.tile.y, plant.tile.y + 2):
		for x: int in range(plant.tile.x, plant.tile.x + 2):
			tiles.append(state.index_of(x, y))
	var all_blocked: bool = true
	for index: int in tiles:
		all_blocked = all_blocked and not state.can_plant(index)
	check(all_blocked, "can_plant is false on the four occupied tiles")
	var center: Vector2 = (plant.center_tiles()) * TILE
	var touched: bool = false
	var planted_around: int = 0
	for shot: int in 12:
		var scattered: PackedInt32Array = play.land_seed(center + Vector2(shot % 3 - 1, shot % 4 - 1))
		planted_around += scattered.size()
		for index: int in scattered:
			touched = touched or tiles.has(index)
	var kept: bool = true
	for index: int in tiles:
		kept = kept and state.stage[index] == WorldState.STAGE_MATURE
	check(not touched and kept and planted_around > 6, "12 seed landings on the plant plant %d tiles around it and never into its footprint; the footprint stays mature" % planted_around)
	# A free empty tile that is occupied by another big plant is not planted either.
	var s2: WorldState = blank(30, 30)
	s2.debug_fill_stage(Rect2i(10, 10, 4, 4), WorldState.STAGE_MATURE)
	s2.occupy(Rect2i(14, 10, 1, 1), 55)
	var spread: SpreadSim = SpreadSim.new(s2, sim_tuning)
	for i: int in 30:
		spread.tick()
	check(s2.stage[s2.index_of(14, 10)] == WorldState.STAGE_EMPTY and s2.stage[s2.index_of(14, 11)] != WorldState.STAGE_EMPTY, "natural spread skips an occupied empty tile but plants its free neighbours")
	# Natural spread around a placed carrot: the footprint stays as it is.
	var s3: WorldState = blank(30, 30)
	s3.debug_fill_stage(Rect2i(10, 10, 6, 6), WorldState.STAGE_MATURE)
	var p3: PlayState = make_play(s3)
	var plant3: CultivatedPlant = p3.cultivation.try_place(&"kiwi", tile_point(12, 12, 0.0, 0.0))
	var spread3: SpreadSim = SpreadSim.new(s3, sim_tuning)
	for i: int in 40:
		spread3.tick()
	var intact: bool = true
	for y: int in range(plant3.tile.y, plant3.tile.y + 2):
		for x: int in range(plant3.tile.x, plant3.tile.x + 2):
			intact = intact and s3.stage[s3.index_of(x, y)] == WorldState.STAGE_MATURE and s3.occupant[s3.index_of(x, y)] == 1000 + plant3.uid
	check(intact and s3.counters_consistent(), "40 spread ticks around a kiwi leave its footprint mature and occupied; counters match a recount")
	# After 40 ticks the spread planted tiles around the field, so greening grew by planted tiles only.
	check(s3.greened_count == s3.recount_greened() and s3.greened_count == 36 and s3.natural.count(1) > 10, "greening count equals a recount and is still the 36 field tiles (planted seeds are not green yet; %d seeds around)" % s3.natural.count(1))

# ---- carrot --------------------------------------------------------------------------------------------------------


## Ticks until a candidate with `near` mature tiles in range becomes a seed, written from the spec numbers.
func expected_ticks(near: int, permille: int) -> int:
	var per_tick: int = (10000 + 2500 * (near - 1)) * permille / 1000
	var ticks: int = 1
	while ticks * per_tick < 100000:
		ticks += 1
	return ticks

func carrot_patch(width: int, height: int) -> WorldState:
	var state: WorldState = blank(width, height)
	state.debug_fill_stage(Rect2i(10, 10, 8, 8), WorldState.STAGE_MATURE)
	state.debug_fill_stage(Rect2i(60, 10, 8, 8), WorldState.STAGE_MATURE)
	return state

func test_carrot() -> void:
	var state: WorldState = carrot_patch(100, 30)
	var play: PlayState = make_play(state)
	var spread: SpreadSim = SpreadSim.new(state, sim_tuning)
	play.cultivation.boost_sink = spread.set_speed_scale
	var plant: CultivatedPlant = play.cultivation.try_place(&"carrot", tile_point(11, 11, 0.0, 0.0))
	check(plant != null and plant.tile == Vector2i(10, 10) and not plant.mature, "carrot placed at the corner of patch A, young")
	# Expected oracle inputs, computed before anything moves.
	var candidates: Dictionary = {}
	for index: int in state.tile_count():
		if state.can_plant(index):
			var near: int = near_brute_local(state, index % state.width, index / state.width)
			if near > 0:
				candidates[index] = near
	check(candidates.size() > 60, "two patches have %d spread candidates in total" % candidates.size())
	var center: Vector2 = Vector2(11.0, 11.0)
	var in_range: Dictionary = {}
	for index: int in state.tile_count():
		var d: Vector2 = Vector2(index % state.width + 0.5, index / state.width + 0.5) - center
		if d.length_squared() <= 144.0:
			in_range[index] = true
	var boosted_candidates: int = 0
	for index: int in candidates:
		if in_range.has(index):
			boosted_candidates += 1
	check(boosted_candidates > 20 and boosted_candidates < candidates.size() / 2 + 20, "radius 12 covers %d of the %d candidates (almost all of patch A's ring, none of patch B's)" % [boosted_candidates, candidates.size()])
	# Young carrot (39 s): no change at all.
	run_play(play, 39.0, 60)
	check(not plant.mature and spread.speed_scale.is_empty() and play.cultivation.boost.is_empty(), "after 39 s the carrot is still young and no boost exists")
	for tick: int in 12:
		spread.tick()
	var young_ok: bool = true
	for index: int in candidates:
		var seeded: bool = state.natural[index] == 1
		young_ok = young_ok and (seeded == (expected_ticks(int(candidates[index]), 1000) <= 12))
	check(young_ok, "young carrot: after 12 ticks exactly the candidates whose unboosted time (<= 12 ticks) passed are seeds, inside the radius too")
	# Fresh worlds are needed from here: repeat with a mature carrot and record the exact tick of every candidate.
	var fresh: WorldState = carrot_patch(100, 30)
	var fplay: PlayState = make_play(fresh)
	var fspread: SpreadSim = SpreadSim.new(fresh, sim_tuning)
	fplay.cultivation.boost_sink = fspread.set_speed_scale
	var fplant: CultivatedPlant = fplay.cultivation.try_place(&"carrot", tile_point(11, 11, 0.0, 0.0))
	run_play(fplay, 40.2, 60)
	check(fplant.mature and fplay.cultivation.boost.size() == fresh.tile_count(), "after 40 s the carrot is mature and the boost array is installed")
	var wrong_scale: int = 0
	for index: int in fresh.tile_count():
		var d: Vector2 = Vector2(index % fresh.width + 0.5, index / fresh.width + 0.5) - center
		var expected_scale: int = 2000 if d.length_squared() <= 144.0 else 1000
		if fspread.scale_for(index) != expected_scale or fplay.cultivation.boost_at(index) != expected_scale:
			wrong_scale += 1
	check(wrong_scale == 0, "the speed multiplier is 2.0 inside radius 12 of the footprint centre and 1.0 everywhere else (wrong tiles: %d)" % wrong_scale)
	var first_tick: Dictionary = {}
	for tick: int in range(1, 13):
		fspread.tick()
		for index: int in candidates:
			if not first_tick.has(index) and fresh.stage[index] != WorldState.STAGE_EMPTY:
				first_tick[index] = tick
	var mismatches: int = 0
	var fast_inside: int = 0
	var normal_outside: int = 0
	var worst: String = ""
	for index: int in candidates:
		var permille: int = 2000 if in_range.has(index) else 1000
		var want: int = expected_ticks(int(candidates[index]), permille)
		var got: int = int(first_tick.get(index, 99))
		if got != want:
			mismatches += 1
			worst = "tile %d near %d scale %d wanted %d got %d" % [index, int(candidates[index]), permille, want, got]
		if in_range.has(index):
			fast_inside += 1 if got < expected_ticks(int(candidates[index]), 1000) else 0
		else:
			normal_outside += 1 if got == expected_ticks(int(candidates[index]), 1000) else 0
	check(mismatches == 0, "every candidate (%d) became a seed at exactly the oracle tick: boosted inside the radius, normal outside (%s)" % [candidates.size(), worst])
	check(fast_inside == boosted_candidates and normal_outside == candidates.size() - boosted_candidates, "inside: %d candidates faster than without the carrot; outside (patch A beyond the radius and all of patch B): %d unchanged" % [fast_inside, normal_outside])
	var seed_ticks: Array[int] = []
	for index: int in in_range:
		if candidates.has(index) and int(candidates[index]) == 1:
			seed_ticks.append(int(first_tick[index]))
	check(not seed_ticks.is_empty() and seed_ticks.min() == 5 and seed_ticks.max() == 5, "a candidate with one mature neighbour inside the radius: 5 ticks (10 without the carrot)")
	check(fresh.counters_consistent(), "counters consistent after the boosted spread")
	# Overlap: the largest multiplier wins, no adding up.
	var big_carrot: PlantDef = defs[1].duplicate() as PlantDef
	big_carrot.key = &"carrot_big"
	big_carrot.effect_multiplier = 3.0
	big_carrot.effect_radius_tiles = 7.0
	var with_big: Array[PlantDef] = defs.duplicate()
	with_big.append(big_carrot)
	var overlap_state: WorldState = blank(60, 30)
	overlap_state.debug_fill_stage(Rect2i(10, 10, 20, 8), WorldState.STAGE_MATURE)
	var overlap_play: PlayState = make_play(overlap_state, with_big)
	var overlap_spread: SpreadSim = SpreadSim.new(overlap_state, sim_tuning)
	overlap_play.cultivation.boost_sink = overlap_spread.set_speed_scale
	var a: CultivatedPlant = overlap_play.cultivation.try_place(&"carrot", tile_point(11, 11, 0.0, 0.0))
	var b: CultivatedPlant = overlap_play.cultivation.try_place(&"carrot_big", tile_point(19, 11, 0.0, 0.0))
	run_play(overlap_play, 41.0, 60)
	var ca: Vector2 = a.center_tiles()
	var cb: Vector2 = b.center_tiles()
	var overlap_wrong: int = 0
	var both: int = 0
	var seen_values: Dictionary = {}
	for index: int in overlap_state.tile_count():
		var p: Vector2 = Vector2(index % overlap_state.width + 0.5, index / overlap_state.width + 0.5)
		var in_a: bool = (p - ca).length_squared() <= 144.0
		var in_b: bool = (p - cb).length_squared() <= 49.0
		var want: int = 1000
		if in_a:
			want = 2000
		if in_b:
			want = 3000
		both += 1 if in_a and in_b else 0
		seen_values[overlap_spread.scale_for(index)] = true
		if overlap_spread.scale_for(index) != want:
			overlap_wrong += 1
	check(a.mature and b.mature and both > 20 and overlap_wrong == 0 and seen_values.keys().size() == 3, "two overlapping carrots: the larger multiplier wins in the overlap (%d tiles covered by both), values seen %s" % [both, seen_values.keys()])
	info["carrot_candidates"] = candidates.size()
	info["carrot_boosted_candidates"] = boosted_candidates

# ---- kiwi --------------------------------------------------------------------------------------------------------

func kiwi_world() -> WorldState:
	var state: WorldState = blank(60, 60)
	state.debug_fill_stage(Rect2i(5, 5, 40, 40), WorldState.STAGE_MATURE)
	return state

func test_kiwi() -> void:
	var state: WorldState = kiwi_world()
	var play: PlayState = make_play(state)
	var kiwi: CultivatedPlant = play.cultivation.try_place(&"kiwi", tile_point(20, 20, 0.0, 0.0))
	check(kiwi != null, "kiwi placed")
	var timeline: Dictionary = {}
	var max_fruits: int = 0
	var max_age: float = 0.0
	var step: int = 0
	var marks: Array[float] = [39.9, 40.1, 59.9, 60.1, 79.9, 80.1, 89.9, 90.1, 100.0]
	var cursor: int = 0
	while cursor < marks.size():
		play.advance(1.0 / 60.0, FAR)
		step += 1
		var now: float = float(step) / 60.0
		max_fruits = maxi(max_fruits, play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT))
		for item: Dictionary in play.pickups.items:
			max_age = maxf(max_age, float(item["age"]))
		if now >= marks[cursor] - 1.0e-6:
			timeline[marks[cursor]] = [kiwi.mature, play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT)]
			cursor += 1
	check(timeline[39.9] == [false, 0] and timeline[40.1] == [true, 0], "young until 40 s, mature at 40.1 s, no fruit yet (%s %s)" % [timeline[39.9], timeline[40.1]])
	check(timeline[59.9] == [true, 0] and timeline[60.1] == [true, 1], "first fruit exactly 20 s after maturity, at 60 s (%s then %s)" % [timeline[59.9], timeline[60.1]])
	check(timeline[79.9] == [true, 1] and timeline[80.1] == [true, 2], "second fruit at 80 s (%s then %s)" % [timeline[79.9], timeline[80.1]])
	check(timeline[89.9] == [true, 2] and max_fruits == 2, "the cap of 2 fruits per kiwi holds (never more than %d)" % max_fruits)
	check(timeline[90.1] == [true, 1] and timeline[100.0] == [true, 1], "the first fruit disappears after its 30 s lifetime (at 90 s), the replacement is not due before 110 s")
	check(max_age < 30.0 + 1.0 / 60.0, "no fruit grew older than its lifetime of 30 s (oldest seen %.3f s)" % max_age)
	var heal_items: Array[Dictionary] = []
	for item: Dictionary in play.pickups.items:
		if String(item["kind"]) == GroundPickups.KIND_HEAL_FRUIT:
			heal_items.append(item)
	var center: Vector2 = kiwi.center_tiles() * TILE
	var distance_ok: bool = not heal_items.is_empty()
	for item: Dictionary in heal_items:
		var d: float = Vector2(float(item["x"]), float(item["y"])).distance_to(center)
		distance_ok = distance_ok and d >= 6.0 - 1.0e-6 and d <= 12.0 + 1.0e-6 and int(item["owner"]) == GroundPickups.HEAL_OWNER_BASE + kiwi.uid
	check(distance_ok, "fruits lie 6..12 px from the kiwi centre and belong to the kiwi")
	# Collection and HP.
	var p2: PlayState = make_play(kiwi_world())
	var k2: CultivatedPlant = p2.cultivation.try_place(&"kiwi", tile_point(20, 20, 0.0, 0.0))
	run_play(p2, 61.0, 60)
	var fruit: Dictionary = first_heal(p2)
	check(not fruit.is_empty() and p2.hp == 10, "a fruit is lying around and the player is at full HP")
	var spot: Vector2 = Vector2(float(fruit["x"]), float(fruit["y"]))
	run_play(p2, 1.0, 60, spot)
	check(p2.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT) == 1 and p2.hp == 10, "standing on the fruit at full HP: it is NOT collected")
	p2.damage_player(1)
	run_play(p2, 1.0 / 60.0, 60, spot)
	check(p2.hp == 10 and p2.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT) == 0, "at 9 HP the fruit is collected: +2 clamps at the maximum 10")
	p2.damage_player(5)
	check(p2.hp == 5, "HP 5 after 5 damage")
	# Wait for the next fruit with the player away, then collect it: exactly +2.
	var guard: int = 0
	while first_heal(p2).is_empty() and guard < 60 * 60:
		p2.advance(1.0 / 60.0, FAR)
		guard += 1
	var next_fruit: Dictionary = first_heal(p2)
	check(not next_fruit.is_empty(), "the kiwi keeps producing (next fruit after %.1f s)" % (guard / 60.0))
	run_play(p2, 1.0 / 60.0, 60, Vector2(float(next_fruit["x"]), float(next_fruit["y"])))
	check(p2.hp == 7, "collecting a fruit restores exactly 2 HP (5 -> %d)" % p2.hp)
	# Collection range.
	var p3: PlayState = make_play(kiwi_world())
	p3.cultivation.try_place(&"kiwi", tile_point(20, 20, 0.0, 0.0))
	run_play(p3, 61.0, 60)
	var fr3: Dictionary = first_heal(p3)
	p3.damage_player(4)
	var f3: Vector2 = Vector2(float(fr3["x"]), float(fr3["y"]))
	run_play(p3, 0.5, 60, f3 + Vector2(13.5, 0))
	check(p3.hp == 6 and p3.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT) == 1, "a player 13.5 px away does not collect (radius is 12)")
	run_play(p3, 0.5, 60, f3 + Vector2(11.0, 0))
	check(p3.hp == 8 and p3.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT) == 0, "a player 11 px away collects")
	# A seed fruit and a healing fruit side by side: HP full -> only the seed fruit goes.
	var p4: PlayState = make_play(blank(10, 10))
	p4.seeds = 5
	p4.pickups.spawn(GroundPickups.KIND_HEAL_FRUIT, Vector2(10, 10), GroundPickups.HEAL_OWNER_BASE + 77, 30.0)
	p4.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(11, 10), 1)
	p4.advance(1.0 / 60.0, Vector2(10, 10))
	check(p4.seeds == 6 and p4.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT) == 1 and p4.pickups.count_kind(GroundPickups.KIND_SEED_FRUIT) == 0, "full HP: the seed fruit is taken (seeds 5 -> 6), the healing fruit stays")
	p4.damage_player(6)
	p4.advance(1.0 / 60.0, Vector2(10, 10))
	check(p4.hp == 6 and p4.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT) == 0, "orphan healing fruit (no plant) heals the fallback amount 2 (HP 4 -> %d)" % p4.hp)
	# Seed pouch full: a healing fruit is still collected, a seed fruit is not.
	var p5: PlayState = make_play(blank(10, 10))
	p5.seeds = p5.tuning.seed_max
	p5.damage_player(3)
	p5.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(10, 10), 1)
	p5.pickups.spawn(GroundPickups.KIND_HEAL_FRUIT, Vector2(10, 11), GroundPickups.HEAL_OWNER_BASE + 77, 30.0)
	p5.advance(1.0 / 60.0, Vector2(10, 10))
	check(p5.hp == 9 and p5.pickups.count_kind(GroundPickups.KIND_SEED_FRUIT) == 1, "full seed pouch: the healing fruit is collected, the seed fruit stays")
	info["kiwi_first_fruit_s"] = 60.0

func test_budget() -> void:
	var state: WorldState = blank(100, 100)
	state.debug_fill_stage(Rect2i(2, 2, 90, 90), WorldState.STAGE_MATURE)
	var play: PlayState = make_play(state, defs, [Vector2(10, 10)] as Array[Vector2])
	play.seeds = 200
	for i: int in 10:
		play.cultivation.try_place(&"kiwi", tile_point(10 + i * 6, 40, 0.0, 0.0))
	check(play.cultivation.count(&"kiwi") == 10, "ten kiwis placed")
	run_play(play, 85.0, 60)
	var heal: int = play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT)
	check(heal == 16 and play.pickups.count_owned(1) >= 1 and play.sources[0].drops >= 5, "ten kiwis want 20 fruits: the region holds 16 (cap); the seed source kept dropping fruits (%d healing, %d source fruits on the ground, %d dropped)" % [heal, play.pickups.count_owned(1), play.sources[0].drops])
	# Fill the seed budget completely; healing fruits do not count against it and it does not count against them.
	var accepted_plant: int = 0
	for i: int in 30:
		if play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(300 + i, 300), GroundPickups.PLANT_OWNER_BASE + i):
			accepted_plant += 1
	check(accepted_plant == 20 and play.pickups.count_plant_owned() == 20, "plant seed fruits still reach their cap of 20 with 16 healing fruits on the ground (accepted %d)" % accepted_plant)
	var extra_source: int = 0
	for i: int in 20:
		if play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(400 + i, 300), 1):
			extra_source += 1
	var seed_items: int = play.pickups.count_seed_items()
	check(seed_items == play.tuning.pickup_total_cap and extra_source >= 1, "seed fruits fill their whole total of %d in spite of the healing fruits (%d items, %d more source fruits accepted)" % [play.tuning.pickup_total_cap, seed_items, extra_source])
	check(not play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(1, 1), 1), "one more seed fruit than the total is refused")
	check(play.pickups.count() == play.tuning.pickup_total_cap + 16, "healing fruits sit on top of the seed budget: %d items = %d seed + 16 healing" % [play.pickups.count(), play.tuning.pickup_total_cap])
	# And the other way round: with the seed budget full a healing fruit is still accepted once its own cap has room.
	var removed: Dictionary = first_heal(play)
	play.pickups.items.erase(removed)
	check(play.pickups.spawn(GroundPickups.KIND_HEAL_FRUIT, Vector2(5, 5), GroundPickups.HEAL_OWNER_BASE + 999, 30.0) and not play.pickups.spawn(GroundPickups.KIND_HEAL_FRUIT, Vector2(6, 6), GroundPickups.HEAL_OWNER_BASE + 999, 30.0), "a full seed budget does not block a healing fruit; the healing cap of 16 still applies")
	check(play.pickups.count_plant_owned() == 20, "count_plant_owned ignores healing fruits")

# ---- frame rate ----------------------------------------------------------------------------------------------------

func test_frame_rate() -> void:
	var summaries: Array[Dictionary] = []
	for hz: int in [30, 60, 144]:
		var state: WorldState = kiwi_world()
		var play: PlayState = make_play(state)
		var kiwi: CultivatedPlant = play.cultivation.try_place(&"kiwi", tile_point(20, 20, 0.0, 0.0))
		var carrot: CultivatedPlant = play.cultivation.try_place(&"carrot", tile_point(30, 30, 0.0, 0.0))
		var spread: SpreadSim = SpreadSim.new(state, sim_tuning)
		play.cultivation.boost_sink = spread.set_speed_scale
		var mature_at: float = -1.0
		var carrot_at: float = -1.0
		var fruit_at: float = -1.0
		var steps: int = 100 * hz
		var at_85: Array = []
		var counts: Array[int] = []
		for i: int in steps:
			play.advance(1.0 / hz, FAR)
			var now: float = float(i + 1) / hz
			if mature_at < 0.0 and kiwi.mature:
				mature_at = now
			if carrot_at < 0.0 and carrot.mature:
				carrot_at = now
			if fruit_at < 0.0 and play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT) > 0:
				fruit_at = now
			if i + 1 == 85 * hz:
				for item: Dictionary in play.pickups.items:
					at_85.append([snappedf(float(item["x"]), 0.0001), snappedf(float(item["y"]), 0.0001), int(item["owner"])])
				counts.append(play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT))
		summaries.append({"hz": hz, "mature_at": mature_at, "carrot_at": carrot_at, "fruit_at": fruit_at, "at_85": at_85, "counts": counts, "boost": hash(play.cultivation.boost), "drops": kiwi.drops, "end_fruits": play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT)})
	var within: bool = true
	for summary: Dictionary in summaries:
		var step: float = 1.0 / int(summary["hz"])
		within = within and float(summary["mature_at"]) >= 40.0 - 1.0e-6 and float(summary["mature_at"]) <= 40.0 + step + 1.0e-6
		within = within and float(summary["carrot_at"]) >= 40.0 - 1.0e-6 and float(summary["carrot_at"]) <= 40.0 + step + 1.0e-6
		within = within and float(summary["fruit_at"]) >= 60.0 - 1.0e-6 and float(summary["fruit_at"]) <= 60.0 + 2.0 * step + 1.0e-6
	check(within, "30 / 60 / 144 Hz: maturity at 40 s and the first fruit at 60 s to within a frame (%s)" % [summaries.map(func(s: Dictionary) -> Array: return [s["mature_at"], s["fruit_at"]])])
	check(summaries[0]["at_85"] == summaries[1]["at_85"] and summaries[1]["at_85"] == summaries[2]["at_85"] and summaries[0]["counts"] == [2], "30 / 60 / 144 Hz: the same two fruits at the same places after 85 s")
	check(summaries[0]["boost"] == summaries[1]["boost"] and summaries[1]["boost"] == summaries[2]["boost"], "30 / 60 / 144 Hz: identical carrot boost array")
	check(summaries[0]["drops"] == summaries[1]["drops"] and summaries[1]["drops"] == summaries[2]["drops"] and summaries[0]["end_fruits"] == summaries[2]["end_fruits"], "30 / 60 / 144 Hz: same number of drops after 100 s (%s)" % [summaries.map(func(s: Dictionary) -> int: return s["drops"])])

# ---- save --------------------------------------------------------------------------------------------------------

func test_save() -> void:
	var state: WorldState = kiwi_world()
	var play: PlayState = make_play(state)
	play.seeds = 30
	play.cultivation.try_place(&"kiwi", tile_point(20, 20, 0.0, 0.0))
	play.cultivation.try_place(&"carrot", tile_point(30, 30, 0.0, 0.0))
	play.cultivation.try_place(&"kiwi", tile_point(12, 30, 0.0, 0.0))
	run_play(play, 75.0, 60)
	play.damage_player(4)
	play.select_index(2)
	var third: CultivatedPlant = play.cultivation.try_place(&"carrot", tile_point(40, 12, 0.0, 0.0))
	run_play(play, 5.0, 60)
	check(third != null and not third.mature and play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT) >= 2, "save point: young and mature plants, fruits on the ground, HP 6")
	var world_data: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var play_data: Dictionary = JSON.parse_string(JSON.stringify(play.to_dict()))
	var restored_world: WorldState = WorldState.from_dict(world_data, region_def.terrains)
	check(restored_world != null and restored_world.occupancy_owners.size() == 4, "the world save holds the four occupied footprints")
	var twin: PlayState = make_play(restored_world)
	check(twin.load_dict(play_data), "play state restores from its save")
	check(twin.hp == 6 and twin.hp_max == 10 and twin.selected_def().key == &"kiwi", "HP and the selection survive the round trip")
	check(JSON.stringify(twin.cultivation.to_dict()) == JSON.stringify(play.cultivation.to_dict()), "the plant list (kind, position, growth, fruit timer, drops) is identical after the round trip")
	check(restored_world.occupant == state.occupant and JSON.stringify(twin.pickups.to_dict()) == JSON.stringify(play.pickups.to_dict()), "occupancy and the ground fruits (with their own lifetimes) are identical")
	run_play(play, 45.0, 60)
	run_play(twin, 45.0, 60)
	check(JSON.stringify(twin.cultivation.to_dict()) == JSON.stringify(play.cultivation.to_dict()) and JSON.stringify(twin.pickups.to_dict()) == JSON.stringify(play.pickups.to_dict()) and twin.hp == play.hp, "restored and original run 45 s more with identical plants, fruits and HP")
	check(twin.cultivation.boost == play.cultivation.boost and not twin.cultivation.boost.is_empty(), "the carrot boost is rebuilt from the plant list")
	# Loading into a running state replaces its plants and keeps the occupancy consistent.
	var other: PlayState = make_play(restored_world)
	other.load_dict(play_data)
	check(other.load_dict(play_data) and other.cultivation.plants.size() == 4 and restored_world.occupancy_owners.size() == 4, "loading the same save twice does not duplicate plants or occupancy")
	# A save that does not fit is refused and changes nothing.
	var bad: Dictionary = play_data.duplicate(true)
	(bad["cultivated"]["plants"] as Array)[0]["x"] = -5
	(bad["cultivated"]["plants"] as Array)[0]["y"] = -5
	var before: String = JSON.stringify(other.cultivation.to_dict())
	var occupant_before: PackedInt32Array = restored_world.occupant.duplicate()
	check(not other.load_dict(bad) and JSON.stringify(other.cultivation.to_dict()) == before and restored_world.occupant == occupant_before, "a save with a plant on ground that cannot hold it is refused and leaves the running state alone")
	# Old saves without the new keys still load (HP full, ordinary plant selected, no plants).
	var legacy: Dictionary = play_data.duplicate(true)
	legacy.erase("hp")
	legacy.erase("cultivated")
	legacy.erase("selected")
	var empty_world: WorldState = kiwi_world()
	var old: PlayState = make_play(empty_world)
	check(old.load_dict(legacy) and old.hp == 10 and old.selected_index == 0 and old.cultivation.plants.is_empty(), "a save without HP / plants loads with defaults")
	test_save_rejects(play_data)

## Inconsistent plant saves are refused (false) and leave plants and occupancy exactly as they were.
func test_save_rejects(play_data: Dictionary) -> void:
	# Fresh world first (no occupancy in it yet), then the same world restored with its own occupancy.
	var cases: Array[Dictionary] = [
		{"name": "empty ground", "x": 50, "y": 50},
		{"name": "partly outside the map (right)", "x": 59, "y": 20},
		{"name": "partly outside the map (negative)", "x": -1, "y": 20},
		{"name": "far outside the map", "x": 500, "y": 500},
		{"name": "a seed tile in the footprint", "stage": WorldState.STAGE_SEED},
		{"name": "a sprout 1 tile in the footprint", "stage": WorldState.STAGE_SPROUT1},
		{"name": "a sprout 2 tile in the footprint", "stage": WorldState.STAGE_SPROUT2},
		{"name": "an empty tile in the footprint", "stage": WorldState.STAGE_EMPTY},
		{"name": "water in the footprint (not a target)", "water": true},
		{"name": "overlap with another occupant", "foreign": true},
		{"name": "two saved plants on the same tiles", "twin": true},
		{"name": "mature with an age below the growth time", "mature": true, "age": 5.0},
		{"name": "young with an age past the growth time", "mature": false, "age": 41.0},
		{"name": "age beyond the growth time", "mature": true, "age": 99.0},
	]
	var refused_all: bool = true
	for entry: Dictionary in cases:
		var rows: Array = []
		for y: int in 60:
			rows.append(".".repeat(60))
		if entry.has("water"):
			var line: String = rows[21]
			rows[21] = line.substr(0, 21) + "~" + line.substr(22)
		var world: WorldState = state_from_rows(rows)
		world.debug_fill_stage(Rect2i(5, 5, 40, 40), WorldState.STAGE_MATURE)
		if entry.has("stage"):
			world.set_stage(world.index_of(21, 21), int(entry["stage"]))
		if entry.has("foreign"):
			world.occupy(Rect2i(21, 21, 1, 1), 99)
		var data: Dictionary = play_data.duplicate(true)
		var plants: Array = data["cultivated"]["plants"]
		var first: Dictionary = plants[0]
		first["x"] = int(entry.get("x", 20))
		first["y"] = int(entry.get("y", 20))
		if entry.has("mature"):
			first["mature"] = entry["mature"]
		if entry.has("age"):
			first["age"] = entry["age"]
		if entry.has("twin"):
			plants[1]["x"] = first["x"]
			plants[1]["y"] = first["y"]
		var target: PlayState = make_play(world)
		var occupant_before: PackedInt32Array = world.occupant.duplicate()
		var owners_before: int = world.occupancy_owners.size()
		var accepted: bool = target.load_dict(data)
		var unchanged: bool = target.cultivation.plants.is_empty() and world.occupant == occupant_before and world.occupancy_owners.size() == owners_before
		var ok: bool = not accepted and unchanged
		refused_all = refused_all and ok
		check(ok, "bad plant save (%s): refused, nothing changed (accepted=%s)" % [entry["name"], accepted])
	check(refused_all, "every inconsistent plant save is refused")
	# Running state with plants: a refused load keeps them and their occupancy (rollback).
	var live_world: WorldState = kiwi_world()
	var live: PlayState = make_play(live_world)
	live.cultivation.try_place(&"kiwi", tile_point(30, 30, 0.0, 0.0))
	var live_dict: String = JSON.stringify(live.cultivation.to_dict())
	var live_occupant: PackedInt32Array = live_world.occupant.duplicate()
	var bad_empty: Dictionary = play_data.duplicate(true)
	bad_empty["cultivated"]["plants"][0]["x"] = 50
	bad_empty["cultivated"]["plants"][0]["y"] = 50
	check(not live.load_dict(bad_empty) and JSON.stringify(live.cultivation.to_dict()) == live_dict and live_world.occupant == live_occupant, "a refused save on a running state keeps its plants and occupancy")
	# And the good save still goes through on a fresh world (no occupancy yet) and on a restored one.
	var good_world: WorldState = kiwi_world()
	var good: PlayState = make_play(good_world)
	check(good.load_dict(play_data) and good.cultivation.plants.size() == 4, "the consistent save still loads onto a world without occupancy (footprints validated first, then occupied)")

# ---- real scene, injected input -------------------------------------------------------------------------------

var main: Node
var player: FlowerPlayer
var mouse_screen: Vector2 = Vector2(320, 180)

func send_key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func wheel(button: MouseButton) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.factor = 1.0
		event.position = mouse_screen
		event.global_position = mouse_screen
		Input.parse_input_event(event)
	# Injected events are flushed at the start of the next frame: wait two.
	await process_frame
	await process_frame

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

func shoot_at(tile: Vector2i, wait: int = 40) -> void:
	await aim_at((Vector2(tile) + Vector2(0.5, 0.5)) * TILE)
	await click(MOUSE_BUTTON_LEFT)
	await wait_frames(wait)

func test_scene() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	pin_reference_spread(main.tuning)
	await wait_frames(3)
	player = main.player
	var play: PlayState = main.play
	var state: WorldState = main.grid
	var spread: SpreadSim = main.simulation.spread
	check(play.selectable.size() == 3 and play.selected_index == 0 and main.hud.plant_label.text == "植物 [通常] にんじん キウイ", "scene: the HUD lists the three plants, the ordinary one is selected (%s)" % main.hud.plant_label.text)
	check(main.hud.hp_label.text == "HP 10/10", "scene: the HUD shows HP 10/10")
	# Selection by injected Tab and wheel events.
	send_key(KEY_TAB, true)
	await process_frame
	send_key(KEY_TAB, false)
	await process_frame
	check(play.selected_index == 1 and main.hud.plant_label.text == "植物 通常 [にんじん:3] キウイ", "scene: Tab selects the carrot, the HUD follows (%s)" % main.hud.plant_label.text)
	await wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(play.selected_index == 2 and main.hud.plant_label.text == "植物 通常 にんじん [キウイ:3]", "scene: wheel down selects the kiwi (%s)" % main.hud.plant_label.text)
	await wheel(MOUSE_BUTTON_WHEEL_UP)
	await wheel(MOUSE_BUTTON_WHEEL_UP)
	check(play.selected_index == 0, "scene: wheel up twice goes back to the ordinary plant")
	await wheel(MOUSE_BUTTON_WHEEL_UP)
	check(play.selected_index == 2, "scene: wheel up from the first wraps to the last")
	send_key(KEY_TAB, true)
	await process_frame
	send_key(KEY_TAB, false)
	await process_frame
	check(play.selected_index == 0, "scene: Tab from the last wraps to the first")
	# Field: a mature 24x24 patch on open wasteland, the player in the middle.
	var block: Vector2i = find_wasteland_block(state, 44)
	check(block.x >= 0, "scene: found an open wasteland block at %s" % block)
	var field: Rect2i = Rect2i(block.x - 12, block.y - 12, 24, 24)
	var fill_tick: int = spread.ticks
	state.debug_fill_stage(field, WorldState.STAGE_MATURE)
	var greened: int = state.greened_count
	await teleport((Vector2(block) + Vector2(0.5, 0.5)) * TILE)
	# From here the game time is stepped by hand (like the earlier tickets' scene tests): the real drivers are switched
	# off until the pause check. Input, aiming, shots in flight and landings stay the real path.
	main.play_driver.process_mode = Node.PROCESS_MODE_DISABLED
	main.simulation.process_mode = Node.PROCESS_MODE_DISABLED
	# Candidate bookkeeping before anything is planted (for the carrot comparison below).
	var candidates: Array[int] = []
	var near_map: Dictionary = {}
	for y: int in range(field.position.y - 3, field.end.y + 3):
		for x: int in range(field.position.x - 3, field.end.x + 3):
			var index: int = state.index_of(x, y)
			if state.can_plant(index):
				var near: int = near_brute_local(state, x, y)
				if near > 0:
					candidates.append(index)
					near_map[index] = near
	check(candidates.size() > 80, "scene: the patch has %d spread candidates around it" % candidates.size())
	# Carrot: select, shoot into the field.
	play.select_index(1)
	var seeds_before: int = play.seeds
	var carrot_tile: Vector2i = Vector2i(block.x - 6, block.y - 4)
	await shoot_at(carrot_tile)
	var carrot: CultivatedPlant = play.cultivation.plants[0] if play.cultivation.plants.size() > 0 else null
	check(carrot != null and carrot.key == &"carrot" and absi(carrot.tile.x - carrot_tile.x) <= 1 and absi(carrot.tile.y - carrot_tile.y) <= 1, "scene: a left click with the carrot selected planted a carrot at %s" % [carrot.tile if carrot != null else Vector2i(-1, -1)])
	check(play.seeds == seeds_before - 3 and play.reserved_seeds == 0 and main.hud.seed_label.text == "  種 %d/40" % play.seeds, "scene: 3 seeds were spent (%d -> %d) and the HUD shows %s" % [seeds_before, play.seeds, main.hud.seed_label.text])
	check(state.greened_count == greened and state.counters_consistent(), "scene: planting changed no greening count (%d)" % state.greened_count)
	# Kiwi: wheel to it, shoot.
	await wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(play.selected_index == 2, "scene: wheel down selects the kiwi")
	var kiwi_tile: Vector2i = Vector2i(block.x + 5, block.y - 5)
	seeds_before = play.seeds
	await shoot_at(kiwi_tile)
	var kiwi: CultivatedPlant = play.cultivation.plants[1] if play.cultivation.plants.size() > 1 else null
	check(kiwi != null and kiwi.key == &"kiwi" and absi(kiwi.tile.x - kiwi_tile.x) <= 1 and absi(kiwi.tile.y - kiwi_tile.y) <= 1 and play.seeds == seeds_before - 3, "scene: the kiwi was planted too, 3 more seeds spent (%d)" % play.seeds)
	# A shot at ground outside the field plants nothing and spends nothing.
	seeds_before = play.seeds
	var count_before: int = play.cultivation.plants.size()
	await shoot_at(Vector2i(block.x + 20, block.y))
	check(play.cultivation.plants.size() == count_before and play.seeds == seeds_before and play.reserved_seeds == 0 and play.plant_failures >= 1, "scene: a kiwi shot at unplantable ground spends no seeds (%d) and places nothing" % play.seeds)
	# A shot onto an occupied tile.
	await shoot_at(carrot.tile)
	check(play.cultivation.plants.size() == count_before and play.seeds == seeds_before, "scene: a shot onto the carrot's own tile places nothing")
	# Not enough seeds: nothing is fired at all.
	play.seeds = 2
	var shots_before: int = main.projectile_view.shots.size()
	await aim_at((Vector2(block.x - 8, block.y + 6) + Vector2(0.5, 0.5)) * TILE)
	await click(MOUSE_BUTTON_LEFT)
	check(main.projectile_view.shots.size() == shots_before and play.seeds == 2 and play.reserved_seeds == 0, "scene: with 2 seeds a kiwi cannot be fired (no shot in the air, seeds unchanged)")
	play.seeds = 20
	# Occupied footprints: neither a seed landing nor spread touches them.
	var footprint: Array[int] = []
	for plant: CultivatedPlant in play.cultivation.plants:
		for y: int in range(plant.tile.y, plant.tile.y + 2):
			for x: int in range(plant.tile.x, plant.tile.x + 2):
				footprint.append(state.index_of(x, y))
	check(footprint.size() == 8 and footprint.all(func(index: int) -> bool: return state.occupant[index] != 0 and not state.can_plant(index)), "scene: the 8 footprint tiles are occupied and closed to planting")
	# Time to maturity (engine-level time steps through the real play state).
	var start_fill_ticks: int = spread.ticks
	for i: int in 159:
		play.advance(0.25, player.simulation_position)
	check(not carrot.mature and not kiwi.mature and spread.speed_scale.is_empty(), "scene: after 39.75 s both are young, no boost is installed yet")
	for i: int in 4:
		play.advance(0.25, player.simulation_position)
	check(carrot.mature and kiwi.mature and spread.speed_scale.size() == state.tile_count(), "scene: after 40+ s both are mature and the spread simulation holds the boost array")
	# Effect: compare the candidates inside / outside the carrot radius.
	var center: Vector2 = carrot.center_tiles()
	var inside: Array[int] = []
	var outside_slow: Array[int] = []
	for index: int in candidates:
		var p: Vector2 = Vector2(index % state.width + 0.5, index / state.width + 0.5)
		if (p - center).length_squared() <= 144.0:
			inside.append(index)
		elif int(near_map[index]) == 1:
			outside_slow.append(index)
	check(inside.size() > 40 and outside_slow.size() > 10, "scene: %d candidates inside the carrot radius, %d single-neighbour candidates outside" % [inside.size(), outside_slow.size()])
	var scale_wrong: int = 0
	for index: int in candidates:
		var p: Vector2 = Vector2(index % state.width + 0.5, index / state.width + 0.5)
		var want: int = 2000 if (p - center).length_squared() <= 144.0 else 1000
		if spread.scale_for(index) != want:
			scale_wrong += 1
	check(scale_wrong == 0, "scene: the real SpreadSim holds multiplier 2000 inside the radius and 1000 outside for all candidates")
	var spread_start: int = spread.ticks
	for i: int in 4:
		main.simulation.clock.advance(0.25)
	var queue_len: int = spread.queue_size()
	var wait_bound: int = spread.visit_interval_bound(queue_len)
	info["scene_spread_queue"] = queue_len
	info["scene_visit_bound"] = wait_bound
	var target_tick: int = fill_tick + 1 + 5 + wait_bound + 2
	var guard: int = 0
	while spread.ticks < target_tick and guard < 400:
		main.simulation.clock.advance(0.25)
		guard += 1
	var inside_planted: int = 0
	for index: int in inside:
		inside_planted += 1 if state.stage[index] != WorldState.STAGE_EMPTY else 0
	var outside_planted: int = 0
	for index: int in outside_slow:
		outside_planted += 1 if state.stage[index] != WorldState.STAGE_EMPTY else 0
	var slow_window_open: bool = target_tick < fill_tick + 1 + 10
	check(inside_planted == inside.size(), "scene: by spread tick %d (%d ticks after the patch appeared) all %d candidates inside the carrot radius are seeds (visit wait bound %d)" % [spread.ticks, spread.ticks - fill_tick, inside.size(), wait_bound])
	check(slow_window_open and outside_planted == 0, "scene: at the same moment none of the %d single-neighbour candidates outside the radius is a seed yet (they need 10 ticks)" % outside_slow.size())
	info["scene_inside_planted"] = inside_planted
	info["scene_outside_planted"] = outside_planted
	check(state.counters_consistent(), "scene: counters consistent after the boosted spread")
	# Kiwi fruit: 20 s after maturity (the maturity step has passed already: 4 steps = 1 s of the 20 s were counted).
	check(play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT) == 0, "scene: no fruit yet right after maturity")
	for i: int in 80:
		play.advance(0.25, player.simulation_position)
	var fruit: Dictionary = first_heal(play)
	check(not fruit.is_empty(), "scene: the kiwi dropped a healing fruit ~20 s after maturity")
	var fruit_spot: Vector2 = Vector2(float(fruit["x"]), float(fruit["y"]))
	check(play.hp == 10 and fruit_spot.distance_to(player.simulation_position) > 12.0, "scene: HP full and the player is away from the fruit")
	# Pause: nothing of the above moves (the real drivers run again).
	main.play_driver.process_mode = Node.PROCESS_MODE_INHERIT
	main.simulation.process_mode = Node.PROCESS_MODE_INHERIT
	await wait_frames(2)
	var snapshot: Array = [carrot.age, kiwi.age, kiwi.timer, kiwi.drops, play.elapsed, spread.ticks, main.simulation.clock.elapsed, play.pickups.to_dict(), play.hp, play.production_time]
	send_key(KEY_ESCAPE, true)
	await process_frame
	send_key(KEY_ESCAPE, false)
	await process_frame
	check(main.get_tree().paused, "scene: Esc pauses")
	var selection_before: int = play.selected_index
	send_key(KEY_TAB, true)
	await process_frame
	send_key(KEY_TAB, false)
	await wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await wait_frames(90)
	var after: Array = [carrot.age, kiwi.age, kiwi.timer, kiwi.drops, play.elapsed, spread.ticks, main.simulation.clock.elapsed, play.pickups.to_dict(), play.hp, play.production_time]
	check(snapshot == after, "scene: 90 frames of pause change neither plant growth, fruit timer and age, game time, spread, nor HP")
	check(play.selected_index == selection_before, "scene: Tab and the wheel do not change the selection while paused")
	send_key(KEY_ESCAPE, true)
	await process_frame
	send_key(KEY_ESCAPE, false)
	await wait_frames(3)
	check(not main.get_tree().paused and play.elapsed > float(snapshot[4]) and play.elapsed - float(snapshot[4]) < 0.2, "scene: after resuming only the stepped frames of time were added (%.3f s)" % (play.elapsed - float(snapshot[4])))
	# Damage, walk onto the fruit, HP comes back (+2), the fruit is gone.
	play.damage_player(5)
	await wait_frames(1)
	check(main.hud.hp_label.text == "HP 5/10", "scene: after 5 damage the HUD shows %s" % main.hud.hp_label.text)
	fruit = first_heal(play)
	fruit_spot = Vector2(float(fruit["x"]), float(fruit["y"]))
	var fruits_before: int = play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT)
	await teleport(fruit_spot)
	await wait_frames(2)
	check(play.hp == 7 and play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT) == fruits_before - 1 and main.hud.hp_label.text == "HP 7/10", "scene: picking the fruit up healed 2 HP (5 -> %d) and used up one fruit; HUD %s" % [play.hp, main.hud.hp_label.text])
	# Full HP: the next fruit stays on the ground even when the player stands on it.
	play.heal_player(10)
	await teleport(Vector2(player.simulation_position.x + 200.0, player.simulation_position.y))
	for i: int in 100:
		play.advance(0.25, player.simulation_position)
	var remaining: Dictionary = first_heal(play)
	check(not remaining.is_empty(), "scene: the kiwi produced another fruit")
	if not remaining.is_empty():
		await teleport(Vector2(float(remaining["x"]), float(remaining["y"])))
		await wait_frames(5)
		check(play.hp == 10 and play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT) >= 1, "scene: at full HP the fruit under the player is left on the ground")
	# Seed source fruits still appear while kiwi fruits are around.
	var source_fruits: int = 0
	for item: Dictionary in play.pickups.items:
		if int(item["owner"]) > 0 and int(item["owner"]) < GroundPickups.PLANT_OWNER_BASE:
			source_fruits += 1
	check(source_fruits >= 1 or play.pickups.count_owned(1) >= 1, "scene: the seed source's fruits exist next to the kiwi fruits (%d)" % source_fruits)
	main.queue_free()
	await process_frame

## Mature tiles within 2 tiles (Euclidean, dx^2 + dy^2 <= 4) of (x, y), excluding the tile itself, counted brute force.
func near_brute_local(state: WorldState, x: int, y: int) -> int:
	var total: int = 0
	for dy: int in range(-2, 3):
		for dx: int in range(-2, 3):
			if dx * dx + dy * dy <= 4 and (dx != 0 or dy != 0):
				var ox: int = x + dx
				var oy: int = y + dy
				if state.in_bounds(ox, oy) and state.stage[state.index_of(ox, oy)] == WorldState.STAGE_MATURE:
					total += 1
	return total
