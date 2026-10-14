class_name SpreadSim
extends RefCounted
## Natural spread (P1-04): green creeps from mature tiles into empty plantable tiles near them.
## Display-free and clock-free: the caller runs tick() once per spread tick (SimulationDriver connects
## SimClock.spread_ticked to it).
##
## Data (all incremental, nothing walks the whole map after construction):
##   mature_near[tile]  how many mature tiles lie within spread_radius_tiles (Euclidean) of the tile
##   queue              FIFO of candidate tiles = empty plantable tiles with mature_near > 0
##   progress[tile]     spread progress of a queued candidate
## Events: WorldState.tile_listener reports tiles that turned mature / stopped being mature / became empty / were
## released. They are collected in `pending` and applied at most spread_mature_events_per_tick per tick (FIFO).
##
## One spread tick examines at most B = spread_candidates_per_tick queued candidates, taken from the head of the queue.
## An examined candidate gets progress for the ticks that passed since its previous visit (so the speed does not
## depend on how many candidates share the budget), then it either becomes a seed (progress >= threshold) or goes
## to the tail of the queue. A candidate that is no longer valid is dropped. Every candidate is therefore examined at
## least once every ceil(queue size / B) ticks: nobody waits forever and no randomness is involved.
##
## P2 hook: `allow_hook` (Callable(index: int) -> bool, empty = always allowed) decides whether spread may enter a
## tile (enemy territory, nests). A refused candidate keeps its place in the queue but gains no progress, so a hook
## that starts allowing it later takes effect by itself.

var world: WorldState
var tuning: SimTuning
var allow_hook: Callable = Callable()
var ticks: int = 0
## Observability: candidates examined / seeds planted / mature events applied by the latest tick.
var last_examined: int = 0
var last_planted: int = 0
var last_events: int = 0
var total_planted: int = 0

var mature_near: PackedByteArray = PackedByteArray()
var queued_flag: PackedByteArray = PackedByteArray()
var progress: PackedInt32Array = PackedInt32Array()
var last_visit: PackedInt32Array = PackedInt32Array()
var queue: PackedInt32Array = PackedInt32Array()
var head: int = 0
## Tiles whose mature state changed and is not yet reflected in mature_near. `counted_flag` = state that mature_near
## currently includes; pending_flag dedupes `pending`.
var pending: PackedInt32Array = PackedInt32Array()
var pending_head: int = 0
var pending_flag: PackedByteArray = PackedByteArray()
var counted_flag: PackedByteArray = PackedByteArray()
var _dx: PackedInt32Array = PackedInt32Array()
var _dy: PackedInt32Array = PackedInt32Array()
var _delta: PackedInt32Array = PackedInt32Array()
var _reach: int = 0
var _plantable_by_terrain: PackedByteArray = PackedByteArray()

## `sync` true: reads the world once (the only full pass) and applies every mature tile right away.
func _init(world_state: WorldState, sim_tuning: SimTuning, sync: bool = true) -> void:
	world = world_state
	tuning = sim_tuning
	var n: int = world.tile_count()
	mature_near.resize(n)
	queued_flag.resize(n)
	progress.resize(n)
	last_visit.resize(n)
	pending_flag.resize(n)
	counted_flag.resize(n)
	_plantable_by_terrain.resize(world.terrain_defs.size())
	for def: TerrainDef in world.terrain_defs:
		_plantable_by_terrain[def.id] = 1 if def.plantable else 0
	_build_offsets()
	world.tile_listener = _on_tile_changed
	if sync:
		for index: int in n:
			if world.stage[index] == WorldState.STAGE_MATURE:
				_enqueue_event(index)
		_apply_events(n + 1)

func _build_offsets() -> void:
	_dx.clear()
	_dy.clear()
	_delta.clear()
	_reach = ceili(tuning.spread_radius_tiles)
	var limit: float = tuning.spread_radius_tiles * tuning.spread_radius_tiles + 1.0e-6
	for dy: int in range(-_reach, _reach + 1):
		for dx: int in range(-_reach, _reach + 1):
			if (dx != 0 or dy != 0) and float(dx * dx + dy * dy) <= limit:
				_dx.append(dx)
				_dy.append(dy)
				_delta.append(dy * world.width + dx)

# ---- events ---------------------------------------------------------------------------------------------

func _on_tile_changed(index: int, old_stage: int, new_stage: int) -> void:
	if old_stage == WorldState.STAGE_MATURE or new_stage == WorldState.STAGE_MATURE:
		_enqueue_event(index)
	elif new_stage == WorldState.STAGE_EMPTY:
		# Became free (cleared or released): a candidate at once when a mature tile is in range.
		_try_enqueue(index)

func _enqueue_event(index: int) -> void:
	if pending_flag[index] == 0:
		pending_flag[index] = 1
		pending.append(index)

## Applies up to `limit` pending events in FIFO order. Returns how many.
func _apply_events(limit: int) -> int:
	var applied: int = 0
	var width: int = world.width
	var height: int = world.height
	var count: int = _dx.size()
	var size: int = pending.size()
	while pending_head < size and applied < limit:
		var index: int = pending[pending_head]
		pending_head += 1
		pending_flag[index] = 0
		applied += 1
		var is_mature: int = 1 if world.stage[index] == WorldState.STAGE_MATURE else 0
		if is_mature == counted_flag[index]:
			continue
		counted_flag[index] = is_mature
		var step: int = 1 if is_mature == 1 else -1
		var x: int = index % width
		var y: int = index / width
		var inside: bool = x >= _reach and y >= _reach and x < width - _reach and y < height - _reach
		for k: int in count:
			var other: int
			if inside:
				other = index + _delta[k]
			else:
				var ox: int = x + _dx[k]
				var oy: int = y + _dy[k]
				if ox < 0 or oy < 0 or ox >= width or oy >= height:
					continue
				other = oy * width + ox
			var near: int = mature_near[other] + step
			mature_near[other] = near
			if step == 1 and near == 1:
				_try_enqueue(other)
	if pending_head >= size:
		pending.clear()
		pending_head = 0
	return applied

func _try_enqueue(index: int) -> void:
	if queued_flag[index] == 0 and mature_near[index] > 0 and world.can_plant(index):
		queued_flag[index] = 1
		progress[index] = 0
		last_visit[index] = ticks
		queue.append(index)

# ---- tick -----------------------------------------------------------------------------------------------

func rate_for(near: int) -> int:
	return tuning.spread_progress_per_tick + tuning.spread_progress_per_extra_neighbor * (maxi(near, 1) - 1)

func tick() -> void:
	ticks += 1
	last_events = _apply_events(tuning.spread_mature_events_per_tick)
	var budget: int = mini(tuning.spread_candidates_per_tick, queue.size() - head)
	var examined: int = 0
	var planted: int = 0
	var threshold: int = tuning.spread_progress_threshold
	var base_rate: int = tuning.spread_progress_per_tick
	var extra_rate: int = tuning.spread_progress_per_extra_neighbor
	var hook_valid: bool = allow_hook.is_valid()
	# Hot loop: read-only arrays are held in locals; the arrays this class writes are detached from the members for
	# the loop (no copy-on-write copies) and put back afterwards. set_stage(SEED) does not call the tile listener,
	# so nothing re-enters this object meanwhile.
	var target: PackedByteArray = world.target
	var occupant: PackedInt32Array = world.occupant
	var terrain: PackedByteArray = world.terrain
	var stage: PackedByteArray = world.stage
	var plantable: PackedByteArray = _plantable_by_terrain
	var near_array: PackedByteArray = mature_near
	var line: PackedInt32Array = queue
	var values: PackedInt32Array = progress
	var visits: PackedInt32Array = last_visit
	var flags: PackedByteArray = queued_flag
	queue = PackedInt32Array()
	progress = PackedInt32Array()
	last_visit = PackedInt32Array()
	queued_flag = PackedByteArray()
	var position: int = head
	var now: int = ticks
	while examined < budget:
		var index: int = line[position]
		position += 1
		examined += 1
		var near: int = near_array[index]
		# Still a valid candidate? (can_plant inlined: target, plantable terrain, empty, unoccupied, a mature tile near)
		if near == 0 or target[index] == 0 or stage[index] != WorldState.STAGE_EMPTY or occupant[index] != 0 or plantable[terrain[index]] == 0:
			flags[index] = 0
			continue
		var elapsed: int = now - visits[index]
		visits[index] = now
		if hook_valid and not bool(allow_hook.call(index)):
			line.append(index)
			continue
		var value: int = values[index] + elapsed * (base_rate + extra_rate * (near - 1))
		if value >= threshold:
			flags[index] = 0
			values[index] = 0
			world.set_stage(index, WorldState.STAGE_SEED)
			world.natural[index] = 1
			planted += 1
		else:
			values[index] = value
			line.append(index)
	queue = line
	progress = values
	last_visit = visits
	queued_flag = flags
	head = position
	if head > 4096 and head * 2 > queue.size():
		queue = queue.slice(head)
		head = 0
	last_examined = examined
	last_planted = planted
	total_planted += planted

func queue_size() -> int:
	return queue.size() - head

func pending_size() -> int:
	return pending.size() - pending_head

# ---- bounds (settings-derived) ----------------------------------------------------------------------------

## Most spread ticks between two examinations of one candidate when the queue holds at most `q` tiles.
func visit_interval_bound(q: int) -> int:
	return (q + tuning.spread_candidates_per_tick - 1) / tuning.spread_candidates_per_tick

## Upper bound (spread ticks) from the moment a tile has a mature tile in range until it becomes a seed:
## applying the event + progress at the slowest rate (one mature neighbour) + the wait between visits.
func seed_delay_bound(q: int, events: int) -> int:
	var apply_wait: int = (events + tuning.spread_mature_events_per_tick - 1) / tuning.spread_mature_events_per_tick
	var rate: int = rate_for(1)
	var progress_ticks: int = (tuning.spread_progress_threshold + rate - 1) / rate
	return apply_wait + progress_ticks + visit_interval_bound(q)

## Upper bound (spread ticks) for one hop of the front: seed delay + the slowest natural growth to mature (dry,
## no fertility) + the growth sweep wait for `active` tiles.
func hop_bound(q: int, events: int, active: int) -> int:
	var per_growth_tick: float = float(tuning.base_growth_per_tick) * tuning.moisture_growth_min * tuning.natural_growth_multiplier
	var growth_ticks: int = ceili(float(tuning.mature_growth) / per_growth_tick)
	var limit: int = maxi(tuning.max_growth_tiles_per_tick, 1)
	growth_ticks += (active + limit - 1) / limit + 1
	var seconds: float = float(growth_ticks) * tuning.growth_tick_seconds
	return seed_delay_bound(q, events) + ceili(seconds / tuning.spread_tick_seconds) + 1

# ---- save structure ---------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var remaining: PackedInt32Array = queue.slice(head)
	var values: PackedInt32Array = PackedInt32Array()
	var visits: PackedInt32Array = PackedInt32Array()
	for index: int in remaining:
		values.append(progress[index])
		visits.append(last_visit[index])
	return {
		"version": 1,
		"ticks": ticks,
		"total_planted": total_planted,
		"queue": WorldState._pack_bytes(remaining.to_byte_array()),
		"progress": WorldState._pack_bytes(values.to_byte_array()),
		"visits": WorldState._pack_bytes(visits.to_byte_array()),
		"pending": WorldState._pack_bytes(pending.slice(pending_head).to_byte_array()),
		"counted": WorldState._pack_bytes(counted_flag),
	}

## Restores onto a world rebuilt from its own save. Create the object with sync = false first. False if invalid.
func load_dict(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != 1:
		return false
	var n: int = world.tile_count()
	var counted: PackedByteArray = WorldState._unpack_bytes(data["counted"])
	var remaining: PackedInt32Array = WorldState._unpack_bytes(data["queue"]).to_int32_array()
	var values: PackedInt32Array = WorldState._unpack_bytes(data["progress"]).to_int32_array()
	var visits: PackedInt32Array = WorldState._unpack_bytes(data["visits"]).to_int32_array()
	var waiting: PackedInt32Array = WorldState._unpack_bytes(data["pending"]).to_int32_array()
	if counted.size() != n or remaining.size() != values.size() or remaining.size() != visits.size():
		return false
	ticks = int(data["ticks"])
	total_planted = int(data.get("total_planted", 0))
	mature_near.fill(0)
	queued_flag.fill(0)
	pending_flag.fill(0)
	counted_flag = counted
	var width: int = world.width
	var height: int = world.height
	for index: int in n:
		if counted[index] == 1:
			var x: int = index % width
			var y: int = index / width
			for k: int in _dx.size():
				var ox: int = x + _dx[k]
				var oy: int = y + _dy[k]
				if ox >= 0 and oy >= 0 and ox < width and oy < height:
					mature_near[oy * width + ox] += 1
	queue = remaining
	head = 0
	for i: int in remaining.size():
		queued_flag[remaining[i]] = 1
		progress[remaining[i]] = values[i]
		last_visit[remaining[i]] = visits[i]
	pending = PackedInt32Array()
	pending_head = 0
	for index: int in waiting:
		_enqueue_event(index)
	return true
