extends "res://scripts/content_pack/enemies/base.gd"
## E14 ミツバチの巣(honeybee_hive)と働き蜂の群れ(honeybee_swarm)。どちらも中立(安定判定に数えない、報酬なし)。
## 巣: calm / angry。群れ: orbit / chase。怒りは巣が持つ(anger_until、相手 ttype/tid)。受粉は enemy_system.pollinator_list() が生存中の巣を返す。
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")
const ORBIT_PX: float = 12.0

static func init(s: RefCounted, e: Dictionary, o: Dictionary) -> void:
	if str(e.kind) == "honeybee_hive":
		e.state = "calm"
		e.anger_until = 0.0
		e.ttype = ""
		e.tid = 0
		e.near_t = 0.0
		e.respawn_at = -1.0
		_make_swarm(s, e, str(e.origin))
	else:
		e.state = "orbit"
		e.hive_id = int(o.get("hive_id", 0))
		e.ang = fmod(float(e.id) * 1.7, TAU)

static func _make_swarm(s: RefCounted, hive: Dictionary, origin: String) -> void:
	s.spawn("honeybee_swarm", Vector2(hive.pos) + Vector2(0, -ORBIT_PX), origin, {"hive_id": int(hive.id), "home": hive.pos, "tier": str(hive.tier)})

static func _hive_of(s: RefCounted, e: Dictionary) -> Dictionary:
	if str(e.kind) == "honeybee_hive":
		return e
	return s.ref(int(e.hive_id))

static func _swarm_alive(s: RefCounted, hive: Dictionary) -> bool:
	for m: Dictionary in s.enemies:
		if m.alive and m.kind == "honeybee_swarm" and int(m.hive_id) == int(hive.id):
			return true
	return false

## 怒らせる。ttype/tid は刺す相手(主人公 "hero",0 / おたすけ植物 "helper",id)。怒り中の再刺激は期間を延ばす。
static func anger(s: RefCounted, hive: Dictionary, ttype: String, tid: int, ev: Array[Dictionary]) -> void:
	if hive.state != "angry":
		s.fx(ev, "bee_anger", hive.pos, hive)
	hive.state = "angry"
	hive.anger_until = s.time + s.pf(hive, "anger_s")
	hive.ttype = ttype
	hive.tid = tid

## 攻撃(爆風を含む)を受けたとき。撃ったのがおたすけ植物(kind=="helper")なら最も近いおたすけ植物、それ以外は主人公。
static func _provoke(s: RefCounted, e: Dictionary, kind: String, from: Variant, ev: Array[Dictionary]) -> void:
	var hive: Dictionary = _hive_of(s, e)
	if hive.is_empty() or not bool(hive.alive):
		return
	if kind == "helper":
		var origin: Vector2 = Vector2(from) if typeof(from) == TYPE_VECTOR2 else Vector2(hive.pos)
		var best: Dictionary = {}
		var bd: float = 1e18
		for t: Dictionary in s.all_targets():
			if t.type == "helper" and origin.distance_to(t.pos) < bd:
				best = t
				bd = origin.distance_to(t.pos)
		if not best.is_empty():
			anger(s, hive, "helper", int(best.id), ev)
			return
	anger(s, hive, "hero", 0, ev)

static func calc_damage(s: RefCounted, e: Dictionary, amount: float, kind: String, from: Variant, ev: Array[Dictionary]) -> float:
	_provoke(s, e, kind, from, ev)
	return amount

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	if str(e.kind) == "honeybee_hive":
		_hive(s, e, dt, ev)
	else:
		_swarm(s, e, dt, ev)

static func _hive(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	if e.state == "angry" and s.due(float(e.anger_until)):
		e.state = "calm"
		e.ttype = ""
		e.tid = 0
	var h: Dictionary = s.hero_t()
	if not h.is_empty() and h.pos.distance_to(e.pos) <= s.pm(e, "near_m"):
		e.near_t = float(e.near_t) + dt
	else:
		e.near_t = 0.0
	if e.state == "calm" and float(e.near_t) >= s.pf(e, "near_s") - 1e-6:
		anger(s, e, "hero", 0, ev)
	if float(e.respawn_at) >= 0.0 and s.due(float(e.respawn_at)) and not _swarm_alive(s, e):
		e.respawn_at = -1.0
		_make_swarm(s, e, "produced")

static func _find(s: RefCounted, ttype: String, tid: int) -> Dictionary:
	if ttype == "enemy":   # 第2弾: 巣をかじるハチミツグマ
		var m: Dictionary = s.ref(tid)
		if not m.is_empty() and bool(m.alive):
			return {"type": "enemy", "id": tid, "pos": Vector2(m.pos)}
		return {}
	for t: Dictionary in s.all_targets():
		if str(t.type) == ttype and int(t.id) == tid:
			return t
	return {}

static func _fly(s: RefCounted, e: Dictionary, goal: Vector2, dt: float) -> void:
	var d: float = e.pos.distance_to(goal)
	var step: float = minf(s.speed_px(e) * dt, d)
	if d > 1e-6:
		var np: Vector2 = e.pos + (goal - e.pos) / d * step
		if s.host.in_bounds(Grid.cell_of_pos(np)):
			e.pos = np
			e.last_cell = Grid.cell_of_pos(np)

static func _swarm(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	var hive: Dictionary = _hive_of(s, e)
	if hive.is_empty() or not bool(hive.alive):
		return
	var t: Dictionary = {}
	if hive.state == "angry":
		t = _find(s, str(hive.ttype), int(hive.tid))
		if t.is_empty():
			hive.anger_until = s.time
	if not t.is_empty():
		e.state = "chase"
		_fly(s, e, t.pos, dt)
		var lim: float = s.pm(hive, "chase_m")
		if e.pos.distance_to(hive.pos) > lim:
			e.pos = Vector2(hive.pos) + (e.pos - hive.pos).normalized() * lim
			e.last_cell = Grid.cell_of_pos(e.pos)
		if s.in_reach(e, t) and s.due(float(e.melee_at)):
			e.melee_at = s.time + s.pf(hive, "sting_interval_s")
			s.dmg_target(e, t, s.pf(hive, "sting_damage"), ev)
			s.fx(ev, "sting", e.pos, e)
	else:
		e.state = "orbit"
		e.ang = float(e.ang) + (s.speed_px(e) * 0.5 / ORBIT_PX) * dt
		var goal: Vector2 = Vector2(hive.pos) + Vector2.from_angle(float(e.ang)) * ORBIT_PX
		_fly(s, e, goal, dt)

static func on_defeat(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	if str(e.kind) == "honeybee_swarm":
		var hive: Dictionary = s.ref(int(e.hive_id))
		if not hive.is_empty() and bool(hive.alive):
			hive.respawn_at = s.time + s.pf(e, "respawn_s")
	else:
		# 巣が壊れると群れは散る。何も得られない(報酬0、受粉は pollinator_list から消える)
		for m: Dictionary in s.enemies:
			if m.alive and m.kind == "honeybee_swarm" and int(m.hive_id) == int(e.id):
				m.alive = false
				s.fx(ev, "swarm_gone", m.pos, m)

static func on_flee(_s: RefCounted, _e: Dictionary) -> void:
	pass
