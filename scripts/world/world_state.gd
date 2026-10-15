class_name WorldState
extends RefCounted
## Runtime state of one region. Display-free. Per-tile values live in packed arrays
## (index = y * width + x). Shared definitions (TerrainDef) are referenced, never copied or mutated.

const STAGE_EMPTY: int = 0
const STAGE_SEED: int = 1
const STAGE_SPROUT1: int = 2
const STAGE_SPROUT2: int = 3
const STAGE_MATURE: int = 4
## A target tile counts as greened (greening rate numerator) from this stage on.
const GREENED_MIN_STAGE: int = STAGE_SPROUT1
const PLANT_NONE: int = 0
const PLANT_NORMAL: int = 1
## Sprout position candidates: the 2x2 centre pixels of the 4x4 tile. slot -> (1 + (slot & 1), 1 + (slot >> 1)).
const SLOT_COUNT: int = 4
## Side of the square tile chunks used for the per-chunk mature counts (fast "how many mature plants near here").
const CHUNK_TILES: int = 16

## Zone states (P2-01 holds them; the transitions are P2-04). Stable and complete zones are never entered by enemies.
const ZONE_UNCONQUERED: int = 0
const ZONE_CLEARING: int = 1
const ZONE_STABLE: int = 2
const ZONE_COMPLETE: int = 3

## Occupancy owner id bands (WorldState.occupy owner ids must be > 0 and never collide between users):
##   1 .. 999           reserved (tests, debug)
##   1000 .. 99999      cultivated plants: Cultivation.OWNER_BASE (1000) + uid (P1-05)
##   100000 .. 999999   helper plants of P3 (100000 + uid)
##   1000000 .. above   enemy nests: OWNER_BAND_NEST + nest id (P2-01)
const OWNER_BAND_CULTIVATED: int = 1000
const OWNER_BAND_HELPER: int = 100000
const OWNER_BAND_NEST: int = 1000000

var width: int = 0
var height: int = 0
var sprout_seed: int = 0
## Shared read-only definitions indexed by terrain id.
var terrain_defs: Array[TerrainDef] = []

var terrain: PackedByteArray = PackedByteArray()
## 1 if the tile is in the greening-rate denominator (derived from terrain defs).
var target: PackedByteArray = PackedByteArray()
var plant_id: PackedByteArray = PackedByteArray()
var stage: PackedByteArray = PackedByteArray()
var growth: PackedInt32Array = PackedInt32Array()
var moisture: PackedByteArray = PackedByteArray()
var fertility: PackedByteArray = PackedByteArray()
var sprout_slot: PackedByteArray = PackedByteArray()
## Occupancy container for 2x2 / 4x4 plants (P1-05, P3): owner id per tile, 0 = free.
var occupant: PackedInt32Array = PackedInt32Array()
var occupancy_owners: Dictionary = {}

## Integer greening counters (never floating point).
var target_count: int = 0
var greened_count: int = 0

## Tiles whose pixels must be redrawn. dirty_flag dedupes dirty_tiles.
var dirty_tiles: PackedInt32Array = PackedInt32Array()
var dirty_flag: PackedByteArray = PackedByteArray()

## Active set (P1-03): the only tiles the growth tick visits = growing tiles (seed, sprout 1, sprout 2) and tiles with
## moisture > 0. active_flag dedupes active_tiles. Derived data: rebuilt from stage and moisture by rebuild_derived().
var active_tiles: PackedInt32Array = PackedInt32Array()
var active_flag: PackedByteArray = PackedByteArray()
## Growth tick counter (written by GrowthSim) and, per active tile, the growth tick at which it was last processed
## (P1-04: the growth tick may visit only part of the active set per tick; the elapsed ticks are applied in one go).
var growth_tick: int = 0
var last_growth_tick: PackedInt32Array = PackedInt32Array()
## 1 = this seed / sprout was planted by natural spread (grows faster, see SimTuning.natural_growth_multiplier).
var natural: PackedByteArray = PackedByteArray()
## Optional observer Callable(index: int, old_stage: int, new_stage: int), called by set_stage when a tile turns
## mature / stops being mature / becomes empty, and by release() for freed tiles (old = new = STAGE_EMPTY).
## SpreadSim uses it to keep its candidate queue incremental. Empty = nobody listens.
var tile_listener: Callable = Callable()
## Mature tile counts per CHUNK_TILES x CHUNK_TILES chunk and in total (differential, checked against a recount in tests).
var chunks_x: int = 0
var chunks_y: int = 0
var mature_chunk_count: PackedInt32Array = PackedInt32Array()
var mature_count: int = 0
## 1 = this mature tile came ready-made with its terrain (TerrainDef.initial_stage) and does not produce seed fruits
## (P1-06). Cleared when the tile stops being mature, so a tile that regrows produces normally.
var fruitless: PackedByteArray = PackedByteArray()
## Mature tiles that DO produce seed fruits (mature and not fruitless), per chunk and in total. PlantProducer reads these.
var producing_chunk_count: PackedInt32Array = PackedInt32Array()
var producing_count: int = 0
## 1 per terrain id when the player can walk on it (from TerrainDef.walkable).
var walkable_by_terrain: PackedByteArray = PackedByteArray()

## Zones (P2-01): zone id of every tile, state per zone, and per zone the number of greening targets and of greened
## tiles (differential, kept by set_stage; checked against recounts in tests). Without a zone layer there is one
## unconquered zone 0 covering the whole map.
var zone_count: int = 1
var zone_of: PackedByteArray = PackedByteArray()
var zone_state: PackedByteArray = PackedByteArray()
var zone_target_count: PackedInt32Array = PackedInt32Array()
var zone_greened_count: PackedInt32Array = PackedInt32Array()
## Tiles holding a plant (any stage above empty) per CHUNK_TILES chunk and in total: a cheap "is there anything to
## eat near here" for enemies. Derived data (rebuilt by rebuild_derived()), kept by set_stage.
var plant_chunk_count: PackedInt32Array = PackedInt32Array()
var plant_count: int = 0

func _init(w: int, h: int, defs: Array[TerrainDef], seed_value: int) -> void:
	width = w
	height = h
	sprout_seed = seed_value
	terrain_defs = defs
	var n: int = w * h
	terrain.resize(n)
	target.resize(n)
	plant_id.resize(n)
	stage.resize(n)
	growth.resize(n)
	moisture.resize(n)
	fertility.resize(n)
	sprout_slot.resize(n)
	occupant.resize(n)
	dirty_flag.resize(n)
	active_flag.resize(n)
	last_growth_tick.resize(n)
	natural.resize(n)
	fruitless.resize(n)
	walkable_by_terrain.resize(defs.size())
	for def: TerrainDef in defs:
		walkable_by_terrain[def.id] = 1 if def.walkable else 0
	chunks_x = (w + CHUNK_TILES - 1) / CHUNK_TILES
	chunks_y = (h + CHUNK_TILES - 1) / CHUNK_TILES
	mature_chunk_count.resize(chunks_x * chunks_y)
	producing_chunk_count.resize(chunks_x * chunks_y)
	plant_chunk_count.resize(chunks_x * chunks_y)
	zone_of.resize(n)
	zone_state = PackedByteArray([ZONE_UNCONQUERED])
	zone_target_count = PackedInt32Array([0])
	zone_greened_count = PackedInt32Array([0])
	for index: int in n:
		sprout_slot[index] = slot_for(index, seed_value)

## Fixed per-tile pseudo random sprout position (a hash, not a sequential RNG: order independent).
static func slot_for(index: int, seed_value: int) -> int:
	var h: int = (index * 0x9E3779B1 + (seed_value & 0xFFFFFFFF) * 0x85EBCA6B) & 0xFFFFFFFF
	h ^= h >> 15
	h = (h * 0x2C1B3C6D) & 0xFFFFFFFF
	h ^= h >> 12
	h = (h * 0x297A2D39) & 0xFFFFFFFF
	h ^= h >> 15
	return h & 3

func tile_count() -> int:
	return width * height

func index_of(x: int, y: int) -> int:
	return y * width + x

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height

## True when the player can stand on tile (x, y). Outside the map is not walkable.
func is_walkable(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height and walkable_by_terrain[terrain[y * width + x]] == 1

## Applies terrain defs: target flags, initial plant/stage, counters. Call once after filling `terrain`.
func apply_terrain_defs() -> void:
	var is_target_by_id: PackedByteArray = PackedByteArray()
	is_target_by_id.resize(terrain_defs.size())
	for def: TerrainDef in terrain_defs:
		is_target_by_id[def.id] = 1 if def.is_target else 0
	target_count = 0
	greened_count = 0
	for index: int in tile_count():
		var def: TerrainDef = terrain_defs[terrain[index]]
		target[index] = is_target_by_id[def.id]
		if target[index] == 1:
			target_count += 1
			stage[index] = def.initial_stage
			plant_id[index] = def.initial_plant_id
			fruitless[index] = 1 if (def.initial_stage == STAGE_MATURE and not def.initial_produces_fruit) else 0
			if def.initial_stage >= GREENED_MIN_STAGE:
				greened_count += 1
		else:
			stage[index] = STAGE_EMPTY
			plant_id[index] = PLANT_NONE
			fruitless[index] = 0
	rebuild_derived()
	rebuild_zone_counts()

## Rebuilds the derived data (active set, mature chunk counts) from stage and moisture.
func rebuild_derived() -> void:
	active_tiles = PackedInt32Array()
	active_flag.fill(0)
	mature_chunk_count.fill(0)
	producing_chunk_count.fill(0)
	plant_chunk_count.fill(0)
	mature_count = 0
	producing_count = 0
	plant_count = 0
	for index: int in tile_count():
		var s: int = stage[index]
		if s != STAGE_EMPTY:
			plant_chunk_count[chunk_of(index)] += 1
			plant_count += 1
		if s == STAGE_MATURE:
			mature_chunk_count[chunk_of(index)] += 1
			mature_count += 1
			if fruitless[index] == 0:
				producing_chunk_count[chunk_of(index)] += 1
				producing_count += 1
		else:
			fruitless[index] = 0
		if (s >= STAGE_SEED and s < STAGE_MATURE) or moisture[index] > 0:
			active_flag[index] = 1
			last_growth_tick[index] = growth_tick
			active_tiles.append(index)

func chunk_of(index: int) -> int:
	return ((index / width) / CHUNK_TILES) * chunks_x + (index % width) / CHUNK_TILES

## Adds a tile to the active set (idempotent).
func activate(index: int) -> void:
	if active_flag[index] == 0:
		active_flag[index] = 1
		last_growth_tick[index] = growth_tick
		active_tiles.append(index)

## Sets the moisture of a target tile and keeps the active set right. Non-target tiles are refused.
func set_moisture(index: int, value: int) -> bool:
	if index < 0 or index >= tile_count() or target[index] == 0:
		return false
	moisture[index] = clampi(value, 0, 255)
	if value > 0:
		activate(index)
	return true

func terrain_def_at(index: int) -> TerrainDef:
	return terrain_defs[terrain[index]]

func is_target_tile(index: int) -> bool:
	return target[index] == 1

## Free of plants and occupants, on plantable terrain.
func can_plant(index: int) -> bool:
	return target[index] == 1 and terrain_defs[terrain[index]].plantable and stage[index] == STAGE_EMPTY and occupant[index] == 0

## Sets a growth stage directly (used by tick logic later; also the debug / test entry point).
## Refuses non-target tiles, so shots at non-targets can never raise the greening count.
## Maintains the greening counter and the dirty list. Returns false if refused.
func set_stage(index: int, new_stage: int) -> bool:
	if index < 0 or index >= tile_count() or new_stage < STAGE_EMPTY or new_stage > STAGE_MATURE:
		return false
	if target[index] == 0:
		return false
	var old_stage: int = stage[index]
	if old_stage == new_stage:
		return true
	if old_stage < GREENED_MIN_STAGE and new_stage >= GREENED_MIN_STAGE:
		greened_count += 1
		zone_greened_count[zone_of[index]] += 1
	elif old_stage >= GREENED_MIN_STAGE and new_stage < GREENED_MIN_STAGE:
		greened_count -= 1
		zone_greened_count[zone_of[index]] -= 1
	if (old_stage == STAGE_EMPTY) != (new_stage == STAGE_EMPTY):
		var plant_delta: int = 1 if old_stage == STAGE_EMPTY else -1
		plant_chunk_count[chunk_of(index)] += plant_delta
		plant_count += plant_delta
	var was_producing: int = 1 if (old_stage == STAGE_MATURE and fruitless[index] == 0) else 0
	if old_stage == STAGE_MATURE and new_stage != STAGE_MATURE:
		fruitless[index] = 0
	stage[index] = new_stage
	if (old_stage == STAGE_MATURE) != (new_stage == STAGE_MATURE):
		var delta: int = 1 if new_stage == STAGE_MATURE else -1
		mature_chunk_count[chunk_of(index)] += delta
		mature_count += delta
	var now_producing: int = 1 if (new_stage == STAGE_MATURE and fruitless[index] == 0) else 0
	if now_producing != was_producing:
		producing_chunk_count[chunk_of(index)] += now_producing - was_producing
		producing_count += now_producing - was_producing
	if new_stage >= STAGE_SEED and new_stage < STAGE_MATURE:
		activate(index)
	if new_stage == STAGE_EMPTY:
		plant_id[index] = PLANT_NONE
		growth[index] = 0
		natural[index] = 0
	elif plant_id[index] == PLANT_NONE:
		plant_id[index] = PLANT_NORMAL
	mark_dirty(index)
	if tile_listener.is_valid() and (new_stage == STAGE_MATURE or old_stage == STAGE_MATURE or new_stage == STAGE_EMPTY):
		tile_listener.call(index, old_stage, new_stage)
	# The edge of a mature tile depends on its four neighbours' maturity (diagonals are ignored).
	if (old_stage == STAGE_MATURE) != (new_stage == STAGE_MATURE):
		var x: int = index % width
		var y: int = index / width
		if x > 0:
			mark_dirty(index - 1)
		if x < width - 1:
			mark_dirty(index + 1)
		if y > 0:
			mark_dirty(index - width)
		if y < height - 1:
			mark_dirty(index + width)
	return true

## Debug / test helper: sets a rectangle of tiles to one stage. Returns the number accepted.
func debug_fill_stage(rect: Rect2i, new_stage: int) -> int:
	var accepted: int = 0
	for y: int in range(maxi(rect.position.y, 0), mini(rect.end.y, height)):
		for x: int in range(maxi(rect.position.x, 0), mini(rect.end.x, width)):
			if set_stage(index_of(x, y), new_stage):
				accepted += 1
	return accepted

func mark_dirty(index: int) -> void:
	if dirty_flag[index] == 0:
		dirty_flag[index] = 1
		dirty_tiles.append(index)

func mark_all_dirty() -> void:
	for index: int in tile_count():
		mark_dirty(index)

## Hands the dirty tile list (the oldest `limit` entries, all when limit < 0) to the renderer and removes them from it.
func take_dirty(limit: int = -1) -> PackedInt32Array:
	var result: PackedInt32Array = dirty_tiles
	if limit >= 0 and result.size() > limit:
		result = dirty_tiles.slice(0, limit)
		dirty_tiles = dirty_tiles.slice(limit)
	else:
		dirty_tiles = PackedInt32Array()
	for index: int in result:
		dirty_flag[index] = 0
	return result

func clear_dirty() -> void:
	take_dirty()

# ---- Greening rate (integers only) -------------------------------------------------------

## Full recount for cross-checking the differential counters.
func recount_targets() -> int:
	var total: int = 0
	for index: int in tile_count():
		total += target[index]
	return total

func recount_greened() -> int:
	var total: int = 0
	for index: int in tile_count():
		if target[index] == 1 and stage[index] >= GREENED_MIN_STAGE:
			total += 1
	return total

func recount_mature() -> int:
	var total: int = 0
	for index: int in tile_count():
		if stage[index] == STAGE_MATURE:
			total += 1
	return total

func recount_plants() -> int:
	var total: int = 0
	for index: int in tile_count():
		if stage[index] != STAGE_EMPTY:
			total += 1
	return total

func recount_plant_chunks() -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	result.resize(chunks_x * chunks_y)
	for index: int in tile_count():
		if stage[index] != STAGE_EMPTY:
			result[chunk_of(index)] += 1
	return result

func counters_consistent() -> bool:
	return recount_targets() == target_count and recount_greened() == greened_count and recount_mature() == mature_count and recount_plants() == plant_count and recount_zone_targets() == zone_target_count and recount_zone_greened() == zone_greened_count

# ---- Zones (P2-01: container and counters; transitions are P2-04) -------------------------------

## Installs the zone layer: `ids` holds the zone id of every tile, `states` the initial state per zone. False when the
## data does not fit (size, ids out of range). Counters are rebuilt.
func set_zones(ids: PackedByteArray, states: PackedByteArray) -> bool:
	if ids.size() != tile_count() or states.is_empty():
		return false
	for id: int in ids:
		if id >= states.size():
			return false
	zone_of = ids
	zone_count = states.size()
	zone_state = states.duplicate()
	rebuild_zone_counts()
	return true

## Rebuilds the per-zone target and greened counters from the tile data.
func rebuild_zone_counts() -> void:
	zone_target_count = recount_zone_targets()
	zone_greened_count = recount_zone_greened()

func recount_zone_targets() -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	result.resize(zone_count)
	for index: int in tile_count():
		if target[index] == 1:
			result[zone_of[index]] += 1
	return result

func recount_zone_greened() -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	result.resize(zone_count)
	for index: int in tile_count():
		if target[index] == 1 and stage[index] >= GREENED_MIN_STAGE:
			result[zone_of[index]] += 1
	return result

func zone_at(index: int) -> int:
	return zone_of[index]

## Sets the state of a zone (the rules for when are P2-04). False for an unknown zone or state.
func set_zone_state(zone: int, state: int) -> bool:
	if zone < 0 or zone >= zone_count or state < ZONE_UNCONQUERED or state > ZONE_COMPLETE:
		return false
	zone_state[zone] = state
	return true

## Enemies may enter / harm a zone unless it is stable or complete (the hard "no re-invasion" rule).
func zone_open_to_enemies(zone: int) -> bool:
	return zone >= 0 and zone < zone_count and zone_state[zone] < ZONE_STABLE

## 100 % is decided by integer equality, never by a rounded ratio.
func is_fully_greened() -> bool:
	return target_count > 0 and greened_count == target_count

## Floor of the greening percentage; only 100 when is_fully_greened().
func greening_percent_floor() -> int:
	if target_count == 0:
		return 0
	return greened_count * 100 / target_count

# ---- Occupancy container (contents: P1-05 and P3) ---------------------------------------

## Reserves a rect of free plantable tiles for one big plant. Owner ids are > 0.
func occupy(rect: Rect2i, owner_id: int) -> bool:
	if owner_id <= 0 or occupancy_owners.has(owner_id) or rect.size.x <= 0 or rect.size.y <= 0:
		return false
	if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > width or rect.end.y > height:
		return false
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var index: int = index_of(x, y)
			if target[index] == 0 or occupant[index] != 0 or not terrain_defs[terrain[index]].plantable:
				return false
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			occupant[index_of(x, y)] = owner_id
	occupancy_owners[owner_id] = rect
	return true

func release(owner_id: int) -> bool:
	if not occupancy_owners.has(owner_id):
		return false
	var rect: Rect2i = occupancy_owners[owner_id]
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			occupant[index_of(x, y)] = 0
			if tile_listener.is_valid():
				tile_listener.call(index_of(x, y), STAGE_EMPTY, STAGE_EMPTY)
	occupancy_owners.erase(owner_id)
	return true

func owner_at(index: int) -> int:
	return occupant[index]

# ---- Save structure (the save feature itself is P5) --------------------------------------

## An empty array is stored as {"n": 0, "z": ""}: compressing / encoding zero bytes makes the engine report errors.
static func _pack_bytes(data: PackedByteArray) -> Dictionary:
	if data.is_empty():
		return {"n": 0, "z": ""}
	return {"n": data.size(), "z": Marshalls.raw_to_base64(data.compress(FileAccess.COMPRESSION_ZSTD))}

static func _unpack_bytes(entry: Dictionary) -> PackedByteArray:
	if int(entry["n"]) <= 0:
		return PackedByteArray()
	return Marshalls.base64_to_raw(String(entry["z"])).decompress(int(entry["n"]), FileAccess.COMPRESSION_ZSTD)

func to_dict() -> Dictionary:
	var owners: Dictionary = {}
	for owner_id: int in occupancy_owners:
		var rect: Rect2i = occupancy_owners[owner_id]
		owners[str(owner_id)] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	return {
		"version": 1,
		"width": width,
		"height": height,
		"sprout_seed": sprout_seed,
		"terrain": _pack_bytes(terrain),
		"plant_id": _pack_bytes(plant_id),
		"stage": _pack_bytes(stage),
		"growth": _pack_bytes(growth.to_byte_array()),
		"moisture": _pack_bytes(moisture),
		"fertility": _pack_bytes(fertility),
		"sprout_slot": _pack_bytes(sprout_slot),
		"occupant": _pack_bytes(occupant.to_byte_array()),
		"natural": _pack_bytes(natural),
		"fruitless": _pack_bytes(fruitless),
		"occupancy_owners": owners,
		"zones": {"count": zone_count, "of": _pack_bytes(zone_of), "state": Array(zone_state)},
	}

## Restores a state. Target flags and counters are re-derived from the shared defs and the restored
## stages. Returns null when the data does not fit.
static func from_dict(data: Dictionary, defs: Array[TerrainDef]) -> WorldState:
	if int(data.get("version", 0)) != 1:
		return null
	var w: int = int(data.get("width", 0))
	var h: int = int(data.get("height", 0))
	var n: int = w * h
	if w <= 0 or h <= 0:
		return null
	var state: WorldState = WorldState.new(w, h, defs, int(data.get("sprout_seed", 0)))
	state.terrain = _unpack_bytes(data["terrain"])
	state.plant_id = _unpack_bytes(data["plant_id"])
	state.stage = _unpack_bytes(data["stage"])
	state.growth = _unpack_bytes(data["growth"]).to_int32_array()
	state.moisture = _unpack_bytes(data["moisture"])
	state.fertility = _unpack_bytes(data["fertility"])
	state.sprout_slot = _unpack_bytes(data["sprout_slot"])
	state.occupant = _unpack_bytes(data["occupant"]).to_int32_array()
	if state.terrain.size() != n or state.stage.size() != n or state.growth.size() != n or state.occupant.size() != n or state.plant_id.size() != n or state.moisture.size() != n or state.fertility.size() != n or state.sprout_slot.size() != n:
		return null
	for index: int in n:
		if state.terrain[index] >= defs.size() or state.stage[index] > STAGE_MATURE:
			return null
	if data.has("natural"):
		var natural_loaded: PackedByteArray = _unpack_bytes(data["natural"])
		if natural_loaded.size() == n:
			state.natural = natural_loaded
	# Ready-made mature tiles of terrains that do not produce fruits (older saves have no list: derive it).
	var fruitless_loaded: PackedByteArray = _unpack_bytes(data["fruitless"]) if data.has("fruitless") else PackedByteArray()
	if fruitless_loaded.size() == n:
		state.fruitless = fruitless_loaded
	else:
		for index: int in n:
			var def: TerrainDef = defs[state.terrain[index]]
			state.fruitless[index] = 1 if (state.stage[index] == STAGE_MATURE and def.initial_stage == STAGE_MATURE and not def.initial_produces_fruit) else 0
	state.occupancy_owners = {}
	var owners: Dictionary = data.get("occupancy_owners", {})
	for key: String in owners:
		var r: Array = owners[key]
		state.occupancy_owners[int(key)] = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
	state.target_count = 0
	state.greened_count = 0
	for index: int in n:
		state.target[index] = 1 if defs[state.terrain[index]].is_target else 0
		if state.target[index] == 1:
			state.target_count += 1
			if state.stage[index] >= GREENED_MIN_STAGE:
				state.greened_count += 1
		elif state.stage[index] != STAGE_EMPTY:
			return null
	if data.has("zones"):
		var zone_data: Dictionary = data["zones"]
		var ids: PackedByteArray = _unpack_bytes(zone_data["of"])
		var states: PackedByteArray = PackedByteArray()
		for value: Variant in zone_data["state"]:
			states.append(int(value))
		if int(zone_data.get("count", 0)) != states.size() or not state.set_zones(ids, states):
			return null
		for value: int in states:
			if value > ZONE_COMPLETE:
				return null
	state.rebuild_derived()
	state.rebuild_zone_counts()
	return state
