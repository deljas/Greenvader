extends "res://scripts/content_pack/enemies/base.gd"
## E17 ハキリアリ(leafcutter_ant)とアリ塚(ant_hill)。
## アリ: idle / walk / cut / carry / lost。アリ塚: dormant / active(活動条件は host.nest_active(pos, kind) の1か所だけ)。
## 行列の道筋 trail = [アリ塚の位置, 目標株の中心]。途中の1匹が倒されると後続は lost(うろうろ)になる。
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")

static func init(s: RefCounted, e: Dictionary, o: Dictionary) -> void:
	if str(e.kind) == "ant_hill":
		e.state = "dormant"
		e.next_spawn = s.time + s.pf(e, "spawn_interval_s")
	else:
		e.state = "idle"
		e.hill_id = int(o.get("hill_id", 0))
		e.target_crop = 0
		e.trail = []
		e.resume = "walk"
		e.lost_pos = e.pos

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	if str(e.kind) == "ant_hill":
		_hill(s, e)
	else:
		_ant(s, e, dt, ev)

static func produced_count(s: RefCounted, hill: Dictionary) -> int:
	var n: int = 0
	for m: Dictionary in s.enemies:
		if m.alive and m.kind == "leafcutter_ant" and int(m.hill_id) == int(hill.id) and m.origin == "produced":
			n += 1
	return n

static func _hill(s: RefCounted, e: Dictionary) -> void:
	var act: bool = bool(s.host.nest_active(e.pos, "ant_hill"))
	e.state = "active" if act else "dormant"
	if s.due(float(e.next_spawn)):
		e.next_spawn = s.time + s.pf(e, "spawn_interval_s")
		if act and produced_count(s, e) < int(s.pf(e, "max_active")):
			s.spawn("leafcutter_ant", Vector2(e.pos) + Vector2(0.0, 8.0), "produced", {"hill_id": int(e.id), "home": e.pos, "tier": str(e.tier)})

static func _hill_pos(s: RefCounted, e: Dictionary) -> Variant:
	var h: Dictionary = s.ref(int(e.hill_id))
	if h.is_empty() or not bool(h.alive):
		return null
	return Vector2(h.pos)

static func _ant(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	var lim: Dictionary = {"limit_px": s.territory_px(e)}
	match str(e.state):
		"idle":
			var c: Dictionary = s.nearest_crop(e, s.pm(e, "seek_m"), false)
			if not c.is_empty():
				e.target_crop = int(c.id)
				var hp: Variant = _hill_pos(s, e)
				e.trail = [Vector2(hp) if hp != null else Vector2(e.home), s.crop_center(c)]
				e.state = "walk"
				return
			var center: Vector2 = Vector2(e.home)
			s.wander(e, dt, ev, s.speed_px(e) * 0.6, 25.0, center)
		"walk":
			var c2: Dictionary = s.crops.get_crop(int(e.target_crop))
			if c2.is_empty() or not s.crops.crop_targetable_by(s.tags_of(e), int(c2.id)):
				e.state = "idle"
				return
			if s.crop_dist(e.pos, c2) <= s.radius_px(e) + 2.0:
				s.set_state(e, "cut", s.pf(e, "cut_s"))
				return
			s.step_move(e, s.crop_center(c2) - e.pos, s.speed_px(e), dt, ev, lim)
			if bool(e.blocked):
				e.state = "idle"
		"cut":
			var c3: Dictionary = s.crops.get_crop(int(e.target_crop))
			if c3.is_empty():
				e.state = "idle"
				return
			if s.due(float(e.until)):
				e.state = "carry"
				s.hurt_crop(e, int(e.target_crop), s.pf(e, "cut_damage"), ev)
		"carry":
			var hp2: Variant = _hill_pos(s, e)
			if hp2 == null:
				e.state = "idle"
				return
			if s.walk_to(e, Vector2(hp2), s.speed_px(e), dt, ev, 10.0, lim) or bool(e.blocked):
				e.state = "idle"
		"lost":
			s.wander(e, dt, ev, s.speed_px(e) * 0.6, 15.0, Vector2(e.lost_pos))
			if s.due(float(e.until)):
				e.wp_valid = false
				e.state = str(e.resume)

static func on_defeat(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	if str(e.kind) == "ant_hill":
		if str(e.origin) == "initial":
			# 小規模の巣相当。基礎値だけを載せ、距離階級の倍率などはホスト(共通基盤)が掛ける
			ev.append({"type": "reward", "enemy_id": e.id, "kind": e.kind, "amount": int(s.pf(e, "nest_reward_base")), "tier": e.tier, "pos": e.pos, "nest": "small"})
		return
	var st: String = str(e.state)
	if st != "walk" and st != "carry":
		return
	var hp: Variant = _hill_pos(s, e)
	if hp == null:
		return
	var dd: float = e.pos.distance_to(Vector2(hp))
	for m: Dictionary in s.enemies:
		if not m.alive or m.kind != "leafcutter_ant" or int(m.id) == int(e.id) or int(m.hill_id) != int(e.hill_id):
			continue
		if int(m.target_crop) != int(e.target_crop) or str(m.state) != st:
			continue
		var md: float = m.pos.distance_to(Vector2(hp))
		var behind: bool = md < dd if st == "walk" else md > dd
		if behind:
			m.resume = st
			m.lost_pos = m.pos
			m.wp_valid = false
			s.set_state(m, "lost", s.pf(m, "lost_s"))
			s.fx(ev, "ant_lost", m.pos, m)
