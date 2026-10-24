extends "res://scripts/content_pack/enemies/base.gd"
## E12 ホオブクロウサギ。状態: rest / approach / chew / return / flee / tired
## かじっている間、その株の補正後生産量は cheek(ほお袋、上限cheek_cap)へ入る(crop_system の seeds_stolen を on_crop_events が stash へ渡す)。
const Util: GDScript = preload("res://scripts/content_pack/enemies/flee_util.gd")

static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "rest"
	e.cheek = 0.0
	e.gnaw_crop = 0
	e.target_crop = 0
	e.chew_at = 0.0
	e.think_at = 0.0

static func stash(s: RefCounted, e: Dictionary, amount: float) -> void:
	e.cheek = minf(s.pf(e, "cheek_cap"), float(e.cheek) + amount)

static func _ungnaw(s: RefCounted, e: Dictionary) -> void:
	if int(e.gnaw_crop) > 0:
		s.crops.set_gnawed(int(e.gnaw_crop), false)
		e.gnaw_crop = 0

static func _full(s: RefCounted, e: Dictionary) -> bool:
	return float(e.cheek) >= s.pf(e, "cheek_cap") - 1e-6

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	var st: String = str(e.state)
	if st == "flee":
		Util.flee_step(s, e, dt, ev)
		return
	if st == "tired":
		if s.due(float(e.until)):
			e.state = "return" if _full(s, e) else "rest"
		return
	if Util.hero_near(s, e):
		_ungnaw(s, e)
		Util.begin_flee(s, e, null, ev)
		return
	match st:
		"rest":
			if _full(s, e) or not s.due(float(e.think_at)):
				return
			e.think_at = s.time + 0.5
			var c: Dictionary = Util.find_crop(s, e, s.pm(e, "seek_m"))
			if not c.is_empty():
				e.target_crop = int(c.id)
				e.state = "approach"
		"approach":
			var c2: Dictionary = s.crops.get_crop(int(e.target_crop))
			if c2.is_empty() or not bool(c2.mature):
				e.state = "rest"
				return
			if s.crop_dist(e.pos, c2) <= s.radius_px(e) + 2.0:
				e.gnaw_crop = int(c2.id)
				s.crops.set_gnawed(int(c2.id), true)
				e.chew_at = s.time + 1.0
				e.state = "chew"
				return
			s.step_move(e, s.crop_center(c2) - e.pos, s.speed_px(e), dt, ev, {"limit_px": s.territory_px(e)})
			if bool(e.blocked):
				e.state = "rest"
		"chew":
			var c3: Dictionary = s.crops.get_crop(int(e.gnaw_crop))
			if c3.is_empty() or not bool(c3.mature):
				_ungnaw(s, e)
				e.state = "rest"
				return
			if _full(s, e):
				_ungnaw(s, e)
				e.state = "return"
				return
			if s.due(float(e.chew_at)):
				e.chew_at = float(e.chew_at) + 1.0
				s.hurt_crop(e, int(e.gnaw_crop), s.pf(e, "chew_damage"), ev)
		"return":
			if s.walk_to(e, e.home, s.speed_px(e), dt, ev, 3.0) or bool(e.blocked):
				e.state = "rest"

static func on_flee(s: RefCounted, e: Dictionary) -> void:
	_ungnaw(s, e)
	e.state = "rest"
	e.until = s.time

## 撃破時はほお袋の種を地面へ落とす(拾い物)
static func on_defeat(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	_ungnaw(s, e)
	var n: int = floori(float(e.cheek))
	if n >= 1:
		s.crops.add_pickup(e.pos, n, int(e.id), "seeds")
		s.fx(ev, "cheek_drop", e.pos, e, {"amount": n})
	e.cheek = 0.0
