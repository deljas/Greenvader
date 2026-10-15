extends SceneTree
## Independent P2-01 scene check: real main.tscn, Esc injected through Input.parse_input_event (engine-internal).
## Run: Godot --headless --fixed-fps 60 --path <p> --script res://tests/p2/independent/p2_01_v_scene.gd [-- --hz=N]
var results: Array[Dictionary] = []
var main: Node
var hz: int = 60

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func ticks(n: int) -> void:
	for i: int in n:
		await physics_frame

func key_tap(code: Key) -> void:
	for pressed: bool in [true, false]:
		var e: InputEventKey = InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame

func sig(e: EnemyField) -> String:
	var s: String = "%d|%d|%d|%d|" % [e.steps_done, e.boars.size(), e.total_spawned, e.total_gnawed]
	for b: Boar in e.boars:
		s += "%d:%.3f,%.3f;" % [b.id, b.pos.x, b.pos.y]
	return s

func run() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--hz="):
			hz = int(a.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await ticks(3)
	var e: EnemyField = main.enemies
	var w: WorldState = main.grid
	rec("scene.nests", "main scene has 15 nests wired, spread hook set", e != null and e.nests.size() == 15 and main.simulation.spread.allow_hook.is_valid(), "nests=%d" % e.nests.size())
	# give boars something to eat near the first nest
	var n: Nest = e.nests[0]
	for y: int in range(n.tile.y + 8, n.tile.y + 20):
		for x: int in range(n.tile.x + 8, n.tile.x + 20):
			w.set_stage(y * w.width + x, 4)
	await ticks(roundi(14.0 * hz))
	rec("scene.spawn", "boars exist after ~14 s of game time", e.boars.size() > 0 and e.boars.size() <= 15, "boars=%d" % e.boars.size())
	var paused_before: bool = paused
	await key_tap(KEY_ESCAPE)
	await ticks(2)
	rec("scene.paused", "Esc injection pauses", paused and not paused_before, "paused=%s" % paused)
	var s0: String = sig(e)
	var t0: float = e.time
	var g0: int = w.greened_count
	await ticks(roundi(20.0 * hz))
	rec("scene.pause_freeze", "20 s paused: no spawn, move or bite (state identical)", sig(e) == s0 and e.time == t0 and w.greened_count == g0, "time %f -> %f" % [t0, e.time])
	await key_tap(KEY_ESCAPE)
	await ticks(2)
	var resumed: bool = not paused
	await ticks(roundi(1.0 * hz))
	var dt: float = e.time - t0
	rec("scene.resume_nobank", "after resume ~1 s of enemy time, no lump sum (<= 1.3 s)", resumed and dt > 0.5 and dt <= 1.3, "dt=%f spawned=%d" % [dt, e.total_spawned])
	var f: FileAccess = FileAccess.open("res://evidence/p2/p2-01/independent/checks_scene_%d.json" % hz, FileAccess.WRITE)
	f.store_string(JSON.stringify({"results": results}, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("RESULT scene hz=%d checks=%d failures=%d" % [hz, results.size(), fails])
	quit(1 if fails > 0 else 0)
