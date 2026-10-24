extends "res://scripts/content_pack/enemies/base.gd"
## E16 ヘドロゴイ。水中のみ。状態: dive(潜行、当たらない) → rise(予兆) → surface(浮上、当たる) → dive …
## 泥の玉は e.muds に {pos,land_at} で持ち、着弾点を発射時から fx(mud_mark) で知らせる。泥は主人公だけに作用し、草・植物には作用しない。

static func init(s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.muds = []
	s.set_state(e, "dive", s.pf(e, "dive_s"))

static func hittable(_s: RefCounted, e: Dictionary) -> bool:
	return e.state == "surface"

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	for m: Dictionary in e.muds.duplicate():
		if s.due(float(m.land_at)):
			e.muds.erase(m)
			_land(s, e, m, ev)
	match str(e.state):
		"dive":
			s.wander(e, dt, ev, s.speed_px(e), 60.0)
			if s.due(float(e.until)):
				s.set_state(e, "rise", s.pf(e, "warn_s"))
				s.fx(ev, "carp_warn", e.pos, e)
		"rise":
			if s.due(float(e.until)):
				s.set_state(e, "surface", s.pf(e, "surface_s"))
				var h: Dictionary = s.hero_t()
				if not h.is_empty() and e.pos.distance_to(h.pos) <= s.pm(e, "trigger_m"):
					var m: Dictionary = {"pos": h.pos, "land_at": s.time + s.pf(e, "mud_flight_s")}
					e.muds.append(m)
					s.fx(ev, "mud_mark", h.pos, e, {"land_at": m.land_at, "radius": s.pm(e, "mud_radius_m")})
		"surface":
			if s.due(float(e.until)):
				s.set_state(e, "dive", s.pf(e, "dive_s"))

static func _land(s: RefCounted, e: Dictionary, m: Dictionary, ev: Array[Dictionary]) -> void:
	s.fx(ev, "mud_land", m.pos, e, {"radius": s.pm(e, "mud_radius_m")})
	var h: Dictionary = s.hero_t()
	if not h.is_empty() and h.pos.distance_to(m.pos) <= s.pm(e, "mud_radius_m"):
		s.dmg_target(e, h, s.pf(e, "mud_damage"), ev)
		ev.append({"type": "hero_slow", "factor": 1.0 - s.pf(e, "slow"), "seconds": s.pf(e, "slow_s"), "source": "mud"})
