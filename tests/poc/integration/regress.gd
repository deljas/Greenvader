extends SceneTree
## POC-09 integration B: main regressions on town_01, one run each, game-time fast-forward (headless OK).
##   godot --headless --path <repo> --script res://tests/poc/integration/regress.gd
## B1 resources at zero, B2 downed (no rollback), B3 stable area not re-invaded (covered by A6/A11, re-checked in B4c),
## B4 save/load in germinating / combat / downed / stable+FarSeed states, B5 pause, B6 resolution switch, B7 occlusion, B8 day/night.
## Saves only in user://poc_saves_integration/ (own namespace). The bot never uses debug refill or direct state writes.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const Day: GDScript = preload("res://scripts/poc/environment/poc_day.gd")
const Cmp: GDScript = preload("res://tests/poc/integration/cmp.gd")
const Bot: GDScript = preload("res://tests/poc/integration/bot.gd")
const OUT: String = "res://evidence/helper/03/"
const SAVE_DIR: String = "user://poc_saves_integration/"
const STAND: Vector2i = Vector2i(78, 84)
const WATER_BANK: Vector2i = Vector2i(44, 55)

var failures: int = 0
var passes: int = 0
var checks: Array[String] = []
var info: Dictionary = {}
var sessions: Array[RefCounted] = []

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
	sessions.append(made)
	return made

func run_for(s: RefCounted, seconds: float) -> void:
	var left: float = seconds
	while left > 0.0:
		var piece: float = minf(left, 0.25)
		s.advance_game(piece)
		left -= piece

func world_hash(s: RefCounted) -> int:
	var st: WorldState = s.state
	return [st.stage, st.growth, st.moisture, st.fertility, st.occupant, st.plant_id, st.zone_state].hash()

func static_hash(s: RefCounted) -> int:
	return [s.state.terrain, s.state.target, s.state.occupant].hash()

func clean_dir() -> void:
	for file: String in DirAccess.get_files_at(SAVE_DIR):
		DirAccess.remove_absolute(SAVE_DIR + file)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	clean_dir()
	_b1_resources()
	_b2_downed()
	_b4_save_states()
	await _b5_to_b8()
	for s: RefCounted in sessions:
		s.close()
	clean_dir()
	info["checks"] = checks
	info["passes"] = passes
	info["failures"] = failures
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT + "B_regress.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(info, "  ", false, true))
	file.close()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)

# ---------------------------------------------------------------- B1 resources at zero

func _b1_resources() -> void:
	var s: RefCounted = make_session()
	var st: WorldState = s.state
	var bot: RefCounted = Bot.new(s)
	bot.guard_until = 3000.0
	# --- water to zero first (real water shots at the safe-zone ground next to the frontier spot)
	bot.go(STAND, 60.0, 2.0)
	var guard: int = 0
	var aim_water: Vector2 = Bot.cpx(STAND + Vector2i(-6, 0))
	while s.play.water >= s.play_tuning.water_cost_per_shot and guard < 60:
		guard += 1
		bot.try_fire(true, aim_water)
		bot.frame()
	bot.idle(1.0)
	var no_water: Dictionary = s.fire(true, aim_water)
	var msg_water: String = s.last_message
	check("B1.water_zero_blocks_water_shot", s.play.water < s.play_tuning.water_cost_per_shot and not bool(no_water["ok"]) and String(no_water["reason"]) == "no_water", "water=%.1f reason=%s msg=%s water shots=%d" % [s.play.water, no_water["reason"], msg_water, bot.water_shots])
	# --- sow with no water at all and watch the growth go on
	var sown_info: Dictionary = bot.sow(STAND, 8, false)
	var sown: PackedInt32Array = sown_info["sown"]
	var landing: Array[Vector2i] = sown_info["landing"]
	var moist_sum: int = 0
	var growth_before: int = 0
	var stage_before: int = 0
	for i: int in sown:
		moist_sum += st.moisture[i]
		growth_before += st.growth[i]
		stage_before += st.stage[i]
	var water_at: float = s.play.water
	bot.idle(12.0)
	var growth_after: int = 0
	var stage_after: int = 0
	var moist_after: int = 0
	for i: int in sown:
		growth_after += st.growth[i]
		stage_after += st.stage[i]
		moist_after += st.moisture[i]
	check("B1.growth_continues_without_water", sown.size() > 0 and s.play.water <= water_at and bot.water_shots == 10 and (growth_after > growth_before or stage_after > stage_before), "water stays %.1f (10 water shots were all fired before sowing); sown tiles=%d, ground moisture sum %d -> %d (natural, not from the player's water); growth sum %d -> %d, stage sum %d -> %d over 12 s" % [s.play.water, sown.size(), moist_sum, moist_after, growth_before, growth_after, stage_before, stage_after])
	# --- seeds to zero by really shooting them, then recover at the supply source
	guard = 0
	while s.play.seeds > 0 and guard < 60:
		guard += 1
		bot.try_fire(false, Bot.cpx(landing[guard % landing.size()]))
		bot.frame()
	bot.idle(1.0)
	var no_seed: Dictionary = s.fire(false, Bot.cpx(landing[0]))
	var msg_seed: String = s.last_message
	check("B1.seeds_zero_blocks_seed_shot", s.play.seeds == 0 and not bool(no_seed["ok"]) and String(no_seed["reason"]) == "no_seed", "seeds=%d reason=%s msg=%s seed shots=%d" % [s.play.seeds, no_seed["reason"], msg_seed, bot.seed_shots])
	var t0: float = s.clock.elapsed
	var wait: float = bot.restock(6, 200.0)
	var seeds_after: int = s.play.seeds
	var fired: Dictionary = s.fire(false, Bot.cpx(landing[0]))
	check("B1.seeds_recover_at_source", seeds_after >= 6 and bool(fired["ok"]), "seeds 0 -> %d in %.1f s game time (%.1f s waiting at the source), shot ok=%s" % [seeds_after, s.clock.elapsed - t0, wait, fired["ok"]])
	# --- refill at the waterside
	var t_water: float = s.clock.elapsed
	var arrived: bool = bot.go(WATER_BANK, 120.0, 3.0)
	var refilled_flag: bool = false
	var guard2: int = 0
	var water_start: float = s.play.water
	while s.play.water < s.play_tuning.water_max - 0.01 and guard2 < 200:
		guard2 += 1
		bot.idle(0.5)
		refilled_flag = refilled_flag or s.play.refilling
	var water_full: float = s.play.water
	var walk_back: bool = bot.go(STAND, 120.0, 2.0)
	var shot_ok: Dictionary = s.fire(true, aim_water)
	check("B1.water_refill_at_waterside", arrived and refilled_flag and water_full >= s.play_tuning.water_max - 0.01 and bool(shot_ok["ok"]), "arrived=%s refilling seen=%s water %.0f -> %.0f, round trip %.1f s game time, water shot after return ok=%s (back=%s)" % [arrived, refilled_flag, water_start, water_full, s.clock.elapsed - t_water, shot_ok["ok"], walk_back])
	info["b1"] = {"downs": bot.down_times.size(), "events": Array(bot.events)}
	bot.detach()

# ---------------------------------------------------------------- B2 downed

func _b2_downed() -> void:
	var s: RefCounted = make_session()
	var st: WorldState = s.state
	var bot: RefCounted = Bot.new(s)
	bot.guard_until = 3000.0
	var sown_info: Dictionary = bot.sow(STAND, 8, true)
	var source: Vector2i = bot.nearest_source_cell()
	bot.go(source, 60.0, 2.0)
	var t_end: float = s.clock.elapsed + 90.0
	while s.clock.elapsed < t_end:
		bot.idle(2.0)
	var greened_before: int = st.greened_count
	var zone_before: PackedByteArray = st.zone_state.duplicate()
	var nests_before: int = s.enemies.alive_nest_count(-1)
	var sown: PackedInt32Array = sown_info["sown"]
	var sown_stage_before: int = 0
	for i: int in sown:
		sown_stage_before += st.stage[i]
	# Walk (unarmed: engage off, no firing) to a spot beside the north nest and let the boars hit until downed.
	bot.engage = false
	var nest: Nest = s.enemies.nest_by_id(3)
	var no_skip: Array[Vector2i] = []
	var spot: Vector2i = bot.shoot_spot(nest.center_px(Config.TILE_PX), no_skip)
	var arrived: bool = bot.go(spot, 90.0, 2.5)
	# Unarmed: walk into the nearest boar until the contact damage downs the player.
	var field: PackedInt32Array = PackedInt32Array()
	var field_age: int = 1 << 30
	var guard: int = 0
	while not s.play.health.downed and guard < 3000:
		guard += 1
		if s.enemies.boars.is_empty():
			bot.idle(1.0)
			continue
		# Nearest boar by WALKING distance (a boar behind a wall cannot be reached; walking into the wall never makes contact).
		var from_player: PackedInt32Array = bot.field_from(bot.cell_now())
		var target: Boar = null
		var best_d: int = 1 << 30
		for boar: Boar in s.enemies.boars:
			var bc: Vector2i = Coords.logic_to_cell(boar.pos)
			var near_c: Vector2i = bc if bot.is_clear_cell(bc) else bot.nearest_clear(bc)
			var d: int = from_player[near_c.y * st.width + near_c.x]
			if d >= 0 and d < best_d:
				best_d = d
				target = boar
		if target == null:
			bot.idle(1.0)
			continue
		var goal: Vector2i = Coords.logic_to_cell(target.pos)
		if field_age >= 5:
			field = bot.field_from(goal)
			field_age = 0
		field_age += 1
		bot.step_along(field, goal if bot.is_clear_cell(goal) else bot.nearest_clear(goal))
	var was_downed: bool = s.play.health.downed
	var pos_down: Vector2 = s.position
	var hp_down: int = s.play.hp
	var move_while_down: Vector2 = s.walk(Vector2(1, 0), 0.1)
	var fire_while_down: Dictionary = s.fire(false, s.position + Vector2(20, 0))
	var greened_down: int = st.greened_count
	check("B2.contact_damage_downs_the_player", arrived and was_downed and hp_down == 0 and move_while_down == Vector2.ZERO and String(fire_while_down["reason"]) == "downed", "arrived=%s downed=%s hp=%d hits=%d walk=%s fire=%s at cell %s zone %d" % [arrived, was_downed, hp_down, s.play.health.hit_count, move_while_down, fire_while_down["reason"], Coords.logic_to_cell(pos_down), s.player_zone()])
	# The fruit production draws its plant around the PLAYER position. The loaded copy is already back at the start while the original
	# still lies at the nest, so a production tick inside the remaining lying time would legitimately differ. Let such a tick pass
	# (still lying: <= downed_seconds) before saving, so that the lockstep comparison below is about the loading, not about that tick.
	var tick_guard: int = 0
	while s.play.health.downed and tick_guard < 80:
		tick_guard += 1
		var to_tick: float = float(s.play.production_ticks + 1) * s.play_tuning.plant_production_interval_seconds - s.play.production_time
		var lying_left: float = float(s.play.health.downed_steps) / float(maxi(s.play_tuning.health_step_hz, 1))
		if to_tick > lying_left + 0.05 or lying_left < 0.2:
			break
		s.advance_game(0.05)
	var still_down: bool = s.play.health.downed
	greened_down = st.greened_count
	# Save while downed -> new session (state restored as 'already returned', see PlayerHealth.load_dict).
	clean_dir()
	var saved: Dictionary = PocSave.save(s, SAVE_DIR, {"resolution_index": 0})
	var loaded: Dictionary = PocSave.load_slot(SAVE_DIR, false, Callable(self, "make_session"))
	var copy: RefCounted = loaded["session"] if bool(loaded["ok"]) else null
	var copy_ok: bool = bool(saved["ok"]) and copy != null and not copy.play.health.downed and copy.player_zone() == 0 and copy.play.hp == copy.play.hp_max
	var copy_info: String = "saved=%s loaded=%s" % [saved["ok"], loaded["ok"]]
	if copy != null:
		copy_info += " copy: downed=%s hp=%d/%d zone=%d position=%s world_equal=%s" % [copy.play.health.downed, copy.play.hp, copy.play.hp_max, copy.player_zone(), Coords.logic_to_cell(copy.position), world_hash(copy) == world_hash(s)]
	check("B4d.downed_save_loads_as_returned_with_world_intact", still_down and copy_ok and world_hash(copy) == world_hash(s) and copy.state.greened_count == greened_down and copy.enemies.alive_nest_count(-1) == nests_before, copy_info)
	# The original now lies down for 1.5 s and returns; advance both in lockstep and compare.
	bot.stop_when = Callable()
	for i: int in 120:
		s.advance_game(0.25)
		if copy != null:
			copy.advance_game(0.25)
	var diff: String = Cmp.same_state(s, copy) if copy != null else "no copy"
	check("B4d.downed_original_and_loaded_copy_match_after_30s", diff == "", "first difference: %s" % [diff if diff != "" else "none"])
	var revived_ok: bool = not s.play.health.downed and s.player_zone() == 0 and s.play.hp == s.play.hp_max
	var zone_same: bool = st.zone_state == zone_before
	var sown_stage_after: int = 0
	for i: int in sown:
		sown_stage_after += st.stage[i]
	check("B2.return_to_safe_zone_without_rollback", revived_ok and zone_same and st.greened_count >= greened_before and sown_stage_after >= sown_stage_before and s.enemies.alive_nest_count(-1) == nests_before, "revived=%s zone=%d hp=%d/%d; greened %d -> %d -> %d; zone_state before=%s now=%s; nests alive %d -> %d; sown stage sum %d -> %d; downs=%d" % [revived_ok, s.player_zone(), s.play.hp, s.play.hp_max, greened_before, greened_down, st.greened_count, zone_before, st.zone_state, nests_before, s.enemies.alive_nest_count(-1), sown_stage_before, sown_stage_after, s.play.health.down_count])
	info["b2"] = {"down_count": s.play.health.down_count, "hits": s.play.health.hit_count, "events": Array(bot.events)}
	bot.detach()

# ---------------------------------------------------------------- B4 save / load states

func lockstep(a: RefCounted, b: RefCounted, seconds: float) -> void:
	var steps: int = int(seconds / 0.25)
	for i: int in steps:
		a.advance_game(0.25)
		b.advance_game(0.25)

func save_and_clone(s: RefCounted, resolution: int = 0) -> RefCounted:
	clean_dir()
	var saved: Dictionary = PocSave.save(s, SAVE_DIR, {"resolution_index": resolution})
	var loaded: Dictionary = PocSave.load_slot(SAVE_DIR, false, Callable(self, "make_session"))
	if not bool(saved["ok"]) or not bool(loaded["ok"]):
		print("save/load failed: ", saved.get("reason", ""), loaded.get("reason", ""))
		return null
	return loaded["session"]

func _b4_save_states() -> void:
	# --- germinating
	var s: RefCounted = make_session()
	var bot: RefCounted = Bot.new(s)
	var info_sow: Dictionary = bot.sow(STAND, 8, true)
	bot.idle(3.0)
	var growing: int = 0
	for i: int in s.state.tile_count():
		if s.state.stage[i] >= WorldState.STAGE_SEED and s.state.stage[i] < WorldState.STAGE_MATURE and s.state.target[i] == 1 and s.state.zone_at(i) == 1:
			growing += 1
	var copy: RefCounted = save_and_clone(s)
	var diff_now: String = Cmp.same_state(s, copy) if copy != null else "no copy"
	lockstep(s, copy, 30.0)
	var diff_later: String = Cmp.same_state(s, copy) if copy != null else "no copy"
	check("B4a.germinating_save_load_same_progress", growing > 0 and diff_now == "" and diff_later == "", "growing tiles at save=%d, t=%.1f s; diff at load='%s', diff after +30 s='%s'; greened %d/%d" % [growing, s.clock.elapsed - 30.0, diff_now, diff_later, s.state.greened_count, copy.state.greened_count])
	bot.detach()
	# --- combat
	var c: RefCounted = make_session()
	var cbot: RefCounted = Bot.new(c)
	cbot.guard_until = 2000.0
	cbot.idle(60.0)
	var nest: Nest = c.enemies.nest_by_id(3)
	cbot.go(Vector2i(88, 86), 20.0, 3.0)
	cbot.stop_when = func() -> bool: return nest.hp < nest.hp_max and c.enemies.boars.size() >= 1 and c.projectiles.shots.size() > 0
	var guard: int = 0
	while not cbot.stopped and guard < 6 and nest.alive:
		guard += 1
		cbot.kill_nest(nest, 120.0)
		if c.play.seeds < 4:
			cbot.restock(30, 120.0)
	var in_combat: bool = c.enemies.boars.size() >= 1 and nest.hp < nest.hp_max and nest.alive
	var shots_flying: int = c.projectiles.shots.size()
	var boars_at_save: int = c.enemies.boars.size()
	var copy2: RefCounted = save_and_clone(c)
	var dn: String = Cmp.same_state(c, copy2) if copy2 != null else "no copy"
	lockstep(c, copy2, 20.0)
	var dl: String = Cmp.same_state(c, copy2) if copy2 != null else "no copy"
	check("B4b.combat_save_load_same_progress", in_combat and dn == "" and dl == "", "boars=%d nest hp=%d/%d shots in flight at save=%d (dropped and refunded by design), seeds %d, t=%.1f; diff at load='%s', after +20 s='%s'; boars now %d/%d hp %d/%d" % [boars_at_save, nest.hp, nest.hp_max, shots_flying, c.play.seeds, c.clock.elapsed - 20.0, dn, dl, c.enemies.boars.size(), copy2.enemies.boars.size(), c.play.hp, copy2.play.hp])
	cbot.detach()
	info["b4"] = {"germinating": {"growing": growing}, "combat": {"boars": boars_at_save, "shots_in_flight": shots_flying}}

# ---------------------------------------------------------------- B5 .. B8 (scene instance)

func _frames(n: int) -> void:
	for i: int in n:
		await process_frame

func _b5_to_b8() -> void:
	var main: Node = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(2)
	var s: RefCounted = main.session
	main.save_dir = SAVE_DIR
	# --- B5 pause: play 75 s through tick() first (enemies exist), then pause.
	for i: int in 300:
		main.tick(0.25, Vector2.ZERO)
	var boars_before: int = s.enemies.boars.size()
	var before: Dictionary = {"elapsed": s.clock.elapsed, "world": world_hash(s), "pos": s.position, "water": s.play.water, "seeds": s.play.seeds, "pickup_age": s.play.pickups.items[0]["age"] if s.play.pickups.count() > 0 else 0.0, "enemies": JSON.stringify(s.enemies.to_dict()), "growth_ticks": s.clock.growth_ticks, "spread_ticks": s.clock.spread_ticks, "enemy_time": s.enemies.time, "play_elapsed": s.play.elapsed}
	main.toggle_pause()
	var paused_flag: bool = s.paused
	for i: int in 200:
		main.tick(0.25, Vector2(1, 0))
	var fire_paused: Dictionary = s.fire(false, s.position + Vector2(10, 0))
	var after: Dictionary = {"elapsed": s.clock.elapsed, "world": world_hash(s), "pos": s.position, "water": s.play.water, "seeds": s.play.seeds, "pickup_age": s.play.pickups.items[0]["age"] if s.play.pickups.count() > 0 else 0.0, "enemies": JSON.stringify(s.enemies.to_dict()), "growth_ticks": s.clock.growth_ticks, "spread_ticks": s.clock.spread_ticks, "enemy_time": s.enemies.time, "play_elapsed": s.play.elapsed}
	check("B5.pause_stops_everything", paused_flag and before == after and not bool(fire_paused["ok"]) and String(fire_paused["reason"]) == "paused", "boars=%d; 200 paused ticks with walk input and a shot: elapsed %.2f -> %.2f, position kept, enemies/world/pickups/growth unchanged, fire reason=%s" % [boars_before, before["elapsed"], after["elapsed"], fire_paused["reason"]])
	main.toggle_pause()
	var t_resume: float = s.clock.elapsed
	main.tick(5.0, Vector2.ZERO)
	var jump: float = s.clock.elapsed - t_resume
	var t2: float = s.clock.elapsed
	main.tick(0.016, Vector2.ZERO)
	var one_frame: float = s.clock.elapsed - t2
	check("B5.resume_does_not_catch_up", not s.paused and jump <= 0.25 + 0.0001 and absf(one_frame - 0.016) < 0.0001, "after resume a 5 s long frame advances %.3f s (cap 0.25), a 16 ms frame advances %.4f s" % [jump, one_frame])
	main.open_pause_menu()
	var menu_paused: bool = s.paused and main.menu == &"pause"
	var e_menu: float = s.clock.elapsed
	for i: int in 40:
		main.tick(0.25, Vector2.ZERO)
	var menu_frozen: bool = s.clock.elapsed == e_menu
	main.close_menu()
	check("B5.pause_menu_pauses_and_restores", menu_paused and menu_frozen and not s.paused and main.menu == &"", "menu paused=%s frozen=%s resumed unpaused=%s" % [menu_paused, menu_frozen, not s.paused])
	# --- B6 resolution switch 640 <-> 960
	var cell: Vector2i = Vector2i(88, 80)
	s.position = Coords.cell_center_logic(cell)
	s.set_aim(s.position + Vector2(24, -16))
	main.tick(0.0, Vector2.ZERO)
	var snap0: Dictionary = _view_snapshot(main)
	var ok1: bool = main.set_resolution(1, Vector2i(1920, 1080))
	main.tick(0.0, Vector2.ZERO)
	var snap1: Dictionary = _view_snapshot(main)
	var ok2: bool = main.set_resolution(0, Vector2i(1920, 1080))
	main.tick(0.0, Vector2.ZERO)
	var snap2: Dictionary = _view_snapshot(main)
	var same_logic: bool = snap0["pos"] == snap1["pos"] and snap0["pos"] == snap2["pos"] and snap0["aim"] == snap1["aim"] and snap0["aim"] == snap2["aim"] and snap0["size_m"] == snap1["size_m"] and snap0["size_m"] == snap2["size_m"]
	var frac_ok: bool = (snap0["aim_frac"] as Vector2).distance_to(snap1["aim_frac"]) < 0.004 and (snap0["aim_frac"] as Vector2).distance_to(snap2["aim_frac"]) < 0.004 and (snap0["player_frac"] as Vector2).distance_to(snap1["player_frac"]) < 0.004
	check("B6.resolution_switch_keeps_position_aim_view", ok1 and ok2 and same_logic and frac_ok and snap0["res"] == Vector2i(640, 360) and snap1["res"] == Vector2i(960, 540) and snap2["res"] == snap0["res"], "640: %s | 960: %s | back: %s" % [snap0, snap1, snap2])
	# --- B7 occlusion
	_b7_occlusion(main)
	# --- B8 day / night
	_b8_day_night(main)
	main.queue_free()
	await _frames(2)

func _view_snapshot(main: Node) -> Dictionary:
	var s: RefCounted = main.session
	var res: Vector2i = main.current_resolution()
	var aim_g: Vector2 = Coords.logic_to_ground(s.aim)
	var pos_g: Vector2 = Coords.logic_to_ground(s.position)
	return {"res": res, "pos": s.position, "aim": s.aim, "size_m": main.camera.size, "render": main.render_view.size, "aim_frac": main.camera.unproject_position(Vector3(aim_g.x, 0, aim_g.y)) / Vector2(res), "player_frac": main.camera.unproject_position(Vector3(pos_g.x, 0, pos_g.y)) / Vector2(res)}

func _raw(main: Node, foot: Vector3) -> Array:
	var ov: Node = main.occlusion_view
	var keys: Array = ov.occlusion.raw_occluders(ov.occlusion.sample_points(foot, 1.42, main.camera.global_basis.x), main.camera.global_basis.z).keys()
	keys.sort()
	return keys

func _b7_occlusion(main: Node) -> void:
	var s: RefCounted = main.session
	var ov: Node = main.occlusion_view
	var half: Vector2 = Config.player_half_px()
	var found_behind: Dictionary = {}
	var found_front: Dictionary = {}
	for entry: Dictionary in ov.occlusion.entries:
		var group: String = String(entry["group"])
		var inst: Dictionary = s.placement.get_instance(String(entry["ids"][0]))
		if String(inst["kind"]) != "building":
			continue
		var p: Vector2 = inst["pos"]
		for k: int in range(2, 14):
			var foot: Vector3 = Vector3(p.x - 0.5 * float(k) * 0.707107, 0.04, p.y - 0.5 * float(k) * 0.707107)
			var logic: Vector2 = Coords.ground_to_logic(Vector2(foot.x, foot.z))
			if Walker.is_clear(s.state, Config.TILE_PX, logic, half) and _raw(main, foot) == [group]:
				found_behind = {"group": group, "logic": logic, "k": k}
				break
		if found_behind.is_empty():
			continue
		for k: int in range(-3, -16, -1):
			var foot2: Vector3 = Vector3(p.x - 0.5 * float(k) * 0.707107, 0.04, p.y - 0.5 * float(k) * 0.707107)
			var logic2: Vector2 = Coords.ground_to_logic(Vector2(foot2.x, foot2.z))
			if Walker.is_clear(s.state, Config.TILE_PX, logic2, half) and _raw(main, foot2).is_empty():
				found_front = {"logic": logic2, "k": k}
				break
		if not found_front.is_empty():
			break
		found_behind = {}
	if found_behind.is_empty() or found_front.is_empty():
		check("B7.occlusion_behind_building_only_target", false, "no building with a walkable behind/front pair found")
		return
	var group_id: String = found_behind["group"]
	var group_ids: Array = []
	for entry: Dictionary in ov.occlusion.entries:
		if String(entry["group"]) == group_id:
			group_ids = entry["ids"]
	s.position = found_behind["logic"]
	for i: int in 16:
		main.tick(0.05, Vector2.ZERO)
	var occluded: PackedStringArray = ov.occlusion.occluded_groups()
	var faded: PackedStringArray = ov.faded_instances()
	var only_target: bool = occluded == PackedStringArray([group_id])
	for id: String in faded:
		only_target = only_target and group_ids.has(id)
	var target_alpha: float = main.placement_view.instance_alpha(String(group_ids[0]))
	var others_opaque: bool = true
	for id: String in main.placement_view.materials:
		if not group_ids.has(id) and absf(main.placement_view.instance_alpha(id) - 1.0) > 0.0001:
			others_opaque = false
	var world_before: int = static_hash(s)
	check("B7.occlusion_behind_building_only_target", only_target and target_alpha < 0.99 and others_opaque and not faded.is_empty(), "group %s at k=%d: occluded=%s faded=%s alpha=%.2f others opaque=%s" % [group_id, found_behind["k"], occluded, faded, target_alpha, others_opaque])
	s.position = found_front["logic"]
	for i: int in 40:
		main.tick(0.05, Vector2.ZERO)
	var restored: bool = ov.occlusion.occluded_groups().is_empty() and ov.faded_instances().is_empty()
	for id: String in main.placement_view.materials:
		restored = restored and absf(main.placement_view.instance_alpha(id) - 1.0) < 0.0001
	check("B7.occlusion_restored_in_front", restored and static_hash(s) == world_before, "front k=%d: occluded=%s faded=%s, all instance alpha 1.0, terrain/targets/occupancy unchanged" % [found_front["k"], ov.occlusion.occluded_groups(), ov.faded_instances()])
	info["b7"] = {"behind": {"group": group_id, "k": found_behind["k"], "cell": [Coords.logic_to_cell(found_behind["logic"]).x, Coords.logic_to_cell(found_behind["logic"]).y]}, "front": {"k": found_front["k"], "cell": [Coords.logic_to_cell(found_front["logic"]).x, Coords.logic_to_cell(found_front["logic"]).y]}}

func _b8_day_night(main: Node) -> void:
	var s: RefCounted = main.session
	var elapsed0: float = s.clock.elapsed
	var hour0: float = s.day_hour()
	var expected0: float = Day.hour_at(elapsed0, s.env_tuning)
	s.paused = true
	main.tick(0.25, Vector2.ZERO)
	var hour_paused: float = s.day_hour()
	s.paused = false
	var day_seconds: float = float(s.env_tuning["day_seconds"])
	check("B8.hour_derives_from_game_clock", absf(hour0 - expected0) < 1e-9 and absf(hour_paused - hour0) < 1e-9, "elapsed %.2f s -> hour %.3f (formula %.3f); unchanged while paused" % [elapsed0, hour0, expected0])
	# Fast-forward the game clock to 06:30 / 09:00 / 12:00 / 15:00 / 17:30 and read the key light direction through the real tick().
	var samples: Array = []
	var east_seen: float = -2.0
	var south_seen: float = -2.0
	var west_seen: float = -2.0
	for target_hour: float in [10.0, 12.0, 14.0, 16.0, 17.5]:
		var need: float = fposmod(target_hour - s.day_hour(), 24.0) / 24.0 * day_seconds
		run_for(s, need)
		main.tick(0.0, Vector2.ZERO)
		var source: Vector3 = main.sun.global_basis.z
		var horizontal: Vector2 = Vector2(source.x, source.z).normalized()
		var east: float = horizontal.dot(Vector2(Day.EAST.x, Day.EAST.z))
		var south: float = horizontal.dot(Vector2(Day.SOUTH.x, Day.SOUTH.z))
		var west: float = horizontal.dot(Vector2(Day.WEST.x, Day.WEST.z))
		var expect: Vector3 = Day.state(s.day_hour(), s.env_tuning)["source"]
		samples.append({"hour": snappedf(s.day_hour(), 0.01), "east": snappedf(east, 0.001), "south": snappedf(south, 0.001), "west": snappedf(west, 0.001), "elevation_deg": snappedf(rad_to_deg(asin(clampf(source.y, -1.0, 1.0))), 0.1), "matches_formula": source.is_equal_approx(expect.normalized())})
	var first: Dictionary = samples[0]
	var noon: Dictionary = samples[1]
	var last: Dictionary = samples[samples.size() - 1]
	var ordered: bool = float(first["east"]) > float(first["west"]) and float(noon["south"]) > 0.95 and float(last["west"]) > float(last["east"])
	var azimuth_progress: bool = true
	var prev_east: float = 2.0
	for sample: Dictionary in samples:
		azimuth_progress = azimuth_progress and float(sample["east"]) < prev_east and bool(sample["matches_formula"])
		prev_east = float(sample["east"])
	check("B8.sun_goes_east_south_west", ordered and azimuth_progress and float(noon["elevation_deg"]) > float(first["elevation_deg"]) and float(noon["elevation_deg"]) > float(last["elevation_deg"]), "samples=%s" % [samples])
	# Night: moon light, sun power zero, growth factor exactly 1.
	var night_need: float = fposmod(1.0 - s.day_hour(), 24.0) / 24.0 * day_seconds
	run_for(s, night_need)
	main.tick(0.0, Vector2.ZERO)
	check("B8.night_uses_moon_and_unit_sunlight", main.env_view.last_is_moon and absf(s.sunlight_factor() - 1.0) < 1e-9 and s.day_state()["night"] > 0.9, "hour %.2f moon=%s sunlight factor=%.4f night=%.2f light energy=%.3f" % [s.day_hour(), main.env_view.last_is_moon, s.sunlight_factor(), s.day_state()["night"], main.sun.light_energy])
	info["b8"] = {"samples": samples}
