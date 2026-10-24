extends "res://scripts/content_pack/enemies/base.gd"
## E24 カバ。状態: float(水中で浮かぶ) / land(陸を歩いて狙いへ) / eat / windup / charge / retreat(水へ戻る) / rest(水中で休む)
## 水中の背中は当たるが×0.5。陸へは水際から land_reach_m までしか上がらない。陸で累計15ダメージを受けると水へ戻り、10秒休んで再上陸する。
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")
const STATES: Array = ["float", "land", "eat", "windup", "charge", "retreat", "rest"]
const KINDS: Array = ["", "hero", "crop", "grass", "fruit"]

static func init(s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "float"
	e.land_dmg = 0.0
	e.t_kind = ""
	e.target_crop = 0
	e.t_cell = Vector2i.ZERO
	e.fruit_id = 0
	e.eat_at = 0.0
	e.think_at = s.time
	e.charge_dir = Vector2.DOWN
	e.hit_ids = []
	e.charge_cd = 0.0

static func validate(_s: RefCounted, e: Dictionary) -> bool:
	return STATES.has(str(e.state)) and KINDS.has(str(e.t_kind)) and typeof(e.t_cell) == TYPE_VECTOR2I and typeof(e.charge_dir) == TYPE_VECTOR2

static func in_water(s: RefCounted, e: Dictionary) -> bool:
	return s.host.is_water(Grid.cell_of_pos(e.pos))

static func damage_mult(s: RefCounted, e: Dictionary, _k: String, _f: Variant) -> float:
	return s.pf(e, "water_mult") if in_water(s, e) else 1.0

static func _opts(s: RefCounted, e: Dictionary) -> Dictionary:
	return {"habitat": "amphi", "shore_px": s.pm(e, "land_reach_m"), "limit_px": s.territory_px(e)}

static func on_hit(s: RefCounted, e: Dictionary, _k: String, _f: Variant, dealt: float, ev: Array[Dictionary]) -> void:
	if in_water(s, e):
		return
	e.land_dmg = float(e.land_dmg) + dealt
	if float(e.land_dmg) >= s.pf(e, "retreat_damage") - 1e-6 and e.state != "retreat" and e.state != "rest":
		e.t_kind = ""
		e.state = "retreat"
		s.fx(ev, "hippo_retreat", e.pos, e)

## 水際から land_reach_m 以内で、狙いを探す(主人公 → 落果 → 株 → 草)。見つかれば land へ。
static func _find(s: RefCounted, e: Dictionary) -> bool:
	var reach: float = s.pm(e, "land_reach_m")
	var seek: float = s.territory_px(e)
	var h: Dictionary = s.hero_t()
	if not h.is_empty() and e.pos.distance_to(h.pos) <= s.pm(e, "hero_m") and s.near_water(h.pos, reach) and not s.host.is_water(Grid.cell_of_pos(h.pos)) \
			and s.due(float(e.charge_cd)):
		e.t_kind = "hero"
		e.state = "land"
		return true
	# 落果(草食タグ): 水際から8m以内のもの
	var tg: Array = s.tags_of(e)
	var fb: Dictionary = s.crops.nearest_attracting_fruit(tg, e.pos, seek)
	if not fb.is_empty() and s.near_water(fb.pos, reach):
		e.t_kind = "fruit"
		e.fruit_id = int(fb.id)
		e.state = "land"
		return true
	var best: Dictionary = {}
	var bd: float = INF
	for c: Dictionary in s.crops.crops:
		if not s.crops.crop_targetable_by(tg, int(c.id)):
			continue
		var d: float = s.crop_dist(e.pos, c)
		if d <= seek and d < bd and s.near_water(s.crop_center(c), reach + 4.0 * maxf(c.size.x, c.size.y)):
			best = c
			bd = d
	if not best.is_empty():
		e.t_kind = "crop"
		e.target_crop = int(best.id)
		e.state = "land"
		return true
	# 成熟した草(段階を1つ戻す)
	var c0: Vector2i = Grid.cell_of_pos(e.pos)
	var n: int = 25
	var bg: Variant = null
	var bgd: float = INF
	for dy: int in range(-n, n + 1):
		for dx: int in range(-n, n + 1):
			var cc: Vector2i = c0 + Vector2i(dx, dy)
			if not s.host.in_bounds(cc) or s.host.is_water(cc) or s.host.grass_stage(cc) != "grass" or s.host.is_stable_cell(cc):
				continue
			var p: Vector2 = Grid.center_of_cell(cc)
			var dd: float = p.distance_to(e.pos)
			if dd < bgd and dd <= seek and s.near_water(p, reach):
				bgd = dd
				bg = cc
	if bg != null:
		e.t_kind = "grass"
		e.t_cell = bg
		e.state = "land"
		return true
	return false

static func _goal(s: RefCounted, e: Dictionary) -> Variant:
	match str(e.t_kind):
		"hero":
			var h: Dictionary = s.hero_t()
			if h.is_empty() or e.pos.distance_to(h.pos) > s.pm(e, "hero_m") * 3.0 or s.host.is_water(Grid.cell_of_pos(h.pos)):
				return null
			return h.pos
		"crop":
			var c: Dictionary = s.crops.get_crop(int(e.target_crop))
			return null if c.is_empty() else s.crop_center(c)
		"grass":
			return Grid.center_of_cell(e.t_cell) if s.host.grass_stage(e.t_cell) == "grass" else null
		"fruit":
			for f: Dictionary in s.crops.fruit_list():
				if int(f.id) == int(e.fruit_id):
					return f.pos
			return null
	return null

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	var h: Dictionary = s.hero_t()
	match str(e.state):
		"float":
			if s.due(float(e.think_at)):
				e.think_at = s.time + s.pf(e, "think_s")
				if _find(s, e):
					return
			s.wander(e, dt, ev, s.speed_px(e) * 0.4, s.pm(e, "wander_m"))
		"land":
			# 陸で主人公が4m以内 → 突進の予兆
			if not h.is_empty() and not in_water(s, e) and e.pos.distance_to(h.pos) <= s.pm(e, "hero_m") and s.due(float(e.charge_cd)):
				e.face = (h.pos - e.pos).normalized()
				e.charge_dir = e.face
				s.set_state(e, "windup", s.pf(e, "windup_s"))
				s.fx(ev, "windup", e.pos, e)
				return
			var g: Variant = _goal(s, e)
			if g == null:
				e.t_kind = ""
				if not _find(s, e):
					e.state = "retreat"
				return
			if str(e.t_kind) == "hero":
				s.step_move(e, Vector2(g) - e.pos, s.speed_px(e), dt, ev, _opts(s, e))
				if bool(e.blocked):
					e.t_kind = ""
					e.state = "retreat"
				return
			var reach_d: float = s.radius_px(e) + 3.0
			var target_d: float = e.pos.distance_to(Vector2(g))
			if str(e.t_kind) == "crop":
				var cc: Dictionary = s.crops.get_crop(int(e.target_crop))
				target_d = s.crop_dist(e.pos, cc)
			if target_d <= reach_d:
				e.state = "eat"
				e.eat_at = s.time + (s.pf(e, "fruit_eat_s") if str(e.t_kind) == "fruit" else s.pf(e, "eat_interval_s"))
				return
			s.step_move(e, Vector2(g) - e.pos, s.speed_px(e), dt, ev, _opts(s, e))
			if bool(e.blocked):
				e.t_kind = ""
				e.state = "retreat"
		"eat":
			var g2: Variant = _goal(s, e)
			if g2 == null:
				e.state = "land"
				e.t_kind = ""
				if not _find(s, e):
					e.state = "retreat"
				return
			if s.due(float(e.eat_at)):
				match str(e.t_kind):
					"crop":
						e.eat_at = float(e.eat_at) + s.pf(e, "eat_interval_s")
						s.hurt_crop(e, int(e.target_crop), s.pf(e, "eat_damage"), ev)
					"grass":
						e.eat_at = float(e.eat_at) + s.pf(e, "grass_interval_s")
						ev.append({"type": "ground_stage", "cell": e.t_cell, "stage": "sprout", "cause": "hippo"})   # 成熟した草の段階を1つ戻す
						s.fx(ev, "grass_eaten", Grid.center_of_cell(e.t_cell), e)
						e.t_kind = ""
						e.state = "land"
						if not _find(s, e):
							e.state = "retreat"
					"fruit":
						ev.append_array(s.crops.consume_fruit(int(e.fruit_id), int(e.id)))
						e.fruit_id = 0
						e.t_kind = ""
						e.state = "land"
						if not _find(s, e):
							e.state = "retreat"
		"windup":
			if not h.is_empty():
				e.charge_dir = (h.pos - e.pos).normalized() if e.pos.distance_to(h.pos) > 0.1 else e.charge_dir
				e.face = e.charge_dir
			if s.due(float(e.until)):
				e.hit_ids = []
				s.set_state(e, "charge", s.pf(e, "charge_s"))
		"charge":
			var o: Dictionary = _opts(s, e)
			o["straight"] = true
			var n2: int = int(ceil(s.pm(e, "charge_mps") * dt / 2.0))
			for _i: int in range(n2):
				s.step_move(e, e.charge_dir, s.pm(e, "charge_mps"), dt / float(n2), ev, o)
				for t: Dictionary in s.all_targets():
					var key: String = str(t.type) + str(t.id)
					if e.pos.distance_to(t.pos) <= s.radius_px(e) + 4.0 and not e.hit_ids.has(key):
						e.hit_ids.append(key)
						s.dmg_target(e, t, s.pf(e, "charge_damage"), ev)
				if bool(e.blocked):
					break
			if bool(e.blocked) or s.due(float(e.until)):
				e.charge_cd = s.time + s.pf(e, "charge_cd_s")
				e.state = "land"
				e.t_kind = ""
		"retreat":
			if in_water(s, e):
				s.set_state(e, "rest", s.pf(e, "rest_s"))
				e.t_kind = ""
				return
			var wp: Variant = s.nearest_water_pos(e.pos, 200.0)
			if wp == null:
				s.set_state(e, "rest", s.pf(e, "rest_s"))
				return
			s.step_move(e, Vector2(wp) - e.pos, s.pm(e, "retreat_mps"), dt, ev, {"habitat": "amphi", "shore_px": 0.0, "straight": true})
		"rest":
			if s.due(float(e.until)):
				e.state = "float"
				e.land_dmg = 0.0
				e.think_at = s.time

static func on_flee(s: RefCounted, e: Dictionary) -> void:
	e.state = "float"
	e.until = s.time
