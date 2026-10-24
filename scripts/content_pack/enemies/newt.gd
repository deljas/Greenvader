extends "res://scripts/content_pack/enemies/base.gd"
## E30 ブンシンイモリ(decoy_newt)とその分身(decoy_tail)。
## 本体: idle / approach / bite。攻撃が当たるたびに尾が残っていれば尾を切り離し、尾は分身になる。尾は8秒で再生(tail が false の間は分身を出せない)。
## 分身: run。本体と同じ見た目で別の方向へ2.5m/sで走り、攻撃せず、何かが当たると消え、10秒で消える。安定判定にも検知にも数えない(定義の decoy)。
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")
const STATES: Array = ["idle", "approach", "bite", "run"]

static func init(s: RefCounted, e: Dictionary, o: Dictionary) -> void:
	if str(e.kind) == "decoy_newt":
		e.state = "idle"
		e.tail = true
		e.regrow_at = 0.0
		e.bite_at = 0.0
		e.think_at = s.time
	else:
		e.state = "run"
		e.run_dir = Vector2(o.get("run_dir", Vector2.RIGHT))
		e.expire_at = s.time + float(o.get("life_s", 10.0))
		e.decoy_of = int(o.get("decoy_of", 0))

static func validate(_s: RefCounted, e: Dictionary) -> bool:
	if not STATES.has(str(e.state)):
		return false
	if str(e.kind) == "decoy_tail":
		return typeof(e.run_dir) == TYPE_VECTOR2
	return true

## 分身は何かが当たれば(水も含めて)消える
static func calc_damage(s: RefCounted, e: Dictionary, amount: float, kind: String, from: Variant, ev: Array[Dictionary]) -> float:
	if str(e.kind) == "decoy_tail":
		return maxf(float(e.hp), 1.0)
	return amount * float(s.beh(e).damage_mult(s, e, kind, from))

static func on_water(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	if str(e.kind) == "decoy_tail":
		s.deal_raw(e, maxf(float(e.hp), 1.0), "water", ev)
		s.fx(ev, "decoy_pop", e.pos, e)

static func on_defeat(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	if str(e.kind) == "decoy_tail":
		s.fx(ev, "decoy_pop", e.pos, e)

static func on_hit(s: RefCounted, e: Dictionary, kind: String, from: Variant, _d: float, ev: Array[Dictionary]) -> void:
	if str(e.kind) != "decoy_newt" or kind == "water" or not bool(e.tail):
		return
	e.tail = false
	e.regrow_at = s.time + s.pf(e, "regrow_s")
	# 撃った方向とは別の方向(横〜後ろ)へ走らせる
	var away: Vector2 = Vector2.from_angle(s.rng.randf() * TAU)
	if typeof(from) == TYPE_VECTOR2 and Vector2(from).distance_to(e.pos) > 0.1:
		away = (e.pos - Vector2(from)).normalized().rotated(deg_to_rad(s.rng.randf_range(60.0, 120.0)) * (1.0 if s.rng.randf() < 0.5 else -1.0))
	var id: int = s.spawn("decoy_tail", e.pos, "produced", {"run_dir": away, "life_s": s.pf(e, "decoy_s"), "decoy_of": int(e.id), "tier": str(e.tier), "home": e.pos})
	if id >= 0:
		s.ref(id).face = away
	s.fx(ev, "tail_cut", e.pos, e, {"decoy_id": id})

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	if str(e.kind) == "decoy_tail":
		if s.due(float(e.expire_at)):
			e.alive = false
			s.fx(ev, "decoy_gone", e.pos, e)
			return
		s.step_move(e, e.run_dir, s.speed_px(e), dt, ev, {"straight": true, "limit_px": s.territory_px(e)})
		return
	if not bool(e.tail) and s.due(float(e.regrow_at)):
		e.tail = true
	var h: Dictionary = s.hero_t()
	var t: Dictionary = {}
	if not h.is_empty() and e.pos.distance_to(h.pos) <= s.pm(e, "trigger_m"):
		t = h
	else:
		t = s.nearest_helper(e, s.pm(e, "trigger_m"), false)
	match str(e.state):
		"idle", "approach", "bite":
			if t.is_empty():
				e.state = "idle"
				s.wander(e, dt, ev, s.speed_px(e) * 0.6, s.pm(e, "wander_m"))
				return
			if s.in_reach(e, t):
				e.state = "bite"
				e.face = (t.pos - e.pos).normalized()
				if s.due(float(e.bite_at)):
					s.dmg_target(e, t, s.pf(e, "bite_damage"), ev)
					e.bite_at = s.time + s.pf(e, "bite_interval_s")
			else:
				e.state = "approach"
				s.step_move(e, t.pos - e.pos, s.speed_px(e), dt, ev, {"limit_px": s.territory_px(e) + 60.0})

static func on_flee(s: RefCounted, e: Dictionary) -> void:
	if str(e.kind) == "decoy_newt":
		e.state = "idle"
		e.until = s.time
