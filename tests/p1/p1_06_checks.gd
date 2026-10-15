extends SceneTree
## P1-06 headless checks: walking against water / buildings (Walker, and the real player node with injected key events),
## the shallows terrain, the region map (independent BFS over the PNG, determinism of the generator), fruits (safe zone
## excluded, readable colours), and the tempo of the whole loop with the greedy bot (a: bot + carrots, b: natural spread
## only, c: bot without carrots), including the frame cost of the logic.
## Run: Godot --headless --path <project> --script res://tests/p1/p1_06_checks.gd [-- --skip-tempo]
## Results: PASS/FAIL lines, INFO json, and evidence/p1/p1-06/tempo_results.json.
## Expected values come from the ticket and from geometry written in this file (rectangle edges on tile boundaries,
## 96 px/s, the BFS below runs on the PNG pixels and its own colour constants, not on WorldState).

const Bot = preload("res://tests/p1/p1_06_bot.gd")
const REGION_PATH: String = "res://data/region_01.tres"
const TILE: int = 4
const SPEED: float = 96.0
const HALF: Vector2 = Vector2(3, 2)
## Map legend colours (hex of data/region_01.png), written here independently of the TerrainDef resources.
const C_WASTELAND: int = 0xb0a060
const C_SAFE: int = 0x60b060
const C_SHORE: int = 0xe0d090
const C_WATER: int = 0x4080e0
const C_BUILDING: int = 0x808080
const C_SHALLOWS: int = 0x70b0e0

var failures: int = 0
var checks: int = 0
var region_def: RegionDef
var sim_tuning: SimTuning
var play_tuning: PlayTuning
var info: Dictionary = {}
var main: Node
var player: FlowerPlayer
var skip_tempo: bool = false

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", message])

func run() -> void:
	skip_tempo = OS.get_cmdline_user_args().has("--skip-tempo")
	region_def = load(REGION_PATH) as RegionDef
	sim_tuning = load("res://data/sim_tuning.tres") as SimTuning
	play_tuning = load("res://data/play_tuning.tres") as PlayTuning
	check(region_def != null and sim_tuning != null and play_tuning != null, "region and tunings load")
	test_terrain_defs()
	test_walker_small_map()
	test_frame_rate_independence()
	test_map_independent_bfs()
	test_generator_determinism()
	test_shallows_rules()
	test_fruit_rules()
	test_fruit_colours()
	await test_scene_walk()
	if not skip_tempo:
		test_tempo()
	print("INFO " + JSON.stringify(info))
	print("P1_06_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

# ---- helpers -------------------------------------------------------------------------------------------------------

func terrain_def(key: StringName) -> TerrainDef:
	for def: TerrainDef in region_def.terrains:
		if def.key == key:
			return def
	return null

func c8(color: Color) -> Vector3i:
	return Vector3i(roundi(color.r * 255.0), roundi(color.g * 255.0), roundi(color.b * 255.0))

## Small world from glyph rows through the real loader path: . wasteland, s safe, : shore, ~ water, # building, h shallows.
func state_from_rows(rows: Array) -> WorldState:
	var def: RegionDef = RegionDef.new()
	def.width_tiles = String(rows[0]).length()
	def.height_tiles = rows.size()
	def.terrains = region_def.terrains
	def.sprout_seed = region_def.sprout_seed
	var image: Image = Image.create(def.width_tiles, def.height_tiles, false, Image.FORMAT_RGB8)
	var glyphs: Dictionary = {".": &"wasteland", "s": &"safe", ":": &"shore", "~": &"water", "#": &"building", "h": &"shallows"}
	for y: int in rows.size():
		for x: int in String(rows[y]).length():
			var v: Vector3i = c8(terrain_def(glyphs[String(rows[y])[x]]).map_color)
			image.set_pixel(x, y, Color8(v.x, v.y, v.z))
	return RegionLoader.build_state(def, image)

func overlaps_blocked(world: WorldState, position: Vector2) -> bool:
	# Brute force: every tile the rectangle [pos-half, pos+half) touches with positive area.
	for ty: int in range(floori((position.y - HALF.y) / TILE) - 1, ceili((position.y + HALF.y) / TILE) + 2):
		for tx: int in range(floori((position.x - HALF.x) / TILE) - 1, ceili((position.x + HALF.x) / TILE) + 2):
			var overlap_x: float = minf(position.x + HALF.x, (tx + 1) * TILE) - maxf(position.x - HALF.x, tx * TILE)
			var overlap_y: float = minf(position.y + HALF.y, (ty + 1) * TILE) - maxf(position.y - HALF.y, ty * TILE)
			if overlap_x > 1.0e-3 and overlap_y > 1.0e-3 and not world.is_walkable(tx, ty):
				return true
	return false

## Walk plan for the small map: [[direction, seconds], ...] stepped at `hz`; returns positions at every 1/6 s.
func walk_route(world: WorldState, start: Vector2, plan: Array, hz: int) -> Array[Vector2]:
	var position: Vector2 = start
	var samples: Array[Vector2] = []
	var steps_per_sample: int = hz / 6
	var step: int = 0
	var dt: float = 1.0 / hz
	var never_blocked: bool = true
	for phase: Array in plan:
		var direction: Vector2 = (phase[0] as Vector2).normalized()
		var count: int = roundi(float(phase[1]) * hz)
		for i: int in count:
			position = Walker.move(world, TILE, position, direction * SPEED * dt, HALF)
			never_blocked = never_blocked and not overlaps_blocked(world, position)
			step += 1
			if step % steps_per_sample == 0:
				samples.append(position)
	if not never_blocked:
		samples.append(Vector2(-1, -1))
	return samples

func small_map() -> WorldState:
	# 48 x 24: a river (water) at x 24..27 with a 6-row ford (shallows, rows 10..15); a 4 x 4 building at x 8..11, y 4..7.
	var rows: Array = []
	for y: int in 24:
		var line: String = ""
		for x: int in 48:
			var glyph: String = "."
			if x >= 24 and x <= 27:
				glyph = "h" if (y >= 10 and y <= 15) else "~"
			if x >= 8 and x <= 11 and y >= 4 and y <= 7:
				glyph = "#"
			line += glyph
		rows.append(line)
	return state_from_rows(rows)

# ---- terrain definitions -----------------------------------------------------------------------------------------------

func test_terrain_defs() -> void:
	var water: TerrainDef = terrain_def(&"water")
	var building: TerrainDef = terrain_def(&"building")
	var shallows: TerrainDef = terrain_def(&"shallows")
	check(shallows != null and shallows.id == 5 and region_def.terrains[5] == shallows, "region has a shallows terrain at id 5")
	check(water != null and not water.walkable and building != null and not building.walkable, "water and buildings are not walkable")
	check(shallows != null and shallows.walkable and shallows.is_waterside and not shallows.is_target and not shallows.plantable, "shallows: walkable, waterside, not a greening target, not plantable")
	var walkable_keys: Array[StringName] = []
	for def: TerrainDef in region_def.terrains:
		if def.walkable:
			walkable_keys.append(def.key)
	check(walkable_keys == [&"wasteland", &"safe", &"shore", &"shallows"], "walkable terrains: wasteland, safe, shore, shallows (%s)" % [walkable_keys])
	var colours: Dictionary = {}
	for def: TerrainDef in region_def.terrains:
		colours[c8(def.map_color)] = true
	check(colours.size() == 6, "six distinct legend colours")
	check(c8(water.map_color) == Vector3i(0x40, 0x80, 0xe0) and c8(shallows.map_color) == Vector3i(0x70, 0xb0, 0xe0), "legend colours used by the independent checks below match the terrain defs")
	check(play_tuning.walk_half_width_px == 3.0 and play_tuning.walk_half_height_px == 2.0, "feet rectangle: half size 3 x 2 px (6 x 4 px, 1.5 x 1 tiles)")

# ---- walking: unit level -----------------------------------------------------------------------------------------------

func test_walker_small_map() -> void:
	var world: WorldState = small_map()
	var start: Vector2 = Vector2(82, 14)
	check(Walker.is_clear(world, TILE, start, HALF), "walk: the test start position is clear")
	# Water: walking right stops with the rectangle's right edge exactly on the water's left edge (x = 96).
	var position: Vector2 = start
	var entered: bool = false
	for i: int in 240:
		position = Walker.move(world, TILE, position, Vector2(SPEED / 60.0, 0), HALF)
		entered = entered or overlaps_blocked(world, position)
	check(not entered and absf(position.x - 93.0) < 1.0e-6 and absf(position.y - 14.0) < 1.0e-6, "walk: water blocks; the player stops with its right edge on the water edge (x=%.4f, wanted 93)" % position.x)
	# Pushing against the wall for longer changes nothing.
	for i: int in 60:
		position = Walker.move(world, TILE, position, Vector2(SPEED / 60.0, 0), HALF)
	check(absf(position.x - 93.0) < 1.0e-6, "walk: continued pushing keeps the player at the wall")
	# Water from the other side: left edge on x = 112.
	position = Vector2(130, 14)
	for i: int in 240:
		position = Walker.move(world, TILE, position, Vector2(-SPEED / 60.0, 0), HALF)
	check(absf(position.x - 115.0) < 1.0e-6, "walk: water blocks from the east side (x=%.4f, wanted 115)" % position.x)
	# Building: from the right (building x 8..11 -> right edge x = 48), from above and below (y 16..32).
	position = Vector2(70, 22)
	for i: int in 240:
		position = Walker.move(world, TILE, position, Vector2(-SPEED / 60.0, 0), HALF)
	check(absf(position.x - 51.0) < 1.0e-6, "walk: a building blocks from the east (x=%.4f, wanted 51)" % position.x)
	position = Vector2(40, 60)
	for i: int in 240:
		position = Walker.move(world, TILE, position, Vector2(0, -SPEED / 60.0), HALF)
	check(absf(position.y - 34.0) < 1.0e-6, "walk: a building blocks from below (y=%.4f, wanted 34)" % position.y)
	# Building from above: stand over it at x 40 (inside x 32..48), move down from y 8.
	position = Vector2(40, 6)
	for i: int in 240:
		position = Walker.move(world, TILE, position, Vector2(0, SPEED / 60.0), HALF)
	check(absf(position.y - 14.0) < 1.0e-6, "walk: a building blocks from above (y=%.4f, wanted 14)" % position.y)
	# Shallows: crossing the ford on row 12 (y 48..52), reaching the far map edge (x = 192 - 3).
	position = Vector2(82, 50)
	var ford_entered: bool = false
	var in_ford: bool = false
	for i: int in 360:
		position = Walker.move(world, TILE, position, Vector2(SPEED / 60.0, 0), HALF)
		ford_entered = ford_entered or overlaps_blocked(world, position)
		in_ford = in_ford or (position.x > 100 and position.x < 108)
	check(not ford_entered and in_ford and absf(position.x - 189.0) < 1.0e-6, "walk: the shallows can be crossed (stood in the ford, ended at the map edge x=%.3f, wanted 189)" % position.x)
	# A row just outside the ford is blocked (row 9 = y 36..40, rectangle rows 9).
	position = Vector2(82, 38)
	for i: int in 240:
		position = Walker.move(world, TILE, position, Vector2(SPEED / 60.0, 0), HALF)
	check(absf(position.x - 93.0) < 1.0e-6, "walk: one row above the ford is still water (x=%.3f)" % position.x)
	# The rectangle is 4 px tall: a player centred on the ford's first row boundary is blocked by the water row above.
	position = Vector2(82, 40)
	for i: int in 240:
		position = Walker.move(world, TILE, position, Vector2(SPEED / 60.0, 0), HALF)
	check(absf(position.x - 93.0) < 1.0e-6, "walk: a rectangle half over water (y=40: rows 9 and 10) is stopped by the water row")
	# Sliding: diagonal into the wall keeps the along-wall speed (full y component), x stays at the wall.
	position = Vector2(88, 14)
	var elapsed_steps: int = 18
	for i: int in elapsed_steps:
		position = Walker.move(world, TILE, position, Vector2(1, 1).normalized() * SPEED / 60.0, HALF)
	var along: float = SPEED * sqrt(0.5) * float(elapsed_steps) / 60.0
	check(absf(position.x - 93.0) < 1.0e-6 and absf(position.y - (14.0 + along)) < 1.0e-3, "walk: sliding along the wall for 0.3 s: x pinned at 93, y advanced %.3f of %.3f (the diagonal's full y component, no sticking)" % [position.y - 14.0, along])
	# The wall has an opening (the ford): sliding down along it, the player passes through once the rectangle fits.
	position = Vector2(88, 14)
	for i: int in 90:
		position = Walker.move(world, TILE, position, Vector2(1, 1).normalized() * SPEED / 60.0, HALF)
	check(position.x > 100.0 and not overlaps_blocked(world, position), "walk: diagonal push along the wall slips through the ford opening (x=%.2f) without entering water" % position.x)
	# Slide along a building wall to the corner and past it.
	position = Vector2(52, 14)
	for i: int in 90:
		position = Walker.move(world, TILE, position, Vector2(-1, 1).normalized() * SPEED / 60.0, HALF)
	check(position.y > 14.0 + 50.0 and position.x < 51.0 and not overlaps_blocked(world, position), "walk: diagonal against the building's east face slides down along it and on past its corner (pos %s)" % position)
	# Free diagonal in open ground: constant speed 96 px/s.
	position = Vector2(40, 40)
	var origin: Vector2 = position
	for i: int in 30:
		position = Walker.move(world, TILE, position, Vector2(1, 1).normalized() * SPEED / 60.0, HALF)
	check(absf(position.distance_to(origin) - SPEED * 0.5) < 1.0e-3, "walk: a free diagonal covers 96 px/s (%.4f px in 0.5 s)" % position.distance_to(origin))
	# Starting inside a blocked tile does not trap the player (escape through free tiles), and nothing crashes at edges.
	position = Vector2(94, 14)
	position = Walker.move(world, TILE, position, Vector2(-3, 0), HALF)
	check(position.x < 94.0, "walk: a rectangle already overlapping water can still move away from it")
	position = Vector2(10, 10)
	position = Walker.move(world, TILE, position, Vector2(-50, -50), HALF)
	check(absf(position.x - 3.0) < 1.0e-6 and absf(position.y - 2.0) < 1.0e-6, "walk: the map edge blocks like a wall (stopped at %s, wanted (3, 2))" % position)

func test_frame_rate_independence() -> void:
	var world: WorldState = small_map()
	var plan: Array = [[Vector2(1, 1), 1.0], [Vector2(0, -1), 0.5], [Vector2(-1, 0), 0.5], [Vector2(1, 0.3), 1.0], [Vector2(1, 0), 3.0]]
	var start: Vector2 = Vector2(82, 14)
	var runs: Dictionary = {}
	for hz: int in [30, 60, 144]:
		runs[hz] = walk_route(world, start, plan, hz)
	var same_length: bool = runs[30].size() == runs[60].size() and runs[60].size() == runs[144].size()
	var worst: float = 0.0
	var blocked_seen: bool = false
	if same_length:
		for i: int in runs[60].size():
			worst = maxf(worst, maxf((runs[30][i] as Vector2).distance_to(runs[60][i]), (runs[144][i] as Vector2).distance_to(runs[60][i])))
	for hz: int in runs:
		for p: Vector2 in runs[hz]:
			blocked_seen = blocked_seen or p == Vector2(-1, -1)
	check(same_length and not blocked_seen and worst <= Walker.MAX_SUBSTEP + 1.0e-3, "walk: 30 / 60 / 144 Hz give the same path along the wall, through the ford opening, to the map edge (%d samples every 1/6 s, worst deviation %.4f px, bound %.2f px)" % [runs[60].size(), worst, Walker.MAX_SUBSTEP])
	var finals: Array = [runs[30][-1], runs[60][-1], runs[144][-1]]
	check((finals[0] as Vector2).distance_to(finals[1]) <= Walker.MAX_SUBSTEP + 1.0e-3 and (finals[2] as Vector2).distance_to(finals[1]) <= Walker.MAX_SUBSTEP + 1.0e-3 and absf((finals[1] as Vector2).x - 189.0) < 1.0e-3, "walk: the three rates end at the same place (%s %s %s)" % [finals[0], finals[1], finals[2]])
	# A plan that never meets an opening: the paths are identical down to float rounding.
	var plain_plan: Array = [[Vector2(1, 1), 1.0 / 3.0], [Vector2(0, -1), 1.0 / 6.0], [Vector2(-1, 0), 0.5], [Vector2(1, 0), 0.5]]
	var plain: Dictionary = {}
	for hz: int in [30, 60, 144]:
		plain[hz] = walk_route(world, Vector2(82, 6), plain_plan, hz)
	var plain_worst: float = 0.0
	for i: int in plain[60].size():
		plain_worst = maxf(plain_worst, maxf((plain[30][i] as Vector2).distance_to(plain[60][i]), (plain[144][i] as Vector2).distance_to(plain[60][i])))
	check(plain_worst < 1.0e-3, "walk: sliding along a closed wall gives the same path at 30 / 60 / 144 Hz (worst deviation %.6f px)" % plain_worst)
	info["frame_rate_plain_worst_px"] = plain_worst
	info["frame_rate_path_worst_px"] = worst

# ---- the map ---------------------------------------------------------------------------------------------------------

func is_target_colour(c: int) -> bool:
	return c == C_WASTELAND or c == C_SHORE or c == C_SAFE

func is_walk_colour(c: int) -> bool:
	return c == C_WASTELAND or c == C_SHORE or c == C_SAFE or c == C_SHALLOWS

func test_map_independent_bfs() -> void:
	# Independent of WorldState / TerrainDef: raw PNG pixels, colour constants of this file.
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(region_def.map_path))
	image.convert(Image.FORMAT_RGB8)
	var w: int = image.get_width()
	var h: int = image.get_height()
	check(w == 512 and h == 512, "map PNG is 512 x 512")
	var data: PackedByteArray = image.get_data()
	var colour: PackedInt32Array = PackedInt32Array()
	colour.resize(w * h)
	var unknown: int = 0
	var counts: Dictionary = {}
	for i: int in w * h:
		var c: int = (data[i * 3] << 16) | (data[i * 3 + 1] << 8) | data[i * 3 + 2]
		colour[i] = c
		counts[c] = int(counts.get(c, 0)) + 1
		if not (is_walk_colour(c) or c == C_WATER or c == C_BUILDING):
			unknown += 1
	check(unknown == 0, "every map pixel is one of the six legend colours")
	var total_targets: int = int(counts.get(C_WASTELAND, 0)) + int(counts.get(C_SHORE, 0)) + int(counts.get(C_SAFE, 0))
	info["map_counts"] = {"wasteland": counts.get(C_WASTELAND), "shore": counts.get(C_SHORE), "safe": counts.get(C_SAFE), "water": counts.get(C_WATER), "building": counts.get(C_BUILDING), "shallows": counts.get(C_SHALLOWS), "targets": total_targets}
	var start: Vector2i = region_def.start_tile
	var source: Vector2i = region_def.seed_source_tiles[0]
	check(is_walk_colour(colour[start.y * w + start.x]) and is_walk_colour(colour[source.y * w + source.x]), "the start tile and the seed source tile are walkable ground")
	check(colour[start.y * w + start.x] == C_SAFE and colour[source.y * w + source.x] == C_SAFE, "the start and the seed source lie in the safe zone")
	# 4-neighbour flood fill from the start over walkable colours.
	var seen: PackedByteArray = flood(colour, w, h, start, false)
	var reach_targets: int = 0
	var reach_walk: int = 0
	var shallows_reached: int = 0
	var shallows_targets: int = 0
	for i: int in w * h:
		if seen[i] == 1:
			reach_walk += 1
			if is_target_colour(colour[i]):
				reach_targets += 1
			if colour[i] == C_SHALLOWS:
				shallows_reached += 1
		if colour[i] == C_SHALLOWS and is_target_colour(colour[i]):
			shallows_targets += 1
	# Unreachable target components (closed pockets).
	var pocket_seen: PackedByteArray = seen.duplicate()
	var pockets: Array[int] = []
	for i: int in w * h:
		if is_target_colour(colour[i]) and pocket_seen[i] == 0:
			var size: int = fill_component(colour, w, h, i, pocket_seen)
			pockets.append(size)
	pockets.sort()
	var pocket_total: int = 0
	for size: int in pockets:
		pocket_total += size
	print("INFO map: targets=%d reachable=%d unreachable=%d in %d pockets %s" % [total_targets, reach_targets, total_targets - reach_targets, pockets.size(), pockets])
	check(reach_targets + pocket_total == total_targets, "reachable + closed-pocket targets add up to all targets (%d + %d = %d)" % [reach_targets, pocket_total, total_targets])
	check(reach_targets == 244202 and total_targets == 244759, "walkable-reachable greening targets from the start: %d of %d (independent BFS; expected 244202 / 244759)" % [reach_targets, total_targets])
	check(pockets.size() == 8 and pocket_total == 557, "closed pockets that cannot be walked to: %d pockets, %d tiles (the lake island 109 and seven 64-tile ring enclosures)" % [pockets.size(), pocket_total])
	check(float(reach_targets) / float(total_targets) > 0.995, "the walkable part is almost all of the map (%.3f %%)" % (100.0 * reach_targets / total_targets))
	check(shallows_targets == 0, "shallows pixels are never greening targets")
	# Fords: connected shallows components, each touching walkable land on both sides of the river.
	var ford_seen: PackedByteArray = PackedByteArray()
	ford_seen.resize(w * h)
	var fords: Array[Rect2i] = []
	for i: int in w * h:
		if colour[i] == C_SHALLOWS and ford_seen[i] == 0:
			fords.append(component_bounds(colour, w, h, i, ford_seen, C_SHALLOWS))
	info["fords"] = fords.map(func(r: Rect2i) -> Array: return [r.position.x, r.position.y, r.size.x, r.size.y])
	check(fords.size() >= 3, "the river has %d fords (shallows bands), at least 3 wanted" % fords.size())
	var fords_ok: bool = true
	for ford: Rect2i in fords:
		var mid_y: int = ford.position.y + ford.size.y / 2
		var west_land: bool = is_target_colour(colour[mid_y * w + ford.position.x - 1]) or colour[mid_y * w + ford.position.x - 1] == C_SHALLOWS
		var east_land: bool = is_target_colour(colour[mid_y * w + ford.end.x]) or colour[mid_y * w + ford.end.x] == C_SHALLOWS
		fords_ok = fords_ok and west_land and east_land and ford.size.y >= 4
	check(fords_ok, "every ford is at least 4 rows tall and touches walkable ground west and east of it")
	check(shallows_reached == int(counts.get(C_SHALLOWS, 0)), "every shallows tile is walkable-reachable from the start (%d of %d)" % [shallows_reached, counts.get(C_SHALLOWS, 0)])
	# Both banks: reachable targets east of the river (x >= 290) and west of it (x <= 220).
	var east: int = 0
	var west: int = 0
	var east_all: int = 0
	var west_all: int = 0
	for y: int in h:
		for x: int in w:
			var i: int = y * w + x
			if is_target_colour(colour[i]):
				if x >= 290:
					east_all += 1
					east += seen[i]
				elif x <= 220:
					west_all += 1
					west += seen[i]
	check(west > 0 and east > 0 and float(west) / west_all > 0.99 and float(east) / east_all > 0.99, "both banks are reachable on foot: west %d of %d, east %d of %d targets" % [west, west_all, east, east_all])
	info["bank_targets"] = {"west_reach": west, "west_all": west_all, "east_reach": east, "east_all": east_all}
	# Clearance: tiles the 6 x 4 px rectangle can stand on when centred on the tile (the tile and its east/west neighbours
	# walkable). Walking between such tiles is physically possible, so the BFS over them is a lower bound on foot reach.
	var standable: PackedByteArray = PackedByteArray()
	standable.resize(w * h)
	for y: int in h:
		for x: int in range(1, w - 1):
			var i: int = y * w + x
			if is_walk_colour(colour[i]) and is_walk_colour(colour[i - 1]) and is_walk_colour(colour[i + 1]):
				standable[i] = 1
	var start_ok: bool = standable[start.y * w + start.x] == 1
	var phys_seen: PackedByteArray = flood_mask(standable, w, h, start)
	var phys_targets: int = 0
	for i: int in w * h:
		if phys_seen[i] == 1 and is_target_colour(colour[i]):
			phys_targets += 1
	print("INFO map: targets reachable by a 6x4 px rectangle (standable-tile BFS) = %d" % phys_targets)
	info["standable_reach_targets"] = phys_targets
	# Targets the rectangle cannot stand on (dead-end alleys narrower than 3 tiles, the 8-tile edge band) must still be
	# in shooting range of ground it can reach: Chebyshev distance transform to the standable-reachable set.
	var far: PackedInt32Array = PackedInt32Array()
	far.resize(w * h)
	for i: int in w * h:
		far[i] = 0 if phys_seen[i] == 1 else 100000
	for y: int in h:
		for x: int in w:
			var i: int = y * w + x
			var best: int = far[i]
			if x > 0:
				best = mini(best, far[i - 1] + 1)
			if y > 0:
				best = mini(best, far[i - w] + 1)
				if x > 0:
					best = mini(best, far[i - w - 1] + 1)
				if x < w - 1:
					best = mini(best, far[i - w + 1] + 1)
			far[i] = best
	for y: int in range(h - 1, -1, -1):
		for x: int in range(w - 1, -1, -1):
			var i: int = y * w + x
			var best: int = far[i]
			if x < w - 1:
				best = mini(best, far[i + 1] + 1)
			if y < h - 1:
				best = mini(best, far[i + w] + 1)
				if x < w - 1:
					best = mini(best, far[i + w + 1] + 1)
				if x > 0:
					best = mini(best, far[i + w - 1] + 1)
			far[i] = best
	var farthest: int = 0
	var cannot_stand: int = 0
	for i: int in w * h:
		if seen[i] == 1 and is_target_colour(colour[i]):
			farthest = maxi(farthest, far[i])
			if phys_seen[i] == 0:
				cannot_stand += 1
	print("INFO map: %d reachable targets cannot be stood on by the rectangle; the farthest is %d tiles from ground it can reach" % [cannot_stand, farthest])
	info["no_standing_targets"] = cannot_stand
	info["farthest_no_standing_tiles"] = farthest
	check(start_ok and float(phys_targets) / float(reach_targets) > 0.98 and farthest <= 8, "the 6x4 px rectangle reaches %d of %d walkable targets; the others (%d) are at most %d tiles (%d px) from ground it can reach, well inside the 120 px shot range" % [phys_targets, reach_targets, cannot_stand, farthest, farthest * TILE])
	# The game's own state agrees with the independent count.
	var world: WorldState = RegionLoader.load_region(region_def)
	var agree: bool = true
	for i: int in w * h:
		var expected_walk: bool = is_walk_colour(colour[i])
		var actual_walk: bool = world.is_walkable(i % w, i / w)
		agree = agree and expected_walk == actual_walk
		if is_target_colour(colour[i]) != (world.target[i] == 1):
			agree = false
	check(agree, "WorldState walkability and target flags equal the PNG-derived ones on all 262,144 tiles")
	check(world.target_count == total_targets, "WorldState.target_count equals the independent count (%d)" % world.target_count)
	# Out-of-map tiles are not walkable.
	check(not world.is_walkable(-1, 0) and not world.is_walkable(0, -1) and not world.is_walkable(512, 0) and not world.is_walkable(0, 512), "tiles outside the map are not walkable")

func flood(colour: PackedInt32Array, w: int, h: int, start: Vector2i, _unused: bool) -> PackedByteArray:
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(w * h)
	for i: int in w * h:
		mask[i] = 1 if is_walk_colour(colour[i]) else 0
	return flood_mask(mask, w, h, start)

func flood_mask(mask: PackedByteArray, w: int, h: int, start: Vector2i) -> PackedByteArray:
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(w * h)
	var queue: PackedInt32Array = PackedInt32Array([start.y * w + start.x])
	if mask[queue[0]] == 0:
		return seen
	seen[queue[0]] = 1
	var head: int = 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var x: int = i % w
		var y: int = i / w
		for n: Vector2i in [Vector2i(x + 1, y), Vector2i(x - 1, y), Vector2i(x, y + 1), Vector2i(x, y - 1)]:
			if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h:
				var j: int = n.y * w + n.x
				if seen[j] == 0 and mask[j] == 1:
					seen[j] = 1
					queue.append(j)
	return seen

## Flood fill of walkable tiles from `start` index, marking `seen`; returns the number of TARGET tiles in the component.
func fill_component(colour: PackedInt32Array, w: int, h: int, start: int, seen: PackedByteArray) -> int:
	var queue: PackedInt32Array = PackedInt32Array([start])
	seen[start] = 1
	var head: int = 0
	var targets: int = 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		if is_target_colour(colour[i]):
			targets += 1
		var x: int = i % w
		var y: int = i / w
		for n: Vector2i in [Vector2i(x + 1, y), Vector2i(x - 1, y), Vector2i(x, y + 1), Vector2i(x, y - 1)]:
			if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h:
				var j: int = n.y * w + n.x
				if seen[j] == 0 and is_walk_colour(colour[j]):
					seen[j] = 1
					queue.append(j)
	return targets

func component_bounds(colour: PackedInt32Array, w: int, h: int, start: int, seen: PackedByteArray, wanted: int) -> Rect2i:
	var queue: PackedInt32Array = PackedInt32Array([start])
	seen[start] = 1
	var head: int = 0
	var lo: Vector2i = Vector2i(start % w, start / w)
	var hi: Vector2i = lo
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var x: int = i % w
		var y: int = i / w
		lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
		hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
		for n: Vector2i in [Vector2i(x + 1, y), Vector2i(x - 1, y), Vector2i(x, y + 1), Vector2i(x, y - 1)]:
			if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h:
				var j: int = n.y * w + n.x
				if seen[j] == 0 and colour[j] == wanted:
					seen[j] = 1
					queue.append(j)
	return Rect2i(lo, hi - lo + Vector2i.ONE)

func test_generator_determinism() -> void:
	var out_path: String = ProjectSettings.globalize_path("user://p1_06_regen.png")
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/tools/gen_region_01.gd", "--", "--out=" + out_path], output, true)
	var original: String = FileAccess.get_sha256(ProjectSettings.globalize_path(region_def.map_path))
	var regenerated: String = FileAccess.get_sha256(out_path)
	check(code == 0 and not regenerated.is_empty(), "the generator ran again (exit code %d)" % code)
	check(original == regenerated and not original.is_empty(), "regenerating the map gives byte-identical data/region_01.png (sha256 %s)" % original.substr(0, 16))
	info["map_sha256"] = original

func test_shallows_rules() -> void:
	# Shooting and spreading never plant on shallows; they are not in the greening rate; they are waterside.
	var rows: Array = []
	for y: int in 20:
		rows.append("....hhhhhh....".repeat(2).substr(0, 28))
	var world: WorldState = state_from_rows(rows)
	var shallow_index: int = world.index_of(6, 10)
	var land_index: int = world.index_of(1, 10)
	check(world.target[shallow_index] == 0 and not world.can_plant(shallow_index) and world.can_plant(land_index), "shallows: target flag 0, cannot be planted (land beside it can)")
	var greened: int = world.greened_count
	check(not world.set_stage(shallow_index, WorldState.STAGE_SEED) and world.stage[shallow_index] == WorldState.STAGE_EMPTY and world.greened_count == greened, "shallows: set_stage is refused, greening count unchanged")
	check(not world.set_moisture(shallow_index, 50) and world.moisture[shallow_index] == 0, "shallows: water does not wet them")
	var landed: PackedInt32Array = Landing.scatter_seeds(world, TILE, Vector2(6.5 * TILE, 10.5 * TILE), 10.0, 6, 1)
	check(landed.size() == 0 and world.greened_count == greened, "a seed landing in the middle of the shallows plants nothing (%d)" % landed.size())
	var edge: PackedInt32Array = Landing.scatter_seeds(world, TILE, Vector2(4.0 * TILE, 10.5 * TILE), 10.0, 6, 2)
	var on_shallows: int = 0
	for index: int in edge:
		on_shallows += 1 if world.terrain_defs[world.terrain[index]].key == &"shallows" else 0
	check(edge.size() > 0 and on_shallows == 0, "a seed landing at the shore plants only land tiles (%d planted, %d on shallows)" % [edge.size(), on_shallows])
	# Natural spread does not enter shallows even right next to mature ground.
	world.debug_fill_stage(Rect2i(0, 0, 4, 20), WorldState.STAGE_MATURE)
	var clock: SimClock = SimClock.new()
	clock.configure(sim_tuning)
	var growth: GrowthSim = GrowthSim.new(world, sim_tuning)
	var spread: SpreadSim = SpreadSim.new(world, sim_tuning)
	for i: int in 4000:
		clock.advance(0.25)
		while clock.growth_ticks > growth.ticks:
			growth.tick()
		while clock.spread_ticks > spread.ticks:
			spread.tick()
	var shallows_planted: int = 0
	for y: int in 20:
		for x: int in range(4, 10):
			shallows_planted += 1 if world.stage[world.index_of(x, y)] != WorldState.STAGE_EMPTY else 0
	check(shallows_planted == 0, "natural spread never enters the shallows (1000 s next to a mature field)")
	# Waterside: refill works standing in the shallows and on the shore, not 4+ tiles from any water.
	var play: PlayState = PlayState.new(world, play_tuning, sim_tuning, TILE, [] as Array[Vector2], [] as Array[PlantDef])
	check(play.is_near_water(Vector2(6.5 * TILE, 10.5 * TILE)), "standing in the shallows counts as being at the water (refill)")
	# The real map: a ford tile is waterside, ground far from water is not.
	var real: WorldState = RegionLoader.load_region(region_def)
	var real_play: PlayState = PlayState.new(real, play_tuning, sim_tuning, TILE, [] as Array[Vector2], [] as Array[PlantDef])
	check(not real_play.is_near_water((Vector2(region_def.start_tile) + Vector2(0.5, 0.5)) * TILE), "the start of the real map is not at the water")

func find_open_square(world: WorldState, size: int) -> Rect2i:
	for y: int in range(40, 480, 10):
		for x: int in range(40, 200, 10):
			var ok: bool = true
			for yy: int in range(y, y + size):
				for xx: int in range(x, x + size):
					var index: int = world.index_of(xx, yy)
					if world.terrain_defs[world.terrain[index]].key != &"wasteland" or world.stage[index] != WorldState.STAGE_EMPTY:
						ok = false
						break
				if not ok:
					break
			if ok:
				return Rect2i(x, y, size, size)
	return Rect2i()

# ---- fruits ----------------------------------------------------------------------------------------------------------

func test_fruit_rules() -> void:
	var world: WorldState = RegionLoader.load_region(region_def)
	var safe_tiles: int = 0
	for i: int in world.tile_count():
		if world.terrain_defs[world.terrain[i]].key == &"safe":
			safe_tiles += 1
	check(world.mature_count == safe_tiles and safe_tiles == 331, "the safe zone starts mature (%d tiles)" % world.mature_count)
	check(world.producing_count == 0 and world.counters_consistent(), "safe-zone plants are fruitless: 0 producing tiles of %d mature" % world.mature_count)
	# Production around the start for 10 minutes: only the source's own fruits ever exist.
	var sources: Array[Vector2] = []
	for tile: Vector2i in region_def.seed_source_tiles:
		sources.append((Vector2(tile) + Vector2(0.5, 0.5)) * TILE)
	var defs: Array[PlantDef] = []
	defs.assign(region_def.plants)
	var play: PlayState = PlayState.new(world, play_tuning, sim_tuning, TILE, sources, defs)
	var start: Vector2 = Vector2(region_def.start_tile * TILE) + Vector2(2, 2)
	var plant_fruits_max: int = 0
	var seeds_start: int = play.seeds
	for i: int in 600 * 6:
		play.advance(1.0 / 6.0, start + Vector2(30, 30))
		plant_fruits_max = maxi(plant_fruits_max, play.pickups.count_plant_owned())
	check(play.producer.total_produced == 0 and plant_fruits_max == 0, "10 minutes next to the safe zone: no plant fruit is produced (total %d, most on the ground %d)" % [play.producer.total_produced, plant_fruits_max])
	check(play.pickups.count() <= play_tuning.source_fruit_cap and seeds_start == 20, "only the seed source's fruits lie around (%d <= %d); the start seed stock is %d" % [play.pickups.count(), play_tuning.source_fruit_cap, seeds_start])
	# A natural (non-ready-made) mature patch does produce.
	var patch: Rect2i = find_open_square(world, 20)
	check(patch.size.x == 20, "found an open 20 x 20 wasteland square at %s" % patch)
	var mature_before: int = world.mature_count
	world.debug_fill_stage(patch, WorldState.STAGE_MATURE)
	check(world.mature_count == mature_before + 400 and world.producing_count == 400 and world.counters_consistent(), "a grown mature patch counts as producing (400 tiles)")
	var middle: Vector2 = (Vector2(patch.position) + Vector2(10, 10)) * TILE
	for i: int in 60 * 6:
		play.advance(1.0 / 6.0, middle)
	check(play.producer.total_produced > 5, "a grown mature patch produces fruits around the player (%d in 60 s)" % play.producer.total_produced)
	var all_in_patch: bool = true
	for item: Dictionary in play.pickups.items:
		if GroundPickups.is_plant_owner(int(item["owner"])):
			var tx: int = floori(float(item["x"]) / TILE)
			var ty: int = floori(float(item["y"]) / TILE)
			all_in_patch = all_in_patch and patch.has_point(Vector2i(tx, ty))
	check(all_in_patch, "plant fruits drop only on producing tiles of the patch")
	# A safe-zone tile that is cleared and grows back produces like any other.
	var safe_tile: int = world.index_of(region_def.start_tile.x, region_def.start_tile.y)
	var producing_before: int = world.producing_count
	world.set_stage(safe_tile, WorldState.STAGE_EMPTY)
	check(world.fruitless[safe_tile] == 0 and world.mature_count == mature_before + 400 - 1 and world.producing_count == producing_before, "clearing a ready-made tile clears its fruitless mark")
	world.set_stage(safe_tile, WorldState.STAGE_MATURE)
	check(world.producing_count == producing_before + 1 and world.counters_consistent(), "the same tile grown back is a normal producing tile")
	var count_check: int = 0
	var chunk_sum: int = 0
	for v: int in world.producing_chunk_count:
		chunk_sum += v
	for i: int in world.tile_count():
		count_check += 1 if (world.stage[i] == WorldState.STAGE_MATURE and world.fruitless[i] == 0) else 0
	check(count_check == world.producing_count and chunk_sum == world.producing_count, "producing counters equal a brute-force recount (%d) and the chunk sum (%d)" % [count_check, chunk_sum])
	# Save round trip keeps the marks.
	var restored: WorldState = WorldState.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())), region_def.terrains)
	check(restored != null and restored.fruitless == world.fruitless and restored.producing_count == world.producing_count, "a save round trip keeps the fruitless marks and the producing count")
	var older: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict()))
	older.erase("fruitless")
	var derived: WorldState = WorldState.from_dict(older, region_def.terrains)
	check(derived != null and derived.producing_count == derived.mature_count - safe_tiles and derived.counters_consistent(), "an older save without the list derives it: every mature safe-zone tile is fruitless (even one that had regrown; the list is only a fallback)")
	# Brute-force producer check: count_near agrees with a scan of the producing tiles.
	var probe: Vector2 = middle + Vector2(30, 0)
	var expected: int = 0
	for i: int in world.tile_count():
		if world.stage[i] == WorldState.STAGE_MATURE and world.fruitless[i] == 0:
			var centre: Vector2 = Vector2((i % world.width + 0.5) * TILE, (i / world.width + 0.5) * TILE)
			if centre.distance_squared_to(probe) <= 160.0 * 160.0:
				expected += 1
	check(play.producer.count_near(probe, 160.0) == expected, "the producer counts exactly the producing tiles within 160 px (%d)" % expected)
	# Immediately after the start of the real scene setup there is nothing but source fruit (already shown above).

func luminance(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

func colour_distance(a: Color, b: Color) -> float:
	return sqrt((a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b))

func opaque_pixels(texture: ImageTexture) -> Array[Color]:
	var image: Image = texture.get_image()
	var result: Array[Color] = []
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				result.append(image.get_pixel(x, y))
	return result

func mean_colour(pixels: Array[Color]) -> Color:
	var sum: Color = Color(0, 0, 0, 0)
	for p: Color in pixels:
		sum += p
	return Color(sum.r / pixels.size(), sum.g / pixels.size(), sum.b / pixels.size(), 1.0)

func test_fruit_colours() -> void:
	var plant: Array[Color] = opaque_pixels(PlayArt.plant_fruit())
	var source: Array[Color] = opaque_pixels(PlayArt.fruit())
	var heal: Array[Color] = opaque_pixels(PlayArt.heal_fruit())
	check(plant.size() == 12 and source.size() == 12 and heal.size() == 12, "all three fruits are 4x4 sprites with 12 opaque pixels")
	# Backgrounds a fruit can lie on: every target terrain's ground, the mature plant colour, its half-transparent edge, sprouts.
	var backgrounds: Dictionary = {"mature": sim_tuning.mature_color, "sprout": sim_tuning.sprout_color}
	for def: TerrainDef in region_def.terrains:
		if def.is_target:
			backgrounds[String(def.key) + " ground"] = def.ground_color
			backgrounds[String(def.key) + " mature edge"] = def.ground_color.lerp(sim_tuning.mature_color, sim_tuning.edge_alpha)
	var worst_fraction: float = 1.0
	var worst_name: String = ""
	var fraction_report: Dictionary = {}
	var brightness_report: Dictionary = {}
	var worst_bright: float = 1.0
	for name: String in backgrounds:
		var bg: Color = backgrounds[name]
		var readable: int = 0
		var brighter_or_darker: int = 0
		for pixel: Color in plant:
			if colour_distance(pixel, bg) >= 0.28 or absf(luminance(pixel) - luminance(bg)) >= 0.2:
				readable += 1
			if absf(luminance(pixel) - luminance(bg)) >= 0.2:
				brighter_or_darker += 1
		var fraction: float = float(readable) / plant.size()
		fraction_report[name] = snappedf(fraction, 0.01)
		brightness_report[name] = snappedf(float(brighter_or_darker) / plant.size(), 0.01)
		if fraction < worst_fraction:
			worst_fraction = fraction
			worst_name = name
		if name.contains("mature"):
			worst_bright = minf(worst_bright, float(brighter_or_darker) / plant.size())
	info["plant_fruit_readable_fraction"] = fraction_report
	info["plant_fruit_brightness_fraction"] = brightness_report
	check(worst_fraction >= 0.75, "the plant fruit is readable on every ground: at least %.0f %% of its pixels differ clearly (colour distance >= 0.28 or brightness >= 0.2) from the worst background (%s)" % [worst_fraction * 100.0, worst_name])
	check(worst_bright >= 0.75, "on mature green (and its half-transparent edges), at least %.0f %% of the plant fruit pixels also differ in brightness (not by hue alone)" % [worst_bright * 100.0])
	var mean_plant: Color = mean_colour(plant)
	var mean_source: Color = mean_colour(source)
	var mean_heal: Color = mean_colour(heal)
	check(colour_distance(mean_plant, mean_source) >= 0.2 and colour_distance(mean_plant, mean_heal) >= 0.3 and colour_distance(mean_source, mean_heal) >= 0.2, "the three fruits differ in colour: plant/source %.2f, plant/heal %.2f, source/heal %.2f" % [colour_distance(mean_plant, mean_source), colour_distance(mean_plant, mean_heal), colour_distance(mean_source, mean_heal)])
	var distinct_pixels: bool = true
	for p: Color in plant:
		for q: Color in source:
			if p.is_equal_approx(q):
				distinct_pixels = false
		for q: Color in heal:
			if p.is_equal_approx(q):
				distinct_pixels = false
	check(distinct_pixels, "no pixel colour is shared between the plant fruit and the other two fruits")
	var shapes_differ: bool = PlayArt.plant_fruit().get_image().get_data() != PlayArt.fruit().get_image().get_data()
	check(shapes_differ, "the plant fruit and the source fruit are different images")

# ---- walking through the real scene with injected key events ---------------------------------------------------

func send_key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

## Injected events reach the action state at the start of the next frame, so wait for it.
func press(code: Key, pressed: bool) -> void:
	send_key(code, pressed)
	await process_frame

func row_wall(world: WorldState, y: int, x_from: int) -> int:
	# First non-walkable tile east of x_from on row y.
	for x: int in range(x_from, world.width):
		if not world.is_walkable(x, y):
			return x
	return -1

func steps(count: int) -> void:
	for i: int in count:
		player._physics_process(1.0 / 60.0)

func test_scene_walk() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	player = main.player
	var world: WorldState = main.grid
	check(player.walk_world == world and player.walk_half == HALF, "the scene wires the player to the world (feet rectangle %s)" % player.walk_half)
	check(Walker.is_clear(world, TILE, player.simulation_position, HALF), "the player starts on clear ground")
	# Manual physics steps with injected keys (deterministic: the player's own physics callback is switched off, so no
	# engine tick moves the player between the steps; step 7 turns it back on).
	main.play_driver.process_mode = Node.PROCESS_MODE_DISABLED
	main.simulation.process_mode = Node.PROCESS_MODE_DISABLED
	player.set_physics_process(false)
	# 1. Open ground, diagonal: D + S for 1 s. Constant speed 96 px/s.
	player.simulation_position = Vector2(region_def.start_tile * TILE) + Vector2(2, 2)
	var origin: Vector2 = player.simulation_position
	await press(KEY_D, true)
	await press(KEY_S, true)
	check(Input.is_action_pressed("move_right") and Input.is_action_pressed("move_down"), "the injected D and S key events reach the move actions")
	steps(60)
	var travelled: float = player.simulation_position.distance_to(origin)
	check(absf(travelled - SPEED) < 0.01, "injected D+S for 1 s in the open: %.3f px travelled (96 wanted; the diagonal is not faster)" % travelled)
	await press(KEY_D, false)
	await press(KEY_S, false)
	# 2. Row 100 eastwards until the water; find the wall independently from the world tiles.
	var row: int = 100
	var wall_x: int = row_wall(world, row, 200)
	var stop_x: float = float(wall_x * TILE) - HALF.x
	player.simulation_position = Vector2(200 * TILE, row * TILE + 2)
	await press(KEY_D, true)
	var entered_water: bool = false
	for i: int in 400:
		steps(1)
		entered_water = entered_water or overlaps_blocked(world, player.simulation_position)
	await press(KEY_D, false)
	check(not entered_water and absf(player.simulation_position.x - stop_x) < 1.0e-4, "injected D: the player stops at the river bank on row %d (x=%.3f, wanted %.3f), never inside the water" % [row, player.simulation_position.x, stop_x])
	var at_wall: Vector2 = player.simulation_position
	# 3. Pushing diagonally against the bank slides along it.
	await press(KEY_D, true)
	await press(KEY_S, true)
	steps(30)
	await press(KEY_D, false)
	await press(KEY_S, false)
	var slid: Vector2 = player.simulation_position - at_wall
	check(absf(slid.y - SPEED * 0.5 * sqrt(0.5)) < 0.05 and absf(slid.x) < 0.5 and not overlaps_blocked(world, player.simulation_position), "injected D+S against the bank for 0.5 s: slid %.2f px down (wanted %.2f), x moved %.3f" % [slid.y, SPEED * 0.5 * sqrt(0.5), slid.x])
	# 4. A building: walk west into the east face of the first building run found on the real map.
	var building_row: int = -1
	var building_x: int = -1
	for y: int in range(120, 400):
		for x: int in range(60, 200):
			if world.terrain_defs[world.terrain[world.index_of(x, y)]].key == &"building" and world.is_walkable(x + 3, y) and world.is_walkable(x + 4, y):
				building_row = y
				building_x = x
				break
		if building_row >= 0:
			break
	check(building_row >= 0, "found a building tile on the real map at (%d, %d)" % [building_x, building_row])
	var east_face: int = building_x
	while east_face + 1 < world.width and world.terrain_defs[world.terrain[world.index_of(east_face + 1, building_row)]].key == &"building":
		east_face += 1
	player.simulation_position = Vector2((east_face + 1 + 8) * TILE, building_row * TILE + 2)
	var start_clear: bool = Walker.is_clear(world, TILE, player.simulation_position, HALF)
	await press(KEY_A, true)
	var entered_building: bool = false
	for i: int in 200:
		steps(1)
		entered_building = entered_building or overlaps_blocked(world, player.simulation_position)
	await press(KEY_A, false)
	var building_stop: float = float((east_face + 1) * TILE) + HALF.x
	check(start_clear and not entered_building and absf(player.simulation_position.x - building_stop) < 1.0e-4, "injected A: the player stops at the building's east face (x=%.3f, wanted %.3f)" % [player.simulation_position.x, building_stop])
	# 5. Each ford of the real map: cross it with D only along the middle of the band.
	var fords: Array = info["fords"]
	var crossed: int = 0
	for ford: Array in fords:
		var y: int = int(ford[1]) + int(ford[3]) / 2
		var west_x: int = int(ford[0]) - 12
		player.simulation_position = Vector2(west_x * TILE, y * TILE)
		await press(KEY_D, true)
		var inside_water: bool = false
		var was_in_ford: bool = false
		for i: int in 150:
			steps(1)
			inside_water = inside_water or overlaps_blocked(world, player.simulation_position)
			var tx: int = floori(player.simulation_position.x / TILE)
			was_in_ford = was_in_ford or (tx > int(ford[0]) + 2 and tx < int(ford[0]) + int(ford[2]) - 2)
		await press(KEY_D, false)
		var tile_x: int = floori(player.simulation_position.x / TILE)
		if not inside_water and was_in_ford and tile_x > int(ford[0]) + int(ford[2]):
			crossed += 1
	check(crossed == fords.size(), "injected D crosses each of the %d fords (crossed %d) without entering the water" % [fords.size(), crossed])
	# 6. Three rows above the first ford's band the river is water: blocked.
	var ford0: Array = fords[0]
	player.simulation_position = Vector2((int(ford0[0]) - 12) * TILE, (int(ford0[1]) - 3) * TILE)
	await press(KEY_D, true)
	steps(200)
	await press(KEY_D, false)
	check(floori(player.simulation_position.x / TILE) < int(ford0[0]) + 2, "injected D three rows above the ford is stopped by the water (tile x %d, the ford starts at %d)" % [floori(player.simulation_position.x / TILE), int(ford0[0])])
	# 7. The engine's own physics loop (not manual stepping): hold D for a stretch of real physics frames.
	player.set_physics_process(true)
	player.simulation_position = Vector2(region_def.start_tile * TILE) + Vector2(2, 2)
	await press(KEY_D, true)
	var x0: float = player.simulation_position.x
	var ticks0: int = Engine.get_physics_frames()
	for i: int in 45:
		await physics_frame
	var ticks: int = Engine.get_physics_frames() - ticks0
	var moved: float = player.simulation_position.x - x0
	await press(KEY_D, false)
	var expected_move: float = SPEED / float(Engine.physics_ticks_per_second) * float(ticks)
	check(ticks >= 40 and absf(moved - expected_move) < SPEED / 60.0 * 1.5, "the real physics loop moves the held player: %d ticks, %.2f px (about %.2f)" % [ticks, moved, expected_move])
	# 8. Pause: nothing moves while paused.
	player.simulation_position = Vector2(region_def.start_tile * TILE) + Vector2(2, 2)
	await press(KEY_D, true)
	paused = true
	var before_pause: Vector2 = player.simulation_position
	for i: int in 20:
		await physics_frame
	var after_pause: Vector2 = player.simulation_position
	await press(KEY_D, false)
	paused = false
	check(after_pause == before_pause, "while the tree is paused the held key moves nobody (20 physics frames)")
	main.queue_free()
	await process_frame

# ---- tempo ------------------------------------------------------------------------------------------------------------

func run_bot(mode: String, minutes: float, dt: float) -> Dictionary:
	var bot: RefCounted = Bot.new()
	bot.bot_on = mode != "b"
	bot.carrots_on = mode == "a"
	var limit: float = minutes * 60.0
	while bot.time < limit and not bot.is_complete():
		bot.step(dt)
	bot.samples.append(bot.snapshot())
	return {"bot": bot, "minutes": bot.time / 60.0, "complete": bot.is_complete(), "percent": bot.percent_now(), "reach_times": bot.reach_times.duplicate()}

func at_minute(samples: Array[Dictionary], minute: float) -> float:
	var best: float = 0.0
	for s: Dictionary in samples:
		if float(s["t"]) <= minute * 60.0 + 0.5:
			best = float(s["percent"])
	return best

func test_tempo() -> void:
	var a: Dictionary = run_bot("a", 60.0, 1.0 / 60.0)
	var c: Dictionary = run_bot("c", 60.0, 1.0 / 60.0)
	var b: Dictionary = run_bot("b", 180.0, 1.0 / 60.0)
	var bot_a: RefCounted = a["bot"]
	var bot_b: RefCounted = b["bot"]
	var bot_c: RefCounted = c["bot"]
	var table: Array = []
	for minute: int in range(0, 65, 5):
		table.append({"minute": minute, "a": snappedf(at_minute(bot_a.samples, minute), 0.1), "b": snappedf(at_minute(bot_b.samples, minute), 0.1), "c": snappedf(at_minute(bot_c.samples, minute), 0.1)})
	var results: Dictionary = {"reachable_targets": bot_a.reach_targets, "a": summary(bot_a), "b": summary(bot_b), "c": summary(bot_c), "table_5min": table}
	var file: FileAccess = FileAccess.open("res://evidence/p1/p1-06/tempo_results.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(results, "  "))
		file.close()
	info["tempo"] = {"a_min": snappedf(a["minutes"], 0.01), "c_min": snappedf(c["minutes"], 0.01), "b_percent_at_180": snappedf(b["percent"], 0.1)}
	for row: Dictionary in table:
		print("TEMPO_TABLE %s" % JSON.stringify(row))
	check(a["complete"] and a["minutes"] >= 20.0 and a["minutes"] <= 35.0, "(a) bot with carrots reaches 100 %% of the walkable targets in %.1f min (target window 20..35 min)" % a["minutes"])
	check(bot_a.world.counters_consistent() and bot_a.reach_greened == bot_a.reach_targets, "(a) ends with every walkable target greened (%d of %d) and consistent counters" % [bot_a.reach_greened, bot_a.reach_targets])
	check(c["complete"] and c["minutes"] >= 15.0 and c["minutes"] <= 40.0, "(c) bot without carrots also finishes in the same order of time: %.1f min" % c["minutes"])
	check(bot_a.carrots_placed >= 5 and bot_c.carrots_placed == 0, "(a) planted %d carrots, (c) none" % bot_a.carrots_placed)
	# (b) natural spread alone: cannot cross the river (shallows are not plantable), so it ends on the west bank.
	var t_a50: float = float(bot_a.reach_times.get(50, 1.0e9))
	var t_b50: float = float(bot_b.reach_times.get(50, 1.0e9))
	var t_a25: float = float(bot_a.reach_times.get(25, 1.0e9))
	var t_b25: float = float(bot_b.reach_times.get(25, 1.0e9))
	check(t_b25 >= 2.0 * t_a25 and t_b50 >= 2.0 * t_a50, "(b) is at least twice as slow as (a): 25 %% at %.1f vs %.1f min, 50 %% at %.1f vs %.1f min" % [t_b25 / 60.0, t_a25 / 60.0, t_b50 / 60.0, t_a50 / 60.0])
	check(not bot_b.is_complete() and bot_b.percent_now() < 60.0, "(b) never finishes: natural spread stops at the river (%.1f %% after 180 min)" % bot_b.percent_now())
	check(at_minute(bot_b.samples, a["minutes"]) <= 25.0, "(b) when (a) has finished (%.1f min) has greened at most a quarter (%.1f %%)" % [a["minutes"], at_minute(bot_b.samples, a["minutes"])])
	# Seed economy: the bot does not stall long.
	check(bot_a.stall_total <= 90.0 and bot_a.stall_longest <= 12.0, "(a) seed stall: %.0f s in total (%.1f %% of the run), longest %.1f s" % [bot_a.stall_total, 100.0 * bot_a.stall_total / bot_a.time, bot_a.stall_longest])
	check(bot_c.stall_total <= 90.0 and bot_c.stall_longest <= 12.0, "(c) seed stall: %.0f s in total, longest %.1f s" % [bot_c.stall_total, bot_c.stall_longest])

func summary(bot: RefCounted) -> Dictionary:
	var reach_minutes: Dictionary = {}
	for mark: int in bot.reach_times:
		reach_minutes[str(mark)] = snappedf(float(bot.reach_times[mark]) / 60.0, 0.01)
	return {"minutes": snappedf(bot.time / 60.0, 0.01), "percent": snappedf(bot.percent_now(), 0.01), "complete": bot.is_complete(), "reach_minutes": reach_minutes, "shots_seed": bot.shots_seed, "shots_water": bot.shots_water, "shots_carrot": bot.shots_carrot, "carrots_placed": bot.carrots_placed, "refills": bot.refills, "stall_total_s": snappedf(bot.stall_total, 0.1), "stall_longest_s": snappedf(bot.stall_longest, 0.1), "stall_log": bot.stall_log, "walk_s": snappedf(bot.walk_time, 0.1), "shots_by_grid": bot.shots_by_grid, "samples": bot.samples}
