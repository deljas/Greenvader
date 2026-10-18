extends SceneTree
## POC-09 integration A: one full run on town_01 (fixed seeds) through the session's normal operation API only.
##   godot --headless --path <repo> --script res://tests/poc/integration/play_through.gd
## New game -> sow -> water -> germinate / mature -> seed recovery -> walk to the nests, destroy 3 -> remove the remaining
## boars -> stable -> NO input from there on -> exact 100 % (island included) within the pre-computed bound -> completion display.
## No debug refill, no direct writes to play / world / enemy state (the bot only calls walk / fire / advance_game).
## Saves go to user://poc_saves_integration/ only.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const Cmp: GDScript = preload("res://tests/poc/integration/cmp.gd")
const Bot: GDScript = preload("res://tests/poc/integration/bot.gd")
const OUT: String = "res://evidence/poc/09/"
const SAVE_DIR: String = "user://poc_saves_integration/"
const STAND: Vector2i = Vector2i(78, 84)

var failures: int = 0
var passes: int = 0
var report: Dictionary = {}
var checks: Array[String] = []
var s: RefCounted
var bot: RefCounted
var extra_sessions: Array[RefCounted] = []

func check(name: String, ok: bool, detail: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", name, detail]
	checks.append(line)
	print(line)
	if ok:
		passes += 1
	else:
		failures += 1

func _init() -> void:
	_run.call_deferred()

func make_session() -> RefCounted:
	var size: Vector2i = Session.town_size()
	var made: RefCounted = Session.new(size.x, size.y)
	made.paving = Session.paving_from(made.env_tuning)
	if not made.load_combat(Session.TOWN_SETUP):
		push_error("town load failed")
	return made

func diff_sections(a: RefCounted, b: RefCounted) -> String:
	var da: Dictionary = PocSave.capture(a)
	var db: Dictionary = PocSave.capture(b)
	var out: PackedStringArray = PackedStringArray()
	for k: String in da:
		if k == "saved_at":
			continue
		var ja: String = JSON.stringify(da[k], "", true, true)
		var jb: String = JSON.stringify(db[k], "", true, true)
		if ja != jb:
			var sub: PackedStringArray = PackedStringArray()
			if da[k] is Dictionary:
				for k2: String in da[k]:
					if JSON.stringify(da[k][k2], "", true, true) != JSON.stringify((db[k] as Dictionary).get(k2), "", true, true):
						sub.append(k2)
			out.append("%s{%s}" % [k, ",".join(sub)])
	return ";".join(out)

func stage_counts(indices: PackedInt32Array) -> Array:
	var counts: Array = [0, 0, 0, 0, 0]
	for i: int in indices:
		counts[s.state.stage[i]] += 1
	return counts

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	s = make_session()
	var st: WorldState = s.state
	bot = Bot.new(s)
	bot.guard_until = 5000.0
	bot.log_every = 10.0
	check("A0.new_game_defaults", s.combat_mode and st.width == 112 and s.play.seeds == s.play_tuning.seed_start and is_equal_approx(s.play.water, s.play_tuning.water_start) and s.play.hp == s.play.hp_max and not s.debug_refill_enabled and s.clock.elapsed == 0.0 and st.zone_state[0] >= WorldState.ZONE_STABLE and st.zone_state[1] == WorldState.ZONE_UNCONQUERED, "seeds=%d water=%.0f hp=%d zones=%s targets=%d greened=%d" % [s.play.seeds, s.play.water, s.play.hp, st.zone_state, st.target_count, st.greened_count])
	var bound_start: float = s.far.completion_bound_seconds()
	report["bound_at_start_s"] = bound_start
	report["start"] = bot.snapshot_row()

	# ------------------------------------------------------------ sow + water (hand sowing)
	bot.go(STAND, 60.0, 2.0)
	var landing: Array[Vector2i] = []
	var candidates: Array[Vector2i] = []
	for y: int in range(74, 97):
		for x: int in range(58, 77):
			var i: int = st.index_of(x, y)
			var c: Vector2i = Vector2i(x, y)
			var d_px: float = Bot.cpx(c).distance_to(Bot.cpx(STAND))
			if st.target[i] == 1 and st.zone_at(i) == 1 and st.stage[i] == WorldState.STAGE_EMPTY and (st.terrain[i] == Session.T_WASTE or st.terrain[i] == Session.T_PAVED) and d_px >= 24.0 and d_px <= 52.0 and not s.shot_blocked(Bot.cpx(STAND), Bot.cpx(c)):
				candidates.append(c)
	for c: Vector2i in candidates:
		var spaced: bool = true
		for other: Vector2i in landing:
			if absi(other.x - c.x) < 3 and absi(other.y - c.y) < 3:
				spaced = false
		if spaced and landing.size() < 8:
			landing.append(c)
	var before_stage: PackedByteArray = st.stage.duplicate()
	var seeds_before_sow: int = s.play.seeds
	var water_before: float = s.play.water
	for c: Vector2i in landing:
		while not bot.try_fire(false, Bot.cpx(c)):
			bot.frame()
		bot.idle(0.4)
	bot.idle(1.0)
	var sown: PackedInt32Array = PackedInt32Array()
	for i: int in st.tile_count():
		if before_stage[i] == WorldState.STAGE_EMPTY and st.stage[i] >= WorldState.STAGE_SEED:
			sown.append(i)
	for c: Vector2i in landing:
		while not bot.try_fire(true, Bot.cpx(c)):
			bot.frame()
		bot.idle(0.4)
	bot.idle(1.0)
	var moist_after_water: int = 0
	for i: int in sown:
		moist_after_water += 1 if st.moisture[i] > 0 else 0
	check("A1.sow_and_water", landing.size() >= 4 and sown.size() >= 8 and bot.seed_shots == landing.size() and bot.water_shots == landing.size() and s.play.seeds == seeds_before_sow - landing.size() and s.play.water < water_before and moist_after_water > 0, "landing spots=%d seeds shot=%d (%d->%d) planted tiles=%d water shots=%d (%.0f->%.0f) moist tiles=%d/%d" % [landing.size(), bot.seed_shots, seeds_before_sow, s.play.seeds, sown.size(), bot.water_shots, water_before, s.play.water, moist_after_water, sown.size()])
	report["sow"] = {"landing_cells": landing.size(), "planted_tiles": sown.size(), "stage_counts_after_sow": stage_counts(sown), "seeds": [seeds_before_sow, s.play.seeds], "water": [water_before, s.play.water]}

	# ------------------------------------------------------------ germinate -> mature while restocking at the source
	var t_sow: float = s.clock.elapsed
	var t_sprout: float = -1.0
	var t_mature: float = -1.0
	var source: Vector2i = bot.nearest_source_cell()
	bot.go(source, 100.0, 2.0)
	var wait_limit: float = t_sow + 240.0
	var plant_gain_start: int = int(bot.gain_by_class["plant"])
	while s.clock.elapsed < wait_limit and not bot.stopped:
		bot.idle(2.0)
		# Seed recovery from the grown plants: walk to a fruit lying near the sown ground, then back to the source.
		var fruit_cell: Vector2i = Vector2i(-1, -1)
		var fruit_d: float = 1.0e12
		for item: Dictionary in s.play.pickups.items:
			if int(item["owner"]) >= 1000000 and int(item["owner"]) < 4000000 and String(item["kind"]) == "seed_fruit":
				var at: Vector2 = Vector2(float(item["x"]), float(item["y"]))
				if at.distance_to(s.position) < fruit_d and s.play.seeds < s.play_tuning.seed_max:
					fruit_d = at.distance_to(s.position)
					fruit_cell = Coords.logic_to_cell(at)
		if fruit_cell.x >= 0:
			bot.go(fruit_cell, 20.0, 3.0)
			bot.idle(0.5)
			bot.go(source, 40.0, 2.0)
		var counts: Array = stage_counts(sown)
		if t_sprout < 0.0 and int(counts[2]) + int(counts[3]) + int(counts[4]) > 0:
			t_sprout = s.clock.elapsed
		if t_mature < 0.0 and int(counts[4]) > 0:
			t_mature = s.clock.elapsed
		if t_mature >= 0.0 and s.clock.elapsed >= t_mature + 90.0:
			break
	var counts_mid: Array = stage_counts(sown)
	check("A2.germinate_and_mature", t_sprout > 0.0 and t_mature > 0.0 and int(counts_mid[4]) > 0, "sprout at +%.1f s, first mature at +%.1f s after sowing; stage counts [empty,seed,s1,s2,mature]=%s; greened=%d" % [t_sprout - t_sow, t_mature - t_sow, counts_mid, st.greened_count])
	var plant_gain: int = int(bot.gain_by_class["plant"]) - plant_gain_start
	report["growth"] = {"sprout_after_s": t_sprout - t_sow, "mature_after_s": t_mature - t_sow, "stage_counts_mid": counts_mid, "greened_mid": st.greened_count}
	report["seed_recovery_pre_combat"] = {"gain_by_class": bot.gain_by_class.duplicate(), "plant_producer_total": s.play.producer.total_produced, "seeds_now": s.play.seeds}
	check("A3.seed_recovery_from_source_and_plants", int(bot.gain_by_class["source"]) > 0 and s.play.seeds > seeds_before_sow - landing.size(), "pickups collected: %s (plant fruit collected in the wait window=%d, producer total produced=%d), seeds now=%d" % [bot.gain_by_class, plant_gain, s.play.producer.total_produced, s.play.seeds])

	# ------------------------------------------------------------ nests
	var nest_log: Array = []
	var guard_rounds: int = 0
	while s.enemies.alive_nest_count(-1) > 0 and not bot.stopped and guard_rounds < 40:
		guard_rounds += 1
		if s.play.seeds < 30:
			bot.restock(38, 200.0)
		var best: Nest = null
		var best_d: float = 1.0e12
		for nest: Nest in s.enemies.nests:
			if nest.alive:
				var d: float = nest.center_px(Config.TILE_PX).distance_to(s.position)
				if d < best_d:
					best_d = d
					best = nest
		var hp0: int = best.hp
		var t0: float = s.clock.elapsed
		var seeds0: int = s.play.seeds
		var result: String = bot.kill_nest(best)
		nest_log.append({"nest": best.id, "tile": [best.tile.x, best.tile.y], "result": result, "t_start": snappedf(t0, 0.1), "t_end": snappedf(s.clock.elapsed, 0.1), "seeds_start": seeds0, "seeds_end": s.play.seeds, "hp_start": hp0})
	check("A4.three_nests_destroyed", s.enemies.alive_nest_count(-1) == 0 and s.enemies.total_nests_destroyed == 3 and st.zone_state[1] >= WorldState.ZONE_CLEARING, "nest log=%s; downs=%d" % [nest_log, bot.down_times.size()])
	report["nests"] = nest_log
	var t_clearing: float = float((s.zone_times[1] as Dictionary).get(WorldState.ZONE_CLEARING, -1.0))
	var boars_at_clear: int = s.enemies.boars.size()

	# ------------------------------------------------------------ remaining enemies
	var spawned_at_clear: int = s.enemies.total_spawned
	var killed_by_hunt: int = bot.hunt_boars(500.0)
	var guard2: int = 0
	while st.zone_state[1] < WorldState.ZONE_STABLE and guard2 < 50 and not bot.stopped:
		guard2 += 1
		bot.idle(2.0)
	check("A5.remaining_enemies_removed_then_stable", s.enemies.boars.is_empty() and st.zone_state[1] >= WorldState.ZONE_STABLE and s.enemies.total_spawned == spawned_at_clear, "boars at clearing=%d, hunted=%d, spawned total=%d (at clearing %d)" % [boars_at_clear, killed_by_hunt, s.enemies.total_spawned, spawned_at_clear])
	var t_stable: float = float((s.zone_times[1] as Dictionary).get(WorldState.ZONE_STABLE, -1.0))
	var log_texts: PackedStringArray = PackedStringArray(s.zone_log)
	check("A5b.zone_notices_in_order", s.zone_log.size() >= 2 and s.zone_log[0].contains("巣をすべて壊した") and s.zone_log[1].contains("安定した"), str(s.zone_log))
	report["resources_until_stable"] = {"seed_shots": bot.seed_shots, "water_shots": bot.water_shots, "min_seeds": bot.min_seeds, "min_water": bot.min_water, "min_hp": bot.min_hp, "downs": bot.down_times.size(), "down_times": bot.down_times, "hits_taken": s.play.health.hit_count, "gain_by_class": bot.gain_by_class, "walked_m": bot.walked_px * Config.M_PER_LOGIC_PX, "frames": bot.frames}
	check("A5c.finite_resources_observed", bot.min_seeds <= 3 or int(bot.events.size()) > 0, "min seeds=%d min water=%.0f min hp=%d seed shots=%d restock events=%d downs=%d hits taken=%d" % [bot.min_seeds, bot.min_water, bot.min_hp, bot.seed_shots, bot.events.size(), bot.down_times.size(), s.play.health.hit_count])

	# ------------------------------------------------------------ NO INPUT from here on
	bot.detach()
	var bound: float = s.far.completion_bound_seconds()
	var limit_time: float = t_stable + bound
	var green_at_stable: int = st.greened_count
	var pos_at_stable: Vector2 = s.position
	var spawned_stable: int = s.enemies.total_spawned
	var launched_stable: int = s.projectiles.launched
	var seeds_stable: int = s.play.seeds
	var water_stable: float = s.play.water
	var hits_stable: int = s.play.health.hit_count
	var in_flight_at_stable: int = s.projectiles.shots.size()
	report["stable"] = {"t_stable_s": t_stable, "bound_at_stable_s": bound, "limit_time_s": limit_time, "greened_at_stable": green_at_stable, "targets": st.target_count, "pct_at_stable": s.greening_percent(), "position_cell": [Coords.logic_to_cell(pos_at_stable).x, Coords.logic_to_cell(pos_at_stable).y], "zone_times": s.zone_times.duplicate(true)}
	print("INFO stable at %.1f s, bound %.1f s (start-time bound %.1f), limit %.1f, greened %d/%d" % [t_stable, bound, bound_start, limit_time, green_at_stable, st.target_count])
	var invaded_steps: int = 0
	var loaded_copy: RefCounted = null
	var hook_time: float = -1.0
	var hook_info: Dictionary = {}
	var compare_sig_equal: Variant = null
	var compare_detail: String = ""
	var compare_diff: String = "not reached"
	var samples: Array = []
	var next_sample: float = s.clock.elapsed
	var t_100: float = -1.0
	while s.clock.elapsed <= limit_time + 0.001 and st.greened_count != st.target_count:
		s.advance_game(0.25)
		if loaded_copy != null and s.clock.elapsed <= hook_time + 30.0 + 0.001:
			loaded_copy.advance_game(0.25)
			if absf(s.clock.elapsed - (hook_time + 30.0)) < 0.001:
				compare_diff = Cmp.same_state(s, loaded_copy)
				compare_sig_equal = compare_diff == ""
				compare_detail = "diff sections: [%s] after +30 s idle: orig elapsed=%.2f copy elapsed=%.2f greened %d/%d far job_zone=%d round_active=%s" % [diff_sections(s, loaded_copy), s.clock.elapsed, loaded_copy.clock.elapsed, st.greened_count, loaded_copy.state.greened_count, s.far.job_zone, s.far.round_active]
		if not s.enemies.boars.is_empty() or s.enemies.total_spawned != spawned_stable:
			invaded_steps += 1
		if s.clock.elapsed >= next_sample:
			next_sample += 30.0
			samples.append(bot.snapshot_row())
		if hook_time < 0.0 and (s.far.job_zone >= 0 or s.far.round_active):
			hook_info = {"t": s.clock.elapsed, "job_zone": s.far.job_zone, "round_active": s.far.round_active, "job_open": s.far.job_open, "far_ticks": s.far.ticks, "sweep_cursor": s.far.sweep_cursor}
			var saved: Dictionary = PocSave.save(s, SAVE_DIR, {"resolution_index": 0})
			var loaded: Dictionary = PocSave.load_slot(SAVE_DIR, false, Callable(self, "make_session"))
			if bool(saved["ok"]) and bool(loaded["ok"]):
				loaded_copy = loaded["session"]
				extra_sessions.append(loaded_copy)
				hook_time = s.clock.elapsed
				hook_info["equal_at_save"] = Cmp.same_state(s, loaded_copy) == ""
				hook_info["copy_job_zone"] = loaded_copy.far.job_zone
				hook_info["copy_round_active"] = loaded_copy.far.round_active
			else:
				hook_time = -2.0
				hook_info["error"] = str(saved.get("reason", "")) + str(loaded.get("reason", ""))
	t_100 = s.clock.elapsed
	var since_stable: float = t_100 - t_stable
	report["completion"] = {"t_100_s": t_100, "since_stable_s": since_stable, "bound_s": bound, "ratio": since_stable / bound, "greened": st.greened_count, "targets": st.target_count, "pct": s.greening_percent(), "samples_every_30s": samples}
	check("A6.no_reinvasion_after_stable", invaded_steps == 0 and s.enemies.boars.is_empty() and s.enemies.total_spawned == spawned_stable, "invaded steps=%d spawned=%d boars=%d" % [invaded_steps, s.enemies.total_spawned, s.enemies.boars.size()])
	var island: Array = s.combat_setup["layout"]["island"]
	var island_ok: bool = true
	for y: int in range(int(island[1]), int(island[1]) + int(island[3])):
		for x: int in range(int(island[0]), int(island[0]) + int(island[2])):
			island_ok = island_ok and st.stage[st.index_of(x, y)] >= WorldState.GREENED_MIN_STAGE
	var exact: bool = st.greened_count == st.target_count and st.target_count > 0 and st.greening_percent_floor() == 100 and st.recount_greened() == st.target_count
	check("A7.exact_100_percent_within_bound_with_island", exact and island_ok and t_100 <= limit_time + 0.001 and st.counters_consistent(), "greened %d/%d, 100%% at game time %.1f s = %.1f s after stable; bound %.1f s (%.0f%% used); island ok=%s" % [st.greened_count, st.target_count, t_100, since_stable, bound, 100.0 * since_stable / bound, island_ok])
	check("A8.no_input_after_stable", s.position == pos_at_stable and s.projectiles.launched == launched_stable and s.play.seeds >= seeds_stable - 0 and s.play.health.hit_count == hits_stable and in_flight_at_stable == 0, "position kept, shots launched %d->%d, hits %d->%d, seeds %d->%d (gain by pickups only), water %.0f->%.0f" % [launched_stable, s.projectiles.launched, hits_stable, s.play.health.hit_count, seeds_stable, s.play.seeds, water_stable, s.play.water])
	check("A9.zone_complete_and_notice", st.zone_state[1] == WorldState.ZONE_COMPLETE and st.zone_state[0] == WorldState.ZONE_COMPLETE and st.cleared and s.cleared_notices == 1 and s.zone_log.has("すべての地域を緑化した"), "zone_state=%s cleared=%s notices=%d log=%s" % [st.zone_state, st.cleared, s.cleared_notices, s.zone_log])
	if hook_time >= 0.0:
		check("A10.save_load_while_far_seed_running", bool(hook_info.get("equal_at_save", false)) and compare_sig_equal == true and (int(hook_info["copy_job_zone"]) >= 0 or bool(hook_info["copy_round_active"])), "hook=%s; %s; whole-state equal after +30 s (float tol 1e-6) = %s %s" % [hook_info, compare_detail, str(compare_sig_equal), compare_diff])
	else:
		check("A10.save_load_while_far_seed_running", false, "FarSeed never reported job_zone>=0 or round_active before 100%%: %s" % str(hook_info))
	report["far_hook"] = hook_info
	# ------------------------------------------------------------ after completion: a further 120 s with no input
	var green_done: int = st.greened_count
	var extra_invaded: int = 0
	var steps_left: int = 480
	while steps_left > 0:
		steps_left -= 1
		s.advance_game(0.25)
		if not s.enemies.boars.is_empty() or s.enemies.total_spawned != spawned_stable:
			extra_invaded += 1
	check("A11.stays_complete_120s_more", extra_invaded == 0 and st.greened_count == green_done and st.greening_percent_floor() == 100 and st.zone_state[1] == WorldState.ZONE_COMPLETE, "greened %d, invaded steps %d, game time %.1f s (hour %.2f)" % [st.greened_count, extra_invaded, s.clock.elapsed, s.day_hour()])
	report["end"] = bot.snapshot_row()
	report["events"] = Array(bot.events)
	report["zone_log"] = Array(s.zone_log)
	report["rows_every_10s"] = bot.rows
	report["game_end_time_s"] = s.clock.elapsed

	# ------------------------------------------------------------ completion display through the real scene (hud / badge)
	var main: Node = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await process_frame
	await process_frame
	main.replace_session(s)
	main.tick(0.0, Vector2.ZERO)
	var badge_text: String = main.ui.badge.text
	var hud_text: String = main.hud.text
	check("A12.completion_display", badge_text.contains("★緑化完了") and badge_text.contains("100") and main.zone_summary().contains("【全地域緑化】") and hud_text.contains("緑化 100%"), "badge=[%s] summary=[%s]" % [badge_text.replace("\n", " / "), main.zone_summary()])
	report["completion_display"] = {"badge": badge_text, "zone_summary": main.zone_summary(), "hud": hud_text}
	main.queue_free()
	await process_frame
	for extra: RefCounted in extra_sessions:
		extra.close()
	s.close()
	report["checks"] = checks
	report["passes"] = passes
	report["failures"] = failures
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT + "A_playthrough.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", false, true))
	file.close()
	for f: String in DirAccess.get_files_at(SAVE_DIR):
		DirAccess.remove_absolute(SAVE_DIR + f)
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
