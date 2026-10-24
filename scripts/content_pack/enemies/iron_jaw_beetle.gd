extends "res://scripts/content_pack/enemies/base.gd"
## E21 テツアゴクワガタ。状態: idle / approach / windup / snip / recover
## おたすけ植物を最優先(12m以内)、いなければ3m以内の主人公。予兆0.5秒の後に挟み切る。

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "idle"
	e.ttype = ""
	e.tid = 0

static func _pick(s: RefCounted, e: Dictionary) -> Dictionary:
	var hp: Dictionary = s.nearest_helper(e, s.pm(e, "trigger_helper_m"), false)
	if not hp.is_empty():
		return hp
	var h: Dictionary = s.hero_t()
	if not h.is_empty() and e.pos.distance_to(h.pos) <= s.pm(e, "trigger_hero_m"):
		return h
	return {}

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	match str(e.state):
		"idle", "approach":
			var t: Dictionary = _pick(s, e)
			if t.is_empty():
				e.state = "idle"
				s.wander(e, dt, ev, s.speed_px(e) * 0.6, 40.0)
				return
			e.state = "approach"
			e.face = (t.pos - e.pos).normalized() if e.pos.distance_to(t.pos) > 0.1 else e.face
			if s.in_reach(e, t):
				e.ttype = str(t.type)
				e.tid = int(t.id)
				s.set_state(e, "windup", s.pf(e, "windup_s"))
				s.fx(ev, "windup", e.pos, e)
			else:
				s.step_move(e, t.pos - e.pos, s.speed_px(e), dt, ev)
		"windup":
			if s.due(float(e.until)):
				e.state = "snip"
				for t2: Dictionary in s.all_targets():
					if str(t2.type) == str(e.ttype) and int(t2.id) == int(e.tid) and s.in_reach(e, t2):
						s.dmg_target(e, t2, s.pf(e, "helper_damage") if t2.type == "helper" else s.pf(e, "hero_damage"), ev)
						break
				s.fx(ev, "snip", e.pos, e)
				s.set_state(e, "recover", s.pf(e, "recover_s"))
		"recover":
			if s.due(float(e.until)):
				e.state = "idle"
