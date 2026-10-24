extends "res://scripts/content_pack/enemies/base.gd"
## E32 タイホウエビ。状態: idle / approach / windup(予兆1.2秒) / cooldown(間隔5秒)
## 4m以内に主人公かおたすけ植物がいると予兆 → 半径4mの主人公・おたすけ植物を1.5秒気絶(hero_stun / helper_stop cause stun)+5ダメージ。建物で遮られる。栽培植物・草には作用しない。
const Common2: GDScript = preload("res://scripts/content_pack/common2.gd")
const STATES: Array = ["idle", "approach", "windup", "cooldown"]

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "idle"
	e.next_at = 0.0

static func validate(_s: RefCounted, e: Dictionary) -> bool:
	return STATES.has(str(e.state))

static func _target(s: RefCounted, e: Dictionary, range_px: float) -> Dictionary:
	return s.nearest_target(e, range_px, false)

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	match str(e.state):
		"idle", "approach", "cooldown":
			if str(e.state) == "cooldown" and s.due(float(e.until)):
				e.state = "idle"
			var t: Dictionary = _target(s, e, s.pm(e, "trigger_m"))
			if not t.is_empty() and s.due(float(e.next_at)):
				e.face = (t.pos - e.pos).normalized() if e.pos.distance_to(t.pos) > 0.1 else e.face
				s.set_state(e, "windup", s.pf(e, "windup_s"))
				s.fx(ev, "shrimp_windup", e.pos, e, {"radius": s.pm(e, "wave_m")})
				return
			var far: Dictionary = _target(s, e, s.pm(e, "trigger_m") * 2.0)
			if not far.is_empty() and str(e.state) != "cooldown":
				e.state = "approach"
				s.step_move(e, far.pos - e.pos, s.speed_px(e), dt, ev, {"limit_px": s.territory_px(e) + s.pm(e, "trigger_m") * 2.0})
				return
			if str(e.state) == "approach":
				e.state = "idle"
			s.wander(e, dt, ev, s.speed_px(e) * 0.6, s.pm(e, "wander_m"))
		"windup":
			if s.due(float(e.until)):
				var rad: float = s.pm(e, "wave_m")
				for t2: Dictionary in s.all_targets():
					if e.pos.distance_to(t2.pos) <= rad and s.host.line_clear(e.pos, t2.pos):   # 建物で遮られる
						if t2.type == "hero":
							ev.append(Common2.hero_stun_event(s.pf(e, "stun_s"), int(e.id)))
						else:
							ev.append(Common2.helper_stop_event(int(t2.id), s.pf(e, "stun_s"), "stun"))
						s.dmg_target(e, t2, s.pf(e, "damage"), ev)
				s.fx(ev, "shrimp_wave", e.pos, e, {"radius": rad})
				e.next_at = s.time + s.pf(e, "interval_s") - s.pf(e, "windup_s")   # 衝撃波から衝撃波まで5秒
				s.set_state(e, "cooldown", s.pf(e, "interval_s"))

static func on_flee(s: RefCounted, e: Dictionary) -> void:
	e.state = "idle"
	e.until = s.time
