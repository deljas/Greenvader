extends SceneTree
## P2-06 tempo measurement with the fighting bot. Run:
##   Godot --headless --path <project> --script res://tests/p2/p2_06_tempo.gd -- [--mode=a|b|c] [--minutes=90] [--dt=0.05]
##     [--sim=key:val,...] [--play=key:val,...] [--enemy=key:val,...] [--bot=key:val,...] [--out=path]
## mode a = bot with carrots, b = the player does nothing (enemies and natural spread only), c = bot without carrots.
const Bot = preload("res://tests/p2/p2_06_bot.gd")

func _initialize() -> void:
	run.call_deferred()

func parse_overrides(text: String) -> Dictionary:
	var result: Dictionary = {}
	if text.is_empty():
		return result
	for pair: String in text.split(","):
		var kv: PackedStringArray = pair.split(":")
		var value: Variant = kv[1]
		if String(kv[1]) == "true" or String(kv[1]) == "false":
			value = String(kv[1]) == "true"
		elif String(kv[1]).is_valid_int():
			value = int(kv[1])
		elif String(kv[1]).is_valid_float():
			value = float(kv[1])
		result[kv[0]] = value
	return result

func run() -> void:
	var mode: String = "a"
	var minutes: float = 90.0
	var dt: float = 0.05
	var sim: Dictionary = {}
	var play: Dictionary = {}
	var enemy: Dictionary = {}
	var botp: Dictionary = {}
	var out: String = ""
	var quiet: bool = false
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
		elif argument.begins_with("--enemy="):
			enemy = parse_overrides(argument.trim_prefix("--enemy="))
		elif argument.begins_with("--bot="):
			botp = parse_overrides(argument.trim_prefix("--bot="))
		elif argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
		elif argument == "--quiet":
			quiet = true
	var bot: RefCounted = Bot.new(sim, play, enemy, botp)
	bot.bot_on = mode != "b"
	bot.carrots_on = mode == "a"
	print("TEMPO mode=%s minutes=%.0f dt=%.3f sim=%s play=%s enemy=%s bot=%s nests=%d" % [mode, minutes, dt, sim, play, enemy, botp, bot.enemies.nests.size()])
	var started: int = Time.get_ticks_msec()
	var limit: float = minutes * 60.0
	var last_print: float = 0.0
	var worst_step_ms: float = 0.0
	while bot.time < limit and not bot.world.cleared:
		var t0: int = Time.get_ticks_usec()
		bot.step(dt)
		worst_step_ms = maxf(worst_step_ms, (Time.get_ticks_usec() - t0) / 1000.0)
		if bot.time - last_print >= 120.0 and not quiet:
			last_print = bot.time
			var s: Dictionary = bot.snapshot()
			print("  t=%5.1f min  %6.2f%%  seeds=%d water=%.0f hp=%d kills=%d nests=%d boars=%d downs=%d stall=%.0fs zones=%s task=%s (cpu %.0fs)" % [s["t"] / 60.0, s["percent"], s["seeds"], s["water"], s["hp"], s["kills"], s["nests_left"], s["boars"], s["downs"], s["stall"], s["zones"], bot.task, (Time.get_ticks_msec() - started) / 1000.0])
	bot.samples.append(bot.snapshot())
	var result: Dictionary = {"mode": mode, "sim": sim, "play": play, "enemy": enemy, "bot": botp, "dt": dt, "minutes": bot.time / 60.0, "cleared": bot.world.cleared, "cleared_at_min": snappedf(bot.cleared_at / 60.0, 0.01) if bot.cleared_at >= 0.0 else -1.0,
		"all_stable_at_min": snappedf(bot.all_stable_at / 60.0, 0.01) if bot.all_stable_at >= 0.0 else -1.0,
		"clearing_at_min": {}, "stable_at_min": {}, "complete_at_min": {},
		"downs": bot.play.health.down_count, "down_times": bot.down_times, "hits_taken": bot.play.health.hit_count, "stall_total_s": snappedf(bot.stall_total, 0.1), "stall_longest_s": snappedf(bot.stall_longest, 0.1),
		"kills": bot.enemies.total_killed, "nests_destroyed": bot.enemies.total_nests_destroyed, "spawned": bot.enemies.total_spawned, "gnawed": bot.enemies.total_gnawed,
		"shots_seed": bot.shots_seed, "shots_at_boars": bot.shots_at_boars, "shots_at_nests": bot.shots_at_nests, "shots_carrot": bot.shots_carrot, "carrots_placed": bot.carrots_placed, "kiwis_placed": bot.kiwis_placed,
		"assaults": bot.assaults_started, "assaults_given_up": bot.assaults_given_up, "hunts": bot.hunts_started, "evade_steps": bot.evade_steps, "carrot_skips": bot.carrot_skips,
		"percent_reach": bot.percent_now(), "reach_times_min": {}, "counters_consistent": bot.world.counters_consistent(),
		"worst_step_ms": worst_step_ms, "worst_logic_ms": bot.worst_total_us / 1000.0, "worst_enemy_ms": bot.worst_enemy_us / 1000.0, "worst_far_ms": bot.worst_far_us / 1000.0,
		"far_laps": bot.far.laps, "samples": bot.samples, "stall_log": bot.stall_log}
	for z: int in bot.stable_at:
		result["stable_at_min"][str(z)] = snappedf(float(bot.stable_at[z]) / 60.0, 0.01)
	for z: int in bot.clearing_at:
		result["clearing_at_min"][str(z)] = snappedf(float(bot.clearing_at[z]) / 60.0, 0.01)
	for z: int in bot.complete_at:
		result["complete_at_min"][str(z)] = snappedf(float(bot.complete_at[z]) / 60.0, 0.01)
	for mark: int in bot.reach_times:
		result["reach_times_min"][str(mark)] = snappedf(float(bot.reach_times[mark]) / 60.0, 0.01)
	print("TEMPO_RESULT " + JSON.stringify(result))
	if out != "":
		var file: FileAccess = FileAccess.open(out, FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "  "))
		file.close()
	quit(0)
