extends SceneTree
## Independent verifier for P1-02 (headless, real main.tscn, engine-internal input injection only).
## Run: Godot --headless --fixed-fps 60 --path <project> --script res://tests/p1/independent/p1_02_v_checks.gd
## Expectations are derived from the spec (tasks/P1_02.md, AUTO_001.md) and brute-force scans of the real map,
## not from the implementation's formulas.

const OUT: String = "res://evidence/p1/p1-02/independent/"
const TILE: int = 4

var results: Array[Dictionary] = []
var main: Node
var observations: Dictionary = {}
var keys_down: Dictionary = {}
var landed_n: int = 0

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func run() -> void:
	var only: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	if only == "7":
		await t7_pause()
		print("ONLY7 done")
		for r: Dictionary in results:
			if r["status"] != "PASS":
				print("FAIL present")
		var f7: FileAccess = FileAccess.open(OUT + "checks_pause_realtime.json", FileAccess.WRITE)
		f7.store_string(JSON.stringify(results, "  "))
		f7.close()
		quit(0)
		return
	await t1_resources()
	await t2_scatter()
	await t3_non_target()
	await t45_recovery_and_refill()
	await t6_source()
	await t7_pause()
	await t8_hud()
	await t9_save()
	var f: FileAccess = FileAccess.open(OUT + "checks_headless.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"results": results, "observations": observations}, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("V_RESULT total=%d fails=%d" % [results.size(), fails])
	quit(1 if fails > 0 else 0)

# ---------------------------------------------------------------------------------------------- helpers

func new_main() -> Node:
	if main != null:
		main.queue_free()
		await process_frame
	paused = false
	keys_down.clear()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	landed_n = 0
	main.projectile_view.landed.connect(func(_k: String, _p: Vector2) -> void: landed_n += 1)
	return main

func place_player(p: Vector2) -> void:
	main.player.simulation_position = p
	main.player.position = p.round()
	await process_frame
	await process_frame

func ticks(n: int) -> void:
	for i: int in n:
		await physics_frame

func drain_shots(limit: int = 400) -> void:
	var n: int = 0
	while not main.projectile_view.shots.is_empty() and n < limit:
		await physics_frame
		n += 1

func screen_of(world_pos: Vector2) -> Vector2:
	return main.get_viewport().get_canvas_transform() * world_pos

func inject_motion(world_pos: Vector2) -> void:
	var m: InputEventMouseMotion = InputEventMouseMotion.new()
	m.position = screen_of(world_pos)
	m.global_position = m.position
	Input.parse_input_event(m)

func click(button: MouseButton, world_pos: Vector2) -> void:
	inject_motion(world_pos)
	var d: InputEventMouseButton = InputEventMouseButton.new()
	d.button_index = button
	d.pressed = true
	d.position = screen_of(world_pos)
	d.global_position = d.position
	Input.parse_input_event(d)
	var u: InputEventMouseButton = InputEventMouseButton.new()
	u.button_index = button
	u.pressed = false
	u.position = d.position
	u.global_position = d.position
	Input.parse_input_event(u)

## Click then let the event pass through two frames (headless input is flushed at frame start).
func click_wait(button: MouseButton, world_pos: Vector2) -> void:
	click(button, world_pos)
	await process_frame
	await process_frame

func launches() -> int:
	return main.projectile_view.shots.size() + landed_n

func key(code: Key, down: bool) -> void:
	if bool(keys_down.get(code, false)) == down:
		return
	keys_down[code] = down
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)

func release_all() -> void:
	for code: Key in [KEY_A, KEY_D, KEY_W, KEY_S]:
		key(code, false)

func tap_escape() -> void:
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = KEY_ESCAPE
	e.keycode = KEY_ESCAPE
	e.pressed = true
	Input.parse_input_event(e)
	var u: InputEventKey = InputEventKey.new()
	u.physical_keycode = KEY_ESCAPE
	u.keycode = KEY_ESCAPE
	u.pressed = false
	Input.parse_input_event(u)

## Walks with injected WASD key events until within `tol` px. Returns frames used.
func walk_to(target: Vector2, max_frames: int, tol: float = 2.0, on_tick: Callable = Callable()) -> int:
	var n: int = 0
	while n < max_frames:
		var delta: Vector2 = target - main.player.simulation_position
		if delta.length() <= tol:
			break
		key(KEY_D, delta.x > tol)
		key(KEY_A, delta.x < -tol)
		key(KEY_S, delta.y > tol)
		key(KEY_W, delta.y < -tol)
		await physics_frame
		if on_tick.is_valid():
			on_tick.call()
		n += 1
	release_all()
	await physics_frame
	return n

func tile_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))

func center_of(t: Vector2i) -> Vector2:
	return (Vector2(t) + Vector2(0.5, 0.5)) * TILE

## Independent: smallest Euclidean tile distance from tile t to any waterside (water/shore) tile within `reach`.
func near_dist(world: WorldState, defs: Array, t: Vector2i, reach: int) -> float:
	var best: float = INF
	for dy: int in range(-reach, reach + 1):
		for dx: int in range(-reach, reach + 1):
			var x: int = t.x + dx
			var y: int = t.y + dy
			if x < 0 or y < 0 or x >= world.width or y >= world.height:
				continue
			if defs[world.terrain[y * world.width + x]].is_waterside:
				best = minf(best, sqrt(float(dx * dx + dy * dy)))
	return best

func square_all(world: WorldState, cx: int, cy: int, half: int, terrain_id: int) -> bool:
	if cx - half < 0 or cy - half < 0 or cx + half >= world.width or cy + half >= world.height:
		return false
	for y: int in range(cy - half, cy + half + 1):
		for x: int in range(cx - half, cx + half + 1):
			if world.terrain[y * world.width + x] != terrain_id:
				return false
	return true

## Nearest (to `near`) tile whose (2*half+1)^2 square is all one terrain id.
func find_square(world: WorldState, terrain_id: int, half: int, near: Vector2i) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 1 << 60
	for cy: int in range(half, world.height - half, 2):
		for cx: int in range(half, world.width - half, 2):
			var d: int = (cx - near.x) * (cx - near.x) + (cy - near.y) * (cy - near.y)
			if d >= best_d:
				continue
			if square_all(world, cx, cy, half, terrain_id):
				best = Vector2i(cx, cy)
				best_d = d
	return best

func stage_snapshot(world: WorldState) -> PackedByteArray:
	return world.stage.duplicate()

func nontarget_dirty(world: WorldState) -> int:
	var bad: int = 0
	for i: int in world.tile_count():
		if world.target[i] == 0 and (world.stage[i] != 0 or world.plant_id[i] != 0 or world.growth[i] != 0):
			bad += 1
	return bad

# ---------------------------------------------------------------------------------------------- 1 resources

func t1_resources() -> void:
	await new_main()
	var play: PlayState = main.play
	var world: WorldState = main.grid
	var defs: Array = main.region_def.terrains
	var site: Vector2i = find_square(world, 0, 6, main.region_def.start_tile)
	observations["wasteland_site"] = str(site)
	await place_player(center_of(site))
	rec("1.init", "initial seeds 20 (cap 40), water 100 (cap 100), not refilling at wasteland site", play.seeds == 20 and play.tuning.seed_max == 40 and is_equal_approx(play.water, 100.0) and not play.refilling, "seeds=%d/%d water=%s site=%s" % [play.seeds, play.tuning.seed_max, play.water, site])
	var aim: Vector2 = center_of(site) + Vector2(50, 0)
	inject_motion(aim)
	await process_frame
	var mouse_world: Vector2 = main.player.get_global_mouse_position()
	rec("1.aim_inject", "injected mouse motion moves the world mouse point to the aimed world position (headless)", mouse_world.distance_to(aim) < 1.5, "aim=%s mouse_world=%s" % [aim, mouse_world])
	# 20 injected left clicks
	var seq: PackedInt32Array = PackedInt32Array()
	var min_seeds: int = 99
	var shots_before: int = launches()
	for i: int in 20:
		await click_wait(MOUSE_BUTTON_LEFT, aim)
		seq.append(play.seeds)
		min_seeds = mini(min_seeds, play.seeds)
	var expect: PackedInt32Array = PackedInt32Array()
	for i: int in 20:
		expect.append(19 - i)
	var shots_after: int = launches()
	rec("1.seed_spend", "each injected left click spends exactly 1 seed (20 -> 0) and launches one shot", seq == expect and shots_after - shots_before == 20, "seq=%s shots+=%d" % [str(seq), shots_after - shots_before])
	var lc: int = play.landing_counter
	var sh: int = launches()
	for i: int in 5:
		await click_wait(MOUSE_BUTTON_LEFT, aim)
	rec("1.seed_empty", "with 0 seeds a click fires nothing and spends nothing (launch count unchanged, seeds stay 0)", play.seeds == 0 and launches() == sh and not main.fire(false), "seeds=%d launches=%d->%d" % [play.seeds, sh, launches()])
	await drain_shots()
	rec("1.seed_landed_all", "all 20 shots landed (landing_counter == 20), shots list empty", play.landing_counter == 20 and main.projectile_view.shots.is_empty(), "landing_counter %d (before drain %d)" % [play.landing_counter, lc])
	# water
	var wseq: Array = []
	var w0: float = play.water
	for i: int in 10:
		await click_wait(MOUSE_BUTTON_RIGHT, aim)
		wseq.append(play.water)
	var wok: bool = true
	for i: int in 10:
		if absf(float(wseq[i]) - (100.0 - 10.0 * (i + 1))) > 0.001:
			wok = false
	rec("1.water_spend", "each right click spends 10 of 100 water: 90,80,...,0", wok and w0 == 100.0, "seq=%s" % str(wseq))
	sh = launches()
	for i: int in 3:
		await click_wait(MOUSE_BUTTON_RIGHT, aim)
	rec("1.water_empty", "with 0 water a right click fires nothing and spends nothing", play.water == 0.0 and launches() == sh, "water=%s launches=%d" % [play.water, launches()])
	await drain_shots()
	# partial gauge
	play.water = 9.5
	sh = launches()
	var fired_low: bool = main.fire(true, aim)
	rec("1.water_partial_refused", "water 9.5 (< cost 10): not fired, gauge unchanged at 9.5", (not fired_low) and play.water == 9.5 and launches() == sh, "fired=%s water=%s" % [fired_low, play.water])
	play.water = 10.0
	var fired_ok: bool = main.fire(true, aim)
	rec("1.water_exact_cost", "water exactly 10 can fire once and ends at 0 (not negative)", fired_ok and play.water == 0.0, "fired=%s water=%s" % [fired_ok, play.water])
	await drain_shots()
	# caps and negatives
	play.seeds = 0
	var added: int = play.add_seeds(100)
	var neg: int = play.add_seeds(-5)
	var aw: float = play.add_water(1000.0)
	var nw: float = play.add_water(-5.0)
	rec("1.caps", "add_seeds(100) stops at 40, add_water(1000) at 100, negative additions are ignored", play.seeds == 40 and added == 40 and neg == 0 and play.water == 100.0 and aw == 100.0 and nw == 0.0, "seeds=%d added=%d neg=%d water=%s aw=%s nw=%s" % [play.seeds, added, neg, play.water, aw, nw])
	var spent_false: bool = true
	play.seeds = 0
	play.water = 0.0
	spent_false = (not play.spend_seed()) and (not play.spend_water()) and play.seeds == 0 and play.water == 0.0
	rec("1.no_negative", "spend_seed/spend_water at zero return false and never go negative", spent_false and min_seeds >= 0, "seeds=%d water=%s min_seeds_seen=%d" % [play.seeds, play.water, min_seeds])
	# range: far aim lands at 120 px
	play.seeds = 5
	var far_aim: Vector2 = center_of(site) + Vector2(400, 0)
	var origin: Vector2 = main.player.simulation_position
	main.fire(false, far_aim)
	var shot: Dictionary = main.projectile_view.shots[main.projectile_view.shots.size() - 1]
	var tgt: Vector2 = shot["target"]
	rec("1.range", "aiming 400 px away lands at the 120 px range along the aim direction", absf(tgt.distance_to(origin) - 120.0) < 0.01 and absf(tgt.y - origin.y) < 0.01, "target=%s origin=%s dist=%s" % [tgt, origin, tgt.distance_to(origin)])
	await drain_shots()

# ---------------------------------------------------------------------------------------------- 2 scatter

func disk_tiles(world: WorldState, p: Vector2, r: float) -> Array:
	var out: Array = []
	for y: int in range(maxi(0, floori(p.y / TILE) - 6), mini(world.height, floori(p.y / TILE) + 7)):
		for x: int in range(maxi(0, floori(p.x / TILE) - 6), mini(world.width, floori(p.x / TILE) + 7)):
			if center_of(Vector2i(x, y)).distance_to(p) <= r:
				out.append(y * world.width + x)
	return out

func t2_scatter() -> void:
	await new_main()
	var play: PlayState = main.play
	var world: WorldState = main.grid
	var site: Vector2i = find_square(world, 0, 6, main.region_def.start_tile)
	var base: Vector2 = center_of(site)
	var greened0: int = world.greened_count
	var bad_radius: int = 0
	var bad_prestate: int = 0
	var bad_count: int = 0
	var bad_outside_change: int = 0
	var lands: int = 0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var all_placed: Dictionary = {}
	var max_placed: int = 0
	for n: int in 40:
		var p: Vector2 = base + Vector2(rng.randf_range(-12, 12), rng.randf_range(-12, 12))
		var before: PackedByteArray = stage_snapshot(world)
		var prefree: Dictionary = {}
		for idx: int in disk_tiles(world, p, 10.0):
			if world.target[idx] == 1 and world.stage[idx] == 0 and world.occupant[idx] == 0:
				prefree[idx] = true
		var placed: PackedInt32Array = play.land_seed(p)
		lands += 1
		max_placed = maxi(max_placed, placed.size())
		if placed.size() > 6 or placed.size() != mini(6, prefree.size()):
			bad_count += 1
		for idx: int in placed:
			if not prefree.has(idx):
				bad_prestate += 1
			if center_of(Vector2i(idx % world.width, idx / world.width)).distance_to(p) > 10.0 + 0.0001:
				bad_radius += 1
			all_placed[idx] = true
		# nothing else in the 25x25 neighbourhood changed
		var pset: Dictionary = {}
		for idx: int in placed:
			pset[idx] = true
		var t0: Vector2i = tile_of(p)
		for y: int in range(t0.y - 12, t0.y + 13):
			for x: int in range(t0.x - 12, t0.x + 13):
				var i2: int = y * world.width + x
				if world.stage[i2] != before[i2] and not pset.has(i2):
					bad_outside_change += 1
	rec("2.scatter_count", "each landing places min(6, free tiles in radius) seeds, never more than 6", bad_count == 0, "landings=%d max_placed=%d bad=%d" % [lands, max_placed, bad_count])
	rec("2.scatter_free_only", "placed tiles were free/target/unoccupied/no plant before", bad_prestate == 0, "bad=%d" % bad_prestate)
	rec("2.scatter_radius", "every placed tile centre lies within 10 px of the landing point (independent geometry)", bad_radius == 0, "bad=%d" % bad_radius)
	rec("2.scatter_no_other_change", "no tile outside the placed set changes stage (25x25 neighbourhood)", bad_outside_change == 0, "bad=%d" % bad_outside_change)
	var seed_tiles: int = 0
	for i: int in world.tile_count():
		if world.stage[i] == 1:
			seed_tiles += 1
	rec("2.seed_not_greened", "seed stage alone does not change greened_count; counter equals recount", world.greened_count == greened0 and world.recount_greened() == world.greened_count and world.counters_consistent(), "greened %d -> %d seed_tiles=%d placed_unique=%d recount=%d" % [greened0, world.greened_count, seed_tiles, all_placed.size(), world.recount_greened()])
	# time passes (simulation driver ticks) - seeds alone must not grow in P1-02
	await ticks(120)
	rec("2.seed_no_growth", "120 ticks later seeds are still seeds and greened_count unchanged", world.greened_count == greened0 and world.recount_greened() == greened0, "greened=%d" % world.greened_count)
	# exhaustion at one point
	var q: Vector2 = base + Vector2(40, 0)
	var counts: Array = []
	var disk: Array = disk_tiles(world, q, 10.0)
	for n: int in 6:
		counts.append(play.land_seed(q).size())
	var all_seeds: bool = true
	for idx: int in disk:
		if world.stage[idx] != 1:
			all_seeds = false
	var sum: int = 0
	for c: int in counts:
		sum += c
	rec("2.exhaust", "repeated landings never re-seed a seeded tile: totals equal disk size, then zero", sum == disk.size() and all_seeds and counts[counts.size() - 1] == 0, "counts=%s disk=%d" % [str(counts), disk.size()])
	# existing plants and occupancy are untouched
	var r0: Vector2 = base + Vector2(-40, 20)
	var rt: Vector2i = tile_of(r0)
	world.set_stage(rt.y * world.width + rt.x, 2)
	world.set_stage(rt.y * world.width + rt.x + 1, 3)
	world.set_stage((rt.y + 1) * world.width + rt.x, 4)
	var occ_ok: bool = world.occupy(Rect2i(rt.x - 1, rt.y - 1, 2, 2), 77)
	var gcount: int = world.greened_count
	var snap_stage: Array = []
	for d: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		snap_stage.append(world.stage[(rt.y + d.y) * world.width + rt.x + d.x])
	for n: int in 10:
		play.land_seed(r0)
	var snap2: Array = []
	for d: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		snap2.append(world.stage[(rt.y + d.y) * world.width + rt.x + d.x])
	var occ_clean: bool = true
	for y: int in range(rt.y - 1, rt.y + 1):
		for x: int in range(rt.x - 1, rt.x + 1):
			if world.stage[y * world.width + x] == 1 and world.occupant[y * world.width + x] == 77:
				occ_clean = false
	rec("2.existing_plant_occupied", "tiles with sprout/mature plants keep their stage; occupied tiles never get seeds; greened unchanged", occ_ok and snap_stage == snap2 and occ_clean and world.greened_count == gcount and world.counters_consistent(), "stages %s -> %s occupied_ok=%s occ_clean=%s greened %d->%d" % [str(snap_stage), str(snap2), occ_ok, occ_clean, gcount, world.greened_count])
	# fixed seed reproducibility on two independent worlds
	var def: RegionDef = main.region_def
	var runs: Array = []
	for r: int in 2:
		var w2: WorldState = RegionLoader.load_region(def)
		var p2: PlayState = PlayState.new(w2, load("res://data/play_tuning.tres"), main.tuning, TILE, [] as Array[Vector2])
		var seq: Array = []
		for n: int in 12:
			var pt: Vector2 = base + Vector2((n % 4) * 6 - 9, (n / 4) * 6 - 6)
			seq.append(Array(p2.land_seed(pt)))
		runs.append(seq)
	rec("2.reproducible", "same map + same landing sequence + same fixed seed gives identical placements", str(runs[0]) == str(runs[1]) and str(runs[0]).length() > 20, "len=%d" % str(runs[0]).length())
	var alt: PlayTuning = (load("res://data/play_tuning.tres") as PlayTuning).duplicate() as PlayTuning
	alt.scatter_seed = 12345
	var w3: WorldState = RegionLoader.load_region(def)
	var p3: PlayState = PlayState.new(w3, alt, main.tuning, TILE, [] as Array[Vector2])
	var seq3: Array = []
	for n: int in 12:
		var pt3: Vector2 = base + Vector2((n % 4) * 6 - 9, (n / 4) * 6 - 6)
		seq3.append(Array(p3.land_seed(pt3)))
	rec("2.seed_matters", "a different scatter_seed changes the placements (the sequence is really seeded)", str(seq3) != str(runs[0]), "differs=%s" % (str(seq3) != str(runs[0])))
	# out-of-map landing points must be harmless
	var w5: WorldState = RegionLoader.load_region(def)
	var p5: PlayState = PlayState.new(w5, load("res://data/play_tuning.tres"), main.tuning, TILE, [] as Array[Vector2])
	var oob_total: int = 0
	for q5: Vector2 in [Vector2(-100, -100), Vector2(5000, 5000), Vector2(-3, 2000), Vector2(2047.9, -1.0), Vector2(0, 0), Vector2(2047, 2047)]:
		oob_total += p5.land_seed(q5).size() + p5.land_water(q5)
		for idx: int in p5.last_scatter:
			if w5.target[idx] == 0:
				oob_total += 1000
	rec("2.out_of_map", "landing points outside / on the corners of the map do not crash and only touch in-map target tiles", w5.counters_consistent() and oob_total < 1000 and nontarget_dirty(w5) == 0, "touched=%d" % oob_total)
	# water splash on target tiles
	var w4: WorldState = RegionLoader.load_region(def)
	var p4: PlayState = PlayState.new(w4, load("res://data/play_tuning.tres"), main.tuning, TILE, [] as Array[Vector2])
	var before_m: PackedByteArray = w4.moisture.duplicate()
	var changed: int = p4.land_water(base)
	var disk_w: Array = disk_tiles(w4, base, 12.0)
	var dm_ok: bool = true
	for idx: int in disk_w:
		if int(w4.moisture[idx]) != mini(int(before_m[idx]) + 40, 100):
			dm_ok = false
	var outside_m: int = 0
	for i: int in w4.tile_count():
		if w4.moisture[i] != before_m[i] and not (i in disk_w):
			outside_m += 1
	p4.land_water(base)
	p4.land_water(base)
	var capped: bool = true
	for idx: int in disk_w:
		if int(w4.moisture[idx]) != 100:
			capped = false
	rec("2.water_splash", "water adds +40 moisture to target tiles within 12 px (cap 100), nothing outside; 3 splashes cap at 100", dm_ok and outside_m == 0 and capped and changed == disk_w.size(), "changed=%d disk=%d outside=%d capped=%s" % [changed, disk_w.size(), outside_m, capped])

# ---------------------------------------------------------------------------------------------- 3 non-target

func t3_non_target() -> void:
	await new_main()
	var play: PlayState = main.play
	var world: WorldState = main.grid
	var defs: Array = main.region_def.terrains
	var water_half: int = 5
	var wc: Vector2i = find_square(world, 3, water_half, main.region_def.start_tile)
	while wc.x < 0 and water_half > 3:
		water_half -= 1
		wc = find_square(world, 3, water_half, main.region_def.start_tile)
	var bh: int = 4
	var bc: Vector2i = find_square(world, 4, bh, main.region_def.start_tile)
	while bc.x < 0 and bh > 1:
		bh -= 1
		bc = find_square(world, 4, bh, main.region_def.start_tile)
	observations["water_square"] = "center=%s half=%d" % [wc, water_half]
	observations["building_square"] = "center=%s half=%d" % [bc, bh]
	rec("3.sites", "real map has a water interior (>= 7x7) and a building interior (>= 3x3) to aim at", wc.x >= 0 and water_half >= 3 and bc.x >= 0 and bh >= 1, "water=%s half=%d building=%s half=%d" % [wc, water_half, bc, bh])
	var greened0: int = world.greened_count
	var targets0: int = world.target_count
	var stage0: PackedByteArray = stage_snapshot(world)
	var moist0: PackedByteArray = world.moisture.duplicate()
	var seeds_spent: int = 0
	var water_spent: int = 0
	for site: Vector2i in [wc, bc]:
		var tgt: Vector2 = center_of(site)
		for ang: int in [0, 90, 180, 270]:
			var pl: Vector2 = tgt + Vector2.RIGHT.rotated(deg_to_rad(ang)) * 60.0
			main.player.simulation_position = pl
			for k: int in 25:
				play.seeds = play.tuning.seed_max
				play.water = 100.0
				if main.fire(false, tgt):
					seeds_spent += 1
				if main.fire(true, tgt):
					water_spent += 1
				await physics_frame
			await drain_shots()
	var seed_zone_changed: int = 0
	for i: int in world.tile_count():
		if world.stage[i] != stage0[i] or world.moisture[i] != moist0[i]:
			seed_zone_changed += 1
	rec("3.centre_shots", "%d seed + %d water shots at water/building centres: no tile anywhere changed stage or moisture; greened/target counters unchanged" % [seeds_spent, water_spent], seed_zone_changed == 0 and world.greened_count == greened0 and world.target_count == targets0 and world.counters_consistent() and nontarget_dirty(world) == 0 and seeds_spent >= 200, "changed_tiles=%d greened %d->%d seeds_spent=%d water_spent=%d" % [seed_zone_changed, greened0, world.greened_count, seeds_spent, water_spent])
	# injected click version, only when the aim point is not covered by a UI panel
	var tgt2: Vector2 = center_of(wc)
	main.player.simulation_position = tgt2 + Vector2(-50, 0)
	main.player.position = main.player.simulation_position.round()
	await process_frame
	await process_frame
	var sp: Vector2 = screen_of(tgt2)
	var seeds_before: int = play.seeds
	play.seeds = 10
	for i: int in 10:
		click(MOUSE_BUTTON_LEFT, tgt2)
		await process_frame
	await drain_shots()
	rec("3.centre_clicks", "10 injected clicks aimed at the water centre (screen %s): seeds spent, no tile changed" % sp, play.seeds == 0 and world.greened_count == greened0 and nontarget_dirty(world) == 0, "seeds=%d greened=%d" % [play.seeds, world.greened_count])
	# edge observation: water/building tile adjacent to target land
	var edge_obs: Array = []
	var edge_ok: bool = true
	var found: int = 0
	for y: int in range(80, 440, 3):
		for x: int in range(80, 440, 3):
			var i: int = y * world.width + x
			if world.target[i] == 0 and found < 6:
				var near_target: int = 0
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if world.target[(y + d.y) * world.width + x + d.x] == 1:
						near_target += 1
				if near_target >= 1 and square_all_nontarget_ratio(world, x, y) > 0.4:
					found += 1
					var p: Vector2 = center_of(Vector2i(x, y))
					var w2: WorldState = RegionLoader.load_region(main.region_def)
					var p2: PlayState = PlayState.new(w2, load("res://data/play_tuning.tres"), main.tuning, TILE, [] as Array[Vector2])
					var placed: PackedInt32Array = p2.land_seed(p)
					var inside: bool = true
					for idx: int in placed:
						if w2.target[idx] == 0 or center_of(Vector2i(idx % w2.width, idx / w2.width)).distance_to(p) > 10.0001:
							inside = false
					var tt: String = defs[world.terrain[i]].key
					edge_ok = edge_ok and inside and w2.greened_count == w2.recount_greened() and w2.greened_count == world.greened_count
					edge_obs.append("%s(%d,%d): placed=%d all_target_in_radius=%s greened=%d" % [tt, x, y, placed.size(), inside, w2.greened_count])
	observations["edge_landings"] = edge_obs
	rec("3.edge_observation", "OBSERVED: landing on a non-target tile next to target land still seeds the target tiles inside the 10 px radius (allowed by spec); never non-target, never greened", edge_ok and found > 0, "; ".join(edge_obs))

func square_all_nontarget_ratio(world: WorldState, x: int, y: int) -> float:
	var n: int = 0
	var t: int = 0
	for dy: int in range(-2, 3):
		for dx: int in range(-2, 3):
			t += 1
			if world.target[(y + dy) * world.width + x + dx] == 0:
				n += 1
	return float(n) / float(t)

# ---------------------------------------------------------------------------------------------- 4 + 5 recovery, refill

func t45_recovery_and_refill() -> void:
	await new_main()
	var play: PlayState = main.play
	var world: WorldState = main.grid
	var defs: Array = main.region_def.terrains
	# --- 5. distance rule at brute-force chosen positions
	var cats: Dictionary = {}  # exact distance key -> tile
	var want: Array = [1.0, 2.0, 2.236, 3.0]
	var scan_n: int = 0
	for y: int in range(60, 460):
		for x: int in range(60, 460):
			var t: int = world.terrain[y * world.width + x]
			if t == 2 or t == 3:
				scan_n += 1
				for off: Vector2i in [Vector2i(-1, 0), Vector2i(-2, 0), Vector2i(-2, 1), Vector2i(-3, 0)]:
					var p: Vector2i = Vector2i(x, y) + off
					if p.x < 8 or p.y < 8 or world.terrain[p.y * world.width + p.x] == 3 or world.terrain[p.y * world.width + p.x] == 2:
						continue
					var d: float = near_dist(world, defs, p, 4)
					for w: float in want:
						if absf(d - w) < 0.01 and not cats.has(w):
							cats[w] = p
		if cats.size() == want.size():
			break
	rec("5.sites", "found map positions whose nearest waterside tile is exactly 1, 2, sqrt5, 3 tiles away (brute force)", cats.size() == want.size(), str(cats))
	var refill_obs: Array = []
	var dist_ok: bool = true
	for w: float in want:
		if not cats.has(w):
			continue
		var p: Vector2i = cats[w]
		play.water = 0.0
		await place_player(center_of(p))
		var t0: float = play.water
		var e0: float = play.elapsed
		await ticks(60)
		var gain: float = play.water - t0
		var secs: float = play.elapsed - e0
		var should: bool = w <= 2.0
		var rate: float = gain / secs if secs > 0.0 else 0.0
		var ok: bool = (should and absf(rate - 25.0) < 1.0) or ((not should) and gain == 0.0)
		dist_ok = dist_ok and ok
		refill_obs.append("dist=%.3f tile=%s gain=%.2f over %.3fs rate=%.2f expect_refill=%s" % [w, p, gain, secs, rate, should])
	rec("5.distance_rule", "water refills at ~25/s only when the nearest waterside tile is within 2 tiles (1, 2 refill; sqrt5, 3 do not)", dist_ok and refill_obs.size() == 4, " | ".join(refill_obs))
	play.water = 95.0
	await place_player(center_of(cats[1.0]))
	await ticks(60)
	rec("5.refill_cap", "refill stops at the 100 cap", play.water == 100.0, "water=%s" % play.water)
	# --- 4a. seed recovery from the source, real scene + injected input
	await new_main()
	play = main.play
	world = main.grid
	var site: Vector2i = find_square(world, 0, 6, main.region_def.start_tile)
	await place_player(center_of(site))
	var aim: Vector2 = center_of(site) + Vector2(40, 0)
	for i: int in 20:
		click(MOUSE_BUTTON_LEFT, aim)
		await process_frame
	await drain_shots()
	var seeds_zero: bool = play.seeds == 0
	click(MOUSE_BUTTON_LEFT, aim)
	await process_frame
	var still_zero: bool = play.seeds == 0 and main.projectile_view.shots.is_empty()
	rec("4.seed_zero", "after 20 clicks seeds are 0 and a further click does nothing", seeds_zero and still_zero, "seeds=%d shots=%d" % [play.seeds, main.projectile_view.shots.size()])
	var src: SeedSource = play.sources[0]
	# wait (real physics ticks) until a fruit exists; player kept far away at the site
	var waited: int = 0
	while play.pickups.count() == 0 and waited < 2000:
		await physics_frame
		waited += 1
	rec("4.fruit_appears", "the source drops its first fruit by ~8 s of game time without any player action", play.pickups.count() >= 1 and waited >= 440 and waited <= 560, "ticks waited=%d (since scene start+setup) fruits=%d" % [waited, play.pickups.count()])
	var item: Dictionary = play.pickups.items[0]
	var fpos: Vector2 = Vector2(float(item["x"]), float(item["y"]))
	# start 70 px from the fruit and walk with injected keys
	main.player.simulation_position = fpos + Vector2(-70, 30)
	await process_frame
	var used: int = await walk_to(fpos, 400, 1.0, func() -> void:
		if play.seeds > 0:
			release_all())
	for i: int in 10:
		await physics_frame
	rec("4.seed_recovered", "walking (injected WASD) to the fruit collects it: seeds 0 -> 1, fruit gone", play.seeds >= 1, "seeds=%d frames=%d player=%s fruit=%s fruits_left=%d" % [play.seeds, used, main.player.simulation_position, fpos, play.pickups.count()])
	var seeds_now: int = play.seeds
	main.player.simulation_position = center_of(site)
	await process_frame
	await process_frame
	click(MOUSE_BUTTON_LEFT, aim)
	await process_frame
	rec("4.fire_again", "after recovery a click fires again and spends the recovered seed", play.seeds == seeds_now - 1, "seeds %d -> %d" % [seeds_now, play.seeds])
	await drain_shots()
	# --- 4b. water recovery by walking to the waterside
	await new_main()
	play = main.play
	world = main.grid
	site = find_square(world, 0, 6, main.region_def.start_tile)
	await place_player(center_of(site))
	aim = center_of(site) + Vector2(40, 0)
	for i: int in 10:
		click(MOUSE_BUTTON_RIGHT, aim)
		await process_frame
	await drain_shots()
	rec("4.water_zero", "10 right clicks empty the gauge, the 11th does nothing", play.water == 0.0, "water=%s" % play.water)
	click(MOUSE_BUTTON_RIGHT, aim)
	await process_frame
	var no_fire: bool = main.projectile_view.shots.is_empty() and play.water == 0.0
	await ticks(120)
	rec("4.no_refill_away", "2 s away from water: gauge stays 0 and click still does nothing", no_fire and play.water == 0.0, "water=%s refilling=%s" % [play.water, play.refilling])
	var wp: Vector2i = cats[1.0]
	var viol: Array = [0]
	var last: Array = [play.water]
	var checker: Callable = func() -> void:
		var tdist: float = near_dist(world, defs, tile_of(main.player.simulation_position), 3)
		if play.water > last[0] + 0.0001 and tdist > 2.0:
			viol[0] += 1
		last[0] = play.water
	var used2: int = await walk_to(center_of(wp), 3000, 1.0, checker)
	await ticks(30)
	rec("4.water_recovered", "walking to the waterside restores water; no gain was ever seen while the nearest waterside was > 2 tiles away", play.water > 10.0 and viol[0] == 0, "water=%s walk_frames=%d violations=%d from=%s to=%s" % [play.water, used2, viol[0], center_of(site), center_of(wp)])
	await ticks(60)
	main.player.simulation_position = main.player.simulation_position
	var l0: int = launches()
	var w_before: float = play.water
	await click_wait(MOUSE_BUTTON_RIGHT, main.player.simulation_position + Vector2(30, 0))
	rec("4.water_fire_again", "after recovery a right click fires (one more launch) and spends 10 (net of refill during 2 frames)", launches() == l0 + 1 and play.water < w_before - 8.0, "water %s -> %s launches %d -> %d" % [w_before, play.water, l0, launches()])

# ---------------------------------------------------------------------------------------------- 6 source

func t6_source() -> void:
	await new_main()
	var play: PlayState = main.play
	var world: WorldState = main.grid
	var site: Vector2i = find_square(world, 0, 6, main.region_def.start_tile)
	await place_player(center_of(site))
	var src: SeedSource = play.sources[0]
	var srctile: Vector2i = tile_of(src.position)
	var def: TerrainDef = main.region_def.terrains[world.terrain[srctile.y * world.width + srctile.x]]
	rec("6.safe_zone", "the source stands on a safe-zone tile and has an indestructible flag, no health/damage API", def.key == &"safe" and SeedSource.INDESTRUCTIBLE and not ("health" in src) and not src.has_method("take_damage") and not src.has_method("damage"), "tile=%s terrain=%s" % [srctile, def.key])
	# fire at the source from the player: it must survive
	play.seeds = 40
	play.water = 100.0
	main.player.simulation_position = src.position + Vector2(-50, 0)
	for i: int in 30:
		play.seeds = 40
		main.fire(false, src.position)
		main.fire(true, src.position)
		await physics_frame
	await drain_shots()
	rec("6.survives_shots", "60 shots aimed at the source: still present, same position, node still in the tree", play.sources.size() == 1 and play.sources[0].position == src.position and main.actors.get_node_or_null("SeedSource1") != null, "sources=%d node=%s" % [play.sources.size(), main.actors.get_node_or_null("SeedSource1")])
	# timing run with the player far away so nothing is collected. Fresh main so the source timer starts at 0.
	await new_main()
	play = main.play
	world = main.grid
	await place_player(center_of(site))
	src = play.sources[0]
	var t_first: float = -1.0
	var t_cap: float = -1.0
	var max_count: int = 0
	var counts_at: Dictionary = {}
	var spawn_times: Array = []
	var last_count: int = 0
	for i: int in 4800:
		await physics_frame
		var c: int = play.pickups.count()
		max_count = maxi(max_count, c)
		if c > last_count:
			spawn_times.append(snappedf(play.elapsed, 0.01))
		last_count = c
		if i + 1 in [1500, 3000, 3900, 4200, 4500, 4800]:
			counts_at[i + 1] = c
	observations["fruit_spawn_times"] = spawn_times
	observations["fruit_counts_at_ticks"] = counts_at
	var interval_ok: bool = spawn_times.size() >= 4 and absf(float(spawn_times[0]) - 8.0) < 0.1 and absf(float(spawn_times[1]) - float(spawn_times[0]) - 8.0) < 0.1 and absf(float(spawn_times[2]) - float(spawn_times[1]) - 8.0) < 0.1
	rec("6.interval", "fruits drop every 8 s of game time (8, 16, 24) and the 4th does not come while 3 lie there", interval_ok, "spawn_times=%s" % str(spawn_times))
	rec("6.cap3", "at most 3 fruits of the source ever lie on the ground (max seen %d); 3 are present at t=25..60 s (tick 1500: %s, 3000: %s)" % [max_count, counts_at.get(1500), counts_at.get(3000)], max_count <= 3 and counts_at.get(1500) == 3 and counts_at.get(3000) == 3, "max=%d counts=%s" % [max_count, str(counts_at)])
	rec("6.lifetime_respawn", "fruits expire 60 s after dropping (8.0 -> 68.0: count 3 -> 2 at 70 s) and the source drops the next one one interval later (~76 s)", spawn_times.size() >= 4 and counts_at.get(4200) == 2 and absf(float(spawn_times[3]) - 76.0) < 0.2, "spawns=%s counts=%s" % [str(spawn_times), str(counts_at)])
	# collection increments seeds; pickup at cap stays; radius
	var play2: PlayState = main.play
	play2.seeds = 10
	play2.pickups.items.clear()
	var P: Vector2 = Vector2(500, 500)
	play2.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, P + Vector2(11.9, 0), 1)
	play2.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, P + Vector2(0, 12.6), 1)
	play2.advance(1.0 / 60.0, P)
	rec("6.collect_radius", "a fruit 11.9 px away is collected (+1 seed), one 12.6 px away is not (radius 12)", play2.seeds == 11 and play2.pickups.count() == 1, "seeds=%d fruits=%d" % [play2.seeds, play2.pickups.count()])
	play2.seeds = 40
	for i: int in 30:
		play2.advance(1.0 / 60.0, P + Vector2(0, 12.6))
	rec("6.full_no_collect", "with 40 seeds standing on a fruit does not collect it; seeds stay 40, fruit stays", play2.seeds == 40 and play2.pickups.count() == 1, "seeds=%d fruits=%d" % [play2.seeds, play2.pickups.count()])
	play2.seeds = 39
	play2.advance(1.0 / 60.0, P + Vector2(0, 12.6))
	rec("6.collect_at_39", "at 39 seeds the fruit is collected -> 40, never beyond", play2.seeds == 40 and play2.pickups.count() == 0, "seeds=%d fruits=%d" % [play2.seeds, play2.pickups.count()])
	var gp: GroundPickups = GroundPickups.new(24, 60.0)
	var accepted: int = 0
	for i: int in 30:
		if gp.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(i, i), 5):
			accepted += 1
	rec("6.total_cap", "GroundPickups refuses spawns beyond the 24 total cap", accepted == 24 and gp.count() == 24, "accepted=%d" % accepted)

# ---------------------------------------------------------------------------------------------- 7 pause

func t7_pause() -> void:
	await new_main()
	var play: PlayState = main.play
	var world: WorldState = main.grid
	var defs: Array = main.region_def.terrains
	# stand near water so refilling would be active, with the gauge low
	var cats: Vector2i = Vector2i(-1, -1)
	for y: int in range(60, 460):
		for x: int in range(60, 460):
			var tt: int = world.terrain[y * world.width + x]
			if (tt == 2 or tt == 3) and cats.x < 0:
				var p: Vector2i = Vector2i(x - 1, y)
				var pt: int = world.terrain[p.y * world.width + p.x]
				if pt != 2 and pt != 3 and near_dist(world, defs, p, 3) == 1.0 and pt != 4:
					cats = p
		if cats.x >= 0:
			break
	await place_player(center_of(cats))
	play.water = 10.0
	play.seeds = 5
	await ticks(5)
	observations["t7_site"] = "%s refilling=%s" % [cats, play.refilling]
	print("DBG7 cats=%s player=%s refilling=%s water=%s nd=%s" % [cats, main.player.simulation_position, play.refilling, play.water, near_dist(world, defs, tile_of(main.player.simulation_position), 3)])
	await ticks(495)  # let the source start counting, fruits appear
	play.water = 10.0
	main.fire(false, main.player.simulation_position + Vector2(100, 0))
	main.fire(true, main.player.simulation_position + Vector2(0, 100))
	await ticks(5)
	var shots_snap: Array = []
	for s: Dictionary in main.projectile_view.shots:
		shots_snap.append([s["position"], s["traveled"], s["age"]])
	var snap: Dictionary = {
		"elapsed": play.elapsed, "seeds": play.seeds, "water": play.water, "timer": play.sources[0].timer,
		"ages": str(play.pickups.items.map(func(it: Dictionary) -> float: return it["age"])), "n_pick": play.pickups.count(),
		"shots": str(shots_snap), "landing": play.landing_counter, "player": main.player.simulation_position,
	}
	var shots_n: int = main.projectile_view.shots.size()
	tap_escape()
	await process_frame
	await process_frame
	rec("7.esc_pauses", "injected Esc pauses the tree and shows the pause panel", paused and main.pause_panel.visible, "paused=%s panel=%s shots_in_flight=%d" % [paused, main.pause_panel.visible, shots_n])
	var snap_p: Dictionary = {
		"elapsed": play.elapsed, "seeds": play.seeds, "water": play.water, "timer": play.sources[0].timer,
		"ages": str(play.pickups.items.map(func(it: Dictionary) -> float: return it["age"])), "n_pick": play.pickups.count(),
		"shots": str(main.projectile_view.shots.map(func(s: Dictionary) -> Array: return [s["position"], s["traveled"], s["age"]])), "landing": play.landing_counter,
	}
	var wall0: int = Time.get_ticks_msec()
	await create_timer(1.5, true).timeout  # 1.5 s of real time while paused
	print("DBG7b paused=%s el=%s" % [paused, play.elapsed])
	await ticks(180)
	print("DBG7c paused=%s el=%s" % [paused, play.elapsed])
	# inputs during pause: clicks and fire() must do nothing
	var off_panel: Vector2 = main.player.simulation_position + Vector2(-250, 60)  # screen (70,240): not over the pause panel
	await click_wait(MOUSE_BUTTON_LEFT, off_panel)
	await click_wait(MOUSE_BUTTON_RIGHT, off_panel)
	var fire_p: bool = main.fire(false, main.player.simulation_position + Vector2(40, 0))
	print("DBG7d paused=%s el=%s" % [paused, play.elapsed])
	await ticks(5)
	print("DBG7e paused=%s el=%s" % [paused, play.elapsed])
	var snap_q: Dictionary = {
		"elapsed": play.elapsed, "seeds": play.seeds, "water": play.water, "timer": play.sources[0].timer,
		"ages": str(play.pickups.items.map(func(it: Dictionary) -> float: return it["age"])), "n_pick": play.pickups.count(),
		"shots": str(main.projectile_view.shots.map(func(s: Dictionary) -> Array: return [s["position"], s["traveled"], s["age"]])), "landing": play.landing_counter,
	}
	var wall: int = Time.get_ticks_msec() - wall0
	rec("7.frozen", "after %d ms wall time and 185 ticks paused: elapsed, seeds, water, source timer, fruit ages, shot positions all unchanged; clicks/fire do nothing" % wall, snap_p == snap_q and not fire_p, "before=%s after=%s fire=%s" % [str(snap_p), str(snap_q), fire_p])
	var kept_water_low: bool = play.water == 10.0 or play.water == snap_p["water"]
	tap_escape()
	await process_frame
	var e_resume: float = play.elapsed
	await ticks(30)
	var advanced: float = play.elapsed - e_resume
	rec("7.resume_no_bank", "after Esc resume 30 ticks advance game time by ~0.5 s (not by the ~%d ms paused)" % wall, (not paused) and advanced > 0.4 and advanced < 0.6, "advanced=%.4f s unpaused=%s" % [advanced, not paused])
	var moved: bool = str(main.projectile_view.shots.map(func(s: Dictionary) -> Array: return [s["position"], s["traveled"], s["age"]])) != snap_q["shots"] or main.projectile_view.shots.is_empty()
	rec("7.shots_continue", "in-flight shots continue after resume", moved, "shots now=%d (was %d)" % [main.projectile_view.shots.size(), shots_n])
	rec("7.refill_paused_only", "the refill did not run during pause (water unchanged 10) yet runs after resume", kept_water_low and play.water > 10.0, "water now=%s (before pause %s)" % [play.water, snap_p["water"]])

# ---------------------------------------------------------------------------------------------- 8 HUD

func t8_hud() -> void:
	await new_main()
	var play: PlayState = main.play
	var world: WorldState = main.grid
	var hud: PlayHud = main.hud
	play.seeds = 7
	play.water = 63.9
	await process_frame
	await process_frame
	var s: String = hud.seed_label.text
	var w: String = hud.water_label.text
	var g: String = hud.green_label.text
	rec("8.seed_water_text", "HUD shows seeds 7/40 and water 63 (gauge value floor) after the values change", s.contains("7/40") and w.contains("63") and not w.contains("64"), "seed='%s' water='%s' green='%s'" % [s, w, g])
	play.add_seeds(100)
	play.water = 0.0
	await process_frame
	await process_frame
	rec("8.follow", "HUD follows: seeds at cap 40/40, water 0, gauge marked low", hud.seed_label.text.contains("40/40") and hud.water_label.text.contains("0") and hud.gauge.low and hud.gauge.fraction == 0.0, "seed='%s' water='%s' low=%s" % [hud.seed_label.text, hud.water_label.text, hud.gauge.low])
	# greening percent floor
	var T: int = world.target_count
	var steps: Array = []
	var ok_all: bool = true
	var order: PackedInt32Array = PackedInt32Array()
	for i: int in world.tile_count():
		if world.target[i] == 1 and world.stage[i] == 0:
			order.append(i)
	var pos: int = 0
	var thresholds: Array = [37, 63, 99]
	for pct: int in thresholds:
		# smallest g with g*100 >= pct*T, computed in integers here
		var gneed: int = (pct * T + 99) / 100
		var below: int = gneed - 1
		while world.greened_count < below and pos < order.size():
			world.set_stage(order[pos], 2)
			pos += 1
		await process_frame
		await process_frame
		var txt_below: String = hud.green_label.text
		world.set_stage(order[pos], 2)
		pos += 1
		await process_frame
		await process_frame
		var txt_at: String = hud.green_label.text
		var exp_below: String = "%d" % (pct - 1)
		var exp_at: String = "%d" % pct
		var good: bool = txt_below.contains(exp_below + "％") and txt_at.contains(exp_at + "％") and world.greened_count == gneed
		ok_all = ok_all and good
		steps.append("%d%%: g=%d below='%s' at='%s'" % [pct, gneed, txt_below, txt_at])
	rec("8.green_floor", "HUD greening shows the floor: one tile below the threshold shows pct-1 (e.g. 36.99998 -> 36), at the threshold shows pct", ok_all, " | ".join(steps))
	# 100 only at full
	while pos < order.size() - 1:
		world.set_stage(order[pos], 2)
		pos += 1
	await process_frame
	await process_frame
	var t99: String = hud.green_label.text
	var gb: int = world.greened_count
	world.set_stage(order[pos], 2)
	pos += 1
	await process_frame
	await process_frame
	var t100: String = hud.green_label.text
	rec("8.green_99_100", "one tile short of all targets shows 99％, all targets shows 100％", gb == T - 1 and t99.contains("99％") and world.is_fully_greened() and t100.contains("100％"), "short='%s' full='%s' g=%d T=%d" % [t99, t100, world.greened_count, T])
	rec("8.green_counter", "greened_count equals independent recount at the end", world.counters_consistent(), "g=%d recount=%d" % [world.greened_count, world.recount_greened()])

# ---------------------------------------------------------------------------------------------- 9 save

func t9_save() -> void:
	await new_main()
	var play: PlayState = main.play
	play.seeds = 13
	play.water = 42.5
	play.landing_counter = 9
	await ticks(100)
	play.advance(9.0, Vector2(0, 0))  # forces fruits to exist (steps are capped to 0.25 s, so call repeatedly)
	for i: int in 120:
		play.advance(0.25, Vector2(0, 0))
	var before: Dictionary = play.to_dict()
	var text: String = JSON.stringify(before)
	var parsed: Variant = JSON.parse_string(text)
	var play2: PlayState = PlayState.new(main.grid, play.tuning, main.tuning, TILE, [Vector2(main.play.sources[0].position)] as Array[Vector2])
	var ok: bool = play2.load_dict(parsed)
	var after: Dictionary = play2.to_dict()
	rec("9.roundtrip", "to_dict -> JSON -> load_dict -> to_dict is identical (seeds, water, counter, elapsed, fruits, source timers)", ok and JSON.stringify(after) == text and play.pickups.count() > 0, "ok=%s fruits=%d seeds=%d water=%s" % [ok, play2.pickups.count(), play2.seeds, play2.water])
	var bad: Dictionary = parsed.duplicate(true)
	bad["sources"] = []
	var s0: int = play2.seeds
	var rej: bool = not play2.load_dict(bad)
	var bad2: Dictionary = parsed.duplicate(true)
	bad2["version"] = 99
	var rej2: bool = not play2.load_dict(bad2)
	var bad3: Dictionary = parsed.duplicate(true)
	bad3["seeds"] = 9999
	bad3["water"] = -5
	var okc: bool = play2.load_dict(bad3)
	rec("9.reject_clamp", "mismatched sources / wrong version are rejected without changing state; out-of-range seeds/water are clamped (40 / 0)", rej and rej2 and play2.seeds == 40 and play2.water == 0.0 and okc and s0 == 13, "rej=%s rej2=%s clamped seeds=%d water=%s" % [rej, rej2, play2.seeds, play2.water])
	# world roundtrip with seeds
	var w: WorldState = main.grid
	var d: Dictionary = w.to_dict()
	var w2: WorldState = WorldState.from_dict(JSON.parse_string(JSON.stringify(d)), main.region_def.terrains)
	rec("9.world_roundtrip", "world with scattered seeds survives to_dict/JSON/from_dict (stages equal, counters equal)", w2 != null and w2.stage == w.stage and w2.greened_count == w.greened_count, "ok=%s" % (w2 != null))
