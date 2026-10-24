extends "res://scripts/content_pack/enemies/base.gd"
## E07 ガラクタヤドカリ。状態: idle / approach / naked_run / wearing
## 殻のHPが先に減る(バズーカ×2)。殻が割れると裸(被ダメ×2)。ガラクタ置き場で3秒かけて新しい殻を背負う。
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")

static func init(s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.shell = true
	e.shell_hp = s.pf(e, "shell_hp")
	e.target_pile = 0
	e.skip = {}
	e.claw_at = 0.0
	e.retreat_until = 0.0
	e.retreat_from = e.pos
	e.stall = 0.0

static func calc_damage(s: RefCounted, e: Dictionary, amount: float, kind: String, _f: Variant, ev: Array[Dictionary]) -> float:
	if bool(e.shell):
		var a: float = amount * (s.pf(e, "shell_bazooka_mult") if kind == "bazooka" else 1.0)
		e.shell_hp = float(e.shell_hp) - a
		s.fx(ev, "shell_hit", e.pos, e)
		if float(e.shell_hp) <= 0.0:
			e.shell = false
			e.shell_hp = 0.0
			e.state = "naked_run"
			s.fx(ev, "shell_break", e.pos, e)
		return 0.0
	return amount * s.pf(e, "naked_mult")

static func _choose_pile(s: RefCounted, e: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = 1e18
	var h: Dictionary = s.hero_t()
	for p: Dictionary in s.piles:
		if int(p.stock) <= 0:
			continue
		if e.skip.has(str(p.id)) and not s.due(float(e.skip[str(p.id)])):
			continue
		if not h.is_empty() and h.pos.distance_to(p.pos) <= s.pm(e, "pile_skip_hero_m"):
			continue
		var d: float = e.pos.distance_to(p.pos)
		if d < bd:
			bd = d
			best = p
	return best

static func _nearest_pile_pos(s: RefCounted, e: Dictionary) -> Variant:
	var best: Variant = null
	var bd: float = 1e18
	for p: Dictionary in s.piles:
		var d: float = e.pos.distance_to(p.pos)
		if d < bd:
			bd = d
			best = p.pos
	return best

static func _fight(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary], naked: bool) -> bool:
	var t: Dictionary = s.pick_target(e, s.pm(e, "trigger_m"), s.pm(e, "trigger_m"), false)
	if t.is_empty():
		return false
	var sp: float = s.pm(e, "naked_mps") if naked else s.speed_px(e)
	if s.in_reach(e, t):
		if naked:
			if s.due(float(e.claw_at)):
				s.dmg_target(e, t, s.pf(e, "scratch_damage"), ev)
				e.claw_at = s.time + s.pf(e, "scratch_interval_s")
				e.retreat_until = s.time + s.pf(e, "scratch_retreat_s")
				e.retreat_from = t.pos
		elif s.due(float(e.claw_at)):
			s.dmg_target(e, t, s.pf(e, "claw_damage"), ev)
			e.claw_at = s.time + s.pf(e, "claw_interval_s")
	else:
		s.step_move(e, t.pos - e.pos, sp, dt, ev)
	return true

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	if e.state == "wearing":
		if s.due(float(e.until)):
			var p: Dictionary = s.get_pile(int(e.target_pile))
			e.shell = true
			e.shell_hp = s.pf(e, "shell_hp")
			e.state = "idle"
			s.fx(ev, "shell_wear", e.pos, e)
			if not p.is_empty():
				p.stock = int(p.stock) - 1
				if int(p.stock) <= 0:
					s.piles.erase(p)
					ev.append({"type": "junk_pile_removed", "pile_id": p.id, "pos": p.pos, "cell": Grid.cell_of_pos(p.pos)})
			e.target_pile = 0
		return
	if bool(e.shell):
		if _fight(s, e, dt, ev, false):
			e.state = "approach"
			return
		e.state = "idle"
		var np: Variant = _nearest_pile_pos(s, e)
		s.wander(e, dt, ev, s.speed_px(e) * 0.6, s.pm(e, "wander_m"), np if np != null else e.home)
		return
	# 裸
	e.state = "naked_run"
	if not s.due(float(e.retreat_until)):
		s.walk_away(e, e.retreat_from, s.pm(e, "naked_mps"), dt, ev)
		return
	var pile: Dictionary = _choose_pile(s, e)
	if pile.is_empty():
		if not _fight(s, e, dt, ev, true):
			s.wander(e, dt, ev, s.pm(e, "naked_mps") * 0.5, s.pm(e, "wander_m"))
		return
	e.target_pile = int(pile.id)
	var t: Dictionary = s.nearest_target(e, s.radius_px(e) + 8.0, false)
	if not t.is_empty() and s.in_reach(e, t) and s.due(float(e.claw_at)):
		s.dmg_target(e, t, s.pf(e, "scratch_damage"), ev)
		e.claw_at = s.time + s.pf(e, "scratch_interval_s")
		e.retreat_until = s.time + s.pf(e, "scratch_retreat_s")
		e.retreat_from = t.pos
		return
	if e.pos.distance_to(pile.pos) <= 8.0:
		s.set_state(e, "wearing", s.pf(e, "wear_s"))
		return
	var sp: float = s.pm(e, "naked_mps")
	var moved: float = s.step_move(e, pile.pos - e.pos, sp, dt, ev)
	if moved < 0.3 * sp * dt:
		e.stall = float(e.stall) + dt
		if float(e.stall) >= 2.0:
			e.skip[str(pile.id)] = s.time + 10.0
			e.stall = 0.0
	else:
		e.stall = 0.0

static func on_flee(_s: RefCounted, _e: Dictionary) -> void:
	pass
