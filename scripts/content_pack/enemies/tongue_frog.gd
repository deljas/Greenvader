extends "res://scripts/content_pack/enemies/base.gd"
## E13 ベロガエル。状態: idle / aim / tongue / cooldown。予兆で舌の線(方向)を固定し、予兆後に7mの直線へ舌を伸ばす。
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "idle"
	e.cd_until = 0.0
	e.tongue_dir = Vector2.DOWN

## 舌の先端。建物で遮られる。
static func trace(s: RefCounted, e: Dictionary) -> Vector2:
	var dir: Vector2 = e.tongue_dir
	var maxd: float = s.pm(e, "tongue_range_m")
	var d: float = 2.0
	var last: float = 0.0
	while d <= maxd + 1e-6:
		var p: Vector2 = e.pos + dir * d
		if s.host.is_building(Grid.cell_of_pos(p)) or not s.host.in_bounds(Grid.cell_of_pos(p)):
			break
		last = d
		d += 2.0
	if d > maxd + 1e-6:
		last = maxd
	return e.pos + dir * last

static func update(s: RefCounted, e: Dictionary, _dt: float, ev: Array[Dictionary]) -> void:
	match str(e.state):
		"idle":
			if not s.due(float(e.cd_until)):
				return
			var h: Dictionary = s.hero_t()
			if h.is_empty() or e.pos.distance_to(h.pos) > s.pm(e, "trigger_m") or not s.host.line_clear(e.pos, h.pos):
				return
			e.tongue_dir = (h.pos - e.pos).normalized()
			e.face = e.tongue_dir
			s.set_state(e, "aim", s.pf(e, "aim_s"))
			s.fx(ev, "tongue_line", e.pos, e, {"to": trace(s, e), "seconds": s.pf(e, "aim_s")})
		"aim":
			if s.due(float(e.until)):
				_fire(s, e, ev)
		"tongue":
			if s.due(float(e.until)):
				e.state = "cooldown"
		"cooldown":
			if s.due(float(e.cd_until)):
				e.state = "idle"

static func _fire(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	var end: Vector2 = trace(s, e)
	var dir: Vector2 = e.tongue_dir
	var length: float = e.pos.distance_to(end)
	var best: Dictionary = {}
	var ba: float = 1e18
	for t: Dictionary in s.all_targets():
		var rel: Vector2 = t.pos - e.pos
		var along: float = rel.dot(dir)
		var perp: float = absf(rel.cross(dir))
		if along >= 0.0 and along <= length + s.HERO_R and perp <= s.HERO_R and along < ba:
			best = t
			ba = along
	s.fx(ev, "tongue", e.pos, e, {"to": end})
	if not best.is_empty():
		if best.type == "hero":
			s.dmg_target(e, best, s.pf(e, "tongue_damage"), ev)
			var d: float = best.pos.distance_to(e.pos)
			var pull: float = minf(s.pm(e, "pull_m"), maxf(0.0, d - s.radius_px(e) - s.HERO_R))
			var to: Vector2 = best.pos + (e.pos - best.pos).normalized() * pull
			ev.append({"type": "hero_pull", "to": to, "source": e.id, "kind": e.kind, "distance": pull})
		else:
			s.dmg_target(e, best, s.pf(e, "helper_damage"), ev)
	e.cd_until = s.time + s.pf(e, "cooldown_s")
	s.set_state(e, "tongue", 0.2)
