extends "res://scripts/content_pack/enemies/base.gd"
## E15 アルマジロ。状態: idle / curl / roll / dizzy。転がり中は壁(建物・水際・タケ・安定地域・地図外)で反射し、最大 max_bounces 回跳ね返るか roll_max_s で止まる。

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "idle"
	e.roll_dir = Vector2.RIGHT
	e.bounces = 0
	e.hit_ids = []
	e.tpos = e.pos

static func damage_mult(s: RefCounted, e: Dictionary, _k: String, _f: Variant) -> float:
	if e.state == "roll":
		return s.pf(e, "roll_mult")
	if e.state == "dizzy":
		return s.pf(e, "dizzy_mult")
	return 1.0

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	match str(e.state):
		"idle":
			var h: Dictionary = s.hero_t()
			if not h.is_empty() and e.pos.distance_to(h.pos) <= s.pm(e, "trigger_m"):
				e.tpos = h.pos
				e.face = (h.pos - e.pos).normalized()
				s.set_state(e, "curl", s.pf(e, "windup_s"))
				s.fx(ev, "windup", e.pos, e)
				return
			s.wander(e, dt, ev, s.speed_px(e) * 0.6, 60.0)
		"curl":
			var h2: Dictionary = s.hero_t()
			if not h2.is_empty():
				e.tpos = h2.pos
			if e.pos.distance_to(e.tpos) > 0.1:
				e.face = (e.tpos - e.pos).normalized()
			if s.due(float(e.until)):
				e.roll_dir = Vector2(e.face)
				e.bounces = 0
				e.hit_ids = []
				s.set_state(e, "roll", s.pf(e, "roll_max_s"))
		"roll":
			_roll(s, e, dt, ev)
		"dizzy":
			if s.due(float(e.until)):
				e.state = "idle"

static func _stop(s: RefCounted, e: Dictionary) -> void:
	s.set_state(e, "dizzy", s.pf(e, "dizzy_s"))

static func _roll(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	var speed: float = s.pm(e, "roll_mps")
	var n: int = int(ceil(speed * dt / 2.0))
	var opts: Dictionary = {"straight": true, "ignore_repel": true}
	for _i: int in range(n):
		s.step_move(e, e.roll_dir, speed, dt / float(n), ev, opts)
		if not bool(e.alive):
			return
		var cid: int = int(s.crops.crop_id_at(Vector2i(floori(e.pos.x / 4.0), floori(e.pos.y / 4.0))))
		if cid > 0 and not e.hit_ids.has("c" + str(cid)):
			e.hit_ids.append("c" + str(cid))
			s.hurt_crop(e, cid, s.pf(e, "crop_damage"), ev)
			if not bool(e.alive) or float(e.flee_until) > s.time:
				return
		for t: Dictionary in s.all_targets():
			var key: String = str(t.type) + str(t.id)
			if e.pos.distance_to(t.pos) <= s.radius_px(e) + s.HERO_R and not e.hit_ids.has(key):
				e.hit_ids.append(key)
				s.dmg_target(e, t, s.pf(e, "hit_damage"), ev)
		if bool(e.blocked):
			if int(e.bounces) >= int(s.pf(e, "max_bounces")):
				_stop(s, e)
				return
			e.bounces = int(e.bounces) + 1
			_reflect(s, e)
			s.fx(ev, "bounce", e.pos, e)
	if s.due(float(e.until)):
		_stop(s, e)

static func _reflect(s: RefCounted, e: Dictionary) -> void:
	var d: Vector2 = e.roll_dir
	var bx: bool = absf(d.x) > 1e-6 and not s.can_stand(e, e.pos + Vector2(signf(d.x) * 2.0, 0.0), {"ignore_repel": true})
	var by: bool = absf(d.y) > 1e-6 and not s.can_stand(e, e.pos + Vector2(0.0, signf(d.y) * 2.0), {"ignore_repel": true})
	if bx and not by:
		d.x = -d.x
	elif by and not bx:
		d.y = -d.y
	else:
		d = -d
	e.roll_dir = d
	e.face = d

static func on_flee(s: RefCounted, e: Dictionary) -> void:
	s.set_state(e, "idle", 0.0)
