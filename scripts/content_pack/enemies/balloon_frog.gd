extends "res://scripts/content_pack/enemies/base.gd"
## E33 フウセンガエル(3匹、同じ group_id)。状態: hop(地上、HP6、攻撃しない) / inflate(1秒で膨らむ) / float(浮上して0.8m/sで漂う)
## 浮いている間はどの攻撃でも1回当たれば割れて撃破(水は攻撃ではない)。主人公に触れても割れる。割れた場所の半径1.6mに酸が5秒残る(3ダメージ/秒、主人公・おたすけ植物・栽培植物)。
const STATES: Array = ["hop", "inflate", "float"]

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "hop"

static func validate(_s: RefCounted, e: Dictionary) -> bool:
	return STATES.has(str(e.state))

## 浮かんでいる間は飛行の扱い(地面の影は表示側)。膨らんでいる最中・浮上中は当たる。
static func calc_damage(s: RefCounted, e: Dictionary, amount: float, kind: String, from: Variant, ev: Array[Dictionary]) -> float:
	if e.state == "float" and kind != "water":
		return maxf(float(e.hp), 1.0)   # 1回当たれば割れる
	return amount * float(s.beh(e).damage_mult(s, e, kind, from))

static func on_defeat(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	if e.state == "float":
		s.add_acid(e.pos, int(e.id), s.pm(e, "acid_m"), s.pf(e, "acid_s"), s.pf(e, "acid_dps"))
		s.fx(ev, "frog_pop", e.pos, e, {"radius": s.pm(e, "acid_m")})

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	var h: Dictionary = s.hero_t()
	match str(e.state):
		"hop":
			if not h.is_empty() and e.pos.distance_to(h.pos) <= s.pm(e, "trigger_m"):
				s.set_state(e, "inflate", s.pf(e, "inflate_s"))
				s.fx(ev, "inflate", e.pos, e)
				return
			s.wander(e, dt, ev, s.pm(e, "hop_mps"), s.pm(e, "wander_m"))
		"inflate":
			if s.due(float(e.until)):
				e.state = "float"
		"float":
			if h.is_empty():
				return
			s.step_move(e, h.pos - e.pos, s.pm(e, "float_mps"), dt, ev, {"habitat": "air", "straight": true, "no_root": true})
			if e.pos.distance_to(h.pos) <= s.radius_px(e) + 4.0:
				s.fx(ev, "frog_touch", e.pos, e)
				s.deal_raw(e, maxf(float(e.hp), 1.0), "touch", ev)   # 主人公に触れて割れる

static func on_flee(_s: RefCounted, _e: Dictionary) -> void:
	pass
