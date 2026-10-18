extends SceneTree
## POC-04 logic checks (headless OK). Run:
## godot --headless --path <repo> --script res://tests/poc/combat/logic.gd
## Long conditions are fast-forwarded with advance_game() in 0.25 s pieces; each condition runs once. No OS-level input.
## Contact damage is switched off only in the scenario where a bot has to clear the region (T6); everything else uses defaults.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")

var failures: int = 0
var passes: int = 0
var sessions: Array[RefCounted] = []
var report: PackedStringArray = []

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
		print("PASS ", name, " ", detail)
	else:
		failures += 1
		print("FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	_fixture()
	_wiring_and_pause()
	_spawn_and_walls()
	_hits_and_rewards()
	_carcass_cycle()
	_hit_order()
	_contact_and_revive()
	_determinism()
	_clear_stable_complete()
	for s: RefCounted in sessions:
		s.close()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)

func new_session() -> RefCounted:
	var s: RefCounted = Session.new()
	var ok: bool = s.load_combat()
	if not ok:
		print("FAIL load_combat")
	sessions.append(s)
	return s

func cpx(cell: Vector2i) -> Vector2:
	return Coords.cell_center_logic(cell)

func run_for(s: RefCounted, seconds: float) -> void:
	var left: float = seconds
	while left > 0.0:
		var piece: float = minf(left, 0.25)
		s.advance_game(piece)
		left -= piece

## 4-neighbour reachability from the start cell over cells where the player's feet fit. cell -> [distance, parent].
func reach_map(s: RefCounted) -> Dictionary:
	var start: Vector2i = Coords.logic_to_cell(s.position)
	var seen: Dictionary = {start: [0, Vector2i(-1, -1)]}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n) or not s.state.in_bounds(n.x, n.y):
				continue
			if not Walker.is_clear(s.state, Config.TILE_PX, cpx(n), Config.player_half_px()):
				continue
			seen[n] = [int(seen[c][0]) + 1, c]
			queue.append(n)
	return seen

## Reachable cell 4..8 cells from `target_px` with a clear shot line, nearest to the start. (-1,-1) if none.
func shoot_spot(s: RefCounted, reach: Dictionary, target_px: Vector2) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 1 << 30
	for key: Variant in reach.keys():
		var c: Vector2i = key
		var dist_px: float = cpx(c).distance_to(target_px)
		if dist_px < 4.0 * Config.TILE_PX + 8.0 or dist_px > 8.0 * Config.TILE_PX:
			continue
		if s.shot_blocked(cpx(c), target_px):
			continue
		if int(reach[c][0]) < best_d:
			best_d = int(reach[c][0])
			best = c
	return best

## Walks the player along the BFS parents to `goal` with the real walk() (collision included). Returns [arrived, steps].
func walk_to(s: RefCounted, reach: Dictionary, goal: Vector2i) -> Array:
	var path: Array[Vector2i] = []
	var c: Vector2i = goal
	while c != Vector2i(-1, -1):
		path.push_front(c)
		c = reach[c][1]
	var steps: int = 0
	for waypoint: Vector2i in path:
		var target: Vector2 = cpx(waypoint)
		var guard: int = 0
		while s.position.distance_to(target) > 1.2 and guard < 60:
			var ground: Vector2 = (target - s.position).normalized()
			s.walk(Coords.ground_dir_to_screen(ground), minf(0.1, s.position.distance_to(target) / Config.walk_speed_px()))
			guard += 1
			steps += 1
	return [s.position.distance_to(cpx(goal)) <= 1.5, steps]

func make_boar(s: RefCounted, at_px: Vector2, hp: int = 3) -> Boar:
	var nest: Nest = s.enemies.nests[0]
	var boar: Boar = Boar.new()
	boar.id = s.enemies.next_boar_id
	s.enemies.next_boar_id += 1
	boar.nest_id = nest.id
	boar.zone = 1
	boar.pos = at_px
	boar.home = nest.center_px(Config.TILE_PX)
	boar.hp = hp
	boar.rng = 7
	boar.wait = 1000000
	boar.think = 1000000
	nest.boar_count += 1
	s.enemies.boars.append(boar)
	return boar

func fire_volley(s: RefCounted, target: Vector2, count: int, pause: float = 0.25) -> int:
	var fired: int = 0
	for i: int in count:
		s.play.add_seeds(40)
		if bool(s.fire(false, target)["ok"]):
			fired += 1
		s.advance_game(pause)
	return fired

# ---------------------------------------------------------------- T1 fixture

func _fixture() -> void:
	var s: RefCounted = new_session()
	var st: WorldState = s.state
	check("fixture.zones", st.zone_count == 2 and st.zone_state[0] == WorldState.ZONE_COMPLETE and st.zone_state[1] == WorldState.ZONE_UNCONQUERED, "states=%s" % [st.zone_state])
	check("fixture.nests", s.enemies.nests.size() == 3 and s.enemies.alive_nest_count(1) == 3, "nests=%d" % s.enemies.nests.size())
	# Target set: exactly the open natural ground; buildings, water and sealed interiors are not in it.
	var expect: int = 0
	var bad: int = 0
	var building_or_water: int = 0
	for i: int in st.tile_count():
		var t: int = st.terrain[i]
		var open_ground: bool = t == Session.T_WASTE or t == Session.T_SAFE or t == Session.T_SHORE
		if open_ground:
			expect += 1
		if (t == Session.T_BUILDING or t == Session.T_WATER):
			building_or_water += 1
			if st.target[i] == 1:
				bad += 1
		if s.placement.obstacle[i] == 1 and st.target[i] == 1:
			bad += 1
	check("fixture.target_set_excludes_building_water_sealed", bad == 0 and building_or_water > 0 and s.placement.sealed_count > 0 and expect == st.target_count and st.counters_consistent(), "targets=%d expect=%d excluded=%d sealed=%d" % [st.target_count, expect, building_or_water, s.placement.sealed_count])
	# The island: a target, not reachable by walking, farther than the spread radius from every other target cell.
	var reach: Dictionary = reach_map(s)
	var island: Array[Vector2i] = []
	for y: int in range(6, 9):
		for x: int in range(6, 9):
			island.append(Vector2i(x, y))
	var all_target: bool = true
	var unreachable: bool = true
	for c: Vector2i in island:
		all_target = all_target and st.target[st.index_of(c.x, c.y)] == 1
		unreachable = unreachable and not reach.has(c)
	var isolated: bool = true
	var radius: float = s.sim_tuning.spread_radius_tiles
	for y: int in st.height:
		for x: int in st.width:
			if st.target[st.index_of(x, y)] == 0 or island.has(Vector2i(x, y)):
				continue
			for c: Vector2i in island:
				if Vector2(x - c.x, y - c.y).length() <= radius + 0.001:
					isolated = false
	check("fixture.island_isolated_target", all_target and unreachable and isolated, "target=%s unreachable=%s isolated=%s" % [all_target, unreachable, isolated])
	# Every nest can be walked to and shot at (a spot exists), the safe-zone start can reach the open ground.
	var spots_ok: bool = true
	for nest: Nest in s.enemies.nests:
		spots_ok = spots_ok and shoot_spot(s, reach, nest.center_px(Config.TILE_PX)).x >= 0
	check("fixture.nest_shoot_spots_reachable", spots_ok, "reachable cells=%d" % reach.size())
	var island_spot: bool = false
	for key: Variant in reach.keys():
		var c: Vector2i = key
		if cpx(c).distance_to(cpx(Vector2i(7, 7))) < s.play_tuning.projectile_range_px - 4.0 and not s.shot_blocked(cpx(c), cpx(Vector2i(7, 7))):
			island_spot = true
	check("fixture.island_shootable", island_spot)
	check("fixture.fixed_seed", s.enemy_tuning.rng_seed == 20261018 and st.sprout_seed == 81026)

# ---------------------------------------------------------------- T2 wiring, pause

func _wiring_and_pause() -> void:
	var s: RefCounted = new_session()
	check("wiring.hooks", s.projectiles.enemy_hit_provider.is_valid() and s.spread.allow_hook.is_valid() and s.play.enemies == s.enemies and s.far != null and s.zone_progress != null and s.combat != null)
	s.paused = true
	var elapsed: float = s.clock.elapsed
	var etime: float = s.enemies.time
	var launched: int = s.projectiles.launched
	s.fire(false, s.position + Vector2(10, 0))
	run_for(s, 30.0)
	check("pause.nothing_advances", s.clock.elapsed == elapsed and s.enemies.time == etime and s.enemies.total_spawned == 0 and s.projectiles.launched == launched, "elapsed=%f etime=%f" % [s.clock.elapsed, s.enemies.time])
	s.paused = false
	run_for(s, 20.0)
	check("pause.resume_runs_without_banked_time", s.enemies.time > 19.5 and s.enemies.time < 20.5 and s.enemies.total_spawned > 0, "etime=%f spawned=%d" % [s.enemies.time, s.enemies.total_spawned])

# ---------------------------------------------------------------- T3 spawn caps, zone rule, walls, nest tiles

func _spawn_and_walls() -> void:
	var s: RefCounted = new_session()
	var st: WorldState = s.state
	# Lure chasers at the walls: plants on the island (across water) and right above the mill's north wall.
	st.debug_fill_stage(Rect2i(6, 6, 3, 3), WorldState.STAGE_MATURE)
	st.debug_fill_stage(Rect2i(3, 20, 9, 2), WorldState.STAGE_MATURE)
	var max_boars: int = 0
	var max_per_nest: int = 0
	var bad_pos: int = 0
	var bad_zone: int = 0
	var half: Vector2 = s.enemies.half
	var nest_cells_planted: int = 0
	var steps: int = 0
	for i: int in 1600:
		s.advance_game(0.25)
		steps += 1
		max_boars = maxi(max_boars, s.enemies.boars.size())
		for nest: Nest in s.enemies.nests:
			max_per_nest = maxi(max_per_nest, nest.boar_count)
		for boar: Boar in s.enemies.boars:
			if not Walker.is_clear(st, Config.TILE_PX, boar.pos, half):
				bad_pos += 1
			var x0: int = floori((boar.pos.x - half.x + 0.001) / Config.TILE_PX)
			var x1: int = ceili((boar.pos.x + half.x - 0.001) / Config.TILE_PX) - 1
			var y0: int = floori((boar.pos.y - half.y + 0.001) / Config.TILE_PX)
			var y1: int = ceili((boar.pos.y + half.y - 0.001) / Config.TILE_PX) - 1
			for cx: int in [x0, x1]:
				for cy: int in [y0, y1]:
					if st.zone_of[st.index_of(cx, cy)] != 1:
						bad_zone += 1
		if i % 40 == 0:
			for nest: Nest in s.enemies.nests:
				for dy: int in nest.size:
					for dx: int in nest.size:
						if st.stage[st.index_of(nest.tile.x + dx, nest.tile.y + dy)] != 0:
							nest_cells_planted += 1
	check("spawn.capped", max_boars == s.enemy_tuning.boar_cap and max_per_nest <= s.enemy_tuning.nest_boar_cap and s.enemies.total_spawned >= s.enemy_tuning.boar_cap, "max_boars=%d cap=%d per_nest_max=%d spawned=%d" % [max_boars, s.enemy_tuning.boar_cap, max_per_nest, s.enemies.total_spawned])
	check("walls.boars_never_leave_walkable_cells", bad_pos == 0 and steps == 1600, "violations=%d over %d steps (%.0f s), boars alive=%d, gnawed=%d" % [bad_pos, steps, steps * 0.25, s.enemies.boars.size(), s.enemies.total_gnawed])
	check("zones.boars_stay_out_of_start_zone", bad_zone == 0, "violations=%d" % bad_zone)
	check("spread.never_enters_nest_tiles", nest_cells_planted == 0 and s.spread.allow_hook.is_valid(), "planted on nest tiles=%d" % nest_cells_planted)
	check("counters.consistent_after_run", st.counters_consistent())
	check("player.untouched_in_safe_patch_centre", s.play.hp == s.play.hp_max and s.play.health.hit_count == 0, "hp=%d" % s.play.hp)

# ---------------------------------------------------------------- T4 hits, rewards

func _hits_and_rewards() -> void:
	var s: RefCounted = new_session()
	var spot: Vector2i = Vector2i(24, 18)
	s.position = cpx(spot)
	var boar: Boar = make_boar(s, cpx(Vector2i(24, 13)), 3)
	var target: Vector2 = boar.pos
	fire_volley(s, target, 1)
	check("hit.seed_damages_boar", boar.hp == 2 and s.combat.hits == 1, "hp=%d hits=%d" % [boar.hp, s.combat.hits])
	var landed_before: int = s.projectiles.landed_count
	fire_volley(s, target, 2)
	check("hit.boar_defeated", boar.hp <= 0 and not s.enemies.boars.has(boar) and s.enemies.total_killed == 1 and s.projectiles.landed_count == landed_before, "killed=%d landed_extra=%d" % [s.enemies.total_killed, s.projectiles.landed_count - landed_before])
	check("reward.fruits_dropped", s.combat.fruits_dropped + s.combat.fruits_direct >= 1 and s.play.pickups.count() >= 1, "dropped=%d direct=%d pickups=%d" % [s.combat.fruits_dropped, s.combat.fruits_direct, s.play.pickups.count()])
	var seeds_before: int = s.play.seeds
	s.play.seeds = 0
	var drops: Array[Vector2] = []
	for item: Dictionary in s.play.pickups.items:
		drops.append(Vector2(float(item["x"]), float(item["y"])))
	for point: Vector2 in drops:
		s.position = point
		s.advance_game(0.25)
	check("reward.seeds_collected", s.play.seeds >= 1, "seeds=%d (was %d before zeroing)" % [s.play.seeds, seeds_before])
	check("carcass.created_at_kill", s.enemies.carcasses.size() == 1 and s.enemies.carcasses[0].pos.is_equal_approx(target))
	# Nest: 10 hp, reachable spot, destroyed by seeds; tiles released; hp visible in the status line.
	var s2: RefCounted = new_session()
	var reach: Dictionary = reach_map(s2)
	var nest: Nest = s2.enemies.nests[0]
	var spot2: Vector2i = shoot_spot(s2, reach, nest.center_px(Config.TILE_PX))
	s2.position = cpx(spot2)
	var hp0: int = nest.hp
	fire_volley(s2, nest.center_px(Config.TILE_PX), 1)
	check("hit.seed_damages_nest", nest.hp == hp0 - 1 and nest.alive and s2.combat_status_text().contains("%d/%d" % [nest.hp, nest.hp_max]), "hp=%d" % nest.hp)
	fire_volley(s2, nest.center_px(Config.TILE_PX), 12)
	var released: bool = true
	for dy: int in nest.size:
		for dx: int in nest.size:
			released = released and s2.state.occupant[s2.state.index_of(nest.tile.x + dx, nest.tile.y + dy)] == 0
	check("hit.nest_destroyed_and_reward", not nest.alive and released and s2.enemies.total_nests_destroyed == 1 and s2.combat.fruits_dropped + s2.combat.fruits_direct >= 1 and s2.enemies.alive_nest_count(1) == 2, "alive=%d" % s2.enemies.alive_nest_count(1))

# ---------------------------------------------------------------- T5 carcass cycle

func _carcass_cycle() -> void:
	var s: RefCounted = new_session()
	var st: WorldState = s.state
	var spot: Vector2 = cpx(Vector2i(24, 14))
	var cell_index: int = st.index_of(24, 14)
	var base_fertility: int = st.fertility[cell_index]
	var boar: Boar = make_boar(s, spot, 1)
	s.enemies.damage_boar(boar, 1)
	var corpse_fert: int = st.fertility[cell_index]
	check("carcass.corpse_adds_fertility", corpse_fert == base_fertility + s.enemy_tuning.carcass_fertility and s.enemies.carcass_count(Carcass.STAGE_CORPSE) == 1, "%d -> %d" % [base_fertility, corpse_fert])
	# Keep the nests quiet while time passes: the fertility cycle is what is measured.
	for nest: Nest in s.enemies.nests:
		nest.spawn_steps = -1000000
	run_for(s, s.enemy_tuning.carcass_seconds + 2.0)
	check("carcass.becomes_bone", s.enemies.carcass_count(Carcass.STAGE_BONE) == 1 and st.fertility[cell_index] == base_fertility + s.enemy_tuning.bone_fertility, "fert=%d" % st.fertility[cell_index])
	run_for(s, s.enemy_tuning.bone_seconds + 2.0)
	check("carcass.vanishes_fertility_returns", s.enemies.carcasses.is_empty() and st.fertility[cell_index] == base_fertility, "fert=%d base=%d" % [st.fertility[cell_index], base_fertility])

# ---------------------------------------------------------------- T6 hit order wall -> enemy -> ground

func _hit_order() -> void:
	var s: RefCounted = new_session()
	var st: WorldState = s.state
	# The mill's north wall is at y=23 for x=2..12. Player at (7,18); boar A in front of the wall (7,22); boar B behind it (7,36).
	var player_cell: Vector2i = Vector2i(7, 18)
	s.position = cpx(player_cell)
	var wall_between: bool = s.shot_blocked(cpx(player_cell), cpx(Vector2i(7, 36)))
	var behind: Boar = make_boar(s, cpx(Vector2i(7, 36)), 3)
	var blocked_before: int = s.shots_blocked_by_wall
	var landed_before: int = s.projectiles.landed_count
	fire_volley(s, behind.pos, 3)
	check("order.wall_hides_enemy_behind_it", wall_between and behind.hp == 3 and s.shots_blocked_by_wall == blocked_before + 3 and s.combat.hits == 0 and s.projectiles.landed_count == landed_before, "blocked=%d hits=%d hp=%d" % [s.shots_blocked_by_wall - blocked_before, s.combat.hits, behind.hp])
	var front: Boar = make_boar(s, cpx(Vector2i(7, 22)), 3)
	fire_volley(s, behind.pos, 1)
	check("order.enemy_in_front_of_wall_is_hit_first", front.hp == 2 and behind.hp == 3 and s.combat.hits == 1, "front hp=%d behind hp=%d" % [front.hp, behind.hp])
	# Enemy before ground: a shot aimed past a boar in the open is consumed by it and does not plant anything.
	var s2: RefCounted = new_session()
	s2.position = cpx(Vector2i(24, 18))
	var in_line: Boar = make_boar(s2, cpx(Vector2i(24, 15)), 3)
	var planted_before: int = s2.state.plant_count
	fire_volley(s2, cpx(Vector2i(24, 11)), 1)
	run_for(s2, 1.0)
	check("order.enemy_before_ground", in_line.hp == 2 and s2.projectiles.landed_count == 0 and s2.state.plant_count == planted_before, "hp=%d landed=%d" % [in_line.hp, s2.projectiles.landed_count])
	# Water passes through enemies (old rule) and lands behind.
	var wet_before: int = s2.projectiles.landed_count
	s2.play.add_water(50.0)
	s2.fire(true, cpx(Vector2i(24, 11)))
	run_for(s2, 1.0)
	check("order.water_passes_through_enemy", in_line.hp == 2 and s2.projectiles.landed_count == wet_before + 1, "hp=%d landed=%d" % [in_line.hp, s2.projectiles.landed_count])
	report.append("hit order: wall (clear_end) -> enemy on the clear part of the segment -> ground landing; an enemy in front of a wall is hit, one behind is not; a hit shot is consumed (no landing); water passes through enemies")

# ---------------------------------------------------------------- T7 contact, downed, safe-zone return

func _contact_and_revive() -> void:
	var s: RefCounted = new_session()
	var st: WorldState = s.state
	# Freeze the enemy simulation (no gnawing / walking) so only the player's side changes; growth/spread keep running.
	s.enemy_tuning.enabled = false
	var out: Vector2i = Vector2i(24, 17)
	s.position = cpx(out)
	var boar: Boar = make_boar(s, s.position, 3)
	var hp0: int = s.play.hp
	var zones_before: PackedByteArray = st.zone_state.duplicate()
	var green_before: int = st.greened_count
	var zone_green_before: PackedInt32Array = st.zone_greened_count.duplicate()
	s.advance_game(0.25)
	check("contact.damages_player", s.play.hp == hp0 - s.enemy_tuning.contact_damage and s.play.health.hit_count == 1, "hp=%d" % s.play.hp)
	var downed_seen: bool = false
	var revived_at: Array[Vector2] = []
	s.play.health.revived.connect(func(at: Vector2) -> void: revived_at.append(at))
	for i: int in 400:
		boar.pos = s.position
		s.advance_game(0.25)
		downed_seen = downed_seen or s.play.health.downed
		if not revived_at.is_empty():
			break
	check("contact.downed_then_returns_to_safe_zone", downed_seen and s.play.health.down_count == 1 and not revived_at.is_empty() and s.position.is_equal_approx(cpx(Vector2i(24, 24))) and s.play.hp == s.play.hp_max and not s.play.health.downed and s.state.zone_of[s.state.index_of(24, 24)] == 0, "pos=%s hp=%d" % [s.position, s.play.hp])
	var zones_ok: bool = true
	for z: int in st.zone_count:
		zones_ok = zones_ok and st.zone_state[z] >= zones_before[z]
	check("revive.does_not_roll_back_state", zones_ok and st.greened_count >= green_before and st.zone_greened_count[0] >= zone_green_before[0], "greened %d -> %d zones=%s" % [green_before, st.greened_count, st.zone_state])
	# Downed player cannot walk or fire.
	boar.pos = Vector2(10, 10)
	run_for(s, 3.0)
	check("downed.hit_possible_again_after_invulnerability", s.play.health.hit(s.play, 99, s.position + Vector2(1, 0), s.position) and s.play.health.downed)
	var frozen: Vector2 = s.position
	var moved: Vector2 = s.walk(Vector2.RIGHT, 0.2)
	var fire_result: Dictionary = s.fire(false, s.position + Vector2(10, 0))
	check("downed.blocks_walk_and_fire", moved == Vector2.ZERO and s.position == frozen and not bool(fire_result["ok"]) and String(fire_result["reason"]) == "downed")

# ---------------------------------------------------------------- T8 determinism

func _determinism() -> void:
	var a: RefCounted = new_session()
	var b: RefCounted = new_session()
	run_for(a, 90.0)
	run_for(b, 90.0)
	var da: String = JSON.stringify(a.enemies.to_dict())
	var db: String = JSON.stringify(b.enemies.to_dict())
	check("determinism.fixed_seed_same_enemy_state", da == db and a.enemies.total_spawned > 0, "spawned=%d len=%d" % [a.enemies.total_spawned, da.length()])

# ---------------------------------------------------------------- T9 clear -> stable -> complete (100 %)

func _clear_stable_complete() -> void:
	var s: RefCounted = new_session()
	var st: WorldState = s.state
	s.enemy_tuning.contact_damage = 0
	# Bound from the settings only, before anything happens (FarSeedSim.completion_bound_seconds: delay + fair sweep laps + slowest growth).
	var bound: float = s.far.completion_bound_seconds()
	var lap: int = s.far.lap_steps_bound()
	report.append("100%% bound = completion_bound_seconds() = %.1f s (swept targets %d, lap_steps_bound %d, sweep period %d ticks of %.1f s, sweep delay %.0f s, growth wait derived from sprout1_growth/slowest rate)" % [bound, s.far.swept_targets(), lap, s.far.sweep_period_ticks(), s.sim_tuning.spread_tick_seconds, s.sim_tuning.far_sweep_start_delay_seconds])
	print("INFO bound=%.1f" % bound)
	# 0. Let the nests work for a while first (the player stays in the safe patch), so boars exist when the nests fall.
	run_for(s, 40.0)
	var boars_before_clear: int = s.enemies.boars.size()
	# 1. Walk to each nest with the real walk() and destroy it with seeds.
	var reach: Dictionary = reach_map(s)
	var walked_all: bool = true
	var total_walk_steps: int = 0
	var killed_in_order: bool = true
	for nest: Nest in s.enemies.nests:
		var center: Vector2 = nest.center_px(Config.TILE_PX)
		var spot: Vector2i = shoot_spot(s, reach, center)
		var from_cell: Vector2i = Coords.logic_to_cell(s.position)
		var local: Dictionary = reach_map(s)
		var arrived: Array = walk_to(s, local, spot) if local.has(spot) else [false, 0]
		walked_all = walked_all and bool(arrived[0])
		total_walk_steps += int(arrived[1])
		var shots: int = 0
		while nest.alive and shots < 40:
			s.play.add_seeds(40)
			s.fire(false, center)
			s.advance_game(0.25)
			shots += 1
		killed_in_order = killed_in_order and not nest.alive
		print("INFO nest %d: from %s walked to %s (%s) shots=%d" % [nest.id, from_cell, spot, arrived, shots])
	check("clear.walked_and_shot_all_nests", walked_all and killed_in_order and s.enemies.alive_nest_count(1) == 0, "walk steps=%d" % total_walk_steps)
	check("clear.zone_is_clearing_not_stable", boars_before_clear > 0 and not s.enemies.boars.is_empty() and st.zone_state[1] == WorldState.ZONE_CLEARING and s.zone_log.size() >= 1 and s.zone_log[0].contains("巣をすべて壊した"), "boars left=%d log=%s" % [s.enemies.boars.size(), s.zone_log])
	var spawned_at_clear: int = s.enemies.total_spawned
	run_for(s, 40.0)
	var still_clearing: bool = st.zone_state[1] == WorldState.ZONE_CLEARING or s.enemies.boars.is_empty()
	check("clear.spawning_stopped", s.enemies.total_spawned == spawned_at_clear and still_clearing, "spawned %d -> %d, boars=%d" % [spawned_at_clear, s.enemies.total_spawned, s.enemies.boars.size()])
	# 2. Remove the remaining boars by shooting them (freeze one, stand 5 cells away with a clear line, 3 seeds).
	var boar_kills: int = 0
	var guard: int = 0
	var stable_early: bool = false
	while not s.enemies.boars.is_empty() and guard < 40:
		guard += 1
		var boar: Boar = s.enemies.boars[0]
		boar.wait = 1000000
		var placed: bool = false
		for angle: int in 16:
			var offset: Vector2 = Vector2.from_angle(TAU * float(angle) / 16.0) * 20.0
			var candidate: Vector2 = boar.pos + offset
			if Walker.is_clear(st, Config.TILE_PX, candidate, Config.player_half_px()) and not s.shot_blocked(candidate, boar.pos):
				s.position = candidate
				placed = true
				break
		if not placed:
			s.position = boar.pos
		var before: int = s.enemies.boars.size()
		var tries: int = 0
		while s.enemies.boars.size() == before and tries < 8:
			s.play.add_seeds(40)
			s.fire(false, boar.pos)
			s.advance_game(0.25)
			tries += 1
		boar_kills += before - s.enemies.boars.size()
		if not s.enemies.boars.is_empty() and st.zone_state[1] == WorldState.ZONE_STABLE:
			stable_early = true
	check("clear.remaining_enemies_removed", s.enemies.boars.is_empty() and boar_kills >= 1 and not stable_early, "killed %d by shots, spawned total %d, killed total %d" % [boar_kills, s.enemies.total_spawned, s.enemies.total_killed])
	check("stable.reached_in_order", st.zone_state[1] >= WorldState.ZONE_STABLE and s.zone_log.size() >= 2 and s.zone_log[0].contains("巣をすべて壊した") and s.zone_log[1].contains("安定した"), "log=%s" % [s.zone_log])
	var t_stable: float = float((s.zone_times[1] as Dictionary).get(WorldState.ZONE_STABLE, -1.0))
	check("stable.notice_text", s.last_message.length() > 0 and t_stable >= 0.0, "last=%s t_stable=%.2f" % [s.last_message, t_stable])
	# 3. No re-invasion; revive does not roll anything back; then 100 % with no resources and no input.
	s.position = cpx(Vector2i(24, 24))
	var spawned_stable: int = s.enemies.total_spawned
	var hits_before: int = s.play.health.hit_count
	var seeds_at_stable: int = s.play.seeds
	var water_at_stable: float = s.play.water
	var shots_at_stable: int = s.projectiles.launched
	var green_at_stable: int = st.greened_count
	var invaded: int = 0
	# A nest placed into the stable zone must spawn nothing (the stable zone is closed); it is removed again afterwards so the
	# 100 % count is not held back by its tiles.
	var intruder: Nest = s.enemies.add_nest(1, Vector2i(34, 15))
	var limit_time: float = t_stable + bound
	for i: int in 240:
		s.advance_game(0.25)
		if not s.enemies.boars.is_empty() or s.enemies.total_spawned != spawned_stable:
			invaded += 1
	if intruder != null:
		s.enemies.destroy_nest(intruder)
	while s.clock.elapsed <= limit_time + 0.001 and st.greened_count != st.target_count:
		s.advance_game(0.25)
		if not s.enemies.boars.is_empty() or s.enemies.total_spawned != spawned_stable:
			invaded += 1
	var complete_at: float = s.clock.elapsed
	check("stable.no_reinvasion", invaded == 0 and intruder != null and s.enemies.boars.is_empty() and s.enemies.total_spawned == spawned_stable, "invaded steps=%d, intruder nest placed=%s, spawned=%d" % [invaded, intruder != null, s.enemies.total_spawned])
	var all_planted_on_targets: bool = true
	var island_ok: bool = true
	for i: int in st.tile_count():
		if st.target[i] == 0 and st.stage[i] != 0:
			all_planted_on_targets = false
	for y: int in range(6, 9):
		for x: int in range(6, 9):
			island_ok = island_ok and st.stage[st.index_of(x, y)] >= WorldState.GREENED_MIN_STAGE
	var elapsed_since: float = complete_at - t_stable
	check("complete.exact_100_percent_within_bound", st.greened_count == st.target_count and st.target_count > 0 and st.greening_percent_floor() == 100 and complete_at <= limit_time + 0.001, "greened=%d/%d took %.1f s after stable, bound %.1f s (limit time %.1f)" % [st.greened_count, st.target_count, elapsed_since, bound, limit_time])
	check("complete.island_included_and_non_targets_untouched", island_ok and all_planted_on_targets and st.counters_consistent(), "island ok=%s" % island_ok)
	check("complete.no_resources_or_input_used", s.play.seeds == seeds_at_stable and is_equal_approx(s.play.water, water_at_stable) and s.projectiles.launched == shots_at_stable and s.play.health.hit_count == hits_before, "seeds %d->%d" % [seeds_at_stable, s.play.seeds])
	check("complete.zone_and_region_state", st.zone_state[1] == WorldState.ZONE_COMPLETE and st.cleared and s.cleared_notices == 1 and s.zone_log.has("すべての地域を緑化した") and s.zone_log.has("イノシシの原の緑化が完了した"), "state=%s cleared=%s log=%s" % [st.zone_state, st.cleared, s.zone_log])
	report.append("100%% result: stable at %.1f s, 100%% at %.1f s (took %.1f s of the %.1f s bound), greened %d/%d, green at stable %d" % [t_stable, complete_at, elapsed_since, bound, st.greened_count, st.target_count, green_at_stable])
	# 4. Downing after stable/complete: forced hits down the player, revive keeps everything.
	var state_before: PackedByteArray = st.zone_state.duplicate()
	var green_complete: int = st.greened_count
	var revived: Array[bool] = []
	s.play.health.revived.connect(func(_at: Vector2) -> void: revived.append(true))
	run_for(s, 3.0)
	var downed_ok: bool = s.play.health.hit(s.play, 99, s.position + Vector2(1, 0), s.position)
	run_for(s, 4.0)
	check("revive.after_complete_keeps_progress", downed_ok and not revived.is_empty() and st.zone_state == state_before and st.greened_count == green_complete and st.greened_count == st.target_count and st.cleared, "state=%s greened=%d" % [st.zone_state, st.greened_count])
	for line: String in report:
		print("REPORT ", line)
