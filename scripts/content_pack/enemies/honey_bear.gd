extends "res://scripts/content_pack/enemies/base.gd"
## E25 ハチミツグマ。状態: idle / approach / eat / return / sleep / enraged
## 狙いの優先: リンゴの落果 → ミツバチの巣 → 果実の植物。満腹度(落果1・巣を壊す3・株を倒す2)が3に達すると家で眠る。
## 眠り中は被ダメ×1.5。攻撃されても起きないが、HPが半分を切ると起きて怒る(満腹度は0に戻る)。巣をかじっている間、ミツバチの群れはクマを刺す。
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")
const Hive: GDScript = preload("res://scripts/content_pack/enemies/honeybee.gd")
const STATES: Array = ["idle", "approach", "eat", "return", "sleep", "enraged"]
const KINDS: Array = ["", "fruit", "hive", "crop"]
const FRUIT_PLANTS: Array = ["strawberry", "grape", "watermelon", "giant_watermelon", "apple"]

static func init(s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "idle"
	e.satiety = 0
	e.t_kind = ""
	e.target_id = 0
	e.eat_at = 0.0
	e.rage_at = 0.0
	e.claw_at = 0.0
	e.think_at = s.time

static func validate(_s: RefCounted, e: Dictionary) -> bool:
	return STATES.has(str(e.state)) and KINDS.has(str(e.t_kind))

static func damage_mult(s: RefCounted, e: Dictionary, _k: String, _f: Variant) -> float:
	return s.pf(e, "sleep_mult") if e.state == "sleep" else 1.0

static func _rage(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	e.t_kind = ""
	e.target_id = 0
	if e.state == "sleep":
		e.satiety = 0
	s.set_state(e, "enraged", 0.0)
	e.rage_at = s.time + s.pf(e, "windup_s")
	e.claw_at = e.rage_at
	s.fx(ev, "bear_rage", e.pos, e)

static func on_hit(s: RefCounted, e: Dictionary, kind: String, _f: Variant, _d: float, ev: Array[Dictionary]) -> void:
	if kind == "water" or kind == "spine":
		return
	if e.state == "sleep":
		if float(e.hp) < s.pf(e, "wake_hp_frac") * float(e.max_hp):
			_rage(s, e, ev)   # 攻撃されても起きないが、HPが半分を切ると起きて怒る
	elif e.state != "enraged":
		_rage(s, e, ev)

static func _hive_list(s: RefCounted, e: Dictionary) -> Array:
	var out: Array = []
	for m: Dictionary in s.enemies:
		if m.alive and m.kind == "honeybee_hive" and Vector2(m.pos).distance_to(e.home) <= s.territory_px(e):
			out.append(m)
	return out

static func _pick(s: RefCounted, e: Dictionary) -> bool:
	var tg: Array = s.tags_of(e)
	var terr: float = s.territory_px(e)
	# 1. リンゴの落果(縄張り+10m以内。安定地域の落果は除外済み)
	var best_f: Dictionary = {}
	var bd: float = INF
	for f: Dictionary in s.crops.fruit_list():
		if s.host.is_stable_cell(f.cell):
			continue
		var d: float = e.pos.distance_to(f.pos)
		if Vector2(e.home).distance_to(f.pos) <= terr + 100.0 and d < bd:
			bd = d
			best_f = f
	if not best_f.is_empty():
		e.t_kind = "fruit"
		e.target_id = int(best_f.id)
		return true
	# 2. ミツバチの巣
	var best_h: Dictionary = {}
	bd = INF
	for m: Dictionary in _hive_list(s, e):
		var d2: float = e.pos.distance_to(m.pos)
		if d2 < bd:
			bd = d2
			best_h = m
	if not best_h.is_empty():
		e.t_kind = "hive"
		e.target_id = int(best_h.id)
		return true
	# 3. 果実の植物
	var best_c: Dictionary = {}
	bd = INF
	for c: Dictionary in s.crops.crops:
		if not FRUIT_PLANTS.has(str(c.kind)) or not bool(c.mature) or not s.crops.crop_targetable_by(tg, int(c.id)):
			continue
		if s.crop_dist(e.home, c) > terr:
			continue
		var d3: float = s.crop_dist(e.pos, c)
		if d3 < bd:
			bd = d3
			best_c = c
	if not best_c.is_empty():
		e.t_kind = "crop"
		e.target_id = int(best_c.id)
		return true
	return false

## 現在の狙いの位置と、そこまでの届く距離。なければ null
static func _goal(s: RefCounted, e: Dictionary) -> Variant:
	match str(e.t_kind):
		"fruit":
			for f: Dictionary in s.crops.fruit_list():
				if int(f.id) == int(e.target_id):
					return f.pos
		"hive":
			var m: Dictionary = s.ref(int(e.target_id))
			if not m.is_empty() and bool(m.alive):
				return Vector2(m.pos)
		"crop":
			var c: Dictionary = s.crops.get_crop(int(e.target_id))
			if not c.is_empty():
				return s.crop_center(c)
	return null

static func _gain(s: RefCounted, e: Dictionary, key: String) -> void:
	e.satiety = int(e.satiety) + int(s.pf(e, key))
	e.t_kind = ""
	e.target_id = 0
	e.state = "return" if int(e.satiety) >= int(s.pf(e, "full")) else "idle"

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	var lim: Dictionary = {"limit_px": s.territory_px(e) + 120.0}
	match str(e.state):
		"idle":
			if int(e.satiety) >= int(s.pf(e, "full")):
				e.state = "return"
				return
			if s.due(float(e.think_at)):
				e.think_at = s.time + s.pf(e, "think_s")
				if _pick(s, e):
					e.state = "approach"
					return
			s.wander(e, dt, ev, s.speed_px(e) * 0.5, 60.0)
		"approach":
			var g: Variant = _goal(s, e)
			if g == null:
				e.t_kind = ""
				e.state = "idle"
				return
			var reach: float = s.radius_px(e) + 3.0
			var dist: float = e.pos.distance_to(Vector2(g))
			if str(e.t_kind) == "crop":
				dist = s.crop_dist(e.pos, s.crops.get_crop(int(e.target_id)))
			elif str(e.t_kind) == "hive":
				dist = maxf(0.0, dist - 6.0)
			if dist <= reach:
				e.state = "eat"
				e.eat_at = s.time + (s.pf(e, "fruit_eat_s") if str(e.t_kind) == "fruit" else (s.pf(e, "hive_interval_s") if str(e.t_kind) == "hive" else s.pf(e, "crop_interval_s")))
				return
			s.step_move(e, Vector2(g) - e.pos, s.speed_px(e), dt, ev, lim)
			if bool(e.blocked):
				e.t_kind = ""
				e.state = "idle"
		"eat":
			var g2: Variant = _goal(s, e)
			if g2 == null:
				e.t_kind = ""
				e.state = "idle"
				return
			if str(e.t_kind) == "hive":
				var hv: Dictionary = s.ref(int(e.target_id))
				# 巣をかじっている間、ミツバチの群れはクマを刺す(怒りの相手がクマになる。主人公に怒っている間は変えない)
				if hv.state == "calm" or str(hv.ttype) == "enemy":
					Hive.anger(s, hv, "enemy", int(e.id), ev)
			if s.due(float(e.eat_at)):
				match str(e.t_kind):
					"fruit":
						ev.append_array(s.crops.consume_fruit(int(e.target_id), int(e.id)))
						_gain(s, e, "sat_fruit")
					"hive":
						e.eat_at = float(e.eat_at) + s.pf(e, "hive_interval_s")
						var hv2: Dictionary = s.ref(int(e.target_id))
						s.deal_raw(hv2, s.pf(e, "hive_damage"), "bear", ev)
						if not bool(hv2.alive):
							_gain(s, e, "sat_hive")
					"crop":
						e.eat_at = float(e.eat_at) + s.pf(e, "crop_interval_s")
						var cid: int = int(e.target_id)
						s.hurt_crop(e, cid, s.pf(e, "crop_damage"), ev)
						if bool(e.alive) and s.crops.get_crop(cid).is_empty():
							_gain(s, e, "sat_crop")
		"return":
			if s.walk_to(e, e.home, s.speed_px(e), dt, ev, 3.0, lim) or bool(e.blocked):
				s.set_state(e, "sleep", 0.0)
				s.fx(ev, "bear_sleep", e.pos, e)
		"sleep":
			pass
		"enraged":
			var h: Dictionary = s.hero_t()
			if h.is_empty() or e.pos.distance_to(h.pos) > s.pm(e, "calm_m"):
				e.state = "return" if int(e.satiety) >= int(s.pf(e, "full")) else "idle"   # 主人公が18mより離れると落ち着く
				return
			e.face = (h.pos - e.pos).normalized() if e.pos.distance_to(h.pos) > 0.1 else e.face
			if not s.due(float(e.rage_at)):
				return
			if s.in_reach(e, h):
				if s.due(float(e.claw_at)):
					s.dmg_target(e, h, s.pf(e, "claw_damage"), ev)
					e.claw_at = s.time + s.pf(e, "claw_interval_s")
					s.fx(ev, "claw", e.pos, e)
			else:
				s.step_move(e, h.pos - e.pos, s.pm(e, "rage_mps"), dt, ev, {"limit_px": s.pm(e, "calm_m") + s.territory_px(e)})

static func on_flee(s: RefCounted, e: Dictionary) -> void:
	e.t_kind = ""
	if e.state != "sleep" and e.state != "enraged":
		e.state = "idle"
	e.until = s.time
