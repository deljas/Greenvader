class_name PlayState
extends RefCounted
## Player resources (seeds, water), landing effects, water refill, seed sources and ground pickups.
## Display-free; time only moves through advance(), which the pausable SimulationDriver-side node calls
## with the physics delta. A paused tree therefore freezes everything here and nothing is banked.

signal seeds_changed(count: int)
signal water_changed(value: float)
signal hp_changed(value: int)
signal selection_changed(index: int)

var world: WorldState
var tuning: PlayTuning
var sim_tuning: SimTuning
var tile_px: int = 4

var seeds: int = 0
var water: float = 0.0
## Number of seed landings so far; picks the member of the fixed random sequence for the next landing.
var landing_counter: int = 0
var elapsed: float = 0.0
var pickups: GroundPickups
var sources: Array[SeedSource] = []
## Seed fruit production of mature plants around the player (P1-03).
var producer: PlantProducer
## Game time counted toward production ticks (like SimClock: ticks come from the total, not from the frame rate).
var production_time: float = 0.0
var production_ticks: int = 0
## Observability: tiles planted by the latest seed landing, tiles wetted by the latest water landing.
var last_scatter: PackedInt32Array = PackedInt32Array()
var last_wet_count: int = 0
var refilling: bool = false
var waterside_by_terrain: PackedByteArray = PackedByteArray()

## Hit points of the player (P1-05). Damage itself is P2; damage_player() is the entry for it, tests and the debug tools.
var hp: int = 10
var hp_max: int = 10
## Cultivated plants (carrot, kiwi) and the plant kinds the player can choose between (the region's plant list in
## its order; index 0 is the ordinary plant that is planted by seed scatter).
var cultivation: Cultivation
var selectable: Array[PlantDef] = []
var selected_index: int = 0
## Seeds held back for cultivated plant shots that are in flight (spent only when the plant is really placed).
var reserved_seeds: int = 0
var inflight: Dictionary = {}
## Observability: result of the latest cultivated landing (placed plant or null) and counts.
var last_plant: CultivatedPlant
var plant_landings: int = 0
var plant_failures: int = 0

func _init(world_state: WorldState, play_tuning: PlayTuning, simulation_tuning: SimTuning, tile_size: int, source_pixel_positions: Array[Vector2], plant_defs: Array[PlantDef] = []) -> void:
	world = world_state
	tuning = play_tuning
	sim_tuning = simulation_tuning
	tile_px = tile_size
	seeds = clampi(tuning.seed_start, 0, tuning.seed_max)
	water = clampf(tuning.water_start, 0.0, tuning.water_max)
	for index: int in source_pixel_positions.size():
		sources.append(SeedSource.new(index + 1, source_pixel_positions[index]))
	pickups = _new_pickups()
	producer = PlantProducer.new(world, tuning, tile_px)
	hp_max = maxi(tuning.hp_max, 1)
	hp = clampi(tuning.hp_start, 0, hp_max)
	selectable = plant_defs.duplicate()
	if selectable.is_empty() or selectable[0].is_cultivated():
		var normal: PlantDef = PlantDef.new()
		normal.id = 1
		normal.key = &"normal"
		normal.display_name = "通常"
		selectable.insert(0, normal)
	cultivation = Cultivation.new(world, tuning, tile_px, selectable)
	waterside_by_terrain.resize(world.terrain_defs.size())
	for def: TerrainDef in world.terrain_defs:
		waterside_by_terrain[def.id] = 1 if def.is_waterside else 0

## Pickup container with the plant limit that keeps the seed sources' slots free:
## plants may use at most min(plant_fruit_cap, total - sources * source_fruit_cap) of the region-wide total.
func _new_pickups() -> GroundPickups:
	var reserved: int = sources.size() * tuning.source_fruit_cap
	var plant_limit: int = clampi(mini(tuning.plant_fruit_cap, tuning.pickup_total_cap - reserved), 0, tuning.pickup_total_cap)
	return GroundPickups.new(tuning.pickup_total_cap, tuning.pickup_lifetime_seconds, plant_limit, tuning.plant_fruit_lifetime_seconds, tuning.heal_fruit_total_cap, tuning.heal_fruit_lifetime_seconds)

# ---- resources -----------------------------------------------------------------------------

## Seeds that can still be spent (the ones held back for cultivated shots in flight are not available).
func available_seeds() -> int:
	return seeds - reserved_seeds

func can_fire_seed() -> bool:
	return available_seeds() >= 1

func can_fire_water() -> bool:
	return water + 1.0e-6 >= tuning.water_cost_per_shot

## Spends one seed. False (and nothing changes) when none is left.
func spend_seed() -> bool:
	if available_seeds() < 1:
		return false
	seeds -= 1
	seeds_changed.emit(seeds)
	return true

## Spends one water shot worth of gauge. False (and nothing changes) when the gauge is too low.
func spend_water() -> bool:
	if not can_fire_water():
		return false
	water = maxf(water - tuning.water_cost_per_shot, 0.0)
	water_changed.emit(water)
	return true

## Adds seeds up to the cap; returns how many were actually added.
func add_seeds(amount: int) -> int:
	var added: int = clampi(amount, 0, tuning.seed_max - seeds)
	if added > 0:
		seeds += added
		seeds_changed.emit(seeds)
	return added

func add_water(amount: float) -> float:
	var added: float = clampf(amount, 0.0, tuning.water_max - water)
	if added > 0.0:
		water += added
		water_changed.emit(water)
	return added

# ---- HP ---------------------------------------------------------------------------------------------------

## Takes `amount` HP away (never below 0). Returns the HP actually lost.
func damage_player(amount: int) -> int:
	var lost: int = clampi(amount, 0, hp)
	if lost > 0:
		hp -= lost
		hp_changed.emit(hp)
	return lost

## Restores `amount` HP (never above the maximum). Returns the HP actually gained.
func heal_player(amount: int) -> int:
	var gained: int = clampi(amount, 0, hp_max - hp)
	if gained > 0:
		hp += gained
		hp_changed.emit(hp)
	return gained

# ---- plant selection and cultivated shots ----------------------------------------------------------------

func selected_def() -> PlantDef:
	return selectable[selected_index]

## Moves the selection by `step` (wraps around). Returns the new index.
func cycle_selection(step: int) -> int:
	selected_index = posmod(selected_index + step, selectable.size())
	selection_changed.emit(selected_index)
	return selected_index

func select_index(index: int) -> void:
	selected_index = clampi(index, 0, selectable.size() - 1)
	selection_changed.emit(selected_index)

func def_by_key(key: StringName) -> PlantDef:
	for def: PlantDef in selectable:
		if def.key == key:
			return def
	return null

## A cultivated shot of this kind may be fired: enough free seeds for the cost and the kind's count limit not reached
## (plants in flight count).
func can_fire_plant(def: PlantDef) -> bool:
	return def.is_cultivated() and available_seeds() >= def.seed_cost and cultivation.count(def.key) + int(inflight.get(def.key, 0)) < def.max_count

## Holds the seed cost back for a shot that was just fired.
func reserve_plant(def: PlantDef) -> void:
	reserved_seeds += def.seed_cost
	inflight[def.key] = int(inflight.get(def.key, 0)) + 1

## A shot ended without landing on the ground (expired, hit something): gives the held-back seeds back.
func cancel_plant(key: StringName) -> void:
	var def: PlantDef = def_by_key(key)
	if def == null or int(inflight.get(key, 0)) <= 0:
		return
	inflight[key] = int(inflight[key]) - 1
	reserved_seeds = maxi(reserved_seeds - def.seed_cost, 0)

## A cultivated shot landed at `point` (world px). The held-back seeds are spent when a plant is placed and given back
## (never spent) when no block fits. Returns the new plant or null.
func land_plant(key: StringName, point: Vector2) -> CultivatedPlant:
	var def: PlantDef = def_by_key(key)
	if def == null:
		return null
	cancel_plant(key)
	var plant: CultivatedPlant = cultivation.try_place(key, point)
	last_plant = plant
	if plant == null:
		plant_failures += 1
		return null
	seeds = maxi(seeds - def.seed_cost, 0)
	seeds_changed.emit(seeds)
	plant_landings += 1
	return plant

# ---- landing ----------------------------------------------------------------------------------

## A seed landed at `point` (world pixels). Returns the tiles that became seeds.
func land_seed(point: Vector2) -> PackedInt32Array:
	landing_counter += 1
	last_scatter = Landing.scatter_seeds(world, tile_px, point, tuning.seed_scatter_radius_px, tuning.seed_scatter_max, tuning.scatter_seed * 1000003 + landing_counter)
	return last_scatter

## A water shot landed at `point` (world pixels). Returns the number of tiles that got wetter.
func land_water(point: Vector2) -> int:
	last_wet_count = Landing.splash_water(world, tile_px, point, tuning.water_splash_radius_px, tuning.water_moisture_add, sim_tuning.moisture_max)
	return last_wet_count

# ---- time ---------------------------------------------------------------------------------------

## True when `position` (world pixels) is within the refill distance of a waterside or water tile.
func is_near_water(position: Vector2) -> bool:
	var tile_x: int = floori(position.x / tile_px)
	var tile_y: int = floori(position.y / tile_px)
	var reach: int = ceili(tuning.water_refill_distance_tiles)
	var limit: float = tuning.water_refill_distance_tiles * tuning.water_refill_distance_tiles
	for dy: int in range(-reach, reach + 1):
		for dx: int in range(-reach, reach + 1):
			if float(dx * dx + dy * dy) > limit:
				continue
			var x: int = tile_x + dx
			var y: int = tile_y + dy
			if world.in_bounds(x, y) and waterside_by_terrain[world.terrain[world.index_of(x, y)]] == 1:
				return true
	return false

## Advances game time by `delta` seconds (capped per call). `player_position` is in world pixels.
func advance(delta: float, player_position: Vector2) -> void:
	if delta <= 0.0:
		return
	delta = minf(delta, tuning.max_step_seconds)
	elapsed += delta
	refilling = is_near_water(player_position)
	if refilling:
		add_water(tuning.water_refill_per_second * delta)
	for source: SeedSource in sources:
		source.advance(delta, pickups, tuning)
	cultivation.advance(delta, pickups)
	production_time += delta
	while float(production_ticks + 1) * tuning.plant_production_interval_seconds <= production_time + 1.0e-9:
		production_ticks += 1
		producer.produce(pickups, player_position)
	pickups.advance(delta)
	pickups.collect(player_position, tuning.pickup_collect_radius_px, _accept_pickup)

func _accept_pickup(item: Dictionary) -> bool:
	if String(item["kind"]) == GroundPickups.KIND_HEAL_FRUIT:
		if hp >= hp_max:
			return false
		return heal_player(cultivation.heal_for_owner(int(item["owner"]))) > 0
	if String(item["kind"]) != GroundPickups.KIND_SEED_FRUIT:
		return false
	if seeds >= tuning.seed_max:
		return false
	return add_seeds(tuning.seed_fruit_seeds) > 0

# ---- save structure (the save feature itself is P5) -------------------------------------------

func to_dict() -> Dictionary:
	var source_list: Array = []
	for source: SeedSource in sources:
		source_list.append(source.to_dict())
	return {
		"version": 1,
		"seeds": seeds,
		"water": water,
		"landing_counter": landing_counter,
		"elapsed": elapsed,
		"pickups": pickups.to_dict(),
		"sources": source_list,
		"production": {"time": production_time, "ticks": production_ticks, "producer": producer.to_dict()},
		"hp": hp,
		"cultivated": cultivation.to_dict(),
		"selected": String(selected_def().key),
	}

## Restores the state. False (state left unchanged) when the data does not fit the current sources.
func load_dict(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != 1:
		return false
	var source_list: Array = data.get("sources", [])
	if source_list.size() != sources.size() or not data.has("pickups") or not data.has("seeds") or not data.has("water"):
		return false
	var cultivated_backup: Dictionary = cultivation.to_dict()
	if data.has("cultivated") and not cultivation.load_dict(data["cultivated"]):
		return false
	var restored: GroundPickups = _new_pickups()
	if not restored.load_dict(data["pickups"]):
		cultivation.load_dict(cultivated_backup)
		return false
	var backup: Array[Dictionary] = []
	for source: SeedSource in sources:
		backup.append(source.to_dict())
	for index: int in sources.size():
		if not sources[index].load_dict(source_list[index]):
			for i: int in sources.size():
				sources[i].load_dict(backup[i])
			cultivation.load_dict(cultivated_backup)
			return false
	seeds = clampi(int(data["seeds"]), 0, tuning.seed_max)
	water = clampf(float(data["water"]), 0.0, tuning.water_max)
	landing_counter = maxi(int(data.get("landing_counter", 0)), 0)
	elapsed = maxf(float(data.get("elapsed", 0.0)), 0.0)
	pickups = restored
	var production: Dictionary = data.get("production", {})
	production_time = maxf(float(production.get("time", 0.0)), 0.0)
	production_ticks = maxi(int(production.get("ticks", 0)), 0)
	producer.load_dict(production.get("producer", {}))
	hp = clampi(int(data.get("hp", hp_max)), 0, hp_max)
	var loaded_def: PlantDef = def_by_key(StringName(String(data.get("selected", "normal"))))
	selected_index = selectable.find(loaded_def) if loaded_def != null else 0
	reserved_seeds = 0
	inflight = {}
	seeds_changed.emit(seeds)
	water_changed.emit(water)
	hp_changed.emit(hp)
	selection_changed.emit(selected_index)
	return true
