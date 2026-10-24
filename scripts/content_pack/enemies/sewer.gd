extends "res://scripts/content_pack/enemies/base.gd"
## E26 マンホール(manhole)とドブネズミ(sewer_rat)。
## マンホール: open / closed。同じ net_id のマンホールで一つの巣。開いているものが一つでもあれば巣は生きている。
##   栽培植物が乗ると閉じる(plug にその株ID)。全部閉じたら巣を制圧し、巣の報酬(基礎30)を1回だけ(origin が initial のときだけ)。
##   生産は網全体で15秒ごと、生存6匹まで(produced、報酬0)。当たらない・壊せない。
## ドブネズミ: idle / walk / gnaw / enter(マンホールへ向かう) / ug(地下を移動、3秒) / stuck(出口が塞がれ、下から株をかじる)
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")
const Common2: GDScript = preload("res://scripts/content_pack/common2.gd")
const RAT_STATES: Array = ["idle", "walk", "gnaw", "enter", "ug", "stuck"]

static func init(s: RefCounted, e: Dictionary, o: Dictionary) -> void:
	if str(e.kind) == "manhole":
		e.state = "open"
		e.net_id = int(o.get("net_id", e.id))
		e.plug = 0
		e.next_spawn = s.time + s.pf(e, "spawn_interval_s")
		e.nest_paid = false
	else:
		e.state = "idle"
		e.net_id = int(o.get("net_id", 0))
		e.home_mh = int(o.get("home_mh", 0))
		e.exit_id = 0
		e.ug_until = 0.0
		e.target_crop = 0
		e.gnaw_at = 0.0
		e.roam_at = s.time + s.pf(e, "roam_s")
		e.think_at = s.time

static func hittable(_s: RefCounted, e: Dictionary) -> bool:
	if str(e.kind) == "manhole":
		return false
	return e.state != "ug" and e.state != "stuck"

static func tags(s: RefCounted, e: Dictionary) -> Array:
	if str(e.kind) == "sewer_rat" and not hittable(s, e):
		return []
	return s.def_of(e).get("tags", [])

static func counts(_s: RefCounted, e: Dictionary) -> bool:
	return str(e.kind) != "manhole" or e.state == "open"

static func detect_pos(_s: RefCounted, e: Dictionary) -> Variant:
	if str(e.kind) == "sewer_rat" and not hittable(_s, e):
		return null   # 地下のネズミは検知できない
	return e.pos

static func validate(_s: RefCounted, e: Dictionary) -> bool:
	if str(e.kind) == "manhole":
		return e.state == "open" or e.state == "closed"
	return RAT_STATES.has(str(e.state))

static func _cell(e: Dictionary) -> Vector2i:
	return Grid.cell_of_pos(e.pos)

static func _plug_of(s: RefCounted, m: Dictionary) -> int:
	return int(s.crops.crop_id_at(_cell(m)))

static func net_members(s: RefCounted, net: int) -> Array:
	var out: Array = []
	for m: Dictionary in s.enemies:
		if m.alive and m.kind == "manhole" and int(m.net_id) == net:
			out.append(m)
	return out

static func open_members(s: RefCounted, net: int) -> Array:
	var out: Array = []
	for m: Dictionary in net_members(s, net):
		if m.state == "open":
			out.append(m)
	return out

static func rat_count(s: RefCounted, net: int) -> int:
	var n: int = 0
	for m: Dictionary in s.enemies:
		if m.alive and m.kind == "sewer_rat" and int(m.net_id) == net:
			n += 1
	return n

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	if str(e.kind) == "manhole":
		_manhole(s, e, ev)
	else:
		_rat(s, e, dt, ev)

static func _manhole(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	# 塞がれているか(マスに栽培植物が乗っていれば閉じる)
	var plug: int = _plug_of(s, e)
	var was: String = str(e.state)
	e.plug = plug
	e.state = "closed" if plug > 0 else "open"
	if was != e.state:
		s.fx(ev, "manhole_closed" if e.state == "closed" else "manhole_open", e.pos, e)
	var members: Array = net_members(s, int(e.net_id))
	if members.is_empty() or int((members[0] as Dictionary).id) != int(e.id):
		return   # 網の代表(最小ID)だけが生産と制圧の判定をする
	var opens: Array = []
	for m: Dictionary in members:
		if m.state == "open":
			opens.append(m)
	# 制圧: 全部閉じたら1回だけ巣の報酬
	if opens.is_empty():
		var paid: bool = false
		for m: Dictionary in members:
			if bool(m.nest_paid):
				paid = true
		if not paid:
			for m: Dictionary in members:
				m.nest_paid = true
			s.fx(ev, "nest_suppressed", e.pos, e)
			ev.append({"type": "nest_suppressed", "net_id": int(e.net_id), "pos": e.pos})
			if str(e.origin) == "initial":
				var rv: Dictionary = Common2.reward_event(int(e.id), "manhole", int(s.pf(e, "nest_reward_base")), str(e.tier), e.pos)
				rv["nest"] = "small"
				ev.append(rv)
	# 生産(網全体で15秒ごと。開いているマンホールから)
	if s.due(float(e.next_spawn)):
		e.next_spawn = s.time + s.pf(e, "spawn_interval_s")
		if not opens.is_empty() and bool(s.host.nest_active(e.pos, "manhole")) and rat_count(s, int(e.net_id)) < int(s.pf(e, "max_alive")):
			var src: Dictionary = opens[s.rng.randi_range(0, opens.size() - 1)]
			s.spawn("sewer_rat", Vector2(src.pos) + Vector2(0.0, 4.0), "produced", {"net_id": int(e.net_id), "home_mh": int(src.id), "home": src.pos, "tier": str(e.tier)})
			s.fx(ev, "rat_emerge", src.pos, src)
		for m: Dictionary in members:
			m.next_spawn = e.next_spawn

static func _enter_target(s: RefCounted, e: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = INF
	for m: Dictionary in open_members(s, int(e.net_id)):
		var d: float = e.pos.distance_to(m.pos)
		if d < bd:
			bd = d
			best = m
	return best

static func _rat(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	var home_m: Dictionary = s.ref(int(e.home_mh))
	var home_pos: Vector2 = Vector2(home_m.pos) if not home_m.is_empty() else Vector2(e.home)
	match str(e.state):
		"idle":
			if s.due(float(e.think_at)):
				e.think_at = s.time + s.pf(e, "think_s")
				var best: Dictionary = {}
				var bd: float = INF
				var tg: Array = s.tags_of(e)
				for c: Dictionary in s.crops.crops:
					if not s.crops.crop_targetable_by(tg, int(c.id)):
						continue
					if s.crop_dist(home_pos, c) > s.territory_px(e):
						continue
					var d: float = s.crop_dist(e.pos, c)
					if d < bd:
						bd = d
						best = c
				if not best.is_empty():
					e.target_crop = int(best.id)
					e.state = "walk"
					return
				if s.due(float(e.roam_at)):
					var mh: Dictionary = _enter_target(s, e)
					if not mh.is_empty():
						e.exit_id = int(mh.id)
						e.state = "enter"
						return
			s.wander(e, dt, ev, s.speed_px(e) * 0.5, s.pm(e, "wander_m"), home_pos)
		"walk":
			var c2: Dictionary = s.crops.get_crop(int(e.target_crop))
			if c2.is_empty():
				e.state = "idle"
				e.roam_at = s.time + s.pf(e, "roam_s")
				return
			if s.crop_dist(e.pos, c2) <= s.radius_px(e) + 2.0:
				e.state = "gnaw"
				e.gnaw_at = s.time + s.pf(e, "gnaw_interval_s")
				return
			s.step_move(e, s.crop_center(c2) - e.pos, s.speed_px(e), dt, ev)
			if bool(e.blocked):
				e.state = "idle"
		"gnaw":
			var c3: Dictionary = s.crops.get_crop(int(e.target_crop))
			if c3.is_empty():
				e.state = "idle"
				e.roam_at = s.time + s.pf(e, "roam_s")
				return
			if s.due(float(e.gnaw_at)):
				e.gnaw_at = float(e.gnaw_at) + s.pf(e, "gnaw_interval_s")
				s.hurt_crop(e, int(e.target_crop), s.pf(e, "gnaw_damage"), ev)
		"enter":
			var tm: Dictionary = s.ref(int(e.exit_id))
			if tm.is_empty() or tm.state != "open":
				e.state = "idle"
				return
			if s.walk_to(e, tm.pos, s.speed_px(e), dt, ev, 2.0):
				# 地下へ。同じ網の別の開いたマンホールから3秒後に出てくる(なければ同じ出口)
				var opts: Array = []
				for m: Dictionary in open_members(s, int(e.net_id)):
					if int(m.id) != int(tm.id):
						opts.append(m)
				var ex: Dictionary = tm
				if not opts.is_empty():
					ex = opts[s.rng.randi_range(0, opts.size() - 1)]
				e.exit_id = int(ex.id)
				e.pos = tm.pos
				e.last_cell = Grid.cell_of_pos(e.pos)
				s.set_state(e, "ug", s.pf(s.ref(int(tm.id)), "underground_s"))
				s.fx(ev, "rat_enter", tm.pos, e)
			elif bool(e.blocked):
				e.state = "idle"
		"ug":
			if s.due(float(e.until)):
				_arrive(s, e, ev)
		"stuck":
			_arrive(s, e, ev)

## 出口に着いた。開いていれば地上へ。塞がれていれば下から株をかじる。
static func _arrive(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	var ex: Dictionary = s.ref(int(e.exit_id))
	if ex.is_empty() or not bool(ex.alive):
		var op: Array = open_members(s, int(e.net_id))
		if op.is_empty():
			var all: Array = net_members(s, int(e.net_id))
			if all.is_empty():
				e.state = "idle"   # 網が無い(孤立した個体)は地上へ出る
				return
			ex = all[0]
		else:
			ex = op[0]
		e.exit_id = int(ex.id)
	e.pos = ex.pos
	e.last_cell = Grid.cell_of_pos(e.pos)
	var plug: int = _plug_of(s, ex)
	if plug <= 0:
		e.home_mh = int(ex.id)
		e.home = ex.pos
		e.pos = Vector2(ex.pos) + Vector2(0.0, 4.0)
		e.last_cell = Grid.cell_of_pos(e.pos)
		e.state = "idle"
		e.roam_at = s.time + s.pf(e, "roam_s")
		e.think_at = s.time
		s.fx(ev, "rat_emerge", ex.pos, e)
		return
	if e.state != "stuck":
		e.state = "stuck"
		e.gnaw_at = s.time + s.pf(e, "plug_interval_s")
		return
	if s.due(float(e.gnaw_at)):
		e.gnaw_at = float(e.gnaw_at) + s.pf(e, "plug_interval_s")
		s.hurt_crop(e, plug, s.pf(e, "plug_damage"), ev)   # 出ようとして下から株をかじる

static func on_flee(s: RefCounted, e: Dictionary) -> void:
	if str(e.kind) == "sewer_rat":
		e.state = "idle"
		e.until = s.time
