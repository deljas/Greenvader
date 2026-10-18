extends SceneTree
## POC-09 independent verification, condition 1: one full town_01 run with my own bot (walk / fire / advance_game only; no debug refill,
## no direct writes into play / world / enemy state), then NO input from stable until complete, judged against a bound recorded at stable.
##   godot --headless --path <repo> --script res://tests/poc/independent/poc09_play.gd
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const OUT: String = "res://evidence/poc/09/independent/"
const DT: float = 0.2
const FIRE_COOLDOWN: float = 0.4

var passes: int = 0
var fails: int = 0
var lines: PackedStringArray = PackedStringArray()
var s: RefCounted
var path: Array[Vector2i] = []
var path_goal: Vector2i = Vector2i(-1, -1)
var path_age: float = 99.0
var cooldown: float = 0.0
var last_pos: Dictionary = {}
var shots_fired: int = 0
var seed_gain_events: int = 0
var seed_gain_unexplained: int = 0
var boar_in_safe: int = 0
var targets_oracle: Dictionary = {}
var stuck_ref: Vector2 = Vector2.ZERO
var stuck_t: float = 0.0
var stuck_count: int = 0

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

func target_ids() -> Array[int]:
	# Own reading of the terrain files: which terrain ids count as greening targets.
	var ids: Array[int] = []
	for path_: String in ["res://data/terrain/", "res://data/poc/terrain/"]:
		for f: String in DirAccess.get_files_at(path_):
			if not f.ends_with(".tres"):
				continue
			var t: String = FileAccess.get_file_as_string(path_ + f)
			var id_val: int = -1
			var is_t: bool = false
			for ln: String in t.split("\n"):
				if ln.begins_with("id = "):
					id_val = int(ln.substr(5))
				if ln.begins_with("is_target = true"):
					is_t = true
			if is_t and id_val >= 0:
				ids.append(id_val)
	return ids

func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))

# ------------------------------------------------------------ navigation
func bfs(from: Vector2i, goal_test: Callable) -> Array[Vector2i]:
	var st: WorldState = s.state
	var w: int = st.width
	var prev: Dictionary = {from: from}
	var queue: Array[Vector2i] = [from]
	var head: int = 0
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if goal_test.call(c):
			var out: Array[Vector2i] = []
			var k: Vector2i = c
			while k != from:
				out.push_front(k)
				k = prev[k]
			return out
		for d: Vector2i in dirs:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= st.height or prev.has(n):
				continue
			if not st.is_walkable(n.x, n.y):
				continue
			if d.x != 0 and d.y != 0 and (not st.is_walkable(c.x + d.x, c.y) or not st.is_walkable(c.x, c.y + d.y)):
				continue
			# keep one cell away from blocked cells where possible is not needed: feet half size 2.8px < half cell
			prev[n] = c
			queue.append(n)
	return []

func walk_to_cell_set(goal_test: Callable, key: Vector2i) -> bool:
	## Follows a BFS path to the nearest cell satisfying goal_test. Returns true when already there.
	var here: Vector2i = cell_of(s.position)
	if goal_test.call(here):
		return true
	if path.is_empty() or path_goal != key or path_age > 1.0:
		path = bfs(here, goal_test)
		path_goal = key
		path_age = 0.0
		if path.is_empty():
			return false
	path_age += DT
	while not path.is_empty() and s.position.distance_to(Coords.cell_center_logic(path[0])) < 2.2:
		path.pop_front()
	if path.is_empty():
		return false
	var dir: Vector2 = (Coords.cell_center_logic(path[0]) - s.position).normalized()
	var screen: Vector2 = Coords.ground_dir_to_screen(dir)
	s.walk(screen, DT)
	return false

# ------------------------------------------------------------ stepping with bookkeeping
func step(dt: float = DT) -> void:
	stuck_t += dt
	if stuck_t >= 4.0:
		if s.position.distance_to(stuck_ref) < 2.0 and not s.play.health.downed:
			stuck_count += 1
			path.clear()
			path_age = 99.0
			var ang: float = float(stuck_count) * 2.399
			for i: int in 6:
				s.walk(Vector2(cos(ang), sin(ang)), DT)
		stuck_ref = s.position
		stuck_t = 0.0
	var seeds0: int = s.play.seeds
	var direct0: int = s.combat.seeds_direct
	var items: Array = s.play.pickups.items.duplicate()
	var pos0: Vector2 = s.position
	s.advance_game(dt)
	cooldown = maxf(0.0, cooldown - dt)
	if s.play.seeds > seeds0:
		seed_gain_events += 1
		var near: bool = s.combat.seeds_direct > direct0
		for it: Dictionary in items:
			if Vector2(float(it["x"]), float(it["y"])).distance_to(s.position) <= 12.0 + 6.0 or Vector2(float(it["x"]), float(it["y"])).distance_to(pos0) <= 12.0 + 6.0:
				near = true
		if not near:
			seed_gain_unexplained += 1
	for b: Boar in s.enemies.boars:
		if s.state.zone_at(s.state.index_of(clampi(floori(b.pos.x / 4.0), 0, s.state.width - 1), clampi(floori(b.pos.y / 4.0), 0, s.state.height - 1))) == 0:
			boar_in_safe += 1

func try_fire_at(p: Vector2) -> bool:
	if cooldown > 0.0 or s.play.seeds <= 0 or s.play.health.downed:
		return false
	if s.position.distance_to(p) > 58.0 or s.shot_blocked(s.position, p):
		return false
	s.set_aim(p)
	var r: Dictionary = s.fire(false)
	if bool(r["ok"]):
		shots_fired += 1
		cooldown = FIRE_COOLDOWN
		return true
	return false

func boar_aim(b: Boar) -> Vector2:
	var p: Vector2 = s.enemies.boar_body_center(b)
	var vel: Vector2 = Vector2.ZERO
	if last_pos.has(b.id):
		vel = (p - (last_pos[b.id] as Vector2)) / DT
	last_pos[b.id] = p
	return p + vel * (s.position.distance_to(p) / 160.0)

func nearest_boar(limit: float) -> Boar:
	var best: Boar = null
	var bd: float = limit
	for b: Boar in s.enemies.boars:
		var d: float = s.position.distance_to(b.pos)
		if d < bd:
			bd = d
			best = b
	return best

func nest_alive() -> Array[Nest]:
	var out: Array[Nest] = []
	for n: Nest in s.enemies.nests:
		if n.alive:
			out.append(n)
	return out

func seed_pickup_near(limit: float) -> Vector2:
	var best: Vector2 = Vector2.INF
	var bd: float = limit
	for it: Dictionary in s.play.pickups.items:
		if String(it["kind"]) != "seed_fruit":
			continue
		var p: Vector2 = Vector2(float(it["x"]), float(it["y"]))
		var d: float = s.position.distance_to(p)
		if d < bd:
			bd = d
			best = p
	return best

func goto_pos(p: Vector2) -> void:
	var goal: Vector2i = cell_of(p)
	var ok: bool = walk_to_cell_set(func(c: Vector2i) -> bool: return c == goal, goal)
	if ok:
		var d: Vector2 = p - s.position
		if d.length() > 1.0:
			s.walk(Coords.ground_dir_to_screen(d.normalized()), minf(DT, d.length() / Config.walk_speed_px()))

func approach_nest(n: Nest) -> void:
	var c: Vector2 = n.center_px(4)
	var test: Callable = func(cell: Vector2i) -> bool:
		var p: Vector2 = Coords.cell_center_logic(cell)
		var d: float = p.distance_to(c)
		return d >= 22.0 and d <= 36.0 and not s.shot_blocked(p, c)
	var ok: bool = walk_to_cell_set(test, Vector2i(n.id, -7))
	if ok or s.position.distance_to(c) <= 40.0 and not s.shot_blocked(s.position, c):
		try_fire_at(c)

func idle_at_source() -> void:
	# stand between the two sources and pick up the fruits they drop
	var near: Vector2 = seed_pickup_near(200.0)
	if near != Vector2.INF:
		goto_pos(near)
	else:
		goto_pos(Coords.cell_center_logic(Vector2i(88, 86)))

func bot_step() -> void:
	if s.play.health.downed:
		step()
		return
	var threat: Boar = nearest_boar(48.0)
	if threat != null and s.play.seeds > 0:
		var aim: Vector2 = boar_aim(threat)
		if try_fire_at(aim) or (cooldown > 0.0 and not s.shot_blocked(s.position, aim)):
			step()
			return
	var alive: Array[Nest] = nest_alive()
	var need: int = 14
	if s.play.seeds < need and s.play.hp > 0:
		# restock at the start zone (also pick up what defeated enemies dropped on the way)
		var near: Vector2 = seed_pickup_near(40.0)
		if near != Vector2.INF:
			goto_pos(near)
		elif s.player_zone() != 0 or s.play.seeds < need:
			idle_at_source()
		step()
		return
	var near2: Vector2 = seed_pickup_near(30.0)
	if near2 != Vector2.INF and s.play.seeds < 38:
		goto_pos(near2)
		step()
		return
	if not alive.is_empty():
		# nearest living nest by path-free distance
		var best: Nest = alive[0]
		for n: Nest in alive:
			if s.position.distance_to(n.center_px(4)) < s.position.distance_to(best.center_px(4)):
				best = n
		approach_nest(best)
	else:
		var b: Boar = nearest_boar(99999.0)
		if b != null:
			goto_pos(b.pos)
	step()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var size: Vector2i = Session.town_size()
	s = Session.new(size.x, size.y)
	s.paving = Session.paving_from(s.env_tuning)
	check("load_town_01", s.load_combat(Session.TOWN_SETUP), "size %s" % str(size))
	check("debug_refill_off", not s.debug_refill_enabled)
	var ids: Array[int] = target_ids()
	var start_terrain: PackedByteArray = s.state.terrain.duplicate()
	for i: int in start_terrain.size():
		if ids.has(int(start_terrain[i])):
			targets_oracle[i] = true
	info("oracle target cells=%d state.target_count=%d target terrain ids=%s" % [targets_oracle.size(), s.state.target_count, str(ids)])
	check("oracle_target_count_matches", targets_oracle.size() == s.state.target_count)
	# own connectivity: components of oracle targets under 8-neighbourhood
	var comp: Dictionary = {}
	var comp_n: int = 0
	var w: int = s.state.width
	var comp_sizes: Array[int] = []
	for i: int in targets_oracle:
		if comp.has(i):
			continue
		var q: Array[int] = [i]
		comp[i] = comp_n
		var h: int = 0
		while h < q.size():
			var c: int = q[h]
			h += 1
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var nx: int = c % w + dx
					var ny: int = c / w + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= s.state.height:
						continue
					var ni: int = ny * w + nx
					if targets_oracle.has(ni) and not comp.has(ni):
						comp[ni] = comp_n
						q.append(ni)
		comp_sizes.append(q.size())
		comp_n += 1
	info("target components (8-neigh) sizes=%s" % str(comp_sizes))
	var island_cells: int = 0
	for y: int in range(53, 57):
		for x: int in range(52, 56):
			if targets_oracle.has(y * w + x):
				island_cells += 1
	info("island rect [52,53,4,4] target cells=%d" % island_cells)
	var t0: int = Time.get_ticks_msec()
	# ---- new game: a short hand-sowing + watering near the start before heading out
	var wl: Vector2 = Coords.cell_center_logic(Vector2i(80, 80))
	s.position = s.position # no teleporting: start where the game puts us
	var seeds_start: int = s.play.seeds
	var water_start: float = s.play.water
	info("start pos cell=%s seeds=%d water=%.0f hp=%d" % [str(cell_of(s.position)), seeds_start, water_start, s.play.hp])
	# water the start zone cell ahead (if the water gauge allows) and sow 3 seeds out of the start
	var sow_ok: int = 0
	for k: int in 3:
		s.set_aim(s.position + Vector2(-20 - k * 6, -14))
		if bool(s.fire(false)["ok"]):
			sow_ok += 1
		step(0.5)
	s.set_aim(s.position + Vector2(-22, -14))
	var water_ok: bool = bool(s.fire(true)["ok"])
	step(2.0)
	check("hand_sow_and_water_by_fire_api", sow_ok == 3 and water_ok, "sowed=%d water=%s" % [sow_ok, str(water_ok)])
	# ---- play until the combat zone is stable
	var zone: int = s.combat_zone()
	check("combat_zone_is_1", zone == 1)
	var limit: float = 3000.0
	var t_stable: float = -1.0
	var guard: int = 0
	var last_report: float = 0.0
	while s.clock.elapsed < limit:
		bot_step()
		if int(s.state.zone_state[zone]) >= WorldState.ZONE_STABLE:
			t_stable = s.clock.elapsed
			break
		if s.clock.elapsed - last_report > 300.0:
			last_report = s.clock.elapsed
			info("t=%.0f stuck=%d pos=%s seeds=%d hp=%d nests=%d boars=%d downs=%d" % [s.clock.elapsed, stuck_count, str(cell_of(s.position)), s.play.seeds, s.play.hp, nest_alive().size(), s.enemies.boars.size(), s.play.health.down_count])
	check("zone_reached_stable_by_play", t_stable >= 0.0, "t_stable=%.1f game s (limit %.0f), shots=%d, downs=%d, wallclock=%.1fs" % [t_stable, limit, shots_fired, s.play.health.down_count, (Time.get_ticks_msec() - t0) / 1000.0])
	if t_stable < 0.0:
		_finish()
		return
	check("all_nests_destroyed", nest_alive().is_empty() and s.enemies.boar_count_in_zone(zone) == 0)
	var bound: float = s.far.completion_bound_seconds()
	var greened_at_stable: int = s.state.greened_count
	info("STABLE at %.1f s; completion_bound_seconds()=%.1f; greened=%d/%d (%d%%) zone_states=%s" % [t_stable, bound, greened_at_stable, s.state.target_count, s.greening_percent(), str(Array(s.state.zone_state))])
	info("far at stable: job_zone=%d round_active=%s comp_count=%d" % [s.far.job_zone, str(s.far.round_active), s.far.comp_count()])
	check("bound_positive", bound > 0.0)
	# ---- no input from here
	var max_pct_before_full: int = 0
	var shown_100_early: bool = false
	var reached_at: float = -1.0
	var reinvasion: int = 0
	var seeds_after: int = s.play.seeds
	var seeds_up_after_stable: int = 0
	var states_regressed: bool = false
	var prev_states: Array = Array(s.state.zone_state)
	var deadline: float = t_stable + bound
	while s.clock.elapsed <= deadline + 1.0:
		s.advance_game(2.0)
		if s.state.greened_count == s.state.target_count:
			reached_at = s.clock.elapsed
			break
		max_pct_before_full = maxi(max_pct_before_full, s.greening_percent())
		if s.greening_percent() >= 100:
			shown_100_early = true
		if not nest_alive().is_empty() or s.enemies.boar_count_in_zone(zone) > 0 or not s.enemies.boars.is_empty():
			reinvasion += 1
		for z: int in prev_states.size():
			if int(s.state.zone_state[z]) < int(prev_states[z]):
				states_regressed = true
		prev_states = Array(s.state.zone_state)
	check("reached_100_within_bound", reached_at >= 0.0, "reached after %.1f s (bound %.1f s, %.1f%% of bound); max shown pct before full=%d" % [reached_at - t_stable, bound, 100.0 * (reached_at - t_stable) / bound, max_pct_before_full])
	check("percent_shows_99_not_100_before_full", not shown_100_early and max_pct_before_full <= 99)
	check("no_reinvasion_after_stable", reinvasion == 0 and s.enemies.boars.is_empty() and nest_alive().is_empty())
	check("no_zone_state_regress", not states_regressed)
	# independent recount from the stage array
	var greened_recount: int = 0
	var not_green: int = 0
	var off_target_green: int = 0
	var not_green_comp: Dictionary = {}
	for i: int in s.state.tile_count():
		var g: bool = int(s.state.stage[i]) >= 2 # STAGE_SPROUT1 counts as greened
		if targets_oracle.has(i):
			if g:
				greened_recount += 1
			else:
				not_green += 1
				not_green_comp[comp[i]] = true
		elif g:
			off_target_green += 1
	check("greened_equals_target_independent_recount", reached_at >= 0.0 and greened_recount == targets_oracle.size() and not_green == 0 and s.state.greened_count == s.state.target_count, "recount %d / oracle %d / state %d/%d / off-target greened %d" % [greened_recount, targets_oracle.size(), s.state.greened_count, s.state.target_count, off_target_green])
	check("terrain_unchanged_during_run", s.state.terrain == start_terrain)
	var island_ok: bool = true
	for y: int in range(53, 57):
		for x: int in range(52, 56):
			if targets_oracle.has(y * w + x) and int(s.state.stage[y * w + x]) < 2:
				island_ok = false
	check("island_greened", island_ok and island_cells > 0, "island target cells %d" % island_cells)
	check("greening_percent_is_100_only_when_full", s.greening_percent() == 100)
	# complete / cleared (may need a moment after the last tile)
	s.advance_game(5.0)
	var zs: Array = Array(s.state.zone_state)
	check("zones_complete_and_cleared", zs == [3, 3] and s.state.cleared and s.cleared_notices == 1 and s.zone_log.has(ZoneHud.CLEARED_TEXT), "zones=%s cleared=%s notices=%d" % [str(zs), str(s.state.cleared), s.cleared_notices])
	check("no_boar_ever_in_start_zone", boar_in_safe == 0, "samples=%d" % boar_in_safe)
	check("seed_gain_explained_by_pickups_or_rewards", seed_gain_unexplained == 0, "gain steps=%d unexplained=%d" % [seed_gain_events, seed_gain_unexplained])
	# finite resources: with no input and no pickups the seed count cannot rise; after completion nothing grows without bound
	var seeds_end: int = s.play.seeds
	s.advance_game(60.0)
	info("seeds at end=%d after +60s=%d (sources keep ground fruit capped; pouch max %d); pickups on ground=%d (cap %d)" % [seeds_end, s.play.seeds, s.play.tuning.seed_max, s.play.pickups.count(), s.play.pickups.total_cap])
	check("pickups_capped", s.play.pickups.count() <= s.play.pickups.total_cap + s.play.tuning.heal_fruit_total_cap)
	info("RESULT timeline: stable %.1f s; 100%% at %.1f s (after %.1f s, bound %.1f); wallclock %.1f s" % [t_stable, reached_at, reached_at - t_stable, bound, (Time.get_ticks_msec() - t0) / 1000.0])
	info("zone_times=%s" % JSON.stringify(s.zone_times))
	info("shots_fired=%d downs=%d hits=%d fruits_dropped=%d seeds_direct=%d" % [shots_fired, s.play.health.down_count, s.combat.hits, s.combat.fruits_dropped, s.combat.seeds_direct])
	_finish()

func _finish() -> void:
	var f: FileAccess = FileAccess.open(OUT + "play.log", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\nRESULT passes=%d failures=%d\n" % [passes, fails])
		f.close()
	print("RESULT passes=%d failures=%d" % [passes, fails])
	s.close()
	quit(1 if fails > 0 else 0)
