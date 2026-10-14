class_name Cultivation
extends RefCounted
## Cultivated plants (P1-05: carrot, kiwi): placement on mature ground, growth from young to mature, the carrot's
## spread boost and the kiwi's healing fruits. Display-free; time only moves through advance() (game time), so a
## paused tree freezes everything and nothing is banked.
##
## A plant occupies a size x size block of tiles (WorldState.occupy). The tiles are mature ground before and stay mature:
## they count as greened already, so placing a plant never changes the greening counters.
## Placement tries the (up to) four blocks that contain the landing tile in a fixed order and takes the first valid one.

signal changed()

## Occupancy owner ids of cultivated plants are OWNER_BASE + uid (distinct from other users of WorldState.occupy).
const OWNER_BASE: int = 1000
const EPSILON: float = 1.0e-6

var world: WorldState
var tuning: PlayTuning
var tile_px: int = 4
var defs: Dictionary = {}
var plants: Array[CultivatedPlant] = []
var next_uid: int = 1
## Per-tile carrot multiplier in permille (empty until a carrot matured), handed to `boost_sink` whenever it changes.
var boost: PackedInt32Array = PackedInt32Array()
## Callable(scale: PackedInt32Array) -> void. Main connects SpreadSim.set_speed_scale here.
var boost_sink: Callable = Callable()
## Observability for tests.
var last_placed_uid: int = 0
var total_fruits_dropped: int = 0

func _init(world_state: WorldState, play_tuning: PlayTuning, tile_size: int, plant_defs: Array[PlantDef]) -> void:
	world = world_state
	tuning = play_tuning
	tile_px = tile_size
	for def: PlantDef in plant_defs:
		if def.is_cultivated():
			defs[def.key] = def

func def_for(key: StringName) -> PlantDef:
	return defs.get(key) as PlantDef

func count(key: StringName) -> int:
	var total: int = 0
	for plant: CultivatedPlant in plants:
		if plant.key == key:
			total += 1
	return total

func plant_by_uid(uid: int) -> CultivatedPlant:
	for plant: CultivatedPlant in plants:
		if plant.uid == uid:
			return plant
	return null

# ---- placement ----------------------------------------------------------------------------------------------

## True when every tile of the block is a plantable target tile, mature, and free.
func block_valid(origin: Vector2i, size: int) -> bool:
	if origin.x < 0 or origin.y < 0 or origin.x + size > world.width or origin.y + size > world.height:
		return false
	for y: int in range(origin.y, origin.y + size):
		for x: int in range(origin.x, origin.x + size):
			var index: int = world.index_of(x, y)
			if world.target[index] == 0 or not world.terrain_defs[world.terrain[index]].plantable:
				return false
			if world.stage[index] != WorldState.STAGE_MATURE or world.occupant[index] != 0:
				return false
	return true

## The blocks (top-left tiles) that contain the landing tile, in the order they are tried: the block whose centre is
## nearest to the landing point first, then the rest in the fixed order up-left, up-right, down-left, down-right.
func candidate_origins(size: int, point_px: Vector2) -> Array[Vector2i]:
	var tile: Vector2i = Vector2i(floori(point_px.x / tile_px), floori(point_px.y / tile_px))
	var fixed: Array[Vector2i] = []
	for oy: int in [-(size - 1), 0]:
		for ox: int in [-(size - 1), 0]:
			fixed.append(tile + Vector2i(ox, oy))
	var ordered: Array[Vector2i] = []
	var best: int = 0
	var best_distance: float = INF
	for i: int in fixed.size():
		var center: Vector2 = (Vector2(fixed[i]) + Vector2(size, size) * 0.5) * tile_px
		var distance: float = center.distance_squared_to(point_px)
		if distance < best_distance - 1.0e-9:
			best_distance = distance
			best = i
	ordered.append(fixed[best])
	for i: int in fixed.size():
		if i != best:
			ordered.append(fixed[i])
	return ordered

## Plants `key` at a landing point (world px). Returns the new plant, or null when no block fits / the count limit is
## reached / the kind is unknown. Nothing changes on failure.
func try_place(key: StringName, point_px: Vector2) -> CultivatedPlant:
	var def: PlantDef = def_for(key)
	if def == null or count(key) >= def.max_count:
		return null
	for origin: Vector2i in candidate_origins(def.footprint_tiles, point_px):
		if not block_valid(origin, def.footprint_tiles):
			continue
		var plant: CultivatedPlant = CultivatedPlant.new()
		plant.uid = next_uid
		plant.key = key
		plant.tile = origin
		plant.size = def.footprint_tiles
		if not world.occupy(plant.rect(), OWNER_BASE + plant.uid):
			continue
		next_uid += 1
		plants.append(plant)
		last_placed_uid = plant.uid
		changed.emit()
		return plant
	return null

# ---- time ---------------------------------------------------------------------------------------------------

## Advances all plants by `delta` game seconds. Healing fruits are dropped into `pickups`.
func advance(delta: float, pickups: GroundPickups) -> void:
	if delta <= 0.0:
		return
	var matured: bool = false
	var boost_dirty: bool = false
	for plant: CultivatedPlant in plants:
		var def: PlantDef = def_for(plant.key)
		if def == null:
			continue
		var remaining: float = delta
		if not plant.mature:
			var need: float = def.grow_seconds - plant.age
			if delta < need - EPSILON:
				plant.age += delta
				continue
			remaining = maxf(delta - need, 0.0)
			plant.age = def.grow_seconds
			plant.mature = true
			matured = true
			if def.effect == PlantDef.EFFECT_SPREAD_BOOST:
				_stamp(plant, def)
				boost_dirty = true
		if def.effect == PlantDef.EFFECT_HEAL_FRUIT:
			_advance_fruit(plant, def, remaining, pickups)
	if boost_dirty:
		_push_boost()
	if matured:
		changed.emit()

func _advance_fruit(plant: CultivatedPlant, def: PlantDef, delta: float, pickups: GroundPickups) -> void:
	var owner_id: int = GroundPickups.HEAL_OWNER_BASE + plant.uid
	if pickups.count_owned(owner_id) >= def.fruit_cap:
		plant.timer = 0.0
		return
	plant.timer += delta
	while plant.timer + EPSILON >= def.fruit_interval_seconds and pickups.count_owned(owner_id) < def.fruit_cap:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = tuning.scatter_seed * 1000003 + plant.uid * 7919 + plant.drops * 31 + 5011
		var angle: float = rng.randf() * TAU
		var radius: float = lerpf(def.fruit_drop_radius_min_px, def.fruit_drop_radius_max_px, rng.randf())
		var center: Vector2 = plant.center_tiles() * tile_px
		if not pickups.spawn(GroundPickups.KIND_HEAL_FRUIT, center + Vector2(cos(angle), sin(angle)) * radius, owner_id, def.fruit_lifetime_seconds):
			# The region-wide budget is full: keep the full timer and try again next time.
			plant.timer = def.fruit_interval_seconds
			return
		plant.drops += 1
		total_fruits_dropped += 1
		plant.timer = maxf(plant.timer - def.fruit_interval_seconds, 0.0)
	if pickups.count_owned(owner_id) >= def.fruit_cap:
		plant.timer = 0.0

## HP restored by the healing fruit with this owner id (the plant's definition, or the tuning's fallback).
func heal_for_owner(owner_id: int) -> int:
	var plant: CultivatedPlant = plant_by_uid(owner_id - GroundPickups.HEAL_OWNER_BASE)
	if plant != null:
		var def: PlantDef = def_for(plant.key)
		if def != null:
			return def.fruit_heal
	return tuning.heal_fruit_fallback_heal

# ---- carrot boost -------------------------------------------------------------------------------------------

func _permille(def: PlantDef) -> int:
	return maxi(roundi(def.effect_multiplier * 1000.0), 1000)

## Raises the boost of every tile within the carrot's radius to at least its multiplier. Overlaps do not add up:
## a tile gets the largest multiplier of the mature carrots covering it.
func _stamp(plant: CultivatedPlant, def: PlantDef) -> void:
	if boost.is_empty():
		boost.resize(world.tile_count())
		boost.fill(1000)
	var permille: int = _permille(def)
	var center: Vector2 = plant.center_tiles()
	var reach: int = ceili(def.effect_radius_tiles)
	var limit: float = def.effect_radius_tiles * def.effect_radius_tiles + 1.0e-6
	for y: int in range(maxi(floori(center.y) - reach - 1, 0), mini(floori(center.y) + reach + 2, world.height)):
		for x: int in range(maxi(floori(center.x) - reach - 1, 0), mini(floori(center.x) + reach + 2, world.width)):
			var dx: float = float(x) + 0.5 - center.x
			var dy: float = float(y) + 0.5 - center.y
			if dx * dx + dy * dy <= limit:
				var index: int = world.index_of(x, y)
				if boost[index] < permille:
					boost[index] = permille

func _push_boost() -> void:
	if boost_sink.is_valid():
		boost_sink.call(boost)

## Rebuilds the boost array from the mature carrots (after a load; later for removals).
func rebuild_boost() -> void:
	boost = PackedInt32Array()
	for plant: CultivatedPlant in plants:
		var def: PlantDef = def_for(plant.key)
		if plant.mature and def != null and def.effect == PlantDef.EFFECT_SPREAD_BOOST:
			_stamp(plant, def)
	_push_boost()

## Multiplier in permille in effect on a tile (1000 = none).
func boost_at(index: int) -> int:
	return boost[index] if not boost.is_empty() else 1000

## Saved footprint check: inside the map; every tile a plantable target, mature, and not occupied by anything else.
func _footprint_ok(rect: Rect2i, owner_id: int) -> bool:
	if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > world.width or rect.end.y > world.height:
		return false
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var index: int = world.index_of(x, y)
			if world.target[index] == 0 or not world.terrain_defs[world.terrain[index]].plantable:
				return false
			if world.stage[index] != WorldState.STAGE_MATURE:
				return false
			if world.occupant[index] != 0 and world.occupant[index] != owner_id:
				return false
	return true

# ---- save structure -----------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var list: Array = []
	for plant: CultivatedPlant in plants:
		list.append(plant.to_dict())
	return {"version": 1, "next_uid": next_uid, "plants": list}

## Restores the plant list. The occupied tiles are part of the world's own save (WorldState.occupancy_owners); when the
## world does not hold them yet they are occupied here. False (state unchanged) when the data does not fit the world.
func load_dict(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != 1:
		return false
	var loaded: Array[CultivatedPlant] = []
	var seen: Dictionary = {}
	for entry: Variant in data.get("plants", []):
		if not (entry is Dictionary):
			return false
		var source: Dictionary = entry
		var plant: CultivatedPlant = CultivatedPlant.new()
		plant.uid = int(source.get("uid", 0))
		plant.key = StringName(String(source.get("key", "")))
		plant.tile = Vector2i(int(source.get("x", -1)), int(source.get("y", -1)))
		plant.size = int(source.get("size", 2))
		plant.age = maxf(float(source.get("age", 0.0)), 0.0)
		plant.mature = bool(source.get("mature", false))
		plant.timer = maxf(float(source.get("timer", 0.0)), 0.0)
		plant.drops = maxi(int(source.get("drops", 0)), 0)
		var def: PlantDef = def_for(plant.key)
		if plant.uid <= 0 or seen.has(plant.uid) or def == null or plant.size != def.footprint_tiles:
			return false
		# Growth state must agree with itself: mature exactly when the age reached the growth time.
		var aged: bool = plant.age + EPSILON >= def.grow_seconds
		if plant.mature != aged or plant.age > def.grow_seconds + EPSILON:
			return false
		seen[plant.uid] = true
		loaded.append(plant)
	var backup: Array[CultivatedPlant] = plants.duplicate()
	for plant: CultivatedPlant in backup:
		world.release(OWNER_BASE + plant.uid)
	var taken: Array[int] = []
	var ok: bool = true
	for plant: CultivatedPlant in loaded:
		var owner_id: int = OWNER_BASE + plant.uid
		# The footprint must be inside the map, mature plantable target ground, and free or already this plant's own.
		ok = _footprint_ok(plant.rect(), owner_id)
		if not ok:
			break
		if world.occupancy_owners.has(owner_id):
			ok = Rect2i(world.occupancy_owners[owner_id]) == plant.rect()
		else:
			ok = world.occupy(plant.rect(), owner_id)
			if ok:
				taken.append(owner_id)
		if not ok:
			break
	if not ok:
		for owner_id: int in taken:
			world.release(owner_id)
		for plant: CultivatedPlant in backup:
			world.occupy(plant.rect(), OWNER_BASE + plant.uid)
		return false
	plants = loaded
	next_uid = maxi(int(data.get("next_uid", 1)), 1)
	for plant: CultivatedPlant in plants:
		next_uid = maxi(next_uid, plant.uid + 1)
	rebuild_boost()
	changed.emit()
	return true
