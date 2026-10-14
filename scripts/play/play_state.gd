class_name PlayState
extends RefCounted
## Player resources (seeds, water), landing effects, water refill, seed sources and ground pickups.
## Display-free; time only moves through advance(), which the pausable SimulationDriver-side node calls
## with the physics delta. A paused tree therefore freezes everything here and nothing is banked.

signal seeds_changed(count: int)
signal water_changed(value: float)

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

func _init(world_state: WorldState, play_tuning: PlayTuning, simulation_tuning: SimTuning, tile_size: int, source_pixel_positions: Array[Vector2]) -> void:
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
	waterside_by_terrain.resize(world.terrain_defs.size())
	for def: TerrainDef in world.terrain_defs:
		waterside_by_terrain[def.id] = 1 if def.is_waterside else 0

## Pickup container with the plant limit that keeps the seed sources' slots free:
## plants may use at most min(plant_fruit_cap, total - sources * source_fruit_cap) of the region-wide total.
func _new_pickups() -> GroundPickups:
	var reserved: int = sources.size() * tuning.source_fruit_cap
	var plant_limit: int = clampi(mini(tuning.plant_fruit_cap, tuning.pickup_total_cap - reserved), 0, tuning.pickup_total_cap)
	return GroundPickups.new(tuning.pickup_total_cap, tuning.pickup_lifetime_seconds, plant_limit, tuning.plant_fruit_lifetime_seconds)

# ---- resources -----------------------------------------------------------------------------

func can_fire_seed() -> bool:
	return seeds >= 1

func can_fire_water() -> bool:
	return water + 1.0e-6 >= tuning.water_cost_per_shot

## Spends one seed. False (and nothing changes) when none is left.
func spend_seed() -> bool:
	if seeds < 1:
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
	production_time += delta
	while float(production_ticks + 1) * tuning.plant_production_interval_seconds <= production_time + 1.0e-9:
		production_ticks += 1
		producer.produce(pickups, player_position)
	pickups.advance(delta)
	pickups.collect(player_position, tuning.pickup_collect_radius_px, _accept_pickup)

func _accept_pickup(item: Dictionary) -> bool:
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
	}

## Restores the state. False (state left unchanged) when the data does not fit the current sources.
func load_dict(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != 1:
		return false
	var source_list: Array = data.get("sources", [])
	if source_list.size() != sources.size() or not data.has("pickups") or not data.has("seeds") or not data.has("water"):
		return false
	var restored: GroundPickups = _new_pickups()
	if not restored.load_dict(data["pickups"]):
		return false
	var backup: Array[Dictionary] = []
	for source: SeedSource in sources:
		backup.append(source.to_dict())
	for index: int in sources.size():
		if not sources[index].load_dict(source_list[index]):
			for i: int in sources.size():
				sources[i].load_dict(backup[i])
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
	seeds_changed.emit(seeds)
	water_changed.emit(water)
	return true
