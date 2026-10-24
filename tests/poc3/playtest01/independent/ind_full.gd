extends SceneTree
## Independent item 13: no fair sweep; 100% reached with no input. Args after --: plain | loaded
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/playtest01/independent/"
func _init() -> void: call_deferred("run")
func run() -> void:
	var mode: String = "loaded" if "loaded" in OS.get_cmdline_user_args() else "plain"
	var s: RefCounted = Session.new()
	for n: Dictionary in s.nests.duplicate(): s.combat_system.damage_nest(n, float(n.hp) + 1.0)
	for e: Dictionary in s.enemies.duplicate(): s.combat_system.damage_enemy(e, float(e.hp) + 1.0)
	var info: Dictionary = {"mode": mode}
	if "control" in OS.get_cmdline_user_args():
		mode = "control"; info.mode = mode
		s.sim_tuning.far_sweep_start_delay_seconds = 120.0
	if mode == "loaded":
		s.seeds = 100000
		for k: String in ["clover", "carrot", "wheat", "rafflesia", "watermelon", "army", "gatlinger", "sprinkler"]: s.unlocked[k] = true
		var base: Vector2i = Coords.logic_to_cell(s.position)
		var placed: Dictionary = {}
		var order: Array = ["watermelon", "wheat", "clover", "carrot", "rafflesia", "army", "sprinkler", "gatlinger", "watermelon", "wheat", "clover"]
		var i: int = 0
		for r: int in range(3, 30, 1):
			if i >= order.size(): break
			for a: int in range(0, 360, 30):
				if i >= order.size(): break
				var c: Vector2i = base + Vector2i(roundi(cos(deg_to_rad(a + r * 7)) * r), roundi(sin(deg_to_rad(a + r * 7)) * r))
				if not s.state.in_bounds(c.x, c.y): continue
				var k: String = order[i]
				var res: Dictionary
				if s.CATALOG[k].role == "helper": res = s.place_helper(k, c, 100 if k == "gatlinger" else 0)
				else: res = s.place_plant(k, c)
				if bool(res.ok):
					placed[k] = int(placed.get(k, 0)) + 1; i += 1
					break
		info["placed"] = placed
	s.advance_game(1.0)
	var start: float = s.clock.elapsed
	var stable: bool = s.nests.is_empty() and s.enemies.is_empty() and s.state.zone_state[0] >= WorldState.ZONE_STABLE
	var top_first: float = -1.0
	var top_green: int = -1
	s.clock.max_advance = 120.0
	var first_targets: Array[int] = []
	for ix: int in s.state.tile_count():
		if s.state.target[ix] == 1 and s.state.stage[ix] == 0:
			first_targets.append(ix)
			if first_targets.size() >= 300: break
	info["first_target_cell"] = [first_targets[0] % s.state.width, first_targets[0] / s.state.width]
	var last_green: int = s.state.greened_count
	var last_change: float = s.clock.elapsed
	var tl: Array = []
	var seeds_zero_ok: bool = true
	var enemy_spawn: bool = false
	var income_hist: Array = []
	while not s.state.is_fully_greened() and s.clock.elapsed - start <= 21600.0 and s.clock.elapsed - last_change < 7200.0:
		s.clock.advance(120.0)
		if s.state.greened_count != last_green: last_green = s.state.greened_count; last_change = s.clock.elapsed
		if not s.enemies.is_empty() or not s.nests.is_empty(): enemy_spawn = true
		if top_first < 0.0:
			for ix: int in first_targets:
				if s.state.stage[ix] > 0:
					top_first = s.clock.elapsed - start; top_green = s.state.greened_count; break
		if int((s.clock.elapsed - start) / 600.0) > tl.size(): tl.append([int(s.clock.elapsed - start), s.state.greened_count, s.seeds])
	var missing: Array = []
	for index: int in s.state.tile_count():
		if s.state.target[index] == 1 and s.state.stage[index] < WorldState.GREENED_MIN_STAGE and missing.size() < 10:
			missing.append([index % s.state.width, index / s.state.width, s.state.stage[index], s.state.occupant[index] if "occupant" in s.state else -1])
	info.merge({"stable": stable, "seconds": s.clock.elapsed - start, "greened": s.state.greened_count, "targets": s.state.target_count, "fully": s.state.is_fully_greened(), "sweep_planted": s.far.total_sweep_planted, "island_planted": s.far.total_island_planted, "delay": s.sim_tuning.far_sweep_start_delay_seconds, "top_row_first_planted_s": top_first, "greened_when_top_row_first_planted": top_green, "reinvasion": enemy_spawn, "plants_alive": s.plants.size(), "helpers_alive": s.helpers.size(), "timeline": tl, "missing_sample": missing})
	print(JSON.stringify(info))
	var fa: FileAccess = FileAccess.open(OUT + "full_%s.json" % mode, FileAccess.WRITE)
	fa.store_string(JSON.stringify(info, "  ")); fa.close()
	s.close()
	quit(0 if bool(info.fully) and info.sweep_planted == 0 else 1)
