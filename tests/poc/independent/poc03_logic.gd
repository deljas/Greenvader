extends SceneTree
## POC-03 independent verification. In-engine only; no OS input. Own oracles (terrain/obstacle arrays), not the session's checks.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocInput: GDScript = preload("res://scripts/poc/poc_input.gd")
var fails: int = 0

func check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("PASS " if ok else "FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func fresh() -> RefCounted:
	var s: RefCounted = Session.new()
	assert(s.load_placement())
	return s

func solid(s: RefCounted, cell: Vector2i) -> bool:
	## Own oracle for "stops a shot": off-map, outer/base building ring, or an obstacle cell owned by a catalog asset with blocks_projectile.
	if not s.state.in_bounds(cell.x, cell.y):
		return true
	var i: int = s.state.index_of(cell.x, cell.y)
	if s.placement.obstacle[i] == 0:
		return s.state.terrain[i] == s.placement.building_id
	var owner: int = s.placement.owner_index[i]
	if owner <= 0:
		return true
	var asset: String = String(s.placement.instances[owner - 1]["asset"])
	return bool(s.placement.catalog[asset].get("blocks_projectile", false))

func seg_crosses_solid(s: RefCounted, a: Vector2, b: Vector2) -> bool:
	var n: int = maxi(ceili(a.distance_to(b) * 2.0), 1)
	for k: int in range(1, n):
		if solid(s, Coords.logic_to_cell(a.lerp(b, float(k) / float(n)))):
			return true
	return false

func count_stage(s: RefCounted, min_stage: int) -> int:
	var c: int = 0
	for i: int in s.state.stage.size():
		if s.state.stage[i] >= min_stage:
			c += 1
	return c

func plant_pickups(s: RefCounted) -> int:
	var c: int = 0
	for it: Dictionary in s.play.pickups.items:
		if int(it["owner"]) >= GroundPickups.PLANT_OWNER_BASE:
			c += 1
	return c

func nearest_pickup(s: RefCounted) -> Variant:
	var best: Variant = null
	var bd: float = 1e9
	for it: Dictionary in s.play.pickups.items:
		var p: Vector2 = Vector2(float(it["x"]), float(it["y"]))
		var d: float = p.distance_to(s.position)
		if d < bd:
			bd = d
			best = p
	return best

func fire_seed_at_open(s: RefCounted, offset_cells: Vector2i) -> Dictionary:
	var target: Vector2 = s.position + Vector2(offset_cells) * float(Config.TILE_PX)
	return s.fire(false, target)

func _run() -> void:
	_defaults()
	_cycle()
	_recovery()
	_shots()
	_pause()
	await _main_checks()
	print("FAILS=", fails)
	quit(1 if fails > 0 else 0)

func _defaults() -> void:
	var s: RefCounted = fresh()
	check("default.debug_off", not s.debug_refill_enabled and not s.debug_refill())
	check("default.finite_seeds", s.play.seeds == s.play_tuning.seed_start and s.play.seeds < 100, "seeds=%d water=%.0f" % [s.play.seeds, s.play.water])

func _cycle() -> void:
	var s: RefCounted = fresh()
	print("start cell ", Coords.logic_to_cell(s.position), " seeds ", s.play.seeds)
	var seeds0: int = s.play.seeds
	# plant seeds on a ring of open targets around the player, fire at different spots, stay within the shared safe patch
	var offsets: Array[Vector2i] = [Vector2i(3, 0), Vector2i(0, 3), Vector2i(-3, 0), Vector2i(0, -3), Vector2i(3, 3), Vector2i(-3, -3)]
	var fired: int = 0
	for o: Vector2i in offsets:
		var r: Dictionary = fire_seed_at_open(s, o)
		if r["ok"]:
			fired += 1
		s.advance_game(1.0)
	check("cycle.sown", fired >= 4 and s.play.seeds == seeds0 - fired and count_stage(s, 1) > 0, "fired=%d seeds=%d planted=%d" % [fired, s.play.seeds, count_stage(s, 1)])
	var planted0: int = count_stage(s, 1)
	var sprouted: bool = false
	var matured: bool = false
	var expanded: bool = false
	var got_fruit: bool = false
	var collected: bool = false
	var seeds_before_collect: int = -1
	var t: float = 0.0
	var water_shots: int = 0
	while t < 1200.0:
		s.advance_game(5.0)
		t += 5.0
		if not sprouted and count_stage(s, WorldState.STAGE_SPROUT1) > 0:
			sprouted = true
			print("sprout at t=", t)
		if not matured and s.state.mature_count > 0:
			matured = true
			print("mature at t=", t)
		if matured and not expanded and count_stage(s, 1) > planted0 + 6:
			expanded = true
			print("expanded at t=", t, " cells=", count_stage(s, 1), " vs ", planted0)
		if not got_fruit and plant_pickups(s) > 0:
			got_fruit = true
			print("plant fruit on ground at t=", t, " total pickups=", s.play.pickups.count())
		if got_fruit:
			# collect through normal walking toward the nearest pickup
			var target: Variant = nearest_pickup(s)
			if target != null and plant_pickups(s) > 0:
				var before: int = s.play.seeds
				var guard: int = 0
				while guard < 400 and nearest_pickup(s) != null and s.position.distance_to(nearest_pickup(s)) > 6.0:
					var p: Vector2 = nearest_pickup(s)
					var dir: Vector2 = (p - s.position).normalized()
					s.walk(Coords.ground_dir_to_screen(dir), 0.1)
					s.advance_game(0.1)
					guard += 1
				if s.play.seeds > before:
					collected = true
					seeds_before_collect = before
					print("collected: seeds ", before, " -> ", s.play.seeds)
		if collected:
			break
	check("cycle.germinate", sprouted)
	check("cycle.mature", matured)
	check("cycle.natural_expansion", expanded)
	check("cycle.fruit_on_ground", got_fruit)
	check("cycle.collect_increases_seeds", collected)
	# playing on: from the produced fruit fire again -> loop closes with player API only
	var r2: Dictionary = fire_seed_at_open(s, Vector2i(4, -2))
	check("cycle.refire_after_collect", r2["ok"] or s.play.seeds == 0, str(r2))
	s.close()

func _recovery() -> void:
	var s: RefCounted = fresh()
	s.play.seeds = 0
	var r: Dictionary = fire_seed_at_open(s, Vector2i(3, 0))
	check("recover.no_seed_refused", not r["ok"] and r["reason"] == "no_seed")
	# stand at the player start (safe zone with a source); wait; walk to pickups
	var got: bool = false
	var t: float = 0.0
	var src: Vector2 = s.play.sources[0].position
	print("source ", src, " player ", s.position)
	while t < 120.0 and not got:
		s.advance_game(0.5)
		t += 0.5
		var p: Variant = nearest_pickup(s)
		if p != null:
			var guard: int = 0
			while guard < 600 and nearest_pickup(s) != null and s.position.distance_to(nearest_pickup(s)) > 6.0 and s.play.seeds == 0:
				var q: Vector2 = nearest_pickup(s)
				s.walk(Coords.ground_dir_to_screen((q - s.position).normalized()), 0.1)
				s.advance_game(0.1)
				guard += 1
		if s.play.seeds > 0:
			got = true
	check("recover.seed_from_source", got, "t=%.0f seeds=%d" % [t, s.play.seeds])
	s.close()
	# water zero: growth continues but slower than watered
	var a: RefCounted = fresh()
	var dry_cell: Vector2i = Coords.logic_to_cell(a.position) + Vector2i(3, 0)
	a.play.water = 0.0
	var wet_fail: Dictionary = a.fire(true, a.position + Vector2(12, 0))
	check("recover.no_water_refused", not wet_fail["ok"] and wet_fail["reason"] == "no_water")
	a.fire(false, a.position + Vector2(12, 0))
	a.advance_game(2.0)
	var idx: Array[int] = []
	for i: int in a.state.stage.size():
		if a.state.stage[i] == WorldState.STAGE_SEED:
			idx.append(i)
	check("recover.dry_seed_planted", idx.size() > 0)
	var g0: int = 0
	for i: int in idx:
		g0 += a.state.growth[i]
	var dry_stage_progress: bool = false
	var t2: float = 0.0
	while t2 < 900.0 and not dry_stage_progress:
		a.advance_game(5.0)
		t2 += 5.0
		for i: int in idx:
			if a.state.stage[i] >= WorldState.STAGE_SPROUT1:
				dry_stage_progress = true
	var dry_t: float = t2
	check("recover.dry_growth_progresses", dry_stage_progress, "t=%.0f" % dry_t)
	# watered comparison
	var b: RefCounted = fresh()
	b.fire(false, b.position + Vector2(12, 0))
	b.advance_game(1.0)
	b.fire(true, b.position + Vector2(12, 0))
	b.advance_game(1.0)
	var idx2: Array[int] = []
	for i: int in b.state.stage.size():
		if b.state.stage[i] == WorldState.STAGE_SEED:
			idx2.append(i)
	var wet_t: float = 0.0
	var wet_prog: bool = false
	while wet_t < 900.0 and not wet_prog:
		b.advance_game(5.0)
		wet_t += 5.0
		for i: int in idx2:
			if b.state.stage[i] >= WorldState.STAGE_SPROUT1:
				wet_prog = true
	print("sprout time dry=", dry_t, " wet=", wet_t)
	check("recover.dry_is_slower_or_equal", wet_prog and dry_t >= wet_t, "dry=%.0f wet=%.0f" % [dry_t, wet_t])
	# water refill at shore: walk to nearest waterside cell
	a.play.water = 0.0
	var best: Vector2 = Vector2.ZERO
	var bd: float = 1e9
	for y: int in a.state.height:
		for x: int in a.state.width:
			var i2: int = a.state.index_of(x, y)
			if a.state.terrain_def_at(i2).is_waterside and a.state.is_walkable(x, y):
				var c: Vector2 = Coords.cell_center_logic(Vector2i(x, y))
				if c.distance_to(a.position) < bd:
					bd = c.distance_to(a.position)
					best = c
	var guard2: int = 0
	while guard2 < 3000 and a.position.distance_to(best) > 3.0:
		a.walk(Coords.ground_dir_to_screen((best - a.position).normalized()), 0.1)
		a.advance_game(0.1)
		guard2 += 1
	var w_before: float = a.play.water
	a.advance_game(2.0)
	check("recover.water_refill_at_shore", a.play.water > w_before, "reached=%s water %.1f -> %.1f at %s" % [a.position.distance_to(best) <= 3.0, w_before, a.play.water, a.position])
	a.close()
	b.close()

func _shots() -> void:
	var s: RefCounted = fresh()
	# find a free walkable cell with a solid cell 2..5 cells away in a cardinal direction and open ground 2+ cells beyond it
	var found: bool = false
	var pos_cell: Vector2i
	var dir: Vector2i
	var wall_dist: int = 0
	for y: int in range(2, s.state.height - 2):
		for x: int in range(2, s.state.width - 2):
			var c: Vector2i = Vector2i(x, y)
			if solid(s, c):
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				for k: int in range(2, 6):
					if solid(s, c + d * k) and not solid(s, c + d * (k - 1)):
						# thin wall (thickness t) then open beyond
						var t: int = 1
						while solid(s, c + d * (k + t)) and t < 6:
							t += 1
						if not solid(s, c + d * (k + t)) and not solid(s, c + d * (k + t + 1)) and k + t + 1 <= 14:
							pos_cell = c
							dir = d
							wall_dist = k
							found = true
							break
				if found:
					break
			if found:
				break
		if found:
			break
	check("shots.found_wall_scenario", found)
	if not found:
		return
	print("scenario cell ", pos_cell, " dir ", dir, " wall at ", wall_dist)
	s.position = Coords.cell_center_logic(pos_cell)
	var beyond: Vector2 = s.position + Vector2(dir) * float(Config.TILE_PX) * float(wall_dist + 4)
	var stage0: int = count_stage(s, 1)
	var seeds0: int = s.play.seeds
	var res: Dictionary = s.fire(false, beyond)
	s.advance_game(5.0)
	var stray: int = 0
	var bad_side: int = 0
	for i: int in s.state.stage.size():
		if s.state.stage[i] > 0:
			var c: Vector2i = Vector2i(i % s.state.width, i / s.state.width)
			if seg_crosses_solid(s, s.position, Coords.cell_center_logic(c)):
				bad_side += 1
	check("shots.wall_no_plant_beyond", bad_side == 0, "fire=%s planted_total=%d beyond=%d blocked=%d filtered=%d msg=%s" % [res["ok"], count_stage(s, 1), bad_side, s.shots_blocked_by_wall, s.scatter_filtered, s.last_message])
	# also with water
	var wet_before: int = 0
	for i: int in s.state.moisture.size():
		wet_before += s.state.moisture[i]
	s.fire(true, beyond)
	s.advance_game(5.0)
	# diagonal grazing: aim through each of the four wall-adjacent directions from many positions around the first wall: no plant on far side
	var viol: int = 0
	var viol_land: int = 0
	var viol_far: int = 0
	var tries: int = 0
	var landings_seen: int = 0
	var sample: String = ""
	for dx: int in range(-3, 4):
		for dy: int in range(-3, 4):
			var base: Vector2i = pos_cell + Vector2i(dx, dy)
			for ang: int in range(0, 360, 30):
				var s2: RefCounted = fresh()
				if solid(s2, base):
					s2.close()
					break
				s2.position = Coords.cell_center_logic(base)
				var lp: Array = []
				s2.projectiles.landed.connect(func(_k: String, pt: Vector2) -> void: lp.append(pt))
				var aim: Vector2 = s2.position + Vector2.from_angle(deg_to_rad(float(ang))) * 60.0
				s2.fire(false, aim)
				s2.advance_game(3.0)
				tries += 1
				for pt: Vector2 in lp:
					landings_seen += 1
					if solid(s2, Coords.logic_to_cell(pt)) or seg_crosses_solid(s2, s2.position, pt):
						viol_land += 1
					for i: int in s2.state.stage.size():
						if s2.state.stage[i] > 0 and s2.state.growth[i] == 0:
							var c2: Vector2i = Vector2i(i % s2.state.width, i / s2.state.width)
							var cc: Vector2 = Coords.cell_center_logic(c2)
							if cc.distance_to(pt) <= 14.0:
								if seg_crosses_solid(s2, pt, cc) or solid(s2, c2):
									viol += 1
									if sample == "":
										sample = "base=%s ang=%d land=%s cell=%s" % [base, ang, pt, c2]
				s2.close()
	print("sweep tries=", tries, " landings=", landings_seen, " sample=", sample)
	viol = viol + viol_land
	check("shots.radial_sweep_no_plant_behind_walls", viol == 0 and tries > 5, "tries=%d violations=%d" % [tries, viol])
	s.close()
	# non-target aims: building cell / water cell centre
	var n: RefCounted = fresh()
	var bcell: Vector2i = Vector2i(-1, -1)
	var wcell: Vector2i = Vector2i(-1, -1)
	for y: int in range(1, n.state.height - 1):
		for x: int in range(1, n.state.width - 1):
			var i: int = n.state.index_of(x, y)
			var def: TerrainDef = n.state.terrain_def_at(i)
			if wcell.x < 0 and String(def.key) == "water":
				wcell = Vector2i(x, y)
			if bcell.x < 0 and solid(n, Vector2i(x, y)) and solid(n, Vector2i(x + 1, y)) and solid(n, Vector2i(x, y + 1)):
				bcell = Vector2i(x, y)
	var green0: int = n.state.greened_count
	var stage_before: int = count_stage(n, 1)
	var pond_c: Vector2 = Coords.cell_center_logic(Vector2i(42, 5))
	n.position = Coords.cell_center_logic(Vector2i(42, 9))
	print("pond start cell solid=", solid(n, Coords.logic_to_cell(n.position)), " terrain at pos=", n.state.terrain_def_at(n.state.index_of(42, 9)).key)
	for k: int in 3:
		n.fire(false, pond_c)
		n.advance_game(2.0)
	var pond_planted: int = count_stage(n, 1) - stage_before
	# building interior: aim at the middle of the outer ring corner region from inside, next to it (wall blocks)
	n.position = Coords.cell_center_logic(Vector2i(3, 3))
	for k: int in 3:
		n.fire(false, Coords.cell_center_logic(Vector2i(0, 0)))
		n.advance_game(2.0)
	n.advance_game(60.0)
	check("nontarget.pond_centre_aim_plants_nothing", pond_planted == 0, "planted=%d" % pond_planted)
	var ctl: RefCounted = fresh()
	ctl.advance_game(n.clock.elapsed)
	check("nontarget.green_same_as_untouched_control", n.state.greened_count == ctl.state.greened_count and n.state.counters_consistent(), "green n=%d control=%d start=%d" % [n.state.greened_count, ctl.state.greened_count, green0])
	ctl.close()
	var bad_planted: int = 0
	for i: int in n.state.stage.size():
		if n.state.stage[i] > 0 and n.state.target[i] == 0:
			bad_planted += 1
	check("nontarget.no_stage_on_nontarget", bad_planted == 0, "bad=%d" % bad_planted)
	n.close()
	# range clamp: far aim lands at range_px
	var f: RefCounted = fresh()
	var rr: Dictionary = f.fire(false, f.position + Vector2(0, 1000))
	check("shots.range_clamped", rr["ok"] and f.position.distance_to(rr["landing"]) <= f.play_tuning.projectile_range_px + 0.01, "landing dist %.1f cap %.1f" % [f.position.distance_to(rr["landing"]), f.play_tuning.projectile_range_px])
	f.close()

func snap_all(s: RefCounted) -> Dictionary:
	var shots: Array = []
	for sh: Dictionary in s.projectiles.shots:
		shots.append([sh["position"], sh["age"]])
	var ages: Array = []
	for it: Dictionary in s.play.pickups.items:
		ages.append([it["x"], it["y"], it["age"]])
	var timers: Array = []
	for src: SeedSource in s.play.sources:
		timers.append(src.timer)
		timers.append(src.drops)
	return {"elapsed": s.clock.elapsed, "gt": s.clock.growth_ticks, "st": s.clock.spread_ticks, "seeds": s.play.seeds, "water": s.play.water, "pe": s.play.elapsed, "prod": s.play.production_ticks, "pt": s.play.production_time, "shots": shots, "ages": ages, "timers": timers, "growth": Array(s.state.growth), "stage": Array(s.state.stage), "moist": Array(s.state.moisture), "pos": s.position, "hp": s.play.hp}

func _pause() -> void:
	var s: RefCounted = fresh()
	# get something in every system: plants, pickups, a shot in flight
	for o: Vector2i in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3)]:
		fire_seed_at_open(s, o)
		s.advance_game(0.5)
	s.advance_game(40.0)
	s.fire(false, s.position + Vector2(40, 0))
	s.advance_game(0.1)
	check("pause.has_things", s.projectiles.shots.size() > 0 and s.play.pickups.count() > 0, "shots=%d pickups=%d" % [s.projectiles.shots.size(), s.play.pickups.count()])
	s.paused = true
	var a: Dictionary = snap_all(s)
	s.advance_game(60.0)
	s.advance(10.0)
	s.walk(Vector2.RIGHT, 5.0)
	var fired: Dictionary = s.fire(false, s.position + Vector2(20, 0))
	var b: Dictionary = snap_all(s)
	check("pause.nothing_moves", a == b and not fired["ok"], "elapsed %f->%f fire=%s" % [a["elapsed"], b["elapsed"], fired])
	# near water refill frozen too
	s.paused = false
	var e0: float = s.clock.elapsed
	s.advance_game(0.25)
	var d: float = s.clock.elapsed - e0
	check("pause.no_catch_up", absf(d - 0.25) < 1e-6 and absf(s.play.elapsed - (float(a["pe"]) + 0.25)) < 1e-6, "dt=%f play dt=%f" % [d, s.play.elapsed - float(a["pe"])])
	# water refill frozen: stand at shore with empty gauge, paused
	var w: RefCounted = fresh()
	var best: Vector2 = Vector2.ZERO
	var bd: float = 1e9
	for y: int in w.state.height:
		for x: int in w.state.width:
			var i: int = w.state.index_of(x, y)
			if w.state.terrain_def_at(i).is_waterside and w.state.is_walkable(x, y):
				var c: Vector2 = Coords.cell_center_logic(Vector2i(x, y))
				if c.distance_to(w.position) < bd:
					bd = c.distance_to(w.position)
					best = c
	w.position = best
	w.play.water = 0.0
	w.paused = true
	w.advance_game(30.0)
	check("pause.refill_frozen", w.play.water == 0.0)
	w.close()
	s.close()

func _frames(n: int) -> void:
	for i: int in n:
		await process_frame

func _main_checks() -> void:
	PocInput.register()
	var main: Node = load("res://scenes/poc.tscn").instantiate()
	root.add_child(main)
	await _frames(2)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	var s: RefCounted = main.session
	main.tick(0.0, Vector2.ZERO)
	var norm_points: Array[Vector2] = [Vector2(0.55, 0.40), Vector2(0.30, 0.65), Vector2(0.50, 0.50)]
	var lands: Array = [[], []]
	for r: int in 2:
		if main.current_resolution() != Config.RESOLUTIONS[r]:
			main.toggle_resolution(Vector2i(1920, 1080))
		main.tick(0.0, Vector2.ZERO)
		var size: Vector2 = Vector2(main.render_view.size)
		print("res ", main.current_resolution(), " view ", size)
		for np: Vector2 in norm_points:
			var cp: Vector2 = np * size
			var pk: Dictionary = main.pick_ground(cp)
			var res: Dictionary = main.click_fire(cp, false) if pk["ok"] else {"ok": false}
			lands[r].append([pk.get("logic", Vector2.INF), res.get("landing", Vector2.INF)])
			s.advance_game(2.0)
	var same_pick: bool = true
	var same_land: bool = true
	for k: int in norm_points.size():
		var a: Array = lands[0][k]
		var b: Array = lands[1][k]
		if (a[0] as Vector2).distance_to(b[0]) > 0.5 or (a[0] as Vector2).x == INF:
			same_pick = false
		# landing from the same player position & aim must match; player did not move
		if (a[1] as Vector2).distance_to(b[1]) > 0.5 or (a[1] as Vector2).x == INF:
			same_land = false
	print("lands ", lands)
	check("click.same_screen_pos_same_ground_640_960", same_pick)
	check("click.same_landing_640_960", same_land)
	# UI rejection
	var rejected: bool = false
	for c: Control in main.ui_controls:
		if c.is_visible_in_tree():
			var pos: Vector2 = c.get_global_rect().get_center()
			var seeds0: int = s.play.seeds
			var n0: int = s.projectiles.shots.size()
			var r: Dictionary = main.click_fire(pos, false)
			rejected = not r["ok"] and s.play.seeds == seeds0 and s.projectiles.shots.size() == n0
			print("ui control ", c.name, " rect ", c.get_global_rect(), " result ", r)
			break
	check("click.ui_rejected", rejected and main.ui_controls.size() > 0)
	# inject a real mouse button event through the engine (no OS input) via parse_input_event
	var seeds1: int = s.play.seeds
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(main.render_view.size) * Vector2(0.55, 0.40)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await _frames(2)
	check("click.parse_input_event_fires", s.play.seeds == seeds1 - 1, "seeds %d -> %d" % [seeds1, s.play.seeds])
	# pause through main: tick with large delta while paused
	main.toggle_pause()
	var e0: float = s.clock.elapsed
	main.tick(5.0, Vector2.RIGHT)
	check("pause.main_tick_frozen", s.clock.elapsed == e0)
	main.toggle_pause()
	main.tick(0.1, Vector2.ZERO)
	check("pause.main_resume_small_step", s.clock.elapsed - e0 <= 0.1 + 1e-6, "dt=%f" % (s.clock.elapsed - e0))
	main.queue_free()
	await _frames(2)
