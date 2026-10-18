extends SceneTree
## HLP-02 logic checks (headless OK): godot --headless --path <repo> --script res://tests/poc/helpers/work.gd
## Gatlinger (takes seeds from nearby mature cells, shoots them onto free greenable cells, no duplicates, stops at zero stock, never
## across walls, never onto buildings / water / nests, front speed vs natural spread), Sprinkler (free by the water, inventory + manual
## refill elsewhere, faster growth), Army (kills inside the radius, does not chase beyond it, returns to its post, no attack across a
## wall), save round trip of the working state, exact 100 % with all three placed, pause. Own save namespace user://poc_saves_test_helpers_work/.
## Long conditions are fast-forwarded; each condition runs once. No OS-level input.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const DIR: String = "user://poc_saves_test_helpers_work/"
const TILE: float = 4.0
## A projectile-stopping wall found by wall_site(): a free 4x4 block five cells west of it and a boar spot east of it.
var WEST_BLOCK: Vector2i = Vector2i(-1, -1)
var WALL_BOAR: Vector2 = Vector2.ZERO

var failures: int = 0
var passes: int = 0
var sessions: Array[RefCounted] = []
var front_report: String = ""

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
		print("PASS ", name, " ", detail)
	else:
		failures += 1
		print("FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func make_session() -> RefCounted:
	var size: Vector2i = Session.town_size()
	var s: RefCounted = Session.new(size.x, size.y)
	s.load_combat(Session.TOWN_SETUP)
	sessions.append(s)
	return s

func run_for(s: RefCounted, seconds: float) -> void:
	var left: float = seconds
	while left > 0.0:
		var piece: float = minf(left, 0.25)
		s.advance_game(piece)
		left -= piece

func kill_enemies(s: RefCounted) -> void:
	for nest: Nest in s.enemies.nests:
		s.enemies.damage_nest(nest, 999)
	while not s.enemies.boars.is_empty():
		s.enemies.damage_boar(s.enemies.boars[0], 999)

func block_center(origin: Vector2i) -> Vector2:
	return (Vector2(origin) + Vector2(2, 2)) * TILE

func make_mature(s: RefCounted, rect: Rect2i) -> void:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var i: int = s.state.index_of(x, y)
			if s.state.target[i] == 1 and s.state.occupant[i] == 0:
				s.state.set_stage(i, WorldState.STAGE_MATURE)

## Places a helper of `kind_index` with its 4x4 block at `origin` (the ground made mature first) through the session API.
func put(s: RefCounted, origin: Vector2i, kind_index: int) -> Dictionary:
	make_mature(s, Rect2i(origin, Vector2i(4, 4)))
	s.helpers.seeds = 10
	s.position = block_center(origin)
	s.set_aim(block_center(origin))
	s.helper_mode = kind_index
	var r: Dictionary = s.place_helper()
	s.helper_mode = -1
	s.position = Vector2(-1000, -1000)
	return s.helpers.plant_by_uid(int(r["uid"]))

func start_patch_edge(s: RefCounted) -> Vector2i:
	# Westmost fully mature free 4x4 block of the start patch (its west side faces wasteland).
	var st: WorldState = s.state
	for ox: int in range(1, st.width - 5):
		for oy: int in range(1, st.height - 5):
			var ok: bool = true
			for y: int in range(oy, oy + 4):
				for x: int in range(ox, ox + 4):
					var i: int = st.index_of(x, y)
					ok = ok and st.is_walkable(x, y) and st.target[i] == 1 and st.occupant[i] == 0 and st.stage[i] == WorldState.STAGE_MATURE
			if ok:
				return Vector2i(ox, oy + 4)
	return Vector2i(-1, -1)

const FRONT_SECONDS: float = 80.0

## Greened cells (stage >= sprout 1) whose centre lies within `radius` of `centre`, not counting the plant's own block.
func disc_greened(s: RefCounted, centre: Vector2, radius: float, own: Rect2i) -> int:
	var n: int = 0
	for y: int in s.state.height:
		for x: int in s.state.width:
			var i: int = s.state.index_of(x, y)
			if s.state.target[i] == 1 and s.state.stage[i] >= WorldState.GREENED_MIN_STAGE and not own.has_point(Vector2i(x, y)) and Vector2((x + 0.5) * TILE, (y + 0.5) * TILE).distance_to(centre) <= radius:
				n += 1
	return n

func count_stage(s: RefCounted, stage: int) -> int:
	var n: int = 0
	for i: int in s.state.tile_count():
		n += 1 if s.state.stage[i] == stage and s.state.target[i] == 1 else 0
	return n

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)
	_data()
	_gat_receive_and_fire()
	_gat_walls_and_terrain()
	_gat_front_speed()
	_sprinkler()
	_army()
	_save()
	_pause()
	_hundred_percent()
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)
	for s: RefCounted in sessions:
		s.close()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)

# ---------------------------------------------------------------- data / fixture

func wall_site(s: RefCounted) -> bool:
	var st: WorldState = s.state
	var p: RefCounted = s.placement
	for by: int in range(2, st.height - 12):
		for bx: int in range(2, st.width - 12):
			var ok: bool = true
			for y: int in range(by - 1, by + 5):
				for x: int in range(bx - 1, bx + 5):
					var i: int = st.index_of(x, y)
					ok = ok and st.is_walkable(x, y) and st.target[i] == 1 and st.terrain_defs[st.terrain[i]].plantable and not p.projectile_blocked_cell(Vector2i(x, y))
			if not ok:
				continue
			# a wall one cell gap beyond the block, to the east (dir x) or the south (dir y)
			for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var perp: Vector2i = Vector2i(dir.y, dir.x)
				var first: Vector2i = Vector2i(bx, by) + dir * 5
				var wall_ok: bool = true
				for k: int in 4:
					wall_ok = wall_ok and p.projectile_blocked_cell(first + perp * k)
				if not wall_ok:
					continue
				var t: int = 0
				var mid: Vector2i = first + perp
				while t < 6 and p.projectile_blocked_cell(mid + dir * t):
					t += 1
				var beyond: Vector2i = mid + dir * t
				if t <= 5 and st.in_bounds(beyond.x, beyond.y) and st.is_walkable(beyond.x, beyond.y) and not p.projectile_blocked_cell(beyond):
					WEST_BLOCK = Vector2i(bx, by)
					WALL_BOAR = (Vector2(beyond) + Vector2(0.5, 0.5)) * TILE
					if p.blocks_projectile(block_center(WEST_BLOCK), WALL_BOAR) and WALL_BOAR.distance_to(block_center(WEST_BLOCK)) <= 40.0:
						return true
	return false

func _data() -> void:
	var s: RefCounted = make_session()
	var h: RefCounted = s.helpers
	check("data.work_values", int(h.gat["stock_max"]) > 0 and float(h.gat["fire_interval"]) > 0.0 and float(h.spr["pulse_cost"]) > 0.0 and int(h.army["damage"]) > 0, "gat=%s spr=%s army=%s" % [h.gat, h.spr, h.army])
	check("data.radii", float(h.kind_def("gatlinger")["radius_m"]) > float(h.kind_def("sprinkler")["radius_m"]) and float(h.kind_def("army")["radius_m"]) > 0.0)
	var found: bool = wall_site(s)
	check("fixture.free_block_west_of_a_wall_with_boar_spot", found, "block=%s boar=%s" % [WEST_BLOCK, WALL_BOAR])

# ---------------------------------------------------------------- Gatlinger

func _gat_receive_and_fire() -> void:
	var s: RefCounted = make_session()
	kill_enemies(s)
	var h: RefCounted = s.helpers
	s.position = Vector2(-1000, -1000)
	var origin: Vector2i = start_patch_edge(s)
	var plant: Dictionary = put(s, origin, 0)
	check("gat.placed_empty_stock", not plant.is_empty() and String(plant["kind"]) == "gatlinger" and float(plant["stock"]) == float(h.gat["stock_start"]), str(plant))
	var mature: int = h.mature_cells_around(plant)
	check("gat.mature_cells_around", mature >= int(h.gat["min_mature_cells"]), "mature=%d" % mature)
	# no source of seeds: stock does not grow
	h.gat["min_mature_cells"] = 100000.0
	run_for(s, 12.0)
	check("gat.no_receive_without_mature_cells", float(plant["stock"]) == 0.0 and h.fire_serial == 0)
	h.gat["min_mature_cells"] = 8.0
	var mature_before: int = s.state.mature_count
	run_for(s, 5.0)
	check("gat.receives_from_mature_cells", float(plant["stock"]) + float(h.fire_serial) >= 2.0, "stock=%.1f shots=%d mature_now=%d (before %d)" % [float(plant["stock"]), h.fire_serial, s.state.mature_count, mature_before])
	check("gat.source_not_consumed", s.state.mature_count >= mature_before - 0 and s.state.counters_consistent())
	plant["stock"] = 0.0
	h.gat["min_mature_cells"] = 1000000.0
	run_for(s, 6.0)
	h.gat["min_mature_cells"] = 8.0
	# fire accounting with the supply cut: stock decreases by exactly the shots, never below zero, no over-consumption
	h.gat["receive_interval"] = 1.0e9
	plant["timer2"] = 1.0e9
	plant["stock"] = 6.0
	var shots_before: int = h.fire_serial
	var seeded_before: int = h.seeded_total + h.wasted_total
	var seen_targets: Dictionary = {}
	var duplicate_in_air: bool = false
	var max_dist: float = 0.0
	var centre: Vector2 = h.plant_center_px(plant)
	var radius: float = float(h.kind_def("gatlinger")["radius_px"])
	var out_of_range: bool = false
	var min_stock: float = 99.0
	for step: int in 200:
		s.advance_game(0.25)
		var air: Dictionary = {}
		for f: Dictionary in h.flights:
			var key: int = int(f["cx"]) * 1000 + int(f["cy"])
			duplicate_in_air = duplicate_in_air or air.has(key)
			air[key] = true
			seen_targets[key] = true
			var to: Vector2 = Vector2((float(f["cx"]) + 0.5) * TILE, (float(f["cy"]) + 0.5) * TILE)
			max_dist = maxf(max_dist, to.distance_to(centre))
			out_of_range = out_of_range or to.distance_to(centre) > radius + 0.01
		min_stock = minf(min_stock, float(plant["stock"]))
	var shots: int = h.fire_serial - shots_before
	check("gat.shoots_one_per_stock_exactly", shots == 6 and float(plant["stock"]) == 0.0 and min_stock >= 0.0, "shots=%d stock=%.1f" % [shots, float(plant["stock"])])
	check("gat.all_flights_landed_planted", h.flights.is_empty() and h.seeded_total + h.wasted_total - seeded_before == 6, "seeded=%d wasted=%d" % [h.seeded_total, h.wasted_total])
	check("gat.no_duplicate_target_in_air", not duplicate_in_air and seen_targets.size() == 6, "distinct=%d" % seen_targets.size())
	check("gat.targets_within_range", not out_of_range)
	# stops at zero stock
	var serial: int = h.fire_serial
	run_for(s, 30.0)
	check("gat.zero_stock_stops", h.fire_serial == serial and h.flights.is_empty() and float(plant["stock"]) == 0.0)
	# far origins: with a bigger run the targets reach well beyond the plant's surroundings
	plant["stock"] = float(h.gat["stock_max"])
	var targets: Array[Vector2] = []
	for step: int in 400:
		var before: int = h.flights.size()
		s.advance_game(0.25)
		for f: Dictionary in h.flights:
			var p: Vector2 = Vector2((float(f["cx"]) + 0.5) * TILE, (float(f["cy"]) + 0.5) * TILE)
			if float(f["age"]) <= 0.26:
				targets.append(p)
	var far_count: int = 0
	for p: Vector2 in targets:
		far_count += 1 if p.distance_to(centre) >= radius * 0.6 else 0
		max_dist = maxf(max_dist, p.distance_to(centre))
	check("gat.seeds_far_away_too", targets.size() >= 10 and far_count >= 3 and max_dist >= radius * 0.7, "targets=%d far(>=60%% radius)=%d max=%.1fpx of %.1fpx" % [targets.size(), far_count, max_dist, radius])

func _gat_walls_and_terrain() -> void:
	var s: RefCounted = make_session()
	kill_enemies(s)
	var h: RefCounted = s.helpers
	s.position = Vector2(-1000, -1000)
	var plant: Dictionary = put(s, WEST_BLOCK, 0)
	check("gatwall.placed", not plant.is_empty())
	h.gat["receive_interval"] = 1.0e9
	var centre: Vector2 = h.plant_center_px(plant)
	var radius: float = float(h.kind_def("gatlinger")["radius_px"])
	# how many free cells in range really are behind a wall (the case must exist, else the check proves nothing)
	var hidden: int = 0
	var visible: int = 0
	for y: int in range(0, s.state.height):
		for x: int in range(0, s.state.width):
			var p: Vector2 = Vector2((x + 0.5) * TILE, (y + 0.5) * TILE)
			if p.distance_to(centre) <= radius and s.state.can_plant(s.state.index_of(x, y)):
				if s.placement.blocks_projectile(centre, p):
					hidden += 1
				else:
					visible += 1
	check("gatwall.cells_behind_wall_exist", hidden >= 4 and visible >= 4, "hidden=%d visible=%d" % [hidden, visible])
	# a long run with many shots: every target is visible from the plant and a valid greenable free cell; non-greenable cells are in range too
	var bad_los: int = 0
	var bad_cell: int = 0
	var shots: int = 0
	var landed_cells: Array[Vector2i] = []
	var nongreen_in_range: int = 0
	for y: int in range(0, s.state.height):
		for x: int in range(0, s.state.width):
			var p2: Vector2 = Vector2((x + 0.5) * TILE, (y + 0.5) * TILE)
			var idx: int = s.state.index_of(x, y)
			if p2.distance_to(centre) <= radius and (s.state.target[idx] == 0 or not s.state.terrain_defs[s.state.terrain[idx]].plantable):
				nongreen_in_range += 1
	for round: int in 6:
		plant["stock"] = 12.0
		for step: int in 160:
			var count: int = h.flights.size()
			s.advance_game(0.25)
			for f: Dictionary in h.flights:
				if float(f["age"]) <= 0.26 and float(f["age"]) > 0.0:
					var cell: Vector2i = Vector2i(int(f["cx"]), int(f["cy"]))
					var idx2: int = s.state.index_of(cell.x, cell.y)
					shots += 1
					var p3: Vector2 = Vector2((cell.x + 0.5) * TILE, (cell.y + 0.5) * TILE)
					bad_los += 1 if s.placement.blocks_projectile(centre, p3) else 0
					bad_cell += 1 if s.state.target[idx2] == 0 or not s.state.terrain_defs[s.state.terrain[idx2]].plantable or s.state.occupant[idx2] != 0 else 0
					landed_cells.append(cell)
		# make room again: undo the planted seeds near the plant so candidate cells remain
		for cell: Vector2i in landed_cells:
			var i3: int = s.state.index_of(cell.x, cell.y)
			if s.state.stage[i3] != WorldState.STAGE_EMPTY and s.state.stage[i3] != WorldState.STAGE_MATURE:
				s.state.set_stage(i3, WorldState.STAGE_EMPTY)
	check("gatwall.no_target_across_wall", shots >= 40 and bad_los == 0, "shots=%d across_wall=%d" % [shots, bad_los])
	check("gatwall.targets_are_greenable_free_cells", bad_cell == 0 and nongreen_in_range > 0, "bad=%d nongreenable_cells_in_range=%d" % [bad_cell, nongreen_in_range])
	# nests / water / buildings: a Gatlinger standing next to the pond and a nest never plants there either
	var nest: Nest = s.enemies.nests[0]
	var s2: RefCounted = make_session()
	kill_enemies(s2)
	s2.enemies.nests[0].alive = false
	var nest_tiles_planted: int = 0
	var h2: RefCounted = s2.helpers
	h2.gat["receive_interval"] = 1.0e9
	# a live nest: re-create a session where nest 0 stays alive and stands close to a mature block
	var s3: RefCounted = make_session()
	var live: Nest = s3.enemies.nests[0]
	var block: Vector2i = Vector2i(live.tile.x - 5, live.tile.y + live.size / 2 - 2)
	s3.position = Vector2(-1000, -1000)
	var plant3: Dictionary = put(s3, block, 0)
	s3.helpers.gat["receive_interval"] = 1.0e9
	var nest_cells_in_range: int = 0
	var c3: Vector2 = s3.helpers.plant_center_px(plant3)
	for y: int in range(live.tile.y, live.tile.y + live.size):
		for x: int in range(live.tile.x, live.tile.x + live.size):
			nest_cells_in_range += 1 if Vector2((x + 0.5) * TILE, (y + 0.5) * TILE).distance_to(c3) <= radius else 0
	var nest_planted: int = 0
	for round: int in 4:
		plant3["stock"] = 12.0
		for step: int in 140:
			s3.helpers.advance(0.25, Vector2(-1000, -1000), true)
		for y: int in range(live.tile.y, live.tile.y + live.size):
			for x: int in range(live.tile.x, live.tile.x + live.size):
				var ii: int = s3.state.index_of(x, y)
				nest_planted += 1 if s3.state.stage[ii] != WorldState.STAGE_EMPTY else 0
	check("gatnest.never_plants_on_nest", live.alive and nest_cells_in_range > 0 and nest_planted == 0, "nest_cells_in_range=%d planted=%d shots=%d" % [nest_cells_in_range, nest_planted, s3.helpers.fire_serial])
	# pond: shore cells are greenable (planted), water cells never
	var water_planted: int = 0
	var s4: RefCounted = make_session()
	kill_enemies(s4)
	var pond_block: Vector2i = Vector2i(-1, -1)
	for y: int in range(1, s4.state.height - 5):
		for x: int in range(1, s4.state.width - 5):
			if pond_block.x < 0 and s4.state.terrain[s4.state.index_of(x + 4, y + 2)] == Session.T_WATER and s4.state.terrain[s4.state.index_of(x + 3, y + 2)] != Session.T_WATER:
				pond_block = Vector2i(x, y)
	s4.position = Vector2(-1000, -1000)
	var water_cells_in_range: int = 0
	if pond_block.x >= 0:
		var shore_ok: bool = true
		for y: int in range(pond_block.y, pond_block.y + 4):
			for x: int in range(pond_block.x, pond_block.x + 4):
				shore_ok = shore_ok and s4.state.is_walkable(x, y) and s4.state.target[s4.state.index_of(x, y)] == 1
		var plant4: Dictionary = put(s4, pond_block, 0) if shore_ok else {}
		if not plant4.is_empty():
			s4.helpers.gat["receive_interval"] = 1.0e9
			var c4: Vector2 = s4.helpers.plant_center_px(plant4)
			for y: int in s4.state.height:
				for x: int in s4.state.width:
					water_cells_in_range += 1 if s4.state.terrain[s4.state.index_of(x, y)] == Session.T_WATER and Vector2((x + 0.5) * TILE, (y + 0.5) * TILE).distance_to(c4) <= radius else 0
			for round: int in 4:
				plant4["stock"] = 12.0
				for step: int in 140:
					s4.helpers.advance(0.25, Vector2(-1000, -1000), true)
				for y: int in s4.state.height:
					for x: int in s4.state.width:
						var j: int = s4.state.index_of(x, y)
						water_planted += 1 if s4.state.terrain[j] == Session.T_WATER and s4.state.stage[j] != WorldState.STAGE_EMPTY else 0
	check("gatwater.never_plants_in_water", water_cells_in_range > 0 and water_planted == 0, "water_cells_in_range=%d planted=%d" % [water_cells_in_range, water_planted])

func _gat_front_speed() -> void:
	var a: RefCounted = make_session()
	var b: RefCounted = make_session()
	# The nests stay alive (with the region cleared the far-seeding sweep would plant everywhere and hide the natural front) but spawn
	# nothing. A mature field is made through set_stage so that the natural spread notices it (the start patch is not a spread source).
	for s: RefCounted in [a, b]:
		s.position = Vector2(-1000, -1000)
		s.enemy_tuning.boar_cap = 0
		s.enemy_tuning.nest_boar_cap = 0
		make_mature(s, Rect2i(20, 38, 12, 12))
	var plant: Dictionary = put(a, Vector2i(28, 41), 0)
	var centre: Vector2 = a.helpers.plant_center_px(plant)
	var radius: float = float(a.helpers.kind_def("gatlinger")["radius_px"])
	var greened_a0: int = disc_greened(a, centre, radius, a.helpers.plant_rect(plant))
	var greened_b0: int = disc_greened(b, centre, radius, a.helpers.plant_rect(plant))
	var horizon: float = FRONT_SECONDS
	for mark: int in 4:
		run_for(a, horizon / 4.0)
		run_for(b, horizon / 4.0)
		print("FRONT t=%.0f with=%d without=%d" % [horizon / 4.0 * float(mark + 1), disc_greened(a, centre, radius, a.helpers.plant_rect(plant)) - greened_a0, disc_greened(b, centre, radius, a.helpers.plant_rect(plant)) - greened_b0])
	var gain_a: int = disc_greened(a, centre, radius, a.helpers.plant_rect(plant)) - greened_a0
	var gain_b: int = disc_greened(b, centre, radius, a.helpers.plant_rect(plant)) - greened_b0
	var multiple: float = float(gain_a) / float(maxi(gain_b, 1))
	front_report = "front speed (greened cells inside the Gatlinger range) over %.0f s: natural only +%d, with one Gatlinger +%d (x%.2f); shots=%d seeded=%d wasted=%d stock_left=%.1f" % [horizon, gain_b, gain_a, multiple, a.helpers.fire_serial, a.helpers.seeded_total, a.helpers.wasted_total, float(plant["stock"])]
	print("FRONT ", front_report)
	check("gat.front_faster_than_natural_spread", gain_b > 0 and multiple >= 1.5 and multiple <= 6.0, front_report)

# ---------------------------------------------------------------- Sprinkler

func water_block(s: RefCounted) -> Vector2i:
	# a 4x4 greenable walkable block touching a waterside terrain (shore / shallows / water), away from the start patch
	var st: WorldState = s.state
	for y: int in range(1, st.height - 5):
		for x: int in range(1, st.width - 5):
			var ok: bool = true
			for yy: int in range(y, y + 4):
				for xx: int in range(x, x + 4):
					var i: int = st.index_of(xx, yy)
					ok = ok and st.is_walkable(xx, yy) and st.target[i] == 1 and st.terrain_defs[st.terrain[i]].plantable and st.occupant[i] == 0
			if not ok:
				continue
			var touches: bool = false
			for yy: int in range(y - 1, y + 5):
				for xx: int in range(x - 1, x + 5):
					touches = touches or s.play.waterside_by_terrain[st.terrain[st.index_of(xx, yy)]] == 1
			if touches:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func sow(s: RefCounted, plant: Dictionary, stage: int, count: int) -> Array[int]:
	var h: RefCounted = s.helpers
	var out: Array[int] = []
	var centre: Vector2 = h.plant_center_px(plant)
	var radius: float = float(h.kind_def("sprinkler")["radius_px"])
	for y: int in s.state.height:
		for x: int in s.state.width:
			var i: int = s.state.index_of(x, y)
			if out.size() < count and s.state.can_plant(i) and Vector2((x + 0.5) * TILE, (y + 0.5) * TILE).distance_to(centre) <= radius * 0.9:
				s.state.set_stage(i, stage)
				out.append(i)
	return out

func _sprinkler() -> void:
	var s: RefCounted = make_session()
	kill_enemies(s)
	var h: RefCounted = s.helpers
	s.position = Vector2(-1000, -1000)
	var wb: Vector2i = water_block(s)
	check("spr.fixture_water_block", wb.x >= 0, str(wb))
	var by_water: Dictionary = put(s, wb, 1)
	check("spr.placed_by_water", not by_water.is_empty() and h.is_by_water(by_water) and String(by_water["kind"]) == "sprinkler", str(by_water))
	var cells: Array[int] = sow(s, by_water, WorldState.STAGE_SEED, 12)
	var stock_before: float = float(by_water["stock"])
	var wet_samples: int = 0
	var pulses0: int = h.pulses_total
	for step: int in 160:
		s.advance_game(0.25)
		if step % 20 == 19:
			for i: int in cells:
				if s.state.stage[i] != WorldState.STAGE_MATURE and s.state.stage[i] != WorldState.STAGE_EMPTY:
					wet_samples += 1 if s.state.moisture[i] > 0 else 0
	check("spr.water_edge_waters_without_supply", cells.size() == 12 and h.pulses_total - pulses0 >= 8 and float(by_water["stock"]) == stock_before and wet_samples > 0, "pulses=%d stock=%.1f wet_samples=%d" % [h.pulses_total - pulses0, float(by_water["stock"]), wet_samples])
	check("spr.status_text_by_water", s.helper_status_text().contains("水辺"), s.helper_status_text())
	# away from the water: inventory
	var s2: RefCounted = make_session()
	kill_enemies(s2)
	var h2: RefCounted = s2.helpers
	var far_block: Vector2i = start_patch_edge(s2)
	s2.position = Vector2(-1000, -1000)
	var dry: Dictionary = put(s2, far_block, 1)
	check("spr.dry_site_not_by_water", not dry.is_empty() and not h2.is_by_water(dry), str(dry))
	dry["stock"] = 10.0
	var seeds: Array[int] = sow(s2, dry, WorldState.STAGE_SEED, 10)
	run_for(s2, 20.0)
	check("spr.dry_site_runs_out_and_stops", seeds.size() == 10 and h2.pulses_total == 1 and float(dry["stock"]) < 10.0, "pulses=%d stock=%.1f" % [h2.pulses_total, float(dry["stock"])])
	var stopped_at: int = h2.pulses_total
	for i: int in seeds:
		s2.state.set_moisture(i, 0)
		s2.state.set_stage(i, WorldState.STAGE_SEED)
	run_for(s2, 12.0)
	check("spr.no_pulse_without_water", h2.pulses_total == stopped_at and float(dry["stock"]) < float(h2.spr["pulse_cost"]), "stock=%.1f" % float(dry["stock"]))
	# manual refill: the player walks up to it
	s2.position = h2.plant_center_px(dry) + Vector2(14.0, 0.0)
	run_for(s2, 1.0)
	var refilled: float = float(dry["stock"])
	check("spr.player_nearby_refills", refilled >= float(h2.spr["pulse_cost"]), "stock=%.1f" % refilled)
	s2.position = Vector2(-1000, -1000)
	for i: int in seeds:
		s2.state.set_moisture(i, 0)
		s2.state.set_stage(i, WorldState.STAGE_SEED)
	run_for(s2, 8.0)
	check("spr.resumes_after_refill", h2.pulses_total > stopped_at, "pulses=%d" % h2.pulses_total)
	s2.position = h2.plant_center_px(dry) + Vector2(200.0, 0.0)
	var before_far: float = float(dry["stock"])
	h2.advance(1.0, s2.position, false)
	check("spr.far_player_no_refill", float(dry["stock"]) <= before_far)
	# the stock is capped and a downed player cannot refill
	s2.position = h2.plant_center_px(dry) + Vector2(14.0, 0.0)
	dry["stock"] = 0.0
	h2.advance(1.0, s2.position, true)
	check("spr.downed_player_no_refill", float(dry["stock"]) == 0.0)
	for i: int in 20:
		h2.advance(1.0, s2.position, false)
	check("spr.stock_capped", float(dry["stock"]) <= float(h2.spr["stock_max"]) + 0.001)
	# growth is faster with water (same cells, same time, the unwatered copy as control)
	var wet: RefCounted = make_session()
	var control: RefCounted = make_session()
	for t: RefCounted in [wet, control]:
		kill_enemies(t)
		t.position = Vector2(-1000, -1000)
	var spot: Vector2i = start_patch_edge(wet)
	var watered: Dictionary = put(wet, spot, 1)
	put(control, spot, 0)
	watered["stock"] = 60.0
	var cells_a: Array[int] = sow(wet, watered, WorldState.STAGE_SEED, 12)
	var cells_b: Array[int] = sow(control, control.helpers.plants[0], WorldState.STAGE_SEED, 12)
	run_for(wet, 20.0)
	run_for(control, 20.0)
	var sum_a: int = 0
	var sum_b: int = 0
	for k: int in cells_a.size():
		sum_a += int(wet.state.growth[cells_a[k]])
	for k: int in cells_b.size():
		sum_b += int(control.state.growth[cells_b[k]])
	check("spr.growth_faster_with_sprinkler", cells_a == cells_b and cells_a.size() == 12 and sum_a > sum_b * 1.15, "growth sum with=%d without=%d" % [sum_a, sum_b])

# ---------------------------------------------------------------- Army

func army_fixture() -> Array:
	var s: RefCounted = make_session()
	kill_enemies(s)
	s.position = Vector2(-1000, -1000)
	var origin: Vector2i = start_patch_edge(s)
	var plant: Dictionary = put(s, origin, 2)
	return [s, plant]

func new_boar(s: RefCounted, at: Vector2, hp: int = 3) -> Boar:
	var boar: Boar = Boar.new()
	boar.id = 9100 + s.enemies.boars.size()
	boar.zone = 1
	boar.hp = hp
	boar.pos = at
	s.enemies.boars.append(boar)
	return boar

func _army() -> void:
	var fx: Array = army_fixture()
	var s: RefCounted = fx[0]
	var plant: Dictionary = fx[1]
	var h: RefCounted = s.helpers
	var home: Vector2 = h.plant_center_px(plant)
	var radius: float = float(h.kind_def("army")["radius_px"])
	check("army.placed_unit_at_post", String(plant["kind"]) == "army" and h.unit_pos(plant).distance_to(home) < 0.01 and radius > 0.0)
	# inside the radius: killed (3 hp, 2 damage: two hits)
	var killed0: int = s.enemies.total_killed
	var boar: Boar = new_boar(s, home + Vector2(-radius * 0.7, 0.0))
	var t_kill: float = -1.0
	for step: int in 200:
		h.advance(0.1, Vector2(-1000, -1000), true)
		if t_kill < 0.0 and not s.enemies.boars.has(boar):
			t_kill = float(step + 1) * 0.1
	check("army.kills_boar_inside_radius", t_kill > 0.0 and t_kill < 8.0 and s.enemies.total_killed == killed0 + 1 and h.kills_total == 1, "killed after %.1f s" % t_kill)
	var back: float = h.unit_pos(plant).distance_to(home)
	check("army.returns_to_post_after_fight", back < 0.5, "distance to post %.2f px" % back)
	# outside the radius: not attacked, not chased
	var far_boar: Boar = new_boar(s, home + Vector2(-radius - 12.0, 0.0))
	var max_out: float = 0.0
	for step: int in 200:
		h.advance(0.1, Vector2(-1000, -1000), true)
		max_out = maxf(max_out, h.unit_pos(plant).distance_to(home))
	check("army.ignores_boar_outside_radius", far_boar.hp == 3 and s.enemies.boars.has(far_boar) and max_out < 0.01, "unit moved %.2f px" % max_out)
	# at the very edge: the unit may walk out, but never beyond the radius, and goes home when the boar leaves
	far_boar.pos = home + Vector2(-radius + 1.0, 0.0)
	far_boar.hp = 1000
	var max_reach: float = 0.0
	for step: int in 60:
		h.advance(0.1, Vector2(-1000, -1000), true)
		max_reach = maxf(max_reach, h.unit_pos(plant).distance_to(home))
	var attacked: bool = far_boar.hp < 1000
	far_boar.pos = home + Vector2(-radius - 30.0, 0.0)
	for step: int in 100:
		h.advance(0.1, Vector2(-1000, -1000), true)
		max_reach = maxf(max_reach, h.unit_pos(plant).distance_to(home))
	check("army.never_beyond_radius_and_returns", max_reach <= radius + 0.01 and attacked and h.unit_pos(plant).distance_to(home) < 0.5, "max %.1f of %.1f px, attacked=%s" % [max_reach, radius, attacked])
	s.enemies.boars.erase(far_boar)
	# walkable cells only: the unit never stands on a non-walkable cell (chasing along a building)
	var walkable_ok: bool = true
	var w: Array = _wall_army()
	var ws: RefCounted = w[0]
	var wplant: Dictionary = w[1]
	var wh: RefCounted = ws.helpers
	wh.army["reach_px"] = 22.0
	var whome: Vector2 = wh.plant_center_px(wplant)
	var east: Boar = new_boar(ws, WALL_BOAR, 100000)
	var blocked_in_reach: int = 0
	var hits: int = 0
	var hits_blocked: int = 0
	var pre_hp: int = east.hp
	for step: int in 400:
		var unit_before: Vector2 = wh.unit_pos(wplant)
		wh.advance(0.05, Vector2(-1000, -1000), true)
		var u: Vector2 = wh.unit_pos(wplant)
		var cell: Vector2i = Coords.logic_to_cell(u)
		walkable_ok = walkable_ok and ws.state.is_walkable(cell.x, cell.y)
		var close: bool = u.distance_to(east.pos) <= 22.0
		var blocked: bool = ws.placement.blocks_projectile(u, east.pos)
		blocked_in_reach += 1 if close and blocked else 0
		if east.hp < pre_hp:
			hits += 1
			hits_blocked += 1 if ws.placement.blocks_projectile(unit_before, east.pos) or blocked else 0
			pre_hp = east.hp
	check("army.unit_stays_on_walkable_cells", walkable_ok)
	check("army.no_attack_across_wall", blocked_in_reach > 0 and hits_blocked == 0, "steps in reach but behind the wall=%d, hits=%d, hits across wall=%d" % [blocked_in_reach, hits, hits_blocked])
	ws.enemies.boars.erase(east)
	# a wall between the post and a boar that never gets closer: no damage at all when the unit cannot get a clear line
	var plant_hp: int = int(plant["hp"])
	check("army.post_plant_untouched", plant_hp == int(h.kind_def("army")["hp"]))

## Army block west of the 2x2 wall in the open field (the unit walks toward a boar east of the wall).
func _wall_army() -> Array:
	var s: RefCounted = make_session()
	kill_enemies(s)
	s.position = Vector2(-1000, -1000)
	var plant: Dictionary = put(s, WEST_BLOCK, 2)
	return [s, plant]

# ---------------------------------------------------------------- save

func write_json(data: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(DIR + PocSave.SLOT_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "", false, true))
	f.close()

func load_slot() -> Dictionary:
	return PocSave.load_slot(DIR, false, Callable(self, "make_session"))

func _save() -> void:
	var s: RefCounted = make_session()
	s.enemy_tuning.boar_cap = 0
	s.enemy_tuning.nest_boar_cap = 0
	var h: RefCounted = s.helpers
	s.position = Coords.cell_center_logic(s.placement.player_start_cell)
	var origin: Vector2i = start_patch_edge(s)
	var gat: Dictionary = put(s, origin, 0)
	var spr: Dictionary = put(s, origin + Vector2i(-6, 0), 1)
	var army: Dictionary = put(s, origin + Vector2i(0, 6), 2)
	s.position = Coords.cell_center_logic(s.placement.player_start_cell)
	make_mature(s, Rect2i(origin.x - 8, origin.y - 8, 20, 20))
	gat["stock"] = 7.0
	spr["stock"] = 33.0
	sow(s, spr, WorldState.STAGE_SEED, 6)
	h.gat["min_mature_cells"] = 1000000.0
	h.gat["fire_interval"] = 1.0
	for step: int in 30:
		s.advance_game(0.25)
	check("save.fixture_working_state", h.plants.size() == 3 and not h.flights.is_empty() and h.fire_serial > 0 and h.pulses_total > 0, "flights=%d shots=%d pulses=%d" % [h.flights.size(), h.fire_serial, h.pulses_total])
	h.army["damage"] = 0.0
	new_boar(s, h.plant_center_px(army) + Vector2(20.0, 0.0), 3)
	for step: int in 8:
		h.advance(0.1, s.position, true)
	check("save.fixture_unit_away_from_post", h.unit_pos(army).distance_to(h.plant_center_px(army)) > 3.0, "unit offset %.1f px" % h.unit_pos(army).distance_to(h.plant_center_px(army)))
	gat["timer"] = 0.0
	gat["stock"] = 7.0
	h.advance(0.1, s.position, true)
	check("save.fixture_flight_in_air", not h.flights.is_empty(), "flights=%d" % h.flights.size())
	var saved: Dictionary = PocSave.save(s, DIR)
	var loaded: Dictionary = load_slot()
	check("save.roundtrip_ok", bool(saved["ok"]) and bool(loaded["ok"]), String(loaded.get("reason", "")))
	var t: RefCounted = loaded["session"]
	if JSON.stringify(t.helpers.to_dict()) != JSON.stringify(h.to_dict()):
		print("DIFF loaded ", JSON.stringify(t.helpers.to_dict()))
		print("DIFF orig   ", JSON.stringify(h.to_dict()))
	var other_equal: bool = true
	var cap_a: Dictionary = JSON.parse_string(JSON.stringify(PocSave.capture(s)))
	var cap_b: Dictionary = JSON.parse_string(JSON.stringify(PocSave.capture(t)))
	for key: String in cap_a:
		# The fake boar of this fixture has no nest, so the enemy section is compared by the enemy tests (not here).
		if key != "saved_at" and key != "enemies" and JSON.stringify(cap_a[key]) != JSON.stringify(cap_b.get(key)):
			other_equal = false
			print("DIFFSECTION ", key)
	check("save.working_state_identical", JSON.stringify(t.helpers.to_dict()) == JSON.stringify(h.to_dict()) and other_equal)
	check("save.stock_flights_unit_restored", t.helpers.flights.size() == h.flights.size() and float(t.helpers.plant_by_uid(int(gat["uid"]))["stock"]) == float(gat["stock"]) and float(t.helpers.plant_by_uid(int(spr["uid"]))["stock"]) == float(spr["stock"]) and t.helpers.unit_pos(t.helpers.plant_by_uid(int(army["uid"]))).is_equal_approx(h.unit_pos(army)))
	check("save.format_version_unchanged", PocSave.FORMAT_VERSION == 2 and int(JSON.parse_string(FileAccess.get_file_as_string(DIR + PocSave.SLOT_FILE))["helpers"]["version"]) == 2)
	# a lifted plant keeps its stock
	t.position = t.helpers.plant_center_px(t.helpers.plant_by_uid(int(spr["uid"]))) + Vector2(-14.0, 0.0)
	var stock_before: float = float(t.helpers.plant_by_uid(int(spr["uid"]))["stock"])
	var lift_result: Dictionary = t.lift_helper()
	check("save.lifted_keeps_stock", t.helpers.is_carrying() and int(t.helpers.carried["uid"]) == int(spr["uid"]) and float(t.helpers.carried["stock"]) == stock_before, "%s stock=%.1f" % [lift_result, stock_before])
	PocSave.save(t, DIR)
	var loaded2: Dictionary = load_slot()
	check("save.lifted_roundtrip", bool(loaded2["ok"]) and JSON.stringify(loaded2["session"].helpers.to_dict()) == JSON.stringify(t.helpers.to_dict()))
	PocSave.save(s, DIR)
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + PocSave.SLOT_FILE))
	var tampers: Dictionary = {
		"gat_stock_over_cap": func(d: Dictionary) -> void: d["helpers"]["plants"][0]["stock"] = 999.0,
		"stock_negative": func(d: Dictionary) -> void: d["helpers"]["plants"][1]["stock"] = -1.0,
		"army_stock_nonzero": func(d: Dictionary) -> void: d["helpers"]["plants"][2]["stock"] = 5.0,
		"timer_huge": func(d: Dictionary) -> void: d["helpers"]["plants"][0]["timer"] = 999.0,
		"unit_far_from_post": func(d: Dictionary) -> void: d["helpers"]["plants"][2]["ax"] = 20.0,
		"unit_off_map": func(d: Dictionary) -> void: d["helpers"]["plants"][2]["ay"] = 1.0e9,
		"work_keys_missing": func(d: Dictionary) -> void: d["helpers"]["plants"][0].erase("stock"),
		"flight_off_map": func(d: Dictionary) -> void: d["helpers"]["flights"][0]["cx"] = 5000,
		"flight_age_past_end": func(d: Dictionary) -> void: d["helpers"]["flights"][0]["age"] = 99.0,
		"flight_zero_duration": func(d: Dictionary) -> void: d["helpers"]["flights"][0]["dur"] = 0.0,
		"flights_missing": func(d: Dictionary) -> void: d["helpers"].erase("flights"),
		"fire_serial_negative": func(d: Dictionary) -> void: d["helpers"]["fire_serial"] = -3,
		"stats_missing": func(d: Dictionary) -> void: d["helpers"]["stats"].erase("kills"),
		"carried_stock_over_cap": func(d: Dictionary) -> void: d["helpers"]["carried"] = {"uid": 999, "kind": "sprinkler", "hp": 3, "stock": 999.0},
	}
	for key: String in tampers:
		var d: Dictionary = base.duplicate(true)
		tampers[key].call(d)
		write_json(d)
		var r: Dictionary = load_slot()
		check("save.reject.%s" % key, not bool(r["ok"]), "%s %s" % [r.get("code", ""), r.get("reason", "")])
	# a section written by HLP-01 (version 1, no work state) still loads, with fresh work state
	var old: Dictionary = base.duplicate(true)
	old["helpers"]["version"] = 1
	for plant: Dictionary in old["helpers"]["plants"]:
		for key: String in ["stock", "timer", "timer2", "ax", "ay"]:
			plant.erase(key)
	old["helpers"].erase("flights")
	old["helpers"].erase("fire_serial")
	for key: String in ["seeded", "wasted", "pulses", "kills"]:
		old["helpers"]["stats"].erase(key)
	write_json(old)
	var r_old: Dictionary = load_slot()
	check("save.helpers_v1_section_loads_with_defaults", bool(r_old["ok"]) and r_old["session"].helpers.plants.size() == 3 and r_old["session"].helpers.flights.is_empty(), String(r_old.get("reason", "")))

# ---------------------------------------------------------------- pause and 100 %

func _pause() -> void:
	var s: RefCounted = make_session()
	kill_enemies(s)
	var h: RefCounted = s.helpers
	s.position = Vector2(-1000, -1000)
	var origin: Vector2i = start_patch_edge(s)
	var gat: Dictionary = put(s, origin, 0)
	var spr: Dictionary = put(s, origin + Vector2i(-6, 0), 1)
	var army: Dictionary = put(s, origin + Vector2i(0, 6), 2)
	make_mature(s, Rect2i(origin.x - 8, origin.y - 8, 20, 20))
	gat["stock"] = 10.0
	h.gat["fire_interval"] = 1.0
	sow(s, spr, WorldState.STAGE_SEED, 6)
	new_boar(s, h.plant_center_px(army) + Vector2(20.0, 0.0), 100000)
	for step: int in 12:
		s.advance_game(0.25)
	var running: bool = not h.flights.is_empty() or h.fire_serial > 0
	s.paused = true
	var before: String = JSON.stringify(h.to_dict())
	var greened: int = s.state.greened_count
	run_for(s, 60.0)
	check("pause.work_frozen", running and JSON.stringify(h.to_dict()) == before and s.state.greened_count == greened)
	s.paused = false
	run_for(s, 3.0)
	check("pause.resume_continues", JSON.stringify(h.to_dict()) != before)

func _hundred_percent() -> void:
	var s: RefCounted = make_session()
	var h: RefCounted = s.helpers
	s.enemy_tuning.contact_damage = 0
	var bound: float = s.far.completion_bound_seconds()
	for nest: Nest in s.enemies.nests:
		s.enemies.damage_nest(nest, 99)
	var guard: int = 0
	while not s.enemies.boars.is_empty() and guard < 400:
		s.enemies.damage_boar(s.enemies.boars[0], 99)
		guard += 1
		s.advance_game(0.25)
	var origin: Vector2i = start_patch_edge(s)
	put(s, origin, 0)
	put(s, origin + Vector2i(-6, 0), 1)
	put(s, origin + Vector2i(0, 6), 2)
	s.position = Coords.cell_center_logic(s.placement.player_start_cell)
	check("hundred.three_kinds_placed", h.plants.size() == 3, str(h.plants.size()))
	var steps: int = 0
	while s.state.zone_state[1] < WorldState.ZONE_STABLE and steps < 4000:
		s.advance_game(0.25)
		steps += 1
	var t_stable: float = float((s.zone_times[1] as Dictionary).get(WorldState.ZONE_STABLE, s.clock.elapsed))
	var limit: float = t_stable + bound
	var t_done: float = -1.0
	while s.clock.elapsed <= limit + 5.0:
		s.advance_game(0.25)
		if s.state.greened_count == s.state.target_count:
			t_done = s.clock.elapsed - t_stable
			break
	check("hundred.exact_100_with_working_helpers_within_bound", t_done >= 0.0 and t_done <= bound, "after stable %.1f s of bound %.1f s, greened %d/%d, shots=%d seeded=%d pulses=%d" % [t_done, bound, s.state.greened_count, s.state.target_count, h.fire_serial, h.seeded_total, h.pulses_total])
	check("hundred.counters_ok_and_helpers_standing", h.plants.size() == 3 and s.state.counters_consistent() and s.greening_percent() == 100)
