extends SceneTree
## POC-07 logic checks for the playable town (data/poc/maps/town_01.json). Headless OK:
## godot --headless --path <repo> --script res://tests/poc/map/logic.gd
## Each condition runs once; long conditions are fast-forwarded with advance_game() in 0.25 s pieces. No OS-level input.
## Contact damage is switched off only in the scenario where a bot has to clear the region (T8); everything else uses defaults.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const MAP_PATH: String = "res://data/poc/maps/town_01.json"
## Body half size of a 1.6 m wide walker (the corridor requirement of the main route).
const WIDE_HALF: Vector2 = Vector2(8.0, 8.0)

var failures: int = 0
var passes: int = 0
var sessions: Array[RefCounted] = []
var report: PackedStringArray = []
var data: Dictionary = {}
var layout: Dictionary = {}
var main: Node

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
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	data = parsed if parsed is Dictionary else {}
	layout = data.get("layout", {})
	_composition()
	_game_elements()
	_reachability()
	_target_set_and_water()
	_regeneration()
	await _start_occlusion()
	_default_launch_flags()
	_clear_stable_complete()
	for s: RefCounted in sessions:
		s.close()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	for line: String in report:
		print("REPORT ", line)
	quit(1 if failures > 0 else 0)

func new_session() -> RefCounted:
	var size: Vector2i = Session.town_size()
	var s: RefCounted = Session.new(size.x, size.y)
	if not s.load_combat(Session.TOWN_SETUP):
		print("FAIL load_combat(town)")
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

func cell_of(value: Variant) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))

func rect_of(value: Variant) -> Rect2i:
	return Rect2i(int(value[0]), int(value[1]), int(value[2]), int(value[3]))

## 4-neighbour reachability from `from_cell` over cells where a body of half size `half` fits. cell -> [distance, parent].
func reach_map(s: RefCounted, from_cell: Vector2i = Vector2i(-1, -1), half: Vector2 = Vector2.ZERO) -> Dictionary:
	var body: Vector2 = Config.player_half_px() if half == Vector2.ZERO else half
	var start: Vector2i = Coords.logic_to_cell(s.position) if from_cell.x < 0 else from_cell
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
			if not Walker.is_clear(s.state, Config.TILE_PX, cpx(n), body):
				continue
			seen[n] = [int(seen[c][0]) + 1, c]
			queue.append(n)
	return seen

## Reachable cell 4..8 cells from `target_px` with a clear shot line, nearest to the BFS origin. (-1,-1) if none.
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

func target_signature(s: RefCounted) -> String:
	return "%d/%d/%d/%d/%d" % [hash(s.state.terrain), hash(s.state.target), hash(s.state.stage), s.state.target_count, s.state.greened_count]

func building_instances(s: RefCounted) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for inst: Dictionary in s.placement.instances:
		if inst["kind"] == "building":
			list.append(inst)
	return list

# ---------------------------------------------------------------- T1 composition

func _composition() -> void:
	var s: RefCounted = new_session()
	var st: WorldState = s.state
	var size: Vector2i = Session.town_size()
	check("map.size_about_45m", size.x == st.width and size.y == st.height and absf(float(size.x) * Config.CELL_M - 44.8) < 0.01 and size.x >= 100 and size.x <= 125, "%dx%d cells = %.1f x %.1f m" % [size.x, size.y, size.x * Config.CELL_M, size.y * Config.CELL_M])
	var buildings: Array[Dictionary] = building_instances(s)
	var shapes: Dictionary = {}
	for inst: Dictionary in buildings:
		var cells: PackedInt32Array = s.placement.cells_of[inst["id"]]
		var lo: Vector2i = Vector2i(1 << 20, 1 << 20)
		var hi: Vector2i = Vector2i(-1, -1)
		for index: int in cells:
			lo = Vector2i(mini(lo.x, index % st.width), mini(lo.y, index / st.width))
			hi = Vector2i(maxi(hi.x, index % st.width), maxi(hi.y, index / st.width))
		shapes[inst["asset"]] = [hi.x - lo.x + 1, hi.y - lo.y + 1, cells.size()]
	check("map.buildings_5_to_8_distinct_shapes", buildings.size() >= 5 and buildings.size() <= 8 and shapes.size() == buildings.size(), "%d buildings, footprints (w,h,cells)=%s" % [buildings.size(), shapes])
	var puddles: int = 0
	var cars: int = 0
	var lamps: int = 0
	var trees: int = 0
	var props: int = 0
	for inst: Dictionary in s.placement.instances:
		puddles += 1 if inst["kind"] == "puddle" else 0
		cars += 1 if inst["asset"] == "PRP-041" else 0
		lamps += 1 if inst["asset"] == "PRP-001" else 0
		trees += 1 if inst["kind"] == "tree" else 0
		props += 1 if inst["kind"] == "prop" else 0
	check("map.props_cars_puddles_trees", puddles >= 3 and cars >= 2 and lamps >= 2 and trees >= 4 and props >= 10, "puddles=%d cars=%d lamps=%d trees=%d props=%d" % [puddles, cars, lamps, trees, props])
	var paved: int = 0
	var paved_targets: int = 0
	for i: int in st.tile_count():
		if st.terrain[i] == Session.T_PAVED:
			paved += 1
			paved_targets += st.target[i]
	check("map.paved_streets_are_greening_targets", paved > 1500 and paved == paved_targets, "paved cells=%d (targets %d)" % [paved, paved_targets])
	var unique: Dictionary = {}
	for inst: Dictionary in s.placement.instances:
		unique[inst["id"]] = true
	check("map.instance_ids_unique_and_catalog_aux", unique.size() == s.placement.instances.size() and s.placement.verify_hashes(), "%d instances, %d adopted assets" % [unique.size(), s.placement.catalog.size()])
	var aux_ok: bool = true
	var vine_buildings: int = 0
	for inst: Dictionary in buildings:
		var entry: Dictionary = s.placement.catalog[inst["asset"]]
		aux_ok = aux_ok and entry["collision"] == "walls" and entry["occlusion_group"] == "instance" and entry.has("vine_surfaces")
		vine_buildings += 1 if (entry["vine_surfaces"] as Array).size() > 0 else 0
	for inst: Dictionary in s.placement.instances:
		if inst["kind"] != "puddle":
			aux_ok = aux_ok and not (s.placement.cells_of[inst["id"]] as PackedInt32Array).is_empty()
	check("map.every_object_has_collision_cells_and_aux_defs", aux_ok and vine_buildings >= 4, "buildings with vine surfaces=%d" % vine_buildings)

# ---------------------------------------------------------------- T2 game elements

func _game_elements() -> void:
	var s: RefCounted = new_session()
	var st: WorldState = s.state
	var safe: Rect2i = rect_of(layout["safe_zone"])
	check("elements.zones", st.zone_count == 2 and st.zone_state[0] == WorldState.ZONE_COMPLETE and st.zone_state[1] == WorldState.ZONE_UNCONQUERED, "states=%s" % [st.zone_state])
	var in_safe: bool = true
	for y: int in range(safe.position.y, safe.end.y):
		for x: int in range(safe.position.x, safe.end.x):
			in_safe = in_safe and st.zone_of[st.index_of(x, y)] == 0 and st.terrain[st.index_of(x, y)] == Session.T_SAFE
	check("elements.safe_zone_is_zone_0_safe_terrain_and_initial_green", in_safe and st.zone_greened_count[0] == st.zone_target_count[0] and st.zone_greened_count[0] > 400 and st.zone_of[st.index_of(s.placement.player_start_cell.x, s.placement.player_start_cell.y)] == 0, "zone0 greened %d/%d" % [st.zone_greened_count[0], st.zone_target_count[0]])
	var src_ok: bool = s.play.sources.size() == (layout["seed_sources"] as Array).size() and s.play.sources.size() >= 1
	for source: SeedSource in s.play.sources:
		var cell: Vector2i = Coords.logic_to_cell(source.position)
		src_ok = src_ok and safe.has_point(cell) and st.zone_of[st.index_of(cell.x, cell.y)] == 0
	check("elements.seed_sources_in_safe_zone", src_ok, "%d sources" % s.play.sources.size())
	check("elements.nests_in_combat_zone", s.enemies.nests.size() == 3 and s.enemies.alive_nest_count(1) == 3 and s.combat_zone() == 1 and s.enemies.nests.size() == (layout["nests"] as Array).size(), "nests=%d" % s.enemies.nests.size())
	var water: Rect2i = rect_of((layout["constant_water"] as Array)[0])
	var all_water: bool = true
	for y: int in range(water.position.y, water.end.y):
		for x: int in range(water.position.x, water.end.x):
			var i: int = st.index_of(x, y)
			var is_island: bool = rect_of(layout["island"]).has_point(Vector2i(x, y))
			all_water = all_water and (is_island or (st.terrain[i] == Session.T_WATER and not st.is_walkable(x, y)))
	check("elements.constant_water_not_walkable", all_water and water.size.x * water.size.y > 100, "water rect %s" % water)
	var island: Rect2i = rect_of(layout["island"])
	var reach: Dictionary = reach_map(s)
	var island_target: bool = true
	var island_unreachable: bool = true
	for y: int in range(island.position.y, island.end.y):
		for x: int in range(island.position.x, island.end.x):
			island_target = island_target and st.target[st.index_of(x, y)] == 1 and st.zone_of[st.index_of(x, y)] == 1
			island_unreachable = island_unreachable and not reach.has(Vector2i(x, y))
	var isolated: bool = true
	var radius: float = s.sim_tuning.spread_radius_tiles
	for y: int in st.height:
		for x: int in st.width:
			if st.target[st.index_of(x, y)] == 0 or island.has_point(Vector2i(x, y)):
				continue
			for c: Vector2i in [island.position, island.end - Vector2i(1, 1), Vector2i(island.position.x, island.end.y - 1), Vector2i(island.end.x - 1, island.position.y)]:
				if Vector2(x - c.x, y - c.y).length() <= radius + 0.001:
					isolated = false
	check("elements.island_target_unreachable_isolated", island_target and island_unreachable and isolated, "island %s target=%s unreachable=%s isolated=%s" % [island, island_target, island_unreachable, isolated])
	check("elements.frontier_between_zones", _frontier_cells(s) > 40, "zone0/zone1 border walkable cells=%d" % _frontier_cells(s))
	check("elements.fixed_seeds", s.enemy_tuning.rng_seed == 20261018 and st.sprout_seed == 81026)

func _frontier_cells(s: RefCounted) -> int:
	var st: WorldState = s.state
	var count: int = 0
	for y: int in st.height - 1:
		for x: int in st.width - 1:
			var i: int = st.index_of(x, y)
			if st.is_walkable(x, y) and st.zone_of[i] == 0:
				for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
					if st.in_bounds(x + d.x, y + d.y) and st.zone_of[st.index_of(x + d.x, y + d.y)] == 1 and st.is_walkable(x + d.x, y + d.y):
						count += 1
						break
	return count

# ---------------------------------------------------------------- T3 reachability

func _reachability() -> void:
	var s: RefCounted = new_session()
	var st: WorldState = s.state
	var reach: Dictionary = reach_map(s)
	var wide: Dictionary = reach_map(s, Vector2i(-1, -1), WIDE_HALF)
	check("reach.start_free_and_walkable_area", reach.size() > 6000 and wide.size() > 4000, "reachable cells %d (wide 1.6 m body: %d)" % [reach.size(), wide.size()])
	# Main route waypoints: every one reachable, also with a 1.6 m wide body (no pinch point on the main way).
	var route_ok: bool = true
	var wide_ok: bool = true
	var route_len: int = 0
	var previous: Vector2i = s.placement.player_start_cell
	for value: Variant in layout["route"]:
		var cell: Vector2i = cell_of(value)
		route_ok = route_ok and reach.has(cell)
		wide_ok = wide_ok and wide.has(cell)
		var leg: Dictionary = reach_map(s, previous, WIDE_HALF)
		if leg.has(cell):
			route_len += int(leg[cell][0])
		else:
			wide_ok = false
		previous = cell
	check("reach.route_loop_all_waypoints_wide_body", route_ok and wide_ok, "waypoints=%d, loop length %d cells = %.0f m" % [(layout["route"] as Array).size(), route_len, route_len * Config.CELL_M])
	report.append("route loop (1.6 m body): %d cells = %.0f m, walk %.0f s at %.1f m/s" % [route_len, route_len * Config.CELL_M, route_len * Config.CELL_M / Config.WALK_SPEED_MPS, Config.WALK_SPEED_MPS])
	# Nests: a clear shooting spot (4..8 cells away) reachable by the normal body, and by the wide body.
	var spots_ok: bool = true
	var wide_spots_ok: bool = true
	var in_range: bool = true
	for nest: Nest in s.enemies.nests:
		var center: Vector2 = nest.center_px(Config.TILE_PX)
		var spot: Vector2i = shoot_spot(s, reach, center)
		var wide_spot: Vector2i = shoot_spot(s, wide, center)
		spots_ok = spots_ok and spot.x >= 0
		wide_spots_ok = wide_spots_ok and wide_spot.x >= 0
		if spot.x >= 0:
			in_range = in_range and cpx(spot).distance_to(center) <= s.play_tuning.projectile_range_px and not s.shot_blocked(cpx(spot), center)
	check("reach.every_nest_walkable_and_shootable", spots_ok and in_range, "nests=%d range=%.0f px" % [s.enemies.nests.size(), s.play_tuning.projectile_range_px])
	check("reach.every_nest_shootable_from_wide_route", wide_spots_ok)
	# Island shootable (a reachable cell inside the range with a clear line).
	var island: Rect2i = rect_of(layout["island"])
	var island_px: Vector2 = cpx(island.position + island.size / 2)
	var island_spot: bool = false
	for key: Variant in reach.keys():
		var c: Vector2i = key
		if cpx(c).distance_to(island_px) < s.play_tuning.projectile_range_px - 4.0 and not s.shot_blocked(cpx(c), island_px):
			island_spot = true
			break
	check("reach.island_shootable", island_spot)
	# Seed sources: the player can stand next to each source and every possible drop point is reachable (pickups can be collected).
	var pick_ok: bool = true
	var checked: int = 0
	for source: SeedSource in s.play.sources:
		var source_cell: Vector2i = Coords.logic_to_cell(source.position)
		pick_ok = pick_ok and reach.has(source_cell)
		for angle: int in 24:
			for radius_px: float in [s.play_tuning.source_drop_radius_min_px, s.play_tuning.source_drop_radius_max_px]:
				var drop: Vector2 = source.position + Vector2.from_angle(TAU * float(angle) / 24.0) * radius_px
				var near: bool = false
				for dy: int in range(-3, 4):
					for dx: int in range(-3, 4):
						var c2: Vector2i = Coords.logic_to_cell(drop) + Vector2i(dx, dy)
						if reach.has(c2) and cpx(c2).distance_to(drop) <= s.play_tuning.pickup_collect_radius_px - 1.0:
							near = true
				pick_ok = pick_ok and near
				checked += 1
	check("reach.seed_source_drops_collectable", pick_ok and checked > 0, "drop points checked=%d" % checked)
	# Water: a shore cell next to the constant water is reachable and refills (wide body too).
	var bank: Vector2i = cell_of((layout["hub_cells"] as Dictionary)["water_bank"])
	check("reach.water_bank_reachable_and_refills", reach.has(bank) and wide.has(Vector2i(41, 55)) and s.play.is_near_water(cpx(bank)), "bank %s" % bank)
	var plaza: Vector2i = cell_of((layout["hub_cells"] as Dictionary)["plaza"])
	check("reach.plaza_and_alley_reachable", reach.has(plaza) and wide.has(plaza) and wide.has(Vector2i(57, 20)), "plaza %s" % plaza)
	# Everything walkable that is not enclosed is reached (no stranded walkable pockets other than the island ring).
	var stranded: int = 0
	for y: int in st.height:
		for x: int in st.width:
			if st.is_walkable(x, y) and not reach.has(Vector2i(x, y)) and Walker.is_clear(st, Config.TILE_PX, cpx(Vector2i(x, y)), Config.player_half_px()):
				stranded += 1
	check("reach.no_stranded_open_pockets_except_island", stranded <= island.size.x * island.size.y, "free but unreachable cells=%d (island %d)" % [stranded, island.size.x * island.size.y])
	# The enemy's start zone: the player's start is in the safe zone and the first waypoint legs leave the safe zone.
	check("reach.start_in_safe_zone", s.player_zone() == 0)

# ---------------------------------------------------------------- T4 target set, water, puddles

func _target_set_and_water() -> void:
	var s: RefCounted = new_session()
	var st: WorldState = s.state
	var p: RefCounted = s.placement
	var bad: int = 0
	var excluded: int = 0
	var expect: int = 0
	for i: int in st.tile_count():
		var t: int = st.terrain[i]
		var open_ground: bool = t == Session.T_WASTE or t == Session.T_SAFE or t == Session.T_SHORE or t == Session.T_PAVED
		expect += 1 if open_ground else 0
		if t == Session.T_BUILDING or t == Session.T_WATER or p.obstacle[i] == 1:
			excluded += 1
			bad += st.target[i]
	check("targets.exclude_buildings_water_blocked_cells", bad == 0 and excluded > 2000 and expect == st.target_count and st.counters_consistent(), "targets=%d expect=%d excluded=%d sealed interiors=%d" % [st.target_count, expect, excluded, p.sealed_count])
	var puddle_cells: int = 0
	var puddle_ok: bool = true
	var water_ok: bool = true
	var water_cells: int = 0
	for y: int in st.height:
		for x: int in st.width:
			var cell: Vector2i = Vector2i(x, y)
			var i: int = st.index_of(x, y)
			if p.is_puddle(cell):
				puddle_cells += 1
				puddle_ok = puddle_ok and st.is_walkable(x, y) and not p.is_water_source(cell) and not st.terrain_def_at(i).is_waterside and st.target[i] == 1 and not p.blocks_walk(cell)
			if st.terrain[i] == Session.T_WATER:
				water_cells += 1
				water_ok = water_ok and not st.is_walkable(x, y) and p.is_water_source(cell) and p.blocks_walk(cell) and st.target[i] == 0
	check("water.puddles_walkable_decor_only", puddle_ok and puddle_cells > 20, "puddle cells=%d" % puddle_cells)
	check("water.constant_water_blocks_and_supplies", water_ok and water_cells > 150, "water cells=%d" % water_cells)
	# Puddle: standing on one gives no water; the shore of the constant water does.
	var puddle_pos: Vector2 = Vector2.INF
	for inst: Dictionary in p.instances:
		if inst["kind"] == "puddle" and inst["id"] == "puddle_03":
			puddle_pos = Coords.ground_to_logic(inst["pos"])
	s.play.water = 10.0
	s.position = puddle_pos
	var near_puddle: bool = s.play.is_near_water(puddle_pos)
	s.advance_game(2.0)
	var no_refill: bool = s.play.water <= 10.0 + 0.001
	var bank: Vector2i = cell_of((layout["hub_cells"] as Dictionary)["water_bank"])
	s.position = cpx(bank)
	s.advance_game(2.0)
	check("water.puddle_gives_no_water_shore_does", puddle_pos != Vector2.INF and not near_puddle and no_refill and s.play.water > 10.0 + 10.0, "after 2 s on the shore: %.1f" % s.play.water)
	# Shots: blocked by walls, not by decorative puddles; no plant ever lands on a non-target.
	var wall_cell: Vector2i = Vector2i(-1, -1)
	for index: int in p.cells_of["bld_gallery_01"]:
		wall_cell = Vector2i(index % st.width, index / st.width)
		break
	check("shots.building_blocks_projectile_puddle_does_not", wall_cell.x >= 0 and p.projectile_blocked_cell(wall_cell) and not p.projectile_blocked_cell(Vector2i(40, 92)), "wall cell %s" % wall_cell)

# ---------------------------------------------------------------- T5 regeneration

func _regeneration() -> void:
	var a: RefCounted = new_session()
	var b: RefCounted = new_session()
	var same_ids: bool = a.placement.instances.size() == b.placement.instances.size()
	for k: int in mini(a.placement.instances.size(), b.placement.instances.size()):
		var ia: Dictionary = a.placement.instances[k]
		var ib: Dictionary = b.placement.instances[k]
		same_ids = same_ids and ia["id"] == ib["id"] and ia["asset"] == ib["asset"] and ia["pos"] == ib["pos"] and is_equal_approx(ia["yaw"], ib["yaw"]) and a.placement.cells_of[ia["id"]] == b.placement.cells_of[ib["id"]]
	check("regen.instances_identical", same_ids and a.placement.obstacle == b.placement.obstacle and a.placement.puddle == b.placement.puddle and a.placement.owner_index == b.placement.owner_index)
	var file_ids: PackedStringArray = []
	for entry: Variant in data["instances"]:
		file_ids.append(String(entry["instance_id"]))
	var session_ids: PackedStringArray = []
	for inst: Dictionary in a.placement.instances:
		session_ids.append(String(inst["id"]))
	check("regen.instance_ids_fixed_by_data_order", file_ids == session_ids, "%d ids" % file_ids.size())
	check("regen.target_set_identical", target_signature(a) == target_signature(b) and a.state.target == b.state.target and a.state.zone_of == b.state.zone_of and a.base_terrain == b.base_terrain, target_signature(a))
	var nests_a: PackedStringArray = []
	var nests_b: PackedStringArray = []
	for nest: Nest in a.enemies.nests:
		nests_a.append(JSON.stringify(nest.to_dict()))
	for nest: Nest in b.enemies.nests:
		nests_b.append(JSON.stringify(nest.to_dict()))
	var sources_same: bool = a.play.sources.size() == b.play.sources.size()
	for k: int in mini(a.play.sources.size(), b.play.sources.size()):
		sources_same = sources_same and a.play.sources[k].position == b.play.sources[k].position
	check("regen.nests_and_sources_identical", nests_a == nests_b and sources_same)
	run_for(a, 60.0)
	run_for(b, 60.0)
	check("regen.same_seed_same_run", JSON.stringify(a.enemies.to_dict()) == JSON.stringify(b.enemies.to_dict()) and target_signature(a) == target_signature(b) and a.enemies.total_spawned > 0, "spawned=%d" % a.enemies.total_spawned)

# ---------------------------------------------------------------- T6 start position: no occlusion at the start

func _frames(n: int) -> void:
	for i: int in n:
		await process_frame

func _start_occlusion() -> void:
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(2)
	var s: RefCounted = main.session
	check("start.scene_loads_town", s.combat_mode and s.state.width == 112 and s.placement.instances.size() == (data["instances"] as Array).size() and main.occlusion_view != null and main.enemy_view != null, "instances=%d" % s.placement.instances.size())
	check("start.occlusion_groups_cover_buildings", main.occlusion_view.occlusion.entries.size() >= 30, "groups=%d" % main.occlusion_view.occlusion.entries.size())
	for i: int in 30:
		main.tick(0.1, Vector2.ZERO)
	var ov: Node = main.occlusion_view
	check("start.no_occlusion_at_start", ov.occlusion.occluded_groups().is_empty() and ov.faded_instances().is_empty(), "occluded=%s" % str(ov.occlusion.occluded_groups()))
	# Walk the whole route with the real tick(): the occlusion comes and goes, and nothing stays faded at the end.
	var reach: Dictionary = reach_map(s)
	var seen_groups: Dictionary = {}
	var previous: Vector2i = Coords.logic_to_cell(s.position)
	var fade_frames: int = 0
	var frames: int = 0
	for value: Variant in layout["route"]:
		var goal: Vector2i = cell_of(value)
		var local: Dictionary = reach_map(s, previous, WIDE_HALF)
		if not local.has(goal):
			continue
		var path: Array[Vector2i] = []
		var c: Vector2i = goal
		while c != Vector2i(-1, -1):
			path.push_front(c)
			c = local[c][1]
		for k: int in range(0, path.size(), 3):
			s.position = cpx(path[k])
			main.tick(0.05, Vector2.ZERO)
			frames += 1
			for id: String in ov.occlusion.occluded_groups():
				seen_groups[id] = true
			fade_frames += 1 if not ov.occlusion.occluded_groups().is_empty() else 0
		previous = goal
	s.position = Coords.cell_center_logic(s.placement.player_start_cell)
	for i: int in 30:
		main.tick(0.1, Vector2.ZERO)
	var clean: bool = ov.occlusion.occluded_groups().is_empty() and ov.faded_instances().is_empty()
	for id: String in main.placement_view.materials:
		clean = clean and absf(main.placement_view.instance_alpha(id) - 1.0) < 0.0001
	check("start.route_walk_occlusion_comes_and_goes", clean and seen_groups.size() >= 1, "frames=%d with occlusion=%d, groups seen=%s" % [frames, fade_frames, str(seen_groups.keys())])
	main.queue_free()
	await _frames(2)

# ---------------------------------------------------------------- T7 launch flags (the default launch is the town)

func _default_launch_flags() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/poc/poc_main.gd")
	check("launch.default_is_town_and_fixtures_kept", source.contains("current_scene == self") and source.contains("--fixture=02") and source.contains("--fixture=04") and source.contains("--combat") and source.contains("--bare"))

# ---------------------------------------------------------------- T8 clear -> stable -> complete (100 %)

func _clear_stable_complete() -> void:
	var s: RefCounted = new_session()
	var st: WorldState = s.state
	s.enemy_tuning.contact_damage = 0
	# Bound from the settings only, before anything happens.
	var bound: float = s.far.completion_bound_seconds()
	var lap: int = s.far.lap_steps_bound()
	report.append("100%% bound = completion_bound_seconds() = %.1f s (tiles %d, swept targets %d, lap_steps_bound %d, sweep period %d ticks of %.1f s, sweep delay %.0f s)" % [bound, st.tile_count(), s.far.swept_targets(), lap, s.far.sweep_period_ticks(), s.sim_tuning.spread_tick_seconds, s.sim_tuning.far_sweep_start_delay_seconds])
	print("INFO bound=%.1f" % bound)
	run_for(s, 40.0)
	var boars_before_clear: int = s.enemies.boars.size()
	var reach: Dictionary = reach_map(s)
	var walked_all: bool = true
	var total_walk_steps: int = 0
	var killed_in_order: bool = true
	var start_cell: Vector2i = Coords.logic_to_cell(s.position)
	var order: Array[Nest] = []
	for nest: Nest in s.enemies.nests:
		order.append(nest)
	for nest: Nest in order:
		var center: Vector2 = nest.center_px(Config.TILE_PX)
		var local: Dictionary = reach_map(s)
		var spot: Vector2i = shoot_spot(s, local, center)
		var from_cell: Vector2i = Coords.logic_to_cell(s.position)
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
	check("clear.walked_and_shot_all_nests", walked_all and killed_in_order and s.enemies.alive_nest_count(1) == 0, "start %s, walk steps=%d (%.0f s at 0.1 s)" % [start_cell, total_walk_steps, total_walk_steps * 0.1])
	check("clear.zone_is_clearing_not_stable", boars_before_clear > 0 and st.zone_state[1] != WorldState.ZONE_STABLE and s.zone_log.size() >= 1 and s.zone_log[0].contains("巣をすべて壊した"), "boars at clear %d, log=%s" % [s.enemies.boars.size(), s.zone_log])
	var spawned_at_clear: int = s.enemies.total_spawned
	run_for(s, 20.0)
	check("clear.spawning_stopped", s.enemies.total_spawned == spawned_at_clear, "spawned %d -> %d" % [spawned_at_clear, s.enemies.total_spawned])
	# Remaining boars are removed by shooting them (freeze one, stand 5 cells away with a clear line, 3 seeds).
	var boar_kills: int = 0
	var guard: int = 0
	var stable_early: bool = false
	while not s.enemies.boars.is_empty() and guard < 60:
		guard += 1
		var boar: Boar = s.enemies.boars[0]
		boar.wait = 1000000
		var placed: bool = false
		for angle: int in 16:
			var candidate: Vector2 = boar.pos + Vector2.from_angle(TAU * float(angle) / 16.0) * 20.0
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
	check("clear.remaining_enemies_removed", s.enemies.boars.is_empty() and not stable_early, "killed %d by shots, spawned total %d, killed total %d" % [boar_kills, s.enemies.total_spawned, s.enemies.total_killed])
	check("stable.reached_in_order", st.zone_state[1] >= WorldState.ZONE_STABLE and s.zone_log.size() >= 2 and s.zone_log[0].contains("巣をすべて壊した") and s.zone_log[1].contains("安定した"), "log=%s" % [s.zone_log])
	var t_stable: float = float((s.zone_times[1] as Dictionary).get(WorldState.ZONE_STABLE, -1.0))
	# No input and no resources from here on: back to the safe zone start, then 100 % within the bound.
	s.position = Coords.cell_center_logic(s.placement.player_start_cell)
	var spawned_stable: int = s.enemies.total_spawned
	var hits_before: int = s.play.health.hit_count
	var seeds_at_stable: int = s.play.seeds
	var water_at_stable: float = s.play.water
	var shots_at_stable: int = s.projectiles.launched
	var green_at_stable: int = st.greened_count
	var limit_time: float = t_stable + bound
	var invaded: int = 0
	while s.clock.elapsed <= limit_time + 0.001 and st.greened_count != st.target_count:
		s.advance_game(0.25)
		if not s.enemies.boars.is_empty() or s.enemies.total_spawned != spawned_stable:
			invaded += 1
	var complete_at: float = s.clock.elapsed
	var elapsed_since: float = complete_at - t_stable
	check("stable.no_reinvasion", invaded == 0 and s.enemies.boars.is_empty() and s.enemies.total_spawned == spawned_stable, "invaded steps=%d spawned=%d" % [invaded, s.enemies.total_spawned])
	var island: Rect2i = rect_of(layout["island"])
	var island_ok: bool = true
	for y: int in range(island.position.y, island.end.y):
		for x: int in range(island.position.x, island.end.x):
			island_ok = island_ok and st.stage[st.index_of(x, y)] >= WorldState.GREENED_MIN_STAGE
	var planted_on_targets: bool = true
	for i: int in st.tile_count():
		if st.target[i] == 0 and st.stage[i] != 0:
			planted_on_targets = false
	check("complete.exact_100_percent_within_bound", st.greened_count == st.target_count and st.target_count > 0 and st.greening_percent_floor() == 100 and complete_at <= limit_time + 0.001, "greened=%d/%d took %.1f s after stable, bound %.1f s (limit time %.1f)" % [st.greened_count, st.target_count, elapsed_since, bound, limit_time])
	check("complete.island_included_and_non_targets_untouched", island_ok and planted_on_targets and st.counters_consistent(), "island ok=%s" % island_ok)
	check("complete.no_resources_or_input_used", s.play.seeds == seeds_at_stable and is_equal_approx(s.play.water, water_at_stable) and s.projectiles.launched == shots_at_stable and s.play.health.hit_count == hits_before, "seeds %d->%d" % [seeds_at_stable, s.play.seeds])
	check("complete.zone_and_region_state", st.zone_state[1] == WorldState.ZONE_COMPLETE and st.cleared and s.cleared_notices == 1, "state=%s cleared=%s" % [st.zone_state, st.cleared])
	report.append("100%% result: stable at %.1f s, 100%% at %.1f s (took %.1f s of the %.1f s bound = %.0f%%), greened %d/%d, green at stable %d, island 16 cells included" % [t_stable, complete_at, elapsed_since, bound, 100.0 * elapsed_since / bound, st.greened_count, st.target_count, green_at_stable])
