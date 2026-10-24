extends "res://scripts/content_pack/enemies/base.gd"
## E28 テツヨロイサイ。状態: idle / windup / charge / recover
## 射撃(shot / helper)は×0.5。水が当たるたびに錆+1(最大5、減らない)。錆1つにつき 速さ-12%・予兆+0.2秒・突進の間隔+1秒。
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")
const STATES: Array = ["idle", "windup", "charge", "recover"]

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "idle"
	e.rust = 0
	e.charge_dir = Vector2.DOWN
	e.hit_ids = []
	e.next_charge = 0.0
	e.trample = {}
	e.tpos = e.pos

static func validate(_s: RefCounted, e: Dictionary) -> bool:
	if not STATES.has(str(e.state)) or int(e.rust) < 0 or int(e.rust) > 5:
		return false
	for k: Variant in (e.trample as Dictionary):
		if typeof(k) != TYPE_STRING or not ((e.trample as Dictionary)[k] is float or (e.trample as Dictionary)[k] is int):
			return false
	return typeof(e.charge_dir) == TYPE_VECTOR2

static func rust_mult(s: RefCounted, e: Dictionary) -> float:
	return maxf(0.1, 1.0 - s.pf(e, "rust_speed") * float(int(e.rust)))

static func damage_mult(s: RefCounted, e: Dictionary, kind: String, _f: Variant) -> float:
	if kind == "shot" or kind == "helper":
		return s.pf(e, "shot_mult")
	return 1.0

static func on_water(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	if int(e.rust) < int(s.pf(e, "rust_max")):
		e.rust = int(e.rust) + 1
		s.fx(ev, "rust", e.pos, e, {"rust": int(e.rust)})

static func _trample(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	var cid: int = int(s.crops.crop_id_at(Grid.cell_of_pos(e.pos)))
	if cid <= 0:
		return
	var key: String = str(cid)
	if e.trample.has(key) and s.time - float(e.trample[key]) < s.pf(e, "trample_cd_s"):
		return
	e.trample[key] = s.time
	s.hurt_crop(e, cid, s.pf(e, "crop_damage"), ev)

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	match str(e.state):
		"idle":
			var h: Dictionary = s.hero_t()
			if not h.is_empty() and s.due(float(e.next_charge)) and e.pos.distance_to(h.pos) <= s.pm(e, "trigger_m") and s.host.line_clear(e.pos, h.pos):
				e.tpos = h.pos
				e.face = (h.pos - e.pos).normalized()
				s.set_state(e, "windup", s.pf(e, "windup_s") + s.pf(e, "rust_windup_s") * float(int(e.rust)))
				s.fx(ev, "windup", e.pos, e)
				return
			# 主人公が遠いときは家の周りを歩き、進路上の栽培植物を踏み荒らす
			s.wander(e, dt, ev, s.speed_px(e) * rust_mult(s, e), s.pm(e, "wander_m"))
			if bool(e.alive):
				_trample(s, e, ev)
		"windup":
			var h2: Dictionary = s.hero_t()
			if not h2.is_empty():
				e.tpos = h2.pos
			var to: Vector2 = e.tpos - e.pos
			if to.length() > 0.1:
				e.face = to.normalized()
			if s.due(float(e.until)):
				e.charge_dir = Vector2(e.face)
				e.hit_ids = []
				s.set_state(e, "charge", s.pf(e, "charge_s"))
		"charge":
			var sp: float = s.pm(e, "charge_mps") * rust_mult(s, e)
			var n: int = int(ceil(sp * dt / 2.0))
			for _i: int in range(n):
				s.step_move(e, e.charge_dir, sp, dt / float(n), ev, {"straight": true, "ignore_repel": true})
				if not bool(e.alive):
					return
				var cid: int = int(s.crops.crop_id_at(Grid.cell_of_pos(e.pos)))
				if cid > 0 and not e.hit_ids.has("c" + str(cid)):
					e.hit_ids.append("c" + str(cid))
					s.hurt_crop(e, cid, s.pf(e, "crop_damage"), ev)
					if not bool(e.alive):
						return
				for t: Dictionary in s.all_targets():
					var key: String = str(t.type) + str(t.id)
					if e.pos.distance_to(t.pos) <= s.radius_px(e) + 4.0 and not e.hit_ids.has(key):
						e.hit_ids.append(key)
						s.dmg_target(e, t, s.pf(e, "charge_damage"), ev)
				if bool(e.blocked):
					break
			if bool(e.blocked) or s.due(float(e.until)):
				s.set_state(e, "recover", s.pf(e, "recover_s"))
				e.next_charge = s.time + s.pf(e, "recover_s") + s.pf(e, "interval_s") + s.pf(e, "rust_interval_s") * float(int(e.rust))
		"recover":
			if s.due(float(e.until)):
				e.state = "idle"

static func on_flee(s: RefCounted, e: Dictionary) -> void:
	s.set_state(e, "recover", 0.0)
