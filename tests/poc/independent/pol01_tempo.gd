extends SceneTree
## POL-01 independent check 3: with data/poc/tempo.json applied, destroy the nests, wait for stable, then NO input until an exact 100 %
## (own recount from the stage array and the terrain files) within far.completion_bound_seconds(). Also runs the shipped tempo for reference.
##   godot --headless --path <repo> --script res://tests/poc/independent/pol01_tempo.gd
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
var passes: int = 0
var fails: int = 0

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("PASS " if ok else "FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func target_ids() -> Array[int]:
	var ids: Array[int] = []
	for path_: String in ["res://data/terrain/", "res://data/poc/terrain/"]:
		for f: String in DirAccess.get_files_at(path_):
			if not f.ends_with(".tres"):
				continue
			var id_val: int = -1
			var is_t: bool = false
			for ln: String in FileAccess.get_file_as_string(path_ + f).split("\n"):
				if ln.begins_with("id = "):
					id_val = int(ln.substr(5))
				if ln.begins_with("is_target = true"):
					is_t = true
			if is_t and id_val >= 0:
				ids.append(id_val)
	return ids

func run_mode(label: String, tempo_path: String) -> Dictionary:
	Session.set("tempo_path", tempo_path)
	var size: Vector2i = Session.town_size()
	var s: RefCounted = Session.new(size.x, size.y)
	s.paving = Session.paving_from(s.env_tuning)
	check(label + "_load", s.load_combat(Session.TOWN_SETUP))
	var bound: float = s.far.completion_bound_seconds()
	var ids: Array[int] = target_ids()
	var oracle: Dictionary = {}
	for i: int in s.state.terrain.size():
		if ids.has(int(s.state.terrain[i])):
			oracle[i] = true
	# own destruction: advance 30 s of game time first (nests start spawning), then reduce nests/boars through the enemy rules
	s.advance_game(30.0)
	for n: Nest in s.enemies.nests:
		s.enemies.damage_nest(n, 99)
	var guard: int = 0
	while not s.enemies.boars.is_empty() and guard < 600:
		s.enemies.damage_boar(s.enemies.boars[0], 99)
		s.advance_game(0.25)
		guard += 1
	var t_cap: float = s.clock.elapsed + 3000.0
	while int(s.state.zone_state[1]) < WorldState.ZONE_STABLE and s.clock.elapsed < t_cap:
		s.advance_game(0.5)
	var t_stable: float = s.clock.elapsed
	var bound2: float = s.far.completion_bound_seconds()
	var pct_early: int = 0
	var reached: float = -1.0
	var shown100_early: bool = false
	var start_pos: Vector2 = s.position
	while s.clock.elapsed <= t_stable + bound2 + 2.0:
		s.advance_game(1.0)
		if s.state.greened_count == s.state.target_count:
			reached = s.clock.elapsed - t_stable
			break
		if s.greening_percent() >= 100:
			shown100_early = true
	var green: int = 0
	var missing: int = 0
	for i: int in s.state.tile_count():
		var g: bool = int(s.state.stage[i]) >= 2
		if oracle.has(i):
			if g:
				green += 1
			else:
				missing += 1
	print("INFO %s: bound_at_start=%.1f bound_at_stable=%.1f stable_at=%.1f reached_after=%.1f targets(oracle)=%d state=%d/%d recount_green=%d missing=%d pct=%d" % [label, bound, bound2, t_stable, reached, oracle.size(), s.state.greened_count, s.state.target_count, green, missing, s.greening_percent()])
	check(label + "_stable_reached", int(s.state.zone_state[1]) >= WorldState.ZONE_STABLE)
	check(label + "_exact_100_within_bound", reached >= 0.0 and reached <= bound2 and green == oracle.size() and missing == 0 and green == s.state.target_count and s.position == start_pos, "after stable %.1f s <= bound %.1f s" % [reached, bound2])
	check(label + "_no_early_100", not shown100_early)
	return {"bound": bound2, "reached": reached, "stable": t_stable}

func _run() -> void:
	var a: Dictionary = run_mode("tempo", "res://data/poc/tempo.json")
	var b: Dictionary = run_mode("shipped", "")
	print("INFO summary: tempo bound %.1f real %.1f ; shipped bound %.1f real %.1f" % [a["bound"], a["reached"], b["bound"], b["reached"]])
	print("RESULT pass=%d fail=%d" % [passes, fails])
	quit(1 if fails > 0 else 0)
