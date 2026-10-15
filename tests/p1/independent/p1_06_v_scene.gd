extends SceneTree
## Independent verifier for P1-06, scene level: the real main.tscn, engine-internal input injection only (key and mouse
## events through Input.parse_input_event; no OS input, no focus). Headless with --fixed-fps 60.
## Run: Godot --headless --fixed-fps 60 --path <project> --script res://tests/p1/independent/p1_06_v_scene.gd -- --only=<name> [--hz=N]
## sections: walk, pause, chain, water, recover, spread, control, carrot, kiwi, invalid

const OUT: String = "res://evidence/p1/p1-06/independent/"
const T: int = 4
const HALF: Vector2 = Vector2(3.0, 2.0)
const PLANT_OWNER_BASE: int = 1000000

var results: Array[Dictionary] = []
var main: Node
var observations: Dictionary = {}
var keys_down: Dictionary = {}
var landed_n: int = 0
var hz: int = 60
var tick_count: int = 0

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func run() -> void:
	var only: String = "walk"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--hz="):
			hz = int(a.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	match only:
		"walk":
			await t_walk()
		"pause":
			await t_pause()
		"chain":
			await t_chain()
		"water":
			await t_water()
		"recover":
			await t_recover()
		"spread":
			await t_spread(false, false)
		"control":
			await t_spread(false, true)
		"carrot":
			await t_spread(true, true)
		"kiwi":
			await t_kiwi()
		"invalid":
			await t_invalid()
	var f: FileAccess = FileAccess.open(OUT + "checks_scene_%s%s.json" % [only, "_%d" % hz if only == "walk" else ""], FileAccess.WRITE)
	f.store_string(JSON.stringify({"results": results, "observations": observations}, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("V_RESULT total=%d fails=%d" % [results.size(), fails])
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------------------------------ helpers

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

func ticks(n: int) -> void:
	for i: int in n:
		await physics_frame
		tick_count += 1

func seconds(s: float) -> void:
	await ticks(roundi(s * hz))

func key_event(code: Key, pressed: bool) -> void:
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)

func key_tap(code: Key) -> void:
	key_event(code, true)
	key_event(code, false)

## Holds exactly the given keys (others are released) via injected key events.
func hold(codes: Array) -> void:
	for code: Variant in keys_down.keys():
		if not codes.has(code):
			key_event(code as Key, false)
			keys_down.erase(code)
	for code: Variant in codes:
		if not keys_down.has(code):
			key_event(code as Key, true)
			keys_down[code] = true

func release_all() -> void:
	hold([])

func screen_of(world_pos: Vector2) -> Vector2:
	return main.get_viewport().get_canvas_transform() * world_pos

func mouse_button(button: MouseButton, world_pos: Vector2) -> void:
	var m: InputEventMouseMotion = InputEventMouseMotion.new()
	m.position = screen_of(world_pos)
	m.global_position = m.position
	Input.parse_input_event(m)
	var d: InputEventMouseButton = InputEventMouseButton.new()
	d.button_index = button
	d.pressed = true
	d.position = m.position
	d.global_position = m.position
	Input.parse_input_event(d)
	var u: InputEventMouseButton = InputEventMouseButton.new()
	u.button_index = button
	u.pressed = false
	u.position = m.position
	u.global_position = m.position
	Input.parse_input_event(u)

## Left click = fire the selected kind, right click = water. Waits two frames so the camera/mouse state is current.
func shoot(world_pos: Vector2, water: bool = false) -> void:
	mouse_button(MOUSE_BUTTON_RIGHT if water else MOUSE_BUTTON_LEFT, world_pos)
	await process_frame
	await process_frame

func teleport(p: Vector2) -> void:
	main.player.simulation_position = p
	await ticks(3)
	await process_frame
	await process_frame

func player_pos() -> Vector2:
	return main.player.simulation_position

func foot_hits_block(w: WorldState, p: Vector2) -> bool:
	var l: float = p.x - HALF.x
	var r: float = p.x + HALF.x
	var t: float = p.y - HALF.y
	var b: float = p.y + HALF.y
	if l < -1e-6 or t < -1e-6 or r > w.width * T + 1e-6 or b > w.height * T + 1e-6:
		return true
	for ty: int in range(maxi(floori(t / T) - 1, 0), mini(floori(b / T) + 2, w.height)):
		for tx: int in range(maxi(floori(l / T) - 1, 0), mini(floori(r / T) + 2, w.width)):
			var def: TerrainDef = w.terrain_defs[w.terrain[ty * w.width + tx]]
			if def.walkable:
				continue
			var ox: float = minf(r, (tx + 1) * T) - maxf(l, tx * T)
			var oy: float = minf(b, (ty + 1) * T) - maxf(t, ty * T)
			if ox > 1e-4 and oy > 1e-4:
				return true
	return false

func stage_count(stage: int) -> int:
	var n: int = 0
	for s: int in main.grid.stage:
		if s == stage:
			n += 1
	return n

func natural_count() -> int:
	var n: int = 0
	for v: int in main.grid.natural:
		n += v
	return n

func plant_fruits() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for item: Dictionary in main.play.pickups.items:
		if String(item["kind"]) == GroundPickups.KIND_SEED_FRUIT and int(item["owner"]) >= PLANT_OWNER_BASE:
			list.append(item)
	return list

func source_fruits() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for item: Dictionary in main.play.pickups.items:
		if String(item["kind"]) == GroundPickups.KIND_SEED_FRUIT and int(item["owner"]) < PLANT_OWNER_BASE:
			list.append(item)
	return list

## Lattice path (tile centres where the 6x4 feet fit) from the player to the nearest goal; used only to decide which
## keys to press. Returns waypoints in px.
func plan(from: Vector2, goal_fn: Callable) -> Array[Vector2]:
	var w: WorldState = main.grid
	var start: Vector2i = Vector2i(floori(from.x / T), floori(from.y / T))
	var parent: Dictionary = {start: Vector2i(-1, -1)}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	var found: Vector2i = Vector2i(-1, -1)
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if goal_fn.call(c):
			found = c
			break
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if parent.has(n) or not w.in_bounds(n.x, n.y):
				continue
			if foot_hits_block(w, (Vector2(n) + Vector2(0.5, 0.5)) * T):
				continue
			parent[n] = c
			queue.append(n)
	var path: Array[Vector2] = []
	if found.x < 0:
		return path
	var cur: Vector2i = found
	while cur != Vector2i(-1, -1):
		path.append((Vector2(cur) + Vector2(0.5, 0.5)) * T)
		cur = parent[cur]
	path.reverse()
	return path

## Steers along a plan with injected WASD until `done_fn` is true or the timeout passes. Returns true when done_fn held.
func walk_path(path: Array[Vector2], done_fn: Callable, timeout_s: float) -> bool:
	var index: int = 0
	var limit: int = roundi(timeout_s * hz)
	for i: int in limit:
		if done_fn.call():
			release_all()
			return true
		var p: Vector2 = player_pos()
		while index < path.size() - 1 and p.distance_to(path[index]) < 2.5:
			index += 1
		var goal: Vector2 = path[mini(index, path.size() - 1)] if not path.is_empty() else p
		var d: Vector2 = goal - p
		var codes: Array = []
		if d.x > 0.9:
			codes.append(KEY_D)
		elif d.x < -0.9:
			codes.append(KEY_A)
		if d.y > 0.9:
			codes.append(KEY_S)
		elif d.y < -0.9:
			codes.append(KEY_W)
		hold(codes)
		await physics_frame
		tick_count += 1
	release_all()
	return done_fn.call()

func find_planting_spot(near: Vector2, min_d: float, max_d: float, skip: Array[Vector2] = []) -> Vector2:
	var w: WorldState = main.grid
	var best: Vector2 = Vector2.INF
	var best_n: int = 0
	for angle_i: int in 24:
		var angle: float = TAU * angle_i / 24.0
		for dist: float in [min_d, (min_d + max_d) * 0.5, max_d]:
			var p: Vector2 = near + Vector2.from_angle(angle) * dist
			var blocked: bool = false
			for other: Vector2 in skip:
				if p.distance_to(other) < 40.0:
					blocked = true
			if blocked:
				continue
			var n: int = 0
			for idx: int in Landing.tiles_in_radius(w, T, p, 10.0):
				if w.can_plant(idx) and w.moisture[idx] == 0:
					n += 1
			if n > best_n:
				best_n = n
				best = p
			if best_n >= 10:
				return best
	return best

func tiles_near(point: Vector2, radius: float) -> PackedInt32Array:
	return Landing.tiles_in_radius(main.grid, T, point, radius)

func hash_world() -> String:
	var g: WorldState = main.grid
	return "%d/%d/%d/%d/%d" % [hash(g.stage), hash(g.growth), hash(g.moisture), hash(g.natural), g.greened_count]

# ------------------------------------------------------------------------------------------ walk

func t_walk() -> void:
	await new_main()
	var w: WorldState = main.grid
	var invariants_bad: int = 0
	var invariant_n: int = 0
	var track: Array = []
	# A: the river edge on row 100 with sliding, scripted 0.5 s segments of WASD
	await teleport(Vector2(940.0, 402.0))
	var segments: Array = [[KEY_D, KEY_S], [KEY_D, KEY_S], [KEY_S], [KEY_D], [KEY_D, KEY_W], [KEY_D, KEY_W], [KEY_A, KEY_S], [KEY_A, KEY_S], [KEY_W], [KEY_D, KEY_S], [KEY_D], [KEY_D, KEY_S], [KEY_A], [KEY_A, KEY_W], [KEY_S], [KEY_S, KEY_D]]
	var per_seg: int = hz / 2
	for seg: Array in segments:
		hold(seg)
		for i: int in per_seg:
			await physics_frame
			tick_count += 1
			invariant_n += 1
			if foot_hits_block(w, player_pos()):
				invariants_bad += 1
		track.append([snappedf(player_pos().x, 0.001), snappedf(player_pos().y, 0.001)])
	release_all()
	observations["route_%d" % hz] = track
	rec("walk.route_never_inside", "hz=%d: along the river edge with held WASD combos the feet never overlap water/buildings (every tick)" % hz, invariants_bad == 0, "bad %d of %d" % [invariants_bad, invariant_n])
	# B: east along ford rows, held D for 6 s
	var ford_end: Array = []
	for fy: int in [62, 202, 324]:
		await teleport(Vector2(900.0, fy * T + 4.0))
		hold([KEY_D])
		await seconds(6.0)
		release_all()
		ford_end.append(player_pos().x)
	rec("walk.fords_cross", "hz=%d: holding D along three ford rows carries the player across the river (x > 1160)" % hz, ford_end[0] > 1160.0 and ford_end[1] > 1160.0 and ford_end[2] > 1160.0, str(ford_end))
	# C: non-ford row stops at the water edge
	await teleport(Vector2(900.0, 402.0))
	hold([KEY_D])
	await seconds(5.0)
	release_all()
	rec("walk.river_stop", "hz=%d: holding D on a non-ford row stops at the water edge (x = 981)" % hz, absf(player_pos().x - 981.0) < 0.01, str(player_pos()))
	# D: ruin building
	await teleport(Vector2(520.0, 712.0))
	hold([KEY_D])
	await seconds(3.0)
	release_all()
	rec("walk.ruin_stop", "hz=%d: holding D stops at the ruin building edge (x = 545)" % hz, absf(player_pos().x - 545.0) < 0.01, str(player_pos()))
	# E: speed on open ground, straight and diagonal
	await teleport(Vector2(1500.0, 1000.0))
	var p0: Vector2 = player_pos()
	hold([KEY_D, KEY_S])
	await seconds(1.0)
	release_all()
	var diag: float = player_pos().distance_to(p0)
	await teleport(Vector2(1500.0, 1000.0))
	p0 = player_pos()
	hold([KEY_D])
	await seconds(1.0)
	release_all()
	var straight: float = player_pos().distance_to(p0)
	rec("walk.speed_equal", "hz=%d: 1 s of D+S covers the same distance as 1 s of D (96 px, within one tick step)" % hz, absf(diag - 96.0) <= 96.0 / hz + 0.1 and absf(straight - 96.0) <= 96.0 / hz + 0.1 and absf(diag - straight) < 0.5, "diag=%.3f straight=%.3f" % [diag, straight])
	# F: map edge
	await teleport(Vector2(40.0, 1000.0))
	hold([KEY_A])
	await seconds(2.0)
	release_all()
	rec("walk.edge_stop", "hz=%d: the 32 px world margin still stops the player at the edge" % hz, absf(player_pos().x - 32.0) < 0.01, str(player_pos()))
	# G: presentation follows (position == round(simulation_position))
	rec("walk.presentation_round", "player node position is the rounded simulation position", main.player.position == main.player.simulation_position.round(), "%s vs %s" % [main.player.position, main.player.simulation_position])

# ------------------------------------------------------------------------------------------ pause

func t_pause() -> void:
	await new_main()
	var w: WorldState = main.grid
	var play: PlayState = main.play
	# growing seeds + water + carrot + kiwi + spread active, player beside the shore with half-empty gauge
	var spot: Vector2 = find_planting_spot(player_pos(), 70.0, 110.0)
	await shoot(spot)
	await shoot(spot, true)
	await seconds(2.0)
	var carrot_idx: int = 0
	main.play.select_index(1)
	await shoot(player_pos() + Vector2(-20, 0))
	main.play.select_index(2)
	await shoot(player_pos() + Vector2(0, -25))
	main.play.select_index(0)
	await seconds(10.0)
	play.damage_player(3)
	# move to the river bank: shore tile with waterside within 2 tiles, then water to 50
	var path: Array[Vector2] = plan(player_pos(), func(c: Vector2i) -> bool: return w.terrain[c.y * w.width + c.x] == 2)
	var arrived: bool = await walk_path(path, func() -> bool: return w.terrain[floori(player_pos().y / T) * w.width + floori(player_pos().x / T)] == 2, 40.0)
	play.water = 50.0
	await seconds(0.5)
	rec("pause.setup", "setup: seeds planted, carrot and kiwi placed, standing on shore (refilling), spread active", arrived and play.cultivation.plants.size() == 2 and play.refilling and stage_count(1) + stage_count(2) > 0, "arrived=%s plants=%d refilling=%s water=%.1f" % [arrived, play.cultivation.plants.size(), play.refilling, play.water])
	# land more seeds so there are in-flight shots at pause time
	play.water = 50.0
	var snap_before: Dictionary = snapshot()
	var plant_ages: Array = []
	for plant: CultivatedPlant in play.cultivation.plants:
		plant_ages.append(plant.to_dict())
	key_tap(KEY_ESCAPE)
	await ticks(2)
	rec("pause.paused", "Esc pauses the tree", paused, "paused=%s" % paused)
	var s_at_pause: Dictionary = snapshot()
	# try everything while paused
	hold([KEY_D, KEY_S])
	await shoot(player_pos() + Vector2(30, 30))
	await shoot(player_pos() + Vector2(30, 30), true)
	await ticks(roundi(10.0 * hz))
	release_all()
	var s_after: Dictionary = snapshot()
	var same: bool = true
	var diffs: String = ""
	for k: String in s_at_pause:
		if str(s_at_pause[k]) != str(s_after[k]):
			same = false
			diffs += " %s: %s -> %s;" % [k, s_at_pause[k], s_after[k]]
	rec("pause.frozen", "10 s paused with held keys, clicks and a refill spot: world, growth, moisture, natural, seeds, water, pickups, plants, time, player all unchanged", same, diffs if not same else JSON.stringify(s_after).substr(0, 300))
	key_tap(KEY_ESCAPE)
	await ticks(3)
	rec("pause.resumed", "Esc resumes", not paused, "")
	var t_resume: float = play.elapsed
	await ticks(hz)
	var advanced: float = play.elapsed - float(s_after["elapsed"])
	rec("pause.no_banked_time", "after resuming, 1 s of ticks advances game time by about 1 s (no catch-up of the 10 s pause)", advanced > 0.9 and advanced < 1.2, "advanced %.3f s" % advanced)
	var clock_adv: float = main.simulation.clock.elapsed - float(s_after["clock"])
	rec("pause.clock_no_catchup", "the simulation clock also advanced about 1 s", clock_adv > 0.9 and clock_adv < 1.2, "clock advanced %.3f" % clock_adv)
	# gauge: refill continues after resume
	rec("pause.refill_after", "water refill works again after resume (gauge went up)", play.water > float(s_after["water"]), "%.1f -> %.1f" % [float(s_after["water"]), play.water])

func snapshot() -> Dictionary:
	var play: PlayState = main.play
	var plants: Array = []
	for plant: CultivatedPlant in play.cultivation.plants:
		plants.append(JSON.stringify(plant.to_dict()))
	var items: Array = []
	for item: Dictionary in play.pickups.items:
		items.append(JSON.stringify(item))
	return {"world": hash_world(), "seeds": play.seeds, "water": snappedf(play.water, 0.0001), "hp": play.hp, "elapsed": snappedf(play.elapsed, 0.00001), "clock": snappedf(main.simulation.clock.elapsed, 0.00001), "pickups": hash(items), "plants": hash(plants), "player": str(player_pos()), "production": play.production_ticks, "shots": main.projectile_view.shots.size()}

# ------------------------------------------------------------------------------------------ chain (landing -> growth -> fruit -> collect -> refire)

func t_chain() -> void:
	await new_main()
	var w: WorldState = main.grid
	var play: PlayState = main.play
	var start: Vector2 = player_pos()
	rec("chain.start", "start: 20 seeds, water 100, HP full, standing at the start tile", play.seeds == 20 and play.water == 100.0 and start == Vector2(738, 754), "seeds=%d water=%.0f pos=%s" % [play.seeds, play.water, start])
	# five wasteland spots 85..115 px away
	var spots: Array[Vector2] = []
	for i: int in 5:
		var spot: Vector2 = find_planting_spot(start, 85.0, 115.0, spots)
		spots.append(spot)
	var t_landed0: float = play.elapsed
	var planted_tiles: Array[int] = []
	for spot: Vector2 in spots:
		var before: int = landed_n
		await shoot(spot)
		await seconds(1.0)
		for idx: int in play.last_scatter:
			planted_tiles.append(idx)
		rec("chain.land_%d" % planted_tiles.size(), "a left click lands a seed near the aim point (landed signal fired)", landed_n == before + 1, "scatter %d" % play.last_scatter.size())
	rec("chain.seeds_spent", "5 shots spent exactly 5 seeds", play.seeds == 15, "%d" % play.seeds)
	var all_seed: bool = planted_tiles.size() >= 15
	var seeds_ok: bool = true
	for idx: int in planted_tiles:
		if w.stage[idx] < WorldState.STAGE_SEED:
			seeds_ok = false
	rec("chain.seed_tiles", "landing planted tiles (stage seed or later) for every shot", all_seed and seeds_ok, "%d tiles" % planted_tiles.size())
	# watch the stages of the planted tiles
	var t1: Dictionary = {}
	var t2: Dictionary = {}
	var t3: Dictionary = {}
	var first_fruit_time: float = -1.0
	var base: float = play.elapsed
	for i: int in roundi(240.0 * hz):
		await physics_frame
		tick_count += 1
		for idx: int in planted_tiles:
			var s: int = w.stage[idx]
			if s >= 2 and not t1.has(idx):
				t1[idx] = play.elapsed - base
			if s >= 3 and not t2.has(idx):
				t2[idx] = play.elapsed - base
			if s >= 4 and not t3.has(idx):
				t3[idx] = play.elapsed - base
		if first_fruit_time < 0.0 and not plant_fruits().is_empty():
			first_fruit_time = play.elapsed - base
		if first_fruit_time >= 0.0 and t3.size() == planted_tiles.size():
			break
	var median := func(d: Dictionary) -> float:
		var v: Array = d.values()
		v.sort()
		return float(v[v.size() / 2]) if not v.is_empty() else -1.0
	var m1: float = median.call(t1)
	var m2: float = median.call(t2)
	var m3: float = median.call(t3)
	observations["chain_times"] = {"sprout1": m1, "sprout2": m2, "mature": m3, "first_fruit": first_fruit_time}
	rec("chain.stages_in_order", "seed -> sprout 1 -> sprout 2 -> mature in this order for every tile", t1.size() == planted_tiles.size() and t3.size() == planted_tiles.size() and m1 < m2 and m2 < m3, "median t1=%.1f t2=%.1f t3=%.1f s (n=%d)" % [m1, m2, m3, t3.size()])
	rec("chain.dry_time", "dry growth takes about one minute (30..90 s) to mature", m3 > 30.0 and m3 < 90.0, "%.1f s" % m3)
	rec("chain.fruit_appears", "mature planted tiles drop a plant seed fruit", first_fruit_time > 0.0, "first fruit %.1f s after landing" % first_fruit_time)
	# no plant fruit may come from the safe zone's ready-made plants (natural-spread tiles and my tiles may produce)
	var near_ok: bool = true
	var from_safe: int = 0
	for f: Dictionary in plant_fruits():
		var tile_index: int = int(f["owner"]) - PLANT_OWNER_BASE
		if w.terrain[tile_index] == 1 or w.fruitless[tile_index] == 1:
			near_ok = false
			from_safe += 1
	rec("chain.fruit_not_from_safe", "no plant fruit belongs to a safe-zone / fruitless tile (only regrown and planted tiles produce)", near_ok, "fruits %d, from safe %d" % [plant_fruits().size(), from_safe])
	# collect: steer by injected WASD to the nearest plant fruit
	var seeds_before: int = play.seeds
	var collected: bool = false
	for attempt: int in 6:
		var fruits: Array[Dictionary] = plant_fruits()
		if fruits.is_empty():
			await seconds(5.0)
			continue
		var target: Vector2 = Vector2(float(fruits[0]["x"]), float(fruits[0]["y"]))
		var fx: Callable = func(c: Vector2i) -> bool: return Vector2((c.x + 0.5) * T, (c.y + 0.5) * T).distance_to(target) < 8.0
		var path: Array[Vector2] = plan(player_pos(), fx)
		var got: bool = await walk_path(path, func() -> bool: return play.seeds > seeds_before, 30.0)
		if got:
			collected = true
			break
	rec("chain.collect", "walking onto the plant fruit (WASD) returns a seed", collected, "seeds %d -> %d" % [seeds_before, play.seeds])
	# re-fire
	var spot2: Vector2 = find_planting_spot(player_pos(), 60.0, 110.0, spots)
	var seeds_b2: int = play.seeds
	var green_b: int = w.greened_count
	await shoot(spot2)
	await seconds(1.5)
	rec("chain.refire", "the collected seed can be fired again and plants new tiles", play.seeds == seeds_b2 - 1 and play.last_scatter.size() >= 1, "seeds %d -> %d, scatter %d" % [seeds_b2, play.seeds, play.last_scatter.size()])
	rec("chain.counters", "greening counters stay consistent after the whole chain", w.counters_consistent(), "greened %d (was %d)" % [w.greened_count, green_b])

# ------------------------------------------------------------------------------------------ water

func t_water() -> void:
	await new_main()
	var w: WorldState = main.grid
	var play: PlayState = main.play
	var home: Vector2 = Vector2(1500.0, 1000.0)
	await teleport(home)
	var spot_a: Vector2 = home + Vector2(-95, 0)
	var spot_b: Vector2 = home + Vector2(95, 0)
	var spot_c: Vector2 = home + Vector2(0, -100)
	rec("water.setup", "open wasteland test site: no waterside near, water 100, not refilling", play.water == 100.0 and not play.refilling, "%.0f %s" % [play.water, play.refilling])
	# A: plant and water x3
	await shoot(spot_a)
	await seconds(1.0)
	var tiles_a: Array[int] = []
	for idx: int in play.last_scatter:
		tiles_a.append(idx)
	var t_a: float = play.elapsed
	for i: int in 3:
		await shoot(spot_a, true)
		await seconds(0.8)
	var wet_a: int = 0
	for idx: int in tiles_a:
		if w.moisture[idx] > 0:
			wet_a += 1
	rec("water.wets", "3 water shots wet the planted tiles", wet_a == tiles_a.size() and tiles_a.size() > 0, "wet %d/%d, water gauge %.0f" % [wet_a, tiles_a.size(), play.water])
	# drain the gauge into a harmless spot (C), then confirm a click does nothing
	var guard: int = 0
	while play.can_fire_water() and guard < 20:
		await shoot(spot_c, true)
		await seconds(0.2)
		guard += 1
	var shots_before: int = main.projectile_view.shots.size()
	var water_before: float = play.water
	await shoot(spot_c, true)
	rec("water.zero", "water gauge is empty (< one shot) and a water click fires nothing", play.water < play.tuning.water_cost_per_shot and main.projectile_view.shots.size() == shots_before and absf(play.water - water_before) < 1e-6, "water %.1f" % play.water)
	# B: plant with the gauge empty
	await shoot(spot_b)
	await seconds(1.0)
	var tiles_b: Array[int] = []
	for idx: int in play.last_scatter:
		tiles_b.append(idx)
	var t_b: float = play.elapsed
	rec("water.b_planted", "seeds plant fine with the gauge empty", tiles_b.size() >= 1 and play.water < 10.0, "tiles %d water %.1f" % [tiles_b.size(), play.water])
	var ma: Dictionary = {}
	var mb: Dictionary = {}
	for i: int in roundi(120.0 * hz):
		await physics_frame
		tick_count += 1
		for idx: int in tiles_a:
			if w.stage[idx] >= 4 and not ma.has(idx):
				ma[idx] = play.elapsed - t_a
		for idx: int in tiles_b:
			if w.stage[idx] >= 4 and not mb.has(idx):
				mb[idx] = play.elapsed - t_b
		if ma.size() == tiles_a.size() and mb.size() == tiles_b.size():
			break
	var va: Array = ma.values()
	var vb: Array = mb.values()
	va.sort()
	vb.sort()
	var med_a: float = float(va[va.size() / 2]) if not va.is_empty() else -1.0
	var med_b: float = float(vb[vb.size() / 2]) if not vb.is_empty() else -1.0
	observations["water_times"] = {"watered": med_a, "dry": med_b}
	rec("water.dry_grows", "without any water the dry seeds still mature (about a minute)", mb.size() == tiles_b.size() and med_b > 40.0 and med_b < 80.0, "median %.1f s, %d/%d mature" % [med_b, mb.size(), tiles_b.size()])
	rec("water.faster", "watered seeds mature clearly earlier than dry ones (at least 10 s sooner)", ma.size() == tiles_a.size() and med_a > 0.0 and med_a < med_b - 10.0, "watered %.1f s vs dry %.1f s" % [med_a, med_b])

# ------------------------------------------------------------------------------------------ recover

func t_recover() -> void:
	await new_main()
	var w: WorldState = main.grid
	var play: PlayState = main.play
	var start: Vector2 = player_pos()
	# spend all 20 seeds
	var spots: Array[Vector2] = []
	var fired: int = 0
	for i: int in 20:
		var spot: Vector2 = find_planting_spot(start, 70.0, 115.0, spots)
		if spot == Vector2.INF:
			spot = start + Vector2.from_angle(i * 0.9) * 100.0
		spots.append(spot)
		await shoot(spot)
		fired += 1
		await seconds(0.1)
	await seconds(1.5)
	rec("recover.seeds_zero", "20 clicks spend all 20 seeds", play.seeds == 0, "seeds %d" % play.seeds)
	var shots0: int = main.projectile_view.shots.size()
	await shoot(start + Vector2(60, 60))
	rec("recover.no_fire_at_zero", "with 0 seeds a click fires nothing", main.projectile_view.shots.size() == shots0 and play.seeds == 0, "")
	# drain water
	var guard: int = 0
	while play.can_fire_water() and guard < 20:
		await shoot(start + Vector2(-100, 0), true)
		await seconds(0.15)
		guard += 1
	await seconds(1.5)
	rec("recover.water_zero", "10 right clicks empty the water gauge", play.water < 10.0, "water %.1f" % play.water)
	# SEED RECOVERY: wait at the source: fruits appear (source cap 3), walk onto them with WASD
	var seeds_b: int = play.seeds
	var path: Array[Vector2] = plan(player_pos(), func(c: Vector2i) -> bool: return Vector2((c.x + 0.5) * T, (c.y + 0.5) * T).distance_to(play.sources[0].position + Vector2(0, 14)) < 6.0)
	await walk_path(path, func() -> bool: return false, 3.0)
	var got: int = 0
	for round_i: int in 6:
		var fr: Array[Dictionary] = source_fruits()
		if fr.is_empty():
			await seconds(3.0)
			continue
		var target: Vector2 = Vector2(float(fr[0]["x"]), float(fr[0]["y"]))
		var p2: Array[Vector2] = plan(player_pos(), func(c: Vector2i) -> bool: return Vector2((c.x + 0.5) * T, (c.y + 0.5) * T).distance_to(target) < 6.0)
		var before: int = play.seeds
		var ok: bool = await walk_path(p2, func() -> bool: return play.seeds > before, 20.0)
		if ok:
			got += 1
		if got >= 2:
			break
	rec("recover.seed_from_source", "from 0 seeds, walking onto the seed source's fruits gives seeds again", play.seeds >= 2 and got >= 2, "seeds 0 -> %d (collected %d)" % [play.seeds, got])
	var green_b: int = w.greened_count
	var seeds_c: int = play.seeds
	var spot3: Vector2 = find_planting_spot(player_pos(), 70.0, 115.0, spots)
	if spot3 == Vector2.INF:
		spot3 = find_planting_spot(player_pos(), 15.0, 119.0, [])
	rec("recover.spot", "a free planting spot exists for the re-fire", spot3 != Vector2.INF, str(spot3))
	await shoot(spot3)
	var seeds_after_click: int = play.seeds
	await seconds(1.5)
	rec("recover.refire", "the recovered seed plants new ground", seeds_after_click == seeds_c - 1 and play.last_scatter.size() >= 1, "seeds %d -> %d right after the click, scatter %d" % [seeds_c, seeds_after_click, play.last_scatter.size()])
	# WATER RECOVERY 1: shore
	var wpath: Array[Vector2] = plan(player_pos(), func(c: Vector2i) -> bool: return w.terrain[c.y * w.width + c.x] == 2)
	var w_before: float = play.water
	var shore_ok: bool = await walk_path(wpath, func() -> bool: return play.water >= 50.0, 60.0)
	var tile_here: int = w.terrain[floori(player_pos().y / T) * w.width + floori(player_pos().x / T)]
	rec("recover.water_shore", "walking to the shore refills the empty gauge (25/s) to 50", shore_ok, "water %.1f -> %.1f at terrain %d tile %s" % [w_before, play.water, tile_here, player_pos() / T])
	var wb: float = play.water
	await shoot(player_pos() + Vector2(0, 50), true)
	rec("recover.water_fire", "water can be fired again after the refill", play.water < wb, "%.1f -> %.1f" % [wb, play.water])
	# WATER RECOVERY 2: stand in the middle of a ford (nothing but shallows within 2 tiles)
	guard = 0
	while play.can_fire_water() and guard < 20:
		await shoot(player_pos() + Vector2(0, 50), true)
		await seconds(0.1)
		guard += 1
	await seconds(1.0)
	# find a path to the ford 2 centre (tile 258,202.5) over shallows only: goal is the row-202 shallows tile at x=258
	var fpath: Array[Vector2] = plan(player_pos(), func(c: Vector2i) -> bool: return c == Vector2i(258, 202))
	var on_ford: bool = await walk_path(fpath, func() -> bool: return player_pos().distance_to(Vector2(258.5 * T, 202.5 * T)) < 3.0, 90.0)
	var wlow: float = play.water
	var far_from_land: bool = true
	var cx: int = 258
	var cy: int = 202
	for dy: int in range(-2, 3):
		for dx: int in range(-2, 3):
			if dx * dx + dy * dy <= 4 and not (w.terrain[(cy + dy) * w.width + cx + dx] == 5):
				far_from_land = false
	# drain again (it refilled on the way if near shore) and hold still on the ford
	guard = 0
	while play.can_fire_water() and guard < 20:
		await shoot(player_pos() + Vector2(0, 40), true)
		await seconds(0.1)
		guard += 1
	var w0: float = play.water
	await seconds(2.0)
	rec("recover.water_shallows", "standing on the shallows (all tiles within 2 tiles are shallows, no shore/land) refills the gauge: waterside includes shallows", on_ford and far_from_land and play.water > w0 + 20.0, "on_ford=%s pure_shallows_area=%s water %.1f -> %.1f at %s" % [on_ford, far_from_land, w0, play.water, player_pos() / T])
	rec("recover.counters", "counters consistent", w.counters_consistent(), "greened %d (was %d)" % [w.greened_count, green_b])

# ------------------------------------------------------------------------------------------ spread / carrot (control)

func t_spread(with_carrot: bool, control_label: bool) -> void:
	await new_main()
	var w: WorldState = main.grid
	var play: PlayState = main.play
	var series: Dictionary = {}
	var first_seed_t: float = -1.0
	var first_mature_t: float = -1.0
	var placed_at: float = 0.0
	if with_carrot:
		key_tap(KEY_TAB)
		await ticks(2)
		rec("carrot.select", "Tab selects the carrot", play.selected_def().key == &"carrot", String(play.selected_def().key))
		var seeds_b: int = play.seeds
		# aim at the safe-zone middle (all mature) so a 2x2 block fits
		await shoot(player_pos() + Vector2(-10, -10))
		await seconds(0.5)
		rec("carrot.placed", "a carrot is placed on the mature safe ground and costs 3 seeds", play.cultivation.count(&"carrot") == 1 and play.seeds == seeds_b - 3, "carrots %d seeds %d -> %d" % [play.cultivation.count(&"carrot"), seeds_b, play.seeds])
		rec("carrot.counter_unchanged", "placing the carrot changes no greening counters (mature ground stays mature)", w.greened_count == 331 and w.mature_count == 331, "%d/%d" % [w.greened_count, w.mature_count])
	var base_n: int = natural_count()
	var checkpoints: Array[int] = [20, 40, 60, 80, 100, 120, 160, 200]
	var cp: int = 0
	var t0: float = main.simulation.clock.elapsed
	var shots: Dictionary = {}
	for i: int in roundi(200.5 * hz):
		await physics_frame
		tick_count += 1
		var tt: float = main.simulation.clock.elapsed - t0
		if first_seed_t < 0.0 and natural_count() > base_n:
			first_seed_t = tt
		if first_mature_t < 0.0 and stage_natural_mature() > 0:
			first_mature_t = tt
		if cp < checkpoints.size() and tt >= checkpoints[cp]:
			shots[str(checkpoints[cp])] = {"natural": natural_count(), "mature_total": w.mature_count, "greened": w.greened_count}
			cp += 1
	var key: String = "carrot" if with_carrot else "control"
	observations["spread_" + key] = {"first_seed_t": first_seed_t, "first_mature_t": first_mature_t, "series": shots}
	rec("spread.%s.starts" % key, "natural spread from the safe zone plants tiles by itself (no input)", first_seed_t > 0.0 and natural_count() > 0, "first natural seed at %.1f s, natural now %d" % [first_seed_t, natural_count()])
	rec("spread.%s.matures" % key, "naturally planted tiles grow up to mature within 200 s", first_mature_t > 0.0, "first natural mature %.1f s" % first_mature_t)
	rec("spread.%s.counters" % key, "counters consistent; greened >= 331 and monotonic with natural tiles", w.counters_consistent() and w.greened_count >= 331, "greened %d" % w.greened_count)
	# all natural tiles are on plantable terrain
	var bad: int = 0
	for i: int in w.tile_count():
		if w.natural[i] == 1 and (w.target[i] == 0 or not w.terrain_defs[w.terrain[i]].plantable):
			bad += 1
	rec("spread.%s.only_targets" % key, "natural tiles lie only on plantable target terrain (never water, buildings, shallows)", bad == 0, "bad %d" % bad)

func stage_natural_mature() -> int:
	var g: WorldState = main.grid
	var n: int = 0
	for i: int in g.tile_count():
		if g.natural[i] == 1 and g.stage[i] == 4:
			n += 1
	return n

# ------------------------------------------------------------------------------------------ kiwi

func t_kiwi() -> void:
	await new_main()
	var w: WorldState = main.grid
	var play: PlayState = main.play
	key_tap(KEY_TAB)
	key_tap(KEY_TAB)
	await ticks(2)
	rec("kiwi.select", "Tab twice selects the kiwi", play.selected_def().key == &"kiwi", String(play.selected_def().key))
	await shoot(player_pos() + Vector2(-12, -12))
	await seconds(0.5)
	rec("kiwi.placed", "a kiwi is placed on the safe ground", play.cultivation.count(&"kiwi") == 1, "%d" % play.cultivation.count(&"kiwi"))
	await teleport(Vector2(738.0, 800.0))
	var damaged: int = play.damage_player(4)
	rec("kiwi.damaged", "HP lowered through the official damage entry (P2 will use it)", play.hp == play.hp_max - 4, "hp %d" % play.hp)
	var heal_seen: float = -1.0
	var t0: float = play.elapsed
	for i: int in roundi(120.0 * hz):
		await physics_frame
		tick_count += 1
		if heal_seen < 0.0 and play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT) > 0:
			heal_seen = play.elapsed - t0
			break
	rec("kiwi.fruit", "the mature kiwi drops a healing fruit within 120 s", heal_seen > 0.0, "after %.1f s" % heal_seen)
	var hp_b: int = play.hp
	var healed: bool = false
	var item_target: Vector2 = Vector2.ZERO
	for item: Dictionary in play.pickups.items:
		if String(item["kind"]) == GroundPickups.KIND_HEAL_FRUIT:
			item_target = Vector2(float(item["x"]), float(item["y"]))
	if heal_seen > 0.0:
		var path: Array[Vector2] = plan(player_pos(), func(c: Vector2i) -> bool: return Vector2((c.x + 0.5) * T, (c.y + 0.5) * T).distance_to(item_target) < 6.0)
		healed = await walk_path(path, func() -> bool: return play.hp > hp_b, 25.0)
	rec("kiwi.heals", "walking onto the healing fruit restores HP (+2)", healed and play.hp == hp_b + 2, "hp %d -> %d" % [hp_b, play.hp])

# ------------------------------------------------------------------------------------------ invalid shots

func t_invalid() -> void:
	await new_main()
	var w: WorldState = main.grid
	var play: PlayState = main.play
	var g0: int = w.greened_count
	var nat0: int = natural_count()
	var stage0: int = hash(w.stage)
	# targets: open water, ruin building, shallows (ford 2 centre)
	var water_pt: Vector2 = Vector2.INF
	for y: int in range(150, 300):
		for x: int in range(248, 262):
			var ok: bool = true
			for dy: int in range(-3, 4):
				for dx: int in range(-3, 4):
					if w.terrain[(y + dy) * w.width + x + dx] != 3:
						ok = false
			if ok and water_pt == Vector2.INF:
				water_pt = Vector2((x + 0.5) * T, (y + 0.5) * T)
	var building_pt: Vector2 = Vector2(147.5 * T, 179.5 * T)
	var shallow_pt: Vector2 = Vector2(258.5 * T, 202.5 * T)
	rec("invalid.points", "test points: open water, ruin building, ford shallows", water_pt != Vector2.INF and w.terrain[179 * w.width + 147] == 4 and w.terrain[202 * w.width + 258] == 5, "water %s" % water_pt)
	var plan_list: Array = [[water_pt, 2], [building_pt, 2], [shallow_pt, 2]]
	var moist0: int = hash(w.moisture)
	var seeds_start: int = play.seeds
	var fired: int = 0
	for entry: Array in plan_list:
		var target: Vector2 = entry[0]
		# stand 50 px away on legal ground, fire 7 seeds and 3 waters at the point
		var stand: Vector2 = Vector2.INF
		for angle_i: int in 16:
			var cand: Vector2 = target + Vector2.from_angle(TAU * angle_i / 16.0) * 55.0
			if not foot_hits_block(w, cand):
				stand = cand
				break
		if stand == Vector2.INF:
			continue
		await teleport(stand)
		for i: int in 5:
			await shoot(target)
			fired += 1
		for i: int in 3:
			await shoot(target, true)
		await seconds(1.5)
	rec("invalid.fired", "15 seed shots and 9 water shots were really fired (seeds spent, 5 kept for the carrot test)", play.seeds == seeds_start - fired and fired == 15, "fired %d, seeds %d" % [fired, play.seeds])
	# nothing changed in the tiles around the targets
	var changed: int = 0
	for target: Vector2 in [water_pt, building_pt, shallow_pt]:
		for idx: int in tiles_near(target, 30.0):
			var tile_terrain: int = w.terrain[idx]
			if tile_terrain in [3, 4, 5] and (w.stage[idx] != 0 or w.moisture[idx] != 0):
				changed += 1
	rec("invalid.no_change", "no water/building/shallows tile around the targets got a plant or moisture", changed == 0, "changed %d" % changed)
	# carrot at non-target ground: refused, seeds kept
	play.select_index(1)
	var seeds_c: int = play.seeds
	for target: Vector2 in [water_pt, building_pt, shallow_pt]:
		var stand2: Vector2 = Vector2.INF
		for angle_i: int in 16:
			var cand2: Vector2 = target + Vector2.from_angle(TAU * angle_i / 16.0) * 55.0
			if not foot_hits_block(w, cand2):
				stand2 = cand2
				break
		await teleport(stand2)
		await shoot(target)
		await seconds(1.5)
	rec("invalid.carrot", "carrots shot at water, building and shallows place nothing and keep the seeds", play.cultivation.count(&"carrot") == 0 and play.seeds == seeds_c and play.reserved_seeds == 0, "carrots %d seeds %d/%d reserved %d" % [play.cultivation.count(&"carrot"), play.seeds, seeds_c, play.reserved_seeds])
	var g1: int = w.greened_count
	var player_made: int = 0
	var green_player: int = 0
	for i: int in w.tile_count():
		if w.stage[i] != 0 and w.natural[i] == 0 and w.terrain[i] != 1:
			player_made += 1
		if w.stage[i] >= 2 and w.natural[i] == 0:
			green_player += 1
	rec("invalid.greened", "no tile outside the safe zone was planted by the player's shots, and the greened count of non-natural tiles is still the 331 safe tiles", player_made == 0 and green_player == 331 and g0 == 331, "player-planted %d, green(non-natural) %d, greened %d (natural spread may add: natural %d -> %d)" % [player_made, green_player, g1, nat0, natural_count()])
	# 10 more seconds: still nothing (also catches deferred effects)
	await seconds(10.0)
	var player_made2: int = 0
	for i: int in w.tile_count():
		if w.stage[i] != 0 and w.natural[i] == 0 and w.terrain[i] != 1:
			player_made2 += 1
	rec("invalid.later", "10 s later still no player-planted tile and no moisture anywhere (no deferred growth from the shots)", player_made2 == 0 and hash(w.moisture) == moist0, "")
	rec("invalid.counters", "counters consistent", w.counters_consistent(), "")
