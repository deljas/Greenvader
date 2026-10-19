extends SceneTree
## WTH-03 integration A: one full run on town_01 (fixed seeds, natural weather / day) through the normal operation API only.
##   godot --headless --path <repo> --script res://tests/poc/integration/full_flow.gd
## new game -> hand sow / water -> cultivated plants -> helper seeds (drops, nest rewards) -> helper plants placed, one moved
## (E lift -> Q -> click) -> viewpoint once (stop and return) -> 3 nests -> remaining boars -> stable -> NO input -> exact 100 %
## within far.completion_bound_seconds() -> completion display and the viewpoint notice through the real scene.
## No debug refill, no direct writes to play / world / enemy / helper state. Sound requests are recorded (standalone audio node).
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const Bot: GDScript = preload("res://tests/poc/integration/full_flow_bot.gd")
const AudioScript: GDScript = preload("res://scripts/poc/audio/poc_audio.gd")
const ViewpointScript: GDScript = preload("res://scripts/poc/view/poc_viewpoint.gd")
const OUT: String = "res://evidence/weather/03/"
const STAND: Vector2i = Vector2i(78, 84)
const SAFE: Rect2i = Rect2i(76, 74, 22, 22)

var failures: int = 0
var passes: int = 0
var report: Dictionary = {}
var checks: Array[String] = []
var s: RefCounted
var bot: RefCounted
var audio: Node
var viewpoint: RefCounted
var queue: Array[String] = ["gatlinger", "sprinkler", "army"]
var helper_events: Array[String] = []
var placed_log: Array[Dictionary] = []
var relocations: int = 0
var gat_placed_at: float = -1.0
var lookout: Dictionary = {}

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

func stage_counts(indices: PackedInt32Array) -> Array:
	var counts: Array = [0, 0, 0, 0, 0]
	for i: int in indices:
		counts[s.state.stage[i]] += 1
	return counts

func safe_distance(x: int, y: int) -> float:
	var dx: int = maxi(maxi(SAFE.position.x - x, x - (SAFE.end.x - 1)), 0)
	var dy: int = maxi(maxi(SAFE.position.y - y, y - (SAFE.end.y - 1)), 0)
	return sqrt(float(dx * dx + dy * dy))

var want_distance: float = 10.0
var bad_pickups: Array[Vector2i] = []

## Blocks near `want_distance` cells outside the safe zone (a moderate front, not the far corner next to the nests).
func frontier_score(origin: Vector2i) -> float:
	return -absf(safe_distance(origin.x + 2, origin.y + 2) - want_distance)

func end_cultivation_selection() -> void:
	var guard: int = 0
	while s.play.selected_def().is_cultivated() and guard < 8:
		s.cycle_plant(1)
		guard += 1

func refresh_clear() -> void:
	var half: Vector2 = Config.player_half_px()
	for y: int in bot.height:
		for x: int in bot.width:
			bot.clear[y * bot.width + x] = 1 if Walker.is_clear(s.state, Config.TILE_PX, Bot.cpx(Vector2i(x, y)), half) else 0

func find_block(score: Callable) -> Vector2i:
	var st: WorldState = s.state
	var field: PackedInt32Array = bot.field_from(bot.cell_now())
	var best: Vector2i = Vector2i(-1, -1)
	var best_score: float = -1.0e18
	for oy: int in range(1, st.height - 5):
		for ox: int in range(1, st.width - 5):
			var ok: bool = true
			for y: int in range(oy, oy + 4):
				for x: int in range(ox, ox + 4):
					var i: int = st.index_of(x, y)
					if not (st.is_walkable(x, y) and st.target[i] == 1 and st.occupant[i] == 0 and st.stage[i] == WorldState.STAGE_MATURE and st.terrain_defs[st.terrain[i]].plantable):
						ok = false
						break
				if not ok:
					break
			if not ok or field[(oy + 2) * st.width + ox + 2] < 0 or field[(oy + 2) * st.width + ox + 2] > 140:
				continue
			var value: float = float(score.call(Vector2i(ox, oy)))
			if value > best_score:
				best_score = value
				best = Vector2i(ox, oy)
	return best

## Walk next to the block, Q (cycle_helper_mode) to the kind, left click (place_helper); records the place sound request.
func place_at(kind: String, origin: Vector2i) -> Dictionary:
	var centre: Vector2 = s.helpers.block_center_px(origin)
	var stand: Vector2i = bot.nearest_clear(Coords.logic_to_cell(centre))
	bot.go(stand, 90.0, 3.0)
	s.set_aim(centre)
	s.end_helper_mode()
	var guard: int = 0
	while s.helper_active_kind() != kind and guard < 6:
		s.cycle_helper_mode()
		guard += 1
	var result: Dictionary = s.place_helper(centre)
	if bool(result["ok"]):
		audio.play_action(&"place")
	s.end_helper_mode()
	refresh_clear()
	return result

func place_cultivated(label: String, targets: Array[Vector2i]) -> bool:
	var guard: int = 0
	while s.selected_label() != label and guard < 6:
		s.cycle_plant(1)
		guard += 1
	var before: int = s.play.cultivation.plants.size()
	for target: Vector2i in targets:
		if s.play.available_seeds() < 3:
			return false
		bot.go(bot.nearest_clear(target + Vector2i(-6, 0)), 60.0, 3.0)
		var attempts: int = 0
		while not bot.try_fire(false, Bot.cpx(target)) and attempts < 40:
			bot.frame()
			attempts += 1
		bot.idle(1.6)
		if s.play.cultivation.plants.size() > before:
			refresh_clear()
			return true
	return false

func nearest_helper_pickup(max_path: int) -> Vector2i:
	var field: PackedInt32Array = bot.field_from(bot.cell_now())
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 1 << 30
	for item: Dictionary in s.helpers.pickups:
		var cell: Vector2i = Coords.logic_to_cell(Vector2(float(item["x"]), float(item["y"])))
		var d: int = field[cell.y * s.state.width + cell.x]
		if d >= 0 and d <= max_path and d < best_d and not bad_pickups.has(cell):
			best_d = d
			best = cell
	return best

func relocate(kind: String) -> bool:
	var target_plant: Dictionary = {}
	for plant: Dictionary in s.helpers.plants:
		if String(plant["kind"]) == kind:
			target_plant = plant
	if target_plant.is_empty():
		return false
	var rect: Rect2i = s.helpers.plant_rect(target_plant)
	want_distance = safe_distance(rect.position.x + 2, rect.position.y + 2) + 6.0
	var target: Vector2i = find_block(Callable(self, "frontier_score"))
	want_distance = 10.0
	if target.x < 0 or Vector2(target - rect.position).length() < 4.0:
		return false
	bot.go(bot.nearest_clear(Vector2i(rect.position.x - 1, rect.position.y + 2)), 90.0, 3.0)
	var lifted: Dictionary = s.lift_helper()   # E
	refresh_clear()
	if not bool(lifted["ok"]):
		helper_events.append("t=%.1f lift failed %s" % [s.clock.elapsed, lifted["code"]])
		return false
	var carried_flag: bool = s.helpers.is_carrying()
	var placed: Dictionary = place_at(kind, target)
	if not bool(placed["ok"]):
		var again: Vector2i = find_block(Callable(self, "frontier_score"))
		if again.x >= 0:
			placed = place_at(kind, again)
	relocations += 1 if bool(placed["ok"]) else 0
	helper_events.append("t=%.1f %s lifted (carried=%s) and re-placed at %s -> %s %s" % [s.clock.elapsed, kind, str(carried_flag), str(target), str(placed["ok"]), String(placed["code"])])
	return true

## One helper chore (returns true when it spent game time): put down a carried plant, place the next kind, collect a helper seed, move the Gatlinger once.
func helper_chore() -> bool:
	if s.play.health.downed:
		bot.frame()
		return true
	if s.helpers.is_carrying():
		var o: Vector2i = find_block(Callable(self, "frontier_score"))
		if o.x >= 0:
			place_at(String(s.helpers.carried["kind"]), o)
		else:
			bot.idle(2.0)
		return true
	if not queue.is_empty() and s.helpers.seeds >= int(s.helpers.kind_def(queue[0])["cost"]) and s.helpers.total_count() < s.helpers.max_helpers:
		var origin: Vector2i = find_block(Callable(self, "frontier_score"))
		if origin.x >= 0:
			var kind: String = queue[0]
			var result: Dictionary = place_at(kind, origin)
			helper_events.append("t=%.1f place %s at %s -> %s %s (helper seeds left %d)" % [s.clock.elapsed, kind, str(origin), str(result["ok"]), String(result["code"]), s.helpers.seeds])
			if bool(result["ok"]):
				placed_log.append({"kind": kind, "t": snappedf(s.clock.elapsed, 0.1), "origin": [origin.x, origin.y], "seeds_before": s.helpers.seeds + int(s.helpers.kind_def(kind)["cost"]), "seeds_after": s.helpers.seeds})
				if kind == "gatlinger":
					gat_placed_at = s.clock.elapsed
				queue.remove_at(0)
				return true
	if not queue.is_empty() and not s.helpers.pickups.is_empty():
		var pickup: Vector2i = nearest_helper_pickup(70)
		if pickup.x >= 0:
			var before: int = s.helpers.seeds
			bot.go(pickup, 40.0, 3.0)
			bot.idle(0.3)
			if s.helpers.seeds <= before:
				bad_pickups.append(pickup)
			helper_events.append("t=%.1f helper seed pickup %s: %d -> %d" % [s.clock.elapsed, str(pickup), before, s.helpers.seeds])
			return true
	if relocations == 0 and gat_placed_at > 0.0 and s.clock.elapsed - gat_placed_at >= 60.0:
		gat_placed_at = s.clock.elapsed + 1.0e9
		return relocate("gatlinger")
	return false

func do_lookout() -> void:
	var spot: Vector2i = viewpoint.cell
	var reached: bool = bot.go(spot, 90.0, 2.0)
	var t0: float = s.clock.elapsed
	var pos0: Vector2 = s.position
	var snap: Dictionary = {"percent": s.greening_percent(), "clock": viewpoint.panel_values(s)["clock"], "weather": s.weather_text()}
	var entered: bool = viewpoint.enter(s)
	var dropped_before: int = audio.dropped_calm
	audio.play_action(&"seed")   # a stray action sound request while the world is stopped
	for k: int in 40:
		s.advance(0.25)
		s.walk(Vector2(1, 0), 0.25)
	var frozen: bool = s.clock.elapsed == t0 and s.position == pos0
	var panel: String = viewpoint.panel_text(s)
	var fire_refused: bool = not bool(s.fire(false, Bot.cpx(spot) + Vector2(20, 0))["ok"])
	var left: bool = viewpoint.leave(s)
	bot.idle(1.0)
	var resumed: bool = absf(s.clock.elapsed - (t0 + 1.0)) < 0.15
	lookout = {"reached_spot": reached, "entered": entered, "frozen": frozen, "fire_refused": fire_refused, "left": left, "resumed_exact_plus_1s": resumed, "panel": panel, "t_game": snappedf(t0, 0.1), "snap": snap, "calm_dropped_sounds": audio.dropped_calm - dropped_before}
	check("A-LOOKOUT.stop_and_return", reached and entered and frozen and fire_refused and left and resumed and not s.paused and audio.dropped_calm > dropped_before, str(lookout))

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	s = make_session()
	var st: WorldState = s.state
	audio = AudioScript.new()
	audio.muted = false
	audio.calm_provider = func() -> bool: return s.paused
	audio.attach(s)
	viewpoint = ViewpointScript.new(s)
	bot = Bot.new(s)
	bot.audio = audio
	bot.guard_until = 6000.0
	bot.log_every = 10.0
	check("A0.new_game_defaults", s.combat_mode and s.play.seeds == s.play_tuning.seed_start and is_equal_approx(s.play.water, s.play_tuning.water_start) and not s.debug_refill_enabled and s.clock.elapsed == 0.0 and viewpoint.has_spot and s.helpers.seeds == 0 and s.helpers.total_count() == 0, "seeds=%d water=%.0f hp=%d helpers seeds=%d viewpoint=%s" % [s.play.seeds, s.play.water, s.play.hp, s.helpers.seeds, str(viewpoint.cell)])
	report["start"] = bot.snapshot_row()
	report["bound_at_start_s"] = s.far.completion_bound_seconds()

	# ---- hand sow + water
	var seeds0: int = s.play.seeds
	var water0: float = s.play.water
	var res: Dictionary = bot.sow(STAND, 8, true)
	var sown: PackedInt32Array = res["sown"]
	check("A1.sow_and_water", (res["landing"] as Array).size() >= 4 and sown.size() >= 8 and s.play.seeds < seeds0 and s.play.water < water0, "landing=%d planted tiles=%d seeds %d->%d water %.0f->%.0f" % [(res["landing"] as Array).size(), sown.size(), seeds0, s.play.seeds, water0, s.play.water])
	var t_sow: float = s.clock.elapsed

	# ---- cultivated plants on the safe zone's mature ground
	var cultivated: int = 0
	var tries: int = 0
	while cultivated < 3 and tries < 5 and s.play.seeds >= 3:
		tries += 1
		var spots: Array[Vector2i] = []
		for k: int in 12:
			var n: int = (k + 2 * cultivated) % 12
			spots.append(Vector2i(79 + (n % 3) * 3, 76 + n * 2))
		if place_cultivated("にんじん" if cultivated % 2 == 0 else "キウイ", spots):
			cultivated += 1
	end_cultivation_selection()
	check("A2.cultivated_plants", cultivated >= 1, "cultivated plants placed=%d (selected via cycle_plant, shot onto mature ground)" % cultivated)

	# ---- viewpoint once
	do_lookout()

	# ---- grow, restock, collect helper seeds, place helper plants
	var source: Vector2i = bot.nearest_source_cell()
	var t_mature: float = -1.0
	var wait_limit: float = t_sow + 300.0
	while s.clock.elapsed < wait_limit and not bot.stopped:
		bot.idle(2.0)
		if helper_chore():
			bot.go(source, 100.0, 3.0)
			continue
		if s.play.seeds < 14:
			bot.restock(30, 100.0)
		if t_mature < 0.0 and int(stage_counts(sown)[4]) > 0:
			t_mature = s.clock.elapsed
		if t_mature >= 0.0 and s.clock.elapsed >= t_mature + 60.0 and s.helpers.total_count() >= 1:
			break
	var mid: Array = stage_counts(sown)
	check("A3.growth_and_first_helper", t_mature > 0.0 and int(mid[4]) > 0 and s.helpers.total_count() >= 1, "mature at +%.1f s; sown stages %s; helpers placed=%d; helper seeds drops=%d collected=%d" % [t_mature - t_sow, mid, s.helpers.total_count(), s.helpers.dropped_total, s.helpers.collected_total])
	report["mid"] = {"t": s.clock.elapsed, "helper_dropped": s.helpers.dropped_total, "helper_collected": s.helpers.collected_total, "placed": placed_log.duplicate(true)}

	# ---- nests
	var nest_log: Array = []
	var guard_rounds: int = 0
	while s.enemies.alive_nest_count(-1) > 0 and not bot.stopped and guard_rounds < 40:
		guard_rounds += 1
		if helper_chore():
			continue
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
		var t0: float = s.clock.elapsed
		var result: String = bot.kill_nest(best)
		nest_log.append({"nest": best.id, "result": result, "t_start": snappedf(t0, 0.1), "t_end": snappedf(s.clock.elapsed, 0.1), "helper_seeds_after": s.helpers.seeds, "helpers": s.helpers.total_count()})
	check("A4.three_nests_destroyed", s.enemies.alive_nest_count(-1) == 0 and s.enemies.total_nests_destroyed == 3 and st.zone_state[1] >= WorldState.ZONE_CLEARING, "nest log=%s downs=%d" % [nest_log, bot.down_times.size()])
	report["nests"] = nest_log
	var spawned_at_clear: int = s.enemies.total_spawned
	var hunted: int = bot.hunt_boars(500.0)
	var g2: int = 0
	while st.zone_state[1] < WorldState.ZONE_STABLE and g2 < 50 and not bot.stopped:
		g2 += 1
		bot.idle(2.0)
	# a last helper round while still in control (before stable it may already be over)
	check("A5.remaining_removed_then_stable", s.enemies.boars.is_empty() and st.zone_state[1] >= WorldState.ZONE_STABLE and s.enemies.total_spawned == spawned_at_clear, "hunted=%d spawned=%d (at clearing %d)" % [hunted, s.enemies.total_spawned, spawned_at_clear])
	var t_stable: float = float((s.zone_times[1] as Dictionary).get(WorldState.ZONE_STABLE, -1.0))
	# helper chores that can still be done with the player in control (stable is the last moment of input)
	var late: int = 0
	while late < 6 and helper_chore():
		late += 1
	var h: RefCounted = s.helpers
	var kinds_placed: Array = []
	for p: Dictionary in placed_log:
		kinds_placed.append(p["kind"])
	check("A6.helper_plants_placed_and_moved", placed_log.size() >= 1 and relocations >= 1, "placed=%s relocations=%d alive=%d lost=%d helper seeds dropped=%d collected=%d nest rewards=%d events=%s" % [kinds_placed, relocations, h.total_count(), h.lost_total, h.dropped_total, h.collected_total, h.nest_rewards_total, helper_events])
	report["helpers"] = {"placed": placed_log, "relocations": relocations, "alive_at_stable": h.total_count(), "lost_total": h.lost_total, "dropped": h.dropped_total, "collected": h.collected_total, "nest_rewards": h.nest_rewards_total, "kills": h.kills_total, "seeded": h.seeded_total, "pulses": h.pulses_total, "events": helper_events, "unplaced_queue": queue}
	t_stable = float((s.zone_times[1] as Dictionary).get(WorldState.ZONE_STABLE, -1.0))
	report["resources_until_stable"] = {"min_seeds": bot.min_seeds, "min_water": bot.min_water, "min_hp": bot.min_hp, "downs": bot.down_times.size(), "seed_shots": bot.seed_shots, "water_shots": bot.water_shots, "hits_taken": s.play.health.hit_count, "gain_by_class": bot.gain_by_class, "walked_m": bot.walked_px * Config.M_PER_LOGIC_PX}

	# ---- NO INPUT from here
	bot.detach()
	var bound: float = s.far.completion_bound_seconds()
	var limit_time: float = t_stable + bound
	var pos_stable: Vector2 = s.position
	var spawned_stable: int = s.enemies.total_spawned
	var launched_stable: int = s.projectiles.launched
	var hits_stable: int = s.play.health.hit_count
	report["stable"] = {"t_stable_s": t_stable, "bound_s": bound, "limit_s": limit_time, "greened": st.greened_count, "targets": st.target_count, "pct": s.greening_percent(), "hour": s.day_hour(), "weather": s.weather_text()}
	print("INFO stable at %.1f s bound %.1f limit %.1f greened %d/%d" % [t_stable, bound, limit_time, st.greened_count, st.target_count])
	var invaded: int = 0
	var samples: Array = []
	var next_sample: float = s.clock.elapsed
	while s.clock.elapsed <= limit_time + 0.001 and st.greened_count != st.target_count:
		s.advance_game(0.25)
		audio.update(0.25)
		bot.track()
		if not s.enemies.boars.is_empty() or s.enemies.total_spawned != spawned_stable:
			invaded += 1
		if s.clock.elapsed >= next_sample:
			next_sample += 30.0
			samples.append(bot.snapshot_row())
	var t_100: float = s.clock.elapsed
	var since: float = t_100 - t_stable
	report["completion"] = {"t_100_s": t_100, "since_stable_s": since, "bound_s": bound, "ratio": since / bound, "pct": s.greening_percent(), "samples_every_30s": samples}
	var island: Array = s.combat_setup["layout"]["island"]
	var island_ok: bool = true
	for y: int in range(int(island[1]), int(island[1]) + int(island[3])):
		for x: int in range(int(island[0]), int(island[0]) + int(island[2])):
			island_ok = island_ok and st.stage[st.index_of(x, y)] >= WorldState.GREENED_MIN_STAGE
	check("A7.no_reinvasion_after_stable", invaded == 0 and s.enemies.boars.is_empty() and s.enemies.total_spawned == spawned_stable, "invaded steps=%d" % invaded)
	var exact: bool = st.greened_count == st.target_count and st.target_count > 0 and st.greening_percent_floor() == 100 and st.recount_greened() == st.target_count
	check("A8.exact_100_percent_within_bound_with_island", exact and island_ok and t_100 <= limit_time + 0.001 and st.counters_consistent(), "greened %d/%d at %.1f s = %.1f s after stable; bound %.1f s (%.0f%% used); island ok=%s" % [st.greened_count, st.target_count, t_100, since, bound, 100.0 * since / bound, island_ok])
	check("A9.no_input_after_stable", s.position == pos_stable and s.projectiles.launched == launched_stable and s.play.health.hit_count == hits_stable, "position kept, launched %d->%d, hits %d->%d" % [launched_stable, s.projectiles.launched, hits_stable, s.play.health.hit_count])
	check("A10.zone_complete_and_notice", st.zone_state[1] == WorldState.ZONE_COMPLETE and st.cleared and s.cleared_notices == 1 and s.zone_log.has("すべての地域を緑化した"), "zone_state=%s notices=%d log=%s" % [st.zone_state, s.cleared_notices, s.zone_log])

	# ---- sounds requested during the run
	var counts: Dictionary = {}
	for snd: StringName in audio.requested:
		counts[String(snd)] = int(counts.get(String(snd), 0)) + 1
	report["audio"] = {"requested_counts": counts, "started_count": audio.started_count, "dropped_calm": audio.dropped_calm, "dropped_muted": audio.dropped_muted, "birds": audio.bird_count, "log_limit_note": "requested keeps only the last 256 entries"}
	var all_counts: Dictionary = counts.duplicate()
	check("A11.sound_requests_recorded", audio.started_count > 0 and audio.bird_count > 0, "requested(last %d)=%s started=%d birds=%d dropped_calm=%d" % [audio.requested.size(), counts, audio.started_count, audio.bird_count, audio.dropped_calm])

	# ---- weather / day seen (natural progression)
	report["weather_seconds"] = bot.weather_seen
	report["phase_seconds"] = bot.phase_seen
	print("INFO weather seen ", bot.weather_seen, " phases ", bot.phase_seen)

	# ---- real scene: completion display and the viewpoint notice fix
	var main: Node = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await process_frame
	await process_frame
	main.replace_session(s)
	main.tick(0.0, Vector2.ZERO)
	var badge: String = main.ui.badge.text
	check("A12.completion_display", badge.contains("★緑化完了") and badge.contains("100") and main.hud.text.contains("緑化 100%"), "badge=[%s]" % badge.replace("\n", " / "))
	bot.go(viewpoint.cell, 120.0, 2.0)
	main.tick(0.0, Vector2.ZERO)
	var hint: String = main.notice.text
	main.interact()
	var viewing: bool = main.is_viewing()
	var notice_in_view: String = main.notice.text
	main.tick(0.0, Vector2.ZERO)
	var notice_after_tick: String = main.notice.text
	main.leave_viewpoint()
	check("A13.lookout_notice_hidden_while_viewing", hint.contains("見晴らし台") and viewing and notice_in_view == "" and notice_after_tick == "", "hint=[%s] viewing=%s notice in view=[%s] after tick=[%s]" % [hint, viewing, notice_in_view, notice_after_tick])
	main.queue_free()
	await process_frame
	report["end"] = bot.snapshot_row()
	report["rows_every_10s"] = bot.rows
	report["bot_events"] = Array(bot.events)
	report["zone_log"] = Array(s.zone_log)
	report["lookout"] = lookout
	report["checks"] = checks
	report["passes"] = passes
	report["failures"] = failures
	audio.detach()
	audio.free()
	s.close()
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT + "A_full_flow.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", false, true))
	file.close()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
