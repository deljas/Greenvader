extends RefCounted
## 逃げる敵(ホオブクロウサギ・シカ)の共通部品。縄張りの外へは出ない。走る→疲れて止まる。

static func hero_near(s: RefCounted, e: Dictionary) -> bool:
	var h: Dictionary = s.hero_t()
	return not h.is_empty() and e.pos.distance_to(h.pos) <= s.pm(e, "flee_trigger_m")

## 縄張り内で、狙える成熟株のうち最も近いもの。見つからなければ空。
static func find_crop(s: RefCounted, e: Dictionary, seek_px: float) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = 1e18
	var tg: Array = s.tags_of(e)
	for c: Dictionary in s.crops.crops:
		if not bool(c.mature) or not s.crops.crop_targetable_by(tg, int(c.id)):
			continue
		var d: float = s.crop_dist(e.pos, c)
		if d <= seek_px and d < bd and s.crop_dist(e.home, c) <= s.territory_px(e):
			best = c
			bd = d
	return best

static func begin_flee(s: RefCounted, e: Dictionary, from: Variant, ev: Array[Dictionary]) -> void:
	var h: Dictionary = s.hero_t()
	if typeof(from) == TYPE_VECTOR2 and Vector2(from).distance_to(e.pos) > 0.1:
		e.flee_from = Vector2(from)
	elif not h.is_empty():
		e.flee_from = h.pos
	else:
		e.flee_from = e.pos - (Vector2(e.home) - e.pos).normalized() if e.pos != e.home else e.pos + Vector2.LEFT
	s.set_state(e, "flee", s.pf(e, "run_s"))
	s.fx(ev, "flee", e.pos, e)

## flee 状態の1ステップ。走り終えたら tired へ。
static func flee_step(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	var h: Dictionary = s.hero_t()
	if not h.is_empty() and e.pos.distance_to(h.pos) <= s.pm(e, "flee_trigger_m") * 3.0:
		e.flee_from = h.pos
	s.walk_away(e, e.flee_from, s.pm(e, "flee_mps"), dt, ev, {"limit_px": s.territory_px(e)})
	if s.due(float(e.until)):
		s.set_state(e, "tired", s.pf(e, "tired_s"))
