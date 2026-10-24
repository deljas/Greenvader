extends "res://scripts/content_pack/enemies/base.gd"
## E08 ノラオオカミ(群れ3匹)。状態: rest / howl / circle / lunge / recover
## lunge は lunge_phase が "windup" → "dash"。囲みの基準角 circle_base は群れ全員に同じ値を持たせる。

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "rest"
	e.lunge_at = 0.0
	e.lunge_phase = "windup"
	e.lunge_dir = Vector2.RIGHT
	e.circle_base = 0.0
	e.bite_at = 0.0

static func _members(s: RefCounted, e: Dictionary) -> Array:
	var out: Array = []
	for m: Dictionary in s.enemies:
		if m.alive and m.kind == "stray_wolf" and int(m.pack_id) == int(e.pack_id):
			out.append(m)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	return out

static func _alert(s: RefCounted, e: Dictionary, hero_pos: Vector2, ev: Array[Dictionary]) -> void:
	var base: float = (e.pos - hero_pos).angle()
	for m: Dictionary in _members(s, e):
		m.circle_base = base
		if m.state == "rest":
			s.set_state(m, "howl", s.pf(m, "howl_s"))
	s.fx(ev, "howl", e.pos, e)

## 主人公(いなければ最も近いおたすけ植物)。12m以内。
static func _prey(s: RefCounted, e: Dictionary) -> Dictionary:
	return s.pick_target(e, s.pm(e, "hunt_m"), s.pm(e, "hunt_m"), false)

static func _behind(s: RefCounted, e: Dictionary, t: Dictionary) -> bool:
	var aim: Vector2 = t.aim
	if aim.length() < 1e-6:
		return true
	var to: Vector2 = e.pos - t.pos
	return absf(rad_to_deg(aim.angle_to(to))) > s.pf(e, "front_half_deg")

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	match str(e.state):
		"rest":
			var h: Dictionary = s.hero_t()
			if not h.is_empty() and e.pos.distance_to(h.pos) <= s.pm(e, "sight_m") and s.host.line_clear(e.pos, h.pos):
				_alert(s, e, h.pos, ev)
				return
			s.wander(e, dt, ev, s.speed_px(e) * 0.4, s.pm(e, "wander_m"))
		"howl":
			if s.due(float(e.until)):
				e.state = "circle"
		"circle", "recover":
			var t: Dictionary = _prey(s, e)
			if t.is_empty():
				e.state = "rest"
				return
			var mem: Array = _members(s, e)
			if mem.size() <= 1:
				_last_one(s, e, t, dt, ev)
				return
			if e.state == "recover" and s.due(float(e.until)):
				e.state = "circle"
			var idx: int = 0
			for i: int in range(mem.size()):
				if int(mem[i].id) == int(e.id):
					idx = i
			var ang: float = float(e.circle_base) + TAU * float(idx) / float(mem.size())
			var slot: Vector2 = t.pos + Vector2.from_angle(ang) * s.pm(e, "circle_m")
			if e.state == "circle" and _behind(s, e, t) and e.pos.distance_to(t.pos) <= s.pm(e, "circle_m") * 1.5 and s.due(float(e.lunge_at)):
				s.set_state(e, "lunge", s.pf(e, "lunge_windup_s"))
				e.lunge_phase = "windup"
				s.fx(ev, "windup", e.pos, e)
				return
			s.walk_to(e, slot, s.speed_px(e), dt, ev, 3.0)
			e.face = (t.pos - e.pos).normalized() if e.pos.distance_to(t.pos) > 0.1 else e.face
		"lunge":
			var t2: Dictionary = _prey(s, e)
			if t2.is_empty():
				e.state = "rest"
				return
			if e.lunge_phase == "windup":
				e.face = (t2.pos - e.pos).normalized() if e.pos.distance_to(t2.pos) > 0.1 else e.face
				if s.due(float(e.until)):
					e.lunge_phase = "dash"
					e.lunge_dir = Vector2(e.face)
					e.until = s.time + s.pf(e, "lunge_s")
			else:
				s.step_move(e, e.lunge_dir, s.pm(e, "lunge_mps"), dt, ev, {"straight": true})
				if not bool(e.alive):
					return
				if e.pos.distance_to(t2.pos) <= s.radius_px(e) + 4.0 + 2.0:
					s.dmg_target(e, t2, s.pf(e, "bite_damage"), ev)
					e.lunge_at = s.time + 1.0
					s.set_state(e, "recover", s.pf(e, "recover_s"))
				elif s.due(float(e.until)) or bool(e.blocked):
					e.lunge_at = s.time + 1.0
					s.set_state(e, "recover", s.pf(e, "recover_s"))

## 最後の1匹は囲みをやめ、正面から間合いを詰めて噛みつく(逃げない)
static func _last_one(s: RefCounted, e: Dictionary, t: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	e.state = "circle"
	if s.in_reach(e, t):
		e.face = (t.pos - e.pos).normalized()
		if s.due(float(e.bite_at)):
			s.dmg_target(e, t, s.pf(e, "bite_damage"), ev)
			e.bite_at = s.time + s.pf(e, "last_interval_s")
	else:
		s.step_move(e, t.pos - e.pos, s.speed_px(e), dt, ev)

static func on_flee(s: RefCounted, e: Dictionary) -> void:
	e.state = "circle"
