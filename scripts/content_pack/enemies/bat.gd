extends "res://scripts/content_pack/enemies/base.gd"
## E27 コウモリ(1匹ずつの個体。同じ group_id で一つの群れ)。状態: roost(ぶら下がり、当たる) / swarm(飛行、当たらない) / dive(急降下、当たる) / low(噛んだ後0.5秒、当たる) / return(ねぐらへ、当たらない)
## 1匹でも攻撃が当たる(撃破含む)、または主人公が3m以内に来ると、ぶら下がっている群れ全員が飛び立つ。2匹以下の群れは乱れ飛ばずすぐ戻る。
## 飛行時間は昼12秒・夜24秒。2秒ごとに群れの代表(最小ID)が1匹を急降下させる。ヒカリゴケの範囲では急降下しない。
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")
const STATES: Array = ["roost", "swarm", "dive", "low", "return"]

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "roost"
	e.roost = e.pos
	e.fly_until = 0.0
	e.next_dive = 0.0
	e.dive_until = 0.0
	e.ang = fmod(float(e.id) * 1.3, TAU)
	e.bit = false

static func hittable(_s: RefCounted, e: Dictionary) -> bool:
	return e.state == "roost" or e.state == "dive" or e.state == "low"

static func validate(_s: RefCounted, e: Dictionary) -> bool:
	return STATES.has(str(e.state)) and typeof(e.roost) == TYPE_VECTOR2

static func members(s: RefCounted, e: Dictionary) -> Array:
	var out: Array = []
	for m: Dictionary in s.enemies:
		if m.alive and m.kind == "bat_flock" and int(m.group_id) == int(e.group_id):
			out.append(m)
	if out.is_empty():
		out.append(e)
	return out

static func _wake(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	var mem: Array = members(s, e)
	if str(e.state) != "roost":
		return
	var small: bool = mem.size() <= int(s.pf(e, "last_flock"))
	var secs: float = s.pf(e, "fly_day_s") if bool(s.host.is_day()) else s.pf(e, "fly_night_s")
	s.fx(ev, "bat_wake", e.pos, e, {"count": mem.size()})
	for m: Dictionary in mem:
		if m.state != "roost":
			continue
		if small:
			s.set_state(m, "return", s.pf(m, "return_min_s"))   # 2匹以下は乱れ飛ばず、すぐねぐらへ戻る
		else:
			s.set_state(m, "swarm", secs)
			m.fly_until = s.time + secs
			m.next_dive = s.time + s.pf(m, "dive_interval_s")

static func on_hit(s: RefCounted, e: Dictionary, _k: String, _f: Variant, _d: float, ev: Array[Dictionary]) -> void:
	_wake(s, e, ev)

## 眠っている1匹が撃破されたら、残りの群れが飛び立つ
static func on_defeat(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	if str(e.state) != "roost":
		return
	var rest: Array = members(s, e)
	for m: Dictionary in rest:
		if m.alive and m.state == "roost":
			_wake(s, m, ev)
			return

static func _fly(s: RefCounted, e: Dictionary, goal: Vector2, speed: float, dt: float) -> void:
	var d: float = e.pos.distance_to(goal)
	var step: float = minf(speed * dt, d)
	if d > 1e-6:
		var np: Vector2 = e.pos + (goal - e.pos) / d * step
		var c: Vector2i = Grid.cell_of_pos(np)
		if s.host.in_bounds(c) and not s.host.is_stable_cell(c):   # 安定地域の上空には入らない
			e.pos = np
			e.last_cell = c

static func _in_moss(s: RefCounted, p: Vector2) -> bool:
	return bool(s.crops.moss_covers_cell(Grid.cell_of_pos(p)))

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	var h: Dictionary = s.hero_t()
	match str(e.state):
		"roost":
			if not h.is_empty() and e.pos.distance_to(h.pos) <= s.pm(e, "wake_m"):
				_wake(s, e, ev)
		"swarm":
			var mem: Array = members(s, e)
			if mem.size() <= int(s.pf(e, "last_flock")) or s.due(float(e.fly_until)):
				s.set_state(e, "return", 0.0)
				return
			var center: Vector2 = h.pos if not h.is_empty() else Vector2(e.roost)
			e.ang = float(e.ang) + 1.8 * dt
			var goal: Vector2 = center + Vector2.from_angle(float(e.ang)) * s.pm(e, "orbit_m")
			_fly(s, e, goal, s.speed_px(e), dt)
			# 群れの代表(最小ID)が、2秒ごとに1匹を急降下させる
			if int((mem[0] as Dictionary).id) == int(e.id) and s.due(float(e.next_dive)):
				e.next_dive = s.time + s.pf(e, "dive_interval_s")
				for m2: Dictionary in mem:
					m2.next_dive = e.next_dive
				var cand: Array = []
				for m: Dictionary in mem:
					if m.state == "swarm":
						cand.append(m)
				if not h.is_empty() and not cand.is_empty() and not _in_moss(s, h.pos):
					var pick: Dictionary = cand[s.rng.randi_range(0, cand.size() - 1)]
					if not _in_moss(s, pick.pos):
						s.set_state(pick, "dive", s.pf(pick, "dive_max_s"))
						pick.bit = false
		"dive":
			var t: Dictionary = h if not h.is_empty() else {}
			if t.is_empty() or s.due(float(e.until)):
				e.state = "swarm"
				return
			_fly(s, e, t.pos, s.pm(e, "dive_mps"), dt)
			if s.in_reach(e, t):
				s.dmg_target(e, t, s.pf(e, "dive_damage"), ev)
				s.fx(ev, "bat_bite", e.pos, e)
				s.set_state(e, "low", s.pf(e, "low_s"))   # 噛んだ後0.5秒は低空にいて当たる
		"low":
			if s.due(float(e.until)):
				e.state = "swarm"
		"return":
			_fly(s, e, e.roost, s.speed_px(e), dt)
			if e.pos.distance_to(e.roost) <= 1.0 and s.due(float(e.until)):
				e.pos = e.roost
				e.state = "roost"
				e.last_cell = Grid.cell_of_pos(e.pos)

static func on_flee(_s: RefCounted, _e: Dictionary) -> void:
	pass
