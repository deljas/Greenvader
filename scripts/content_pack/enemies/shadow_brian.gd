extends "res://scripts/content_pack/enemies/base.gd"
## E01 シャドーブリアン。状態: idle / windup / charge / stuck / recover

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.hit_ids = []
	e.charge_dir = Vector2.DOWN
	e.charge_end = 0.0
	e.tpos = e.pos

static func damage_mult(s: RefCounted, e: Dictionary, kind: String, from: Variant) -> float:
	if e.state == "stuck":
		return s.pf(e, "stuck_mult")
	if kind == "shot" or kind == "helper":
		if s.is_front(e, from, s.pf(e, "front_half_deg")):
			return s.pf(e, "front_mult")
	return 1.0

static func _melee(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> bool:
	var t: Dictionary = s.nearest_target(e, s.radius_px(e) + 8.0, false)
	if t.is_empty() or not s.in_reach(e, t):
		return false
	e.face = (t.pos - e.pos).normalized()
	if s.due(float(e.melee_at)):
		s.dmg_target(e, t, s.pf(e, "melee_damage"), ev)
		e.melee_at = s.time + s.pf(e, "melee_interval_s")
	return true

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	match str(e.state):
		"idle", "recover":
			if _melee(s, e, ev):
				return
			if e.state == "recover":
				if s.due(float(e.until)):
					e.state = "idle"
				return
			var t: Dictionary = s.pick_target(e, s.pm(e, "trigger_m"), s.pm(e, "helper_trigger_m"), true)
			if t.is_empty():
				s.wander(e, dt, ev, s.speed_px(e) * 0.6, s.pm(e, "wander_m"))
				return
			e.tpos = t.pos
			e.face = (t.pos - e.pos).normalized()
			s.set_state(e, "windup", s.pf(e, "windup_s"))
			s.fx(ev, "windup", e.pos, e)
		"windup":
			var t2: Dictionary = s.pick_target(e, s.pm(e, "trigger_m") * 1.5, s.pm(e, "helper_trigger_m") * 1.5, false)
			if not t2.is_empty():
				e.tpos = t2.pos
			var to: Vector2 = e.tpos - e.pos
			if to.length() > 0.1:
				e.face = to.normalized()
			if s.due(float(e.until)):
				e.charge_dir = Vector2(e.face)
				e.hit_ids = []
				e.charge_end = s.time + s.pf(e, "charge_max_s")
				s.set_state(e, "charge", s.pf(e, "charge_max_s"))
		"charge":
			# 1マスの株を飛ばさないよう、2px刻みで進めながら判定する
			var n: int = int(ceil(s.pm(e, "charge_mps") * dt / 2.0))
			for _i: int in range(n):
				s.step_move(e, e.charge_dir, s.pm(e, "charge_mps"), dt / float(n), ev, {"straight": true, "ignore_repel": true})
				if not bool(e.alive):
					return
				var cid: int = int(s.crops.crop_id_at(Vector2i(floori(e.pos.x / 4.0), floori(e.pos.y / 4.0))))
				if cid > 0 and not e.hit_ids.has("c" + str(cid)):
					e.hit_ids.append("c" + str(cid))
					s.hurt_crop(e, cid, s.pf(e, "crop_damage"), ev)
					if not bool(e.alive) or float(e.flee_until) > s.time:
						return
				for t3: Dictionary in s.all_targets():
					var key: String = str(t3.type) + str(t3.id)
					if e.pos.distance_to(t3.pos) <= s.radius_px(e) + 4.0 and not e.hit_ids.has(key):
						e.hit_ids.append(key)
						s.dmg_target(e, t3, s.pf(e, "charge_damage"), ev)
				if bool(e.blocked):
					break
			if bool(e.blocked):
				s.set_state(e, "stuck", s.pf(e, "stuck_s"))
				s.fx(ev, "stuck", e.pos, e)
			elif s.due(float(e.charge_end)):
				s.set_state(e, "recover", s.pf(e, "recover_s"))
		"stuck":
			if s.due(float(e.until)):
				e.state = "idle"

static func on_flee(s: RefCounted, e: Dictionary) -> void:
	s.set_state(e, "recover", 0.0)
