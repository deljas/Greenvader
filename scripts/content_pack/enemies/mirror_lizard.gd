extends "res://scripts/content_pack/enemies/base.gd"
## E31 カガミトカゲ。状態: idle / approach / bite(噛んだ後の硬直、向き固定)
## 正面120°から当たった射撃(shot)とおたすけ植物の弾(helper)は、ダメージを与えず、来た方向へ元の威力で跳ね返る
## (跳ね返った弾は enemy_system.projectiles に入り、主人公・おたすけ植物に当たる)。爆風は正面なら×0.5(跳ね返らない)。たいあたりは向きに関係なく効く。
const Facing: GDScript = preload("res://scripts/content_pack/facing.gd")
const STATES: Array = ["idle", "approach", "bite"]

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "idle"
	e.bite_at = 0.0

static func validate(_s: RefCounted, e: Dictionary) -> bool:
	return STATES.has(str(e.state))

static func _origin(kind: String, from: Variant) -> Variant:
	return Facing.attack_origin(kind, from, from, from)

static func calc_damage(s: RefCounted, e: Dictionary, amount: float, kind: String, from: Variant, ev: Array[Dictionary]) -> float:
	if kind == "shot" or kind == "helper":
		if Facing.is_front(e.face, e.pos, _origin(kind, from), s.pf(e, "front_half_deg")):
			var origin: Vector2 = Vector2(from)
			var dir: Vector2 = (origin - e.pos).normalized()
			var dist: float = e.pos.distance_to(origin)
			s.spawn_projectile({"kind": "reflected", "owner": int(e.id), "pos": e.pos + dir * s.radius_px(e), "dir": dir,
				"speed": s.pm(e, "reflect_mps"), "left": clampf(dist + s.pm(e, "reflect_extra_m"), 60.0, 250.0), "damage": amount})
			s.fx(ev, "reflect", e.pos, e, {"dir": dir})
			return 0.0
	elif kind == "bazooka":
		if Facing.is_front(e.face, e.pos, _origin(kind, from), s.pf(e, "front_half_deg")):
			return amount * s.pf(e, "bazooka_front_mult")
	return amount

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	var turn: float = s.pf(e, "turn_dps")
	if str(e.state) == "bite":
		if s.due(float(e.until)):
			e.state = "idle"
		return   # 噛みつきの後は硬直し、向きを変えない
	var h: Dictionary = s.hero_t()
	var t: Dictionary = {}
	if not h.is_empty() and e.pos.distance_to(h.pos) <= s.pm(e, "trigger_m"):
		t = h
	else:
		t = s.nearest_helper(e, s.pm(e, "trigger_m"), false)
	if t.is_empty():
		e.state = "idle"
		var face0: Vector2 = Vector2(e.face)
		s.wander(e, dt, ev, s.speed_px(e) * 0.6, s.pm(e, "wander_m"))
		e.face = face0
		if bool(e.wp_valid) and e.pos.distance_to(e.wp) > 1.0:
			e.face = Facing.turn_toward(face0, e.wp - e.pos, turn, dt)   # 歩くときも旋回は120°/秒まで
		return
	e.face = Facing.turn_toward(e.face, t.pos - e.pos, turn, dt)
	if s.in_reach(e, t):
		if s.due(float(e.bite_at)):
			s.dmg_target(e, t, s.pf(e, "bite_damage"), ev)
			e.bite_at = s.time + s.pf(e, "lock_s")
			s.set_state(e, "bite", s.pf(e, "lock_s"))
	else:
		e.state = "approach"
		s.step_move(e, t.pos - e.pos, s.speed_px(e), dt, ev, {"keep_face": true, "limit_px": s.territory_px(e) + 80.0})

static func on_flee(s: RefCounted, e: Dictionary) -> void:
	e.state = "idle"
	e.until = s.time
