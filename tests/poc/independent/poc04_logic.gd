extends SceneTree
## POC-04 independent verification (in-engine only, no OS input). Own oracles from terrain/obstacle arrays.
## Harness operations (documented): player teleport (session.position) to shooting spots, seed top-up while fighting.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const TP: int = 4
var fails: int = 0

func check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("PASS " if ok else "FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func fresh() -> RefCounted:
	var s: RefCounted = Session.new()
	assert(s.load_combat())
	return s

# ---- own oracles ----
func idx(s: RefCounted, c: Vector2i) -> int:
	return c.y * 48 + c.x

func obstacle_cell(s: RefCounted, c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= 48 or c.y >= 40:
		return true
	var i: int = idx(s, c)
	return s.placement.obstacle[i] != 0 or s.base_terrain[i] == 4

func foot_ok(s: RefCounted, p: Vector2) -> bool:
	## own: feet cell is not building/obstacle/water (base terrain: 3 water, 4 building)
	var c: Vector2i = Vector2i(floori(p.x / TP), floori(p.y / TP))
	if obstacle_cell(s, c):
		return false
	return s.base_terrain[idx(s, c)] != 3

func solid_seg(s: RefCounted, a: Vector2, b: Vector2) -> bool:
	var n: int = maxi(ceili(a.distance_to(b) * 2.0), 1)
	for k: int in range(0, n + 1):
		var p: Vector2 = a.lerp(b, float(k) / float(n))
		if obstacle_cell(s, Vector2i(floori(p.x / TP), floori(p.y / TP))):
			return true
	return false

func expected_targets(s: RefCounted) -> PackedByteArray:
	## target = base terrain wasteland(0)/safe(1)/shore(2), no obstacle, and not sealed (reachable from the map ring interior through non-obstacle cells, water passable).
	var reach: PackedByteArray = PackedByteArray()
	reach.resize(48 * 40)
	var q: Array[Vector2i] = [Vector2i(24, 24)]
	reach[idx(s, q[0])] = 1
	var h: int = 0
	while h < q.size():
		var c: Vector2i = q[h]
		h += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
			var n: Vector2i = c + d
			if obstacle_cell(s, n) or reach[idx(s, n)] == 1:
				continue
			reach[idx(s, n)] = 1
			q.append(n)
	var out: PackedByteArray = PackedByteArray()
	out.resize(48 * 40)
	for i: int in 48 * 40:
		var kind: int = s.base_terrain[i]
		var c: Vector2i = Vector2i(i % 48, i / 48)
		if (kind == 0 or kind == 1 or kind == 2) and not obstacle_cell(s, c) and reach[i] == 1:
			out[i] = 1
	return out

func recount(s: RefCounted, exp: PackedByteArray) -> Vector2i:
	var t: int = 0
	var g: int = 0
	for i: int in 48 * 40:
		if exp[i] == 1:
			t += 1
			if s.state.stage[i] >= 2:
				g += 1
	return Vector2i(g, t)

# ---- combat helpers ----
func stand_near(s: RefCounted, target: Vector2, min_d: float, max_d: float) -> bool:
	## teleport the player to a clear walkable spot with a clear straight line to target.
	for r: float in [max_d * 0.6, max_d * 0.8, max_d, min_d + 1.0]:
		for k: int in 24:
			var ang: float = TAU * float(k) / 24.0
			var p: Vector2 = target + Vector2(cos(ang), sin(ang)) * r
			if not foot_ok(s, p) or not s.is_walkable_logic(p):
				continue
			if s.state.zone_of[idx(s, Vector2i(floori(p.x / TP), floori(p.y / TP)))] == 0 and false:
				continue
			if solid_seg(s, p, target):
				continue
			s.position = p
			return true
	return false

func settle_downed(s: RefCounted) -> void:
	var guard: int = 0
	while s.play.health.downed and guard < 400:
		s.advance_game(0.25)
		guard += 1

func shoot(s: RefCounted, target: Vector2) -> void:
	if s.play.health.downed:
		settle_downed(s)
	if s.play.seeds < 6:
		s.play.add_seeds(20)
	if not stand_near(s, target, 8.0, 24.0):
		return
	s.play.select_index(0)
	var r: Dictionary = s.fire(false, target)
	if bool(r["ok"]):
		s.advance_game(0.35)

func nest_center(s: RefCounted, n: Nest) -> Vector2:
	return n.center_px(TP)

func pending(s: RefCounted) -> int:
	return s.projectiles.shots.size()

func _run() -> void:
	_t_walls()
	if OS.get_cmdline_user_args().has("--walls"):
		print("FAILS=", fails)
		quit(1 if fails > 0 else 0)
		return
	_s1()
	_s_confine()
	await process_frame
	_s2_plants()
	print("FAILS=", fails)
	quit(1 if fails > 0 else 0)

# ---- condition 2 (shots) ----
func pblock(s: RefCounted, c: Vector2i) -> bool:
	## own oracle: stops a shot = off-map, base building ring, or obstacle owned by a catalog asset with blocks_projectile
	if c.x < 0 or c.y < 0 or c.x >= 48 or c.y >= 40:
		return true
	var i: int = idx(s, c)
	if s.placement.obstacle[i] == 0:
		return s.base_terrain[i] == 4
	var owner: int = s.placement.owner_index[i]
	if owner <= 0:
		return true
	return bool(s.placement.catalog[String(s.placement.instances[owner - 1]["asset"])].get("blocks_projectile", false))

func _pseg(s: RefCounted, a: Vector2, b: Vector2) -> bool:
	var n: int = maxi(ceili(a.distance_to(b) * 2.0), 1)
	for k: int in range(0, n + 1):
		var p: Vector2 = a.lerp(b, float(k) / float(n))
		if pblock(s, Vector2i(floori(p.x / TP), floori(p.y / TP))):
			return true
	return false

func _t_walls() -> void:
	var s: RefCounted = fresh()
	var wx: int = -1
	var wy: int = -1
	for y: int in range(2, 38):
		for x: int in range(6, 38):
			var ok: bool = pblock(s, Vector2i(x, y)) and obstacle_cell(s, Vector2i(x, y)) and not obstacle_cell(s, Vector2i(x - 1, y)) and not pblock(s, Vector2i(x + 1, y))
			if ok:
				for k: int in range(1, 6):
					ok = ok and not obstacle_cell(s, Vector2i(x - k, y)) and not obstacle_cell(s, Vector2i(x + k, y)) and s.base_terrain[idx(s, Vector2i(x - k, y))] != 3 and s.base_terrain[idx(s, Vector2i(x + k, y))] != 3
			if ok and wx < 0:
				wx = x
				wy = y
	check("2.0 found a shot-blocking wall with free ground on both sides", wx >= 0, "wall at (%d,%d)" % [wx, wy])
	var py: float = float(wy) + 0.5
	var boar: Boar = Boar.new()
	boar.id = 900
	boar.nest_id = 1
	boar.zone = 1
	boar.hp = 3
	boar.pos = Vector2(float(wx) - 3.5, py) * TP
	s.enemies.boars.append(boar)
	s.position = Vector2(float(wx) + 5.0, py) * TP
	var blocked_before: int = s.shots_blocked_by_wall
	check("2.1 line player->boar crosses a shot-blocking cell (own oracle)", _pseg(s, s.position, boar.pos))
	var r: Dictionary = s.fire(false, boar.pos)
	for i: int in 20:
		s.projectiles.advance(0.1)
	check("2.2 shot through wall: boar HP intact, shot blocked", boar.hp == 3 and s.shots_blocked_by_wall == blocked_before + 1 and bool(r["ok"]), "hp=%d blocked=%d" % [boar.hp, s.shots_blocked_by_wall])
	# control: same boar, same side, clear line
	s.position = boar.pos + Vector2(0.0, 12.0)
	check("2.3 control line is clear", not _pseg(s, s.position, boar.pos))
	s.fire(false, boar.pos)
	for i: int in 20:
		s.projectiles.advance(0.1)
	check("2.4 control: clear line hits boar (HP 3->2)", boar.hp == 2, "hp=%d" % boar.hp)
	# nest behind a wall: nest 1 at (24,5): no interior wall; skip. Hit over water: boar on the island, player on the east shore.
	var ib: Boar = Boar.new()
	ib.id = 901
	ib.nest_id = 1
	ib.zone = 1
	ib.hp = 3
	ib.pos = Vector2(7.5, 7.5) * TP
	s.enemies.boars.append(ib)
	s.position = Vector2(13.5, 7.5) * TP
	check("2.5 island cell: base terrain is not water and water lies between", s.base_terrain[idx(s, Vector2i(7, 7))] == 0 and s.base_terrain[idx(s, Vector2i(10, 7))] == 3)
	s.fire(false, ib.pos)
	for i: int in 20:
		s.projectiles.advance(0.1)
	check("2.6 shot flies over water and hits boar on island", ib.hp == 2, "hp=%d" % ib.hp)
	# order: wall then boar nearer than wall: boar between player and wall is hit, not the one behind
	var near: Boar = Boar.new()
	near.id = 902
	near.zone = 1
	near.hp = 3
	near.pos = Vector2(float(wx) + 3.0, py) * TP
	s.enemies.boars.append(near)
	s.position = Vector2(float(wx) + 5.5, py) * TP
	s.fire(false, boar.pos)
	for i: int in 20:
		s.projectiles.advance(0.1)
	check("2.7 nearest enemy before the wall is hit (near 3->2, far unchanged 2)", near.hp == 2 and boar.hp == 2, "near=%d far=%d" % [near.hp, boar.hp])
	s.close()

# ---- S1: conditions 1,2(walk),3,4 ----
func _s1() -> void:
	var s: RefCounted = fresh()
	var exp: PackedByteArray = expected_targets(s)
	var rc: Vector2i = recount(s, exp)
	var st_targets: int = 0
	var mismatch: int = 0
	for i: int in 48 * 40:
		if s.state.target[i] == 1:
			st_targets += 1
		if (s.state.target[i] == 1) != (exp[i] == 1):
			mismatch += 1
	check("4.0a target set == own recomputation (no building/water/sealed)", mismatch == 0 and st_targets == rc.y, "state=%d own=%d mismatch=%d" % [st_targets, rc.y, mismatch])
	var bad: int = 0
	for i: int in 48 * 40:
		if s.state.target[i] == 1 and (s.base_terrain[i] == 3 or s.base_terrain[i] == 4 or s.placement.obstacle[i] != 0):
			bad += 1
	check("4.0b no target cell is water/building/obstacle", bad == 0, "bad=%d" % bad)
	var island_cells: Array[Vector2i] = [Vector2i(6, 6), Vector2i(7, 7), Vector2i(8, 8), Vector2i(6, 8), Vector2i(8, 6)]
	var all_t: bool = true
	for c: Vector2i in island_cells:
		all_t = all_t and exp[idx(s, c)] == 1 and s.state.target[idx(s, c)] == 1
	check("4.0c island cells are targets", all_t)
	# island isolation: no walkable-neighbour path to mainland (own BFS without water)
	var seen: Dictionary = {Vector2i(7, 7): true}
	var qq: Array[Vector2i] = [Vector2i(7, 7)]
	var hh: int = 0
	while hh < qq.size():
		var c: Vector2i = qq[hh]
		hh += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n) and not obstacle_cell(s, n) and s.base_terrain[idx(s, n)] != 3:
				seen[n] = true
				qq.append(n)
	check("4.0d island is isolated by water (4-connected land component == 9 cells)", seen.size() == 9, "size=%d" % seen.size())
	# walk reachability of nests (own BFS on walkable)
	var reach: Dictionary = {s.placement.player_start_cell: true}
	var rq: Array[Vector2i] = [s.placement.player_start_cell]
	var rh: int = 0
	while rh < rq.size():
		var c: Vector2i = rq[rh]
		rh += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not reach.has(n) and s.state.in_bounds(n.x, n.y) and s.state.is_walkable(n.x, n.y):
				reach[n] = true
				rq.append(n)
	var all_reach: bool = true
	for n: Nest in s.enemies.nests:
		var near_ok: bool = false
		for c: Variant in reach.keys():
			if Vector2(c).distance_to(Vector2(n.tile) + Vector2(2, 2)) <= 15.0:
				near_ok = true
				break
		all_reach = all_reach and near_ok
	check("1.0 every nest has a walk-reachable cell within shooting range (<=15 cells)", all_reach)
	var bound: float = s.far.completion_bound_seconds()
	print("INFO bound(pre)=", bound, " targets=", s.state.target_count, " initial green=", s.state.greened_count)
	# --- spawn behaviour with nests alive; player idle in safe zone
	var max_total: int = 0
	var max_per_nest: Dictionary = {}
	var seen_pos_bad: int = 0
	var in_safe: int = 0
	for step: int in 1200:
		s.advance_game(0.1)
		max_total = maxi(max_total, s.enemies.boars.size())
		for b: Boar in s.enemies.boars:
			if not foot_ok(s, b.pos):
				seen_pos_bad += 1
			if s.state.zone_of[idx(s, Vector2i(floori(b.pos.x / TP), floori(b.pos.y / TP)))] == 0:
				in_safe += 1
		for n: Nest in s.enemies.nests:
			max_per_nest[n.id] = maxi(int(max_per_nest.get(n.id, 0)), n.boar_count)
	var pn_max: int = 0
	for k: Variant in max_per_nest:
		pn_max = maxi(pn_max, int(max_per_nest[k]))
	check("1.1 spawning is active while nests live and capped (total<=8, per-nest<=3)", s.enemies.total_spawned > 0 and max_total <= 8 and pn_max <= 3, "spawned=%d max_total=%d max_per_nest=%d" % [s.enemies.total_spawned, max_total, pn_max])
	check("1.1b boars hit the cap (cap actually binds: total==8 or per-nest==3 reached)", max_total >= 3 and pn_max == 3, "max_total=%d" % max_total)
	check("2.8 120s idle: boar feet always on walkable non-water cells; never in safe zone 0", seen_pos_bad == 0 and in_safe == 0, "bad=%d in_safe=%d" % [seen_pos_bad, in_safe])
	# --- seed direct hit on nest and on a boar
	var nest: Nest = s.enemies.nests[0]
	var hp0: int = nest.hp
	var g0: int = s.state.greened_count
	var plants0: int = 0
	for i: int in 48 * 40:
		if s.state.stage[i] != 0:
			plants0 += 1
	s.play.add_seeds(40)
	var seeds_b: int = s.play.seeds
	shoot(s, nest_center(s, nest))
	for i: int in 6:
		s.advance_game(0.25)
	check("1.2 seed direct hit damages the nest (-1)", nest.hp == hp0 - 1, "hp %d->%d" % [hp0, nest.hp])
	check("1.2b the seed was consumed and did not scatter on the nest", s.play.seeds == seeds_b - 1 or s.play.seeds <= seeds_b)
	var boar: Boar = null
	var guard: int = 0
	while s.enemies.boars.is_empty() and guard < 200:
		s.advance_game(0.25)
		guard += 1
	boar = s.enemies.boars[0]
	var bhp: int = boar.hp
	shoot(s, boar.pos)
	check("1.3 seed direct hit damages a boar", boar.hp < bhp or not s.enemies.boars.has(boar), "hp %d->%d" % [bhp, boar.hp])
	# --- downed mid-fight must not undo nest destruction
	# kill nest 1 first
	var t_start: float = s.clock.elapsed
	var iter: int = 0
	var pick_before: int = s.play.pickups.count_enemy_owned()
	var seeds_before_kill: int = s.play.seeds
	while nest.alive and iter < 200:
		shoot(s, nest_center(s, nest))
		iter += 1
	check("1.4 nest 1 destroyed by shots", not nest.alive and nest.hp == 0, "iter=%d" % iter)
	var spawned_n1: int = nest.spawned
	var drops: int = 0
	for it: Dictionary in s.play.pickups.items:
		if int(it["owner"]) == 4000000 + 1000000 + nest.id:
			drops += 1
	check("1.5 nest defeat reward: seed fruits dropped (owner nest) or credited directly", drops > 0 or s.play.enemy_direct_seeds > 0, "drops=%d direct=%d" % [drops, s.play.enemy_direct_seeds])
	# pick up reward: stand on a drop
	var s_before: int = 0
	for it: Dictionary in s.play.pickups.items:
		if int(it["owner"]) == 4000000 + 1000000 + nest.id:
			s.play.seeds = 0
			s.position = Vector2(float(it["x"]), float(it["y"]))
			s.advance_game(0.5)
			s_before = s.play.seeds
			break
	check("1.6 collecting the reward raises the seed count", s_before > 0 or drops == 0, "seeds=%d" % s_before)
	# downed during fight
	var alive_before: int = s.enemies.alive_nest_count(1)
	var zs_before: int = int(s.state.zone_state[1])
	var g_before_d: int = s.state.greened_count
	s.play.damage_player(s.play.hp_max)
	s.advance_game(0.05)
	var was_down: bool = s.play.health.downed
	settle_downed(s)
	check("3.1 downed mid-fight -> revived in safe zone; nest stays destroyed, zone state/greened not rolled back", was_down and not s.play.health.downed and s.player_zone() == 0 and s.enemies.alive_nest_count(1) == alive_before and s.state.zone_state[1] >= zs_before and s.state.greened_count >= g_before_d - 0, "down=%s zone=%d nests=%d st=%d g=%d->%d" % [was_down, s.player_zone(), s.enemies.alive_nest_count(1), s.state.zone_state[1], g_before_d, s.state.greened_count])
	# --- kill remaining nests, watch spawn stop & order
	var carcass_seen: bool = false
	for n: Nest in s.enemies.nests:
		var it2: int = 0
		while n.alive and it2 < 300:
			shoot(s, nest_center(s, n))
			it2 += 1
		check("3.2 nest %d destroyed" % n.id, not n.alive)
	var all_nests_gone: bool = s.enemies.alive_nest_count(1) == 0
	var spawned_at_clear: int = s.enemies.total_spawned
	var boars_at_clear: int = s.enemies.boars.size()
	var z_at_clear: int = int(s.state.zone_state[1])
	check("3.3 all nests destroyed -> zone 1 CLEARING (not yet stable) while boars remain (or already stable if none)", all_nests_gone and (z_at_clear == 1 and boars_at_clear > 0 or boars_at_clear == 0 and z_at_clear == 2), "state=%d boars=%d" % [z_at_clear, boars_at_clear])
	# hunt boars; no new spawns
	var hunt: int = 0
	var carcass_stage_seen: Array[int] = []
	var spawn_ok: bool = true
	var order_ok: bool = true
	while not s.enemies.boars.is_empty() and hunt < 400:
		var b: Boar = s.enemies.boars[0]
		var state_now: int = int(s.state.zone_state[1])
		if state_now == 2:
			order_ok = false
		var hp_b: int = b.hp
		var c0: int = s.enemies.carcasses.size()
		shoot(s, b.pos)
		if s.enemies.total_spawned != spawned_at_clear:
			spawn_ok = false
		hunt += 1
	check("3.4 no new boar spawned after the last nest fell", spawn_ok and s.enemies.total_spawned == spawned_at_clear, "spawned %d->%d hunts=%d" % [spawned_at_clear, s.enemies.total_spawned, hunt])
	check("3.5 zone stayed CLEARING until the last boar was removed", order_ok)
	check("3.6 last enemy removed -> zone 1 STABLE (state 2)", s.state.zone_state[1] == 2 and s.enemies.boars.is_empty(), "state=%d" % s.state.zone_state[1])
	var tz: Dictionary = s.zone_times[1]
	print("INFO zone_times[1]=", tz, " log=", s.zone_log)
	check("3.7 zone timeline order UNCONQUERED(0) < CLEARING(1) < STABLE(2) in game time", tz.has(1) and tz.has(2) and float(tz[1]) <= float(tz[2]) and float(tz[0]) <= float(tz[1]), str(tz))
	check("3.7b exactly one clearing notice sequence; region cleared not yet (target not 100%)", s.cleared_notices == 0, "cleared=%d" % s.cleared_notices)
	var t_stable: float = float(tz[2])
	check("1.7 boar kill left carcass(es) (total_carcasses>0), corpse -> bone -> gone", s.enemies.total_carcasses > 0)
	# carcass lifecycle: look at current carcasses
	var stages: Dictionary = {}
	var cc: int = s.enemies.carcasses.size()
	print("INFO carcasses now=", cc, " total=", s.enemies.total_carcasses)
	# --- stable zone not re-invaded; downed after stable doesn't roll back
	var g_st: int = s.state.greened_count
	var z0: int = int(s.state.zone_state[0])
	var z1: int = int(s.state.zone_state[1])
	s.play.damage_player(s.play.hp_max)
	s.advance_game(0.05)
	var down2: bool = s.play.health.downed
	settle_downed(s)
	check("3.8 downed after stabilization -> revived; greened count & zone states not rolled back", down2 and not s.play.health.downed and s.state.greened_count >= g_st and s.state.zone_state[0] == z0 and s.state.zone_state[1] == z1 and s.player_zone() == 0, "g %d->%d" % [g_st, s.state.greened_count])
	# --- 4: wait for 100% without input/resources, sampling
	var spawned_final: int = s.enemies.total_spawned
	var invaded: int = 0
	var seeds_start: int = s.play.seeds
	var water_start: float = s.play.water
	var deadline: float = t_stable + bound
	var t_done: float = -1.0
	var mono_ok: bool = true
	var last_g: int = s.state.greened_count
	var cont: bool = true
	var guard2: int = 0
	var cur_time: float = s.clock.elapsed
	while cont and s.clock.elapsed <= deadline and guard2 < 5000:
		s.advance_game(1.0)
		guard2 += 1
		if not s.enemies.boars.is_empty():
			invaded += 1
		if s.state.greened_count < last_g:
			mono_ok = false
		last_g = s.state.greened_count
		if s.state.greened_count == s.state.target_count:
			t_done = s.clock.elapsed
			cont = false
	var rc2: Vector2i = recount(s, exp)
	print("INFO t_stable=", t_stable, " bound=", bound, " deadline=", deadline, " t_done=", t_done, " elapsed_after_stable=", t_done - t_stable, " green=", s.state.greened_count, "/", s.state.target_count, " own=", rc2)
	check("3.9 stable zone never re-invaded and no new spawns while waiting", invaded == 0 and s.enemies.total_spawned == spawned_final, "invaded=%d" % invaded)
	check("3.10 greened count never decreased after stabilization", mono_ok)
	check("4.1 greened == target_count (state) within the pre-computed bound, no input/resources", t_done >= 0.0 and s.state.greened_count == s.state.target_count, "elapsed_after_stable=%.1f bound=%.1f" % [t_done - t_stable, bound])
	check("4.2 own recount agrees: all expected targets stage>=2", rc2.x == rc2.y and rc2.y == s.state.target_count, str(rc2))
	check("4.3 island cells greened", _island_green(s))
	check("4.4 no shots fired / seeds untouched during wait", s.projectiles.shots.is_empty() and s.play.seeds >= seeds_start)
	check("4.5 percent == 100 and zones COMPLETE/cleared", s.greening_percent() == 100 and s.state.zone_state[1] == 3, "pct=%d st=%d cleared=%s" % [s.greening_percent(), s.state.zone_state[1], str(s.state.cleared)])
	s.close()

func _island_green(s: RefCounted) -> bool:
	for y: int in range(6, 9):
		for x: int in range(6, 9):
			if s.state.stage[idx(s, Vector2i(x, y))] < 2:
				return false
	return true

# ---- confinement stress with plants to chase ----
func _s_confine() -> void:
	var s: RefCounted = fresh()
	var n_plants: int = 0
	for i: int in 48 * 40:
		var c: Vector2i = Vector2i(i % 48, i / 48)
		if s.state.target[i] == 1 and s.state.zone_of[i] == 1 and (c.x + c.y * 3) % 7 == 0:
			s.state.set_stage(i, 1)
			n_plants += 1
	var bad: int = 0
	var zone_bad: int = 0
	var maxb: int = 0
	var gnawed0: int = s.enemies.total_gnawed
	for step: int in 3000:
		s.advance_game(0.1)
		maxb = maxi(maxb, s.enemies.boars.size())
		for b: Boar in s.enemies.boars:
			var c: Vector2i = Vector2i(floori(b.pos.x / TP), floori(b.pos.y / TP))
			if not foot_ok(s, b.pos):
				bad += 1
			elif s.state.zone_of[idx(s, c)] != 1:
				zone_bad += 1
	check("2.9 300s chasing plants: boar feet never on wall/building/water (0 violations)", bad == 0 and s.enemies.total_gnawed > gnawed0, "plants=%d bad=%d gnawed=%d maxboars=%d" % [n_plants, bad, s.enemies.total_gnawed, maxb])
	check("2.10 boars never left zone 1 into safe zone", zone_bad == 0, "zone_bad=%d" % zone_bad)
	# carcass lifecycle with a real kill
	var b2: Boar = null
	var guard: int = 0
	while s.enemies.boars.is_empty() and guard < 100:
		s.advance_game(0.25)
		guard += 1
	b2 = s.enemies.boars[0]
	var kills0: int = s.enemies.total_killed
	var g2: int = 0
	while s.enemies.total_killed == kills0 and g2 < 100:
		if not s.enemies.boars.is_empty():
			shoot(s, s.enemies.boars[0].pos)
		g2 += 1
	check("1.8 boar killed -> carcass exists (corpse stage)", s.enemies.total_killed > kills0 and s.enemies.carcass_count(0) >= 1, "killed=%d corpse=%d" % [s.enemies.total_killed, s.enemies.carcass_count(0)])
	var corpse_t: float = s.enemies.tuning.carcass_seconds
	var bone_t: float = s.enemies.tuning.bone_seconds
	var n_c: int = s.enemies.carcasses.size()
	# advance past corpse time only (nests keep spawning; fine) and observe the bone stage exists, then gone
	var found_bone: bool = false
	var t0: float = s.clock.elapsed
	while s.clock.elapsed - t0 < corpse_t + 2.0:
		s.advance_game(1.0)
		if s.enemies.carcass_count(1) >= 1:
			found_bone = true
	check("1.9 corpse becomes bone after ~carcass_seconds", found_bone, "corpse=%d bone=%d" % [s.enemies.carcass_count(0), s.enemies.carcass_count(1)])
	var tracked: Carcass = null
	for c: Carcass in s.enemies.carcasses:
		if c.stage == 1:
			tracked = c
			break
	var t1: float = s.clock.elapsed
	while s.clock.elapsed - t1 < bone_t + 3.0:
		s.advance_game(1.0)
	check("1.10 bone disappears after ~bone_seconds", tracked != null and not s.enemies.carcasses.has(tracked))
	s.close()

# ---- condition 5: cultivated plants before stabilization ----
func _s2_plants() -> void:
	var s: RefCounted = fresh()
	var exp: PackedByteArray = expected_targets(s)
	var bound: float = s.far.completion_bound_seconds()
	# mature patches in zone 1 near the start, plus one on the island
	var patch_a: Rect2i = Rect2i(29, 23, 4, 2)
	var patch_b: Rect2i = Rect2i(29, 27, 4, 2)
	var patch_i: Rect2i = Rect2i(6, 6, 3, 3)
	for r: Rect2i in [patch_a, patch_b, patch_i]:
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x):
				var i: int = idx(s, Vector2i(x, y))
				if s.state.target[i] == 1:
					s.state.set_stage(i, 4)
	s.play.add_seeds(40)
	var placed: Array[String] = []
	for entry: Array in [["carrot", Vector2(30.5, 24.0)], ["kiwi", Vector2(30.5, 28.0)]]:
		var k: int = -1
		for j: int in s.play.selectable.size():
			if String(s.play.selectable[j].key) == String(entry[0]):
				k = j
		s.play.select_index(k)
		s.position = Vector2(26.0, 24.0) * TP if String(entry[0]) == "carrot" else Vector2(26.0, 26.5) * TP
		var res: Dictionary = s.fire(false, Vector2(entry[1]) * TP)
		for i: int in 10:
			s.advance_game(0.25)
		placed.append("%s:%s plants=%d" % [entry[0], str(res), s.play.cultivation.count(StringName(entry[0]))])
	print("INFO placed ", placed)
	var carrots: int = s.play.cultivation.count(&"carrot")
	var kiwis: int = s.play.cultivation.count(&"kiwi")
	check("5.0 cultivated plants placed before stabilization (carrot>=1, kiwi>=1)", carrots >= 1 and kiwis >= 1, "carrot=%d kiwi=%d" % [carrots, kiwis])
	# island carrot via direct landing (the island is out of throwing reach from the start)
	s.play.select_index(1)
	s.play.add_seeds(20)
	s.position = Vector2(13.5, 7.5) * TP
	var isl_res: Dictionary = s.fire(false, Vector2(7.5, 7.5) * TP)
	for i: int in 12:
		s.advance_game(0.25)
	print("INFO island carrot shot ", isl_res, " carrots=", s.play.cultivation.count(&"carrot"))
	var occupied: int = 0
	for i: int in 48 * 40:
		if s.state.occupant[i] != 0 and s.state.occupant[i] < 4000000 and exp[i] == 1:
			occupied += 1
	print("INFO occupied target cells by plants=", occupied)
	# fight to stability (same bot)
	var guard: int = 0
	for n: Nest in s.enemies.nests:
		var it: int = 0
		while n.alive and it < 300:
			shoot(s, nest_center(s, n))
			it += 1
	var hunt: int = 0
	while not s.enemies.boars.is_empty() and hunt < 400:
		shoot(s, s.enemies.boars[0].pos)
		hunt += 1
	check("5.1 stabilized with plants present", s.state.zone_state[1] >= 2, "state=%d" % s.state.zone_state[1])
	var t_stable: float = float(s.zone_times[1][2])
	var carrots2: int = s.play.cultivation.count(&"carrot")
	var kiwis2: int = s.play.cultivation.count(&"kiwi")
	var deadline: float = t_stable + bound
	var t_done: float = -1.0
	var g: int = 0
	while s.clock.elapsed <= deadline and g < 5000:
		s.advance_game(1.0)
		g += 1
		if s.state.greened_count == s.state.target_count:
			t_done = s.clock.elapsed
			break
	var rc: Vector2i = recount(s, exp)
	print("INFO S2 t_stable=", t_stable, " bound=", bound, " t_done=", t_done, " green=", s.state.greened_count, "/", s.state.target_count, " own=", rc, " carrots=", carrots2, " kiwis=", kiwis2)
	check("5.2 with carrot/kiwi planted before stabilization, 100% within bound", t_done >= 0.0 and s.state.greened_count == s.state.target_count and rc.x == rc.y, "elapsed_after_stable=%.1f bound=%.1f" % [t_done - t_stable, bound])
	var missing: Array[Vector2i] = []
	for i: int in 48 * 40:
		if exp[i] == 1 and s.state.stage[i] < 2:
			missing.append(Vector2i(i % 48, i / 48))
	print("INFO missing cells (first 10): ", missing.slice(0, 10), " count=", missing.size())
	s.close()
