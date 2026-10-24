extends "res://scripts/content_pack/enemies/base.gd"
## E19 トンビ。飛行。状態: circle / mark / lock / dive / ground / climb
## 当たるのは ground と climb の間だけ。影は mark の間 狙った相手に追従し、lock で固定、dive の終わりに固定点へ急降下する。
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")
const ORBIT_PX: float = 30.0
const DIVE_S: float = 0.1

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "circle"
	e.ang = (Vector2(e.pos) - Vector2(e.home)).angle() if e.pos.distance_to(e.home) > 1.0 else 0.0
	e.dir_sign = 1.0
	e.shadow = e.pos
	e.cd_until = 0.0
	e.ttype = ""
	e.tid = 0

static func hittable(_s: RefCounted, e: Dictionary) -> bool:
	return e.state == "ground" or e.state == "climb"

static func _stable(s: RefCounted, p: Vector2) -> bool:
	var c: Vector2i = Grid.cell_of_pos(p)
	return s.host.is_stable_cell(c) or not s.host.in_bounds(c)

static func _find(s: RefCounted, e: Dictionary) -> Dictionary:
	for t: Dictionary in s.all_targets():
		if str(t.type) == str(e.ttype) and int(t.id) == int(e.tid):
			return t
	return {}

## 縄張り(家から)に入った相手。主人公優先、いなければおたすけ植物。安定地域の上空にいる相手は狙わない。
static func _pick(s: RefCounted, e: Dictionary) -> Dictionary:
	var lim: float = s.territory_px(e)
	var h: Dictionary = s.hero_t()
	if not h.is_empty() and Vector2(e.home).distance_to(h.pos) <= lim and not _stable(s, h.pos):
		return h
	var best: Dictionary = {}
	var bd: float = 1e18
	for t: Dictionary in s.all_targets():
		if t.type == "helper":
			var d: float = Vector2(e.home).distance_to(t.pos)
			if d <= lim and d < bd and not _stable(s, t.pos):
				best = t
				bd = d
	return best

static func _orbit(s: RefCounted, e: Dictionary, dt: float) -> void:
	var w: float = s.speed_px(e) / ORBIT_PX
	var na: float = float(e.ang) + float(e.dir_sign) * w * dt
	var goal: Vector2 = Vector2(e.home) + Vector2.from_angle(na) * ORBIT_PX
	if _stable(s, goal):
		e.dir_sign = -float(e.dir_sign)
		return
	e.ang = na
	var d: float = e.pos.distance_to(goal)
	var step: float = minf(s.speed_px(e) * 1.5 * dt, d)
	if d > 1e-6:
		e.pos = e.pos + (goal - e.pos) / d * step
		e.last_cell = Grid.cell_of_pos(e.pos)

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	match str(e.state):
		"circle":
			_orbit(s, e, dt)
			if s.due(float(e.cd_until)):
				var t: Dictionary = _pick(s, e)
				if not t.is_empty():
					e.ttype = str(t.type)
					e.tid = int(t.id)
					e.shadow = t.pos
					s.set_state(e, "mark", s.pf(e, "mark_s"))
					s.fx(ev, "kite_shadow", e.shadow, e, {"locked": false})
		"mark":
			_orbit(s, e, dt)
			var t2: Dictionary = _find(s, e)
			if t2.is_empty() or _stable(s, t2.pos):
				e.state = "circle"
				return
			e.shadow = t2.pos
			if s.due(float(e.until)):
				s.set_state(e, "lock", s.pf(e, "lock_s"))
				s.fx(ev, "kite_shadow", e.shadow, e, {"locked": true})
		"lock":
			_orbit(s, e, dt)
			if s.due(float(e.until)):
				s.set_state(e, "dive", DIVE_S)
		"dive":
			if s.due(float(e.until)):
				e.pos = e.shadow
				e.last_cell = Grid.cell_of_pos(e.pos)
				for t3: Dictionary in s.all_targets():
					if e.shadow.distance_to(t3.pos) <= s.pm(e, "dive_radius_m"):
						s.dmg_target(e, t3, s.pf(e, "dive_damage"), ev)
				s.fx(ev, "dive_hit", e.shadow, e, {"radius": s.pm(e, "dive_radius_m")})
				e.cd_until = s.time + s.pf(e, "cooldown_s")
				s.set_state(e, "ground", s.pf(e, "ground_s"))
		"ground":
			if s.due(float(e.until)):
				s.set_state(e, "climb", s.pf(e, "climb_s"))
		"climb":
			if s.due(float(e.until)):
				e.ang = (Vector2(e.pos) - Vector2(e.home)).angle() if e.pos.distance_to(e.home) > 1.0 else 0.0
				e.state = "circle"

static func on_flee(_s: RefCounted, _e: Dictionary) -> void:
	pass
