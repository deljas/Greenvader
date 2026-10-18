extends RefCounted
## POC-09 test-side walking / shooting bot. It drives a PocSession ONLY through its public operation API
## (walk(), fire(), advance_game(), set_aim()). No debug refill, no direct writes to play / world / enemy state.
## One frame = walk(DT) then advance_game(DT) (the same order as PocMain.tick()).
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const GroundPickupsScript: GDScript = preload("res://scripts/play/ground_pickups.gd")

const DT: float = 0.1
const FIRE_GAP: float = 0.25
const ENGAGE_PX: float = 40.0
const COLLECT_PX: float = 12.0

var s: RefCounted
var clear: PackedByteArray = PackedByteArray()
var width: int = 0
var height: int = 0
var frames: int = 0
var engage: bool = true
var stop_when: Callable = Callable()
var stopped: bool = false
var guard_until: float = 1.0e9
var fire_ready_at: float = 0.0
var seed_shots: int = 0
var water_shots: int = 0
var down_times: Array[float] = []
var gain_by_class: Dictionary = {"source": 0, "plant": 0, "enemy": 0}
var rows: Array[Dictionary] = []
var log_every: float = 10.0
var next_log: float = 0.0
var events: PackedStringArray = PackedStringArray()
var min_seeds: int = 1 << 30
var min_water: float = 1.0e9
var min_hp: int = 1 << 30
var walked_px: float = 0.0
var no_input_mode: bool = false

func _init(session: RefCounted) -> void:
	s = session
	width = s.state.width
	height = s.state.height
	var half: Vector2 = Config.player_half_px()
	clear.resize(width * height)
	for y: int in height:
		for x: int in width:
			clear[y * width + x] = 1 if Walker.is_clear(s.state, Config.TILE_PX, cpx(Vector2i(x, y)), half) else 0
	s.play.health.downed_started.connect(_on_down)

func detach() -> void:
	for connection: Dictionary in s.play.health.downed_started.get_connections():
		if (connection["callable"] as Callable).get_object() == self:
			s.play.health.downed_started.disconnect(connection["callable"])

func _on_down() -> void:
	down_times.append(s.clock.elapsed)
	events.append("t=%.1f downed (hp=0) at cell %s" % [s.clock.elapsed, Coords.logic_to_cell(s.position)])

static func cpx(cell: Vector2i) -> Vector2:
	return Coords.cell_center_logic(cell)

func cell_now() -> Vector2i:
	return Coords.logic_to_cell(s.position)

func is_clear_cell(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height and clear[c.y * width + c.x] == 1

func nearest_clear(c: Vector2i) -> Vector2i:
	for r: int in 12:
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var n: Vector2i = c + Vector2i(dx, dy)
				if is_clear_cell(n):
					return n
	return c

## BFS distance (in cells, 4-neighbour) from `goal` over cells the player body fits; -1 elsewhere.
func field_from(goal: Vector2i) -> PackedInt32Array:
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(width * height)
	dist.fill(-1)
	var g: Vector2i = goal if is_clear_cell(goal) else nearest_clear(goal)
	var queue: PackedInt32Array = PackedInt32Array([g.y * width + g.x])
	dist[g.y * width + g.x] = 0
	var head: int = 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var x: int = i % width
		var y: int = i / width
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				continue
			var j: int = ny * width + nx
			if clear[j] == 0 or dist[j] != -1:
				continue
			dist[j] = dist[i] + 1
			queue.append(j)
	return dist

func _class_counts() -> Dictionary:
	var out: Dictionary = {"source": 0, "plant": 0, "enemy": 0}
	for item: Dictionary in s.play.pickups.items:
		if String(item["kind"]) != GroundPickupsScript.KIND_SEED_FRUIT:
			continue
		if Vector2(float(item["x"]), float(item["y"])).distance_to(s.position) > COLLECT_PX:
			continue
		var owner_id: int = int(item["owner"])
		var key: String = "source"
		if owner_id >= GroundPickupsScript.ENEMY_OWNER_BASE:
			key = "enemy"
		elif owner_id >= GroundPickupsScript.PLANT_OWNER_BASE:
			key = "plant"
		out[key] = int(out[key]) + 1
	return out

## One game frame. `screen_dir` is the walking input (zero = standing).
func frame(screen_dir: Vector2 = Vector2.ZERO) -> void:
	var before_pos: Vector2 = s.position
	s.walk(screen_dir, DT)
	walked_px += s.position.distance_to(before_pos)
	var seeds_before: int = s.play.seeds
	var near_before: Dictionary = _class_counts()
	s.advance_game(DT)
	var near_after: Dictionary = _class_counts()
	if s.play.seeds > seeds_before and not s.play.health.downed:
		for key: String in near_before:
			var gone: int = int(near_before[key]) - int(near_after[key])
			if gone > 0:
				gain_by_class[key] = int(gain_by_class[key]) + gone
	frames += 1
	min_seeds = mini(min_seeds, s.play.seeds)
	min_water = minf(min_water, s.play.water)
	min_hp = mini(min_hp, s.play.hp)
	if s.clock.elapsed >= next_log:
		next_log = s.clock.elapsed + log_every
		rows.append(snapshot_row())
	if stop_when.is_valid() and bool(stop_when.call()):
		stopped = true
	if s.clock.elapsed > guard_until:
		stopped = true
		events.append("GUARD: game-time limit %.0f s hit" % guard_until)

func snapshot_row() -> Dictionary:
	var st: WorldState = s.state
	return {
		"t": snappedf(s.clock.elapsed, 0.1),
		"hour": snappedf(s.day_hour(), 0.01),
		"seeds": s.play.seeds,
		"water": snappedf(s.play.water, 0.1),
		"hp": s.play.hp,
		"downed": s.play.health.downed,
		"greened": st.greened_count,
		"targets": st.target_count,
		"pct": s.greening_percent(),
		"zone0": int(st.zone_state[0]),
		"zone1": int(st.zone_state[1]),
		"nests": s.enemies.alive_nest_count(-1),
		"boars": s.enemies.boars.size(),
		"pos": [snappedf(s.position.x, 0.1), snappedf(s.position.y, 0.1)],
		"pickups": s.play.pickups.count(),
		"shots": s.projectiles.shots.size(),
	}

func idle(seconds: float) -> void:
	var left: float = seconds
	while left > 0.0 and not stopped:
		if engage and _fight():
			left -= DT
			continue
		frame()
		left -= DT

## Shoots the nearest boar in range with a clear line. Returns true when it handled this frame (a frame was advanced).
func _fight() -> bool:
	if s.play.health.downed or not s.play.can_fire_seed():
		return false
	var best: Boar = null
	var best_d: float = ENGAGE_PX
	for boar: Boar in s.enemies.boars:
		var d: float = boar.pos.distance_to(s.position)
		if d <= best_d and not s.shot_blocked(s.position, boar.pos):
			best = boar
			best_d = d
	if best == null:
		return false
	try_fire(false, best.pos)
	frame()
	return true

func try_fire(water_shot: bool, target: Vector2) -> bool:
	if s.clock.elapsed < fire_ready_at:
		return false
	var result: Dictionary = s.fire(water_shot, target)
	if bool(result["ok"]):
		fire_ready_at = s.clock.elapsed + FIRE_GAP
		if water_shot:
			water_shots += 1
		else:
			seed_shots += 1
		return true
	return false

## Moves one frame along `field` toward its goal cell. Returns the remaining cell distance (or -1 when unknown).
func step_along(field: PackedInt32Array, goal: Vector2i) -> int:
	var c: Vector2i = cell_now()
	var here: int = field[c.y * width + c.x] if c.x >= 0 and c.y >= 0 and c.x < width and c.y < height else -1
	var target: Vector2 = cpx(goal)
	if here > 0 or here == -1:
		var best: Vector2i = Vector2i(-1, -1)
		var best_d: int = here if here > 0 else (1 << 30)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= width or n.y >= height:
				continue
			var v: int = field[n.y * width + n.x]
			if v >= 0 and v < best_d:
				best_d = v
				best = n
		if best.x >= 0:
			target = cpx(best)
	var ground: Vector2 = target - s.position
	if ground.length() < 0.2:
		frame()
		return here
	frame(Coords.ground_dir_to_screen(ground.normalized()))
	return here

## Walks to `goal` (fights boars on the way). True when within `arrive_px`.
func go(goal: Vector2i, timeout: float = 150.0, arrive_px: float = 3.0) -> bool:
	var field: PackedInt32Array = field_from(goal)
	var t0: float = s.clock.elapsed
	var target: Vector2 = cpx(goal)
	while not stopped and s.clock.elapsed - t0 < timeout:
		if s.play.health.downed:
			frame()
			continue
		if engage and _fight():
			continue
		if s.position.distance_to(target) <= arrive_px:
			return true
		step_along(field, goal)
	return s.position.distance_to(target) <= arrive_px

func source_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for value: Variant in s.combat_setup.get("seed_sources", []):
		out.append(Vector2i(int(value[0]), int(value[1])))
	return out

func nearest_source_cell() -> Vector2i:
	var best: Vector2i = Vector2i.ZERO
	var best_d: float = 1.0e12
	for c: Vector2i in source_cells():
		var d: float = cpx(c).distance_to(s.position)
		if d < best_d:
			best_d = d
			best = c
	return best

## Round trip to a seed source and wait (standing) until `target_seeds` is reached. Returns the waiting seconds.
func restock(target_seeds: int, timeout: float = 240.0) -> float:
	var source: Vector2i = nearest_source_cell()
	var t_start: float = s.clock.elapsed
	events.append("t=%.1f restock: go to source %s with seeds=%d (target %d)" % [t_start, source, s.play.seeds, target_seeds])
	go(source, 200.0, 2.0)
	var t_arrive: float = s.clock.elapsed
	while not stopped and s.play.seeds < target_seeds and s.clock.elapsed - t_arrive < timeout:
		idle(1.0)
	events.append("t=%.1f restock done: seeds=%d (wait %.1f s)" % [s.clock.elapsed, s.play.seeds, s.clock.elapsed - t_arrive])
	return s.clock.elapsed - t_arrive

## Standing cell 4..8 cells from `center_px` with a clear shot line, nearest (path) to the player; `skip` holds rejected cells.
func shoot_spot(center_px: Vector2, skip: Array[Vector2i]) -> Vector2i:
	var from_player: PackedInt32Array = field_from(cell_now())
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 1 << 30
	for y: int in height:
		for x: int in width:
			var v: int = from_player[y * width + x]
			if v < 0 or v >= best_d:
				continue
			var c: Vector2i = Vector2i(x, y)
			var d_px: float = cpx(c).distance_to(center_px)
			if d_px < 4.0 * Config.TILE_PX + 8.0 or d_px > 8.0 * Config.TILE_PX or skip.has(c):
				continue
			if s.shot_blocked(cpx(c), center_px):
				continue
			best_d = v
			best = c
	return best

## Walks to a firing spot and shoots the nest until it is destroyed. Returns "dead", "no_seeds" or "fail".
func kill_nest(nest: Nest, max_seconds: float = 300.0) -> String:
	var center: Vector2 = nest.center_px(Config.TILE_PX)
	var skip: Array[Vector2i] = []
	var t0: float = s.clock.elapsed
	var attempts: int = 0
	while nest.alive and not stopped and s.clock.elapsed - t0 < max_seconds and attempts < 4:
		attempts += 1
		var spot: Vector2i = shoot_spot(center, skip)
		if spot.x < 0:
			return "fail"
		events.append("t=%.1f nest %d: go to spot %s (hp %d/%d, seeds %d)" % [s.clock.elapsed, nest.id, spot, nest.hp, nest.hp_max, s.play.seeds])
		if not go(spot, 120.0, 2.5):
			skip.append(spot)
			continue
		var hp_at_arrival: int = nest.hp
		var shots_here: int = 0
		while nest.alive and not stopped and s.clock.elapsed - t0 < max_seconds:
			if s.play.health.downed:
				frame()
				continue
			if engage and _fight():
				continue
			if s.play.seeds < 1:
				return "no_seeds"
			if s.position.distance_to(cpx(spot)) > 6.0:
				break
			if try_fire(false, center):
				shots_here += 1
			frame()
			if shots_here >= 30 and nest.hp >= hp_at_arrival:
				skip.append(spot)
				break
	return "dead" if not nest.alive else "fail"

## Hunts boars until none are left (or `max_seconds`). Returns the number of boars shot down by this call.
func hunt_boars(max_seconds: float = 400.0) -> int:
	var t0: float = s.clock.elapsed
	var killed_before: int = s.enemies.total_killed
	var field: PackedInt32Array = PackedInt32Array()
	var field_for: Vector2i = Vector2i(-1, -1)
	var field_age: int = 1 << 30
	while not stopped and not s.enemies.boars.is_empty() and s.clock.elapsed - t0 < max_seconds:
		if s.play.health.downed:
			frame()
			continue
		if s.play.seeds < 6:
			restock(14, 120.0)
			continue
		if _fight():
			continue
		var best: Boar = null
		var best_d: float = 1.0e12
		for boar: Boar in s.enemies.boars:
			var d: float = boar.pos.distance_to(s.position)
			if d < best_d:
				best_d = d
				best = boar
		var goal: Vector2i = Coords.logic_to_cell(best.pos)
		if field_age >= 10 or goal.distance_squared_to(field_for) > 9:
			field = field_from(goal)
			field_for = goal
			field_age = 0
		field_age += 1
		step_along(field, goal if is_clear_cell(goal) else nearest_clear(goal))
	return s.enemies.total_killed - killed_before

## Hand sowing from `stand` (safe-zone edge): walks there, picks up to `count` spaced target cells of zone 1 in throwing range and
## shoots one seed at each (and one water shot each when `water_each`). Returns {landing: Array[Vector2i], sown: PackedInt32Array}.
func sow(stand: Vector2i, count: int, water_each: bool) -> Dictionary:
	var st: WorldState = s.state
	go(stand, 60.0, 2.0)
	var landing: Array[Vector2i] = []
	for y: int in range(stand.y - 10, stand.y + 13):
		for x: int in range(stand.x - 20, stand.x - 1):
			if not st.in_bounds(x, y):
				continue
			var i: int = st.index_of(x, y)
			var c: Vector2i = Vector2i(x, y)
			var d_px: float = cpx(c).distance_to(cpx(stand))
			if landing.size() >= count or st.target[i] != 1 or st.zone_at(i) != 1 or st.stage[i] != WorldState.STAGE_EMPTY:
				continue
			if not (st.terrain[i] == Session.T_WASTE or st.terrain[i] == Session.T_PAVED) or d_px < 24.0 or d_px > 52.0 or s.shot_blocked(cpx(stand), cpx(c)):
				continue
			var spaced: bool = true
			for other: Vector2i in landing:
				if absi(other.x - c.x) < 3 and absi(other.y - c.y) < 3:
					spaced = false
			if spaced:
				landing.append(c)
	var before: PackedByteArray = st.stage.duplicate()
	for c: Vector2i in landing:
		while not try_fire(false, cpx(c)):
			frame()
		idle(0.4)
	idle(1.0)
	var sown: PackedInt32Array = PackedInt32Array()
	for i: int in st.tile_count():
		if before[i] == WorldState.STAGE_EMPTY and st.stage[i] >= WorldState.STAGE_SEED:
			sown.append(i)
	if water_each:
		for c: Vector2i in landing:
			while not try_fire(true, cpx(c)):
				frame()
			idle(0.4)
		idle(1.0)
	return {"landing": landing, "sown": sown}
