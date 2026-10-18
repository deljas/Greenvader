extends SceneTree
## POC-03 logic checks (headless OK). Run:
## godot --headless --path <repo> --script res://tests/poc/play/logic.gd
## Long growth is fast-forwarded with advance_game(); each condition runs once. No OS-level input.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const Projectiles: GDScript = preload("res://scripts/poc/play/poc_projectiles.gd")
const PocInput: GDScript = preload("res://scripts/poc/poc_input.gd")

var failures: int = 0
var passes: int = 0
var sessions: Array[RefCounted] = []

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
	_projectile_unit()
	_cycle()
	_water_effect()
	_seed_recovery()
	_water_recovery()
	_cultivated()
	_wall()
	_non_target()
	_pause()
	_counters()
	_debug_refill_default()
	await _main_checks()
	for s: RefCounted in sessions:
		s.close()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)

func new_session() -> RefCounted:
	var s: RefCounted = Session.new()
	s.load_placement()
	sessions.append(s)
	return s

func _frames(n: int) -> void:
	for i: int in n:
		await process_frame

func stage_count(s: RefCounted, stage: int) -> int:
	var total: int = 0
	for i: int in s.state.tile_count():
		if s.state.stage[i] == stage and s.state.terrain[i] == Session.T_WASTE:
			total += 1
	return total

func free_cell(s: RefCounted, cell: Vector2i) -> bool:
	if not s.state.in_bounds(cell.x, cell.y):
		return false
	var i: int = s.state.index_of(cell.x, cell.y)
	return s.state.is_walkable(cell.x, cell.y) and not s.placement.projectile_blocked_cell(cell) and s.state.target[i] == 1 and s.state.terrain[i] == Session.T_WASTE and s.state.stage[i] == 0 and not s.placement.is_puddle(cell)

## Nearest open wasteland spot (all cells of the (2r+1)^2 block free) that the player can see from the start.
func open_spot(s: RefCounted, radius: int, max_cells: int) -> Vector2i:
	var start: Vector2i = Coords.logic_to_cell(s.position)
	for d: int in range(2, max_cells):
		for dy: int in range(-d, d + 1):
			for dx: int in range(-d, d + 1):
				if maxi(absi(dx), absi(dy)) != d:
					continue
				var c: Vector2i = start + Vector2i(dx, dy)
				var ok: bool = true
				for oy: int in range(-radius, radius + 1):
					for ox: int in range(-radius, radius + 1):
						if not free_cell(s, c + Vector2i(ox, oy)):
							ok = false
				if ok and not s.shot_blocked(s.position, Coords.cell_center_logic(c)):
					return c
	return Vector2i(-1, -1)

# ---------------------------------------------------------------- shots

func _projectile_unit() -> void:
	var tuning: PlayTuning = load("res://data/play_tuning.tres") as PlayTuning
	var p: RefCounted = Projectiles.new()
	p.setup(tuning)
	var landings: Array[Vector2] = []
	p.landed.connect(func(_k: String, pt: Vector2) -> void: landings.append(pt))
	var planned: Vector2 = p.launch("seed", Vector2(100, 100), Vector2(1000, 100))
	check("shot.range_clip", planned.is_equal_approx(Vector2(100 + p.range_px, 100)), "planned=%s range=%f" % [planned, p.range_px])
	for i: int in 60:
		p.advance(0.1)
	check("shot.lands_once_at_target", landings.size() == 1 and landings[0].is_equal_approx(planned) and p.shots.is_empty())
	p.launch("water", Vector2(0, 0), Vector2(60, 0))
	p.advance(0.1)
	check("shot.speed", is_equal_approx((p.shots[0]["position"] as Vector2).x, p.speed * 0.1), "x=%f speed=%f" % [(p.shots[0]["position"] as Vector2).x, p.speed])
	p.shots.clear()
	var refused: bool = false
	for i: int in p.max_count + 1:
		if p.launch("seed", Vector2.ZERO, Vector2(10, 0)) == Vector2.INF:
			refused = true
	check("shot.cap", refused and p.shots.size() == p.max_count, "n=%d" % p.shots.size())
	p.shots.clear()
	var hits: Array[String] = []
	p.enemy_hit.connect(func(k: String, _pt: Vector2, _i: Dictionary) -> void: hits.append(k))
	p.enemy_hit_provider = func(_s: Dictionary, from: Vector2, _to: Vector2) -> Dictionary: return {"point": from + Vector2(1, 0)}
	landings.clear()
	p.launch("seed", Vector2(5, 5), Vector2(40, 5))
	p.advance(0.1)
	check("shot.enemy_hook_ends_shot", hits.size() == 1 and landings.is_empty() and p.shots.is_empty())
	p.enemy_hit_provider = Callable()
	var expired: Array[String] = []
	p.expired.connect(func(k: String, _pt: Vector2) -> void: expired.append(k))
	p.range_px = 100000.0
	p.speed = 1.0
	p.launch("seed", Vector2.ZERO, Vector2(50000, 0))
	for i: int in 20:
		p.advance(0.25)
	check("shot.lifetime", expired.size() == 1 and p.shots.is_empty())
	p.blocker = func(a: Vector2, b: Vector2) -> bool: return maxf(a.x, b.x) >= 20.0
	var stops: Array[Vector2] = []
	p.blocked.connect(func(_k: String, pt: Vector2) -> void: stops.append(pt))
	landings.clear()
	p.speed = 160.0
	p.range_px = 100.0
	p.launch("seed", Vector2(0, 0), Vector2(60, 0))
	for i: int in 20:
		p.advance(0.1)
	check("shot.blocked_in_front", stops.size() == 1 and stops[0].x < 20.0 and stops[0].x > 19.0 and landings.is_empty(), "stop=%s" % [stops])

# ---------------------------------------------------------------- loop

func _cycle() -> void:
	var s: RefCounted = new_session()
	var spot: Vector2i = open_spot(s, 3, 12)
	check("cycle.spot_found", spot.x >= 0, "spot=%s" % spot)
	var seeds0: int = s.play.seeds
	var res: Dictionary = s.fire(false, Coords.cell_center_logic(spot))
	check("cycle.fire_ok_spends_seed", res["ok"] and s.play.seeds == seeds0 - 1 and s.projectiles.shots.size() == 1)
	s.advance_game(2.0)
	var planted: int = stage_count(s, WorldState.STAGE_SEED)
	check("cycle.seeded", planted >= 1 and s.projectiles.shots.is_empty() and s.play.last_scatter.size() == planted, "seed cells=%d %s" % [planted, s.last_message])
	var green0: int = s.state.greened_count
	s.advance_game(90.0)
	var mature: int = stage_count(s, WorldState.STAGE_MATURE)
	check("cycle.sprout_to_mature", mature >= 1 and s.state.greened_count > green0, "mature=%d green %d->%d" % [mature, green0, s.state.greened_count])
	# natural spread: keep running; the mature wasteland area grows beyond the planted cells.
	s.advance_game(240.0)
	var grown: int = 0
	for i: int in s.state.tile_count():
		if s.state.stage[i] > 0 and s.state.terrain[i] == Session.T_WASTE:
			grown += 1
	check("cycle.natural_spread", grown > planted, "plant cells %d > planted %d (spread ticks %d)" % [grown, planted, s.clock.spread_ticks])
	# seed production + collection: a mature patch near the player makes fruits; standing on one collects it.
	s.state.debug_fill_stage(Rect2i(spot.x - 3, spot.y - 3, 7, 7), WorldState.STAGE_MATURE)
	s.position = Coords.cell_center_logic(spot)
	var produced: bool = false
	var fruit: Dictionary = {}
	for i: int in 800:
		s.advance_game(0.25)
		for item: Dictionary in s.play.pickups.items:
			if GroundPickups.is_plant_owner(int(item["owner"])):
				produced = true
				fruit = item
		if produced:
			break
	check("cycle.plant_produces_fruit", produced, "after %.0fs game time" % s.play.production_time)
	if produced:
		var before: int = s.play.seeds
		s.position = Vector2(float(fruit["x"]), float(fruit["y"]))
		s.advance_game(0.25)
		check("cycle.collect_fruit_gives_seed", s.play.seeds >= before + 1, "seeds %d -> %d" % [before, s.play.seeds])
	check("cycle.counters_match_recount", s.state.counters_consistent() and s.state.greened_count == s.state.recount_greened())

func _water_effect() -> void:
	var s: RefCounted = new_session()
	var spot: Vector2i = open_spot(s, 3, 12)
	var dry: int = s.state.index_of(spot.x - 2, spot.y)
	var wet: int = s.state.index_of(spot.x + 2, spot.y)
	s.state.set_stage(dry, WorldState.STAGE_SEED)
	s.state.set_stage(wet, WorldState.STAGE_SEED)
	var water0: float = s.play.water
	var res: Dictionary = s.fire(true, Coords.cell_center_logic(spot + Vector2i(2, 0)))
	check("water.fire_spends_water", res["ok"] and s.play.water < water0, "water %f -> %f" % [water0, s.play.water])
	s.advance_game(3.0)
	check("water.wets_tile_only_near", s.state.moisture[wet] > 0 and s.state.moisture[dry] == 0, "wet=%d dry=%d" % [s.state.moisture[wet], s.state.moisture[dry]])
	s.advance_game(8.0)
	check("water.faster_than_dry", s.state.growth[wet] > s.state.growth[dry] and s.state.growth[dry] > 0, "wet=%d dry=%d" % [s.state.growth[wet], s.state.growth[dry]])

func _seed_recovery() -> void:
	var s: RefCounted = new_session()
	check("recover.sources_from_fixture", s.play.sources.size() == 1)
	var src_cell: Vector2i = Coords.logic_to_cell(s.play.sources[0].position)
	check("recover.source_in_safe_zone", s.base_terrain[src_cell.y * Session.WIDTH + src_cell.x] == Session.T_SAFE, "cell=%s" % src_cell)
	s.play.seeds = 0
	var denied: Dictionary = s.fire(false, Coords.cell_center_logic(Vector2i(24, 17)))
	check("recover.zero_seed_denied", not denied["ok"] and denied["reason"] == "no_seed" and s.projectiles.shots.is_empty())
	# Reachability of the source area from the start and walkability of every drop spot (long run, one pass).
	var reach: Dictionary = {}
	var queue: Array[Vector2i] = [Coords.logic_to_cell(s.position)]
	reach[queue[0]] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not reach.has(n) and s.state.is_walkable(n.x, n.y):
				reach[n] = true
				queue.append(n)
	var all_ok: bool = reach.has(src_cell)
	var dropped: int = 0
	for i: int in 120:
		s.advance_game(8.0)
		for item: Dictionary in s.play.pickups.items.duplicate():
			var c: Vector2i = Coords.logic_to_cell(Vector2(float(item["x"]), float(item["y"])))
			dropped += 1
			if not reach.has(c):
				all_ok = false
				print("  unreachable drop cell ", c, " base=", s.base_terrain[c.y * Session.WIDTH + c.x], " obstacle=", s.placement.obstacle[c.y * Session.WIDTH + c.x], " walkable=", s.state.is_walkable(c.x, c.y))
		s.play.pickups.items.clear()
	check("recover.drops_reachable", all_ok and dropped >= 20, "dropped samples=%d" % dropped)
	s.play.pickups.items.clear()
	s.play.seeds = 0
	s.advance_game(10.0)
	var fruit: Dictionary = s.play.pickups.items[0] if s.play.pickups.count() > 0 else {}
	check("recover.source_makes_fruit", not fruit.is_empty())
	if not fruit.is_empty():
		s.position = Vector2(float(fruit["x"]), float(fruit["y"]))
		s.advance_game(0.25)
		var ok: Dictionary = s.fire(false, s.position + Vector2(20, 0))
		check("recover.seed_back_and_fire", s.play.seeds == 0 and ok["ok"], "after firing the recovered seed")

func _water_recovery() -> void:
	var s: RefCounted = new_session()
	s.play.water = 0.0
	var denied: Dictionary = s.fire(true, s.position + Vector2(20, 0))
	check("water0.fire_denied", not denied["ok"] and denied["reason"] == "no_water")
	s.advance_game(5.0)
	check("water0.no_refill_away_from_water", s.play.water == 0.0)
	var shore: Vector2i = Vector2i(38, 5)
	check("water0.shore_is_waterside", s.placement.is_water_source(shore) and not s.placement.is_water_source(Vector2i(24, 20)))
	s.position = Coords.cell_center_logic(Vector2i(37, 5))
	s.advance_game(2.0)
	check("water0.refills_at_shore", s.play.water > 20.0, "water=%f" % s.play.water)
	var puddle: Vector2i = Vector2i(-1, -1)
	for y: int in Session.HEIGHT:
		for x: int in Session.WIDTH:
			if s.placement.is_puddle(Vector2i(x, y)) and not s.placement.is_water_source(Vector2i(x, y)):
				puddle = Vector2i(x, y)
	check("water0.puddle_not_a_source", puddle.x >= 0 and not s.play.is_near_water(Coords.cell_center_logic(puddle)), "puddle=%s" % puddle)

func _boost_max(s: RefCounted) -> int:
	var best: int = 0
	for v: int in s.play.cultivation.boost:
		best = maxi(best, v)
	return best

func _cultivated() -> void:
	var s: RefCounted = new_session()
	var keys: Array[String] = []
	for def: PlantDef in s.play.selectable:
		keys.append(String(def.key))
	check("plant.selectable_order", keys == ["normal", "carrot", "kiwi"], str(keys))
	s.cycle_plant(1)
	check("plant.cycle", s.selected_label() == "にんじん")
	var target: Vector2 = Coords.cell_center_logic(Vector2i(24, 25))
	s.position = Coords.cell_center_logic(Vector2i(24, 21))
	var seeds0: int = s.play.seeds
	var res: Dictionary = s.fire(false, target)
	check("plant.carrot_reserves_cost", res["ok"] and s.play.reserved_seeds == 3 and s.play.seeds == seeds0)
	s.advance_game(1.5)
	check("plant.carrot_placed_cost_spent", s.play.cultivation.count(&"carrot") == 1 and s.play.seeds == seeds0 - 3 and s.play.reserved_seeds == 0, "seeds=%d" % s.play.seeds)
	s.advance_game(45.0)
	var carrot: CultivatedPlant = s.play.cultivation.plants[0]
	check("plant.carrot_boosts_spread", carrot.mature and not s.play.cultivation.boost.is_empty() and _boost_max(s) >= 3000, "boost max=%d" % _boost_max(s))
	s.cycle_plant(1)
	var kiwi_target: Vector2 = Coords.cell_center_logic(Vector2i(22, 24))
	s.position = Coords.cell_center_logic(Vector2i(24, 21))
	var kiwi_res: Dictionary = s.fire(false, kiwi_target)
	s.advance_game(1.5)
	check("plant.kiwi_placed", kiwi_res["ok"] and s.play.cultivation.count(&"kiwi") == 1, s.last_message)
	s.advance_game(80.0)
	var heal_item: Dictionary = {}
	for item: Dictionary in s.play.pickups.items:
		if String(item["kind"]) == GroundPickups.KIND_HEAL_FRUIT:
			heal_item = item
	check("plant.kiwi_drops_heal_fruit", not heal_item.is_empty())
	if not heal_item.is_empty():
		s.play.damage_player(5)
		var hp0: int = s.play.hp
		s.position = Vector2(float(heal_item["x"]), float(heal_item["y"]))
		s.advance_game(0.25)
		check("plant.kiwi_heals_hp", s.play.hp == hp0 + 2, "hp %d -> %d" % [hp0, s.play.hp])
	# a failed placement (not mature ground) gives the seeds back
	var seeds_before: int = s.play.seeds
	s.cycle_plant(-1)
	var bad: Dictionary = s.fire(false, Coords.cell_center_logic(Vector2i(24, 16)))
	s.advance_game(2.0)
	check("plant.failed_placement_refunds", bad["ok"] and s.play.seeds == seeds_before and s.play.reserved_seeds == 0 and s.play.cultivation.count(&"carrot") == 1, "seeds=%d" % s.play.seeds)

# ---------------------------------------------------------------- walls / non-targets

func _wall() -> void:
	var s: RefCounted = new_session()
	var found: bool = false
	var player_cell: Vector2i = Vector2i.ZERO
	var far_cell: Vector2i = Vector2i.ZERO
	var wall_cell: Vector2i = Vector2i.ZERO
	for y: int in range(2, Session.HEIGHT - 2):
		for x: int in range(2, Session.WIDTH - 10):
			if found:
				break
			for k: int in range(1, 5):
				var ok: bool = free_cell(s, Vector2i(x, y)) and free_cell(s, Vector2i(x - 1, y)) and free_cell(s, Vector2i(x + k + 1, y)) and free_cell(s, Vector2i(x + k + 2, y)) and free_cell(s, Vector2i(x + k + 3, y))
				for w: int in range(1, k + 1):
					ok = ok and s.placement.projectile_blocked_cell(Vector2i(x + w, y)) and s.state.terrain[y * Session.WIDTH + x + w] != Session.T_WATER
				if ok:
					found = true
					player_cell = Vector2i(x, y)
					wall_cell = Vector2i(x + 1, y)
					far_cell = Vector2i(x + k + 2, y)
					break
	check("wall.test_row_found", found, "player=%s wall=%s far=%s" % [player_cell, wall_cell, far_cell])
	s.position = Coords.cell_center_logic(player_cell)
	var stops: Array[Vector2] = []
	s.projectiles.blocked.connect(func(_k: String, pt: Vector2) -> void: stops.append(pt))
	var seeds0: int = s.play.seeds
	var res: Dictionary = s.fire(false, Coords.cell_center_logic(far_cell))
	s.advance_game(2.0)
	var seed_cells: int = stage_count(s, WorldState.STAGE_SEED)
	check("wall.shot_stops_before_wall", res["ok"] and stops.size() == 1 and stops[0].x < float(wall_cell.x * Config.TILE_PX) and stops[0].x > float(player_cell.x * Config.TILE_PX), "stop=%s wall x>=%d" % [stops, wall_cell.x * Config.TILE_PX])
	check("wall.nothing_behind_wall", seed_cells == 0 and s.play.seeds == seeds0 - 1 and s.projectiles.shots.is_empty() and s.play.landing_counter == 0, "seed cells=%d landing_counter=%d" % [seed_cells, s.play.landing_counter])
	var moist0: int = 0
	for i: int in s.state.tile_count():
		moist0 += s.state.moisture[i]
	s.fire(true, Coords.cell_center_logic(far_cell))
	s.advance_game(2.0)
	var moist1: int = 0
	for i: int in s.state.tile_count():
		moist1 += s.state.moisture[i]
	check("wall.water_stops_too", moist1 == moist0 and s.shots_blocked_by_wall == 2, "moisture %d/%d blocked=%d" % [moist0, moist1, s.shots_blocked_by_wall])
	# a cultivated shot into a wall refunds its reserved seeds
	s.cycle_plant(1)
	var before: int = s.play.seeds
	s.fire(false, Coords.cell_center_logic(far_cell))
	s.advance_game(2.0)
	check("wall.cultivated_refunded", s.play.seeds == before and s.play.reserved_seeds == 0 and s.play.inflight.get(&"carrot", 0) == 0)
	# scatter never reaches across a thin obstacle: land right beside the wall, no tile behind it is planted
	s.play.seeds = 20
	s.cycle_plant(-1)
	var beside: Vector2 = Coords.cell_center_logic(Vector2i(player_cell.x, player_cell.y)) + Vector2(2.0, 0.0)
	s.projectiles.landed.emit("seed", beside)
	var behind_planted: bool = false
	for i: int in s.state.tile_count():
		if s.state.stage[i] == WorldState.STAGE_SEED and i % Session.WIDTH >= wall_cell.x + 1 and i / Session.WIDTH == wall_cell.y and i % Session.WIDTH <= far_cell.x + 1:
			behind_planted = true
	check("wall.scatter_filtered_across_wall", not behind_planted, "filtered=%d" % s.scatter_filtered)
	# sealed interior cells stop shots
	var s2: RefCounted = new_session()
	var rebuilt: RefCounted = s2.placement
	rebuilt.seal_enclosed = false
	rebuilt.rebuild()
	var before_obstacle: PackedByteArray = rebuilt.obstacle.duplicate()
	rebuilt.seal_enclosed = true
	rebuilt.rebuild()
	var sealed: Array[int] = []
	for i: int in before_obstacle.size():
		if rebuilt.obstacle[i] == 1 and before_obstacle[i] == 0:
			sealed.append(i)
	var all_block: bool = true
	for i: int in sealed:
		all_block = all_block and rebuilt.projectile_blocked_cell(Vector2i(i % Session.WIDTH, i / Session.WIDTH))
	check("wall.sealed_interior_blocks_shots", sealed.size() > 0 and all_block, "sealed cells=%d" % sealed.size())

func _non_target() -> void:
	var s: RefCounted = new_session()
	var green0: int = s.state.greened_count
	var mature0: int = s.state.mature_count
	# a seed shot into the middle of the pond (passes over water, lands on a non-target) and direct landings on a wall and the ring
	var pond_mid: Vector2 = Coords.cell_center_logic(Vector2i(41, 5))
	s.position = Coords.cell_center_logic(Vector2i(36, 5))
	s.play.land_seed(pond_mid)
	check("nontarget.water_landing_plants_nothing", s.play.last_scatter.is_empty() and s.state.greened_count == green0)
	s.play.land_water(pond_mid)
	s.play.land_seed(Coords.cell_center_logic(Vector2i(0, 0)))
	var wall_cell: Vector2i = Vector2i(-1, -1)
	for i: int in s.state.tile_count():
		if s.placement.obstacle[i] == 1 and s.state.terrain[i] == s.placement.building_id:
			wall_cell = Vector2i(i % Session.WIDTH, i / Session.WIDTH)
			break
	s.play.land_seed(Coords.cell_center_logic(wall_cell))
	s.play.land_water(Coords.cell_center_logic(wall_cell))
	var stray: int = 0
	var wet: int = 0
	for i: int in s.state.tile_count():
		if s.state.target[i] == 0:
			stray += s.state.stage[i]
			wet += s.state.moisture[i]
	check("nontarget.building_water_untouched", stray == 0 and wet == 0 and s.state.greened_count == green0 and s.state.mature_count == mature0 and s.state.counters_consistent(), "wall=%s" % wall_cell)
	var r1: Dictionary = s.fire(false, pond_mid)
	s.advance_game(3.0)
	check("nontarget.shot_over_water_no_gain", r1["ok"] and s.state.greened_count == green0 and s.projectiles.shots.is_empty())

func _pause() -> void:
	var s: RefCounted = new_session()
	var spot: Vector2i = open_spot(s, 2, 12)
	s.state.set_stage(s.state.index_of(spot.x, spot.y), WorldState.STAGE_SEED)
	s.fire(false, Coords.cell_center_logic(spot + Vector2i(3, 0)))
	s.advance_game(0.1)
	var plant: CultivatedPlant = null
	s.cycle_plant(1)
	s.play.cultivation.try_place(&"carrot", Coords.cell_center_logic(Vector2i(24, 24)))
	plant = s.play.cultivation.plants[0] if s.play.cultivation.plants.size() > 0 else null
	var shot_pos: Vector2 = s.projectiles.shots[0]["position"]
	var snapshot: Array = [s.clock.elapsed, s.play.elapsed, s.state.growth[s.state.index_of(spot.x, spot.y)], s.play.sources[0].timer, plant.age if plant != null else -1.0, s.play.production_time, s.play.pickups.count()]
	var seeds0: int = s.play.seeds
	s.paused = true
	s.advance_game(20.0)
	s.advance(5.0)
	var again: Array = [s.clock.elapsed, s.play.elapsed, s.state.growth[s.state.index_of(spot.x, spot.y)], s.play.sources[0].timer, plant.age if plant != null else -1.0, s.play.production_time, s.play.pickups.count()]
	check("pause.everything_stops", snapshot == again and (s.projectiles.shots[0]["position"] as Vector2) == shot_pos, "%s" % [again])
	var fire_paused: Dictionary = s.fire(false, s.position + Vector2(10, 0))
	check("pause.no_fire", not fire_paused["ok"] and fire_paused["reason"] == "paused" and s.play.seeds == seeds0)
	var fruit_pos: Vector2 = s.position
	s.play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, fruit_pos, 1)
	s.advance_game(5.0)
	check("pause.no_collect", s.play.pickups.count() == 1 + int(snapshot[6]) and s.play.seeds == seeds0)
	s.paused = false
	s.advance_game(0.25)
	check("pause.resume_no_banking", is_equal_approx(s.clock.elapsed - float(snapshot[0]), 0.25) and is_equal_approx(s.play.elapsed - float(snapshot[1]), 0.25), "dt=%f" % (s.clock.elapsed - float(snapshot[0])))

func _counters() -> void:
	var s: RefCounted = new_session()
	var targets: int = s.state.target_count
	s.state.debug_fill_stage(Rect2i(0, 0, Session.WIDTH, Session.HEIGHT), WorldState.STAGE_MATURE)
	check("counters.full_matches_recount", s.state.greened_count == s.state.recount_greened() and s.state.counters_consistent() and s.state.is_fully_greened() and s.greening_percent() == 100 and is_equal_approx(s.greening_ratio(), 1.0))
	var any: int = -1
	for i: int in s.state.tile_count():
		if s.state.target[i] == 1:
			any = i
			break
	s.state.set_stage(any, WorldState.STAGE_SEED)
	check("counters.almost_full_is_not_100", s.greening_percent() == 99 and not s.state.is_fully_greened() and s.greening_ratio() < 1.0 and s.state.greened_count == targets - 1 and s.state.counters_consistent(), "percent=%d ratio=%.6f" % [s.greening_percent(), s.greening_ratio()])
	s.state.set_stage(any, WorldState.STAGE_SPROUT1)
	check("counters.sprout_counts", s.state.is_fully_greened() and s.greening_percent() == 100)

func _debug_refill_default() -> void:
	var s: RefCounted = new_session()
	s.play.seeds = 0
	s.play.water = 0.0
	check("debug.refill_off_by_default", not s.debug_refill_enabled and not s.debug_refill() and s.play.seeds == 0 and s.play.water == 0.0)
	s.debug_refill_enabled = true
	check("debug.refill_explicit", s.debug_refill() and s.play.seeds > 0 and s.play.water > 0.0)

# ---------------------------------------------------------------- display layer (in-engine input injection only)

func _main_checks() -> void:
	PocInput.register()
	var main: Node = load("res://scenes/poc.tscn").instantiate()
	root.add_child(main)
	await _frames(2)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	var s: RefCounted = main.session
	main.tick(0.0, Vector2.ZERO)
	check("main.hud_shows_resources", main.hud.text.contains("種") and main.hud.text.contains("水") and main.hud.text.contains("HP") and main.hud.text.contains("緑化"), main.hud.text.replace("\n", " | "))
	var snap: Dictionary = main.play_view.snapshot()
	check("main.view_built", snap["sources"] == 1 and main.play_view.cell_multimesh.instance_count == Session.WIDTH * Session.HEIGHT)
	# same normalised screen position -> same logical landing, in both resolutions and after camera follow
	var fire640: Dictionary = main.click_fire(Vector2(350, 200), false)
	main.tick(0.0, Vector2.ZERO)
	var land640: Vector2 = fire640["landing"]
	check("click.fire_640", fire640["ok"] and s.projectiles.shots.size() == 1, str(fire640))
	for i: int in 20:
		main.tick(0.1, Vector2.ZERO)
	var seeds_a: int = s.play.seeds
	main.set_resolution(1, Vector2i(1920, 1080))
	main.tick(0.0, Vector2.ZERO)
	var fire960: Dictionary = main.click_fire(Vector2(525, 300), false)
	var land960: Vector2 = fire960["landing"]
	check("click.same_logic_target_960", fire960["ok"] and land960.distance_to(land640) < 0.5 and (fire960["logic"] as Vector2).distance_to(fire640["logic"]) < 0.5, "640=%s 960=%s" % [land640, land960])
	check("click.range_is_logical_px", (land960 - s.position).length() <= s.play_tuning.projectile_range_px + 0.001 and (land640 - s.position).length() <= s.play_tuning.projectile_range_px + 0.001)
	# after the camera followed a move, the same screen position is the same offset from the player
	var off0: Vector2 = (main.pick_ground(Vector2(525, 300))["logic"] as Vector2) - s.position
	for i: int in 15:
		main.tick(0.1, Vector2(1, 0))
	var off1: Vector2 = (main.pick_ground(Vector2(525, 300))["logic"] as Vector2) - s.position
	check("click.follow_keeps_offset", off0.distance_to(off1) < 0.5, "off0=%s off1=%s" % [off0, off1])
	# UI and margin rejection
	var seeds_b: int = s.play.seeds
	var shots_b: int = s.projectiles.shots.size()
	var ui_click: Dictionary = main.click_fire(main.pause_button.get_global_rect().get_center(), false)
	var margin_click: Dictionary = main.click_fire(Vector2(-5, 40), true)
	check("click.ui_and_margin_rejected", not ui_click["ok"] and ui_click["reason"] == "ui" and not margin_click["ok"] and s.play.seeds == seeds_b and s.projectiles.shots.size() == shots_b and seeds_a >= 0)
	# injected mouse buttons: left = seed, right = water, wheel / Tab = plant switch
	for i: int in 40:
		main.tick(0.1, Vector2.ZERO)
	var seeds_c: int = s.play.seeds
	var water_c: float = s.play.water
	var left: InputEventMouseButton = InputEventMouseButton.new()
	left.button_index = MOUSE_BUTTON_LEFT
	left.pressed = true
	left.position = Vector2(300, 200)
	left.global_position = left.position
	Input.parse_input_event(left)
	await _frames(2)
	left.pressed = false
	Input.parse_input_event(left)
	var right: InputEventMouseButton = InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = Vector2(300, 200)
	right.global_position = right.position
	Input.parse_input_event(right)
	await _frames(2)
	right.pressed = false
	Input.parse_input_event(right)
	check("input.left_seed_right_water", s.play.seeds == seeds_c - 1 and s.play.water < water_c, "seeds %d->%d water %f->%f" % [seeds_c, s.play.seeds, water_c, s.play.water])
	var sel0: int = s.play.selected_index
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = Vector2(300, 200)
	Input.parse_input_event(wheel)
	await _frames(2)
	var sel1: int = s.play.selected_index
	var tab: InputEventKey = InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	Input.parse_input_event(tab)
	await _frames(2)
	tab.pressed = false
	Input.parse_input_event(tab)
	check("input.wheel_and_tab_switch_plant", sel1 == (sel0 + 1) % 3 and s.play.selected_index == (sel0 + 2) % 3, "%d %d %d" % [sel0, sel1, s.play.selected_index])
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = KEY_E
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	e.pressed = false
	Input.parse_input_event(e)
	check("input.interact_inspects", main.notice.text.contains("成長") or main.notice.text.contains("緑化対象外"), main.notice.text)
	# pause blocks the click path
	main.toggle_pause()
	var paused_click: Dictionary = main.click_fire(Vector2(300, 200), false)
	check("main.paused_click_denied", not paused_click["ok"] and paused_click["reason"] == "paused")
	main.toggle_pause()
	# display sync is incremental: after one planted cell only that cell is rewritten
	main.tick(0.0, Vector2.ZERO)
	var updates0: int = main.play_view.cell_updates
	var spot2: Vector2i = open_spot(s, 0, 14)
	var idx: int = s.state.index_of(spot2.x, spot2.y)
	s.state.set_stage(idx, WorldState.STAGE_SEED)
	main.tick(0.0, Vector2.ZERO)
	check("view.incremental_cell_update", main.play_view.cell_updates - updates0 >= 1 and main.play_view.cell_updates - updates0 < 20, "rewrote %d of %d cells" % [main.play_view.cell_updates - updates0, Session.WIDTH * Session.HEIGHT])
	main.queue_free()
	await _frames(2)
