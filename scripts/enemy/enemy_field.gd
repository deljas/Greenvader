class_name EnemyField
extends RefCounted
## Enemy nests and boars (P2-01). Display-free; time only moves through advance() (game time), so a paused tree freezes
## everything and nothing is banked. The simulation runs in fixed steps of 1 / step_hz seconds counted from the total time
## (like SimClock): the same total time gives the same steps at 30, 60 or 144 Hz, and every timer is an integer step count.
##
## Nests: placed on plantable ground, they occupy a size x size block (WorldState.occupy, owner OWNER_BAND_NEST + id), so
## nothing else (spread, seeds, cultivated plants) can take those tiles. Each alive nest in a zone that is open to enemies
## spawns a boar every spawn interval while it has room under the nest limit and the global limit (the timer does not run
## while a limit is reached, so a full region never banks spawns). Destroying a nest releases its tiles and stops its spawning.
##
## Boars never leave their zone, never enter a stable / complete zone, and never go farther than the tether from their nest. They walk like the player (Walker: no water, no buildings, sliding
## along walls, no path finding). They pick the nearest plant (seed .. mature, not under an occupant) in their zone and
## tether range, found by walking the chunks' plant counts, walk to it and bite the plants within the gnaw radius at a fixed
## interval (WorldState.set_stage to empty: the greening counters follow, and the tile returns to the spread queue by itself).
## Without a target they wander around the nest. A boar that cannot get closer gives that plant up for a while.
## When a zone becomes stable / complete (WorldState.zone_state_changed; ZoneProgress does this when the last enemy falls, tests
## may do it from outside) the boars still in it are removed at once (P2-04): a stable zone holds no enemy, so none can bite or touch.

## A boar fell by a shot (P2-02): where, and its id. The pickups / view side listens (drops are not decided here).
signal boar_defeated(position: Vector2, boar_id: int)
## A nest was destroyed by a shot.
signal nest_defeated(nest: Nest)
## The enemies of a zone changed in a way that may move its state (P2-04): a nest was destroyed or a boar left the field.
signal enemies_changed(zone: int)

const EPS: float = 1.0e-4

var world: WorldState
var tuning: EnemyTuning
var tile_px: int = 4
var half: Vector2 = Vector2(5, 3)
var nests: Array[Nest] = []
var boars: Array[Boar] = []
## Carcasses and bones, oldest first (P2-02).
var carcasses: Array[Carcass] = []
var next_carcass_id: int = 1
var next_nest_id: int = 1
var next_boar_id: int = 1
var time: float = 0.0
var steps_done: int = 0
var spawn_cursor: int = 0
## Observability for tests.
var total_spawned: int = 0
var total_gnawed: int = 0
var total_killed: int = 0
var total_carcasses: int = 0
var total_nests_destroyed: int = 0

var _dt: float = 1.0 / 60.0
var _speed_step: float = 0.0
var _tether_px: float = 0.0
var _spawn_steps: int = 1
var _think_steps: int = 1
var _gnaw_steps: int = 1
var _wander_wait_steps: int = 1
var _stuck_steps: int = 1
var _blocked_steps: int = 1
var _flash_steps: int = 1
var _flash_toggle_steps: int = 1
var _corpse_steps: int = 1
var _bone_steps: int = 1
var _cand_chunk: PackedInt32Array = PackedInt32Array()
var _cand_dist: PackedFloat32Array = PackedFloat32Array()

func _init(world_state: WorldState, enemy_tuning: EnemyTuning, tile_size: int) -> void:
	world = world_state
	tuning = enemy_tuning
	tile_px = tile_size
	half = Vector2(tuning.boar_half_width_px, tuning.boar_half_height_px)
	var hz: float = float(maxi(tuning.step_hz, 1))
	_dt = 1.0 / hz
	_speed_step = tuning.boar_speed_px / hz
	_tether_px = float(tuning.tether_tiles * tile_px)
	_spawn_steps = _to_steps(tuning.spawn_interval_seconds)
	_think_steps = _to_steps(tuning.think_interval_seconds)
	_gnaw_steps = _to_steps(tuning.gnaw_interval_seconds)
	_wander_wait_steps = _to_steps(tuning.wander_wait_seconds)
	_stuck_steps = _to_steps(tuning.stuck_check_seconds)
	_blocked_steps = _to_steps(tuning.blocked_seconds)
	_flash_steps = _to_steps(tuning.hit_flash_seconds)
	_flash_toggle_steps = _to_steps(tuning.hit_flash_toggle_seconds)
	_corpse_steps = _to_steps(tuning.carcass_seconds)
	_bone_steps = _to_steps(tuning.bone_seconds)
	world.zone_state_changed.connect(_on_zone_state_changed)

func _to_steps(seconds: float) -> int:
	return maxi(roundi(seconds * float(maxi(tuning.step_hz, 1))), 1)

# ---- nests ----------------------------------------------------------------------------------------------

## Places the nests of the zones' definitions (zones that start open to enemies only). Returns how many were placed;
## sites that do not fit are skipped with an error.
func setup_nests(zones: Array[ZoneDef]) -> int:
	var placed: int = 0
	for zone: ZoneDef in zones:
		if zone.id >= world.zone_count or not world.zone_open_to_enemies(zone.id):
			continue
		for tile: Vector2i in zone.nest_tiles:
			if nests.size() >= tuning.nest_max_count:
				push_error("EnemyField: more than %d nests are defined" % tuning.nest_max_count)
				return placed
			if add_nest(zone.id, tile) == null:
				push_error("EnemyField: nest site %s of zone %s does not fit" % [tile, zone.key])
			else:
				placed += 1
	return placed

## Places one nest whose block lies completely in `zone` on free plantable ground. Null when it does not fit.
func add_nest(zone: int, tile: Vector2i) -> Nest:
	var nest: Nest = Nest.new()
	nest.id = next_nest_id
	nest.zone = zone
	nest.tile = tile
	nest.size = tuning.nest_size_tiles
	nest.hp_max = maxi(tuning.nest_hp, 1)
	nest.hp = nest.hp_max
	if tile.x < 0 or tile.y < 0 or tile.x + nest.size > world.width or tile.y + nest.size > world.height:
		return null
	for y: int in range(tile.y, tile.y + nest.size):
		for x: int in range(tile.x, tile.x + nest.size):
			if world.zone_of[world.index_of(x, y)] != zone:
				return null
	if not world.occupy(nest.rect(), nest.owner_id()):
		return null
	next_nest_id += 1
	nests.append(nest)
	return nest

func nest_by_id(id: int) -> Nest:
	for nest: Nest in nests:
		if nest.id == id:
			return nest
	return null

func alive_nest_count(zone: int = -1) -> int:
	var total: int = 0
	for nest: Nest in nests:
		if nest.alive and (zone < 0 or nest.zone == zone):
			total += 1
	return total

func boar_count_in_zone(zone: int) -> int:
	var total: int = 0
	for boar: Boar in boars:
		if boar.zone == zone:
			total += 1
	return total

## Takes `amount` hit points from a nest; destroys it at 0. Returns true when it was destroyed by this call.
func damage_nest(nest: Nest, amount: int) -> bool:
	if not nest.alive or amount <= 0:
		return false
	nest.hp = maxi(nest.hp - amount, 0)
	if nest.hp > 0:
		nest.flash_steps = _flash_steps
		return false
	destroy_nest(nest)
	total_nests_destroyed += 1
	nest_defeated.emit(nest)
	return true

## Removes a nest: its tiles are released (planting may take them), it stops spawning. Boars it spawned stay.
func destroy_nest(nest: Nest) -> void:
	if not nest.alive:
		return
	nest.alive = false
	nest.hp = 0
	nest.flash_steps = 0
	world.release(nest.owner_id())
	enemies_changed.emit(nest.zone)

## Takes `amount` hit points from a boar; it is removed at 0. Returns true when it was killed by this call.
func damage_boar(boar: Boar, amount: int) -> bool:
	if amount <= 0:
		return false
	boar.hp = maxi(boar.hp - amount, 0)
	if boar.hp > 0:
		boar.flash_steps = _flash_steps
		return false
	remove_boar(boar)
	total_killed += 1
	add_carcass(boar.pos)
	boar_defeated.emit(boar.pos, boar.id)
	return true

func remove_boar(boar: Boar) -> void:
	var at: int = boars.find(boar)
	if at < 0:
		return
	boars.remove_at(at)
	var nest: Nest = nest_by_id(boar.nest_id)
	if nest != null:
		nest.boar_count = maxi(nest.boar_count - 1, 0)
	enemies_changed.emit(boar.zone)

## A zone that became stable / complete holds no enemy: its remaining boars vanish (no carcass, no drop).
func _on_zone_state_changed(zone: int, _old_state: int, new_state: int) -> void:
	if new_state < WorldState.ZONE_STABLE:
		return
	for boar: Boar in boars.duplicate():
		if boar.zone == zone:
			remove_boar(boar)

## SpreadSim.allow_hook: natural spread never enters a nest's tiles.
func spread_allows(index: int) -> bool:
	return world.occupant[index] < WorldState.OWNER_BAND_NEST

# ---- hit shapes (P2-02 connects them to ProjectileField.enemy_hit_provider) ------------------------------------

func boar_body_center(boar: Boar) -> Vector2:
	return boar.pos - Vector2(0.0, tuning.hit_center_height_px)

## First enemy shape hit by the segment from -> to: {} for none, else {"kind": "boar" | "nest", "boar" / "nest", "point", "t"}.
## A boar is a circle of hit_radius_px around its body centre, an alive nest its block of tiles.
func hit_test(from: Vector2, to: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_t: float = INF
	var segment: Vector2 = to - from
	for boar: Boar in boars:
		var t: float = _segment_circle(from, segment, boar_body_center(boar), tuning.hit_radius_px)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = {"kind": "boar", "boar": boar}
	for nest: Nest in nests:
		if not nest.alive:
			continue
		var r: Rect2i = nest.rect()
		var t: float = _segment_rect(from, segment, Rect2(Vector2(r.position) * tile_px, Vector2(r.size) * tile_px))
		if t >= 0.0 and t < best_t:
			best_t = t
			best = {"kind": "nest", "nest": nest}
	if best.is_empty():
		return {}
	best["t"] = best_t
	best["point"] = from + segment * best_t
	return best

## Smallest t in [0, 1] where the segment touches the circle, or -1.
static func _segment_circle(from: Vector2, segment: Vector2, center: Vector2, radius: float) -> float:
	var offset: Vector2 = from - center
	if offset.length_squared() <= radius * radius:
		return 0.0
	var a: float = segment.length_squared()
	if a <= 1.0e-12:
		return -1.0
	var b: float = 2.0 * offset.dot(segment)
	var c: float = offset.length_squared() - radius * radius
	var disc: float = b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	var t: float = (-b - sqrt(disc)) / (2.0 * a)
	return t if t >= 0.0 and t <= 1.0 else -1.0

## Smallest t in [0, 1] where the segment enters the rectangle (0 when it starts inside), or -1.
static func _segment_rect(from: Vector2, segment: Vector2, rect: Rect2) -> float:
	var t_min: float = 0.0
	var t_max: float = 1.0
	for axis: int in 2:
		var start: float = from.x if axis == 0 else from.y
		var delta: float = segment.x if axis == 0 else segment.y
		var low: float = rect.position.x if axis == 0 else rect.position.y
		var high: float = low + (rect.size.x if axis == 0 else rect.size.y)
		if absf(delta) < 1.0e-12:
			if start < low or start > high:
				return -1.0
		else:
			var t1: float = (low - start) / delta
			var t2: float = (high - start) / delta
			t_min = maxf(t_min, minf(t1, t2))
			t_max = minf(t_max, maxf(t1, t2))
			if t_min > t_max:
				return -1.0
	return t_min

# ---- time -------------------------------------------------------------------------------------------------

## Advances game time by `delta` seconds (capped per call): runs every fixed step that became due.
func advance(delta: float) -> void:
	if delta <= 0.0 or not tuning.enabled:
		return
	delta = minf(delta, tuning.max_step_seconds)
	time += delta
	while float(steps_done + 1) * _dt <= time + 1.0e-9:
		steps_done += 1
		_step()

func _step() -> void:
	_spawn_step()
	for boar: Boar in boars:
		_boar_step(boar)
		if boar.flash_steps > 0:
			boar.flash_steps -= 1
	for nest: Nest in nests:
		if nest.flash_steps > 0:
			nest.flash_steps -= 1
	if not carcasses.is_empty():
		_carcass_step()

## True while the hit flash of a boar / nest (given its remaining flash steps) is in its bright half (view helper).
func flash_bright(flash_steps: int) -> bool:
	return flash_steps > 0 and ((flash_steps - 1) / _flash_toggle_steps) % 2 == 0

# ---- spawning ---------------------------------------------------------------------------------------------

func _spawn_step() -> void:
	var count: int = nests.size()
	if count == 0:
		return
	var base: int = spawn_cursor
	for k: int in count:
		var nest: Nest = nests[(base + k) % count]
		if not nest.alive or not world.zone_open_to_enemies(nest.zone):
			continue
		if nest.boar_count >= tuning.nest_boar_cap or boars.size() >= tuning.boar_cap:
			nest.spawn_steps = 0
			continue
		nest.spawn_steps += 1
		if nest.spawn_steps >= _spawn_steps:
			if _spawn(nest):
				nest.spawn_steps = 0
				spawn_cursor = (base + k + 1) % count
			else:
				nest.spawn_steps = _spawn_steps

## Spawns one boar on a walkable target tile of the ring around the nest. False when no point of the ring fits.
func _spawn(nest: Nest) -> bool:
	var boar: Boar = Boar.new()
	boar.rng = (tuning.rng_seed * 31 + nest.id * 7919 + nest.spawned * 104729 + 1) & 0x7FFFFFFF
	if boar.rng == 0:
		boar.rng = 1
	var center: Vector2 = nest.center_px(tile_px)
	var radius: float = float(nest.size * tile_px) * 0.5 * 1.4143 + tuning.spawn_ring_px
	var start: int = boar.next_int(16)
	for k: int in 16:
		var angle: float = TAU * float((start + k) % 16) / 16.0
		var point: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
		if not Walker.is_clear(world, tile_px, point, half) or not _allowed(nest.zone, center, point):
			continue
		var tx: int = floori(point.x / tile_px)
		var ty: int = floori(point.y / tile_px)
		if world.target[world.index_of(tx, ty)] == 0:
			continue
		boar.id = next_boar_id
		boar.nest_id = nest.id
		boar.zone = nest.zone
		boar.pos = point
		boar.home = center
		boar.hp = maxi(tuning.boar_hp, 1)
		boar.facing = 1 if point.x >= center.x else -1
		boar.think = 1 + (boar.id * 7) % _think_steps
		boar.window_pos = point
		next_boar_id += 1
		nest.spawned += 1
		nest.boar_count += 1
		boars.append(boar)
		total_spawned += 1
		return true
	return false

# ---- boar behaviour ---------------------------------------------------------------------------------------

## True when a boar of `zone` with tether centre `home` may stand with its feet at `p`: every tile under the feet
## rectangle lies in its zone and the point is within the tether.
func _allowed(zone: int, home: Vector2, p: Vector2) -> bool:
	if p.distance_squared_to(home) > _tether_px * _tether_px:
		return false
	var x0: int = floori((p.x - half.x + EPS) / tile_px)
	var x1: int = ceili((p.x + half.x - EPS) / tile_px) - 1
	var y0: int = floori((p.y - half.y + EPS) / tile_px)
	var y1: int = ceili((p.y + half.y - EPS) / tile_px) - 1
	if x0 < 0 or y0 < 0 or x1 >= world.width or y1 >= world.height:
		return false
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			if world.zone_of[y * world.width + x] != zone:
				return false
	return true

func _boar_step(boar: Boar) -> void:
	if boar.blocked_steps > 0:
		boar.blocked_steps -= 1
		if boar.blocked_steps == 0:
			boar.blocked_tile = -1
	if boar.gnaw_cooldown > 0:
		boar.gnaw_cooldown -= 1
	elif _gnaw(boar) > 0:
		boar.gnaw_cooldown = _gnaw_steps
	if boar.wait > 0:
		boar.wait -= 1
		return
	boar.think -= 1
	if boar.think <= 0:
		_think(boar)
	if boar.goal != Vector2.INF:
		_walk(boar)

## Removes the plants within the gnaw radius of the boar. Returns how many tiles were cleared.
func _gnaw(boar: Boar) -> int:
	var radius_px: float = tuning.gnaw_radius_tiles * tile_px
	var limit: float = radius_px * radius_px
	var cleared: int = 0
	for y: int in range(maxi(floori((boar.pos.y - radius_px) / tile_px), 0), mini(floori((boar.pos.y + radius_px) / tile_px), world.height - 1) + 1):
		for x: int in range(maxi(floori((boar.pos.x - radius_px) / tile_px), 0), mini(floori((boar.pos.x + radius_px) / tile_px), world.width - 1) + 1):
			var index: int = y * world.width + x
			if world.stage[index] == WorldState.STAGE_EMPTY or world.occupant[index] != 0 or world.zone_of[index] != boar.zone or not world.zone_open_to_enemies(world.zone_of[index]):
				continue
			var offset: Vector2 = Vector2((x + 0.5) * tile_px, (y + 0.5) * tile_px) - boar.pos
			if offset.length_squared() <= limit and world.set_stage(index, WorldState.STAGE_EMPTY):
				cleared += 1
	total_gnawed += cleared
	return cleared

func _think(boar: Boar) -> void:
	boar.think = _think_steps
	var target: int = _find_target(boar)
	if target >= 0:
		if boar.mode != Boar.MODE_CHASE or boar.goal_tile != target:
			boar.window_steps = 0
			boar.window_pos = boar.pos
		boar.mode = Boar.MODE_CHASE
		boar.goal_tile = target
		boar.goal = Vector2((target % world.width + 0.5) * tile_px, (target / world.width + 0.5) * tile_px)
		return
	if boar.mode == Boar.MODE_CHASE or boar.goal == Vector2.INF:
		boar.mode = Boar.MODE_WANDER
		boar.goal_tile = -1
		_pick_wander(boar)

func _pick_wander(boar: Boar) -> void:
	boar.goal = Vector2.INF
	for attempt: int in 6:
		var angle: float = TAU * float(boar.next_int(360)) / 360.0
		var distance: float = float(2 + boar.next_int(maxi(tuning.wander_radius_tiles - 1, 1))) * tile_px
		var point: Vector2 = boar.home + Vector2(cos(angle), sin(angle)) * distance
		if Walker.is_clear(world, tile_px, point, half) and _allowed(boar.zone, boar.home, point):
			boar.goal = point
			boar.window_steps = 0
			boar.window_pos = boar.pos
			return
	boar.wait = _wander_wait_steps

## Nearest plant tile (any stage, no occupant, in the boar's zone, inside the tether, not given up), or -1.
## Chunks are visited nearest first; the search stops when the next chunk cannot hold anything nearer.
func _find_target(boar: Boar) -> int:
	var chunk_px: float = float(WorldState.CHUNK_TILES * tile_px)
	var min_cx: int = maxi(floori((boar.home.x - _tether_px) / chunk_px), 0)
	var max_cx: int = mini(floori((boar.home.x + _tether_px) / chunk_px), world.chunks_x - 1)
	var min_cy: int = maxi(floori((boar.home.y - _tether_px) / chunk_px), 0)
	var max_cy: int = mini(floori((boar.home.y + _tether_px) / chunk_px), world.chunks_y - 1)
	_cand_chunk.clear()
	_cand_dist.clear()
	var tether_sq: float = _tether_px * _tether_px
	for cy: int in range(min_cy, max_cy + 1):
		for cx: int in range(min_cx, max_cx + 1):
			var chunk: int = cy * world.chunks_x + cx
			if world.plant_chunk_count[chunk] == 0:
				continue
			var low: Vector2 = Vector2(cx, cy) * chunk_px
			var high: Vector2 = low + Vector2(chunk_px, chunk_px)
			var from_home: Vector2 = Vector2(maxf(maxf(low.x - boar.home.x, boar.home.x - high.x), 0.0), maxf(maxf(low.y - boar.home.y, boar.home.y - high.y), 0.0))
			if from_home.length_squared() > tether_sq:
				continue
			var from_boar: Vector2 = Vector2(maxf(maxf(low.x - boar.pos.x, boar.pos.x - high.x), 0.0), maxf(maxf(low.y - boar.pos.y, boar.pos.y - high.y), 0.0))
			_cand_chunk.append(chunk)
			_cand_dist.append(from_boar.length_squared())
	var best_tile: int = -1
	var best_d: float = INF
	var blocked_x: int = boar.blocked_tile % world.width if boar.blocked_tile >= 0 else 0
	var blocked_y: int = boar.blocked_tile / world.width if boar.blocked_tile >= 0 else 0
	for visit: int in _cand_chunk.size():
		var pick: int = -1
		var pick_d: float = INF
		for k: int in _cand_chunk.size():
			if _cand_dist[k] < pick_d:
				pick_d = _cand_dist[k]
				pick = k
		if pick < 0 or pick_d >= best_d:
			break
		var chunk: int = _cand_chunk[pick]
		_cand_dist[pick] = INF
		var x_from: int = (chunk % world.chunks_x) * WorldState.CHUNK_TILES
		var y_from: int = (chunk / world.chunks_x) * WorldState.CHUNK_TILES
		for y: int in range(y_from, mini(y_from + WorldState.CHUNK_TILES, world.height)):
			for x: int in range(x_from, mini(x_from + WorldState.CHUNK_TILES, world.width)):
				var index: int = y * world.width + x
				if world.stage[index] == WorldState.STAGE_EMPTY or world.occupant[index] != 0 or world.zone_of[index] != boar.zone:
					continue
				if boar.blocked_tile >= 0 and absi(x - blocked_x) <= tuning.blocked_radius_tiles and absi(y - blocked_y) <= tuning.blocked_radius_tiles:
					continue
				var center: Vector2 = Vector2((x + 0.5) * tile_px, (y + 0.5) * tile_px)
				if center.distance_squared_to(boar.home) > tether_sq:
					continue
				var d: float = center.distance_squared_to(boar.pos)
				if d < best_d:
					best_d = d
					best_tile = index
	return best_tile

func _walk(boar: Boar) -> void:
	var to_goal: Vector2 = boar.goal - boar.pos
	var distance: float = to_goal.length()
	if distance > tuning.arrival_px:
		var motion: Vector2 = to_goal / distance * minf(_speed_step, distance)
		var moved: Vector2 = _try_move(boar, motion)
		if absf(moved.x - boar.pos.x) > 1.0e-3:
			boar.facing = 1 if moved.x > boar.pos.x else -1
		boar.pos = moved
	boar.window_steps += 1
	if boar.pos.distance_to(boar.goal) <= tuning.arrival_px:
		# Reached: a plant goal is bitten by the regular gnaw (wait for the cooldown), then the next choice is made.
		var chasing: bool = boar.mode == Boar.MODE_CHASE
		boar.goal = Vector2.INF
		boar.goal_tile = -1
		boar.wait = maxi(boar.gnaw_cooldown, 1) if chasing else _wander_wait_steps
		boar.think = 0 if chasing else 1
		return
	if boar.window_steps >= _stuck_steps:
		var moved_far: float = boar.pos.distance_to(boar.window_pos)
		boar.window_steps = 0
		boar.window_pos = boar.pos
		if moved_far < 0.25 * tuning.boar_speed_px * tuning.stuck_check_seconds:
			if boar.mode == Boar.MODE_CHASE:
				boar.blocked_tile = boar.goal_tile
				boar.blocked_steps = _blocked_steps
				boar.think = 0
			else:
				boar.wait = _wander_wait_steps
				boar.think = 1
			boar.goal = Vector2.INF
			boar.goal_tile = -1

## The boar's position after trying `motion`: the full move, else its X part, else its Y part, else it stays. A move
## counts only when Walker accepts it (terrain) and the zone / tether rule holds at the end point.
func _try_move(boar: Boar, motion: Vector2) -> Vector2:
	var full: Vector2 = Walker.move(world, tile_px, boar.pos, motion, half)
	if _allowed(boar.zone, boar.home, full):
		return full
	if motion.x != 0.0 and motion.y != 0.0:
		var along_x: Vector2 = Walker.move(world, tile_px, boar.pos, Vector2(motion.x, 0.0), half)
		if _allowed(boar.zone, boar.home, along_x):
			return along_x
		var along_y: Vector2 = Walker.move(world, tile_px, boar.pos, Vector2(0.0, motion.y), half)
		if _allowed(boar.zone, boar.home, along_y):
			return along_y
	return boar.pos

# ---- carcasses and bones (P2-02) --------------------------------------------------------------------------

## Fertility one carcass adds on the tiles within its radius, by stage.
func carcass_strength(carcass: Carcass) -> int:
	return tuning.carcass_fertility if carcass.stage == Carcass.STAGE_CORPSE else tuning.bone_fertility

## Tile indices whose centre lies within the carcass radius of `pos` (px).
func carcass_tiles(pos: Vector2) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	var radius_px: float = tuning.carcass_radius_tiles * tile_px
	var limit: float = radius_px * radius_px + 1.0e-6
	for y: int in range(maxi(floori((pos.y - radius_px) / tile_px), 0), mini(floori((pos.y + radius_px) / tile_px), world.height - 1) + 1):
		for x: int in range(maxi(floori((pos.x - radius_px) / tile_px), 0), mini(floori((pos.x + radius_px) / tile_px), world.width - 1) + 1):
			if Vector2((x + 0.5) * tile_px, (y + 0.5) * tile_px).distance_squared_to(pos) <= limit:
				result.append(world.index_of(x, y))
	return result

## The fertility the given carcasses add on tile `index`: the sum of their strengths, rounded down to the cap.
func layer_of(list: Array[Carcass], index: int) -> int:
	var centre: Vector2 = Vector2((index % world.width + 0.5) * tile_px, (index / world.width + 0.5) * tile_px)
	var radius_px: float = tuning.carcass_radius_tiles * tile_px
	var limit: float = radius_px * radius_px + 1.0e-6
	var sum: int = 0
	for carcass: Carcass in list:
		if carcass.pos.distance_squared_to(centre) <= limit:
			sum += carcass_strength(carcass)
	return mini(sum, tuning.carcass_fertility_cap)

func layer_at(index: int) -> int:
	return layer_of(carcasses, index)

func _layer_values(tiles: PackedInt32Array) -> PackedInt32Array:
	var values: PackedInt32Array = PackedInt32Array()
	values.resize(tiles.size())
	for i: int in tiles.size():
		values[i] = layer_at(tiles[i])
	return values

## Adds the change between the layer before (`old`) and now to the world's fertility of those tiles.
func _apply_layer_delta(tiles: PackedInt32Array, old: PackedInt32Array) -> void:
	for i: int in tiles.size():
		var delta: int = layer_at(tiles[i]) - old[i]
		if delta != 0:
			world.fertility[tiles[i]] = clampi(int(world.fertility[tiles[i]]) + delta, 0, 255)

## Leaves a carcass at `pos`. Over the limit the oldest one goes first (it passes through bone to nothing).
func add_carcass(pos: Vector2) -> Carcass:
	while carcasses.size() >= maxi(tuning.carcass_cap, 1):
		_remove_carcass(carcasses[0])
	var carcass: Carcass = Carcass.new()
	carcass.id = next_carcass_id
	carcass.pos = pos
	next_carcass_id += 1
	var tiles: PackedInt32Array = carcass_tiles(pos)
	var old: PackedInt32Array = _layer_values(tiles)
	carcasses.append(carcass)
	_apply_layer_delta(tiles, old)
	total_carcasses += 1
	return carcass

func _remove_carcass(carcass: Carcass) -> void:
	var tiles: PackedInt32Array = carcass_tiles(carcass.pos)
	var old: PackedInt32Array = _layer_values(tiles)
	carcasses.erase(carcass)
	_apply_layer_delta(tiles, old)

func _carcass_step() -> void:
	for carcass: Carcass in carcasses.duplicate():
		carcass.age_steps += 1
		if carcass.age_steps >= _corpse_steps + _bone_steps:
			_remove_carcass(carcass)
		elif carcass.age_steps >= _corpse_steps and carcass.stage == Carcass.STAGE_CORPSE:
			var tiles: PackedInt32Array = carcass_tiles(carcass.pos)
			var old: PackedInt32Array = _layer_values(tiles)
			carcass.stage = Carcass.STAGE_BONE
			_apply_layer_delta(tiles, old)

## Every tile within the radius of any of the carcasses, once.
func _covered_tiles(list: Array[Carcass]) -> Array[int]:
	var seen: Dictionary = {}
	for carcass: Carcass in list:
		for index: int in carcass_tiles(carcass.pos):
			seen[index] = true
	var result: Array[int] = []
	result.assign(seen.keys())
	return result

func carcass_count(stage: int) -> int:
	var total: int = 0
	for carcass: Carcass in carcasses:
		if carcass.stage == stage:
			total += 1
	return total

# ---- save structure ---------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var nest_list: Array = []
	for nest: Nest in nests:
		nest_list.append(nest.to_dict())
	var boar_list: Array = []
	for boar: Boar in boars:
		boar_list.append(boar.to_dict())
	var carcass_list: Array = []
	for carcass: Carcass in carcasses:
		carcass_list.append(carcass.to_dict())
	return {
		"version": 1, "time": time, "steps_done": steps_done, "spawn_cursor": spawn_cursor,
		"next_nest_id": next_nest_id, "next_boar_id": next_boar_id,
		"total_spawned": total_spawned, "total_gnawed": total_gnawed, "total_killed": total_killed,
		"total_carcasses": total_carcasses, "total_nests_destroyed": total_nests_destroyed,
		"nests": nest_list, "boars": boar_list, "carcasses": carcass_list, "next_carcass_id": next_carcass_id,
	}

## Restores the nests, boars and carcasses onto a world that holds the matching occupancy (or can take it). False (state
## unchanged) when the data does not fit the world. The carcass fertility lives in WorldState.fertility, which the world's
## own save holds: with `world_has_layer` (default) the world was restored from the same save and already contains it (this
## is checked); without it the carcass fertility is added to the world's fertility here (a fresh world), and the fertility
## of the carcasses that were present before the call is taken away.
func load_dict(data: Dictionary, world_has_layer: bool = true) -> bool:
	if int(data.get("version", 0)) != 1:
		return false
	var loaded_nests: Array[Nest] = []
	var seen: Dictionary = {}
	for entry: Variant in data.get("nests", []):
		if not (entry is Dictionary):
			return false
		var source: Dictionary = entry
		var nest: Nest = Nest.new()
		nest.id = int(source.get("id", 0))
		nest.zone = int(source.get("zone", -1))
		nest.tile = Vector2i(int(source.get("x", -1)), int(source.get("y", -1)))
		nest.size = int(source.get("size", 0))
		nest.hp_max = maxi(int(source.get("hp_max", 1)), 1)
		nest.hp = clampi(int(source.get("hp", 0)), 0, nest.hp_max)
		nest.alive = bool(source.get("alive", false))
		nest.spawn_steps = maxi(int(source.get("spawn_steps", 0)), 0)
		nest.spawned = maxi(int(source.get("spawned", 0)), 0)
		nest.flash_steps = maxi(int(source.get("flash", 0)), 0)
		if nest.id <= 0 or seen.has(nest.id) or nest.zone < 0 or nest.zone >= world.zone_count or nest.size <= 0:
			return false
		if nest.alive != (nest.hp > 0):
			return false
		seen[nest.id] = true
		loaded_nests.append(nest)
	var loaded_boars: Array[Boar] = []
	var boar_ids: Dictionary = {}
	var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(world.width, world.height) * tile_px)
	for entry: Variant in data.get("boars", []):
		if not (entry is Dictionary):
			return false
		var boar: Boar = Boar.from_dict(entry)
		if boar.id <= 0 or boar_ids.has(boar.id) or boar.zone < 0 or boar.zone >= world.zone_count or boar.hp <= 0 or not bounds.has_point(boar.pos):
			return false
		boar_ids[boar.id] = true
		loaded_boars.append(boar)
	var loaded_carcasses: Array[Carcass] = []
	var carcass_ids: Dictionary = {}
	var bounds_px: Rect2 = Rect2(Vector2.ZERO, Vector2(world.width, world.height) * tile_px)
	for entry: Variant in data.get("carcasses", []):
		if not (entry is Dictionary):
			return false
		var source: Dictionary = entry
		var carcass: Carcass = Carcass.new()
		carcass.id = int(source.get("id", 0))
		carcass.pos = Vector2(float(source.get("x", -1.0)), float(source.get("y", -1.0)))
		carcass.age_steps = maxi(int(source.get("age", 0)), 0)
		if carcass.id <= 0 or carcass_ids.has(carcass.id) or not bounds_px.has_point(carcass.pos) or carcass.age_steps >= _corpse_steps + _bone_steps:
			return false
		carcass.stage = Carcass.STAGE_CORPSE if carcass.age_steps < _corpse_steps else Carcass.STAGE_BONE
		carcass_ids[carcass.id] = true
		loaded_carcasses.append(carcass)
	if loaded_carcasses.size() > tuning.carcass_cap:
		return false
	# P2-04: the data must agree with the zone states of the world (a stable zone holds no enemy, a zone past "unconquered" has no
	# nest left alive, and a zone with nests that all fell is not "unconquered").
	var alive_by_zone: Dictionary = {}
	var any_by_zone: Dictionary = {}
	for nest: Nest in loaded_nests:
		any_by_zone[nest.zone] = true
		if nest.alive:
			alive_by_zone[nest.zone] = int(alive_by_zone.get(nest.zone, 0)) + 1
	for zone: int in world.zone_count:
		var zone_status: int = world.zone_state[zone]
		if zone_status >= WorldState.ZONE_CLEARING and alive_by_zone.has(zone):
			return false
		if zone_status == WorldState.ZONE_UNCONQUERED and any_by_zone.has(zone) and not alive_by_zone.has(zone):
			return false
	for boar: Boar in loaded_boars:
		if not world.zone_open_to_enemies(boar.zone):
			return false
	if world_has_layer:
		for carcass: Carcass in loaded_carcasses:
			for index: int in carcass_tiles(carcass.pos):
				if int(world.fertility[index]) < layer_of(loaded_carcasses, index):
					return false
	# Occupancy: every alive nest block must be this nest's own already, or free and takeable.
	var backup: Array[Nest] = nests.duplicate()
	for nest: Nest in backup:
		if nest.alive:
			world.release(nest.owner_id())
	var taken: Array[int] = []
	var ok: bool = true
	for nest: Nest in loaded_nests:
		if not nest.alive:
			continue
		if world.occupancy_owners.has(nest.owner_id()):
			ok = Rect2i(world.occupancy_owners[nest.owner_id()]) == nest.rect()
		else:
			ok = world.occupy(nest.rect(), nest.owner_id())
			if ok:
				taken.append(nest.owner_id())
		if not ok:
			break
	if not ok:
		for owner_id: int in taken:
			world.release(owner_id)
		for nest: Nest in backup:
			if nest.alive:
				world.occupy(nest.rect(), nest.owner_id())
		return false
	nests = loaded_nests
	boars = loaded_boars
	if not world_has_layer:
		for index: int in _covered_tiles(carcasses):
			world.fertility[index] = clampi(int(world.fertility[index]) - layer_at(index), 0, 255)
	carcasses = loaded_carcasses
	if not world_has_layer:
		for index: int in _covered_tiles(carcasses):
			world.fertility[index] = clampi(int(world.fertility[index]) + layer_at(index), 0, 255)
	for nest: Nest in nests:
		nest.boar_count = 0
	for boar: Boar in boars:
		var owner: Nest = nest_by_id(boar.nest_id)
		if owner != null:
			owner.boar_count += 1
	time = maxf(float(data.get("time", 0.0)), 0.0)
	steps_done = maxi(int(data.get("steps_done", 0)), 0)
	spawn_cursor = maxi(int(data.get("spawn_cursor", 0)), 0)
	next_nest_id = maxi(int(data.get("next_nest_id", 1)), 1)
	next_boar_id = maxi(int(data.get("next_boar_id", 1)), 1)
	for nest: Nest in nests:
		next_nest_id = maxi(next_nest_id, nest.id + 1)
	for boar: Boar in boars:
		next_boar_id = maxi(next_boar_id, boar.id + 1)
	total_spawned = maxi(int(data.get("total_spawned", 0)), 0)
	total_gnawed = maxi(int(data.get("total_gnawed", 0)), 0)
	total_killed = maxi(int(data.get("total_killed", 0)), 0)
	total_carcasses = maxi(int(data.get("total_carcasses", 0)), 0)
	total_nests_destroyed = maxi(int(data.get("total_nests_destroyed", 0)), 0)
	next_carcass_id = maxi(int(data.get("next_carcass_id", 1)), 1)
	for carcass: Carcass in carcasses:
		next_carcass_id = maxi(next_carcass_id, carcass.id + 1)
	return true
