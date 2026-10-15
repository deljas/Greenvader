class_name FarSeedSim
extends RefCounted
## Far seed spreading (P2-05): guarantees that a stable zone reaches 100 % greening without any input, islands included.
## Display-free and clock-free: the caller runs tick() once per spread tick (SimulationDriver, after SpreadSim.tick()).
## It only works in zones that are stable or complete (WorldState.ZONE_STABLE and above); other zones are never touched.
## A seed is a natural seed (natural = 1) put with WorldState.set_stage, so it grows like any natural-spread seed (growth
## sweep G of P1-04 included) and the counters / dirty lists follow. Nests are respected by WorldState.can_plant (occupancy).
##
## (b) Fair sweep (the guarantee). A cursor walks the tile indices 0 .. n-1 in a circle. Every sweep period one step reads at
## most S = far_sweep_scan_per_step tiles from the cursor and puts a seed on every free plantable target of a stable zone
## it meets, up to K = far_sweep_seeds_per_step seeds. Tiles that are not free (or in a zone that is not stable) are skipped:
## they do NOT count against K, only against S (and one step never reads more than n tiles). No randomness. The cursor
## passes every tile once per lap, so every tile that is free when the cursor reaches it is seeded within one lap
## (lap_steps_bound()), whatever natural spread does.
##
## (a) Isolated components (quick help for islands and the far bank). When a zone becomes stable, its plantable targets are
## labelled ONCE into connected components (connection = spread radius, Euclidean), sliced over spread ticks (a BFS with a
## per-tick budget; the labels depend only on terrain and zone map). Every far_island_period_seconds a check round visits the
## components that are not yet satisfied; a component with no plant in it (stage above empty, any tile) gets one natural
## seed on its first free tile in BFS order (deterministic). A component that holds a plant is satisfied for good (stable zones
## lose no plants). Work per tick is bounded by the budgets in SimTuning, nothing walks the 262144 tiles in one frame.
##
## The completion bound (completion_bound_seconds) is derived from (b) alone and does not rely on natural spread or (a).

var world: WorldState
var tuning: SimTuning
var ticks: int = 0
## Observability.
var total_sweep_planted: int = 0
var total_island_planted: int = 0
var last_sweep_planted: int = 0
var last_sweep_scanned: int = 0
var laps: int = 0

# (b) sweep
var sweep_cursor: int = 0
var _sweep_period_ticks: int = 1
var _island_period_ticks: int = 1

# (a) labelling and check rounds
## 0 = zone not stable yet (nothing done), 1 = queued / being labelled, 2 = labelled.
var zone_enum: PackedByteArray = PackedByteArray()
## 1 = the zone was stable already when this object was created (ZoneDef initial state): the sweep (b) never works there.
var zone_initial: PackedByteArray = PackedByteArray()
## Tick count at which the zone was noticed to be stable (sweep delay is counted from it).
var zone_stable_tick: PackedInt32Array = PackedInt32Array()
var zone_queue: PackedInt32Array = PackedInt32Array()
var zone_queue_head: int = 0
var job_zone: int = -1
var job_scan: int = 0
var job_head: int = 0
var job_open: bool = false
## Component id (1-based, global) of every labelled tile; 0 = not labelled. Allocated by the first labelling job.
var label: PackedInt32Array = PackedInt32Array()
## Labelled tiles in BFS order; component c (0-based) occupies members[comp_start[c] .. comp_end[c]) once finished.
var members: PackedInt32Array = PackedInt32Array()
var comp_start: PackedInt32Array = PackedInt32Array()
var comp_end: PackedInt32Array = PackedInt32Array()
## 0 = not yet seen holding a plant, 1 = satisfied.
var comp_state: PackedByteArray = PackedByteArray()
var round_active: bool = false
var round_comp: int = 0
var round_pos: int = 0
var round_empty: int = -1

var _dx: PackedInt32Array = PackedInt32Array()
var _dy: PackedInt32Array = PackedInt32Array()
var _delta: PackedInt32Array = PackedInt32Array()
var _reach: int = 0
var _member_terrain: PackedByteArray = PackedByteArray()

func _init(world_state: WorldState, sim_tuning: SimTuning) -> void:
	world = world_state
	tuning = sim_tuning
	zone_enum.resize(world.zone_count)
	zone_initial.resize(world.zone_count)
	zone_stable_tick.resize(world.zone_count)
	for zone: int in world.zone_count:
		zone_initial[zone] = 1 if world.zone_state[zone] >= WorldState.ZONE_STABLE else 0
	_member_terrain.resize(world.terrain_defs.size())
	for def: TerrainDef in world.terrain_defs:
		_member_terrain[def.id] = 1 if (def.is_target and def.plantable) else 0
	_sweep_period_ticks = maxi(roundi(tuning.far_sweep_period_seconds / tuning.spread_tick_seconds), 1)
	_island_period_ticks = maxi(roundi(tuning.far_island_period_seconds / tuning.spread_tick_seconds), 1)
	_reach = ceili(tuning.spread_radius_tiles)
	var limit: float = tuning.spread_radius_tiles * tuning.spread_radius_tiles + 1.0e-6
	for dy: int in range(-_reach, _reach + 1):
		for dx: int in range(-_reach, _reach + 1):
			if (dx != 0 or dy != 0) and float(dx * dx + dy * dy) <= limit:
				_dx.append(dx)
				_dy.append(dy)
				_delta.append(dy * world.width + dx)

func sweep_period_ticks() -> int:
	return _sweep_period_ticks

func island_period_ticks() -> int:
	return _island_period_ticks

# ---- tick -----------------------------------------------------------------------------------------------

func tick() -> void:
	ticks += 1
	last_sweep_planted = 0
	last_sweep_scanned = 0
	if not tuning.far_seed_enabled:
		return
	_notice_stable_zones()
	_label_step()
	_check_step()
	if ticks % _sweep_period_ticks == 0:
		_sweep_step()

func _notice_stable_zones() -> void:
	for zone: int in mini(world.zone_count, zone_enum.size()):
		if zone_enum[zone] == 0 and world.zone_state[zone] >= WorldState.ZONE_STABLE:
			zone_enum[zone] = 1
			zone_stable_tick[zone] = ticks - 1
			zone_queue.append(zone)

func sweep_delay_ticks() -> int:
	return maxi(roundi(tuning.far_sweep_start_delay_seconds / tuning.spread_tick_seconds), 0)

func is_stable_zone(zone: int) -> bool:
	return zone >= 0 and zone < world.zone_count and world.zone_state[zone] >= WorldState.ZONE_STABLE

# ---- (b) sweep ------------------------------------------------------------------------------------------

func _sweep_step() -> void:
	var n: int = world.tile_count()
	var zone_ok: PackedByteArray = PackedByteArray()
	zone_ok.resize(world.zone_count)
	var any: bool = false
	var delay_ticks: int = sweep_delay_ticks()
	for zone: int in world.zone_count:
		if world.zone_state[zone] >= WorldState.ZONE_STABLE and zone_initial[zone] == 0 and zone_enum[zone] != 0 and ticks - zone_stable_tick[zone] >= delay_ticks:
			zone_ok[zone] = 1
			any = true
	if not any:
		return
	var max_seeds: int = maxi(tuning.far_sweep_seeds_per_step, 1)
	var max_scan: int = mini(maxi(tuning.far_sweep_scan_per_step, 1), n)
	var chosen: PackedInt32Array = PackedInt32Array()
	var scanned: int = 0
	var cursor: int = sweep_cursor
	var lapped: int = 0
	# Read-only scan with local copies; the writes (set_stage) happen afterwards, so nothing is copied on write.
	var stage: PackedByteArray = world.stage
	var occupant: PackedInt32Array = world.occupant
	var target: PackedByteArray = world.target
	var terrain: PackedByteArray = world.terrain
	var zone_of: PackedByteArray = world.zone_of
	var member: PackedByteArray = _member_terrain
	while scanned < max_scan and chosen.size() < max_seeds:
		var index: int = cursor
		cursor += 1
		if cursor == n:
			cursor = 0
			lapped += 1
		scanned += 1
		if stage[index] != 0 or occupant[index] != 0 or target[index] == 0 or member[terrain[index]] == 0 or zone_ok[zone_of[index]] == 0:
			continue
		chosen.append(index)
	stage = PackedByteArray()
	sweep_cursor = cursor
	laps += lapped
	for index: int in chosen:
		_plant(index)
	last_sweep_planted = chosen.size()
	last_sweep_scanned = scanned
	total_sweep_planted += chosen.size()

func _plant(index: int) -> bool:
	if not world.can_plant(index):
		return false
	if not world.set_stage(index, WorldState.STAGE_SEED):
		return false
	world.natural[index] = 1
	return true

# ---- (a) labelling --------------------------------------------------------------------------------------

func comp_count() -> int:
	return comp_start.size()

func finished_comp_count() -> int:
	return comp_end.size()

## True while a zone is queued or being labelled.
func labelling_busy() -> bool:
	return job_zone >= 0 or zone_queue_head < zone_queue.size()

func _label_step() -> void:
	var bfs_left: int = maxi(tuning.far_label_tiles_per_tick, 1)
	var scan_left: int = maxi(tuning.far_label_scan_per_tick, 1)
	var n: int = world.tile_count()
	while true:
		if job_zone < 0:
			if zone_queue_head >= zone_queue.size():
				zone_queue = PackedInt32Array()
				zone_queue_head = 0
				return
			job_zone = zone_queue[zone_queue_head]
			zone_queue_head += 1
			job_scan = 0
			job_open = false
			if label.size() != n:
				label.resize(n)
		if job_open:
			if bfs_left <= 0:
				return
			bfs_left -= _expand(bfs_left)
			if job_head < members.size():
				return
			job_open = false
			comp_end.append(members.size())
		else:
			if scan_left <= 0:
				return
			scan_left -= _scan_for_seed(scan_left)
			if not job_open and job_scan >= n:
				zone_enum[job_zone] = 2
				job_zone = -1

## Reads tiles from job_scan on until the first unlabelled plantable target of the job zone: it starts a component.
## Returns the number of tiles read.
func _scan_for_seed(budget: int) -> int:
	var n: int = world.tile_count()
	var from: int = job_scan
	var to: int = mini(from + budget, n)
	var terrain: PackedByteArray = world.terrain
	var zone_of: PackedByteArray = world.zone_of
	var member: PackedByteArray = _member_terrain
	var lab: PackedInt32Array = label
	var zone: int = job_zone
	var found: int = -1
	var index: int = from
	while index < to:
		if zone_of[index] == zone and member[terrain[index]] == 1 and lab[index] == 0:
			found = index
			break
		index += 1
	if found < 0:
		job_scan = to
		return to - from
	var id: int = comp_start.size() + 1
	lab = PackedInt32Array()
	label[found] = id
	comp_start.append(members.size())
	comp_state.append(0)
	members.append(found)
	job_head = members.size() - 1
	job_open = true
	job_scan = found + 1
	return found - from + 1

## Expands up to `limit` queued tiles of the open component. Returns how many were expanded.
func _expand(limit: int) -> int:
	var width: int = world.width
	var height: int = world.height
	var zone: int = job_zone
	var id: int = comp_start.size()
	var terrain: PackedByteArray = world.terrain
	var zone_of: PackedByteArray = world.zone_of
	var member: PackedByteArray = _member_terrain
	var lab: PackedInt32Array = label
	var list: PackedInt32Array = members
	label = PackedInt32Array()
	members = PackedInt32Array()
	var count: int = _dx.size()
	var head: int = job_head
	var done: int = 0
	while head < list.size() and done < limit:
		var index: int = list[head]
		head += 1
		done += 1
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
			if lab[other] == 0 and zone_of[other] == zone and member[terrain[other]] == 1:
				lab[other] = id
				list.append(other)
	label = lab
	members = list
	job_head = head
	return done

# ---- (a) check rounds -----------------------------------------------------------------------------------

func _check_step() -> void:
	if not round_active:
		if ticks % _island_period_ticks != 0 or comp_end.is_empty():
			return
		round_active = true
		round_comp = 0
		round_pos = 0
		round_empty = -1
	var reads: int = maxi(tuning.far_check_reads_per_tick, 1)
	while reads > 0:
		if round_comp >= comp_end.size():
			round_active = false
			return
		if comp_state[round_comp] == 1:
			round_comp += 1
			round_pos = 0
			round_empty = -1
			reads -= 1
			continue
		var start: int = comp_start[round_comp]
		var end: int = comp_end[round_comp]
		var pos: int = start + round_pos
		var green: bool = false
		while pos < end and reads > 0:
			var index: int = members[pos]
			pos += 1
			reads -= 1
			if world.stage[index] != WorldState.STAGE_EMPTY:
				green = true
				break
			if round_empty < 0 and world.occupant[index] == 0:
				round_empty = index
		if green:
			comp_state[round_comp] = 1
			round_comp += 1
			round_pos = 0
			round_empty = -1
			continue
		round_pos = pos - start
		if pos >= end:
			if round_empty >= 0:
				if world.stage[round_empty] != WorldState.STAGE_EMPTY:
					comp_state[round_comp] = 1
				elif _plant(round_empty):
					comp_state[round_comp] = 1
					total_island_planted += 1
			round_comp += 1
			round_pos = 0
			round_empty = -1

# ---- bounds (settings-derived) --------------------------------------------------------------------------

## Most sweep steps after which the cursor has read every tile once (a full lap), counting from the next step: each step ends
## after K seeds (at most E_free / K such steps, the seeds are distinct tiles inside one lap) or after S reads (at most
## n / S such steps), so ceil(E / K) + ceil(n / S) + 1 steps always cover n reads.
func lap_steps_bound(free_targets: int = -1) -> int:
	var free: int = swept_targets() if free_targets < 0 else free_targets
	var n: int = world.tile_count()
	var max_seeds: int = maxi(tuning.far_sweep_seeds_per_step, 1)
	var max_scan: int = mini(maxi(tuning.far_sweep_scan_per_step, 1), n)
	return (free + max_seeds - 1) / max_seeds + (n + max_scan - 1) / max_scan + 1

## Greening targets of the zones the sweep works in (not the zones that started stable).
func swept_targets() -> int:
	var total: int = 0
	for zone: int in world.zone_count:
		if zone_initial[zone] == 0:
			total += world.zone_target_count[zone]
	return total

## Growth ticks a natural seed needs at the slowest speed (dry ground, no fertility, no sunlight bonus) to reach sprout 1,
## the stage from which a target counts as greened.
func slowest_greened_ticks() -> int:
	var per_tick: int = maxi(floori(float(tuning.base_growth_per_tick) * tuning.moisture_growth_min * tuning.natural_growth_multiplier), 1)
	return (tuning.sprout1_growth + per_tick - 1) / per_tick

## Upper bound (game seconds) from the moment every zone is stable until every target is greened, with `free_targets` free
## plantable targets at that moment (default: all targets, which is valid for any start). Uses the sweep (b) alone: no natural
## spread, no component seeding. Terms: wait for the first step (one period) + lap_steps_bound steps + the slowest seed's growth
## to sprout 1 + the growth sweep wait for the largest possible active set (every tile) + one tick of margin.
func completion_bound_seconds(free_targets: int = -1) -> float:
	var period: float = float(_sweep_period_ticks) * tuning.spread_tick_seconds
	var sweep_seconds: float = float(lap_steps_bound(free_targets) + 1) * period
	var window: int = maxi(tuning.max_growth_tiles_per_tick, 1)
	var wait_ticks: int = (world.tile_count() + window - 1) / window + 1
	var growth_seconds: float = float(slowest_greened_ticks() + wait_ticks) * tuning.growth_tick_seconds
	# The sweep of a zone starts sweep_delay after it turned stable (+ one tick until it is noticed).
	var delay_seconds: float = float(sweep_delay_ticks() + 1) * tuning.spread_tick_seconds
	return delay_seconds + sweep_seconds + growth_seconds

## Largest number of graph hops (connection = spread radius) from the first tile of component `c` (the tile that gets its seed) to
## any tile of it, doubled: an upper bound of the hops from the seed tile whichever free tile is chosen. Analysis helper (a BFS over
## the component), not used by tick(). Needs the component to be finished.
func component_hops_bound(c: int) -> int:
	if c < 0 or c >= comp_end.size():
		return 0
	var width: int = world.width
	var height: int = world.height
	var id: int = c + 1
	var dist: Dictionary = {}
	var root: int = members[comp_start[c]]
	dist[root] = 0
	var queue: PackedInt32Array = PackedInt32Array([root])
	var head: int = 0
	var deepest: int = 0
	while head < queue.size():
		var index: int = queue[head]
		head += 1
		var x: int = index % width
		var y: int = index / width
		for k: int in _dx.size():
			var ox: int = x + _dx[k]
			var oy: int = y + _dy[k]
			if ox < 0 or oy < 0 or ox >= width or oy >= height:
				continue
			var other: int = oy * width + ox
			if label[other] == id and not dist.has(other):
				dist[other] = int(dist[index]) + 1
				deepest = maxi(deepest, int(dist[other]))
				queue.append(other)
	return 2 * deepest

## Upper bound (game seconds) from the moment a zone that started stable is stable (= game start) until every target of it is
## greened, using (a) + natural spread only (no sweep). `max_hops` = component_hops_bound of the zone's deepest component.
## `zone_targets` bounds the candidate queue, the pending events and the growth active set (default: all targets).
## Terms: labelling (scan n / scan budget + plantable targets / expand budget + 1 ticks) + two check periods and two rounds (a
## round that started before the component was finished misses it) + (max_hops + 1) hops of the spread front, each SpreadSim.hop_bound
## (seed delay + slowest natural growth to mature + sweeps). The stable multiplier is NOT used (1.0, conservative).
func initial_zone_bound_seconds(max_hops: int, zone_targets: int = -1) -> float:
	var m: int = world.target_count
	var q: int = m if zone_targets < 0 else zone_targets
	var n: int = world.tile_count()
	var scan: int = maxi(tuning.far_label_scan_per_tick, 1)
	var expand: int = maxi(tuning.far_label_tiles_per_tick, 1)
	var reads: int = maxi(tuning.far_check_reads_per_tick, 1)
	var label_ticks: int = (n + scan - 1) / scan + (m + expand - 1) / expand + 1
	var round_ticks: int = (2 * m + reads - 1) / reads + 1
	var check_ticks: int = 2 * (_island_period_ticks + round_ticks)
	# SpreadSim's constructor installs itself as the world's tile listener: put the owner of the listener back afterwards.
	var listener: Callable = world.tile_listener
	var probe: SpreadSim = SpreadSim.new(world, tuning, false)
	world.tile_listener = listener
	var hop_ticks: int = (max_hops + 1) * probe.hop_bound(q, q, q)
	return float(label_ticks + check_ticks + hop_ticks) * tuning.spread_tick_seconds

# ---- save structure -------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": 1,
		"ticks": ticks,
		"sweep_cursor": sweep_cursor,
		"laps": laps,
		"total_sweep_planted": total_sweep_planted,
		"total_island_planted": total_island_planted,
		"zone_enum": Array(zone_enum),
		"zone_initial": Array(zone_initial),
		"zone_stable_tick": Array(zone_stable_tick),
		"zone_queue": WorldState._pack_bytes(zone_queue.slice(zone_queue_head).to_byte_array()),
		"job_zone": job_zone,
		"job_scan": job_scan,
		"job_head": job_head,
		"job_open": job_open,
		"label": WorldState._pack_bytes(label.to_byte_array()),
		"members": WorldState._pack_bytes(members.to_byte_array()),
		"comp_start": WorldState._pack_bytes(comp_start.to_byte_array()),
		"comp_end": WorldState._pack_bytes(comp_end.to_byte_array()),
		"comp_state": WorldState._pack_bytes(comp_state),
		"round_active": round_active,
		"round_comp": round_comp,
		"round_pos": round_pos,
		"round_empty": round_empty,
	}

## Restores onto a world rebuilt from its own save. False when the data does not fit.
func load_dict(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != 1:
		return false
	var n: int = world.tile_count()
	var saved_enum: PackedByteArray = PackedByteArray()
	for value: Variant in data["zone_enum"]:
		saved_enum.append(int(value))
	var saved_label: PackedInt32Array = WorldState._unpack_bytes(data["label"]).to_int32_array()
	var saved_members: PackedInt32Array = WorldState._unpack_bytes(data["members"]).to_int32_array()
	var saved_start: PackedInt32Array = WorldState._unpack_bytes(data["comp_start"]).to_int32_array()
	var saved_end: PackedInt32Array = WorldState._unpack_bytes(data["comp_end"]).to_int32_array()
	var saved_state: PackedByteArray = WorldState._unpack_bytes(data["comp_state"])
	var saved_queue: PackedInt32Array = WorldState._unpack_bytes(data["zone_queue"]).to_int32_array()
	var saved_initial: PackedByteArray = PackedByteArray()
	for value: Variant in data["zone_initial"]:
		saved_initial.append(int(value))
	var saved_stable_tick: PackedInt32Array = PackedInt32Array()
	for value: Variant in data["zone_stable_tick"]:
		saved_stable_tick.append(int(value))
	if saved_initial.size() != world.zone_count or saved_stable_tick.size() != world.zone_count:
		return false
	if saved_enum.size() != world.zone_count or (saved_label.size() != 0 and saved_label.size() != n):
		return false
	if saved_start.size() != saved_state.size() or saved_end.size() > saved_start.size() or saved_end.size() < saved_start.size() - 1:
		return false
	for index: int in saved_members:
		if index < 0 or index >= n:
			return false
	var saved_cursor: int = int(data["sweep_cursor"])
	if saved_cursor < 0 or saved_cursor >= maxi(n, 1):
		return false
	ticks = int(data["ticks"])
	sweep_cursor = saved_cursor
	laps = int(data.get("laps", 0))
	total_sweep_planted = int(data.get("total_sweep_planted", 0))
	total_island_planted = int(data.get("total_island_planted", 0))
	zone_enum = saved_enum
	zone_initial = saved_initial
	zone_stable_tick = saved_stable_tick
	zone_queue = saved_queue
	zone_queue_head = 0
	job_zone = int(data["job_zone"])
	job_scan = int(data["job_scan"])
	job_head = int(data["job_head"])
	job_open = bool(data["job_open"])
	label = saved_label
	members = saved_members
	comp_start = saved_start
	comp_end = saved_end
	comp_state = saved_state
	round_active = bool(data["round_active"])
	round_comp = int(data["round_comp"])
	round_pos = int(data["round_pos"])
	round_empty = int(data["round_empty"])
	return true
