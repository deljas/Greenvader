extends "res://scripts/content_pack/enemies/base.gd"
## E02 タラチュネード。状態: idle / chase / fuse / charred / recover
## 仮判断: 自爆ではHPが変わらず、黒焦げ中に受けた分も復活後に残る。

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.wet_until = 0.0
	e.nofuse_until = 0.0
	e.bite_at = 0.0

static func damage_mult(s: RefCounted, e: Dictionary, _k: String, _f: Variant) -> float:
	return s.pf(e, "charred_mult") if e.state == "charred" else 1.0

static func _wet(s: RefCounted, e: Dictionary) -> bool:
	return not s.due(float(e.wet_until))

static func on_water(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	e.wet_until = s.time + s.pf(e, "wet_s")
	s.fx(ev, "wet", e.pos, e)
	if e.state == "fuse":
		s.set_state(e, "chase", 0.0)

static func _explode(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	var r: float = s.pm(e, "blast_radius_m")
	s.fx(ev, "explosion", e.pos, e, {"radius_px": r})
	for t: Dictionary in s.all_targets():
		if e.pos.distance_to(t.pos) <= r:
			s.dmg_target(e, t, s.pf(e, "blast_hero"), ev)
	for c: Dictionary in s.crops.crops.duplicate():
		if s.crop_dist(e.pos, c) <= r:
			s.hurt_crop(e, int(c.id), s.pf(e, "blast_crop"), ev, "collateral")
	s.set_state(e, "charred", s.pf(e, "charred_s"))

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	match str(e.state):
		"idle":
			var t: Dictionary = s.nearest_target(e, s.pm(e, "trigger_m"), false)
			if not t.is_empty():
				e.state = "chase"
		"chase", "recover":
			if e.state == "recover" and s.due(float(e.until)):
				e.state = "chase"
			var t2: Dictionary = s.nearest_target(e, s.pm(e, "chase_m"), false)
			if t2.is_empty():
				if e.state == "chase":
					e.state = "idle"
				return
			var d: float = e.pos.distance_to(t2.pos)
			if not _wet(s, e) and e.state == "chase" and d <= s.pm(e, "fuse_start_m") and s.due(float(e.nofuse_until)):
				s.set_state(e, "fuse", s.pf(e, "fuse_s"))
				s.fx(ev, "windup", e.pos, e)
				return
			if _wet(s, e):
				# 湿っている間は点火できない。歩いて近づいてかみつく
				if s.in_reach(e, t2):
					if s.due(float(e.bite_at)):
						s.dmg_target(e, t2, s.pf(e, "bite_damage"), ev)
						e.bite_at = s.time + s.pf(e, "bite_interval_s")
				else:
					s.step_move(e, t2.pos - e.pos, s.speed_px(e), dt, ev)
			elif d > 1.0:
				s.step_move(e, t2.pos - e.pos, s.speed_px(e), dt, ev)
		"fuse":
			if s.due(float(e.until)):
				_explode(s, e, ev)
		"charred":
			if s.due(float(e.until)):
				e.nofuse_until = s.time + s.pf(e, "recover_s")
				s.set_state(e, "recover", s.pf(e, "recover_s"))
				s.fx(ev, "revive", e.pos, e)

static func on_flee(s: RefCounted, e: Dictionary) -> void:
	if e.state != "charred":
		s.set_state(e, "idle", 0.0)
