extends SceneTree
## POC-07 independent logic verification (headless, no OS input). Own BFS, own bot, own recount.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
var fails: int = 0
var s: RefCounted
var W: int = 0
var H: int = 0

func check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("PASS " if ok else "FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func mk() -> RefCounted:
	var sz: Vector2i = Session.town_size()
	var x: RefCounted = Session.new(sz.x, sz.y)
	if not x.load_combat(Session.TOWN_SETUP):
		print("FAIL load_combat")
	return x

func cc(c: Vector2i) -> Vector2:
	return Coords.cell_center_logic(c)

# own body test: Walker body half 0.28 m = 2.8 px, cell = 4 px -> body at cell centre touches the 8 neighbours
func passable_map(st: WorldState) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(W * H)
	for y: int in range(1, H - 1):
		for x: int in range(1, W - 1):
			var ok: bool = true
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					if not st.is_walkable(x + dx, y + dy):
						ok = false
			out[y * W + x] = 1 if ok else 0
	return out

func bfs(pm: PackedByteArray, from: Vector2i, blocked_goal: bool = false) -> PackedInt32Array:
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(W * H)
	dist.fill(-1)
	var q: Array[int] = [from.y * W + from.x]
	dist[q[0]] = 0
	var h: int = 0
	while h < q.size():
		var i: int = q[h]
		h += 1
		var x: int = i % W
		var y: int = i / W
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var j: int = ny * W + nx
			if pm[j] == 1 and dist[j] < 0:
				dist[j] = dist[i] + 1
				q.append(j)
	return dist

func path_to(pm: PackedByteArray, from: Vector2i, goals: Dictionary) -> Array[Vector2i]:
	var prev: PackedInt32Array = PackedInt32Array()
	prev.resize(W * H)
	prev.fill(-2)
	var q: Array[int] = [from.y * W + from.x]
	prev[q[0]] = -1
	var h: int = 0
	var found: int = -1
	if goals.has(q[0]):
		found = q[0]
	while found < 0 and h < q.size():
		var i: int = q[h]
		h += 1
		var x: int = i % W
		var y: int = i / W
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var j: int = ny * W + nx
			if pm[j] == 1 and prev[j] == -2:
				prev[j] = i
				if goals.has(j):
					found = j
					break
				q.append(j)
	var out: Array[Vector2i] = []
	if found < 0:
		return out
	var k: int = found
	while k >= 0:
		out.push_front(Vector2i(k % W, k / W))
		k = prev[k]
	return out

func goals_near(ctr: Vector2, rmax: float, rmin: float) -> Dictionary:
	var out: Dictionary = {}
	var c: Vector2i = Coords.logic_to_cell(ctr)
	var r: int = ceili(rmax / 4.0) + 1
	for y: int in range(maxi(c.y - r, 0), mini(c.y + r + 1, H)):
		for x: int in range(maxi(c.x - r, 0), mini(c.x + r + 1, W)):
			var i: int = y * W + x
			if P[i] == 1:
				var p: Vector2 = cc(Vector2i(x, y))
				var d: float = p.distance_to(ctr)
				if d <= rmax and d >= rmin and not s.shot_blocked(p, ctr):
					out[i] = true
	return out

func _run() -> void:
	s = mk()
	var st: WorldState = s.state
	W = st.width
	H = st.height
	var pl: RefCounted = s.placement
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Session.TOWN_SETUP))
	# ---- 1 scale / composition
	check("c1 size m", absf(W * 0.4 - 44.8) < 0.01 and H == 112, "%dx%d cells" % [W, H])
	var blds: int = 0
	var cars: int = 0
	var pud: int = 0
	var props: int = 0
	for inst: Dictionary in pl.instances:
		if inst["kind"] == "building":
			blds += 1
		elif inst["kind"] == "puddle":
			pud += 1
		else:
			props += 1
			if String(inst["asset"]) == "PRP-041":
				cars += 1
	check("c1 buildings 5..8", blds >= 5 and blds <= 8, str(blds))
	check("c1 puddles>=2 cars>=1 props", pud >= 2 and cars >= 1 and props >= 5, "pud=%d cars=%d props=%d" % [pud, cars, props])
	var pm: PackedByteArray = passable_map(st)
	var start: Vector2i = Coords.logic_to_cell(s.position)
	var d0: PackedInt32Array = bfs(pm, start)
	check("c1 start passable, not inside a building footprint", pm[start.y * W + start.x] == 1, str(start))
	# ---- 2 game elements
	check("c2 zones: start >=stable, ruined unconquered", st.zone_count == 2 and st.zone_state[0] >= WorldState.ZONE_STABLE and st.zone_state[1] == WorldState.ZONE_UNCONQUERED, str(st.zone_state))
	var nests: Array = s.enemies.nests
	check("c2 nests 2..3", nests.size() >= 2 and nests.size() <= 3, str(nests.size()))
	check("c2 seed sources", s.play.sources.size() >= 1, str(s.play.sources.size()))
	var reached: int = 0
	for src: SeedSource in s.play.sources:
		var c: Vector2i = Coords.logic_to_cell(src.position)
		var best: int = 999999
		for dy: int in range(-3, 4):
			for dx: int in range(-3, 4):
				var x: int = c.x + dx
				var y: int = c.y + dy
				if x >= 0 and y >= 0 and x < W and y < H and d0[y * W + x] >= 0 and cc(Vector2i(x, y)).distance_to(src.position) <= 10.0:
					best = mini(best, d0[y * W + x])
		if best < 999999:
			reached += 1
	check("c2 every seed source reachable (pickup range)", reached == s.play.sources.size(), "%d/%d" % [reached, s.play.sources.size()])
	var shoot_cells: Dictionary = {}
	var rng_px: float = s.projectiles.range_px
	for n: Nest in nests:
		var ctr: Vector2 = n.center_px(4)
		var cands: Dictionary = {}
		for i: int in W * H:
			if d0[i] >= 0:
				var p: Vector2 = cc(Vector2i(i % W, i / W))
				if p.distance_to(ctr) <= rng_px - 5.0 and not s.shot_blocked(p, ctr):
					cands[i] = true
		shoot_cells[n.id] = cands
		check("c2 nest %d reachable firing spots" % n.id, cands.size() > 0, "%d spots (range %.0f px)" % [cands.size(), rng_px])
	# water
	var shore_reach: int = 0
	var water_walk: int = 0
	var puddle_cells: int = 0
	var puddle_bad: int = 0
	for i: int in W * H:
		var def: TerrainDef = st.terrain_def_at(i)
		if def.is_waterside and d0[i] < 0 and false:
			pass
		if def.is_waterside:
			var x: int = i % W
			var y: int = i / W
			if String(def.key) == "water" and st.is_walkable(x, y):
				water_walk += 1
		if pl.puddle[i] == 1:
			puddle_cells += 1
			if not st.is_walkable(i % W, i / W) or def.is_waterside:
				puddle_bad += 1
	for i: int in W * H:
		if d0[i] >= 0:
			var cx: int = i % W
			var cy: int = i / W
			var near: bool = false
			for dy: int in range(-2, 3):
				for dx: int in range(-2, 3):
					if dx * dx + dy * dy <= 4 and cx + dx >= 0 and cy + dy >= 0 and cx + dx < W and cy + dy < H and st.terrain_def_at((cy + dy) * W + cx + dx).is_waterside:
						near = true
			if near:
				shore_reach += 1
	check("c2 constant water: reachable waterside cells exist, deep water not walkable", shore_reach > 0 and water_walk == 0, "shore_reach=%d" % shore_reach)
	check("c2 puddles walkable, not waterside", puddle_cells > 0 and puddle_bad == 0, "cells=%d bad=%d" % [puddle_cells, puddle_bad])
	# island
	var isl_reach: int = 0
	var isl_target: int = 0
	var isl_cells: int = 0
	for y: int in range(53, 57):
		for x: int in range(52, 56):
			isl_cells += 1
			if d0[y * W + x] >= 0:
				isl_reach += 1
			if st.target[y * W + x] == 1:
				isl_target += 1
	check("c2 island unreachable, is a target", isl_reach == 0 and isl_target > 0, "reach=%d targets=%d/%d" % [isl_reach, isl_target, isl_cells])
	# water supply: real sim
	var sx: Vector2i = Vector2i(-1, -1)
	var ws: float = 0.0
	for i: int in W * H:
		if d0[i] >= 0 and sx.x < 0:
			var cx2: int = i % W
			var cy2: int = i / W
			if st.terrain_def_at(i).is_waterside or st.terrain_def_at(i - 1).is_waterside or st.terrain_def_at(i + 1).is_waterside or st.terrain_def_at(i - W).is_waterside or st.terrain_def_at(i + W).is_waterside:
				sx = Vector2i(cx2, cy2)
	s.position = cc(sx)
	s.play.water = 0.0
	s.advance_game(1.0)
	var got_shore: float = s.play.water
	# puddle: stand on puddle cell, far from shore
	var pc: Vector2i = Vector2i(-1, -1)
	for i: int in W * H:
		if pl.puddle[i] == 1 and d0[i] >= 0:
			pc = Vector2i(i % W, i / W)
			break
	s.position = cc(pc)
	s.play.water = 0.0
	s.advance_game(2.0)
	check("c2 shore refills, puddle does not", got_shore > 1.0 and s.play.water == 0.0, "shore=%.1f puddle=%.1f at %s" % [got_shore, s.play.water, str(pc)])
	s.close()
	# ---- 4 determinism
	var a: RefCounted = mk()
	var b: RefCounted = mk()
	var same: bool = a.placement.instances.size() == b.placement.instances.size()
	for i: int in a.placement.instances.size():
		var ia: Dictionary = a.placement.instances[i]
		var ib: Dictionary = b.placement.instances[i]
		if ia != ib:
			same = false
	check("c4 instance id/transform identical", same, "%d instances" % a.placement.instances.size())
	check("c4 target set identical", a.state.target == b.state.target and a.state.terrain == b.state.terrain and a.state.target_count == b.state.target_count, "targets=%d hash=%d" % [a.state.target_count, hash(a.state.target)])
	var nt_same: bool = a.enemies.nests.size() == b.enemies.nests.size()
	for i: int in a.enemies.nests.size():
		if a.enemies.nests[i].tile != b.enemies.nests[i].tile:
			nt_same = false
	check("c4 nests identical", nt_same)
	var ids: Dictionary = {}
	var uniq: bool = true
	for inst: Dictionary in a.placement.instances:
		if ids.has(inst["id"]):
			uniq = false
		ids[inst["id"]] = true
	check("c4 ids unique", uniq)
	a.close()
	b.close()
	# ---- 5 full run with bot
	await process_frame
	bot()
	quit(1 if fails > 0 else 0)

var P: PackedByteArray
func walk_path(path: Array[Vector2i], limit_s: float = 300.0) -> bool:
	var t: float = 0.0
	for c: Vector2i in path:
		var wp: Vector2 = cc(c)
		var stuck: int = 0
		while s.position.distance_to(wp) > 1.2:
			if t > limit_s:
				return false
			var d: Vector2 = (wp - s.position)
			var before: Vector2 = s.position
			s.walk(Coords.ground_dir_to_screen(d.normalized()), 0.1)
			s.advance_game(0.1)
			t += 0.1
			combat_reflex()
			stuck = stuck + 1 if s.position.distance_to(before) < 0.01 else 0
			if stuck > 30:
				print("STUCK pos=", s.position, " wp=", wp, " cell=", Coords.logic_to_cell(s.position), " wpcell=", c, " paused=", s.paused, " downed=", s.play.health.downed)
				var cp: Vector2i = Coords.logic_to_cell(s.position)
				var row: String = ""
				for yy: int in range(cp.y - 3, cp.y + 4):
					for xx: int in range(cp.x - 4, cp.x + 5):
						row += ("." if s.state.is_walkable(xx, yy) else "#")
					row += "\n"
				print(row)
				return false
	return true

var shot_t: float = -10.0
func combat_reflex() -> void:
	if s.clock.elapsed - shot_t < 0.35 or s.play.health.downed or s.play.seeds <= 0:
		return
	for bo: Boar in s.enemies.boars:
		var ctr: Vector2 = s.enemies.boar_body_center(bo)
		if ctr.distance_to(s.position) <= 45.0 and not s.shot_blocked(s.position, ctr):
			s.fire(false, ctr)
			shot_t = s.clock.elapsed
			return

func refill_seeds(want: int) -> bool:
	var cur: Vector2i = Coords.logic_to_cell(s.position)
	var goals: Dictionary = {}
	for src: SeedSource in s.play.sources:
		var c: Vector2i = Coords.logic_to_cell(src.position)
		for dy: int in range(-2, 3):
			for dx: int in range(-2, 3):
				var i: int = (c.y + dy) * W + c.x + dx
				if P[i] == 1:
					goals[i] = true
	var pth: Array[Vector2i] = path_to(P, cur, goals)
	if not walk_path(pth):
		check("bot reached seed source", false, str(cur))
		return false
	var w: float = 0.0
	while s.play.seeds < want and w < 120.0:
		s.advance_game(0.5)
		combat_reflex()
		w += 0.5
	return true

func bot() -> void:
	s = mk()
	var st: WorldState = s.state
	P = passable_map(st)
	var total0: int = st.target_count
	var bound0: float = s.far.completion_bound_seconds()
	print("start: targets=%d greened=%d bound0=%.1fs seeds=%d hp=%d" % [total0, st.greened_count, bound0, s.play.seeds, s.play.hp])
	var wall0: int = Time.get_ticks_msec()
	var log: Array[String] = []
	var destroyed: Dictionary = {}
	var guard: int = 0
	while s.enemies.alive_nest_count() > 0 and guard < 40:
		guard += 1
		var cur: Vector2i = Coords.logic_to_cell(s.position)
		if s.play.seeds < 10:
			if not refill_seeds(18):
				break
		cur = Coords.logic_to_cell(s.position)
		# pick nearest alive nest by path length
		var bestp: Array[Vector2i] = []
		var bestn: Nest = null
		for n: Nest in s.enemies.nests:
			if not n.alive:
				continue
			var ctr: Vector2 = n.center_px(4)
			var goals2: Dictionary = goals_near(ctr, s.projectiles.range_px - 10.0, 12.0)
			var pp: Array[Vector2i] = path_to(P, cur, goals2)
			if pp.size() > 0 and (bestn == null or pp.size() < bestp.size()):
				bestp = pp
				bestn = n
		if bestn == null:
			check("bot found firing path to a nest", false)
			break
		if not walk_path(bestp):
			check("bot walked to nest %d firing spot" % bestn.id, false, "stuck near %s" % str(Coords.logic_to_cell(s.position)))
			break
		var hp_before: int = bestn.hp
		var tries: int = 0
		while bestn.alive and tries < 600:
			tries += 1
			if s.play.seeds <= 0:
				break
			s.fire(false, bestn.center_px(4))
			s.advance_game(0.4)
		if bestn.alive:
			print("INFO nest %d still alive hp %d (out of seeds, will refill)" % [bestn.id, bestn.hp])
		else:
			check("bot destroyed nest %d by session.fire" % bestn.id, true, "hp %d->%d from cell %s in %d shots game t=%.0fs" % [hp_before, bestn.hp, str(Coords.logic_to_cell(s.position)), tries, s.clock.elapsed])
		destroyed[bestn.id] = destroyed.get(bestn.id, false) or not bestn.alive
		print("wall ms ", Time.get_ticks_msec() - wall0)
	check("all nests destroyed", s.enemies.alive_nest_count() == 0)
	# remaining boars
	var rounds: int = 0
	var chase_t: float = 0.0
	var chase_start: float = s.clock.elapsed
	while s.enemies.boars.size() > 0 and chase_t < 900.0:
		chase_t = s.clock.elapsed - chase_start
		rounds += 1
		s.advance_game(0.1)
		if s.play.seeds < 3 and not refill_seeds(12):
			break
		var tstart: float = s.clock.elapsed
		var bo: Boar = s.enemies.boars[0]
		var cur2: Vector2i = Coords.logic_to_cell(s.position)
		var bc: Vector2i = Coords.logic_to_cell(bo.pos)
		var goals3: Dictionary = goals_near(s.enemies.boar_body_center(bo), 35.0, 10.0)
		var pp2: Array[Vector2i] = path_to(P, cur2, goals3)
		if pp2.size() == 0:
			s.advance_game(1.0)
			chase_t += 1.0
		else:
			var cut: Array[Vector2i] = []
			for k: int in mini(pp2.size(), 12):
				cut.append(pp2[k])
			var t0: float = s.clock.elapsed
			walk_path(cut, 30.0)
			chase_t += s.clock.elapsed - t0
		var t1: float = s.clock.elapsed
		var ctr2: Vector2 = s.enemies.boar_body_center(bo)
		if ctr2.distance_to(s.position) <= 40.0 and not s.shot_blocked(s.position, ctr2) and s.play.seeds > 0:
			s.fire(false, ctr2)
			s.advance_game(0.3)
			chase_t += s.clock.elapsed - t1
	check("all boars removed", s.enemies.boars.size() == 0, "chase %.0fs rounds %d, boars left %d, hp %d, killed %d" % [chase_t, rounds, s.enemies.boars.size(), s.play.hp, s.enemies.total_killed])
	print("zone states: ", st.zone_state, " t=", s.clock.elapsed, " greened=", st.greened_count, "/", st.target_count)
	check("zone 1 stable after clearing", st.zone_state[1] >= WorldState.ZONE_STABLE, str(st.zone_state[1]))
	# no-input wait
	var t_stable: float = s.clock.elapsed
	var bound1: float = s.far.completion_bound_seconds()
	var g_stable: int = st.greened_count
	var reinvade: bool = false
	var done: bool = false
	var seeds_s: int = s.play.seeds
	var waited: float = 0.0
	while waited < bound0 + 5.0:
		s.advance_game(2.0)
		waited += 2.0
		for z: int in st.zone_count:
			if st.zone_state[z] >= WorldState.ZONE_STABLE and s.enemies.boar_count_in_zone(z) > 0:
				reinvade = true
		if s.enemies.boars.size() > 0 or s.enemies.alive_nest_count() > 0:
			reinvade = true
		var rg: int = 0
		var rt: int = 0
		if int(waited) % 20 == 0 or true:
			if st.greened_count == st.target_count:
				rg = st.recount_greened()
				rt = st.recount_targets()
				if rg == rt and rt == st.target_count:
					done = true
					break
	var own_t: int = 0
	var own_g: int = 0
	for i: int in st.tile_count():
		if st.target[i] == 1:
			own_t += 1
			if st.stage[i] >= 2:
				own_g += 1
	check("c5 greened==target (own recount) within bound", done and own_g == own_t and own_t == total0, "own %d/%d, counters %d/%d (initial targets %d)" % [own_g, own_t, st.greened_count, st.target_count, total0])
	check("c5 no re-invasion of stable zones", not reinvade)
	print("BOUND0=%.1fs BOUND1=%.1fs MEASURED_after_stable=%.1fs (stable at game t=%.1fs, greened then %d/%d) total game t=%.1fs percent=%d cleared=%s zones=%s" % [bound0, bound1, waited, t_stable, g_stable, own_t, s.clock.elapsed, s.greening_percent(), str(st.cleared), str(st.zone_state)])
	check("c5 within bound", waited <= bound0, "%.1f <= %.1f" % [waited, bound0])
	print("RESULT fails=", fails)
	s.close()
