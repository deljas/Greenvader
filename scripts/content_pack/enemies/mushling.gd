extends "res://scripts/content_pack/enemies/base.gd"
## E03 マッシュリング 親(mushling_parent) / 子(mushling_child)。
## 子: idle / call / harass。親: idle / rush / chase / return。怒りは rage_until(時刻)で持つ。

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.next_call = 0.0
	e.next_gas = 0.0
	e.aggro = false
	e.rage_until = 0.0
	e.rush_to = e.pos
	e.rush_until = 0.0
	e.state = "idle"

static func _rage(s: RefCounted, e: Dictionary) -> bool:
	return not s.due(float(e.rage_until))

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	if str(e.kind) == "mushling_child":
		_child(s, e, dt, ev)
	else:
		_parent(s, e, dt, ev)

# ---------------------------------------------------------------- 子
static func _child(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	var h: Dictionary = s.hero_t()
	if not h.is_empty():
		var d: float = e.pos.distance_to(h.pos)
		if d <= s.pm(e, "trigger_m"):
			e.aggro = true
		elif d > s.pm(e, "lose_m"):
			e.aggro = false
	else:
		e.aggro = false
	match str(e.state):
		"idle":
			if bool(e.aggro):
				if s.due(float(e.next_call)):
					_call(s, e, ev)
				else:
					e.state = "harass"
				return
			var par: Dictionary = s.ref(int(e.parent_id))
			var center: Vector2 = par.pos if (not par.is_empty() and bool(par.alive)) else Vector2(e.home)
			s.wander(e, dt, ev, s.speed_px(e) * 0.6, s.pm(e, "wander_m"), center)
		"call":
			if s.due(float(e.until)):
				e.state = "harass"
				e.next_gas = s.time
		"harass":
			if not bool(e.aggro):
				e.state = "idle"
				return
			if s.due(float(e.next_call)):
				_call(s, e, ev)
				return
			if s.due(float(e.next_gas)):
				e.next_gas = s.time + s.pf(e, "gas_interval_s")
				s.add_gas(e.pos, int(e.id), s.pm(e, "gas_radius_m"), s.pf(e, "gas_s"), s.pf(e, "gas_dps"))
				s.fx(ev, "gas", e.pos, e)
			if e.pos.distance_to(h.pos) > s.pm(e, "keep_m"):
				s.step_move(e, h.pos - e.pos, s.speed_px(e), dt, ev)

static func _call(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	e.next_call = s.time + s.pf(e, "call_cooldown_s")
	s.set_state(e, "call", s.pf(e, "call_s"))
	s.fx(ev, "call", e.pos, e)
	ev.append({"type": "mushling_call", "enemy_id": e.id, "group_id": e.group_id, "pos": e.pos})
	for p: Dictionary in s.enemies:
		if p.alive and p.kind == "mushling_parent" and int(p.group_id) == int(e.group_id) \
				and p.pos.distance_to(e.pos) <= s.pm(p, "rush_range_m") and not _rage(s, p):
			p.state = "rush"
			p.rush_to = e.pos
			p.rush_until = s.time + 20.0

# ---------------------------------------------------------------- 親
static func _parent(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	var rage: bool = _rage(s, e)
	var spd: float = s.speed_px(e) * (s.pf(e, "rage_speed_mult") if rage else 1.0)
	var sight: float = s.pm(e, "rage_sight_m") if rage else s.pm(e, "sight_m")
	var leash: float = s.pm(e, "rage_leash_m") if rage else s.pm(e, "leash_m")
	var t: Dictionary = s.nearest_target(e, sight, false)
	var home_d: float = e.pos.distance_to(e.home)
	match str(e.state):
		"idle":
			if not t.is_empty() and home_d <= leash:
				e.state = "chase"
				return
			if rage and home_d > 8.0:
				e.state = "return"
				return
			s.wander(e, dt, ev, spd * 0.6, s.pm(e, "wander_m"))
		"rush":
			if not t.is_empty() and not rage:
				e.state = "chase"
				return
			if rage or s.due(float(e.rush_until)) or s.walk_to(e, e.rush_to, s.pm(e, "rush_mps"), dt, ev, 25.0):
				e.state = "idle"
				e.wp_valid = false
		"chase":
			if t.is_empty() or home_d > leash:
				e.state = "return"
				return
			if s.in_reach(e, t):
				var interval: float = s.pf(e, "rage_interval_s") if rage else s.pf(e, "melee_interval_s")
				if s.due(float(e.melee_at)):
					var dmg: float = s.pf(e, "melee_damage") * (s.pf(e, "rage_dmg_mult") if rage else 1.0)
					s.dmg_target(e, t, dmg, ev)
					e.melee_at = s.time + interval
			else:
				s.step_move(e, t.pos - e.pos, spd, dt, ev)
		"return":
			if not t.is_empty() and home_d <= leash:
				e.state = "chase"
				return
			if s.walk_to(e, e.home, spd, dt, ev, 20.0):
				e.state = "idle"
				e.wp_valid = false

## 子の最終撃破で、同じ組の親が25秒怒る(怒り中にさらに倒されると25秒に戻る)
static func on_defeat(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	if str(e.kind) != "mushling_child":
		return
	for p: Dictionary in s.enemies:
		if p.alive and p.kind == "mushling_parent" and int(p.group_id) == int(e.group_id):
			p.rage_until = s.time + s.pf(p, "rage_s")
			if p.state == "idle" or p.state == "return" or p.state == "rush":
				p.state = "chase"
			s.fx(ev, "rage", p.pos, p)
