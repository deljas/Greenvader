extends "res://scripts/content_pack/enemies/base.gd"
## E23 スカンク。状態: idle / approach / gnaw / windup(尾を立てて背を向ける)。噴射の間隔は spray_at(時刻)で持つ。
## 正面120°からの shot / bazooka / helper の命中で windup(0.6秒)→ 撃った相手の方向へ扇形の臭気の雲。たいあたり・横後ろからは噴かない。
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")
const Facing: GDScript = preload("res://scripts/content_pack/facing.gd")
const STATES: Array = ["idle", "approach", "gnaw", "windup"]

static func init(s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "idle"
	e.spray_dir = Vector2.DOWN
	e.spray_at = 0.0         # この時刻以降に噴ける(間隔6秒)
	e.target_crop = 0
	e.gnaw_at = 0.0
	e.think_at = s.time

static func validate(_s: RefCounted, e: Dictionary) -> bool:
	return STATES.has(str(e.state)) and typeof(e.spray_dir) == TYPE_VECTOR2

static func on_hit(s: RefCounted, e: Dictionary, kind: String, from: Variant, _d: float, ev: Array[Dictionary]) -> void:
	if kind != "shot" and kind != "bazooka" and kind != "helper":
		return   # たいあたり・水・トゲでは噴かない
	if e.state == "windup" or not s.due(float(e.spray_at)):
		return
	var origin: Variant = Facing.attack_origin(kind, from, from, null)
	if not Facing.is_front(e.face, e.pos, origin, s.pf(e, "front_half_deg")):
		return   # 横・後ろからは噴かない
	e.spray_dir = (Vector2(origin) - e.pos).normalized()
	s.set_state(e, "windup", s.pf(e, "windup_s"))
	s.fx(ev, "skunk_windup", e.pos, e, {"dir": e.spray_dir})

static func _find_crop(s: RefCounted, e: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = INF
	var tg: Array = s.tags_of(e)
	for c: Dictionary in s.crops.crops:
		if not bool(c.mature) or not s.crops.crop_targetable_by(tg, int(c.id)):
			continue
		if s.crop_dist(e.home, c) > s.territory_px(e):
			continue
		var d: float = s.crop_dist(e.pos, c)
		if d < bd:
			bd = d
			best = c
	return best

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	var turn: float = s.pf(e, "turn_dps")
	var h: Dictionary = s.hero_t()
	var hero_close: bool = not h.is_empty() and e.pos.distance_to(h.pos) <= s.pm(e, "hero_trigger_m")
	if str(e.state) == "windup":
		e.face = Facing.turn_toward(e.face, -Vector2(e.spray_dir), turn, dt)   # 背を向ける(旋回は90°/秒まで)
		if s.due(float(e.until)):
			e.state = "idle"
			e.spray_at = s.time + s.pf(e, "interval_s")
			if s.crops.garlic_covers_cell(Grid.cell_of_pos(e.pos)):
				s.fx(ev, "odor_cancel", e.pos, e)   # ニンニクの匂いで打ち消される
			else:
				s.add_odor(e.pos, e.spray_dir, int(e.id), s.pm(e, "cloud_len_m"), s.pf(e, "cloud_deg") * 0.5, s.pf(e, "cloud_s"))
				s.fx(ev, "odor", e.pos, e, {"dir": e.spray_dir})
		return
	if hero_close:
		e.face = Facing.turn_toward(e.face, h.pos - e.pos, turn, dt)   # 主人公と向き合う(旋回は90°/秒まで)
	var face0: Vector2 = Vector2(e.face)   # 移動処理が向きを書き換えるので、旋回上限つきで自分で回す
	match str(e.state):
		"idle":
			if s.due(float(e.think_at)):
				e.think_at = s.time + 0.5
				var c: Dictionary = _find_crop(s, e)
				if not c.is_empty():
					e.target_crop = int(c.id)
					e.state = "approach"
					return
			s.wander(e, dt, ev, s.speed_px(e) * 0.6, s.pm(e, "wander_m"))
			e.face = face0
			if not hero_close and bool(e.wp_valid) and e.pos.distance_to(e.wp) > 1.0:
				e.face = Facing.turn_toward(face0, e.wp - e.pos, turn, dt)
		"approach":
			var c2: Dictionary = s.crops.get_crop(int(e.target_crop))
			if c2.is_empty() or not bool(c2.mature) or not s.crops.crop_targetable_by(s.tags_of(e), int(c2.id)):
				e.state = "idle"
				return
			if s.crop_dist(e.pos, c2) <= s.radius_px(e) + 2.0:
				e.state = "gnaw"
				e.gnaw_at = s.time + s.pf(e, "gnaw_interval_s")
				return
			var dirv: Vector2 = s.crop_center(c2) - e.pos
			s.step_move(e, dirv, s.speed_px(e), dt, ev, {"limit_px": s.territory_px(e), "keep_face": true})
			if not hero_close:
				e.face = Facing.turn_toward(e.face, dirv, turn, dt)
			if bool(e.blocked):
				e.state = "idle"
		"gnaw":
			var c3: Dictionary = s.crops.get_crop(int(e.target_crop))
			if c3.is_empty() or not s.crops.crop_targetable_by(s.tags_of(e), int(c3.id)):
				e.state = "idle"
				return
			if s.due(float(e.gnaw_at)):
				e.gnaw_at = float(e.gnaw_at) + s.pf(e, "gnaw_interval_s")
				s.hurt_crop(e, int(e.target_crop), s.pf(e, "gnaw_damage"), ev)

static func on_flee(s: RefCounted, e: Dictionary) -> void:
	e.state = "idle"
	e.until = s.time
