extends "res://scripts/content_pack/enemies/base.gd"
## E09 コケガメ。状態: hidden / walk / eat / flipped / revealed
## 止まっている間は茂みに擬態。動く・攻撃を受ける・株を食べると見破られ、10秒止まり続けると再び擬態する。

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "hidden"
	e.still_t = 0.0
	e.eat_at = 0.0
	e.bite_at = 0.0
	e.target_crop = 0

static func hidden(_s: RefCounted, e: Dictionary) -> bool:
	return e.state == "hidden"

static func damage_mult(s: RefCounted, e: Dictionary, kind: String, _f: Variant) -> float:
	if e.state == "flipped":
		return s.pf(e, "flip_mult")
	if kind == "shot" or kind == "helper":
		return s.pf(e, "shot_mult")
	return 1.0

static func on_hit(s: RefCounted, e: Dictionary, kind: String, _f: Variant, _d: float, ev: Array[Dictionary]) -> void:
	if kind == "bazooka" and e.state != "flipped":
		s.set_state(e, "flipped", s.pf(e, "flip_s"))
		s.fx(ev, "flipped", e.pos, e)
	elif e.state == "hidden":
		e.state = "revealed"
		e.still_t = 0.0

static func on_defeat(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	ev.append({"type": "fertile", "pos": e.pos, "radius_px": s.pm(e, "fertile_radius_m"), "cause": "moss_turtle"})

static func _bite(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	var t: Dictionary = s.nearest_target(e, s.pm(e, "bite_reach_m"), false)
	if not t.is_empty() and s.due(float(e.bite_at)):
		s.dmg_target(e, t, s.pf(e, "bite_damage"), ev)
		e.bite_at = s.time + s.pf(e, "eat_interval_s")

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	match str(e.state):
		"flipped":
			if s.due(float(e.until)):
				e.state = "revealed"
				e.still_t = 0.0
		"hidden":
			var c: Dictionary = s.nearest_crop(e, s.pm(e, "trigger_crop_m"), false)
			var h: Dictionary = s.nearest_target(e, s.pm(e, "trigger_hero_m"), false)
			if not c.is_empty() or not h.is_empty():
				e.state = "walk"
				e.target_crop = int(c.id) if not c.is_empty() else 0
		"walk":
			_bite(s, e, ev)
			var c2: Dictionary = s.nearest_crop(e, s.pm(e, "trigger_crop_m"), false)
			if c2.is_empty():
				e.state = "revealed"
				e.still_t = 0.0
				return
			e.target_crop = int(c2.id)
			if s.crop_dist(e.pos, c2) <= s.radius_px(e) + 2.0:
				s.set_state(e, "eat", 0.0)
				e.eat_at = s.time + s.pf(e, "eat_interval_s")
			else:
				s.step_move(e, s.crop_center(c2) - e.pos, s.speed_px(e), dt, ev)
		"eat":
			_bite(s, e, ev)
			var cc: Dictionary = s.crops.get_crop(int(e.target_crop))
			if cc.is_empty():
				e.state = "revealed"
				e.still_t = 0.0
				return
			if s.due(float(e.eat_at)):
				e.eat_at = s.time + s.pf(e, "eat_interval_s")
				s.hurt_crop(e, int(e.target_crop), s.pf(e, "eat_damage"), ev)
		"revealed":
			_bite(s, e, ev)
			var c3: Dictionary = s.nearest_crop(e, s.pm(e, "trigger_crop_m"), false)
			if not c3.is_empty():
				e.state = "walk"
				return
			e.still_t = float(e.still_t) + dt
			if float(e.still_t) >= s.pf(e, "rehide_s") - 1e-6:
				e.state = "hidden"
