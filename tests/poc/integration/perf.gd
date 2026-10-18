extends SceneTree
## POC-09 integration D: short performance record (real renderer, NOT --headless):
##   godot --path <repo> --script res://tests/poc/integration/perf.gd
## town_01 in normal density, in a fight at the north nest with the enemy count near its cap (boar_cap 8), the scene running in real
## time (auto_process = true, multiplier x1, no input). 10 s per resolution (640 / 960) with the window's configured vsync, then 10 s
## per resolution with vsync off to see the headroom. No stress load. No OS-level input / foregrounding (root.unfocusable).
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const Bot: GDScript = preload("res://tests/poc/integration/bot.gd")
const OUT: String = "res://evidence/poc/09/"
const SECONDS: float = 10.0
const WARMUP_FRAMES: int = 30

var main: Node
var s: RefCounted
var results: Array[Dictionary] = []

func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()

func _frames(n: int) -> void:
	for i: int in n:
		await process_frame

func _measure_window(label: String, res_index: int, vsync_off: bool) -> void:
	main.set_resolution(res_index, Vector2i(1920, 1080))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if vsync_off else DisplayServer.VSYNC_ENABLED)
	var vsync_mode: int = DisplayServer.window_get_vsync_mode()
	var rid: RID = main.render_view.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	main.auto_process = true
	await _frames(WARMUP_FRAMES)
	var deltas: PackedFloat64Array = PackedFloat64Array()
	var gpu_ms: PackedFloat64Array = PackedFloat64Array()
	var cpu_ms: PackedFloat64Array = PackedFloat64Array()
	var draw_calls: PackedFloat64Array = PackedFloat64Array()
	var boars_min: int = 1 << 30
	var boars_max: int = 0
	var t_start: int = Time.get_ticks_usec()
	var last: int = t_start
	var elapsed_game0: float = s.clock.elapsed
	while float(Time.get_ticks_usec() - t_start) / 1.0e6 < SECONDS:
		await process_frame
		var now: int = Time.get_ticks_usec()
		deltas.append(float(now - last) / 1000.0)
		last = now
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		boars_min = mini(boars_min, s.enemies.boars.size())
		boars_max = maxi(boars_max, s.enemies.boars.size())
	main.auto_process = false
	var sorted: PackedFloat64Array = deltas.duplicate()
	sorted.sort()
	var total: float = 0.0
	for d: float in deltas:
		total += d
	var avg: float = total / float(deltas.size())
	var p99: float = sorted[mini(int(float(sorted.size()) * 0.99), sorted.size() - 1)]
	var worst: float = sorted[sorted.size() - 1]
	var over_16_7: int = 0
	for d: float in deltas:
		over_16_7 += 1 if d > 16.7 + 0.5 else 0
	var gpu_avg: float = _mean(gpu_ms)
	var cpu_avg: float = _mean(cpu_ms)
	var row: Dictionary = {
		"label": label,
		"resolution": "%dx%d" % [Config.RESOLUTIONS[res_index].x, Config.RESOLUTIONS[res_index].y],
		"vsync_mode": vsync_mode,
		"frames": deltas.size(),
		"seconds": snappedf(total / 1000.0, 0.01),
		"avg_frame_ms": snappedf(avg, 0.01),
		"avg_fps": snappedf(1000.0 / avg, 0.1),
		"p99_frame_ms": snappedf(p99, 0.01),
		"worst_frame_ms": snappedf(worst, 0.01),
		"frames_over_16.7ms": over_16_7,
		"min_fps_from_worst": snappedf(1000.0 / worst, 0.1),
		"viewport_gpu_ms_avg": snappedf(gpu_avg, 0.01),
		"viewport_cpu_render_ms_avg": snappedf(cpu_avg, 0.01),
		"draw_calls_avg": snappedf(_mean(draw_calls), 1.0),
		"engine_fps_now": Engine.get_frames_per_second(),
		"boars_min": boars_min,
		"boars_max": boars_max,
		"game_seconds_advanced": snappedf(s.clock.elapsed - elapsed_game0, 0.01),
		"hp_end": s.play.hp,
		"downs": s.play.health.down_count,
	}
	results.append(row)
	print("PERF ", JSON.stringify(row))

func _mean(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sum: float = 0.0
	for v: float in values:
		sum += v
	return sum / float(values.size())

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN perf (headless display server)")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var adapter: String = RenderingServer.get_video_adapter_name()
	print("renderer=", adapter, " display=", DisplayServer.get_name(), " window=", root.size, " refresh=", DisplayServer.screen_get_refresh_rate(), " vsync(initial)=", DisplayServer.window_get_vsync_mode())
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(3)
	main.save_dir = "user://poc_saves_integration/"
	# Play up to the fight at the north nest with the test-side bot (public API), then hand the session to the scene.
	var size: Vector2i = Session.town_size()
	s = Session.new(size.x, size.y)
	s.paving = Session.paving_from(s.env_tuning)
	s.load_combat(Session.TOWN_SETUP)
	var bot: RefCounted = Bot.new(s)
	bot.guard_until = 2000.0
	bot.idle(70.0)
	var nest: Nest = s.enemies.nest_by_id(3)
	bot.stop_when = func() -> bool: return nest.hp < nest.hp_max and s.enemies.boars.size() >= 6
	var guard: int = 0
	while not bot.stopped and nest.alive and guard < 6:
		guard += 1
		bot.kill_nest(nest, 150.0)
		if s.play.seeds < 4:
			bot.restock(30, 150.0)
	bot.detach()
	var near: int = 0
	for boar: Boar in s.enemies.boars:
		near += 1 if boar.pos.distance_to(s.position) < 120.0 else 0
	print("INFO fight state: t=%.1f nest hp %d/%d boars=%d (within 12 m of the player: %d, cap %d) hp=%d" % [s.clock.elapsed, nest.hp, nest.hp_max, s.enemies.boars.size(), near, s.enemy_tuning.boar_cap, s.play.hp])
	main.replace_session(s)
	await _frames(5)
	await _measure_window("640 vsync(config)", 0, false)
	await _measure_window("960 vsync(config)", 1, false)
	await _measure_window("640 vsync off", 0, true)
	await _measure_window("960 vsync off", 1, true)
	var report: Dictionary = {"adapter": adapter, "refresh_hz": DisplayServer.screen_get_refresh_rate(), "fight_state": {"t": s.clock.elapsed, "nests_alive": s.enemies.alive_nest_count(-1), "boars": s.enemies.boars.size(), "boar_cap": s.enemy_tuning.boar_cap}, "windows": results}
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT + "D_perf.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", false, true))
	file.close()
	main.queue_free()
	await _frames(2)
	print("RESULT done")
	quit(0)
