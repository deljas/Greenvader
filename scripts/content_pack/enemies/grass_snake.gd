extends "res://scripts/content_pack/enemies/base.gd"
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")
## E05 クサヘビ。状態: hidden / moving / revealed / strike
## 擬態: 成熟した草("grass")のマスで still_s 秒止まると hidden。reveal_until まで(または草でないマスにいる間)は見える。

static func init(s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.reveal_until = 0.0
	e.still_t = 0.0
	e.dest = e.pos
	e.state = "revealed"
	if _on_grass(s, e):
		e.state = "hidden"

static func _on_grass(s: RefCounted, e: Dictionary) -> bool:
	return s.host.grass_stage(Vector2i(floori(e.pos.x / 4.0), floori(e.pos.y / 4.0))) == "grass"

static func _revealed_now(s: RefCounted, e: Dictionary) -> bool:
	return not s.due(float(e.reveal_until))

static func hidden(s: RefCounted, e: Dictionary) -> bool:
	if not _on_grass(s, e) or _revealed_now(s, e):
		return false
	return e.state == "hidden" or e.state == "strike" or e.state == "moving"

static func hint(s: RefCounted, e: Dictionary) -> bool:
	return e.state == "moving" and hidden(s, e)

static func _reveal(s: RefCounted, e: Dictionary) -> void:
	e.reveal_until = s.time + s.pf(e, "reveal_s")
	if e.state == "hidden":
		e.state = "revealed"
		e.still_t = 0.0

static func on_hit(s: RefCounted, e: Dictionary, _k: String, _f: Variant, _d: float, _ev: Array[Dictionary]) -> void:
	_reveal(s, e)

static func on_seed(s: RefCounted, e: Dictionary, pos: Vector2, _ev: Array[Dictionary]) -> void:
	if e.pos.distance_to(pos) <= 10.0:
		_reveal(s, e)

static func _pick_dest(s: RefCounted, e: Dictionary) -> bool:
	var c0: Vector2i = Vector2i(floori(e.pos.x / 4.0), floori(e.pos.y / 4.0))
	var mn: int = int(s.pf(e, "relocate_min_cells"))
	var mx: int = int(s.pf(e, "relocate_max_cells"))
	for _i: int in range(16):
		var c: Vector2i = c0 + Vector2i(s.rng.randi_range(-mx, mx), s.rng.randi_range(-mx, mx))
		if maxi(absi(c.x - c0.x), absi(c.y - c0.y)) < mn:
			continue
		if s.host.grass_stage(c) == "grass" and s.host.is_walkable(c) and not s.host.is_stable_cell(c) \
				and (s.host.is_blocked(c) == false) and Vector2(Grid.center_of_cell(c)).distance_to(e.home) <= s.territory_px(e):
			e.dest = Grid.center_of_cell(c)
			return true
	return false

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	var on_grass: bool = _on_grass(s, e)
	if not on_grass:
		e.reveal_until = maxf(float(e.reveal_until), s.time + s.pf(e, "reveal_s"))
	match str(e.state):
		"hidden":
			if not on_grass:
				e.state = "revealed"
				return
			var t: Dictionary = s.nearest_target(e, s.pm(e, "trigger_m"), false)
			if not t.is_empty():
				s.set_state(e, "strike", s.pf(e, "windup_s"))
				s.fx(ev, "windup", e.pos, e)
		"strike":
			if s.due(float(e.until)):
				var t2: Dictionary = s.nearest_target(e, s.pm(e, "bite_reach_m"), false)
				if not t2.is_empty():
					s.dmg_target(e, t2, s.pf(e, "bite_damage"), ev)
				e.reveal_until = s.time + s.pf(e, "reveal_s")
				e.still_t = 0.0
				if _pick_dest(s, e):
					e.state = "moving"
				else:
					e.state = "revealed"
		"moving":
			if s.walk_to(e, e.dest, s.speed_px(e), dt, ev, 1.5) or bool(e.blocked):
				e.state = "revealed"
				e.still_t = 0.0
		"revealed":
			if on_grass and not _revealed_now(s, e):
				e.still_t = float(e.still_t) + dt
				if float(e.still_t) >= s.pf(e, "still_s") - 1e-6:
					e.state = "hidden"
			else:
				e.still_t = 0.0

static func on_flee(s: RefCounted, e: Dictionary) -> void:
	e.state = "revealed"
	e.still_t = 0.0
	e.reveal_until = s.time + s.pf(e, "reveal_s")
