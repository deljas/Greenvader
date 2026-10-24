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
## Start of the next sweep window inside world.active_tiles (only meaningful while the set exceeds the per-tick limit).
var cursor: int = 0
## Growth gained per tick for moisture 0..moisture_max with fertility 0 and sunlight 1 (lookup table).
var _moisture_gain: PackedFloat32Array = PackedFloat32Array()
var _fertility_factor: PackedFloat32Array = PackedFloat32Array()

func _init(world_state: WorldState, sim_tuning: SimTuning) -> void:
	world = world_state
	tuning = sim_tuning
	ticks = world_state.growth_tick
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

## Growth gained over `span` consecutive ticks for a tile that starts the span at moisture `m0` (decaying by the
## tuning's decay each tick, floor 0) with the combined factor `factor` (fertility * natural multiplier * sunlight).
## Each tick adds max(round(table[moisture] * factor), 1), exactly as `span` single ticks would.
func _gain_span(m0: int, span: int, factor: float) -> int:
	var decay: int = tuning.moisture_decay_per_tick
	var total: int = 0
	var m: int = mini(m0, tuning.moisture_max)
	for k: int in span:
		var add: int = int(_moisture_gain[m] * factor + 0.5)
		total += add if add > 1 else 1
		if m > 0:
			m = maxi(m - decay, 0)
		if m == 0:
			# Moisture 0 is a fixed point: the remaining ticks all add the dry amount.
			var rest: int = span - k - 1
			if rest > 0:
				var dry: int = int(_moisture_gain[0] * factor + 0.5)
				total += rest * (dry if dry > 1 else 1)
			break
	return total

func tick() -> void:
	ticks += 1
	world.growth_tick = ticks
	_process_window(tuning.max_growth_tiles_per_tick)

## Applies the pending elapsed ticks to the whole active set at once (no tick advance). After this every tile is
## exactly where an unsplit simulation would have it. Used by tests and before reading exact values.
func catch_up() -> void:
	var visited_before: int = last_visited
	var changes_before: int = last_stage_changes
	_process_window(0)
	last_visited = visited_before
	last_stage_changes = changes_before

## Largest number of growth ticks a tile can wait between two visits with the current active set.
func sweep_ticks() -> int:
	var limit: int = tuning.max_growth_tiles_per_tick
	var total: int = world.active_tiles.size()
	if limit <= 0 or total <= limit:
		return 1
	return (total + limit - 1) / limit

## Processes one window of the active set: all of it when it fits `limit` (0 = no limit), otherwise the next `limit`
## tiles of the sweep starting at `cursor`. Tiles keep their order; new activations queue at the end.
func _process_window(limit: int) -> void:
	# Hot loop: the packed arrays are held in locals (member access per tile is much slower) and written back at
	# the end. PackedArrays are copy-on-write, so `stage` is deliberately NOT written here: stage changes go through
	# world.set_stage (which also keeps counters and dirty lists); the local `stage` copy is only read, and a tile is
	# visited once per window, so a stale entry for an already processed tile is never read again.
	var tiles: PackedInt32Array = world.active_tiles
	var total: int = tiles.size()
	var start: int = 0
	var end: int = total
	if limit > 0 and total > limit:
		start = cursor if cursor < total else 0
		end = mini(start + limit, total)
	var stage: PackedByteArray = world.stage
	var moisture: PackedByteArray = world.moisture
	var growth: PackedInt32Array = world.growth
	var fertility: PackedByteArray = world.fertility
	var flag: PackedByteArray = world.active_flag
	var last: PackedInt32Array = world.last_growth_tick
	var natural: PackedByteArray = world.natural
	var decay: int = tuning.moisture_decay_per_tick
	var fast: bool = not sunlight_provider.is_valid()
	var moisture_top: int = tuning.moisture_max
	var mature_growth: int = tuning.mature_growth
	var natural_mult: float = tuning.natural_growth_multiplier
	var gain_table: PackedFloat32Array = _moisture_gain
	var fert_table: PackedFloat32Array = _fertility_factor
	var now: int = ticks
	# Per stage: growth at which the stage starts, and growth at which the next stage starts (index = stage).
	var floors: PackedInt32Array = PackedInt32Array([0, 0, tuning.sprout1_growth, tuning.sprout2_growth, mature_growth])
	# Detach the arrays this loop writes from the world (no copy-on-write copies); they are put back below. set_stage
	# only reads active_flag and the stage data, and the tile listener only records the tile. A sunlight provider may
	# read the world, so nothing is detached while one is installed.
	if fast:
		world.active_tiles = PackedInt32Array()
		world.growth = PackedInt32Array()
		world.last_growth_tick = PackedInt32Array()
		world.moisture = PackedByteArray()
	var keep: int = start
	var changes: int = 0
	for i: int in range(start, end):
		var index: int = tiles[i]
		var elapsed: int = now - last[index]
		if elapsed <= 0:
			tiles[keep] = index
			keep += 1
			continue
		last[index] = now
		var s: int = stage[index]
		var m0: int = moisture[index]
		if s >= 1 and s < 4:
			# A tile put into a later stage directly (debug, tests) starts from that stage's floor.
			var g: int = growth[index]
			if g < floors[s]:
				g = floors[s]
			var factor: float = fert_table[fertility[index]]
			if natural[index] != 0:
				factor *= natural_mult
			if not fast:
				factor *= maxf(float(sunlight_provider.call(index)), 0.001)
			if elapsed == 1:
				var add: int = int(gain_table[m0 if m0 < moisture_top else moisture_top] * factor + 0.5)
				g += add if add > 1 else 1
			else:
				g += _gain_span(m0, elapsed, factor)
			if g > mature_growth:
				g = mature_growth
			growth[index] = g
			if g >= floors[s + 1]:
				var wanted: int = stage_for_growth(g)
				world.set_stage(index, wanted, false)
				changes += 1
				s = wanted
		var m: int = m0
		if world.permanent_water and (s <= WorldState.STAGE_EMPTY or s >= WorldState.STAGE_MATURE):
			m = 0
			moisture[index] = 0
		elif m > 0:
			m -= decay * elapsed
			if m < 0:
				m = 0
			moisture[index] = m
		if (s >= 1 and s < 4) or m > 0:
			tiles[keep] = index
			keep += 1
		else:
			flag[index] = 0
	if end < total:
		var tail: PackedInt32Array = tiles.slice(end)
		tiles.resize(keep)
		tiles.append_array(tail)
	else:
		tiles.resize(keep)
	cursor = keep if limit > 0 and total > limit else 0
	if cursor >= tiles.size():
		cursor = 0
	world.active_tiles = tiles
	world.moisture = moisture
	world.growth = growth
	world.active_flag = flag
	world.last_growth_tick = last
	last_visited = end - start
	last_stage_changes = changes

# ---- Save structure ---------------------------------------------------------------------------------------

## Tick counter, sweep position and the processing order/lag of the active set (the rest of the state lives in
## WorldState). Restoring this and the world and then advancing gives exactly the same result as never saving.
func to_dict() -> Dictionary:
	var lag: PackedInt32Array = PackedInt32Array()
	lag.resize(world.active_tiles.size())
	for i: int in world.active_tiles.size():
		lag[i] = ticks - world.last_growth_tick[world.active_tiles[i]]
	return {
		"version": 1,
		"ticks": ticks,
		# External tile removal may shorten the set between ticks. End-of-set and
		# zero both mean "start the next sweep"; save their canonical representation.
		"cursor": cursor if cursor < world.active_tiles.size() else 0,
		"active": WorldState._pack_bytes(world.active_tiles.to_byte_array()),
		"lag": WorldState._pack_bytes(lag.to_byte_array()),
	}

## Restores onto a world that was rebuilt from its own save (WorldState.from_dict). False when the data does not fit.
func load_dict(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != 1:
		return false
	var saved_ticks: int = int(data.get("ticks", 0))
	var order: PackedInt32Array = WorldState._unpack_bytes(data["active"]).to_int32_array()
	var lag: PackedInt32Array = WorldState._unpack_bytes(data["lag"]).to_int32_array()
	if order.size() != lag.size() or order.size() != world.active_tiles.size():
		return false
	if saved_ticks < 0:
		return false
	var seen: Dictionary = {}
	for index: int in order:
		if index < 0 or index >= world.tile_count() or world.active_flag[index] == 0 or seen.has(index):
			return false
		seen[index] = true
	for elapsed: int in lag:
		if elapsed < 0 or elapsed > saved_ticks:
			return false
	ticks = saved_ticks
	world.growth_tick = saved_ticks
	world.active_tiles = order
	for i: int in order.size():
		world.last_growth_tick[order[i]] = saved_ticks - lag[i]
	cursor = clampi(int(data.get("cursor", 0)), 0, order.size())
	if world.permanent_water:
		# Migrate earlier PoC3 transient moisture only after validating its original
		# active order/lag. Filter inactive wet terrain without rebuilding growing lag.
		var kept: PackedInt32Array = PackedInt32Array()
		var next_cursor: int = 0
		for at: int in order.size():
			var index: int = order[at]
			if world.stage[index] > WorldState.STAGE_EMPTY and world.stage[index] < WorldState.STAGE_MATURE:
				if at < cursor:
					next_cursor += 1
				kept.append(index)
			else:
				world.active_flag[index] = 0
		for index: int in world.tile_count():
			world.moisture[index] = 100 if world.stage[index] > WorldState.STAGE_EMPTY and world.stage[index] < WorldState.STAGE_MATURE and world.moisture[index] > 0 else 0
		world.active_tiles = kept
		cursor = next_cursor if next_cursor < kept.size() else 0
	return true
