extends SceneTree
## Independent verifier for P1-03, scene level (real main.tscn, engine-internal input injection only; headless).
## Run: Godot --headless --fixed-fps 60 --path <project> --script res://tests/p1/independent/p1_03_v_scene.gd -- --only=chain|pause|night|rate --hz=N
## Expectations come from the spec and from my own integration of the growth model, not from the implementation's code.

const OUT: String = "res://evidence/p1/p1-03/independent/"
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
	var only: String = "chain"
	var hz: int = 60
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--hz="):
			hz = int(a.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	match only:
		"chain":
			await t_chain()
		"pause":
			await t_pause()
		"night":
			await t_night()
		"rate":
			await t_rate(hz)
	var f: FileAccess = FileAccess.open(OUT + "checks_scene_%s%s.json" % [only, "_%d" % hz if only == "rate" else ""], FileAccess.WRITE)
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


## First tick offsets at which a tile reaches stage>=2/>=3/4 starting from growth g0 and moisture m0 (my own integration:
## factor 1 + m/100 (1.0 dry .. 2.0 wet), 1000 per tick, thresholds 40000/80000/120000, moisture -1 per tick after the tick).
func model_offsets(g0: int, m0: int) -> Array:
	var g: int = g0
	var m: int = m0
	var res: Array = [0, 0, 0]
	var k: int = 0
	while res[2] == 0 and k < 2000:
		k += 1
		g += roundi(1000.0 * (1.0 + float(m) / 100.0))
		m = maxi(m - 1, 0)
		if res[0] == 0 and g >= 40000:
			res[0] = k
		if res[1] == 0 and g >= 80000:
			res[1] = k
		if res[2] == 0 and g >= 120000:
			res[2] = k
	return res

func mature_in_circle(world: WorldState, c: Vector2, r: float) -> int:
	var n: int = 0
	for y: int in range(maxi(floori((c.y - r) / TILE) - 1, 0), mini(floori((c.y + r) / TILE) + 2, world.height)):
		for x: int in range(maxi(floori((c.x - r) / TILE) - 1, 0), mini(floori((c.x + r) / TILE) + 2, world.width)):
			if world.stage[y * world.width + x] == 4 and Vector2((x + 0.5) * TILE, (y + 0.5) * TILE).distance_to(c) <= r:
				n += 1
	return n

# ---------------------------------------------------------------------------------------------- chain

func t_chain() -> void:
	await new_main()
	# P1-04: natural spread from the safe zone would add greened tiles outside the tracked area; it is switched off so that this
	# counter-tracking assertion keeps its meaning (greening = base + tracked player-planted tiles).
	main.simulation.spread.allow_hook = func(_index: int) -> bool: return false
	var play: PlayState = main.play
	var world: WorldState = main.grid
	var clock: SimClock = main.simulation.clock
	# a wasteland site at least 260 px from every initially mature (safe zone) tile
	var safe: PackedInt32Array = PackedInt32Array()
	for i: int in world.tile_count():
		if world.stage[i] == 4:
			safe.append(i)
	var site: Vector2i = Vector2i(-1, -1)
	var best_d: int = 1 << 60
	for cy: int in range(10, world.height - 10, 3):
		for cx: int in range(10, world.width - 10, 3):
			var dd: int = (cx - main.region_def.start_tile.x) * (cx - main.region_def.start_tile.x) + (cy - main.region_def.start_tile.y) * (cy - main.region_def.start_tile.y)
			if dd >= best_d or not square_all(world, cx, cy, 9, 0):
				continue
			var far_enough: bool = true
			var cc: Vector2 = center_of(Vector2i(cx, cy))
			for s: int in safe:
				if Vector2((s % world.width + 0.5) * TILE, (s / world.width + 0.5) * TILE).distance_to(cc) < 260.0:
					far_enough = false
					break
			if far_enough:
				site = Vector2i(cx, cy)
				best_d = dd
	observations["chain_site"] = str(site)
	var centre: Vector2 = center_of(site)
	await place_player(centre)
	var base_green: int = world.greened_count
	var base_mature: int = world.mature_count
	rec("chain.setup", "site found far (>=260 px) from the initially mature safe zone, player placed, 20 seeds, 100 water", site.x >= 0 and play.seeds == 20 and mature_in_circle(world, centre, 160.0) == 0, "site=%s seeds=%d water=%s mature in circle=%d" % [str(site), play.seeds, str(play.water), mature_in_circle(world, centre, 160.0)])
	var spots_wet: Array[Vector2] = [centre + Vector2(-26, -20), centre + Vector2(-26, 20)]
	var spots_dry: Array[Vector2] = [centre + Vector2(26, -20), centre + Vector2(26, 20)]
	# water the wet spots (two shots each: 40 + 40), let it land
	for sp: Vector2 in spots_wet:
		await click_wait(MOUSE_BUTTON_RIGHT, sp)
		await ticks(6)
		await click_wait(MOUSE_BUTTON_RIGHT, sp)
		await ticks(6)
	await drain_shots()
	await ticks(2)
	var wet_tiles: int = 0
	for y: int in range(site.y - 12, site.y + 13):
		for x: int in range(site.x - 12, site.x + 13):
			if world.moisture[y * world.width + x] > 0:
				wet_tiles += 1
	rec("chain.water_landed", "injected right clicks landed water: bare ground near the wet spots has moisture, greening unchanged", wet_tiles > 10 and world.greened_count == base_green and play.water < 100.0, "wet tiles=%d water gauge=%s" % [wet_tiles, str(play.water)])
	# fire all 20 seeds: 3+3 at the wet spots, 7+7 at the dry spots
	var plan: Array[Vector2] = []
	for k: int in 3:
		plan.append(spots_wet[0])
		plan.append(spots_wet[1])
	for k: int in 7:
		plan.append(spots_dry[0])
		plan.append(spots_dry[1])
	var tracked: Dictionary = {}
	var order: Array = []
	var seeds_before: int = play.seeds
	var greened_at_fire: int = world.greened_count
	for sp: Vector2 in plan:
		await click_wait_phys(MOUSE_BUTTON_LEFT, sp)
		_scan_new(tracked, order, world, clock, site)
	for i: int in 400:
		await physics_frame
		_scan_new(tracked, order, world, clock, site)
		if main.projectile_view.shots.is_empty() and i > 20:
			break
	await physics_frame
	_scan_new(tracked, order, world, clock, site)
	var n_tracked: int = tracked.size()
	rec("chain.seeds_landed", "20 injected left clicks spent 20 seeds and planted seed tiles (stage 1); greening count did not move at planting", play.seeds == seeds_before - 20 and n_tracked >= 25 and world.greened_count - greened_at_fire == _count_stage_ge2(tracked, world), "seeds=%d tracked seed tiles=%d greened delta=%d (tiles already sprouting %d)" % [play.seeds, n_tracked, world.greened_count - greened_at_fire, _count_stage_ge2(tracked, world)])
	var green_mismatch: int = 0
	var frames_run: int = 0
	var first_fruit: Dictionary = {}
	var fruit_seen_at: float = -1.0
	var hz: int = Engine.physics_ticks_per_second
	var t_start: float = clock.elapsed
	while frames_run < hz * 150:
		await physics_frame
		frames_run += 1
		_update_hist(tracked, order, world, clock)
		if frames_run % 15 == 0:
			var mine: int = base_green + _count_stage_ge2(tracked, world)
			if mine != world.greened_count:
				green_mismatch += 1
		if first_fruit.is_empty():
			for it: Dictionary in play.pickups.items:
				if int(it["owner"]) >= GroundPickups.PLANT_OWNER_BASE and tracked.has(int(it["owner"]) - GroundPickups.PLANT_OWNER_BASE):
					first_fruit = it.duplicate()
					fruit_seen_at = clock.elapsed
		var all_m: bool = true
		for t: int in tracked:
			if world.stage[t] != 4:
				all_m = false
				break
		if all_m and not first_fruit.is_empty():
			break
	rec("chain.green_tracking", "greening counter == base + my count of tracked tiles at sprout1 or later, checked every 15 frames over the whole run", green_mismatch == 0, "mismatches=%d, final greened=%d base=%d tracked=%d" % [green_mismatch, world.greened_count, base_green, n_tracked])
	var seq_bad: int = 0
	var time_bad: int = 0
	var checked: int = 0
	var wet_group: Array = []
	var dry_group: Array = []
	var first_bad: String = ""
	for t: int in order:
		var rec_t: Dictionary = tracked[t]
		var hist: Array = rec_t["hist"]
		var stages: Array = [rec_t["s0"]]
		for h: Array in hist:
			stages.append(h[1])
		var want_seq: Array = []
		for s: int in range(int(rec_t["s0"]), 5):
			want_seq.append(s)
		if stages != want_seq:
			seq_bad += 1
		if rec_t["s0"] == 1 and hist.size() == 3:
			var off: Array = model_offsets(int(rec_t["g"]), int(rec_t["m"]))
			var tp: int = int(rec_t["tp"])
			var got: Array = [hist[0][0], hist[1][0], hist[2][0]]
			var want: Array = [tp + off[0], tp + off[1], tp + off[2]]
			checked += 1
			if got != want:
				time_bad += 1
				if first_bad == "":
					first_bad = "tile %d m0=%d g0=%d tp=%d got=%s want=%s" % [t, rec_t["m"], rec_t["g"], tp, str(got), str(want)]
			if int(rec_t["m"]) > 0:
				wet_group.append(got[2] - tp)
			else:
				dry_group.append(got[2] - tp)
	var mean_wet: float = 0.0
	for v: int in wet_group:
		mean_wet += v
	mean_wet /= maxf(wet_group.size(), 1)
	var mean_dry: float = 0.0
	for v: int in dry_group:
		mean_dry += v
	mean_dry /= maxf(dry_group.size(), 1)
	var dry_all_120: bool = true
	for v: int in dry_group:
		if v < 119 or v > 121:
			dry_all_120 = false
	observations["chain_groups"] = {"wet_n": wet_group.size(), "dry_n": dry_group.size(), "mean_wet_ticks": mean_wet, "mean_dry_ticks": mean_dry}
	rec("chain.stage_order", "every tracked tile went seed -> sprout1 -> sprout2 -> mature, no skips, no regress", seq_bad == 0 and checked > 20, "sequence violations=%d, tiles checked=%d" % [seq_bad, checked])
	rec("chain.model_times", "the tick at which each tile reached sprout1/sprout2/mature equals my integration from its moisture and growth at planting (exact), for wet-then-drying and dry tiles", time_bad == 0 and checked > 20, "mismatching tiles=%d of %d %s" % [time_bad, checked, first_bad])
	rec("chain.water_faster", "watered tiles mature faster than unwatered ones; unwatered still mature, in 120 ticks (60 s)", wet_group.size() >= 5 and dry_group.size() >= 5 and mean_wet < mean_dry - 10.0 and dry_all_120, "wet n=%d mean %.1f ticks (%.1f s); dry n=%d mean %.1f ticks (%.1f s)" % [wet_group.size(), mean_wet, mean_wet / 2.0, dry_group.size(), mean_dry, mean_dry / 2.0])
	rec("chain.fruit_from_our_plants", "a plant fruit appeared on one of the tiles we grew (owner = base + tile), lying on a mature tile", not first_fruit.is_empty() and world.stage[int(first_fruit["owner"]) - GroundPickups.PLANT_OWNER_BASE] == 4, "first fruit at game t=%.1f s (%.1f s after the growth watch started): %s" % [fruit_seen_at, fruit_seen_at - t_start, str(first_fruit)])
	var seeds_zero: bool = play.seeds == 0
	var fruit_target: Vector2 = Vector2.INF
	var walk_frames: int = 0
	for attempt: int in 6:
		if play.seeds > 0:
			break
		var nearest: float = INF
		fruit_target = Vector2.INF
		for it: Dictionary in play.pickups.items:
			if int(it["owner"]) >= GroundPickups.PLANT_OWNER_BASE:
				var p: Vector2 = Vector2(float(it["x"]), float(it["y"]))
				var dd2: float = p.distance_to(main.player.simulation_position)
				if dd2 < nearest:
					nearest = dd2
					fruit_target = p
		if fruit_target == Vector2.INF:
			await ticks(120)
			continue
		walk_frames += await walk_to(fruit_target, 400, 3.0)
	var collected_seed_gain: int = play.seeds
	rec("chain.collect", "starting from 0 seeds, walking to a plant fruit with injected WASD collects it automatically (+%d seed)" % play.tuning.seed_fruit_seeds, seeds_zero and collected_seed_gain >= 1, "seeds now=%d after %d walk frames, player at %s" % [collected_seed_gain, walk_frames, str(main.player.simulation_position)])
	var landing_before: int = play.landing_counter
	var seeds_before2: int = play.seeds
	var aim_free: Vector2 = main.player.simulation_position + Vector2(0, -40)
	await click_wait(MOUSE_BUTTON_LEFT, aim_free)
	await drain_shots()
	await ticks(3)
	var scattered: PackedInt32Array = play.last_scatter
	var any_seed: bool = false
	for t: int in scattered:
		if world.stage[t] >= 1:
			any_seed = true
	rec("chain.refire", "the collected seed can be shot again: seed count down by 1, a new landing planted fresh seed tiles", play.landing_counter == landing_before + 1 and play.seeds == seeds_before2 - 1 and scattered.size() > 0 and any_seed, "landing %d -> %d, seeds %d -> %d, new seed tiles=%d" % [landing_before, play.landing_counter, seeds_before2, play.seeds, scattered.size()])
	rec("chain.counters", "world counters consistent at the end (greened/mature/targets vs recount), active set equals brute force", world.counters_consistent() and _active_ok(world), "greened=%d mature=%d (base %d)" % [world.greened_count, world.mature_count, base_mature])
	release_all()

func click_wait_phys(button: MouseButton, world_pos: Vector2) -> void:
	click(button, world_pos)
	await physics_frame
	await physics_frame

func _active_ok(world: WorldState) -> bool:
	var want: Dictionary = {}
	for i: int in world.tile_count():
		var s: int = world.stage[i]
		if (s >= 1 and s <= 3) or world.moisture[i] > 0:
			want[i] = true
	if want.size() != world.active_tiles.size():
		return false
	for t: int in world.active_tiles:
		if not want.has(t):
			return false
	return true

func _count_stage_ge2(tracked: Dictionary, world: WorldState) -> int:
	var n: int = 0
	for t: int in tracked:
		if world.stage[t] >= 2:
			n += 1
	return n

func _scan_new(tracked: Dictionary, order: Array, world: WorldState, clock: SimClock, site: Vector2i) -> void:
	for y: int in range(site.y - 24, site.y + 25):
		for x: int in range(site.x - 24, site.x + 25):
			var i: int = y * world.width + x
			if world.stage[i] >= 1 and not tracked.has(i):
				tracked[i] = {"tp": clock.growth_ticks, "g": world.growth[i], "m": world.moisture[i], "s0": world.stage[i], "last": world.stage[i], "hist": []}
				order.append(i)

func _update_hist(tracked: Dictionary, order: Array, world: WorldState, clock: SimClock) -> void:
	for t: int in order:
		var rec_t: Dictionary = tracked[t]
		var s: int = world.stage[t]
		if s != rec_t["last"]:
			(rec_t["hist"] as Array).append([clock.growth_ticks, s])
			rec_t["last"] = s

# ---------------------------------------------------------------------------------------------- pause

func world_snapshot() -> Dictionary:
	var play: PlayState = main.play
	var world: WorldState = main.grid
	var clock: SimClock = main.simulation.clock
	return {
		"hash": "%d/%d/%d" % [hash(world.stage), hash(world.growth), hash(world.moisture)], "greened": world.greened_count, "mature": world.mature_count,
		"clock": [clock.elapsed, clock.growth_ticks, clock.spread_ticks], "play_elapsed": play.elapsed,
		"production": [play.production_time, play.production_ticks, play.producer.ticks, play.producer.total_produced],
		"pickups": JSON.stringify(play.pickups.to_dict()), "active": main.grid.active_tiles.size(),
	}

func t_pause() -> void:
	await new_main()
	var play: PlayState = main.play
	var world: WorldState = main.grid
	var clock: SimClock = main.simulation.clock
	var site: Vector2i = find_square(world, 0, 12, main.region_def.start_tile + Vector2i(60, 0))
	var centre: Vector2 = center_of(site)
	await place_player(centre)
	play.seeds = play.tuning.seed_max
	var cnt: int = 0
	for dy: int in range(-9, 10):
		for dx: int in range(-9, 10):
			var i: int = (site.y + dy) * world.width + site.x + dx
			if dy < 2 and cnt < 150:
				world.set_stage(i, 4)
				cnt += 1
			elif dy >= 4 and dy < 7:
				world.set_stage(i, 1)
				world.set_moisture(i, 100)
			elif dy >= 7:
				world.set_moisture(i, 60)
	await ticks(60 * 14)
	var fruits: int = play.pickups.count_plant_owned()
	rec("pause.setup", "before pausing: seeds are growing, ground is wet, plant fruits lie on the ground (production runs)", fruits >= 1 and world.active_tiles.size() > 50 and play.producer.total_produced >= 1, "fruits=%d active=%d produced=%d growth_ticks=%d" % [fruits, world.active_tiles.size(), play.producer.total_produced, clock.growth_ticks])
	var before_esc: Dictionary = world_snapshot()
	tap_escape()
	await process_frame
	await process_frame
	var s0: Dictionary = world_snapshot()
	var is_paused: bool = paused
	var wall0: int = Time.get_ticks_msec()
	await create_timer(1.5, true).timeout
	await ticks(60 * 12)
	var s1: Dictionary = world_snapshot()
	var wall: int = Time.get_ticks_msec() - wall0
	var fired: bool = main.fire(false, centre + Vector2(30, 0))
	await ticks(5)
	var s2: Dictionary = world_snapshot()
	rec("pause.frozen", "paused (%d ms wall, 725 physics frames): growth, moisture, stages, clock ticks, production time/ticks, fruit ages and positions, active set all unchanged; firing is refused" % wall, is_paused and s0 == s1 and s1 == s2 and not fired, "paused=%s fired=%s equal=%s clock=%s production=%s" % [str(is_paused), str(fired), str(s0 == s1 and s1 == s2), str(s2["clock"]), str(s2["production"])])
	rec("pause.moved_before", "sanity: the state did change during the 14 s before pausing (so the freeze check is meaningful)", before_esc["clock"][1] >= 27 and before_esc["production"][1] >= 6, "clock ticks=%d production ticks=%d" % [before_esc["clock"][1], before_esc["production"][1]])
	tap_escape()
	await process_frame
	var e0: float = clock.elapsed
	var ct0: int = clock.growth_ticks
	var pt0: int = play.production_ticks
	var pe0: float = play.elapsed
	var age0: float = 0.0
	if play.pickups.count() > 0:
		age0 = float(play.pickups.items[0]["age"])
	await ticks(120)
	var de: float = clock.elapsed - e0
	var dct: int = clock.growth_ticks - ct0
	var dpt: int = play.production_ticks - pt0
	var dpe: float = play.elapsed - pe0
	rec("pause.resume_no_bank", "after resuming, 120 physics frames (2 s) advance game time by 2 s, 4 growth ticks (+-1), 1 production tick (+-1); the ~%d ms spent paused is not added" % wall, (not paused) and absf(de - 2.0) < 0.05 and absf(dpe - 2.0) < 0.05 and absi(dct - 4) <= 1 and dpt >= 0 and dpt <= 2, "elapsed +%.4f play +%.4f growth ticks +%d production ticks +%d (first fruit age before resume %.3f)" % [de, dpe, dct, dpt, age0])
	release_all()

# ---------------------------------------------------------------------------------------------- night (key 3) does not stop growth

func t_night() -> void:
	await new_main()
	var world: WorldState = main.grid
	var clock: SimClock = main.simulation.clock
	var site: Vector2i = find_square(world, 0, 6, main.region_def.start_tile + Vector2i(60, 0))
	var a: int = site.y * world.width + site.x
	var b: int = a + 3
	world.set_stage(a, 1)
	world.set_stage(b, 1)
	await place_player(center_of(site) + Vector2(0, 40))
	var g_a0: int = world.growth[a]
	var hz: int = Engine.physics_ticks_per_second
	await ticks(roundi(hz * 5.0))
	var day_gain: int = world.growth[a] - g_a0
	key(KEY_3, true)
	await physics_frame
	key(KEY_3, false)
	await physics_frame
	var is_night: bool = main.condition == "night"
	var g_b0: int = world.growth[b]
	var c0: int = clock.growth_ticks
	await ticks(roundi(hz * 5.0))
	var night_gain: int = world.growth[b] - g_b0
	var night_ticks: int = clock.growth_ticks - c0
	key(KEY_2, true)
	await physics_frame
	key(KEY_2, false)
	await physics_frame
	var is_rain: bool = main.condition == "rain"
	var g_c0: int = world.growth[b]
	await ticks(roundi(hz * 5.0))
	var rain_gain: int = world.growth[b] - g_c0
	rec("night.not_stopped", "growth never stops: at night (injected key 3) a dry seed still gains 1000 per tick (5 s = 10 ticks = 10000), same as in daylight; same in rain (key 2)", is_night and is_rain and day_gain == 10000 and night_gain == 10000 and rain_gain == 10000, "night=%s rain=%s gains day=%d night=%d (ticks %d) rain=%d" % [str(is_night), str(is_rain), day_gain, night_gain, night_ticks, rain_gain])
	release_all()

# ---------------------------------------------------------------------------------------------- frame-rate (scene)

func t_rate(hz: int) -> void:
	await new_main()
	var play: PlayState = main.play
	var world: WorldState = main.grid
	var clock: SimClock = main.simulation.clock
	var site: Vector2i = find_square(world, 0, 12, main.region_def.start_tile + Vector2i(60, 0))
	var centre: Vector2 = center_of(site)
	await place_player(centre)
	play.seeds = play.tuning.seed_max
	var cnt: int = 0
	for dy: int in range(-9, 0):
		for dx: int in range(-9, 10):
			if cnt < 120:
				world.set_stage((site.y + dy) * world.width + site.x + dx, 4)
				cnt += 1
	for k: int in 3:
		play.land_seed(centre + Vector2(k * 14 - 14, 28))
	play.land_water(centre + Vector2(0, 28))
	var t0: float = clock.elapsed
	var e0: float = play.elapsed
	var ct0: int = clock.growth_ticks
	var pt0: int = play.production_ticks
	var pr0: int = play.producer.ticks
	var snaps: Dictionary = {}
	for target: float in [20.0, 60.0, 100.0, 100.5]:
		var frames: int = roundi(target * float(hz))
		var done: int = roundi((clock.elapsed - t0) * float(hz))
		await ticks(frames - done)
		var items: Array = []
		for it: Dictionary in play.pickups.items:
			items.append([snappedf(float(it["x"]), 0.0001), snappedf(float(it["y"]), 0.0001), int(it["owner"])])
		items.sort()
		snaps[str(target)] = {
			"clock_dt": snappedf(clock.elapsed - t0, 0.0001), "play_dt": snappedf(play.elapsed - e0, 0.0001),
			"growth_ticks": clock.growth_ticks - ct0, "prod_ticks": play.production_ticks - pt0, "producer_ticks": play.producer.ticks - pr0,
			"produced": play.producer.total_produced, "hash": "%d/%d/%d" % [hash(world.stage), hash(world.growth), hash(world.moisture)],
			"greened": world.greened_count, "mature": world.mature_count, "items": items,
		}
	observations["rate_hz"] = hz
	observations["snaps"] = snaps
	var last: Dictionary = snaps["100.5"]
	rec("rate.%d" % hz, "%d Hz physics: after 100.5 s of game time the clock has run 201 growth ticks and 50 production ticks (cross-rate equality is checked by the comparer)" % hz, last["growth_ticks"] == 201 and last["prod_ticks"] == 50 and absf(float(last["clock_dt"]) - 100.5) < 0.02, "growth ticks=%d production ticks=%d clock dt=%s produced=%d mature=%d greened=%d" % [last["growth_ticks"], last["prod_ticks"], str(last["clock_dt"]), last["produced"], last["mature"], last["greened"]])
