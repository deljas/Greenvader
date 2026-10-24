extends "res://scripts/content_pack/enemies/base.gd"
## E10 ペンキカメレオン。状態: hidden / moving / revealed / strike
## ペンキ(paint)が塗られ、止まっている間は見えない。水が当たるとペンキが落ち、以後は常に見える。

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.paint = true
	e.state = "hidden"
	e.reveal_until = 0.0
	e.still_t = 0.0
	e.dest = e.pos
	e.bite_at = 0.0
	e.ambush = false

static func _seen(s: RefCounted, e: Dictionary) -> bool:
	return not bool(e.paint) or not s.due(float(e.reveal_until))

static func hidden(s: RefCounted, e: Dictionary) -> bool:
	return bool(e.paint) and not _seen(s, e) and (e.state == "hidden" or e.state == "moving" or e.state == "strike")

static func hint(s: RefCounted, e: Dictionary) -> bool:
	return e.state == "moving" and hidden(s, e)

static func on_hit(s: RefCounted, e: Dictionary, _k: String, _f: Variant, _d: float, _ev: Array[Dictionary]) -> void:
	if bool(e.paint):
		e.reveal_until = s.time + s.pf(e, "hit_reveal_s")
		if e.state == "hidden":
			e.state = "revealed"
			e.still_t = 0.0

static func on_water(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	if bool(e.paint):
		e.paint = false
		s.fx(ev, "paint_off", e.pos, e)
		if e.state == "hidden":
			e.state = "revealed"
			e.still_t = 0.0

static func _retreat(s: RefCounted, e: Dictionary, from_pos: Vector2) -> void:
	var dir: Vector2 = (e.pos - from_pos)
	dir = dir.normalized() if dir.length() > 0.1 else Vector2.RIGHT
	e.dest = e.pos + dir * s.pm(e, "retreat_m")
	e.state = "moving"

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	match str(e.state):
		"hidden":
			var t: Dictionary = s.nearest_target(e, s.pm(e, "trigger_m"), false)
			if not t.is_empty():
				e.ambush = hidden(s, e)
				s.set_state(e, "strike", s.pf(e, "ambush_windup_s"))
				s.fx(ev, "windup", e.pos, e)
		"strike":
			if s.due(float(e.until)):
				var t2: Dictionary = s.nearest_target(e, s.pm(e, "trigger_m") + 5.0, false)
				if not t2.is_empty():
					s.dmg_target(e, t2, s.pf(e, "ambush_damage") if bool(e.ambush) else s.pf(e, "bite_damage"), ev)
					e.bite_at = s.time + s.pf(e, "bite_interval_s")
					_retreat(s, e, t2.pos)
				else:
					e.state = "revealed"
					e.still_t = 0.0
		"moving":
			if s.walk_to(e, e.dest, s.speed_px(e), dt, ev, 1.5) or bool(e.blocked):
				e.state = "revealed"
				e.still_t = 0.0
		"revealed":
			if _seen(s, e):
				e.still_t = 0.0
				var t3: Dictionary = s.nearest_target(e, s.pm(e, "chase_m"), false)
				if t3.is_empty():
					return
				if s.in_reach(e, t3):
					if s.due(float(e.bite_at)):
						s.dmg_target(e, t3, s.pf(e, "bite_damage"), ev)
						e.bite_at = s.time + s.pf(e, "bite_interval_s")
						_retreat(s, e, t3.pos)
				else:
					s.step_move(e, t3.pos - e.pos, s.speed_px(e), dt, ev)
			else:
				e.still_t = float(e.still_t) + dt
				if float(e.still_t) >= s.pf(e, "still_s") - 1e-6:
					e.state = "hidden"
