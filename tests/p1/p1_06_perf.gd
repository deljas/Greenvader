extends SceneTree
## P1-06 frame cost of the game logic. The greedy bot (with carrots) plays the whole region at 60 steps per second while a
## RegionView repaints the changed tiles each step (as in the game). Per step it records the cost of PlayState.advance +
## SimClock.advance (growth tick, spread tick, production, pickups) + RegionView.flush; the bot's own planning is not counted.
## Run: Godot --headless --path <project> --script res://tests/p1/p1_06_perf.gd [-- --minutes=30]
## NOTE: headless = no GPU; the real-window cost is measured by p1_06_gpu.gd.
const Bot = preload("res://tests/p1/p1_06_bot.gd")

func _initialize() -> void:
	run.call_deferred()

func percentile(values: PackedFloat64Array, q: float) -> float:
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	return sorted[clampi(int(float(sorted.size() - 1) * q), 0, sorted.size() - 1)]

func run() -> void:
	var minutes: float = 30.0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--minutes="):
			minutes = float(argument.trim_prefix("--minutes="))
	var bot: RefCounted = Bot.new()
	var view: RegionView = RegionView.new()
	view.setup(bot.world, bot.sim_tuning)
	bot.view = view
	var costs: PackedFloat64Array = PackedFloat64Array()
	var worst_ms: float = 0.0
	var worst_time: float = 0.0
	var over_16: int = 0
	var heavy_frames: Array[Dictionary] = []
	var dt: float = 1.0 / 60.0
	var started: int = Time.get_ticks_msec()
	while bot.time < minutes * 60.0 and not bot.is_complete():
		bot.step(dt)
		var ms: float = bot.last_logic_us / 1000.0
		costs.append(ms)
		if ms > worst_ms:
			worst_ms = ms
			worst_time = bot.time
		if ms >= 16.0:
			over_16 += 1
		if ms >= 8.0:
			heavy_frames.append({"t": snappedf(bot.time, 0.01), "ms": snappedf(ms, 0.01), "active": bot.world.active_tiles.size(), "queue": bot.spread.queue_size(), "dirty": bot.world.dirty_tiles.size()})
	var mean: float = 0.0
	for c: float in costs:
		mean += c
	mean /= costs.size()
	print("PERF frames=%d game_minutes=%.1f cpu_seconds=%.0f" % [costs.size(), bot.time / 60.0, (Time.get_ticks_msec() - started) / 1000.0])
	print("PERF logic per frame (advance + clock + view flush): mean %.3f ms, p50 %.3f, p99 %.3f, p99.9 %.3f, max %.3f ms (at t=%.1f s); frames >= 16 ms: %d; frames >= 8 ms: %d" % [mean, percentile(costs, 0.5), percentile(costs, 0.99), percentile(costs, 0.999), worst_ms, worst_time, over_16, heavy_frames.size()])
	for frame: Dictionary in heavy_frames.slice(0, 12):
		print("PERF heavy frame %s" % JSON.stringify(frame))
	# Stress scene: everything busy at once on the real region. 60,000 mature tiles with an open rim (spread candidates),
	# 40,000 wet seeds (growth), the player in the middle of it, and every changed tile repainted by the view.
	var stress: RefCounted = Bot.new()
	stress.bot_on = false
	var stress_view: RegionView = RegionView.new()
	stress_view.setup(stress.world, stress.sim_tuning)
	stress.view = stress_view
	stress.world.debug_fill_stage(Rect2i(20, 250, 200, 200), WorldState.STAGE_MATURE)
	for y: int in range(40, 240):
		for x: int in range(20, 220):
			var index: int = stress.world.index_of(x, y)
			if stress.world.set_stage(index, WorldState.STAGE_SEED):
				stress.world.set_moisture(index, 100)
	stress.pos = Vector2(120 * 4, 240 * 4)
	var stress_costs: PackedFloat64Array = PackedFloat64Array()
	var stress_worst: float = 0.0
	for i: int in 60 * 40:
		stress.step(dt)
		stress_costs.append(stress.last_logic_us / 1000.0)
		stress_worst = maxf(stress_worst, stress.last_logic_us / 1000.0)
	var stress_over: int = 0
	for c: float in stress_costs:
		stress_over += 1 if c >= 16.0 else 0
	print("PERF stress scene (40 s): 40,000 wet seeds + 40,000 mature tiles with open rim, view repainting: p50 %.3f, p99 %.3f, max %.3f ms; frames >= 16 ms: %d; active tiles at the end %d" % [percentile(stress_costs, 0.5), percentile(stress_costs, 0.99), stress_worst, stress_over, stress.world.active_tiles.size()])
	var result: Dictionary = {"stress_max_ms": stress_worst, "stress_p99_ms": percentile(stress_costs, 0.99), "stress_frames_over_16ms": stress_over, "frames": costs.size(), "game_minutes": bot.time / 60.0, "mean_ms": mean, "p50_ms": percentile(costs, 0.5), "p99_ms": percentile(costs, 0.99), "p999_ms": percentile(costs, 0.999), "max_ms": worst_ms, "max_at_s": worst_time, "frames_over_16ms": over_16, "frames_over_8ms": heavy_frames.size(), "heavy_frames": heavy_frames.slice(0, 40), "complete": bot.is_complete()}
	var file: FileAccess = FileAccess.open("res://evidence/p1/p1-06/perf_logic.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("P1_06_PERF_RESULT max_ms=%.3f frames_over_16ms=%d" % [worst_ms, over_16])
	quit(1 if over_16 > 0 or stress_over > 0 else 0)
