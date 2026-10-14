class_name GrowthSim
extends RefCounted
## One growth tick over the active set only (P1-03). Display-free and clock-free: the caller decides when a
## tick happens (SimulationDriver connects SimClock.growth_ticked to tick()).
##
## Per tick and active tile:
##   growing tile (seed / sprout 1 / sprout 2): growth += round(base * moisture factor * fertility factor * sunlight factor)
##   then the stage follows the growth thresholds (sprout1 < sprout2 < mature); stages go through WorldState.set_stage.
##   moisture decays by moisture_decay_per_tick (after it was used for this tick's growth).
## A tile leaves the active set when it is neither growing nor wet. The rest of the map is never visited.

var world: WorldState
var tuning: SimTuning
## Sunlight factor hook (P4). Callable(index: int) -> float. Empty = always 1.0.
var sunlight_provider: Callable = Callable()
## Observability: tiles visited / stage changes made by the latest tick, and tick count.
var last_visited: int = 0
var last_stage_changes: int = 0
var ticks: int = 0
## Growth gained per tick for moisture 0..moisture_max with fertility 0 and sunlight 1 (lookup table).
var _moisture_gain: PackedFloat32Array = PackedFloat32Array()
var _fertility_factor: PackedFloat32Array = PackedFloat32Array()

func _init(world_state: WorldState, sim_tuning: SimTuning) -> void:
	world = world_state
	tuning = sim_tuning
	rebuild_tables()

## Call after changing the tuning at run time.
func rebuild_tables() -> void:
	_moisture_gain.resize(tuning.moisture_max + 1)
	for m: int in tuning.moisture_max + 1:
		_moisture_gain[m] = float(tuning.base_growth_per_tick) * moisture_factor(m)
	_fertility_factor.resize(256)
	for f: int in 256:
		_fertility_factor[f] = 1.0 + tuning.fertility_growth_bonus * float(mini(f, tuning.fertility_max)) / float(maxi(tuning.fertility_max, 1))

## Linear between moisture_growth_min (dry) and moisture_growth_max (full). Always > 0.
func moisture_factor(moisture: int) -> float:
	var t: float = clampf(float(moisture) / float(tuning.moisture_max), 0.0, 1.0)
	return maxf(lerpf(tuning.moisture_growth_min, tuning.moisture_growth_max, t), 0.001)

## Sunlight factor of a tile. Always 1.0 until P4 plugs in a provider.
func sunlight_factor(index: int) -> float:
	if sunlight_provider.is_valid():
		return maxf(float(sunlight_provider.call(index)), 0.001)
	return 1.0

## Growth amount a tile receives this tick (integer, at least 1 so growth never stops).
func gain_for(index: int) -> int:
	var gain: float = _moisture_gain[mini(world.moisture[index], tuning.moisture_max)] * _fertility_factor[world.fertility[index]] * sunlight_factor(index)
	return maxi(roundi(gain), 1)

## Growth amount at which a stage starts.
func stage_floor(stage: int) -> int:
	match stage:
		WorldState.STAGE_SPROUT1:
			return tuning.sprout1_growth
		WorldState.STAGE_SPROUT2:
			return tuning.sprout2_growth
		WorldState.STAGE_MATURE:
			return tuning.mature_growth
	return 0

func stage_for_growth(growth: int) -> int:
	if growth >= tuning.mature_growth:
		return WorldState.STAGE_MATURE
	if growth >= tuning.sprout2_growth:
		return WorldState.STAGE_SPROUT2
	if growth >= tuning.sprout1_growth:
		return WorldState.STAGE_SPROUT1
	return WorldState.STAGE_SEED

func tick() -> void:
	ticks += 1
	# Hot loop: the packed arrays are held in locals (member access per tile is much slower) and written back at
	# the end. PackedArrays are copy-on-write, so `stage` is deliberately NOT written here: stage changes go through
	# world.set_stage (which also keeps counters and dirty lists); the local `stage` copy is only read, and a tile is
	# visited once per tick, so a stale entry for an already processed tile is never read again.
	var tiles: PackedInt32Array = world.active_tiles
	var stage: PackedByteArray = world.stage
	var moisture: PackedByteArray = world.moisture
	var growth: PackedInt32Array = world.growth
	var fertility: PackedByteArray = world.fertility
	var flag: PackedByteArray = world.active_flag
	var count: int = tiles.size()
	var decay: int = tuning.moisture_decay_per_tick
	var fast: bool = not sunlight_provider.is_valid()
	var moisture_top: int = tuning.moisture_max
	var mature_growth: int = tuning.mature_growth
	var gain_table: PackedFloat32Array = _moisture_gain
	var fert_table: PackedFloat32Array = _fertility_factor
	# Per stage: growth at which the stage starts, and growth at which the next stage starts (index = stage).
	var floors: PackedInt32Array = PackedInt32Array([0, 0, tuning.sprout1_growth, tuning.sprout2_growth, mature_growth])
	var keep: int = 0
	var changes: int = 0
	for i: int in count:
		var index: int = tiles[i]
		var s: int = stage[index]
		if s >= 1 and s < 4:
			# A tile put into a later stage directly (debug, tests) starts from that stage's floor.
			var g: int = growth[index]
			if g < floors[s]:
				g = floors[s]
			if fast:
				var m0: int = moisture[index]
				if m0 > moisture_top:
					m0 = moisture_top
				var add: int = int(gain_table[m0] * fert_table[fertility[index]] + 0.5)
				g += add if add > 1 else 1
			else:
				g += gain_for(index)
			if g > mature_growth:
				g = mature_growth
			growth[index] = g
			if g >= floors[s + 1]:
				var wanted: int = stage_for_growth(g)
				world.set_stage(index, wanted)
				changes += 1
				s = wanted
		var m: int = moisture[index]
		if m > 0:
			m -= decay
			if m < 0:
				m = 0
			moisture[index] = m
		if (s >= 1 and s < 4) or m > 0:
			tiles[keep] = index
			keep += 1
		else:
			flag[index] = 0
	tiles.resize(keep)
	world.active_tiles = tiles
	world.moisture = moisture
	world.growth = growth
	world.active_flag = flag
	last_visited = count
	last_stage_changes = changes
