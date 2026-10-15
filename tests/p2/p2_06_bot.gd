extends "res://tests/p1/p1_06_bot.gd"
## P2-06 test rig and fighting bot (headless, no rendering). Extends the P1-06 bot rig with the P2 game logic wired the way main.gd
## wires it: EnemyField (nests, boars, carcasses), ZoneProgress, EnemyCombat (shot hits and drops), FarSeedSim on the spread tick,
## the damage state (PlayerHealth through PlayState.advance), the stable-zone spread bonus at its shipped value.
##
## The bot only uses what a player has: moving (Walker.move at the player's speed), aiming and firing (fire(): seed / water / a cultivated
## plant after select_index), picking up what lies on the ground (walking over it). It never writes game state. No randomness.
##
## Priorities (checked between tasks; the reflexes run every step):
##   reflex   a boar within reflex_range_px -> fire a seed at it (lead aimed); a boar within evade_px -> step away from it
##   0 heal   HP low -> walk to the nearest healing fruit (kiwi), else to the nearest mature kiwi and wait for a fruit
##   1 P1 loop: no seed -> collect / wait; water; seed fruits lying close by; low seeds -> detour to fruits
##   2 kiwi / carrot placement when due
##   3 assault the nearest living nest within assault_trigger_tiles (needs HP and seeds), walk into range, shoot it down
##   4 hunt boars left in a clearing zone (a zone turns stable only when none is left)
##   5 plant the nearest untouched cell (not inside a zone that still has a nest unless plant_in_hostile)
##   6 nothing to plant -> assault the nearest nest wherever it is
## Being downed: the bot waits (no control), is put back at the start by the game (PlayerHealth.revived) and goes on.


var enemy_tuning: EnemyTuning
var enemies: EnemyField
var progress: ZoneProgress
var combat: EnemyCombat
var far: FarSeedSim

# ---- policy (bot parameters, not game data) ----
var kiwi_on: bool = true
var plant_in_hostile: bool = false
var assault_trigger_tiles: float = 60.0
var assault_range_px: float = 64.0
var assault_min_seeds: int = 22
var assault_min_hp: int = 6
var assault_timeout: float = 150.0
var reflex_range_px: float = 85.0
var evade_px: float = 20.0
var hp_low: int = 4
var collect_near_px: float = 60.0
var hunt_range_px: float = 56.0
var hunt_timeout: float = 45.0
var kiwi_interval: float = 100.0
var kiwi_max_count: int = 5
var kiwi_min_seeds: int = 18
var kiwi_ready_seconds: float = 40.0
## A cell of the planting grid within this share of a mature carrot's radius is left to the spread (0 = the bot plants there anyway).
var carrot_skip_fraction: float = 0.0

# ---- state ----
var assault_id: int = -1
var hunt_boar: Boar = null
var nest_skip: Dictionary = {}
var boar_skip: Dictionary = {}
var last_kiwi_time: float = -1000.0
var next_kiwi_search: float = 0.0
var heal_wait_started: float = -1.0
var _was_downed: bool = false

# ---- statistics (P2) ----
var down_times: Array = []
var stable_at: Dictionary = {}
var clearing_at: Dictionary = {}
var complete_at: Dictionary = {}
var cleared_at: float = -1.0
var all_stable_at: float = -1.0
var kiwis_placed: int = 0
var shots_at_boars: int = 0
var shots_at_nests: int = 0
var shot_hits: int = 0
var assaults_started: int = 0
var assaults_given_up: int = 0
var hunts_started: int = 0
var evade_steps: int = 0
var carrot_skips: int = 0
var worst_enemy_us: int = 0
var worst_far_us: int = 0
var worst_total_us: int = 0
var _far_us_this_step: int = 0

func _init(sim_overrides: Dictionary = {}, play_overrides: Dictionary = {}, enemy_overrides: Dictionary = {}, bot_overrides: Dictionary = {}) -> void:
	super(sim_overrides, play_overrides)
	# P2-05 pinned the stable-zone bonus off for the P1 bots; here it is the shipped value unless the caller sets it.
	if not sim_overrides.has("stable_spread_multiplier"):
		sim_tuning.stable_spread_multiplier = (load("res://data/sim_tuning.tres") as SimTuning).stable_spread_multiplier
	enemy_tuning = (load("res://data/enemy_tuning.tres") as EnemyTuning).duplicate() as EnemyTuning
	for key: String in enemy_overrides:
		enemy_tuning.set(key, enemy_overrides[key])
	for key: String in bot_overrides:
		set(key, bot_overrides[key])
	far = FarSeedSim.new(world, sim_tuning)
	clock.spread_ticked.connect(_on_spread_ticked_far)
	enemies = EnemyField.new(world, enemy_tuning, TILE)
	enemies.setup_nests(region_def.zones)
	progress = ZoneProgress.new(world, enemies)
	spread.allow_hook = enemies.spread_allows
	combat = EnemyCombat.new(enemies, play)
	play.enemies = enemies
	play.health.respawn_position = pos
	play.health.knocked.connect(_on_knocked)
	play.health.revived.connect(_on_revived)
	world.zone_state_changed.connect(_on_zone_state)
	progress.cleared.connect(_on_cleared)
	progress.start()
	world.clear_dirty()
	last_stage = world.stage.duplicate()

func _on_spread_ticked_far(_i: int) -> void:
	var t0: int = Time.get_ticks_usec()
	far.tick()
	_far_us_this_step += Time.get_ticks_usec() - t0

func _on_knocked(motion: Vector2) -> void:
	pos = Walker.move(world, TILE, pos, motion, half)

func _on_revived(location: Vector2) -> void:
	pos = location
	task = ""
	path = PackedInt32Array()
	_waypoint = Vector2.INF
	_goal_pos = Vector2.INF
	pending_water = Vector2.INF
	assault_id = -1
	hunt_boar = null
	flights.clear()

func _on_zone_state(zone: int, _old: int, new_state: int) -> void:
	if new_state == WorldState.ZONE_CLEARING:
		clearing_at[zone] = time
	elif new_state == WorldState.ZONE_STABLE:
		stable_at[zone] = time
		if all_stable_at < 0.0:
			var all: bool = true
			for z: int in world.zone_count:
				if world.zone_state[z] < WorldState.ZONE_STABLE:
					all = false
			if all:
				all_stable_at = time
	elif new_state == WorldState.ZONE_COMPLETE:
		complete_at[zone] = time

func _on_cleared() -> void:
	cleared_at = time

func is_complete() -> bool:
	return world.cleared

# ---------------------------------------------------------------------------------------------------------------
# Stepping
# ---------------------------------------------------------------------------------------------------------------

func step(dt: float) -> void:
	steps += 1
	time += dt
	var downed: bool = play.health.downed
	if downed and not _was_downed:
		down_times.append(snappedf(time, 0.1))
	_was_downed = downed
	if bot_on and not done and not downed:
		_bot(dt)
	_flights()
	var t0: int = Time.get_ticks_usec()
	_far_us_this_step = 0
	play.advance(dt, pos)
	var t1: int = Time.get_ticks_usec()
	enemies.advance(dt)
	var t2: int = Time.get_ticks_usec()
	clock.advance(dt)
	if view != null:
		view.flush(sim_tuning.render_tiles_per_frame)
	last_logic_us = Time.get_ticks_usec() - t0
	worst_enemy_us = maxi(worst_enemy_us, t2 - t1)
	worst_far_us = maxi(worst_far_us, _far_us_this_step)
	worst_total_us = maxi(worst_total_us, last_logic_us)
	_track()
	peak_pickups = maxi(peak_pickups, play.pickups.count())
	if play.available_seeds() < 1 and bot_on and not done and not play.health.downed:
		stall_total += dt
		stall_current += dt
		stall_longest = maxf(stall_longest, stall_current)
	else:
		if stall_current > 0.0:
			stall_log.append([snappedf(time - stall_current, 0.1), snappedf(stall_current, 0.1)])
		stall_current = 0.0

func snapshot() -> Dictionary:
	var s: Dictionary = super()
	s["kills"] = enemies.total_killed
	s["nests_left"] = enemies.alive_nest_count()
	s["boars"] = enemies.boars.size()
	s["downs"] = play.health.down_count
	s["hp"] = play.hp
	var states: Array = []
	for z: int in world.zone_count:
		states.append(int(world.zone_state[z]))
	s["zones"] = states
	return s

# ---------------------------------------------------------------------------------------------------------------
# Shots (with enemy hits, like ProjectileField)
# ---------------------------------------------------------------------------------------------------------------

func fire(kind: String, aim_point: Vector2) -> bool:
	if cooldown > 0.0 or play.health.downed:
		return false
	var offset: Vector2 = aim_point - pos
	var direction: Vector2 = offset.normalized() if offset.length_squared() > 0.0001 else Vector2.RIGHT
	var distance: float = minf(offset.length(), play_tuning.projectile_range_px)
	var landing: Vector2 = pos + direction * distance
	if kind == ProjectileField.KIND_WATER:
		if not play.can_fire_water():
			return false
		play.spend_water()
		shots_water += 1
	elif kind == ProjectileField.KIND_SEED:
		if not play.can_fire_seed():
			return false
		play.spend_seed()
		shots_seed += 1
	else:
		var def: PlantDef = play.def_by_key(StringName(kind))
		if def == null or not play.can_fire_plant(def):
			return false
		play.select_index(play.selectable.find(def))
		play.reserve_plant(def)
		shots_carrot += 1
	flights.append({"kind": kind, "position": pos, "target": landing, "direction": direction, "total": distance, "traveled": 0.0, "age": 0.0})
	cooldown = fire_interval
	return true

func _flights() -> void:
	var dt_s: float = 0.0
	if steps > 0:
		dt_s = time - _last_flight_time
	_last_flight_time = time
	if dt_s <= 0.0:
		return
	var index: int = flights.size() - 1
	while index >= 0:
		var shot: Dictionary = flights[index]
		shot["age"] = float(shot["age"]) + dt_s
		var from: Vector2 = shot["position"]
		var remaining: float = float(shot["total"]) - float(shot["traveled"])
		var step_len: float = play_tuning.projectile_speed * dt_s
		var arrives: bool = step_len >= remaining
		var to: Vector2 = Vector2(shot["target"]) if arrives else from + Vector2(shot["direction"]) * step_len
		var kind: String = String(shot["kind"])
		var hit: Dictionary = combat.hit_provider(shot, from, to)
		if not hit.is_empty():
			flights.remove_at(index)
			shot_hits += 1
			combat.on_enemy_hit(kind, Vector2(hit.get("point", to)), hit)
			if kind != ProjectileField.KIND_WATER and kind != ProjectileField.KIND_SEED:
				play.cancel_plant(StringName(kind))
		else:
			shot["traveled"] = float(shot["traveled"]) + (remaining if arrives else step_len)
			shot["position"] = to
			if arrives:
				flights.remove_at(index)
				if kind == ProjectileField.KIND_WATER:
					play.land_water(to)
				elif kind == ProjectileField.KIND_SEED:
					play.land_seed(to)
				else:
					var plant: CultivatedPlant = play.land_plant(StringName(kind), to)
					if plant != null:
						if kind == "kiwi":
							kiwis_placed += 1
						else:
							carrots_placed += 1
			elif float(shot["age"]) > play_tuning.projectile_max_age:
				flights.remove_at(index)
				if kind != ProjectileField.KIND_WATER and kind != ProjectileField.KIND_SEED:
					play.cancel_plant(StringName(kind))
		index -= 1

var _last_flight_time: float = 0.0

# ---------------------------------------------------------------------------------------------------------------
# Bot
# ---------------------------------------------------------------------------------------------------------------

func _bot(dt: float) -> void:
	cooldown = maxf(cooldown - dt, 0.0)
	_reflex_fire()
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
			_do_block("carrot")
		"kiwi":
			_do_block("kiwi")
		"water":
			_do_water()
		"idle":
			_do_idle()
		"assault":
			_do_assault()
		"hunt":
			_do_hunt()
		"heal":
			_do_heal()
	if _evade(dt):
		return
	_move(dt)

## Nearest boar to the bot by body distance, or null.
func _nearest_boar() -> Boar:
	var best: Boar = null
	var best_distance: float = INF
	for boar: Boar in enemies.boars:
		var d: float = enemies.boar_body_center(boar).distance_squared_to(pos)
		if d < best_distance:
			best_distance = d
			best = boar
	return best

## Velocity of a boar in px/s from its walking goal (it walks straight to it at boar_speed_px).
func _boar_velocity(boar: Boar) -> Vector2:
	if boar.goal == Vector2.INF or boar.wait > 0:
		return Vector2.ZERO
	var to: Vector2 = boar.goal - boar.pos
	if to.length() < enemy_tuning.arrival_px:
		return Vector2.ZERO
	return to.normalized() * enemy_tuning.boar_speed_px

func _reflex_fire() -> void:
	if cooldown > 0.0 or play.available_seeds() < 1:
		return
	var boar: Boar = _nearest_boar()
	if boar == null:
		return
	var centre: Vector2 = enemies.boar_body_center(boar)
	if centre.distance_to(pos) > reflex_range_px:
		return
	var velocity: Vector2 = _boar_velocity(boar)
	var aim: Vector2 = centre
	for pass_index: int in 2:
		var flight_time: float = aim.distance_to(pos) / play_tuning.projectile_speed
		aim = centre + velocity * flight_time
	if fire(ProjectileField.KIND_SEED, aim):
		shots_at_boars += 1

## Steps away from a boar that is too close. True when the step replaced this step's move.
func _evade(dt: float) -> bool:
	var boar: Boar = _nearest_boar()
	if boar == null:
		return false
	var centre: Vector2 = enemies.boar_body_center(boar)
	if centre.distance_to(pos) > evade_px:
		return false
	var away: Vector2 = pos - centre
	if away.length_squared() < 0.01:
		away = Vector2.LEFT
	pos = Walker.move(world, TILE, pos, away.normalized() * FlowerPlayer.SPEED * dt, half)
	evade_steps += 1
	walk_time += dt
	return true

func _heal_fruit() -> Vector2:
	var best: Vector2 = Vector2.INF
	var best_distance: float = INF
	for item: Dictionary in play.pickups.items:
		if String(item["kind"]) != GroundPickups.KIND_HEAL_FRUIT:
			continue
		var point: Vector2 = Vector2(float(item["x"]), float(item["y"]))
		var d: float = point.distance_squared_to(pos)
		if d < best_distance and nav_ok[cell_of(point)] == 1:
			best_distance = d
			best = point
	return best

func _mature_kiwi() -> Vector2:
	var best: Vector2 = Vector2.INF
	var best_distance: float = INF
	for plant: CultivatedPlant in play.cultivation.plants:
		if plant.key != &"kiwi" or not plant.mature:
			continue
		var point: Vector2 = (Vector2(plant.tile) + Vector2(plant.size, plant.size) * 0.5) * TILE
		var d: float = point.distance_squared_to(pos)
		if d < best_distance and nav_ok[cell_of(point)] == 1:
			best_distance = d
			best = point
	return best

## True when a healing fruit lies on the ground or a mature kiwi stands somewhere the bot can walk to.
func _heal_available() -> bool:
	return _heal_fruit() != Vector2.INF or _mature_kiwi() != Vector2.INF

func _nearest_seed_fruit_within(radius: float) -> Vector2:
	var best: Vector2 = _nearest_fruit()
	if best != Vector2.INF and best.distance_to(pos) <= radius:
		return best
	return Vector2.INF

func _choose() -> void:
	var seeds: int = play.available_seeds()
	# 0: low HP
	if play.hp <= hp_low:
		var fruit: Vector2 = _heal_fruit()
		if fruit != Vector2.INF and fruit.distance_to(pos) <= 500.0:
			_set_task("heal")
			return
		var kiwi: Vector2 = _mature_kiwi()
		if kiwi != Vector2.INF and kiwi.distance_to(pos) <= 700.0:
			_set_task("heal")
			return
	# 1: the P1 loop
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
	if seeds < seed_max_minus() and _nearest_seed_fruit_within(collect_near_px) != Vector2.INF:
		_set_task("collect")
		return
	if seeds < seeds_low:
		var far_fruit: Vector2 = _nearest_fruit()
		if far_fruit != Vector2.INF and far_fruit.distance_to(pos) <= detour_px:
			_set_task("collect")
			return
	# 2: placements
	if kiwi_on and seeds >= kiwi_min_seeds and time - last_kiwi_time >= kiwi_interval and play.cultivation.count(&"kiwi") + _inflight(&"kiwi") < kiwi_max_count and _pick_kiwi_target():
		_set_task("kiwi")
		return
	if carrots_on and seeds >= carrot_min_seeds and time - last_carrot_time >= carrot_interval and _pick_carrot_target():
		_set_task("carrot")
		return
	# 3: assault a close nest
	var nest: Nest = _pick_nest(assault_trigger_tiles * TILE)
	if nest != null and (play.hp >= assault_min_hp or not _heal_available()):
		if seeds >= assault_min_seeds:
			_begin_assault(nest)
			return
		var fruit_for_assault: Vector2 = _nearest_fruit()
		if fruit_for_assault != Vector2.INF and fruit_for_assault.distance_to(pos) <= detour_px and seeds < assault_min_seeds:
			_set_task("collect")
			return
		if seeds >= 12:
			_begin_assault(nest)
			return
	# 4: hunt the boars of a clearing zone
	var target_boar: Boar = _pick_boar()
	if target_boar != null:
		hunt_boar = target_boar
		hunts_started += 1
		_set_task("hunt")
		return
	# 5: plant
	if _pick_target():
		_set_task("plant")
		return
	# 6: nothing to plant: any nest
	var any_nest: Nest = _pick_nest(INF)
	if any_nest != null and (play.hp >= assault_min_hp or not _heal_available()) and seeds >= 12:
		_begin_assault(any_nest)
		return
	if is_complete():
		done = true
	_set_task("idle")

func seed_max_minus() -> int:
	return play.tuning.seed_max - 1

func _inflight(key: StringName) -> int:
	return int(play.inflight.get(key, 0))

# ---- assault / hunt / heal --------------------------------------------------------------------------------------

func _pick_nest(max_distance: float) -> Nest:
	var best: Nest = null
	var best_distance: float = INF
	for nest: Nest in enemies.nests:
		if not nest.alive or float(nest_skip.get(nest.id, -1.0)) > time:
			continue
		var d: float = nest.center_px(TILE).distance_to(pos)
		if d < best_distance and d <= max_distance:
			best_distance = d
			best = nest
	return best

func _begin_assault(nest: Nest) -> void:
	assault_id = nest.id
	assaults_started += 1
	_set_task("assault")

func _do_assault() -> void:
	var nest: Nest = enemies.nest_by_id(assault_id)
	if nest == null or not nest.alive:
		task = ""
		return
	if time - task_started > assault_timeout:
		nest_skip[nest.id] = time + 60.0
		assaults_given_up += 1
		task = ""
		return
	if play.available_seeds() < 1 or (play.hp <= hp_low and _heal_available()):
		task = ""
		return
	var centre: Vector2 = nest.center_px(TILE)
	if pos.distance_to(centre) > assault_range_px + 4.0:
		_goto_range(centre, assault_range_px)
		if task == "":
			nest_skip[nest.id] = time + 90.0
			assaults_given_up += 1
		return
	path = PackedInt32Array()
	_waypoint = Vector2.INF
	if cooldown <= 0.0 and fire(ProjectileField.KIND_SEED, centre):
		shots_at_nests += 1

func _pick_boar() -> Boar:
	var best: Boar = null
	var best_distance: float = INF
	for boar: Boar in enemies.boars:
		if float(boar_skip.get(boar.id, -1.0)) > time:
			continue
		var state: int = world.zone_state[boar.zone]
		var d: float = enemies.boar_body_center(boar).distance_to(pos)
		var wanted: bool = state == WorldState.ZONE_CLEARING or d <= 220.0
		if wanted and d < best_distance:
			best_distance = d
			best = boar
	return best

func _do_hunt() -> void:
	if hunt_boar == null or enemies.boars.find(hunt_boar) < 0:
		hunt_boar = null
		task = ""
		return
	if time - task_started > hunt_timeout:
		boar_skip[hunt_boar.id] = time + 40.0
		hunt_boar = null
		task = ""
		return
	if play.available_seeds() < 1:
		task = ""
		return
	var centre: Vector2 = enemies.boar_body_center(hunt_boar)
	if pos.distance_to(centre) > hunt_range_px:
		# The target moves: plan again every second.
		_goto_range(centre, hunt_range_px)
		if task == "":
			boar_skip[hunt_boar.id] = time + 40.0
			hunt_boar = null
		return
	path = PackedInt32Array()
	_waypoint = Vector2.INF

func _do_heal() -> void:
	if play.hp > hp_low + 2 or time - task_started > 60.0:
		task = ""
		heal_wait_started = -1.0
		return
	var fruit: Vector2 = _heal_fruit()
	if fruit != Vector2.INF:
		heal_wait_started = -1.0
		if fruit.distance_to(pos) <= 5.0:
			return
		_goto_point(fruit)
		return
	var kiwi: Vector2 = _mature_kiwi()
	if kiwi == Vector2.INF:
		task = ""
		return
	if kiwi.distance_to(pos) > 18.0:
		_goto_point(kiwi + Vector2(0, 10))
		return
	# Waiting next to a kiwi for its next fruit.
	path = PackedInt32Array()
	_waypoint = Vector2.INF

# ---- cultivated plants (carrot: parent scoring; kiwi: near the nearest living nest) ------------------------------

func _pick_kiwi_target() -> bool:
	var def: PlantDef = play.def_by_key(&"kiwi")
	if def == null or not play.can_fire_plant(def):
		return false
	if time < next_kiwi_search:
		return false
	next_kiwi_search = time + 8.0
	var nest: Nest = _pick_nest(INF)
	var best: Vector2 = Vector2.INF
	var best_distance: float = INF
	for radius: float in [24.0, 44.0, 64.0]:
		for k: int in 16:
			var sample: Vector2 = pos + Vector2.from_angle(TAU * k / 16.0) * radius
			var tile: Vector2i = Vector2i(floori(sample.x / TILE), floori(sample.y / TILE))
			if not play.cultivation.block_valid(tile, 2):
				continue
			var centre: Vector2 = (Vector2(tile) + Vector2(1, 1)) * TILE
			var d: float = centre.distance_to(nest.center_px(TILE)) if nest != null else centre.distance_to(pos)
			if d < best_distance:
				best_distance = d
				best = centre
	if best == Vector2.INF:
		return false
	task_target = best
	return true

func _do_block(kind: String) -> void:
	if pos.distance_to(task_target) > stand_range_px:
		_goto_range(task_target, stand_range_px)
		return
	if fire(kind, task_target):
		if kind == "kiwi":
			last_kiwi_time = time
		else:
			last_carrot_time = time
		task = ""
	elif time - task_started > 30.0:
		task = ""

# ---- planting (the P1 pick with the zone filter) -----------------------------------------------------------------

func _cell_allowed(g: int, cell: int) -> bool:
	var size: int = cell_tiles[g]
	var gw: int = grid_w[g]
	var x: int = mini((cell % gw) * size + size / 2, world.width - 1)
	var y: int = mini((cell / gw) * size + size / 2, world.height - 1)
	if carrot_skip_fraction > 0.0 and carrots_on and size >= 8:
		for plant: CultivatedPlant in play.cultivation.plants:
			if plant.key == &"carrot" and plant.mature:
				var def: PlantDef = play.def_by_key(&"carrot")
				if plant.center_tiles().distance_to(Vector2(x, y)) <= def.effect_radius_tiles * carrot_skip_fraction:
					carrot_skips += 1
					return false
	if plant_in_hostile:
		return true
	return world.zone_state[world.zone_of[world.index_of(x, y)]] != WorldState.ZONE_UNCONQUERED

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
			if d < best_distance and _cell_allowed(g, cell):
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
