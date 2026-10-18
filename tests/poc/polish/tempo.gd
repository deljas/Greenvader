extends SceneTree
## POL-01 tempo check (headless OK): godot --headless --path <repo> --script res://tests/poc/polish/tempo.gd [-- --baseline]
## Town session, nests/boars removed through the game rules, advance to stable, then NO input until 100 %. The run is compared with
## far.completion_bound_seconds() computed before anything happens. --baseline ignores data/poc/tempo.json (shipped SimTuning).
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
var failures: int = 0
var passes: int = 0

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
		print("PASS ", name, " ", detail)
	else:
		failures += 1
		print("FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var baseline: bool = OS.get_cmdline_user_args().has("--baseline")
	if baseline:
		Session.set("tempo_path", "")
	var size: Vector2i = Session.town_size()
	var s: RefCounted = Session.new(size.x, size.y)
	check("load_town", s.load_combat(Session.TOWN_SETUP))
	s.enemy_tuning.contact_damage = 0
	var bound: float = s.far.completion_bound_seconds()
	print("INFO mode=%s far_K=%d delay=%.0f period=%.1f bound=%.1f swept=%d" % ["baseline" if baseline else "tempo", s.sim_tuning.far_sweep_seeds_per_step, s.sim_tuning.far_sweep_start_delay_seconds, s.sim_tuning.far_sweep_period_seconds, bound, s.far.swept_targets()])
	for n: Nest in s.enemies.nests:
		s.enemies.damage_nest(n, 99)
	var guard: int = 0
	while not s.enemies.boars.is_empty() and guard < 400:
		s.enemies.damage_boar(s.enemies.boars[0], 99)
		guard += 1
		s.advance_game(0.25)
	var steps: int = 0
	while s.state.zone_state[1] < WorldState.ZONE_STABLE and steps < 4000:
		s.advance_game(0.25)
		steps += 1
	check("stable", s.state.zone_state[1] >= WorldState.ZONE_STABLE, "t=%.1f" % s.clock.elapsed)
	var t_stable: float = float((s.zone_times[1] as Dictionary).get(WorldState.ZONE_STABLE, s.clock.elapsed))
	s.position = Coords.cell_center_logic(s.placement.player_start_cell)
	var limit: float = t_stable + bound
	var done: bool = false
	var t_done: float = -1.0
	var mid: Array[String] = []
	while s.clock.elapsed <= limit + 5.0:
		s.advance_game(0.25)
		var after: float = s.clock.elapsed - t_stable
		if int(after * 4.0) % 400 == 0:
			mid.append("%d:%d" % [int(after), s.state.greened_count])
		if s.state.greened_count == s.state.target_count:
			done = true
			t_done = s.clock.elapsed - t_stable
			break
	print("INFO progress ", ",".join(mid))
	check("exact_100_within_bound", done and t_done <= bound, "after stable %.1f s of bound %.1f s (%.1f%%), greened %d/%d" % [t_done, bound, t_done / bound * 100.0, s.state.greened_count, s.state.target_count])
	print("INFO stable_at=%.1f done_after=%.1f bound=%.1f" % [t_stable, t_done, bound])
	s.close()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
