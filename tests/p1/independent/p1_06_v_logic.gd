extends SceneTree
## Independent verifier for P1-06, logic level (headless, no scene). Expectations come from the spec (feet 6x4 px, water/
## buildings/outside the map block, shallows walk but are not targets, frame-rate independence) and from my own python/zlib
## map decode (evidence/p1/p1-06/independent/map_analysis.json), not from the implementation's formulas.
## Run: Godot --headless --path <project> --script res://tests/p1/independent/p1_06_v_logic.gd -- [--only=walk|map|ground|fruit]

const OUT: String = "res://evidence/p1/p1-06/independent/"
const T: int = 4
const SPEED: float = 96.0
const HALF: Vector2 = Vector2(3.0, 2.0)
const W_WASTE: int = 0
const W_SAFE: int = 1
const W_SHORE: int = 2
const W_WATER: int = 3
const W_BUILD: int = 4
const W_SHALLOW: int = 5

var results: Array[Dictionary] = []
var observations: Dictionary = {}
var region_def: RegionDef

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func run() -> void:
	region_def = load("res://data/region_01.tres") as RegionDef
	var only: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	var tests: Dictionary = {"walk": t_walk, "map": t_map, "ground": t_ground, "fruit": t_fruit}
	for key: String in tests:
		if only != "" and only != key:
			continue
		print("--- section ", key)
		(tests[key] as Callable).call()
	var f: FileAccess = FileAccess.open(OUT + "checks_logic%s.json" % ("" if only == "" else "_" + only), FileAccess.WRITE)
	f.store_string(JSON.stringify({"results": results, "observations": observations}, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("V_RESULT total=%d fails=%d" % [results.size(), fails])
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------------------------------ helpers

func make_world(w: int, h: int, fill: int = W_WASTE) -> WorldState:
	var s: WorldState = WorldState.new(w, h, region_def.terrains, 12345)
	s.terrain.fill(fill)
	return s

func set_rect(s: WorldState, x0: int, y0: int, x1: int, y1: int, terrain_id: int) -> void:
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			s.terrain[y * s.width + x] = terrain_id

## Independent oracle (continuous geometry): the foot rectangle at p overlaps (positive area) a blocked tile or leaves the map.
func foot_hits_block(s: WorldState, p: Vector2) -> bool:
	var l: float = p.x - HALF.x
	var r: float = p.x + HALF.x
	var t: float = p.y - HALF.y
	var b: float = p.y + HALF.y
	if l < -1e-6 or t < -1e-6 or r > s.width * T + 1e-6 or b > s.height * T + 1e-6:
		return true
	for ty: int in range(maxi(floori(t / T) - 1, 0), mini(floori(b / T) + 2, s.height)):
		for tx: int in range(maxi(floori(l / T) - 1, 0), mini(floori(r / T) + 2, s.width)):
			var def: TerrainDef = s.terrain_defs[s.terrain[ty * s.width + tx]]
			if def.walkable:
				continue
			var ox: float = minf(r, (tx + 1) * T) - maxf(l, tx * T)
			var oy: float = minf(b, (ty + 1) * T) - maxf(t, ty * T)
			if ox > 1e-4 and oy > 1e-4:
				return true
	return false

func walk(s: WorldState, p: Vector2, dir: Vector2, dt: float) -> Vector2:
	var motion: Vector2 = dir.normalized() * SPEED * dt if dir != Vector2.ZERO else Vector2.ZERO
	return Walker.move(s, T, p, motion, HALF)

# ------------------------------------------------------------------------------------------ walk

func t_walk() -> void:
	rec("walk.speed_const", "player speed constant is 96 px/s (spec of earlier stages)", FlowerPlayer.SPEED == SPEED, str(FlowerPlayer.SPEED))
	var pt: PlayTuning = load("res://data/play_tuning.tres") as PlayTuning
	rec("walk.feet_size", "feet are 6x4 px (half 3 x 2)", pt.walk_half_width_px == 3.0 and pt.walk_half_height_px == 2.0, "%s x %s" % [pt.walk_half_width_px, pt.walk_half_height_px])
	# Test world 48x48: water wall (x 24..26, y 0..47 except a 1-tile and a 2-tile gap), building block, thin wall
	var s: WorldState = make_world(48, 48)
	set_rect(s, 24, 0, 26, 47, W_WATER)
	set_rect(s, 24, 10, 26, 10, W_WASTE)  # 1-tile gap (4 px)
	set_rect(s, 24, 30, 26, 31, W_WASTE)  # 2-tile gap (8 px)
	set_rect(s, 5, 5, 8, 8, W_BUILD)
	set_rect(s, 38, 0, 38, 47, W_BUILD)  # thin 1-tile wall
	set_rect(s, 0, 40, 22, 40, W_BUILD)  # horizontal wall y 160..164 with a 1-tile gap (x 48..52) and a 2-tile gap (x 64..72)
	set_rect(s, 12, 40, 12, 40, W_WASTE)
	set_rect(s, 16, 40, 17, 40, W_WASTE)
	s.apply_terrain_defs()
	# 1 random-ish scripted walk at 3 rates: never overlaps a block (my own geometric oracle)
	var dirs: Array[Vector2] = [Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1)]
	var bad_steps: int = 0
	var total_steps: int = 0
	for hz: int in [30, 60, 144]:
		var p: Vector2 = Vector2(60.3, 60.7)
		var dt: float = 1.0 / hz
		for step: int in hz * 60:
			var dir: Vector2 = dirs[(step / (hz / 3)) * 7 % dirs.size()]
			p = walk(s, p, dir, dt)
			total_steps += 1
			if foot_hits_block(s, p):
				bad_steps += 1
	rec("walk.never_inside", "over 60 s of scripted 8-direction walking at 30/60/144 Hz the feet never overlap water, buildings or the map edge", bad_steps == 0, "bad=%d of %d steps" % [bad_steps, total_steps])
	# 2 big hitch step does not tunnel through a one-tile wall (24 px in one call)
	var p2: Vector2 = Vector2(34.0, 60.0)
	p2 = Walker.move(s, T, p2, Vector2(24, 0), HALF)
	rec("walk.no_tunnel", "a 24 px single move toward a 1-tile wall stops at the wall (x <= 38*4-3 = 149)", p2.x <= 149.0 + 1e-3 and not foot_hits_block(s, p2), str(p2))
	# the wall itself at 38*4=152: start left of it at 140
	p2 = Walker.move(s, T, Vector2(140.0, 60.0), Vector2(24, 0), HALF)
	rec("walk.no_tunnel2", "from x=140 a 24 px move stops at 149", absf(p2.x - 149.0) < 0.01, str(p2))
	# 3 each blocking kind: water, building, map edge
	var pw: Vector2 = Vector2(60.0, 60.0)
	for i: int in 200:
		pw = walk(s, pw, Vector2.RIGHT, 1.0 / 60.0)
	# water wall starts x=24*4=96 -> foot right edge at 96 -> x=93
	rec("walk.water_blocks", "walking right into water stops with the foot at the water edge (x=93, within 0.01)", absf(pw.x - 93.0) < 0.01, str(pw))
	var pb: Vector2 = Vector2(60.0, 40.0)
	for i: int in 200:
		pb = walk(s, pb, Vector2.LEFT, 1.0 / 60.0)
	pb = Vector2(36.0, 70.0)
	for i: int in 120:
		pb = walk(s, pb, Vector2.UP, 1.0 / 60.0)
	# building x 5..8 -> px 20..36, y 5..8 -> px 20..36. coming from y=70 moving up at x=36 (foot 33..39 overlaps building x 33..36) -> stops with top edge at 36 -> y=38
	rec("walk.building_blocks", "walking up into a building stops at its edge (y=38)", absf(pb.y - 38.0) < 0.01, str(pb))
	var pe: Vector2 = Vector2(10.0, 100.0)
	for i: int in 300:
		pe = walk(s, pe, Vector2.LEFT, 1.0 / 60.0)
	rec("walk.map_edge_blocks", "map edge blocks (x=3)", absf(pe.x - 3.0) < 0.01, str(pe))
	# 4 slide along a wall: diagonal into the water wall; x pinned, y keeps full per-axis speed with no snag
	var ps: Vector2 = Vector2(60.0, 60.0)
	var per_axis: float = SPEED * 0.70710678 / 60.0
	var max_dev: float = 0.0
	var dy_min: float = INF
	var prev: Vector2 = ps
	var reached_wall: bool = false
	for i: int in 40:
		ps = walk(s, ps, Vector2(1, 1), 1.0 / 60.0)
		if absf(ps.x - 93.0) < 0.01:
			reached_wall = true
			var dy: float = ps.y - prev.y
			dy_min = minf(dy_min, dy)
			max_dev = maxf(max_dev, absf(dy - per_axis))
		prev = ps
	rec("walk.slides", "diagonal into a wall: feet pinned to the wall and slide down at the full axis speed every step (no sticking)", reached_wall and max_dev < 0.002, "dy_min=%.4f expected=%.4f max_dev=%.5f final=%s" % [dy_min, per_axis, max_dev, ps])
	# slide up-left against the building bottom edge and the edge-of-map with the other axis
	var pu: Vector2 = Vector2(30.0, 45.0)
	var x_start: float = pu.x
	for i: int in 9:
		pu = walk(s, pu, Vector2(-1, -1), 1.0 / 60.0)
	rec("walk.slides_building", "diagonal up-left into the building's bottom edge slides left along it (y pinned at 38, x decreasing)", absf(pu.y - 38.0) < 0.01 and pu.x < x_start - 5.0 and pu.x > 17.0, str(pu))
	# 5 doorways: a 1-tile (4 px) gap is too narrow for 6 px feet; a 2-tile (8 px) gap is passable
	var pg: Vector2 = Vector2(60.0, 42.0)  # row y=10 -> px 40..44, centre 42
	for i: int in 200:
		pg = walk(s, pg, Vector2.RIGHT, 1.0 / 60.0)
	rec("walk.exact_fit_gap", "a gap exactly as tall as the feet (4 px), entered centred while walking east, can be passed", pg.x > 96.0 + 3.0, str(pg))
	pg = Vector2(60.0, 126.0)  # row 31/32 boundary: centre of a 2-tile gap (y 120..128, rows 30,31) is 124
	pg = Vector2(60.0, 124.0)
	for i: int in 200:
		pg = walk(s, pg, Vector2.RIGHT, 1.0 / 60.0)
	rec("walk.wide_gap_passes", "an 8 px gap is passable (feet 4 px tall)", pg.x > 110.0, str(pg))
	# a 4 px wide gap (feet are 6 px wide) cannot be entered going north; the 8 px gap can
	var pv: Vector2 = Vector2(50.0, 190.0)
	for i: int in 120:
		pv = walk(s, pv, Vector2.UP, 1.0 / 60.0)
	var pv2: Vector2 = Vector2(68.0, 190.0)
	for i: int in 120:
		pv2 = walk(s, pv2, Vector2.UP, 1.0 / 60.0)
	rec("walk.narrow_gap_blocked", "a 4 px wide gap (feet 6 px wide) cannot be entered going north: stops below the wall (y=166)", absf(pv.y - 166.0) < 0.01, str(pv))
	rec("walk.wide_gap_north", "the 8 px wide gap can be passed going north", pv2.y < 150.0, str(pv2))
	# off-centre by 3 px: a foot 4 tall cannot fit through a 4 px gap off-centre
	var po: Vector2 = Vector2(60.0, 45.0)
	for i: int in 200:
		po = walk(s, po, Vector2.RIGHT, 1.0 / 60.0)
	rec("walk.off_center_blocked", "off-centre (y=45, feet 43..47 overlaps the wall rows) the 4 px gap is closed", po.x < 96.0, str(po))
	# 6 diagonal speed on open ground: exactly 96 px/s at every rate
	var worst: float = 0.0
	for hz: int in [30, 60, 144]:
		var pd: Vector2 = Vector2(20.0, 150.0)  # open area west of the water wall; keep it short
		pd = Vector2(12.0, 60.0)
		var start: Vector2 = pd
		var dt: float = 1.0 / hz
		var steps: int = hz / 2
		for i: int in steps:
			pd = walk(s, pd, Vector2(1, 1), dt)
		var d: float = pd.distance_to(start)
		var want: float = SPEED * 0.5
		worst = maxf(worst, absf(d - want))
	rec("walk.diagonal_speed", "diagonal movement on open ground covers 48.0 px in 0.5 s at 30/60/144 Hz (within 0.01)", worst < 0.01, "worst error %.5f px" % worst)
	# 7 frame-rate independence of the path through wall slides and a doorway
	var script_dirs: Array[Vector2] = [Vector2(1, 1), Vector2(1, 0), Vector2(1, -1), Vector2(0, -1), Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(1, 0), Vector2(0, 1)]
	var tracks: Dictionary = {}
	for hz: int in [30, 60, 144]:
		var pt2: Vector2 = Vector2(52.0, 42.3)
		var dt: float = 1.0 / hz
		var samples: Array[Vector2] = []
		var steps_per_half: int = hz / 2
		for seg: int in 24:
			var dir: Vector2 = script_dirs[seg % script_dirs.size()]
			for i: int in steps_per_half:
				pt2 = walk(s, pt2, dir, dt)
			samples.append(pt2)
		tracks[hz] = samples
	var maxdiff: float = 0.0
	for hz: int in [30, 144]:
		for i: int in 24:
			maxdiff = maxf(maxdiff, (tracks[hz][i] as Vector2).distance_to(tracks[60][i]))
	observations["walk_rate_maxdiff"] = maxdiff
	rec("walk.rate_independence", "same scripted input at 30/60/144 Hz gives the same path within 0.25 px at every 0.5 s", maxdiff <= 0.25, "max diff %.4f px; end 30=%s 60=%s 144=%s" % [maxdiff, tracks[30][23], tracks[60][23], tracks[144][23]])
	# Same, with long hitch frames (0.25 s cap) compared against 144 Hz on a wall slide
	var ph: Vector2 = Vector2(60.0, 60.0)
	var pf: Vector2 = Vector2(60.0, 60.0)
	for i: int in 8:
		ph = walk(s, ph, Vector2(1, 1), 0.25)
	for i: int in 288:
		pf = walk(s, pf, Vector2(1, 1), 1.0 / 144.0)
	rec("walk.hitch_vs_fast", "8 hitch frames of 0.25 s end within 0.25 px of 288 frames at 144 Hz (diagonal into a wall)", ph.distance_to(pf) <= 0.25, "hitch=%s fast=%s" % [ph, pf])
	# real map: start, source, fords, building ruin, river
	var w: WorldState = RegionLoader.load_region(region_def)
	var sp: Vector2 = Vector2(region_def.start_tile * T) + Vector2(2, 2)
	rec("walk.start_clear", "the start position is a legal standing place", Walker.is_clear(w, T, sp, HALF) and not foot_hits_block(w, sp), str(sp))
	var src_ok: bool = true
	var src_obs: String = ""
	for tile: Vector2i in region_def.seed_source_tiles:
		var c: Vector2 = (Vector2(tile) + Vector2(0.5, 0.5)) * T
		src_ok = src_ok and w.is_walkable(tile.x, tile.y)
		# every tile whose centre can hold a dropped fruit (10..18 px ring) is walkable
		for dy: int in range(-5, 6):
			for dx: int in range(-5, 6):
				var tc: Vector2 = c + Vector2(dx, dy) * T
				if tc.distance_to(c) <= 18.0 + 2.9 and not w.is_walkable(tile.x + dx, tile.y + dy):
					src_ok = false
					src_obs += " blocked(%d,%d)" % [tile.x + dx, tile.y + dy]
	rec("walk.source_reachable", "the seed source tile and the whole fruit drop ring (up to 18 px + tile) are walkable", src_ok, src_obs)
	# ford crossing with injected-equivalent steps along the first ford row
	var xs: Array[float] = []
	for fy: int in [62, 202, 324, 434]:  # rows inside the four ford bands (60..65, 200..205, 322..327, 432..437)
		var p3: Vector2 = Vector2(0, fy * T + 4.0 + 0.0)  # y = row centre of the band's 2nd row (feet 4 px tall fit in a row band of 24 px)
		# find the west bank start: first walkable x column left of the band from x=225
		p3.x = 225.0 * T + 2.0
		var started: bool = Walker.is_clear(w, T, p3, HALF)
		for i: int in 60 * 6:
			p3 = walk(w, p3, Vector2.RIGHT, 1.0 / 60.0)
		xs.append(p3.x)
		rec("walk.ford_%d" % fy, "walking east along the ford row y-tile %d from x-tile 225 crosses the river (ends beyond x-tile 290)" % fy, started and p3.x > 290.0 * T, "start_clear=%s end=%s" % [started, p3])
	# a non-ford row: stops at the water
	var pr: Vector2 = Vector2(225.0 * T + 2.0, 100.0 * T + 2.0)
	var start_ok: bool = Walker.is_clear(w, T, pr, HALF)
	for i: int in 60 * 6:
		pr = walk(w, pr, Vector2.RIGHT, 1.0 / 60.0)
	# first non-walkable tile on that row to the right of the start
	var first_block: int = -1
	for tx: int in range(225, 512):
		if not w.is_walkable(tx, 100):
			first_block = tx
			break
	rec("walk.river_blocks", "outside the fords the river stops the player at the first water tile on the row", start_ok and first_block > 0 and absf(pr.x - (first_block * T - 3.0)) < 0.01, "stopped=%s first_block_tile=%d" % [pr, first_block])
	# building ruin footprint: tiles (137,176) 21x8
	var pbld: Vector2 = Vector2(130.0 * T, 178.0 * T)
	var clear_start: bool = Walker.is_clear(w, T, pbld, HALF)
	for i: int in 60 * 3:
		pbld = walk(w, pbld, Vector2.RIGHT, 1.0 / 60.0)
	rec("walk.ruin_blocks", "the ruin building (tiles x137.., y176..183) stops the player from the west", clear_start and absf(pbld.x - (137.0 * T - 3.0)) < 0.01, str(pbld))
	# the whole region: bounds
	rec("walk.is_walkable_outside", "is_walkable is false outside the map", not w.is_walkable(-1, 5) and not w.is_walkable(5, -1) and not w.is_walkable(512, 5) and not w.is_walkable(5, 512), "")
	# real map foot-walkable flood vs tile BFS is done in the map section

# ------------------------------------------------------------------------------------------ map

func t_map() -> void:
	var w: WorldState = RegionLoader.load_region(region_def)
	var py: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT + "map_analysis.json"))
	var hexmap: Dictionary = {"wasteland": W_WASTE, "safe": W_SAFE, "shore": W_SHORE, "water": W_WATER, "building": W_BUILD, "shallows": W_SHALLOW}
	var counts: Array[int] = [0, 0, 0, 0, 0, 0]
	for i: int in w.tile_count():
		counts[w.terrain[i]] += 1
	var same: bool = true
	var obs: String = ""
	for k: String in hexmap:
		var want: int = int(py["counts"][k])
		var got: int = counts[hexmap[k]]
		obs += "%s=%d/%d " % [k, got, want]
		if want != got:
			same = false
	rec("map.terrain_counts", "per-terrain tile counts of the loaded world equal my python decode of data/region_01.png", same, obs)
	rec("map.target_count", "target count 244,759 (python: wasteland+safe+shore)", w.target_count == 244759 and int(py["targets"]) == 244759, "%d" % w.target_count)
	# defs: flags per spec
	var flags_ok: bool = true
	var fl: String = ""
	for def: TerrainDef in w.terrain_defs:
		var want_walk: bool = def.key != &"water" and def.key != &"building"
		var want_target: bool = def.key in [&"wasteland", &"safe", &"shore"]
		var want_plant: bool = want_target
		fl += "%s(walk=%s tgt=%s plant=%s side=%s) " % [def.key, def.walkable, def.is_target, def.plantable, def.is_waterside]
		if def.walkable != want_walk or def.is_target != want_target or def.plantable != want_plant:
			flags_ok = false
	rec("map.terrain_flags", "water+building not walkable; shallows walkable but not target/plantable; others walkable targets", flags_ok, fl)
	var sh: TerrainDef = null
	for def: TerrainDef in w.terrain_defs:
		if def.key == &"shallows":
			sh = def
	rec("map.shallows_waterside", "shallows count as waterside (refill possible)", sh != null and sh.is_waterside, "")
	# my own GDScript BFS over world.is_walkable from the start tile (second implementation next to the python one)
	var n: int = w.tile_count()
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(n)
	var q: PackedInt32Array = PackedInt32Array()
	var s0: int = w.index_of(region_def.start_tile.x, region_def.start_tile.y)
	seen[s0] = 1
	q.append(s0)
	var head: int = 0
	while head < q.size():
		var i: int = q[head]
		head += 1
		var x: int = i % w.width
		var y: int = i / w.width
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if w.is_walkable(nx, ny) and seen[ny * w.width + nx] == 0:
				seen[ny * w.width + nx] = 1
				q.append(ny * w.width + nx)
	var reach_t: int = 0
	var unreached_t: int = 0
	for i: int in n:
		if w.target[i] == 1:
			if seen[i] == 1:
				reach_t += 1
			else:
				unreached_t += 1
	rec("map.walk_reach", "targets reachable on foot from the start = 244,202 (python 4-neighbour BFS: %d); unreachable = 557" % int(py["tile_bfs_reach_targets"]), reach_t == 244202 and reach_t == int(py["tile_bfs_reach_targets"]) and unreached_t == 557, "reach=%d unreached=%d" % [reach_t, unreached_t])
	rec("map.python_islands", "python: 8 walk-islands holding 557 tiles", int(py["island_count"]) == 8 and int(py["island_targets_total"]) == 557 and int(py["island_walk_tiles_total"]) == 557, "islands=%d targets=%d" % [int(py["island_count"]), int(py["island_targets_total"])])
	rec("map.python_fords", "python: 4 shallows bands (fords), each crossing the river", (py["shallows_components"] as Array).size() == 4, str(py["shallows_components"]))
	rec("map.python_foot_bfs", "python: a foot-rectangle (6x4) flood reaches the same 244,202 targets as the tile BFS (no 1-tile corridor traps)", int(py["foot_bfs_reach_targets"]) == 244202, "foot=%d" % int(py["foot_bfs_reach_targets"]))
	rec("map.east_bank", "python: 118,520 targets are only reachable across the fords (east bank); 125,682 without crossing", int(py["east_bank_targets_via_fords"]) == 118520 and int(py["no_shallows_reach_targets"]) == 125682, "east=%d west=%d" % [int(py["east_bank_targets_via_fords"]), int(py["no_shallows_reach_targets"])])
	rec("map.start_safe", "start tile is a safe-zone tile and walkable", w.terrain[s0] == W_SAFE and w.is_walkable(region_def.start_tile.x, region_def.start_tile.y), "")
	# initial greening: safe zone only
	rec("map.initial_green", "at start only the 331 safe tiles are mature/greened", w.greened_count == 331 and w.mature_count == 331, "green=%d mature=%d" % [w.greened_count, w.mature_count])
	# Shallows can never be planted / watered
	var all_blocked: bool = true
	var shallows_n: int = 0
	for i: int in n:
		if w.terrain[i] == W_SHALLOW:
			shallows_n += 1
			if w.can_plant(i) or w.target[i] != 0 or w.is_target_tile(i):
				all_blocked = false
	rec("map.shallows_not_plantable", "all 539 shallows tiles are non-target and cannot be planted", all_blocked and shallows_n == 539, "n=%d" % shallows_n)
	# walkable BFS vs safe zone: all safe tiles reachable
	var safe_ok: bool = true
	for i: int in n:
		if w.terrain[i] == W_SAFE and seen[i] == 0:
			safe_ok = false
	rec("map.safe_reachable", "every safe-zone tile is reachable on foot", safe_ok, "")
	# water refill point exists near start side: a shore tile reachable
	var shore_reach: int = 0
	for i: int in n:
		if w.terrain[i] == W_SHORE and seen[i] == 1:
			shore_reach += 1
	rec("map.shore_reachable", "reachable shore tiles exist for water refill", shore_reach > 1000, "%d" % shore_reach)

# ------------------------------------------------------------------------------------------ ground (non-target landing)

func t_ground() -> void:
	var w: WorldState = RegionLoader.load_region(region_def)
	var pt: PlayTuning = load("res://data/play_tuning.tres") as PlayTuning
	var tun: SimTuning = load("res://data/sim_tuning.tres") as SimTuning
	var sources: Array[Vector2] = []
	for tile: Vector2i in region_def.seed_source_tiles:
		sources.append((Vector2(tile) + Vector2(0.5, 0.5)) * T)
	var defs: Array[PlantDef] = []
	defs.assign(region_def.plants)
	var play: PlayState = PlayState.new(w, pt, tun, T, sources, defs)
	var green0: int = w.greened_count
	var stage_hash0: int = hash(w.stage)
	var moist_hash0: int = hash(w.moisture)
	# ford centres (python-listed bands): shallows
	var points: Array[Vector2] = [Vector2(254 * T, 63 * T), Vector2(258 * T, 203 * T), Vector2(265 * T, 325 * T), Vector2(262 * T, 435 * T)]
	var all_shallow: bool = true
	for p: Vector2 in points:
		var tile: Vector2i = Vector2i(floori(p.x / T), floori(p.y / T))
		all_shallow = all_shallow and w.terrain[tile.y * w.width + tile.x] == W_SHALLOW
	rec("ground.ford_points_shallow", "my four test points are on shallows", all_shallow, str(points))
	var planted: int = 0
	for rep: int in 40:
		for p: Vector2 in points:
			planted += play.land_seed(p).size()
	rec("ground.shallows_seed", "160 seeds landing in the middle of the fords plant nothing", planted == 0 and hash(w.stage) == stage_hash0 and w.greened_count == green0, "planted=%d" % planted)
	var wet: int = 0
	for p: Vector2 in points:
		wet += play.land_water(p)
	rec("ground.shallows_water", "water landing on shallows wets nothing (no tile gets moisture)", wet == 0 and hash(w.moisture) == moist_hash0, "wet=%d" % wet)
	# open water and building
	var water_pts: Array[Vector2] = [find_solid(w, W_WATER, 150), find_solid(w, W_WATER, 350)]
	var wcheck: bool = true
	for p: Vector2 in water_pts:
		wcheck = wcheck and p != Vector2.INF
	var bpt: Vector2 = find_solid(w, W_BUILD, 170)
	wcheck = wcheck and bpt != Vector2.INF
	rec("ground.points_ok", "water and building test points really are water / building", wcheck, "")
	for rep: int in 30:
		for p: Vector2 in [water_pts[0], water_pts[1], bpt]:
			play.land_seed(p)
			play.land_water(p)
	rec("ground.water_building", "seeds and water landing in the middle of water and a building change nothing", hash(w.stage) == stage_hash0 and hash(w.moisture) == moist_hash0 and w.greened_count == green0, "")
	# carrots on shallows / water: place refused, seeds not spent
	var seeds0: int = play.seeds
	var carrot: PlantDef = play.def_by_key(&"carrot")
	var placed: CultivatedPlant = null
	for p: Vector2 in points + water_pts + [bpt]:
		play.reserve_plant(carrot)
		var plant: CultivatedPlant = play.land_plant(&"carrot", p)
		if plant != null:
			placed = plant
	rec("ground.cultivated_refused", "carrot landing on shallows/water/building places nothing and keeps all seeds", placed == null and play.seeds == seeds0 and play.reserved_seeds == 0, "seeds=%d/%d reserved=%d" % [play.seeds, seeds0, play.reserved_seeds])
	# natural spread beside a ford does not enter the shallows
	var bank: int = -1
	for y: int in range(58, 68):
		for x: int in range(230, 270):
			if bank < 0 and w.terrain[y * w.width + x] in [W_WASTE, W_SHORE] and w.terrain[y * w.width + x + 1] == W_SHALLOW:
				bank = y * w.width + x
	# a mature tile planted with the real sim next to the ford edge (bank tile is on the west edge of shallows)
	var spread: SpreadSim = SpreadSim.new(w, tun)
	var growth: GrowthSim = GrowthSim.new(w, tun)
	var clock: SimClock = SimClock.new()
	clock.configure(tun)
	clock.growth_ticked.connect(func(_i: int) -> void: growth.tick())
	clock.spread_ticked.connect(func(_i: int) -> void: spread.tick())
	var bank_set: bool = bank >= 0 and w.set_stage(bank, WorldState.STAGE_MATURE)
	for i: int in 600 * 4:
		clock.advance(0.25)
	var bad: int = 0
	var grown: int = 0
	for i: int in w.tile_count():
		if w.terrain[i] in [W_SHALLOW, W_WATER, W_BUILD] and (w.stage[i] != 0 or w.moisture[i] != 0 or w.occupant[i] != 0):
			bad += 1
		if w.stage[i] != 0 and w.terrain[i] in [W_WASTE, W_SHORE]:
			grown += 1
	rec("ground.spread_no_shallows", "600 s of natural spread around a mature tile at the ford edge never touches shallows, water or buildings", bank_set and bad == 0 and grown > 20, "bank=%d bad=%d grown=%d" % [bank, bad, grown])
	rec("ground.counters", "greened counter equals a recount after all this", w.counters_consistent(), "")

# ------------------------------------------------------------------------------------------ fruit

## Centre point (px) of a tile of `terrain_id` whose whole 13 px radius lies on that terrain, searching from row `from_row`.
func find_solid(w: WorldState, terrain_id: int, from_row: int) -> Vector2:
	for y: int in range(from_row, w.height - 5):
		for x: int in range(5, w.width - 5):
			var ok: bool = true
			for dy: int in range(-3, 4):
				for dx: int in range(-3, 4):
					if w.terrain[(y + dy) * w.width + x + dx] != terrain_id:
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector2((x + 0.5) * T, (y + 0.5) * T)
	return Vector2.INF

func make_play(w: WorldState) -> PlayState:
	var pt: PlayTuning = load("res://data/play_tuning.tres") as PlayTuning
	var tun: SimTuning = load("res://data/sim_tuning.tres") as SimTuning
	var sources: Array[Vector2] = []
	for tile: Vector2i in region_def.seed_source_tiles:
		sources.append((Vector2(tile) + Vector2(0.5, 0.5)) * T)
	var defs: Array[PlantDef] = []
	defs.assign(region_def.plants)
	return PlayState.new(w, pt, tun, T, sources, defs)

func count_owner(play: PlayState, plant: bool) -> int:
	var n: int = 0
	for item: Dictionary in play.pickups.items:
		if String(item["kind"]) != GroundPickups.KIND_SEED_FRUIT:
			continue
		if (int(item["owner"]) >= GroundPickups.PLANT_OWNER_BASE) == plant:
			n += 1
	return n

func t_fruit() -> void:
	var w: WorldState = RegionLoader.load_region(region_def)
	var play: PlayState = make_play(w)
	var sp: Vector2 = Vector2(region_def.start_tile * T) + Vector2(2, 2)
	rec("fruit.initial_counts", "331 safe tiles are mature but none produces seed fruit (producing_count 0)", w.mature_count == 331 and w.producing_count == 0, "mature=%d producing=%d" % [w.mature_count, w.producing_count])
	var max_plant_fruit: int = 0
	var max_source_fruit: int = 0
	var t: float = 0.0
	while t < 300.0:
		play.advance(1.0 / 60.0, sp)
		t += 1.0 / 60.0
		max_plant_fruit = maxi(max_plant_fruit, count_owner(play, true))
		max_source_fruit = maxi(max_source_fruit, count_owner(play, false))
	rec("fruit.safe_zone_silent", "5 minutes standing in the safe zone: no plant-owned seed fruit ever lies on the ground", max_plant_fruit == 0, "max plant fruit %d" % max_plant_fruit)
	rec("fruit.source_still_gives", "the seed source still drops fruits (at most its cap of 3 on the ground)", max_source_fruit > 0 and max_source_fruit <= 3, "max source fruit %d" % max_source_fruit)
	# regrown tile: clear a safe tile, plant (seed), run the real growth to maturity, producer works
	var idx: int = -1
	for i: int in w.tile_count():
		if w.terrain[i] == W_SAFE:
			idx = i
			break
	w.set_stage(idx, WorldState.STAGE_EMPTY)
	rec("fruit.cleared_not_counted", "clearing a safe tile lowers mature_count by one and leaves producing_count at 0", w.mature_count == 330 and w.producing_count == 0, "%d/%d" % [w.mature_count, w.producing_count])
	var tun: SimTuning = load("res://data/sim_tuning.tres") as SimTuning
	var growth: GrowthSim = GrowthSim.new(w, tun)
	var clock: SimClock = SimClock.new()
	clock.configure(tun)
	clock.growth_ticked.connect(func(_i: int) -> void: growth.tick())
	var tx: int = idx % w.width
	var ty: int = idx / w.width
	var center: Vector2 = Vector2((tx + 0.5) * T, (ty + 0.5) * T)
	var seeded: PackedInt32Array = play.land_seed(center)
	rec("fruit.reseed_possible", "a landed seed can be planted again on the cleared safe tile (the seed scatter finds free tiles)", seeded.size() >= 1, "planted %d" % seeded.size())
	for i: int in 4 * 130:
		clock.advance(0.25)
		play.advance(0.25, center)
	var mature_now: bool = w.stage[idx] == WorldState.STAGE_MATURE
	# every tile planted by that landing is regular growth; count producing tiles
	rec("fruit.regrown_counts", "the replanted tiles matured by themselves (dry, 60 s) and now count as producing", w.producing_count >= 1 and w.producing_count == w.mature_count - 330, "mature=%d producing=%d tile_mature=%s" % [w.mature_count, w.producing_count, mature_now])
	var producing_tiles: int = w.producing_count
	# the tile that regrew produces fruit
	play.pickups.items.clear()
	var found: int = 0
	var t2: float = 0.0
	var away: Vector2 = center + Vector2(70, 0)  # inside the 160 px production radius, outside the 12 px pickup radius
	while t2 < 600.0 and found == 0:
		play.advance(0.25, away)
		t2 += 0.25
		found = count_owner(play, true)
	rec("fruit.regrown_produces", "within 10 minutes a regrown mature tile drops a plant seed fruit", found > 0, "fruit=%d after %.0f s, producing tiles %d" % [found, t2, producing_tiles])
	# persistence round trip (JSON like a real save), fresh region
	var w2: WorldState = RegionLoader.load_region(region_def)
	var data: Dictionary = w2.to_dict()
	var text: String = JSON.stringify(data)
	var back: WorldState = WorldState.from_dict(JSON.parse_string(text), w2.terrain_defs)
	rec("fruit.save_roundtrip", "save/load keeps the fruitless flags: still 331 mature and 0 producing", back != null and back.mature_count == 331 and back.producing_count == 0 and back.fruitless == w2.fruitless, "mature=%d producing=%d" % [back.mature_count, back.producing_count])
	# a modified world: regrown tile producing survives the roundtrip, safe tiles stay fruitless
	w.rebuild_derived()
	var data3: Dictionary = w.to_dict()
	var back3: WorldState = WorldState.from_dict(JSON.parse_string(JSON.stringify(data3)), w.terrain_defs)
	rec("fruit.save_roundtrip_regrown", "a world with regrown producing tiles keeps producing_count after JSON save/load", back3 != null and back3.producing_count == w.producing_count and back3.mature_count == w.mature_count and back3.fruitless == w.fruitless, "producing %d -> %d mature %d -> %d" % [w.producing_count, back3.producing_count, w.mature_count, back3.mature_count])
	# producing counters vs a recount
	var rc_mature: int = 0
	var rc_prod: int = 0
	for i: int in w.tile_count():
		if w.stage[i] == WorldState.STAGE_MATURE:
			rc_mature += 1
			if w.fruitless[i] == 0:
				rc_prod += 1
	var chunk_sum: int = 0
	for c: int in w.producing_chunk_count:
		chunk_sum += c
	rec("fruit.counters", "producing counters (total and per chunk) equal a recount", rc_prod == w.producing_count and chunk_sum == rc_prod and rc_mature == w.mature_count, "recount mature %d producing %d chunk sum %d" % [rc_mature, rc_prod, chunk_sum])
	# save of a world where a new natural growth near safe zone: spread into new tiles produce fruit
	# gather() ignores fruitless tiles
	var w4: WorldState = RegionLoader.load_region(region_def)
	var play4: PlayState = make_play(w4)
	var g: int = play4.producer.gather(sp, 160.0)
	rec("fruit.gather_zero", "PlantProducer.gather around the start finds 0 producing tiles (331 mature but fruitless)", g == 0, "gather=%d" % g)
