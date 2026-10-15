extends SceneTree
## Independent CPU frame-cost measurement of the real main.tscn (P1-06). Headless (no GPU): measures whole-frame wall time between
## consecutive process_frame signals; --fixed-fps does not sleep, so this is the frame's CPU work (all scripts, nodes and
## the RegionView repaint, not GPU submission). Scenarios: real play (WASD + shots) and a stress fixture.
## Run: Godot --headless --fixed-fps 60 --path <project> --script res://tests/p1/independent/p1_06_v_perf.gd -- [--hz=60]

const OUT: String = "res://evidence/p1/p1-06/independent/"
var main: Node
var results: Array[Dictionary] = []
var observations: Dictionary = {}
var keys_down: Dictionary = {}
var last_us: int = 0

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func key_event(code: Key, pressed: bool) -> void:
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)

func hold(codes: Array) -> void:
	for code: Variant in keys_down.keys():
		if not codes.has(code):
			key_event(code as Key, false)
			keys_down.erase(code)
	for code: Variant in codes:
		if not keys_down.has(code):
			key_event(code as Key, true)
			keys_down[code] = true

func click(button: MouseButton, world_pos: Vector2) -> void:
	var m: InputEventMouseMotion = InputEventMouseMotion.new()
	m.position = main.get_viewport().get_canvas_transform() * world_pos
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

func pct(values: PackedFloat64Array, q: float) -> float:
	var s: PackedFloat64Array = values.duplicate()
	s.sort()
	return s[clampi(int(float(s.size() - 1) * q), 0, s.size() - 1)]

## Runs `frames` frames of play-like input; returns per-frame ms (process + physics of the previous frame).
func drive(frames: int, shots_every: int, fire_water: bool) -> PackedFloat64Array:
	var costs: PackedFloat64Array = PackedFloat64Array()
	var dirs: Array = [[KEY_D], [KEY_D, KEY_S], [KEY_S], [KEY_A, KEY_S], [KEY_A], [KEY_A, KEY_W], [KEY_W], [KEY_D, KEY_W]]
	for f: int in frames:
		if f % 45 == 0:
			hold(dirs[(f / 45) % dirs.size()])
		if shots_every > 0 and f % shots_every == 0:
			var p: Vector2 = main.player.simulation_position + Vector2.from_angle(f * 0.37) * 80.0
			main.play.add_seeds(1)
			main.play.add_water(10.0)
			click(MOUSE_BUTTON_RIGHT if (fire_water and (f / shots_every) % 3 == 0) else MOUSE_BUTTON_LEFT, p)
		# Whole-frame wall time: from the start of this frame's idle step to the start of the next one. The headless
		# --fixed-fps loop does not sleep, so this is the frame's CPU work (physics steps + all _process + the engine).
		await process_frame
		var now: int = Time.get_ticks_usec()
		if last_us > 0:
			costs.append((now - last_us) / 1000.0)
		last_us = now
	hold([])
	return costs

func stats(label: String, c: PackedFloat64Array) -> Dictionary:
	var mean: float = 0.0
	for v: float in c:
		mean += v
	mean /= c.size()
	var over: int = 0
	for v: float in c:
		over += 1 if v >= 16.0 else 0
	var d: Dictionary = {"frames": c.size(), "mean_ms": mean, "p50_ms": pct(c, 0.5), "p99_ms": pct(c, 0.99), "p999_ms": pct(c, 0.999), "max_ms": pct(c, 1.0), "frames_over_16ms": over}
	observations[label] = d
	print("PERF %s %s" % [label, JSON.stringify(d)])
	return d

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var w: WorldState = main.grid
	# A: real play from the start, 3 minutes, 4 shots per second, walking in 8 directions
	last_us = 0
	var a: PackedFloat64Array = await drive(60 * 180, 15, true)
	var sa: Dictionary = stats("play_180s_4shots_per_s", a)
	rec("perf.play", "real play 3 min (walking, 4 shots/s, spread running): CPU per frame max < 16 ms and p99 < 8 ms", float(sa["max_ms"]) < 16.0 and float(sa["p99_ms"]) < 8.0, JSON.stringify(sa))
	# B: heavy mid-game fixture: 24,000 mature tiles with a rim, 12,000 wet seeds, 32 carrots/kiwis, many pickups, 60 shots
	# (a different layout from the implementer's: west of the river, around the player)
	w.debug_fill_stage(Rect2i(30, 220, 150, 160), WorldState.STAGE_MATURE)
	var seeded: int = 0
	for y: int in range(400, 500):
		for x: int in range(30, 150):
			var idx: int = y * w.width + x
			if w.set_stage(idx, WorldState.STAGE_SEED):
				w.set_moisture(idx, 100)
				seeded += 1
	main.play.seeds = 40
	var placed: int = 0
	for i: int in 30:
		var key: StringName = &"carrot" if i % 2 == 0 else &"kiwi"
		main.play.reserve_plant(main.play.def_by_key(key))
		if main.play.land_plant(key, Vector2((40 + (i % 10) * 12 + 1) * 4.0, (240 + (i / 10) * 12 + 1) * 4.0)) != null:
			placed += 1
		main.play.seeds = 40
	main.player.simulation_position = Vector2(100 * 4, 390 * 4)
	await process_frame
	last_us = 0
	var b: PackedFloat64Array = await drive(60 * 60, 5, true)
	var sb: Dictionary = stats("stress_60s_12shots_per_s", b)
	observations["stress_setup"] = {"mature": w.mature_count, "seeded": seeded, "cultivated": placed, "active_tiles_end": w.active_tiles.size(), "pickups": main.play.pickups.count()}
	rec("perf.stress", "stress fixture (%d mature, %d wet seeds, %d cultivated plants, 12 shots/s) CPU per frame max < 16 ms" % [w.mature_count, seeded, placed], float(sb["max_ms"]) < 16.0, JSON.stringify(sb) + " " + JSON.stringify(observations["stress_setup"]))
	var f: FileAccess = FileAccess.open(OUT + "checks_perf.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"results": results, "observations": observations}, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("V_RESULT total=%d fails=%d" % [results.size(), fails])
	quit(1 if fails > 0 else 0)
