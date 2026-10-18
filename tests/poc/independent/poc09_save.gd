extends SceneTree
## POC-09 independent verification, conditions 2 and 3 (save/restore with FarSeed running and while downed; no real-time progress).
## The stable state is reached with engine-level setup (nests/boars removed through EnemyField) because the full play-through is condition 1.
## Own namespace user://poc_saves_indep09/ only; removed at the end.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const DIR: String = "user://poc_saves_indep09/"
const OUT: String = "res://evidence/poc/09/independent/"
var passes: int = 0
var fails: int = 0
var lines: PackedStringArray = PackedStringArray()
var keep: Array[RefCounted] = []

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", name, detail]
	lines.append(line)
	print(line)

func info(text: String) -> void:
	lines.append("INFO " + text)
	print("INFO ", text)

func _init() -> void:
	_run.call_deferred()

func mk() -> RefCounted:
	var size: Vector2i = Session.town_size()
	var m: RefCounted = Session.new(size.x, size.y)
	m.paving = Session.paving_from(m.env_tuning)
	m.load_combat(Session.TOWN_SETUP)
	keep.append(m)
	return m

func run_for(m: RefCounted, sec: float) -> void:
	var left: float = sec
	while left > 0.0:
		m.advance_game(minf(left, 0.25))
		left -= 0.25

func sha(b: PackedByteArray) -> String:
	var c: HashingContext = HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(b)
	return c.finish().hex_encode().substr(0, 12)

## My own observation vector: what a player/judge can see or that drives the future.
func obs(m: RefCounted, with_pos: bool = true) -> String:
	var st: WorldState = m.state
	var o: Dictionary = {}
	o["tiles"] = [sha(st.terrain), sha(st.plant_id), sha(st.stage), sha(st.growth.to_byte_array()), sha(st.moisture), sha(st.fertility), sha(st.sprout_slot)]
	o["zones"] = [Array(st.zone_state), st.cleared, st.greened_count, st.target_count, Array(st.zone_greened_count)]
	o["res"] = [m.play.seeds, snappedf(m.play.water, 0.0001), m.play.hp, m.play.pickups.count()]
	if with_pos:
		o["pos"] = [snappedf(m.position.x, 0.001), snappedf(m.position.y, 0.001)]
	o["boars"] = m.enemies.boars.size()
	o["nests"] = m.enemies.alive_nest_count(-1)
	o["clk"] = [snappedf(m.clock.elapsed, 0.0001), m.clock.growth_ticks, m.clock.spread_ticks]
	o["far"] = [m.far.ticks, m.far.job_zone, m.far.round_active, m.far.sweep_cursor, m.far.laps, m.far.total_sweep_planted, m.far.total_island_planted, m.far.finished_comp_count()]
	return JSON.stringify(o, "", true)

func clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)

func stable_session() -> RefCounted:
	var m: RefCounted = mk()
	run_for(m, 20.0)
	for n: Nest in m.enemies.nests.duplicate():
		m.enemies.destroy_nest(n)
	for b: Boar in m.enemies.boars.duplicate():
		m.enemies.remove_boar(b)
	return m

func _run() -> void:
	clean()
	# ---------- 2a: far seeding running
	var a: RefCounted = stable_session()
	check("a.zone1_stable", int(a.state.zone_state[1]) == WorldState.ZONE_STABLE, str(Array(a.state.zone_state)))
	var found: bool = false
	var guard: int = 0
	while guard < 4000:
		run_for(a, 2.0)
		guard += 1
		if a.far.job_zone >= 0 or a.far.round_active:
			found = true
			break
	check("a.far_in_progress_at_save", found, "t=%.1f job_zone=%d round_active=%s labelling_busy=%s" % [a.clock.elapsed, a.far.job_zone, str(a.far.round_active), str(a.far.labelling_busy())])
	run_for(a, 6.0)
	info("a before save: far job_zone=%d round_active=%s cursor=%d greened=%d/%d" % [a.far.job_zone, str(a.far.round_active), a.far.sweep_cursor, a.state.greened_count, a.state.target_count])
	var far_active_at_save: bool = a.far.job_zone >= 0 or a.far.round_active
	var save_res: Dictionary = PocSave.save(a, DIR, {"resolution_index": 0})
	check("a.save", bool(save_res["ok"]), str(save_res.get("reason", "")))
	var ld: Dictionary = PocSave.load_slot(DIR, false, mk)
	check("a.load", bool(ld["ok"]), str(ld.get("reason", "")))
	var b: RefCounted = ld["session"]
	check("a.far_still_in_progress_after_save", far_active_at_save)
	check("a.obs_equal_right_after_load", obs(a) == obs(b), "" if obs(a) == obs(b) else "A=%s\nB=%s" % [obs(a).left(400), obs(b).left(400)])
	var before_green: int = a.state.greened_count
	run_for(a, 120.0)
	run_for(b, 120.0)
	var oa: String = obs(a)
	var ob: String = obs(b)
	check("a.obs_equal_after_120s", oa == ob, "greened %d -> %d / %d" % [before_green, a.state.greened_count, b.state.greened_count])
	check("a.no_rollback_and_progressed", b.state.greened_count >= before_green and int(b.state.zone_state[1]) >= WorldState.ZONE_STABLE and b.enemies.boars.is_empty())
	# let both finish: same completion time
	var done_a: float = -1.0
	var done_b: float = -1.0
	for i: int in 2000:
		run_for(a, 5.0)
		run_for(b, 5.0)
		if done_a < 0.0 and a.state.greened_count == a.state.target_count:
			done_a = a.clock.elapsed
		if done_b < 0.0 and b.state.greened_count == b.state.target_count:
			done_b = b.clock.elapsed
		if done_a >= 0.0 and done_b >= 0.0:
			break
	check("a.same_completion_time_and_state", done_a > 0.0 and done_a == done_b and obs(a) == obs(b), "A=%.1f B=%.1f zones %s/%s" % [done_a, done_b, str(Array(a.state.zone_state)), str(Array(b.state.zone_state))])
	# ---------- 2b: downed while stable and far running
	clean()
	var c: RefCounted = stable_session()
	run_for(c, 1.0)
	var start_pos: Vector2 = c.play.health.respawn_position
	# put the player away from the start zone by walking (no teleport): walk west for a while
	for i: int in 100:
		c.walk(Vector2(-1, 0), 0.2)
		c.advance_game(0.2)
	var away_cell: Vector2i = Vector2i(floori(c.position.x / 4.0), floori(c.position.y / 4.0))
	info("b walked to cell %s zone %d" % [str(away_cell), c.player_zone()])
	c.play.damage_player(c.play.hp_max)
	var guard2: int = 0
	while not c.play.health.downed and guard2 < 50:
		c.advance_game(0.05)
		guard2 += 1
	check("b.player_is_downed", c.play.health.downed, "hp=%d" % c.play.hp)
	run_for(c, 0.3)
	var green_c: int = c.state.greened_count
	var zones_c: Array = Array(c.state.zone_state)
	var far_c: bool = c.far.job_zone >= 0 or c.far.round_active
	var sv: Dictionary = PocSave.save(c, DIR, {"resolution_index": 0})
	check("b.far_active_while_downed", far_c, "job_zone=%d round_active=%s" % [c.far.job_zone, str(c.far.round_active)])
	check("b.save_while_downed", bool(sv["ok"]) and c.play.health.downed, str(sv.get("reason", "")))
	var ld2: Dictionary = PocSave.load_slot(DIR, false, mk)
	check("b.load", bool(ld2["ok"]), str(ld2.get("reason", "")))
	var d: RefCounted = ld2["session"]
	var back_zone: int = d.player_zone()
	check("b.restored_not_downed_in_safe_zone", not d.play.health.downed and back_zone == 0 and d.play.hp > 0, "downed=%s zone=%d hp=%d pos_cell=(%d,%d) (saved at cell %s)" % [str(d.play.health.downed), back_zone, d.play.hp, floori(d.position.x / 4.0), floori(d.position.y / 4.0), str(away_cell)])
	check("b.world_not_rolled_back", d.state.greened_count == green_c and Array(d.state.zone_state) == zones_c and d.state.cleared == c.state.cleared, "greened %d vs %d zones %s" % [d.state.greened_count, green_c, str(Array(d.state.zone_state))])
	check("b.tiles_equal_and_far_same", sha(d.state.stage) == sha(c.state.stage) and d.far.ticks == c.far.ticks and d.far.job_zone == c.far.job_zone and d.far.round_active == c.far.round_active, "far_active=%s ticks %d/%d" % [str(far_c), d.far.ticks, c.far.ticks])
	# the live session revives itself; once both are up (live: after remaining lie time), the world must match again after equal time
	run_for(c, 3.0)
	check("b.live_revived_in_safe_zone", not c.play.health.downed and c.player_zone() == 0)
	# bring both to the same clock, then advance equally
	var diff: float = c.clock.elapsed - d.clock.elapsed
	run_for(d, maxf(diff, 0.0))
	check("b.clocks_aligned", absf(c.clock.elapsed - d.clock.elapsed) < 0.01, "diff=%.4f" % (c.clock.elapsed - d.clock.elapsed))
	run_for(c, 60.0)
	run_for(d, 60.0)
	check("b.world_equal_after_equal_time", obs(c, false) == obs(d, false), "greened %d / %d" % [c.state.greened_count, d.state.greened_count])
	# ---------- 2c: downed in an unconquered region with enemies
	clean()
	var e: RefCounted = mk()
	run_for(e, 150.0)
	e.play.damage_player(e.play.hp_max)
	var g3: int = 0
	while not e.play.health.downed and g3 < 50:
		e.advance_game(0.05)
		g3 += 1
	var boars_e: int = e.enemies.boars.size()
	var nests_e: int = e.enemies.alive_nest_count(-1)
	var zones_e: Array = Array(e.state.zone_state)
	var greened_e: int = e.state.greened_count
	var rs: Dictionary = PocSave.save(e, DIR, {"resolution_index": 0})
	var ld3: Dictionary = PocSave.load_slot(DIR, false, mk)
	check("c.save_load_downed_combat", bool(rs["ok"]) and bool(ld3["ok"]), str(ld3.get("reason", "")))
	if bool(ld3["ok"]):
		var f: RefCounted = ld3["session"]
		check("c.restored_ok", not f.play.health.downed and f.player_zone() == 0 and f.enemies.boars.size() == boars_e and f.enemies.alive_nest_count(-1) == nests_e and Array(f.state.zone_state) == zones_e and f.state.greened_count == greened_e, "boars %d/%d nests %d/%d" % [f.enemies.boars.size(), boars_e, f.enemies.alive_nest_count(-1), nests_e])
	# ---------- 3: no progress outside play
	clean()
	var h: RefCounted = stable_session()
	run_for(h, 90.0)
	PocSave.save(h, DIR)
	var elapsed: float = h.clock.elapsed
	var sig_t: float = h.enemies.time
	var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "slot.json"))
	j["saved_at"] = "1999-01-01T00:00:00"
	var wf: FileAccess = FileAccess.open(DIR + "slot.json", FileAccess.WRITE)
	wf.store_string(JSON.stringify(j, "", false, true))
	wf.close()
	OS.delay_msec(2000)
	var ld4: Dictionary = PocSave.load_slot(DIR, false, mk)
	var k: RefCounted = ld4["session"]
	check("t.clock_not_advanced_by_real_wait_or_saved_at", k.clock.elapsed == elapsed and k.enemies.time == sig_t, "%.4f vs %.4f" % [k.clock.elapsed, elapsed])
	var ok_before: String = obs(k)
	# Edit the saved timestamp into the future and wait again
	j["saved_at"] = "2099-01-01T00:00:00"
	var wf2: FileAccess = FileAccess.open(DIR + "slot.json", FileAccess.WRITE)
	wf2.store_string(JSON.stringify(j, "", false, true))
	wf2.close()
	var ld5: Dictionary = PocSave.load_slot(DIR, false, mk)
	check("t.future_saved_at_no_effect", bool(ld5["ok"]) and obs(ld5["session"]) == ok_before)
	k.paused = true
	var p0: String = obs(k)
	OS.delay_msec(1200)
	for i: int in 20:
		k.advance(0.25)
	check("t.paused_real_time_no_progress", obs(k) == p0)
	k.paused = false
	k.multiplier = 1.0
	var e0: float = k.clock.elapsed
	k.advance(5.0)
	var dt1: float = k.clock.elapsed - e0
	check("t.unpause_not_lump_sum", dt1 > 0.0 and dt1 <= Config.MAX_STEP_S + 0.001, "advanced %.3f game s after a 5 s real gap (cap %.2f)" % [dt1, Config.MAX_STEP_S])
	k.multiplier = 16.0
	var e1: float = k.clock.elapsed
	k.advance(5.0)
	var dt16: float = k.clock.elapsed - e1
	check("t.fast_forward_still_capped_per_frame", dt16 <= Config.MAX_STEP_S * 16.0 + 0.001, "advanced %.3f" % dt16)
	# main node path: pause through the node
	# ---------- cleanup own namespace
	clean()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	check("cleanup_own_namespace", not DirAccess.dir_exists_absolute(DIR))
	for m: RefCounted in keep:
		m.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var wr: FileAccess = FileAccess.open(OUT + "save.log", FileAccess.WRITE)
	if wr != null:
		wr.store_string("\n".join(lines) + "\nRESULT passes=%d failures=%d\n" % [passes, fails])
		wr.close()
	print("RESULT passes=%d failures=%d" % [passes, fails])
	quit(1 if fails > 0 else 0)
