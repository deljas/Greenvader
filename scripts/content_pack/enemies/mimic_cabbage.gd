extends "res://scripts/content_pack/enemies/base.gd"
## E18 ミミックキャベツ。状態: hidden / strike / chase / return / revealed
## 擬態中(hidden)は検知対象外で、そのマスは植付けできない(enemy_system.occupied_by)。攻撃・種・水が当たると revealed、自分から噛みつくと strike で擬態が解ける。

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "hidden"
	e.settle_at = -1.0
	e.bite_at = 0.0

static func hidden(_s: RefCounted, e: Dictionary) -> bool:
	return e.state == "hidden"

static func _reveal(s: RefCounted, e: Dictionary) -> void:
	if e.state == "hidden":
		s.set_state(e, "revealed", s.pf(e, "rehide_s"))
	elif e.state == "revealed":
		e.until = s.time + s.pf(e, "rehide_s")

static func on_hit(s: RefCounted, e: Dictionary, _k: String, _f: Variant, _d: float, _ev: Array[Dictionary]) -> void:
	_reveal(s, e)

static func on_water(s: RefCounted, e: Dictionary, _ev: Array[Dictionary]) -> void:
	_reveal(s, e)

static func on_seed(s: RefCounted, e: Dictionary, pos: Vector2, _ev: Array[Dictionary]) -> void:
	if e.pos.distance_to(pos) <= 10.0:
		_reveal(s, e)

static func _near(s: RefCounted, e: Dictionary) -> Dictionary:
	return s.nearest_target(e, s.pm(e, "trigger_m"), false)

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	match str(e.state):
		"hidden":
			if not _near(s, e).is_empty():
				s.set_state(e, "strike", s.pf(e, "windup_s"))
				s.fx(ev, "windup", e.pos, e)
		"revealed":
			if not _near(s, e).is_empty():
				s.set_state(e, "strike", s.pf(e, "windup_s"))
				s.fx(ev, "windup", e.pos, e)
			elif s.due(float(e.until)):
				e.state = "return"
				e.settle_at = -1.0
		"strike":
			if s.due(float(e.until)):
				var t: Dictionary = s.nearest_target(e, s.pm(e, "trigger_m") + 10.0, false)
				if t.is_empty():
					e.state = "return"
					e.settle_at = -1.0
					return
				e.face = (t.pos - e.pos).normalized()
				s.dmg_target(e, t, s.pf(e, "bite_damage"), ev)
				e.bite_at = s.time + s.pf(e, "bite_interval_s")
				s.set_state(e, "chase", s.pf(e, "chase_s"))
		"chase":
			if s.due(float(e.until)):
				e.state = "return"
				e.settle_at = -1.0
				return
			var t2: Dictionary = s.nearest_target(e, s.pm(e, "chase_m"), false)
			if t2.is_empty():
				return
			if s.in_reach(e, t2):
				if s.due(float(e.bite_at)):
					s.dmg_target(e, t2, s.pf(e, "bite_damage"), ev)
					e.bite_at = s.time + s.pf(e, "bite_interval_s")
			else:
				s.step_move(e, t2.pos - e.pos, s.speed_px(e), dt, ev, {"limit_px": s.territory_px(e)})
		"return":
			if s.walk_to(e, e.home, s.speed_px(e), dt, ev, 2.0) or bool(e.blocked) or e.pos.distance_to(e.home) <= 2.05:
				if float(e.settle_at) < 0.0:
					e.settle_at = s.time + s.pf(e, "rehide_s")
				elif s.due(float(e.settle_at)):
					e.settle_at = -1.0
					e.state = "hidden"

static func on_flee(s: RefCounted, e: Dictionary) -> void:
	e.state = "return"
	e.settle_at = -1.0
	e.until = s.time
