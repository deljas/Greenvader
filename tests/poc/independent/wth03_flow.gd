extends SceneTree
## WTH-03 independent flow: own walking/shooting/helper-placement procedure on town_01 (no debug refill, no state writes): nests -> boars -> stable ->
## no input -> strict 100 % within far.completion_bound_seconds(). Own bot (BFS + walk + fire), not the integration bot.
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/weather/03/independent/"
const DT: float = 0.1
var s: RefCounted
var st: WorldState
var W: int
var H: int
var clear: PackedByteArray = PackedByteArray()
var lines: PackedStringArray = PackedStringArray()
var downs: int = 0
var min_seeds: int = 999
var min_water: float = 999.0
var min_hp: int = 99
var fire_at: float = 0.0
var shots: int = 0
var restocks: int = 0
var walked: float = 0.0
var limit_t: float = 4000.0
var trace: Array = []
var next_trace: float = 0.0

func say(t: String) -> void:
	lines.append(t)
	print(t)

func _init() -> void:
	_run.call_deferred()

func cpx(c: Vector2i) -> Vector2:
	return Coords.cell_center_logic(c)

func frame(dir: Vector2 = Vector2.ZERO) -> void:
	var p: Vector2 = s.position
	s.walk(dir, DT)
	walked += s.position.distance_to(p)
	s.advance_game(DT)
	min_seeds = mini(min_seeds, s.play.seeds)
	min_water = minf(min_water, s.play.water)
	min_hp = mini(min_hp, s.play.hp)
	if s.play.health.downed and not _was_down:
		downs += 1
	_was_down = s.play.health.downed
	if s.clock.elapsed >= next_trace:
		next_trace += 30.0
		trace.append([snappedf(s.clock.elapsed, 0.1), s.play.seeds, snappedf(s.play.water, 0.1), s.play.hp, st.greened_count, s.enemies.boars.size(), s.enemies.alive_nest_count(-1), downs])
var _was_down: bool = false

func cell_now() -> Vector2i:
	return Coords.logic_to_cell(s.position)

func ok_cell(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H and clear[c.y * W + c.x] == 1

func field(goal: Vector2i) -> PackedInt32Array:
	var d: PackedInt32Array = PackedInt32Array()
	d.resize(W * H)
	d.fill(-1)
	var g: Vector2i = goal
	if not ok_cell(g):
		var best: int = 1 << 30
		for r: int in range(0, 10):
			for dy: int in range(-r, r + 1):
				for dx: int in range(-r, r + 1):
					var n: Vector2i = goal + Vector2i(dx, dy)
					if ok_cell(n) and maxi(absi(dx), absi(dy)) == r and best == 1 << 30:
						best = r
						g = n
	var q: PackedInt32Array = PackedInt32Array([g.y * W + g.x])
	d[g.y * W + g.x] = 0
	var h: int = 0
	while h < q.size():
		var i: int = q[h]
		h += 1
		for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = i % W + o.x
			var ny: int = i / W + o.y
			if nx < 0 or ny < 0 or nx >= W or ny >= H: continue
			var j: int = ny * W + nx
			if clear[j] == 0 or d[j] != -1: continue
			d[j] = d[i] + 1
			q.append(j)
	return d

func step(f: PackedInt32Array, goal: Vector2i) -> void:
	var c: Vector2i = cell_now()
	var here: int = f[c.y * W + c.x] if c.x >= 0 and c.y >= 0 and c.x < W and c.y < H else -1
	var tgt: Vector2 = cpx(goal)
	var bd: int = here if here > 0 else (1 << 30)
	for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + o
		if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H: continue
		var v: int = f[n.y * W + n.x]
		if v >= 0 and v < bd:
			bd = v
			tgt = cpx(n)
	var g: Vector2 = tgt - s.position
	if g.length() < 0.2:
		frame()
		return
	var k: float = clampf(g.length() / (Config.walk_speed_px() * DT), 0.15, 1.0)
	frame(Coords.ground_dir_to_screen(g.normalized()) * k)

func shoot(target: Vector2) -> bool:
	if s.clock.elapsed < fire_at: return false
	var r: Dictionary = s.fire(false, target)
	if bool(r["ok"]):
		fire_at = s.clock.elapsed + 0.25
		shots += 1
		return true
	return false

func fight() -> bool:
	if s.play.health.downed or not s.play.can_fire_seed(): return false
	var best: Boar = null
	var bd: float = 40.0
	for b: Boar in s.enemies.boars:
		var d: float = b.pos.distance_to(s.position)
		if d <= bd and not s.shot_blocked(s.position, b.pos):
			bd = d
			best = b
	if best == null: return false
	shoot(best.pos)
	frame()
	return true

func go(goal: Vector2i, timeout: float, arrive: float) -> bool:
	var f: PackedInt32Array = field(goal)
	var t0: float = s.clock.elapsed
	while s.clock.elapsed - t0 < timeout and s.clock.elapsed < limit_t:
		if s.play.health.downed:
			frame()
			continue
		if fight(): continue
		if s.position.distance_to(cpx(goal)) <= arrive: return true
		step(f, goal)
	return s.position.distance_to(cpx(goal)) <= arrive

func idle(sec: float) -> void:
	var left: float = sec
	while left > 0.0:
		if fight():
			left -= DT
			continue
		frame()
		left -= DT

func nearest_source() -> Vector2i:
	var best: Vector2i = Vector2i.ZERO
	var bd: float = 1.0e12
	for v: Variant in s.combat_setup.get("seed_sources", []):
		var c: Vector2i = Vector2i(int(v[0]), int(v[1]))
		var d: float = cpx(c).distance_to(s.position)
		if d < bd:
			bd = d
			best = c
	return best

func restock(target: int) -> void:
	restocks += 1
	var src: Vector2i = nearest_source()
	say("t=%.1f restock #%d seeds=%d -> source %s" % [s.clock.elapsed, restocks, s.play.seeds, src])
	go(src, 200.0, 2.0)
	var t0: float = s.clock.elapsed
	while s.play.seeds < target and s.clock.elapsed - t0 < 300.0:
		idle(1.0)
	say("t=%.1f restock done seeds=%d (waited %.0fs)" % [s.clock.elapsed, s.play.seeds, s.clock.elapsed - t0])

func kill_nest(n: Nest) -> void:
	var center: Vector2 = n.center_px(Config.TILE_PX)
	var skip: Array[Vector2i] = []
	var t0: float = s.clock.elapsed
	var tries: int = 0
	while n.alive and tries < 6 and s.clock.elapsed - t0 < 400.0:
		tries += 1
		if s.play.seeds < 8: restock(38)
		var fp: PackedInt32Array = field(cell_now())
		var spot: Vector2i = Vector2i(-1, -1)
		var bd: int = 1 << 30
		for y: int in H:
			for x: int in W:
				var v: int = fp[y * W + x]
				if v < 0 or v >= bd: continue
				var c: Vector2i = Vector2i(x, y)
				var dp: float = cpx(c).distance_to(center)
				if dp < 4.0 * Config.TILE_PX + 8.0 or dp > 8.0 * Config.TILE_PX or skip.has(c): continue
				if s.shot_blocked(cpx(c), center): continue
				bd = v
				spot = c
		if spot.x < 0:
			say("nest %d: no spot" % n.id)
			return
		if not go(spot, 150.0, 2.5):
			skip.append(spot)
			continue
		var hp0: int = n.hp
		var sh: int = 0
		while n.alive and s.clock.elapsed - t0 < 400.0:
			if s.play.health.downed:
				frame()
				continue
			if fight(): continue
			if s.play.seeds < 1:
				restock(38)
				break
			if s.position.distance_to(cpx(spot)) > 6.0: break
			if shoot(center): sh += 1
			frame()
			if sh >= 30 and n.hp >= hp0:
				skip.append(spot)
				break


var placed: Array = []
var helper_log: Array = []
func try_place_helpers() -> void:
	var hp: RefCounted = s.helpers
	for kind: String in ["gatlinger", "sprinkler", "army"]:
		var cost: int = int(hp.kind_def(kind)["cost"])
		if hp.seeds < cost or hp.total_count() >= hp.max_helpers: continue
		if placed.has(kind) and kind != "gatlinger": continue
		var here: Vector2i = cell_now()
		var fp: PackedInt32Array = field(here)
		var best: Vector2i = Vector2i(-9999, -9999)
		var bd: int = 1 << 30
		for oy: int in range(here.y - 25, here.y + 25):
			for ox: int in range(here.x - 25, here.x + 25):
				var o: Vector2i = Vector2i(ox, oy)
				var ctr: Vector2 = hp.block_center_px(o)
				if not bool(hp.evaluate(kind, o, ctr)["ok"]): continue
				var cc: Vector2i = Coords.logic_to_cell(ctr)
				if not ok_cell(cc) or fp[cc.y * W + cc.x] < 0: continue
				if fp[cc.y * W + cc.x] < bd:
					bd = fp[cc.y * W + cc.x]
					best = o
		if best.x == -9999:
			say("t=%.1f helper %s: no mature free block reachable" % [s.clock.elapsed, kind])
			continue
		var ctr2: Vector2 = hp.block_center_px(best)
		go(Coords.logic_to_cell(ctr2), 120.0, 14.0)
		while s.helper_mode != -1: s.cycle_helper_mode()
		var guard: int = 0
		while s.helper_active_kind() != kind and guard < 6:
			s.cycle_helper_mode(); guard += 1
		s.set_aim(ctr2)
		var r: Dictionary = s.place_helper(ctr2)
		s.end_helper_mode()
		s.clear_aim()
		say("t=%.1f place %s at %s -> ok=%s code=%s seeds_left=%d" % [s.clock.elapsed, kind, best, r["ok"], r["code"], hp.seeds])
		if bool(r["ok"]): placed.append(kind)

func hunt() -> void:
	var t0: float = s.clock.elapsed
	while not s.enemies.boars.is_empty() and s.clock.elapsed - t0 < 600.0:
		if s.play.health.downed:
			frame()
			continue
		if s.play.seeds < 6:
			restock(20)
			continue
		if fight(): continue
		var fp: PackedInt32Array = field(cell_now())
		var tb: Boar = null
		var bd: int = 1 << 30
		for b: Boar in s.enemies.boars:
			var bc: Vector2i = Coords.logic_to_cell(b.pos)
			var v: int = fp[bc.y * W + bc.x] if ok_cell(bc) else -1
			if v >= 0 and v < bd:
				bd = v
				tb = b
		if tb == null:
			tb = s.enemies.boars[0]
		var goal: Vector2i = Coords.logic_to_cell(tb.pos)
		var f: PackedInt32Array = field(goal)
		for i: int in 8:
			if fight(): break
			step(f, goal)

func _run() -> void:
	var size: Vector2i = Session.town_size()
	s = Session.new(size.x, size.y)
	s.paving = Session.paving_from(s.env_tuning)
	s.load_combat(Session.TOWN_SETUP)
	st = s.state
	W = st.width
	H = st.height
	clear.resize(W * H)
	for y: int in H:
		for x: int in W:
			clear[y * W + x] = 1 if Walker.is_clear(st, Config.TILE_PX, cpx(Vector2i(x, y)), Config.player_half_px()) else 0
	say("start: seeds=%d water=%.0f hp=%d greened=%d/%d nests=%d boars=%d bound0=%.1f debug_refill=%s" % [s.play.seeds, s.play.water, s.play.hp, st.greened_count, st.target_count, s.enemies.alive_nest_count(-1), s.enemies.boars.size(), s.far.completion_bound_seconds(), s.debug_refill_enabled])
	var guard: int = 0
	while s.enemies.alive_nest_count(-1) > 0 and guard < 30 and s.clock.elapsed < limit_t:
		guard += 1
		var best: Nest = null
		var bd: float = 1.0e12
		for n: Nest in s.enemies.nests:
			if n.alive and n.center_px(Config.TILE_PX).distance_to(s.position) < bd:
				bd = n.center_px(Config.TILE_PX).distance_to(s.position)
				best = n
		kill_nest(best)
		say("t=%.1f nest %d alive=%s seeds=%d downs=%d helperseeds=%d" % [s.clock.elapsed, best.id, best.alive, s.play.seeds, downs, s.helpers.seeds])
		try_place_helpers()
	var t_nests: float = s.clock.elapsed
	try_place_helpers()
	hunt()
	try_place_helpers()
	var g2: int = 0
	while st.zone_state[1] < WorldState.ZONE_STABLE and g2 < 100:
		g2 += 1
		idle(2.0)
	var t_stable: float = s.clock.elapsed
	var spawned: int = s.enemies.total_spawned
	var bound: float = s.far.completion_bound_seconds()
	say("RESULT stable: nests_done=%.1fs stable_t=%.1fs zone1=%d boars=%d bound=%.1fs greened=%d/%d pct=%d" % [t_nests, t_stable, st.zone_state[1], s.enemies.boars.size(), bound, st.greened_count, st.target_count, s.greening_percent()])
	say("RESULT helpers: placed=%s plants_now=%d helper_seeds=%d collected=%d dropped=%d nest_rewards=%d lost=%d seeded=%d" % [str(placed), s.helpers.plants.size(), s.helpers.seeds, s.helpers.collected_total, s.helpers.dropped_total, s.helpers.nest_rewards_total, s.helpers.lost_total, s.helpers.seeded_total])
	say("RESULT resources: shots=%d restocks=%d min_seeds=%d min_water=%.0f min_hp=%d downs=%d walked_px=%.0f seeds_now=%d water_now=%.0f" % [shots, restocks, min_seeds, min_water, min_hp, downs, walked, s.play.seeds, s.play.water])
	# no input
	var reached: float = -1.0
	var invaded: bool = false
	while s.clock.elapsed <= t_stable + bound + 0.5:
		s.advance_game(0.25)
		if not s.enemies.boars.is_empty() or s.enemies.total_spawned != spawned: invaded = true
		if st.greened_count == st.target_count:
			reached = s.clock.elapsed
			break
	var targets: int = 0
	var not_green: int = 0
	for i: int in st.tile_count():
		if st.target[i] != 0:
			targets += 1
			if st.stage[i] < WorldState.GREENED_MIN_STAGE: not_green += 1
	var pass_all: bool = s.enemies.alive_nest_count(-1) == 0 and st.zone_state[1] >= WorldState.ZONE_STABLE and reached >= 0.0 and not_green == 0 and targets == st.target_count and s.greening_percent() == 100 and not invaded and s.debug_refill_enabled == false
	say("RESULT hundred: reached_after=%.1fs bound=%.1fs targets=%d not_green=%d pct=%d invaded=%s" % [reached - t_stable, bound, targets, not_green, s.greening_percent(), invaded])
	say("%s flow.normal_play_stable_then_exact_100" % ("PASS" if pass_all else "FAIL"))
	say("TRACE [t,seeds,water,hp,greened,boars,nests,downs]: " + JSON.stringify(trace))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var f: FileAccess = FileAccess.open(OUT + "flow.log", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	s.close()
	quit(0 if pass_all else 1)
