extends SceneTree
## P1-06 tempo measurement. Run: Godot --headless --path <project> --script res://tests/p1/p1_06_tempo.gd -- --mode=a|b|c [--minutes=60] [--dt=0.05] [--sim=key:val,...] [--play=key:val,...] [--out=path]
## a = bot with carrots, b = natural spread only (the player does nothing), c = bot without carrots.
const Bot = preload("res://tests/p1/p1_06_bot.gd")

func _initialize() -> void:
	run.call_deferred()

func parse_overrides(text: String) -> Dictionary:
	var result: Dictionary = {}
	if text.is_empty():
		return result
	for pair: String in text.split(","):
		var kv: PackedStringArray = pair.split(":")
		var value: Variant = kv[1]
		if String(kv[1]).is_valid_int():
			value = int(kv[1])
		elif String(kv[1]).is_valid_float():
			value = float(kv[1])
		result[kv[0]] = value
	return result

func run() -> void:
	var mode: String = "a"
	var minutes: float = 60.0
	var dt: float = 0.05
	var sim: Dictionary = {}
	var play: Dictionary = {}
	var out: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--minutes="):
			minutes = float(argument.trim_prefix("--minutes="))
		elif argument.begins_with("--dt="):
			dt = float(argument.trim_prefix("--dt="))
		elif argument.begins_with("--sim="):
			sim = parse_overrides(argument.trim_prefix("--sim="))
		elif argument.begins_with("--play="):
			play = parse_overrides(argument.trim_prefix("--play="))
		elif argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
	var bot: RefCounted = Bot.new(sim, play)
	bot.bot_on = mode != "b"
	bot.carrots_on = mode == "a"
	print("TEMPO mode=%s minutes=%.0f dt=%.3f reach_tiles=%d reach_targets=%d total_targets=%d sim=%s play=%s" % [mode, minutes, dt, bot.reach_tiles, bot.reach_targets, bot.world.target_count, sim, play])
	var started: int = Time.get_ticks_msec()
	var limit: float = minutes * 60.0
	var last_print: float = 0.0
	var worst_step_ms: float = 0.0
	while bot.time < limit and not bot.is_complete():
		var t0: int = Time.get_ticks_usec()
		bot.step(dt)
		worst_step_ms = maxf(worst_step_ms, (Time.get_ticks_usec() - t0) / 1000.0)
		if bot.time - last_print >= 120.0:
			last_print = bot.time
			var s: Dictionary = bot.snapshot()
			print("  t=%5.1f min  %6.2f%%  seeds=%d water=%.0f mature=%d pickups=%d carrots=%d stall=%.0fs shots=%d  task=%s pos=%s target=%s path=%d/%d (cpu %.0fs)" % [s["t"] / 60.0, s["percent"], s["seeds"], s["water"], s["mature"], s["pickups"], s["carrots"], s["stall"], s["shots"], bot.task, bot.pos / 4.0, bot.task_target / 4.0, bot.path_index, bot.path.size(), (Time.get_ticks_msec() - started) / 1000.0])
	bot.samples.append(bot.snapshot())
	var result: Dictionary = {"mode": mode, "minutes": bot.time / 60.0, "percent": bot.percent_now(), "complete": bot.is_complete(), "reach_times_min": {}, "samples": bot.samples,
		"shots_seed": bot.shots_seed, "shots_water": bot.shots_water, "shots_carrot": bot.shots_carrot, "carrots_placed": bot.carrots_placed, "refills": bot.refills,
		"stall_total_s": bot.stall_total, "stall_log": bot.stall_log, "stall_longest_s": bot.stall_longest, "walk_s": bot.walk_time, "shots_by_grid": bot.shots_by_grid, "peak_pickups": bot.peak_pickups,
		"counters_consistent": bot.world.counters_consistent(), "worst_step_ms": worst_step_ms}
	for mark: int in bot.reach_times:
		result["reach_times_min"][str(mark)] = snappedf(float(bot.reach_times[mark]) / 60.0, 0.01)
	print("TEMPO_RESULT " + JSON.stringify(result))
	if out != "":
		var file: FileAccess = FileAccess.open(out, FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "  "))
		file.close()
	quit(0)
