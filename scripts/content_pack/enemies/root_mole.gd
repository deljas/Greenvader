extends "res://scripts/content_pack/enemies/base.gd"
## E22 ネッコモグラ。状態: burrow(地中で待機) / move(地中を進む) / gnaw(株の真下でかじる) / pop(水で追い出され、地上へ出るまで1秒) / peek(株を倒して顔を出す) / stunned(目を回す)
## 地中(burrow / move / gnaw / pop)は当たらない。マップの検知は最新の盛り土の位置(盛り土は0.4mごと、10秒で消える)。
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")
const STATES: Array = ["burrow", "move", "gnaw", "pop", "peek", "stunned"]
const ROOT_KINDS: Array = ["potato", "kudzu"]   # 根の多い株

static func init(s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "burrow"
	e.mounds = []
	e.t_kind = ""             # "" / "crop" / "root"
	e.target_crop = 0
	e.t_cell = Vector2i.ZERO
	e.tpos = e.pos
	e.acc = 0.0
	e.gnaw_at = 0.0
	e.think_at = s.time

static func _up(e: Dictionary) -> bool:
	return e.state == "peek" or e.state == "stunned"

static func hittable(_s: RefCounted, e: Dictionary) -> bool:
	return _up(e)

## 地上へ出ている間だけ分類タグの作用を受ける
static func tags(s: RefCounted, e: Dictionary) -> Array:
	return s.def_of(e).get("tags", []) if _up(e) else []

static func damage_mult(s: RefCounted, e: Dictionary, _k: String, _f: Variant) -> float:
	return s.pf(e, "stunned_mult") if e.state == "stunned" else 1.0

static func detect_pos(_s: RefCounted, e: Dictionary) -> Variant:
	if _up(e):
		return e.pos
	var m: Array = e.mounds
	if m.is_empty():
		return null
	return Vector2((m[m.size() - 1] as Dictionary).pos)

static func validate(_s: RefCounted, e: Dictionary) -> bool:
	if not STATES.has(str(e.state)):
		return false
	for m: Variant in e.mounds:
		if typeof(m) != TYPE_DICTIONARY or typeof((m as Dictionary).get("pos")) != TYPE_VECTOR2 or not ((m as Dictionary).get("until") is float or (m as Dictionary).get("until") is int):
			return false
	return typeof(e.t_cell) == TYPE_VECTOR2I and typeof(e.tpos) == TYPE_VECTOR2

## 水が0.8m以内に当たると1秒後に飛び出す(地中にいる間だけ)
static func on_water_near(s: RefCounted, e: Dictionary, pos: Vector2, radius: float, ev: Array[Dictionary]) -> void:
	var st: String = str(e.state)
	if st != "burrow" and st != "move" and st != "gnaw":
		return
	if Vector2(e.pos).distance_to(pos) <= radius + s.pm(e, "water_m"):
		e.t_kind = ""
		e.target_crop = 0
		s.set_state(e, "pop", s.pf(e, "pop_delay_s"))
		s.fx(ev, "mole_water", e.pos, e)

## 地中の移動。進んだ距離ごとに盛り土を残す。安定地域・範囲外へは入らない。
static func _dig(s: RefCounted, e: Dictionary, goal: Vector2, dt: float) -> void:
	var d: float = e.pos.distance_to(goal)
	if d < 1e-6:
		return
	var step: float = minf(s.speed_px(e) * dt, d)
	var np: Vector2 = e.pos + (goal - e.pos) / d * step
	var cell: Vector2i = Grid.cell_of_pos(np)
	if not s.host.in_bounds(cell) or s.host.is_stable_cell(cell):
		e.t_kind = ""
		e.state = "burrow"
		return
	e.pos = np
	e.last_cell = cell
	e.acc = float(e.acc) + step
	var every: float = s.pf(e, "mound_px")
	var back: Vector2 = (goal - np).normalized() if goal.distance_to(np) > 1e-6 else (goal - e.pos).normalized()
	while float(e.acc) >= every - 1e-6:
		e.acc = float(e.acc) - every
		# ちょうど 0.4m ごとの位置に置く(刻みの途中で超えた分だけ手前へ戻す)
		e.mounds.append({"pos": e.pos - back * float(e.acc), "until": s.time + s.pf(e, "mound_s")})

static func _pick(s: RefCounted, e: Dictionary) -> void:
	var tg: Array = s.def_of(e).get("tags", [])
	var terr: float = s.territory_px(e)
	var best_pri: Dictionary = {}
	var bd_pri: float = INF
	var best_other: Dictionary = {}
	var bd_other: float = INF
	for c: Dictionary in s.crops.crops:
		if not bool(c.mature) or not s.crops.crop_targetable_by(tg, int(c.id)):
			continue
		if s.crop_dist(e.home, c) > terr:
			continue
		var d: float = s.crop_dist(e.pos, c)
		if ROOT_KINDS.has(str(c.kind)):
			if d < bd_pri:
				bd_pri = d
				best_pri = c
		elif d < bd_other:
			bd_other = d
			best_other = c
	var best_root: Variant = null
	var bd_root: float = INF
	for rc: Vector2i in s.crops.root_cells():
		var owner: int = s.crops.root_owner(rc)
		if owner <= 0 or not s.crops.crop_targetable_by(tg, owner):
			continue
		var p: Vector2 = Grid.center_of_cell(rc)
		if p.distance_to(e.home) > terr:
			continue
		var d2: float = p.distance_to(e.pos)
		if d2 < bd_root:
			bd_root = d2
			best_root = rc
	# 根の多い株(ジャガイモ・クズの株と根のマス)を優先。近い方を選ぶ
	if not best_pri.is_empty() or best_root != null:
		if best_root != null and (best_pri.is_empty() or bd_root <= bd_pri):
			e.t_kind = "root"
			e.t_cell = best_root
			e.tpos = Grid.center_of_cell(best_root)
		else:
			e.t_kind = "crop"
			e.target_crop = int(best_pri.id)
			e.tpos = s.crop_center(best_pri)
		e.state = "move"
	elif not best_other.is_empty():
		e.t_kind = "crop"
		e.target_crop = int(best_other.id)
		e.tpos = s.crop_center(best_other)
		e.state = "move"

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	for m: Dictionary in e.mounds.duplicate():
		if s.due(float(m.until)):
			e.mounds.erase(m)
	var tg: Array = s.def_of(e).get("tags", [])
	match str(e.state):
		"burrow":
			if s.due(float(e.think_at)):
				e.think_at = s.time + s.pf(e, "think_s")
				_pick(s, e)
		"move":
			if str(e.t_kind) == "crop":
				var c: Dictionary = s.crops.get_crop(int(e.target_crop))
				if c.is_empty() or not bool(c.mature) or not s.crops.crop_targetable_by(tg, int(c.id)):
					e.state = "burrow"
					return
				e.tpos = s.crop_center(c)
				if s.crop_dist(e.pos, c) <= 1.0:
					s.set_state(e, "gnaw", 0.0)
					e.gnaw_at = s.time + s.pf(e, "gnaw_interval_s")
					return
			elif str(e.t_kind) == "root":
				var owner: int = s.crops.root_owner(e.t_cell)
				if owner <= 0:
					e.state = "burrow"
					return
				if e.pos.distance_to(e.tpos) <= 1.0:
					s.set_state(e, "gnaw", 0.0)
					e.gnaw_at = s.time + s.pf(e, "root_eat_s")
					return
			else:
				e.state = "burrow"
				return
			_dig(s, e, e.tpos, dt)
		"gnaw":
			if str(e.t_kind) == "crop":
				var c2: Dictionary = s.crops.get_crop(int(e.target_crop))
				if c2.is_empty() or not s.crops.crop_targetable_by(tg, int(c2.id)):
					e.state = "burrow"
					return
				if s.due(float(e.gnaw_at)):
					e.gnaw_at = float(e.gnaw_at) + s.pf(e, "gnaw_interval_s")
					s.hurt_crop(e, int(e.target_crop), s.pf(e, "gnaw_damage"), ev)
					if bool(e.alive) and s.crops.get_crop(int(e.target_crop)).is_empty():
						e.t_kind = ""
						s.set_state(e, "peek", s.pf(e, "peek_s"))   # 株を倒したら1秒だけ顔を出す
						s.fx(ev, "mole_peek", e.pos, e)
			elif str(e.t_kind) == "root":
				if s.crops.root_owner(e.t_cell) <= 0:
					e.state = "burrow"
					return
				if s.due(float(e.gnaw_at)):
					ev.append_array(s.crops.eat_root(e.t_cell))
					e.t_kind = ""
					e.state = "burrow"
			else:
				e.state = "burrow"
		"pop":
			if s.due(float(e.until)):
				s.set_state(e, "stunned", s.pf(e, "stunned_s"))
				s.fx(ev, "mole_pop", e.pos, e)
		"peek":
			if s.due(float(e.until)):
				e.state = "burrow"
				e.think_at = s.time
		"stunned":
			if s.due(float(e.until)):
				e.state = "burrow"
				e.think_at = s.time
				s.fx(ev, "mole_dive", e.pos, e)

static func on_flee(s: RefCounted, e: Dictionary) -> void:
	e.state = "burrow"
	e.until = s.time
