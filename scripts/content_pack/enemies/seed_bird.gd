extends "res://scripts/content_pack/enemies/base.gd"
## E06 タネクイドリ。状態: perch / flying / landing / feeding / takeoff / rest(休憩は perch のまま rest_until で表す)
## 飛行中(flying)は当たらない。着地中(landing/feeding)だけ小型タグ(ハエトリソウが捕まえる)。
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "perch"
	e.eaten = 0
	e.rest_until = 0.0
	e.think_at = 0.0
	e.eat_at = 0.0
	e.goal = e.pos
	e.target = Vector2i(-1, -1)
	e.has_target = false
	e.go_home = false

static func hittable(_s: RefCounted, e: Dictionary) -> bool:
	return e.state != "flying"

static func tags(s: RefCounted, e: Dictionary) -> Array:
	var t: Array = s.def_of(e).get("tags", []).duplicate()
	if e.state == "landing" or e.state == "feeding":
		t.append("small")
	return t

static func _is_food(s: RefCounted, c: Vector2i) -> bool:
	var st: String = s.host.grass_stage(c)
	return (st == "seed" or st == "sprout") and not s.host.is_stable_cell(c)

## 縄張り(家から10m)内で最も近い種・芽のマス。exclude は除外するマス。
static func find_target(s: RefCounted, e: Dictionary, exclude: Vector2i) -> Variant:
	var hc: Vector2i = Grid.cell_of_pos(e.home)
	var rc: int = int(ceil(s.territory_px(e) / Grid.CELL_PX))
	var best: Variant = null
	var bd: float = 1e18
	for dy: int in range(-rc, rc + 1):
		for dx: int in range(-rc, rc + 1):
			var c: Vector2i = hc + Vector2i(dx, dy)
			if c == exclude or not s.host.in_bounds(c) or not _is_food(s, c):
				continue
			var cp: Vector2 = Grid.center_of_cell(c)
			if cp.distance_to(e.home) > s.territory_px(e):
				continue
			var d: float = cp.distance_to(e.pos)
			if d < bd:
				bd = d
				best = c
	return best

static func _fly_to(s: RefCounted, e: Dictionary, goal: Vector2, dt: float, ev: Array[Dictionary]) -> bool:
	return s.walk_to(e, goal, s.speed_px(e), dt, ev, 1.5, {"habitat": "air", "ignore_repel": true})

static func _depart(s: RefCounted, e: Dictionary, exclude: Vector2i) -> void:
	var tgt: Variant = null
	if int(e.eaten) < int(s.pf(e, "max_eat")):
		tgt = find_target(s, e, exclude)
	if tgt == null:
		e.has_target = false
		e.goal = e.home
		e.go_home = true
	else:
		e.has_target = true
		e.target = tgt
		e.goal = Grid.center_of_cell(tgt)
		e.go_home = false
	e.state = "flying"

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	match str(e.state):
		"perch":
			if not s.due(float(e.rest_until)) or not s.due(float(e.think_at)):
				return
			e.think_at = s.time + s.pf(e, "think_s")
			if find_target(s, e, Vector2i(-1, -1)) != null:
				_depart(s, e, Vector2i(-1, -1))
		"flying":
			var arrived: bool = _fly_to(s, e, e.goal, dt, ev)
			if bool(e.blocked):
				e.has_target = false
				e.goal = e.home
				e.go_home = true
				return
			if arrived:
				if bool(e.go_home):
					e.state = "perch"
					if int(e.eaten) >= int(s.pf(e, "max_eat")):
						e.rest_until = s.time + s.pf(e, "rest_s")
						e.eaten = 0
				else:
					s.set_state(e, "landing", s.pf(e, "land_s"))
		"landing":
			if s.due(float(e.until)):
				e.state = "feeding"
				e.eat_at = s.time + s.pf(e, "eat_interval_s")
				s.capture_check(e, ev)
		"feeding":
			var h: Dictionary = s.hero_t()
			if not h.is_empty() and e.pos.distance_to(h.pos) <= s.pm(e, "scare_m"):
				s.set_state(e, "takeoff", s.pf(e, "takeoff_s"))
				return
			if bool(e.has_target) and e.pos.distance_to(e.goal) > 2.0:
				s.walk_to(e, e.goal, s.pm(e, "walk_mps"), dt, ev, 1.5, {"habitat": "air", "ignore_repel": true})
				return
			if s.due(float(e.eat_at)):
				e.eat_at = s.time + s.pf(e, "eat_interval_s")
				var cur: Vector2i = e.target
				if bool(e.has_target) and _is_food(s, cur):
					ev.append({"type": "ground_stage", "cell": cur, "stage": "wasteland", "cause": "seed_bird"})
					e.eaten = int(e.eaten) + 1
					s.fx(ev, "peck", e.pos, e)
				var nxt: Variant = null
				if int(e.eaten) < int(s.pf(e, "max_eat")):
					nxt = find_target(s, e, cur)
				if nxt == null:
					s.set_state(e, "takeoff", s.pf(e, "takeoff_s"))
					e.has_target = false
				elif Grid.center_of_cell(nxt).distance_to(e.pos) <= 20.0:
					e.target = nxt
					e.goal = Grid.center_of_cell(nxt)
				else:
					s.set_state(e, "takeoff", s.pf(e, "takeoff_s"))
		"takeoff":
			if s.due(float(e.until)):
				_depart(s, e, e.target)

## 着地中に攻撃が当たると飛び立つ
static func on_hit(s: RefCounted, e: Dictionary, _k: String, _f: Variant, _d: float, _ev: Array[Dictionary]) -> void:
	if e.state == "landing" or e.state == "feeding":
		s.set_state(e, "takeoff", s.pf(e, "takeoff_s"))

static func on_flee(_s: RefCounted, _e: Dictionary) -> void:
	pass
