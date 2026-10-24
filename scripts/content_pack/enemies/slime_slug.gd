extends "res://scripts/content_pack/enemies/base.gd"
## E11 ネバナメクジ。通ったマスに粘液を残す(粘液の効果は enemy_system 側: 主人公減速・成長停止・荒地化・株へ毎秒2)。

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	var c: Dictionary = s.nearest_crop(e, s.pm(e, "seek_m"), false)
	if not c.is_empty():
		e.state = "crawl"
		if s.crop_dist(e.pos, c) > 0.0:
			s.step_move(e, s.crop_center(c) - e.pos, s.speed_px(e), dt, ev)
	else:
		e.state = "idle"
		s.wander(e, dt, ev, s.speed_px(e), s.pm(e, "wander_m"))
	if bool(e.alive):
		s.slime_mark(e, Vector2i(floori(e.pos.x / 4.0), floori(e.pos.y / 4.0)), ev)
