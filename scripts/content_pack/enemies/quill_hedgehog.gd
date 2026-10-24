extends "res://scripts/content_pack/enemies/base.gd"
## E04 ハリナゲネズミ。状態: idle / keep / aim / curl / flipped

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.needle_at = 0.0
	e.curl_ok_at = 0.0
	e.tpos = e.pos

static func damage_mult(s: RefCounted, e: Dictionary, kind: String, _from: Variant) -> float:
	if e.state == "flipped":
		return s.pf(e, "flipped_mult")
	if e.state == "curl" and (kind == "shot" or kind == "helper"):
		return s.pf(e, "curl_mult")
	return 1.0

## たいあたりで丸まりが解け、無防備になる
static func on_hit(s: RefCounted, e: Dictionary, kind: String, _from: Variant, _d: float, ev: Array[Dictionary]) -> void:
	if kind == "tackle" and e.state == "curl":
		s.set_state(e, "flipped", s.pf(e, "flipped_s"))
		s.fx(ev, "flipped", e.pos, e)

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	match str(e.state):
		"idle":
			var t: Dictionary = s.pick_target(e, s.pm(e, "trigger_m"), s.pm(e, "trigger_m"), true)
			if not t.is_empty():
				e.state = "keep"
			else:
				s.wander(e, dt, ev, s.speed_px(e) * 0.6, s.pm(e, "wander_m"))
		"keep":
			var t2: Dictionary = s.pick_target(e, s.pm(e, "trigger_m"), s.pm(e, "trigger_m"), true)
			if t2.is_empty():
				e.state = "idle"
				return
			var d: float = e.pos.distance_to(t2.pos)
			e.face = (t2.pos - e.pos).normalized()
			if t2.type == "hero" and d <= s.pm(e, "curl_trigger_m") and s.due(float(e.curl_ok_at)):
				s.set_state(e, "curl", s.pf(e, "curl_s"))
				s.fx(ev, "curl", e.pos, e)
				return
			if d < s.pm(e, "keep_min_m"):
				s.walk_away(e, t2.pos, s.speed_px(e), dt, ev)
			elif d > s.pm(e, "keep_max_m"):
				s.step_move(e, t2.pos - e.pos, s.speed_px(e), dt, ev)
			if s.due(float(e.needle_at)):
				e.tpos = t2.pos
				s.set_state(e, "aim", s.pf(e, "aim_s"))
				s.fx(ev, "windup", e.pos, e)
		"aim":
			var t3: Dictionary = s.pick_target(e, s.pm(e, "trigger_m"), s.pm(e, "trigger_m"), false)
			if not t3.is_empty():
				e.tpos = t3.pos
			e.face = (e.tpos - e.pos).normalized() if e.tpos.distance_to(e.pos) > 0.1 else e.face
			if s.due(float(e.until)):
				s.spawn_projectile({"kind": "needle", "owner": e.id, "pos": e.pos, "dir": Vector2(e.face),
					"speed": s.pm(e, "needle_mps"), "left": s.pm(e, "needle_range_m"), "damage": s.pf(e, "needle_damage")})
				e.needle_at = s.time + s.pf(e, "needle_interval_s")
				e.state = "keep"
		"curl":
			if s.due(float(e.until)):
				e.curl_ok_at = s.time + s.pf(e, "curl_cooldown_s")
				e.state = "keep"
		"flipped":
			if s.due(float(e.until)):
				e.state = "keep"
