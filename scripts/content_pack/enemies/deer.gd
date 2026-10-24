extends "res://scripts/content_pack/enemies/base.gd"
## E20 シカ。状態: graze / approach / eat / flee / tired。成熟株を食べる(3ダメージ/秒)。
const Util: GDScript = preload("res://scripts/content_pack/enemies/flee_util.gd")

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "graze"
	e.target_crop = 0
	e.eat_at = 0.0
	e.think_at = 0.0

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	var st: String = str(e.state)
	if st == "flee":
		Util.flee_step(s, e, dt, ev)
		return
	if st == "tired":
		if s.due(float(e.until)):
			e.state = "graze"
		return
	if Util.hero_near(s, e):
		Util.begin_flee(s, e, null, ev)
		return
	match st:
		"graze":
			if s.due(float(e.think_at)):
				e.think_at = s.time + 0.5
				var c: Dictionary = Util.find_crop(s, e, s.pm(e, "seek_m"))
				if not c.is_empty():
					e.target_crop = int(c.id)
					e.state = "approach"
					return
			s.wander(e, dt, ev, s.speed_px(e) * 0.4, 60.0)
		"approach":
			var c2: Dictionary = s.crops.get_crop(int(e.target_crop))
			if c2.is_empty() or not bool(c2.mature):
				e.state = "graze"
				return
			if s.crop_dist(e.pos, c2) <= s.radius_px(e) + 2.0:
				e.eat_at = s.time + s.pf(e, "eat_interval_s")
				e.state = "eat"
				return
			s.step_move(e, s.crop_center(c2) - e.pos, s.speed_px(e), dt, ev, {"limit_px": s.territory_px(e)})
			if bool(e.blocked):
				e.state = "graze"
		"eat":
			var c3: Dictionary = s.crops.get_crop(int(e.target_crop))
			if c3.is_empty() or not bool(c3.mature):
				e.state = "graze"
				return
			if s.due(float(e.eat_at)):
				e.eat_at = float(e.eat_at) + s.pf(e, "eat_interval_s")
				s.hurt_crop(e, int(e.target_crop), s.pf(e, "eat_damage"), ev)

## 攻撃が当たると逃げる(疲れて止まっている間は逃げない)
static func on_hit(s: RefCounted, e: Dictionary, _k: String, from: Variant, _d: float, ev: Array[Dictionary]) -> void:
	if e.state != "flee" and e.state != "tired":
		Util.begin_flee(s, e, from, ev)

static func on_flee(s: RefCounted, e: Dictionary) -> void:
	e.state = "graze"
	e.until = s.time
