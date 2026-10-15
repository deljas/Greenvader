extends RefCounted
## P1-06 test rig and greedy bot (headless, no rendering). Used by the tempo measurement (p1_06_tempo.gd) and the checks.
##
## The rig is the real game logic wired the way main.gd wires it: WorldState from the region PNG, SimClock -> GrowthSim /
## SpreadSim, PlayState (resources, landing, pickups, producer, cultivation) and the carrot boost sink. It is stepped at a
## fixed dt. There are no nodes: shots are queued with the same range clip and speed as ProjectileField (a shot lands after
## distance / speed seconds and is handed to PlayState.land_seed / land_water / land_plant), the player walks with Walker.
##
## The bot is a simple greedy loop (no randomness):
##   1 no seed left       -> fetch the nearest seed fruit (or wait at the seed source)
##   2 water low          -> walk to the nearest waterside spot and refill
##   3 seeds getting low  -> detour to a seed fruit close by
##   4 carrot due         -> shoot a carrot at a mature 2x2 block of an old nucleus
##   5 otherwise          -> walk until the nearest untouched spot is within shooting range, shoot a seed, then water
## "Untouched spot" = a cell of the coarse grid (cell_tiles) in which no reachable target tile is planted yet; when none is
## left it falls back to finer grids, so isolated leftovers are shot at too.
## Only targets that are connected to the start by walking (4-neighbour tile BFS over walkable terrain) count.

const TILE: int = 4
const NAV: int = 2
const REGION_PATH: String = "res://data/region_01.tres"

var region_def: RegionDef
var sim_tuning: SimTuning
var play_tuning: PlayTuning
var world: WorldState
var play: PlayState
var clock: SimClock
var growth: GrowthSim
var spread: SpreadSim
var half: Vector2 = Vector2(3, 2)
var pos: Vector2 = Vector2.ZERO
var time: float = 0.0
var steps: int = 0
## Optional RegionView whose per-frame flush is part of the measured logic cost (perf runs).
var view: RegionView = null
## Microseconds spent in the game logic (PlayState.advance + SimClock.advance + view flush) by the latest step.
var last_logic_us: int = 0

# ---- parameters of the bot (not game data) ----
var bot_on: bool = true
var carrots_on: bool = true
var fire_interval: float = 0.25
var cell_tiles: Array[int] = [32, 8, 2]
var stand_range_px: float = 80.0
var water_low: float = 10.0
var water_target: float = 60.0
var water_max_trip_px: float = 600.0
var seeds_low: int = 8
var detour_px: float = 400.0
var carrot_interval: float = 20.0
var carrot_min_age: float = 75.0
var carrot_min_seeds: int = 25
var use_water: bool = true
## The finest grid is used only this long after the 8-tile grid ran out of untouched spots (spread fills near gaps itself).
var fine_wait: float = 120.0

# ---- reachability ----
var reach: PackedByteArray = PackedByteArray()
var reach_tiles: int = 0
var reach_targets: int = 0
var reach_greened: int = 0
var last_stage: PackedByteArray = PackedByteArray()

# ---- nav grid (NAV x NAV tiles per cell) ----
var nav_w: int = 0
var nav_h: int = 0
var nav_ok: PackedByteArray = PackedByteArray()
var refill_cell: PackedByteArray = PackedByteArray()

# ---- target grids ----
var grid_w: Array[int] = []
var grid_h: Array[int] = []
var grid_reach: Array[PackedInt32Array] = []
var grid_busy: Array[PackedInt32Array] = []
var grid_skip: Array[PackedByteArray] = []

# ---- bot state ----
var task: String = ""
var task_target: Vector2 = Vector2.ZERO
var task_grid: int = 0
var task_cell: int = -1
var task_started: float = 0.0
var path: PackedInt32Array = PackedInt32Array()
var path_index: int = 0
var path_time: float = -100.0
var cooldown: float = 0.0
var flights: Array[Dictionary] = []
var nuclei: Array[Dictionary] = []
var last_carrot_time: float = -1000.0
var pending_water: Vector2 = Vector2.INF
var next_refill_check: float = 0.0
var next_carrot_search: float = 0.0
var phase1_done_time: float = -1.0
var shots_by_grid: Array[int] = [0, 0, 0]
var done: bool = false

# ---- statistics ----
var shots_seed: int = 0
var shots_water: int = 0
var shots_carrot: int = 0
var refills: int = 0
var carrots_placed: int = 0
var stall_total: float = 0.0
var stall_longest: float = 0.0
var stall_current: float = 0.0
var stall_events: int = 0
var stall_log: Array = []
var walk_time: float = 0.0
var samples: Array[Dictionary] = []
var next_sample: float = 0.0
var reach_times: Dictionary = {}
var peak_pickups: int = 0

func _init(sim_overrides: Dictionary = {}, play_overrides: Dictionary = {}) -> void:
	region_def = load(REGION_PATH) as RegionDef
	sim_tuning = (load("res://data/sim_tuning.tres") as SimTuning).duplicate() as SimTuning
	play_tuning = (load("res://data/play_tuning.tres") as PlayTuning).duplicate() as PlayTuning
	# P2-05: the P1 tempo bots measure the P1 mechanism; the stable-zone spread bonus (start zone) is pinned off here.
	sim_tuning.stable_spread_multiplier = 1.0
	for key: String in sim_overrides:
		sim_tuning.set(key, sim_overrides[key])
	for key: String in play_overrides:
		if key.begins_with("carrot_"):
			continue
		play_tuning.set(key, play_overrides[key])
	# Experiment hook for the tempo sweeps: carrot_multiplier / carrot_radius override the carrot's data on a copy.
	if play_overrides.has("carrot_multiplier") or play_overrides.has("carrot_radius"):
		var plants_copy: Array[PlantDef] = []
		for def: PlantDef in region_def.plants:
			var copy: PlantDef = def.duplicate() as PlantDef
			if copy.key == &"carrot":
				copy.effect_multiplier = float(play_overrides.get("carrot_multiplier", copy.effect_multiplier))
				copy.effect_radius_tiles = float(play_overrides.get("carrot_radius", copy.effect_radius_tiles))
			plants_copy.append(copy)
		region_def = region_def.duplicate() as RegionDef
		region_def.plants = plants_copy
	world = RegionLoader.load_region(region_def)
	var sources: Array[Vector2] = []
	for tile: Vector2i in region_def.seed_source_tiles:
		sources.append((Vector2(tile) + Vector2(0.5, 0.5)) * region_def.tile_px)
	var defs: Array[PlantDef] = []
	defs.assign(region_def.plants)
	growth = GrowthSim.new(world, sim_tuning)
	spread = SpreadSim.new(world, sim_tuning)
	clock = SimClock.new()
	clock.configure(sim_tuning)
	clock.growth_ticked.connect(func(_i: int) -> void: growth.tick())
	clock.spread_ticked.connect(func(_i: int) -> void: spread.tick())
	play = PlayState.new(world, play_tuning, sim_tuning, region_def.tile_px, sources, defs)
	play.cultivation.boost_sink = spread.set_speed_scale
	half = Vector2(play_tuning.walk_half_width_px, play_tuning.walk_half_height_px)
	pos = Vector2(region_def.start_tile * TILE) + Vector2(2, 2)
	world.clear_dirty()
	_build_reach()
	_build_nav()
	_build_grids()

# ---------------------------------------------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------------------------------------------

## 4-neighbour BFS over walkable tiles from the start tile.
func _build_reach() -> void:
	var n: int = world.tile_count()
	reach.resize(n)
	var start: int = world.index_of(region_def.start_tile.x, region_def.start_tile.y)
	var queue: PackedInt32Array = PackedInt32Array([start])
	reach[start] = 1
	var head: int = 0
	var w: int = world.width
	while head < queue.size():
		var index: int = queue[head]
		head += 1
		var x: int = index % w
		var y: int = index / w
		if x + 1 < w and reach[index + 1] == 0 and world.is_walkable(x + 1, y):
			reach[index + 1] = 1
			queue.append(index + 1)
		if x > 0 and reach[index - 1] == 0 and world.is_walkable(x - 1, y):
			reach[index - 1] = 1
			queue.append(index - 1)
		if y + 1 < world.height and reach[index + w] == 0 and world.is_walkable(x, y + 1):
			reach[index + w] = 1
			queue.append(index + w)
		if y > 0 and reach[index - w] == 0 and world.is_walkable(x, y - 1):
			reach[index - w] = 1
			queue.append(index - w)
	reach_tiles = queue.size()
	last_stage = world.stage.duplicate()
	reach_targets = 0
	reach_greened = 0
	for index: int in n:
		if reach[index] == 1 and world.target[index] == 1:
			reach_targets += 1
			if world.stage[index] >= WorldState.GREENED_MIN_STAGE:
				reach_greened += 1

func _build_nav() -> void:
	nav_w = world.width / NAV
	nav_h = world.height / NAV
	nav_ok.resize(nav_w * nav_h)
	refill_cell.resize(nav_w * nav_h)
	for cy: int in nav_h:
		for cx: int in nav_w:
			var ok: bool = true
			for dy: int in NAV:
				for dx: int in NAV:
					if reach[(cy * NAV + dy) * world.width + cx * NAV + dx] == 0:
						ok = false
			nav_ok[cy * nav_w + cx] = 1 if ok else 0
			if ok:
				# Near water from every point of the cell's centre area (the bot may stop a pixel off the centre).
				var centre: Vector2 = cell_center(cy * nav_w + cx)
				var all_near: bool = true
				for offset: Vector2 in [Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2), Vector2(2, 2)]:
					if not play.is_near_water(centre + offset):
						all_near = false
				if all_near:
					refill_cell[cy * nav_w + cx] = 1

func cell_center(cell: int) -> Vector2:
	return Vector2((cell % nav_w) * NAV + NAV * 0.5, (cell / nav_w) * NAV + NAV * 0.5) * TILE

func cell_of(point: Vector2) -> int:
	return clampi(floori(point.y / (NAV * TILE)), 0, nav_h - 1) * nav_w + clampi(floori(point.x / (NAV * TILE)), 0, nav_w - 1)

func _build_grids() -> void:
	grid_w.clear()
	grid_h.clear()
	grid_reach.clear()
	grid_busy.clear()
	grid_skip.clear()
	for size: int in cell_tiles:
		var gw: int = (world.width + size - 1) / size
		var gh: int = (world.height + size - 1) / size
		grid_w.append(gw)
		grid_h.append(gh)
		var counts: PackedInt32Array = PackedInt32Array()
		counts.resize(gw * gh)
		var busy: PackedInt32Array = PackedInt32Array()
		busy.resize(gw * gh)
		var skip: PackedByteArray = PackedByteArray()
		skip.resize(gw * gh)
		grid_reach.append(counts)
		grid_busy.append(busy)
		grid_skip.append(skip)
	for index: int in world.tile_count():
		if reach[index] == 1 and world.target[index] == 1 and world.terrain_defs[world.terrain[index]].plantable:
			var x: int = index % world.width
			var y: int = index / world.width
			for g: int in cell_tiles.size():
				var cell: int = (y / cell_tiles[g]) * grid_w[g] + x / cell_tiles[g]
				grid_reach[g][cell] += 1
				if world.stage[index] != WorldState.STAGE_EMPTY:
					grid_busy[g][cell] += 1

# ---------------------------------------------------------------------------------------------------------------
# Stepping
# ---------------------------------------------------------------------------------------------------------------

## Advances everything by `dt` seconds of game time.
func step(dt: float) -> void:
	steps += 1
	time += dt
	if bot_on and not done:
		_bot(dt)
	_flights()
	var t0: int = Time.get_ticks_usec()
	play.advance(dt, pos)
	clock.advance(dt)
	if view != null:
		view.flush(sim_tuning.render_tiles_per_frame)
	last_logic_us = Time.get_ticks_usec() - t0
	_track()
	peak_pickups = maxi(peak_pickups, play.pickups.count())
	if play.available_seeds() < 1 and bot_on and not done:
		stall_total += dt
		stall_current += dt
		stall_longest = maxf(stall_longest, stall_current)
	else:
		if stall_current > 0.0:
			stall_log.append([snappedf(time - stall_current, 0.1), snappedf(stall_current, 0.1)])
		stall_current = 0.0

## Folds the tiles that changed into the reachable-greened counter and the grid busy counts.
func _track() -> void:
	# With a view attached the view owns the dirty list (it flushes it); the bot only reads it.
	var dirty: PackedInt32Array = world.dirty_tiles if view != null else world.take_dirty()
	for index: int in dirty:
		var now: int = world.stage[index]
		var before: int = last_stage[index]
		if now == before:
			continue
		last_stage[index] = now
		if reach[index] == 0 or world.target[index] == 0:
			continue
		if (before >= WorldState.GREENED_MIN_STAGE) != (now >= WorldState.GREENED_MIN_STAGE):
			reach_greened += 1 if now >= WorldState.GREENED_MIN_STAGE else -1
		if (before == WorldState.STAGE_EMPTY) != (now == WorldState.STAGE_EMPTY) and world.terrain_defs[world.terrain[index]].plantable:
			var delta: int = 1 if before == WorldState.STAGE_EMPTY else -1
			var x: int = index % world.width
			var y: int = index / world.width
			for g: int in cell_tiles.size():
				grid_busy[g][(y / cell_tiles[g]) * grid_w[g] + x / cell_tiles[g]] += delta
	if time >= next_sample - 1.0e-9:
		next_sample += 300.0
		samples.append(snapshot())
	var percent: float = percent_now()
	for mark: int in [10, 25, 50, 75, 90, 95, 99, 100]:
		if not reach_times.has(mark) and (reach_greened * 100 >= reach_targets * mark):
			reach_times[mark] = time

func percent_now() -> float:
	return 100.0 * float(reach_greened) / float(maxi(reach_targets, 1))

func snapshot() -> Dictionary:
	return {"t": time, "percent": percent_now(), "greened": reach_greened, "seeds": play.seeds, "water": play.water, "mature": world.mature_count, "pickups": play.pickups.count(), "carrots": carrots_placed, "stall": stall_total, "shots": shots_seed}

func is_complete() -> bool:
	return reach_greened >= reach_targets

# ---------------------------------------------------------------------------------------------------------------
# Shots
# ---------------------------------------------------------------------------------------------------------------

## Fires like Main.fire(): clips to the range, spends/reserves, queues the landing. False when refused.
func fire(kind: String, aim_point: Vector2) -> bool:
	if cooldown > 0.0:
		return false
	var offset: Vector2 = aim_point - pos
	var direction: Vector2 = offset.normalized() if offset.length_squared() > 0.0001 else Vector2.RIGHT
	var distance: float = minf(offset.length(), play_tuning.projectile_range_px)
	var landing: Vector2 = pos + direction * distance
	if kind == ProjectileField.KIND_WATER:
		if not play.spend_water():
			return false
		shots_water += 1
	elif kind == ProjectileField.KIND_SEED:
		if not play.spend_seed():
			return false
		shots_seed += 1
	else:
		var def: PlantDef = play.def_by_key(StringName(kind))
		if def == null or not play.can_fire_plant(def):
			return false
		play.reserve_plant(def)
		shots_carrot += 1
	flights.append({"land": time + distance / play_tuning.projectile_speed, "kind": kind, "point": landing})
	cooldown = fire_interval
	return true

func _flights() -> void:
	var index: int = 0
	while index < flights.size():
		var flight: Dictionary = flights[index]
		if float(flight["land"]) <= time + 1.0e-9:
			flights.remove_at(index)
			var kind: String = String(flight["kind"])
			if kind == ProjectileField.KIND_WATER:
				play.land_water(flight["point"])
			elif kind == ProjectileField.KIND_SEED:
				play.land_seed(flight["point"])
			else:
				if play.land_plant(StringName(kind), flight["point"]) != null:
					carrots_placed += 1
		else:
			index += 1

# ---------------------------------------------------------------------------------------------------------------
# Bot
# ---------------------------------------------------------------------------------------------------------------

func _bot(dt: float) -> void:
	cooldown = maxf(cooldown - dt, 0.0)
	if task == "":
		_choose()
	match task:
		"collect":
			_do_collect()
		"wait":
			_do_wait()
		"refill":
			_do_refill()
		"plant":
			_do_plant()
		"carrot":
			_do_carrot()
		"water":
			_do_water()
		"idle":
			_do_idle()
	_move(dt)

func _set_task(name: String) -> void:
	task = name
	task_started = time
	path = PackedInt32Array()
	path_index = 0
	path_time = -100.0
	_waypoint = Vector2.INF

func _choose() -> void:
	var seeds: int = play.available_seeds()
	if seeds < 1:
		if _nearest_fruit() != Vector2.INF:
			_set_task("collect")
		else:
			_set_task("wait")
		return
	if pending_water != Vector2.INF:
		_set_task("water")
		return
	if use_water and play.water < water_low and time >= next_refill_check:
		if _refill_possible():
			_set_task("refill")
			return
		next_refill_check = time + 20.0
	if seeds < seeds_low:
		var fruit: Vector2 = _nearest_fruit()
		if fruit != Vector2.INF and fruit.distance_to(pos) <= detour_px:
			_set_task("collect")
			return
	if carrots_on and seeds >= carrot_min_seeds and time - last_carrot_time >= carrot_interval and _pick_carrot_target():
		_set_task("carrot")
		return
	if _pick_target():
		_set_task("plant")
		return
	if is_complete():
		done = true
	_set_task("idle")

func _do_idle() -> void:
	# Nothing untouched is left: try again every few seconds (spread may still be filling in).
	if time - task_started >= 3.0:
		task = ""

func _nearest_fruit() -> Vector2:
	var best: Vector2 = Vector2.INF
	var best_distance: float = INF
	for item: Dictionary in play.pickups.items:
		if String(item["kind"]) != GroundPickups.KIND_SEED_FRUIT:
			continue
		var point: Vector2 = Vector2(float(item["x"]), float(item["y"]))
		var d: float = point.distance_squared_to(pos)
		if d < best_distance and nav_ok[cell_of(point)] == 1:
			best_distance = d
			best = point
	return best

func _do_collect() -> void:
	if play.available_seeds() >= play.tuning.seed_max - 1 or time - task_started > 40.0:
		task = ""
		return
	var fruit: Vector2 = _nearest_fruit()
	if fruit == Vector2.INF:
		task = ""
		return
	if fruit.distance_to(pos) <= 6.0:
		task = ""
		return
	_goto_point(fruit)

func _do_wait() -> void:
	if play.available_seeds() >= 1 or _nearest_fruit() != Vector2.INF:
		task = ""
		return
	_goto_point(play.sources[0].position + Vector2(0, 14))

func _refill_possible() -> bool:
	var spot: int = _bfs_nearest(refill_cell, 0, true)
	return spot >= 0 and cell_center(spot).distance_to(pos) <= water_max_trip_px

func _do_refill() -> void:
	if play.water >= water_target or time - task_started > 60.0:
		if play.water >= water_target:
			refills += 1
		task = ""
		return
	if play.refilling:
		return
	var spot: int = _bfs_nearest(refill_cell, 0, true)
	if spot < 0:
		task = ""
		return
	_goto_cell(spot)

func _do_water() -> void:
	if pending_water == Vector2.INF or not use_water or play.water < play_tuning.water_cost_per_shot:
		pending_water = Vector2.INF
		task = ""
		return
	if cooldown <= 0.0 and fire(ProjectileField.KIND_WATER, pending_water):
		pending_water = Vector2.INF
		task = ""

## Picks the nearest untouched cell (coarse grid first) as the next planting target. False when none is left.
func _pick_target() -> bool:
	for g: int in cell_tiles.size():
		var best: int = -1
		var best_distance: float = INF
		var counts: PackedInt32Array = grid_reach[g]
		var busy: PackedInt32Array = grid_busy[g]
		var skip: PackedByteArray = grid_skip[g]
		var gw: int = grid_w[g]
		var size: int = cell_tiles[g]
		var min_targets: int = 1 if g > 0 else 20
		if g == 2 and (phase1_done_time < 0.0 or time - phase1_done_time < fine_wait):
			continue
		for cell: int in counts.size():
			if counts[cell] < min_targets or busy[cell] > 0 or skip[cell] == 1:
				continue
			if g > 0 and _neighbour_busy(g, cell) > 0:
				continue
			var center: Vector2 = Vector2((cell % gw) * size + size * 0.5, (cell / gw) * size + size * 0.5) * TILE
			var d: float = center.distance_squared_to(pos)
			if d < best_distance:
				best_distance = d
				best = cell
		if g == 1 and phase1_done_time < 0.0:
			phase1_done_time = time
		if best >= 0:
			var point: Vector2 = _plant_point(g, best)
			if point == Vector2.INF:
				grid_skip[g][best] = 1
				return _pick_target()
			task_grid = g
			task_cell = best
			task_target = point
			return true
	return false

## Planted tiles in the 3x3 cells around a cell of grid g.
func _neighbour_busy(g: int, cell: int) -> int:
	var gw: int = grid_w[g]
	var gh: int = grid_h[g]
	var cx: int = cell % gw
	var cy: int = cell / gw
	var total: int = 0
	for y: int in range(maxi(cy - 1, 0), mini(cy + 2, gh)):
		for x: int in range(maxi(cx - 1, 0), mini(cx + 2, gw)):
			total += grid_busy[g][y * gw + x]
	return total

## The plantable empty reachable tile of a cell nearest to the cell centre, as a pixel point (tile centre).
func _plant_point(g: int, cell: int) -> Vector2:
	var size: int = cell_tiles[g]
	var gw: int = grid_w[g]
	var x0: int = (cell % gw) * size
	var y0: int = (cell / gw) * size
	var centre: Vector2 = Vector2(x0 + size * 0.5, y0 + size * 0.5)
	var best: Vector2 = Vector2.INF
	var best_distance: float = INF
	for y: int in range(y0, mini(y0 + size, world.height)):
		for x: int in range(x0, mini(x0 + size, world.width)):
			var index: int = y * world.width + x
			if reach[index] == 1 and world.can_plant(index):
				var d: float = (Vector2(x + 0.5, y + 0.5)).distance_squared_to(centre)
				if d < best_distance:
					best_distance = d
					best = (Vector2(x, y) + Vector2(0.5, 0.5)) * TILE
	return best

func _do_plant() -> void:
	if play.available_seeds() < 1:
		task = ""
		return
	# The spot may have been filled meanwhile (natural spread reached it).
	if grid_busy[task_grid][task_cell] > 0 or (task_grid > 0 and _neighbour_busy(task_grid, task_cell) > 0) or not world.can_plant(world.index_of(floori(task_target.x / TILE), floori(task_target.y / TILE))):
		task = ""
		return
	if pos.distance_to(task_target) > stand_range_px:
		_goto_range(task_target, stand_range_px)
		return
	if fire(ProjectileField.KIND_SEED, task_target):
		shots_by_grid[task_grid] += 1
		nuclei.append({"point": task_target, "time": time, "carrot": false})
		pending_water = task_target
		task = ""

## A carrot goes onto a mature 2x2 block within shooting range of where the bot stands: the one with the most empty
## ground around it (that ground is what the carrot speeds up). It costs a shot and 3 seeds but no walking.
func _pick_carrot_target() -> bool:
	var def: PlantDef = play.def_by_key(&"carrot")
	if def == null or not play.can_fire_plant(def):
		return false
	if time < next_carrot_search:
		return false
	next_carrot_search = time + 8.0
	var best: Vector2 = Vector2.INF
	var best_score: int = 0
	var reach_tiles_r: int = ceili(def.effect_radius_tiles)
	for radius: float in [24.0, 44.0, 64.0]:
		for k: int in 16:
			var sample: Vector2 = pos + Vector2.from_angle(TAU * k / 16.0) * radius
			var tile: Vector2i = Vector2i(floori(sample.x / TILE), floori(sample.y / TILE))
			if not play.cultivation.block_valid(tile, 2):
				continue
			var score: int = 0
			for y: int in range(tile.y - reach_tiles_r, tile.y + reach_tiles_r + 2, 2):
				for x: int in range(tile.x - reach_tiles_r, tile.x + reach_tiles_r + 2, 2):
					if x >= 0 and y >= 0 and x < world.width and y < world.height:
						var index: int = y * world.width + x
						if reach[index] == 1 and world.can_plant(index):
							score += 1
			if score > best_score:
				best_score = score
				best = (Vector2(tile) + Vector2(1, 1)) * TILE
	if best == Vector2.INF or best_score < 20:
		return false
	task_target = best
	return true

func _do_carrot() -> void:
	if pos.distance_to(task_target) > stand_range_px:
		_goto_range(task_target, stand_range_px)
		return
	if fire("carrot", task_target):
		last_carrot_time = time
		task = ""
	elif time - task_started > 30.0:
		task = ""

# ---------------------------------------------------------------------------------------------------------------
# Walking
# ---------------------------------------------------------------------------------------------------------------

var _goal_pos: Vector2 = Vector2.INF

func _goto_point(point: Vector2) -> void:
	_goal_pos = point
	_plan_to_cells(_flags_around(point, 10.0), point)

func _goto_range(point: Vector2, range_px: float) -> void:
	_goal_pos = Vector2.INF
	_plan_to_cells(_flags_around(point, range_px - 3.0), Vector2.INF)

func _goto_cell(cell: int) -> void:
	_goal_pos = cell_center(cell)
	if path.is_empty() or time - path_time > 1.0:
		path_time = time
		path = _bfs_path_to_cell(cell)
		path_index = 0

var _flag_scratch: PackedByteArray = PackedByteArray()

## Flags every nav cell whose centre lies within `radius` px of the point.
func _flags_around(point: Vector2, radius: float) -> PackedByteArray:
	if _flag_scratch.size() != nav_ok.size():
		_flag_scratch.resize(nav_ok.size())
	_flag_scratch.fill(0)
	var reach_cells: int = ceili(radius / (NAV * TILE)) + 1
	var centre: int = cell_of(point)
	var cx: int = centre % nav_w
	var cy: int = centre / nav_w
	for y: int in range(maxi(cy - reach_cells, 0), mini(cy + reach_cells + 1, nav_h)):
		for x: int in range(maxi(cx - reach_cells, 0), mini(cx + reach_cells + 1, nav_w)):
			var cell: int = y * nav_w + x
			if nav_ok[cell] == 1 and cell_center(cell).distance_to(point) <= radius:
				_flag_scratch[cell] = 1
	return _flag_scratch

func _plan_to_cells(flags: PackedByteArray, final_point: Vector2) -> void:
	# A fixed target is planned once; a moving one (fruit) at most once a second.
	if not path.is_empty() and (task == "plant" or task == "carrot" or time - path_time < 1.0):
		return
	path_time = time
	_waypoint = Vector2.INF
	var start: int = _start_cell()
	if flags[start] == 1:
		path = PackedInt32Array([start])
		path_index = 0
		return
	var goal: int = _bfs_nearest(flags, 0, false)
	if goal < 0:
		# Unreachable or no walkable cell in range: give the task up (its cell is not tried again).
		if task == "plant" and task_cell >= 0:
			grid_skip[task_grid][task_cell] = 1
		task = ""
		return
	path = _bfs_path_to_cell(goal)
	path_index = 0

## Cell the bot starts a search from: its own, or the nearest walkable one.
func _start_cell() -> int:
	var cell: int = cell_of(pos)
	if nav_ok[cell] == 1:
		return cell
	var cx: int = cell % nav_w
	var cy: int = cell / nav_w
	for radius: int in range(1, 6):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				var x: int = cx + dx
				var y: int = cy + dy
				if x >= 0 and y >= 0 and x < nav_w and y < nav_h and nav_ok[y * nav_w + x] == 1:
					return y * nav_w + x
	return cell

var _parent: PackedInt32Array = PackedInt32Array()
var _stamp: PackedInt32Array = PackedInt32Array()
var _stamp_id: int = 0

## Breadth-first search over walkable nav cells from the bot's cell; returns the first cell with flags[cell] == 1
## (the nearest by walking) or -1. `_parent` holds the way back.
func _bfs_nearest(flags: PackedByteArray, _unused: int, _only_flags: bool) -> int:
	if _parent.size() != nav_ok.size():
		_parent.resize(nav_ok.size())
		_stamp.resize(nav_ok.size())
	_stamp_id += 1
	var start: int = _start_cell()
	var queue: PackedInt32Array = PackedInt32Array([start])
	_stamp[start] = _stamp_id
	_parent[start] = -1
	var head: int = 0
	while head < queue.size():
		var cell: int = queue[head]
		head += 1
		if flags[cell] == 1:
			return cell
		var x: int = cell % nav_w
		var next: int = cell + 1
		if x + 1 < nav_w and nav_ok[next] == 1 and _stamp[next] != _stamp_id:
			_stamp[next] = _stamp_id
			_parent[next] = cell
			queue.append(next)
		next = cell - 1
		if x > 0 and nav_ok[next] == 1 and _stamp[next] != _stamp_id:
			_stamp[next] = _stamp_id
			_parent[next] = cell
			queue.append(next)
		next = cell + nav_w
		if next < nav_ok.size() and nav_ok[next] == 1 and _stamp[next] != _stamp_id:
			_stamp[next] = _stamp_id
			_parent[next] = cell
			queue.append(next)
		next = cell - nav_w
		if next >= 0 and nav_ok[next] == 1 and _stamp[next] != _stamp_id:
			_stamp[next] = _stamp_id
			_parent[next] = cell
			queue.append(next)
	return -1

func _bfs_path_to_cell(goal: int) -> PackedInt32Array:
	var flags: PackedByteArray = PackedByteArray()
	flags.resize(nav_ok.size())
	flags[goal] = 1
	var found: int = _bfs_nearest(flags, 0, false)
	var result: PackedInt32Array = PackedInt32Array()
	if found < 0:
		return result
	var cell: int = found
	while cell >= 0:
		result.append(cell)
		cell = _parent[cell]
	result.reverse()
	return result

func _segment_clear(from: Vector2, to: Vector2) -> bool:
	var distance: float = from.distance_to(to)
	var count: int = ceili(distance / 3.0)
	for i: int in range(1, count + 1):
		if not Walker.is_clear(world, TILE, from.lerp(to, float(i) / float(count)), half):
			return false
	return true

var _waypoint: Vector2 = Vector2.INF
var _waypoint_time: float = -100.0

func _move(dt: float) -> void:
	var goal: Vector2 = Vector2.INF
	if path.is_empty():
		if _goal_pos != Vector2.INF and (task == "collect" or task == "wait"):
			goal = _goal_pos
		else:
			return
	else:
		# Furthest path cell that can be reached in a straight line (re-chosen a few times per second).
		if time - _waypoint_time > 0.2 or _waypoint == Vector2.INF:
			_waypoint_time = time
			var last: int = mini(path_index + 14, path.size() - 1)
			while path_index < path.size() - 1 and cell_center(path[path_index]).distance_to(pos) < 3.0:
				path_index += 1
			var chosen: int = path_index
			for k: int in range(last, path_index - 1, -1):
				if _segment_clear(pos, cell_center(path[k])):
					chosen = k
					break
			path_index = chosen
			_waypoint = cell_center(path[chosen])
		goal = _waypoint
		if path_index >= path.size() - 1 and pos.distance_to(cell_center(path[path.size() - 1])) < 2.0:
			if _goal_pos != Vector2.INF and (task == "collect" or task == "wait"):
				goal = _goal_pos
			else:
				return
	var to: Vector2 = goal - pos
	if to.length() < 0.5:
		return
	var motion: Vector2 = to.normalized() * minf(FlowerPlayer.SPEED * dt, to.length())
	pos = Walker.move(world, TILE, pos, motion, half)
	walk_time += dt
