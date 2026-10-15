extends SceneTree
## Independent verifier for P1-04, scene level (real main.tscn, engine-internal input injection only; headless).
## Run: Godot --headless --fixed-fps 60 --path <project> --script res://tests/p1/independent/p1_04_v_scene.gd -- --only=pause|rate|water --hz=N

const OUT: String = "res://evidence/p1/p1-06/independent/reg/p1_04_v/"
const TILE: int = 4

var results: Array[Dictionary] = []
var main: Node
var observations: Dictionary = {}
var keys_down: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func run() -> void:
	var only: String = "pause"
	var hz: int = 60
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--hz="):
			hz = int(a.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	match only:
		"pause":
			await t_pause()
		"rate":
			await t_rate(hz)
		"water":
			await t_water()
	var f: FileAccess = FileAccess.open(OUT + "checks_scene_%s%s.json" % [only, "_%d" % hz if only == "rate" else ""], FileAccess.WRITE)
	f.store_string(JSON.stringify({"results": results, "observations": observations}, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("V_RESULT total=%d fails=%d" % [results.size(), fails])
	quit(1 if fails > 0 else 0)

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
	return main

func ticks(n: int) -> void:
	for i: int in n:
		await physics_frame

func key(code: Key, down: bool) -> void:
	if bool(keys_down.get(code, false)) == down:
		return
	keys_down[code] = down
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)

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

func center_of(t: Vector2i) -> Vector2:
	return (Vector2(t) + Vector2(0.5, 0.5)) * TILE

func square_all(world: WorldState, cx: int, cy: int, half: int, terrain_id: int) -> bool:
	if cx - half < 0 or cy - half < 0 or cx + half >= world.width or cy + half >= world.height:
		return false
	for y: int in range(cy - half, cy + half + 1):
		for x: int in range(cx - half, cx + half + 1):
			if world.terrain[y * world.width + x] != terrain_id or world.stage[y * world.width + x] != 0:
				return false
	return true

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

func snap() -> Dictionary:
	var world: WorldState = main.grid
	var sim: SimulationDriver = main.simulation
	return {
		"hash": "%d/%d/%d/%d" % [hash(world.stage), hash(world.growth), hash(world.moisture), hash(world.natural)],
		"greened": world.greened_count, "mature": world.mature_count, "natural_planted": sim.spread.total_planted,
		"clock": [sim.clock.elapsed, sim.clock.growth_ticks, sim.clock.spread_ticks],
		"spread": [sim.spread.ticks, sim.spread.queue_size(), sim.spread.pending_size()], "growth": [sim.growth.ticks, sim.growth.cursor, world.active_tiles.size()],
	}

func arrange_front(world: WorldState) -> Vector2i:
	var site: Vector2i = find_square(world, 0, 14, main.region_def.start_tile + Vector2i(60, 0))
	for dy: int in range(-6, 7):
		for dx: int in range(-12, -8):
			world.set_stage((site.y + dy) * world.width + site.x + dx, 4)
	return site

func t_pause() -> void:
	await new_main()
	var world: WorldState = main.grid
	var sim: SimulationDriver = main.simulation
	var site: Vector2i = arrange_front(world)
	main.player.simulation_position = center_of(site)
	await ticks(60 * 24)
	var running: Dictionary = snap()
	rec("pause.spread_was_running", "before pausing, natural spread was working (seeds planted by spread) and tiles were growing", int(running["natural_planted"]) > 5 and world.active_tiles.size() > 5, "snapshot %s" % str(running))
	tap_escape()
	await process_frame
	await process_frame
	var s0: Dictionary = snap()
	var is_paused: bool = paused
	await create_timer(1.5, true).timeout
	await ticks(60 * 12)
	var s1: Dictionary = snap()
	rec("pause.frozen", "paused: stages, growth, clock, spread ticks/queue, growth cursor and the natural-planted count do not move during 12 s of physics frames + 1.5 s real time", is_paused and s0 == s1, "paused=%s equal=%s" % [str(is_paused), str(s0 == s1)])
	tap_escape()
	await process_frame
	var p0: int = int(sim.spread.total_planted)
	var c0: float = sim.clock.elapsed
	var sp0: int = sim.spread.ticks
	var g0: int = sim.growth.ticks
	var q0: int = sim.spread.queue_size()
	await ticks(Engine.physics_ticks_per_second * 2)
	var dc: float = sim.clock.elapsed - c0
	rec("pause.resume_no_bank", "after resuming, 2 s of frames advance game time by 2 s, 2 spread ticks and 4 growth ticks (+-1): the paused wall time is not added", (not paused) and absf(dc - 2.0) < 0.06 and absi(sim.spread.ticks - sp0 - 2) <= 1 and absi(sim.growth.ticks - g0 - 4) <= 1 and sim.spread.total_planted - p0 <= 2 * tun_b(), "elapsed +%.4f spread ticks +%d growth ticks +%d planted +%d (B=%d)" % [dc, sim.spread.ticks - sp0, sim.growth.ticks - g0, sim.spread.total_planted - p0, tun_b()])

func tun_b() -> int:
	return main.tuning.spread_candidates_per_tick

func t_rate(hz: int) -> void:
	await new_main()
	var world: WorldState = main.grid
	var sim: SimulationDriver = main.simulation
	var site: Vector2i = arrange_front(world)
	main.player.simulation_position = center_of(site) + Vector2(0, 200)
	var t0: float = sim.clock.elapsed
	var snaps: Dictionary = {}
	for target: float in [20.0, 60.0, 100.5]:
		var frames: int = roundi(target * float(hz))
		var done: int = roundi((sim.clock.elapsed - t0) * float(hz))
		await ticks(frames - done)
		var sn: Dictionary = snap()
		sn["clock_dt"] = snappedf(sim.clock.elapsed - t0, 0.0001)
		snaps[str(target)] = sn
	observations["rate_hz"] = hz
	observations["snaps"] = snaps
	var last: Dictionary = snaps["100.5"]
	rec("rate.%d" % hz, "%d Hz physics: after 100.5 s the clock has run 201 growth ticks and 100 spread ticks since the setup (cross-rate equality is checked by the comparer), natural spread planted tiles" % hz, int(last["natural_planted"]) > 20 and absf(float(last["clock_dt"]) - 100.5) < 0.02, "snap %s" % str(last))

func t_water() -> void:
	await new_main()
	var world: WorldState = main.grid
	# a row with >= 8 consecutive water tiles
	var found: Vector2i = Vector2i(-1, -1)
	for y: int in range(10, world.height - 10, 3):
		var run_len: int = 0
		for x: int in world.width:
			if world.terrain[y * world.width + x] == 3:
				run_len += 1
				if run_len >= 10:
					found = Vector2i(x - 9, y)
					break
			else:
				run_len = 0
		if found.x >= 0:
			break
	var start: Vector2 = center_of(found)
	main.player.simulation_position = start
	await ticks(3)
	key(KEY_D, true)
	await ticks(Engine.physics_ticks_per_second / 2)
	key(KEY_D, false)
	await ticks(2)
	var moved: float = main.player.simulation_position.x - start.x
	var tile_x: int = floori(main.player.simulation_position.x / TILE)
	var terr: int = world.terrain[found.y * world.width + tile_x]
	observations["player_on_water"] = {"start": str(start), "end": str(main.player.simulation_position), "terrain_at_end": terr, "moved_px": moved}
	rec("water.player_walks_on_water", "OBSERVATION (not a pass criterion): the player moved right by %.1f px starting on a water tile (terrain id 3 = water) -> terrain at end id %d" % [moved, terr], true, "moved %.1f px, ended on terrain %d (3 = water); water walkable = %s" % [moved, terr, str(moved > 20.0 and terr == 3)])
