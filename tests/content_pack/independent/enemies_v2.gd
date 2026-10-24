extends SceneTree
## 独立検証: 敵 E01〜E11(カタログ2節)。入口スクリプト。1条件1回、時間は advance で早送り。
const Lab: GDScript = preload("res://scripts/content_pack/lab/lab_host.gd")
const Pack: GDScript = preload("res://scripts/content_pack/content_pack.gd")
const OUT_DIR: String = "res://evidence/content_pack/independent"

var checks: Array = []

func ck(name: String, ok: bool, detail: String = "") -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})

func near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps

func mk(seed: int = 3) -> RefCounted:
	return Pack.new(Lab.new(), seed)

func sp(p: RefCounted, kind: String, x: float, y: float, origin: String = "initial", opts: Dictionary = {}) -> int:
	return p.enemies.spawn(kind, Vector2(x, y), origin, opts)

func R(p: RefCounted, id: int) -> Dictionary:
	return p.enemies.ref(id)

func hero(p: RefCounted, x: float, y: float, aim: Vector2 = Vector2.RIGHT, hp: float = 100.0) -> void:
	p.host.hero_state = {"pos": Vector2(x, y), "hp": hp, "max_hp": 100.0, "aim": aim}

func hpos(p: RefCounted) -> Vector2:
	return p.host.hero_state.pos

func crop(p: RefCounted, kind: String, x: int, y: int, mature: bool = true) -> int:
	var r: Dictionary = p.crops.spawn_crop(kind, Vector2i(x, y), 0, {"mature": mature, "watered": true, "skip_check": true})
	return int(r.id) if bool(r.ok) else -1

func evs(events: Array, type: String, kind: String = "") -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if e.type == type and (kind == "" or str(e.get("kind", "")) == kind):
			out.append(e)
	return out

func fxs(events: Array, kind: String) -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if e.type == "fx" and e.kind == kind:
			out.append(e)
	return out

## secs秒を dt 刻みで進め、[{t,e}] を返す。fn(p, t) があれば各刻みの前に呼ぶ。ground_stage はホストへ反映する。
func sim(p: RefCounted, secs: float, dt: float = 0.1, fn: Callable = Callable()) -> Array:
	var out: Array = []
	var n: int = int(round(secs / dt))
	for i: int in range(n):
		if fn.is_valid():
			fn.call(p, p.enemies.time)
		var ev: Array[Dictionary] = p.advance(dt)
		for e: Dictionary in ev:
			out.append({"t": p.enemies.time, "e": e})
			if e.type == "ground_stage":
				p.host.set_stage(e.cell, e.stage)
	return out

func E(tl: Array) -> Array:
	return tl.map(func(x: Dictionary) -> Dictionary: return x.e)

func hero_dmg(tl: Array, amount: float = -1.0) -> Array:
	var out: Array = []
	for x: Dictionary in tl:
		if x.e.type == "hero_damage" and (amount < 0.0 or near(float(x.e.amount), amount, 1e-6)):
			out.append(x)
	return out

func approx_eq(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return absf(float(a) - float(b)) <= 1e-6
	if typeof(a) != typeof(b):
		return false
	if typeof(a) == TYPE_DICTIONARY:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k: Variant in a:
			if not (b as Dictionary).has(k) or not approx_eq(a[k], b[k]):
				return false
		return true
	if typeof(a) == TYPE_ARRAY:
		if (a as Array).size() != (b as Array).size():
			return false
		for i: int in range((a as Array).size()):
			if not approx_eq(a[i], b[i]):
				return false
		return true
	return a == b

func rt(d: Dictionary) -> Dictionary:
	var v: Variant = JSON.parse_string(JSON.stringify(d))
	return v if typeof(v) == TYPE_DICTIONARY else {}

func _initialize() -> void:
	t_e12()
	t_e13()
	t_e14()
	t_e15()
	t_e16()
	t_e17()
	t_e18()
	t_e19()
	t_e20()
	t_e21()
	t_common()
	var fails: int = 0
	var lines: Array = []
	for c: Dictionary in checks:
		var line: String = "%s %s %s" % [c.status, c.name, c.detail]
		print(line)
		lines.append(line)
		if c.status != "PASS":
			fails += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/enemies_v2.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "enemies_v2", "total": checks.size(), "failed": fails, "checks": checks}, "\t"))
	f.close()
	print("enemies_v2 total=%d failed=%d" % [checks.size(), fails])
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------ E12
func t_e12() -> void:
	var p: RefCounted = mk()
	var r: int = sp(p, "pouch_rabbit", 100, 100)
	hero(p, 400, 400)
	var cid: int = crop(p, "golden_four_leaf", 40, 25, true)    # 25.9種/秒: 数秒でほお袋が満杯
	var tl: Array = sim(p, 6.0)
	var stolen: float = 0.0
	var seeds_player: float = 0.0
	for e: Dictionary in E(tl):
		if e.type == "seeds_stolen":
			stolen += float(e.amount)
		elif e.type == "seeds":
			seeds_player += float(e.amount)
	ck("e12_gnawing_diverts_production_to_cheek", stolen > 0.0 and near(float(R(p, r).cheek), minf(20.0, stolen), 1e-4), "stolen=%.2f cheek=%.2f" % [stolen, float(R(p, r).cheek)])
	# ほお袋は20まで。かじっている間だけ横取り(かじり始めの前は通常生産)
	ck("e12_cheek_capped_at_20", float(R(p, r).cheek) <= 20.0 + 1e-6, str(R(p, r).cheek))
	var cw: RefCounted = mk()
	var rw: int = sp(cw, "pouch_rabbit", 100, 100)
	hero(cw, 400, 400)
	var swc: int = crop(cw, "sunflower", 33, 25, true)   # 0.075種/秒
	var cwl: Array = sim(cw, 12.0)
	var stolen2: float = 0.0
	var seeds2: float = 0.0
	var first_steal_t: float = -1.0
	for x: Dictionary in cwl:
		if x.e.type == "seeds_stolen":
			stolen2 += float(x.e.amount)
			if first_steal_t < 0.0:
				first_steal_t = x.t
		elif x.e.type == "seeds" and first_steal_t >= 0.0:
			seeds2 += float(x.e.amount)
	var cdw: Array = evs(E(cwl), "crop_damaged")
	ck("e12_chew_damage_1_per_sec", cdw.size() >= 2 and cdw.all(func(e: Dictionary) -> bool: return near(float(e.amount), 1.0)), str(cdw.size()))
	ck("e12_stolen_equals_cheek_and_player_gets_none_while_gnawed", stolen2 > 0.0 and near(float(R(cw, rw).cheek), stolen2, 1e-4) and seeds2 == 0.0, "stolen=%.3f cheek=%.3f player=%.3f" % [stolen2, float(R(cw, rw).cheek), seeds2])
	cw.hit_enemy(rw, 100.0, "shot", null)
	ck("e12_kill_ungnaws_crop_resumes_player_production", not bool(cw.crops.get_crop(swc).gnawed), "")
	var tl2: Array = sim(p, 8.0)
	ck("e12_full_returns_home_and_stops", R(p, r).state in ["return", "rest"] and not bool(p.crops.get_crop(cid).gnawed), str(R(p, r).state))
	# 撃破でほお袋の種が拾い物になる。主人公が近づくと回収
	var before: float = float(R(p, r).cheek)
	var kill: Array = p.hit_enemy(r, 100.0, "shot", null)
	ck("e12_death_drops_pickup_floor_cheek", p.crops.pickups.size() == 1 and int(p.crops.pickups[0].amount) == floori(before) and evs(kill, "reward").size() == 1 and int(evs(kill, "reward")[0].amount) == 4, "cheek=%.2f pickups=%s" % [before, str(p.crops.pickups.size())])
	var pk: Vector2 = p.crops.pickups[0].pos
	hero(p, pk.x + 5.0, pk.y)
	var cl: Array = p.advance(0.1)
	ck("e12_pickup_collected_by_hero", evs(cl, "pickup_collected").size() == 1 and int(evs(cl, "pickup_collected")[0].amount) == floori(before), "")
	# 逃走: 5m以内で3.0m/s、4秒走り2秒疲れる。縄張り(家から15m)外へは出ない
	var q: RefCounted = mk()
	var rq: int = sp(q, "pouch_rabbit", 100, 100)
	hero(q, 80, 100)
	var maxd: float = 0.0
	var speeds: Array = []
	var prev: Vector2 = R(q, rq).pos
	var states: Array = []
	for i: int in range(100):
		hero(q, minf(R(q, rq).pos.x - 15.0, 200.0), 100)
		q.advance(0.1)
		var cur: Vector2 = R(q, rq).pos
		speeds.append(cur.distance_to(prev) / 0.1)
		prev = cur
		maxd = maxf(maxd, cur.distance_to(Vector2(100, 100)))
		states.append(R(q, rq).state)
	var topspeed: float = 0.0
	for sv: float in speeds:
		topspeed = maxf(topspeed, sv)
	ck("e12_flee_speed_at_most_3mps", topspeed <= 30.5 and topspeed >= 25.0, "top=%.1f" % topspeed)
	ck("e12_never_leaves_territory_15m", maxd <= 150.0 + 3.0, "max=%.1f" % maxd)
	ck("e12_flee_then_tired_then_flee", states.has("flee") and states.has("tired"), "")
	var tcount: int = states.filter(func(s: String) -> bool: return s == "tired").size()
	ck("e12_tired_stops_in_place", tcount >= 10, str(tcount))
	# 動く速度は主人公(4.8m/s)より遅い
	ck("e12_slower_than_hero", topspeed < 48.0, "")

# ------------------------------------------------------------------ E13
func t_e13() -> void:
	var p: RefCounted = mk()
	var f: int = sp(p, "tongue_frog", 100, 120)
	hero(p, 160, 120)     # 6m
	var tl: Array = sim(p, 0.7)
	ck("e13_aim_0.8s_shows_line", fxs(E(tl), "tongue_line").size() == 1 and hero_dmg(tl).is_empty(), "")
	var tl2: Array = sim(p, 0.3)
	var pull: Array = evs(E(tl2), "hero_pull")
	ck("e13_hit_6dmg_pull_3m", hero_dmg(tl2, 6.0).size() == 1 and pull.size() == 1 and near(float(pull[0].distance), 30.0) and near(Vector2(pull[0].to).distance_to(Vector2(100, 120)), 30.0, 0.5), str(pull))
	# 3秒は舌を伸ばさない
	hero(p, 160, 120)
	var tl3: Array = sim(p, 2.5)
	ck("e13_cooldown_3s", fxs(E(tl3), "tongue_line").is_empty(), "")
	# 予兆中に線から横へ外れれば当たらない
	var q: RefCounted = mk()
	sp(q, "tongue_frog", 100, 120)
	hero(q, 160, 120)
	sim(q, 0.2)
	hero(q, 160, 140)
	var ql: Array = sim(q, 1.0)
	ck("e13_dodge_sideways_during_aim", hero_dmg(ql).is_empty() and evs(E(ql), "hero_pull").is_empty() and fxs(E(ql), "tongue").size() == 1, "")
	# 建物は舌を遮る/視線なしでは撃たない/7mより遠い
	var w: RefCounted = mk()
	sp(w, "tongue_frog", 128, 100)
	hero(w, 128, 40)
	var wl: Array = sim(w, 3.0)
	ck("e13_building_blocks_no_aim", fxs(E(wl), "tongue_line").is_empty() and hero_dmg(wl).is_empty(), "")
	var far: RefCounted = mk()
	sp(far, "tongue_frog", 100, 120)
	hero(far, 180, 120)
	ck("e13_no_trigger_beyond_7m", fxs(E(sim(far, 3.0)), "tongue_line").is_empty(), "")
	# おたすけ植物には4、引き寄せなし
	var h: RefCounted = mk()
	sp(h, "tongue_frog", 100, 120)
	hero(h, 400, 400)
	h.host.helper_list = [{"id": 2, "pos": Vector2(150, 120), "hp": 30.0, "max_hp": 30.0}]
	var hl: Array = [{"t": 0.0, "e": {}}]
	# 主人公が範囲外なので狙えない。主人公を7m以内の別方向へ置いて舌の線上へ入れる
	hero(h, 400, 400)
	var h2: RefCounted = mk()
	sp(h2, "tongue_frog", 100, 120)
	hero(h2, 160, 120)
	h2.host.helper_list = [{"id": 2, "pos": Vector2(130, 120), "hp": 30.0, "max_hp": 30.0}]
	var h2l: Array = sim(h2, 1.2)
	ck("e13_helper_on_line_takes_4_no_pull", evs(E(h2l), "helper_damage").size() == 1 and near(float(evs(E(h2l), "helper_damage")[0].amount), 4.0) and evs(E(h2l), "hero_pull").is_empty() and hero_dmg(h2l).is_empty(), str(h2l.size()))

# ------------------------------------------------------------------ E14
func t_e14() -> void:
	var p: RefCounted = mk()
	var hv: int = sp(p, "honeybee_hive", 102, 102)    # cell(25,25)
	hero(p, 160, 102)
	ck("e14_neutral_not_counted_for_stability", p.enemies.living_count_for_stability() == 0 and p.enemies.is_alive(hv) and not p.enemies.counts_for_stability(hv), "")
	var swarm_id: int = -1
	for id: int in p.enemies.enemy_ids():
		if R(p, id).kind == "honeybee_swarm":
			swarm_id = id
	ck("e14_swarm_exists_neutral", swarm_id > 0 and not p.enemies.counts_for_stability(swarm_id), "")
	var tl: Array = sim(p, 12.0)
	ck("e14_calm_never_attacks", hero_dmg(tl).is_empty() and R(p, hv).state == "calm", "")
	ck("e14_hive_blocks_its_cell_not_walkable_structure", p.enemies.structure_at(Vector2i(25, 25)) == "honeybee_hive", "")
	# 巣のそば1.5m以内に3秒とどまると怒る
	hero(p, 110, 102)
	var tl2: Array = sim(p, 2.5)
	ck("e14_near_2.5s_still_calm", R(p, hv).state == "calm", str(R(p, hv).state))
	var tl3: Array = sim(p, 1.0)
	ck("e14_near_3s_angers", R(p, hv).state == "angry", str(R(p, hv).state))
	var tl4: Array = sim(p, 5.0)
	var stings: Array = hero_dmg(tl4, 3.0)
	ck("e14_angry_sting_3_per_sec", stings.size() >= 3 and stings.size() <= 6, str(stings.size()))
	# 怒りは20秒で終わり、巣10mの外へは追わない
	hero(p, 400, 400)
	var tl5: Array = sim(p, 30.0)
	ck("e14_anger_ends_and_calm", R(p, hv).state == "calm", str(R(p, hv).state))
	# 巣への攻撃で怒る(爆風含む)
	var q: RefCounted = mk()
	var hq: int = sp(q, "honeybee_hive", 102, 102)
	hero(q, 200, 102)
	q.splash(Vector2(120, 102), 30.0, 5.0, "bazooka")
	ck("e14_blast_angers_hive", R(q, hq).state == "angry", str(R(q, hq).state))
	# おたすけ植物が撃つとそのおたすけ植物を狙う
	var h: RefCounted = mk()
	var hh: int = sp(h, "honeybee_hive", 102, 102)
	hero(h, 400, 400)
	h.host.helper_list = [{"id": 4, "pos": Vector2(120, 102), "hp": 50.0, "max_hp": 50.0}]
	h.hit_enemy(hh, 1.0, "helper", Vector2(120, 102))
	var hl: Array = sim(h, 3.0)
	ck("e14_helper_shot_makes_bees_sting_helper", evs(E(hl), "helper_damage").size() >= 1 and hero_dmg(hl).is_empty(), str(evs(E(hl), "helper_damage").size()))
	# 追跡限界10m: 主人公が巣から15m離れていれば刺されない
	var c: RefCounted = mk()
	var hc: int = sp(c, "honeybee_hive", 52, 102)
	hero(c, 40, 102)
	c.hit_enemy(hc, 1.0, "shot", null)
	hero(c, 52 + 160, 102)
	var cl: Array = sim(c, 5.0)
	ck("e14_no_chase_beyond_10m_from_hive", hero_dmg(cl).is_empty(), "")
	# 群れを倒すと30秒後に新しい群れ(生産・報酬0)
	var s: RefCounted = mk()
	var hs: int = sp(s, "honeybee_hive", 102, 102)
	hero(s, 400, 400)
	var sw: int = -1
	for id: int in s.enemies.enemy_ids():
		if R(s, id).kind == "honeybee_swarm":
			sw = id
	var kill: Array = s.hit_enemy(sw, 100.0, "shot", null)
	ck("e14_swarm_death_no_reward", evs(kill, "reward").is_empty() and evs(kill, "enemy_defeated").size() == 1, "")
	sim(s, 29.0)
	var alive_sw1: int = s.enemies.enemy_ids().filter(func(i: int) -> bool: return R(s, i).kind == "honeybee_swarm").size()
	sim(s, 2.0)
	var swarm2: Array = s.enemies.enemy_ids().filter(func(i: int) -> bool: return R(s, i).kind == "honeybee_swarm")
	ck("e14_swarm_respawns_after_30s_produced", alive_sw1 == 0 and swarm2.size() == 1 and R(s, swarm2[0]).origin == "produced", "%d %d" % [alive_sw1, swarm2.size()])
	var kill2: Array = s.hit_enemy(swarm2[0], 100.0, "shot", null)
	ck("e14_produced_swarm_reward_0", evs(kill2, "reward").is_empty(), "")
	# 巣を壊すと報酬なし・受粉が消え、群れも散る。安定地域にいても再侵攻でない(数えない)
	var b: RefCounted = mk()
	var hb: int = sp(b, "honeybee_hive", 102, 102, "initial", {"tier": "far"})
	var cl2: int = crop(b, "clover", 30, 25, true)
	var base: float = 2.0 / 60.0
	ck("e14_pollination_while_alive", near(float(b.crops.production_info(cl2).rate), base * 1.1, 1e-9), "")
	var k3: Array = b.hit_enemy(hb, 1000.0, "shot", null)
	ck("e14_hive_destroyed_no_reward_no_pollination", evs(k3, "reward").is_empty() and near(float(b.crops.production_info(cl2).rate), base, 1e-9), "")
	ck("e14_swarm_gone_with_hive", b.enemies.enemy_ids().is_empty(), str(b.enemies.enemy_ids().size()))
	b.advance(60.0)
	ck("e14_no_second_hive_spawns", b.enemies.enemy_ids().is_empty(), "")
	# 安定地域にいても数えない
	var st: RefCounted = mk()
	sp(st, "honeybee_hive", 102, 102)
	st.host.set_stable_rect(Rect2i(20, 20, 12, 12))
	ck("e14_stable_area_hive_not_counted", st.enemies.living_count_for_stability() == 0 and st.enemies.living_for_stability().is_empty(), "")

# ------------------------------------------------------------------ E15
func t_e15() -> void:
	var p: RefCounted = mk()
	var a: int = sp(p, "armadillo", 160, 100)
	hero(p, 100, 100)
	var tl: Array = sim(p, 0.5)
	ck("e15_curl_windup_0.6s", R(p, a).state == "curl" and fxs(E(tl), "windup").size() == 1, str(R(p, a).state))
	var tl1: Array = sim(p, 0.3)
	ck("e15_rolls_after_windup", R(p, a).state == "roll", str(R(p, a).state))
	var s1: Array = p.hit_enemy(a, 10.0, "shot", null)
	ck("e15_roll_shot_x0.2", near(float(evs(s1, "enemy_damaged")[0].amount), 2.0), "")
	var tl2: Array = sim(p, 5.0)
	var hd: Array = hero_dmg(tl2, 10.0)
	ck("e15_hit_hero_10_once_per_roll", hd.size() == 1, str(hd.size()))
	var bounces: Array = fxs(E(tl2), "bounce")
	ck("e15_bounces_at_most_4", bounces.size() <= 4, str(bounces.size()))
	ck("e15_ends_dizzy_x1.5", R(p, a).state in ["dizzy", "idle"], str(R(p, a).state))
	# 反射: 部屋の中(建物)で跳ね返る
	var w: RefCounted = mk()
	var aw: int = sp(w, "armadillo", 128, 100)
	hero(w, 128, 40)
	var wl: Array = sim(w, 4.5, 0.05)
	var wb: Array = fxs(E(wl), "bounce")
	ck("e15_bounces_off_building", wb.size() >= 1 and wb.size() <= 4, str(wb.size()))
	var rolls: Array = wl.filter(func(x: Dictionary) -> bool: return x.e.type == "fx" and x.e.kind == "windup")
	var t_roll: float = rolls[0].t + 0.6 if rolls.size() > 0 else 0.0
	var dz: Array = wl.filter(func(x: Dictionary) -> bool: return true)
	ck("e15_roll_stops_within_3s", R(w, aw).state in ["dizzy", "idle", "curl"], str(R(w, aw).state))
	# 目を回す間は x1.5 (止まった直後)
	var d: RefCounted = mk()
	var ad: int = sp(d, "armadillo", 100, 100)
	d.enemies.ref(ad).state = "dizzy"
	d.enemies.ref(ad).until = 1e9
	var h3: Array = d.hit_enemy(ad, 10.0, "shot", null)
	ck("e15_dizzy_x1.5", near(float(evs(h3, "enemy_damaged")[0].amount), 15.0), "")
	# 株には8
	var cr: RefCounted = mk()
	var ac: int = sp(cr, "armadillo", 160, 100)
	var cc: int = crop(cr, "pumpkin", 22, 24, true)    # px(88..96,96..104) の線上
	hero(cr, 60, 100)
	var cl: Array = sim(cr, 4.0)
	var cd: Array = evs(E(cl), "crop_damaged")
	ck("e15_crop_damage_8_once", cd.size() == 1 and near(float(cd[0].amount), 8.0), str(cd.size()))
	# タケで跳ね返る
	var bm: RefCounted = mk()
	var ab: int = sp(bm, "armadillo", 160, 100)
	bm.crops.spawn_crop("bamboo", Vector2i(30, 25), 10, {"mature": true, "watered": true, "skip_check": true})
	hero(bm, 100, 100)
	var bl: Array = sim(bm, 2.0, 0.05)
	ck("e15_bamboo_reflects", fxs(E(bl), "bounce").size() >= 1, str(fxs(E(bl), "bounce").size()))

# ------------------------------------------------------------------ E16
func t_e16() -> void:
	var p: RefCounted = mk()
	var c: int = sp(p, "sludge_carp", 30, 30)
	hero(p, 400, 400)
	var shot_times: Array = []
	var surf_t: Array = []
	var always_water: bool = true
	var ok_hit_only_surface: bool = true
	var cnt: int = 0
	for i: int in range(200):
		p.advance(0.1)
		var cell: Vector2i = Vector2i(floori(R(p, c).pos.x / 4.0), floori(R(p, c).pos.y / 4.0))
		if not p.host.is_water(cell):
			always_water = false
		var hit: bool = p.enemies.is_hittable(R(p, c))
		if hit != (R(p, c).state == "surface"):
			ok_hit_only_surface = false
		if hit:
			surf_t.append(p.enemies.time)
	ck("e16_stays_in_water_cells", always_water, "")
	ck("e16_hittable_only_when_surfaced", ok_hit_only_surface, "")
	# 浮上は主人公がいなくても周期的に(8秒ごとに必ず)
	var first: float = surf_t[0]
	var gaps: Array = []
	for i: int in range(1, surf_t.size()):
		if surf_t[i] - surf_t[i - 1] > 1.0:
			gaps.append(surf_t[i] - first)
	ck("e16_surfaces_periodically_every_about_8s", surf_t.size() > 0 and first >= 4.7 and first <= 5.1 and gaps.size() >= 2 and gaps[0] >= 7.0 and gaps[0] <= 8.0, "first=%.1f gaps=%s" % [first, str(gaps)])
	ck("e16_surface_window_2.5s", surf_t.size() >= 50 and surf_t.size() <= 60, str(surf_t.size()))
		# 潜行中は当たらない(HPが変わらない)
	var q: RefCounted = mk()
	var cq: int = sp(q, "sludge_carp", 30, 30)
	hero(q, 400, 400)
	sim(q, 1.0)
	var dv: Array = q.hit_enemy(cq, 5.0, "shot", null)
	ck("e16_dive_shot_misses", dv.is_empty() and near(float(R(q, cq).hp), 25.0) and q.enemies.hittable_targets().is_empty(), "")
	# 泥: 8m以内の主人公に浮上時、着弾0.8秒前から表示、半径1m、6ダメージ+減速50% 2秒
	var m: RefCounted = mk()
	var cm: int = sp(m, "sludge_carp", 30, 30)
	hero(m, 60, 40)     # 岸の外側?(水の上) 近くを歩く想定: 水際
	m.host.hero_state.pos = Vector2(60, 60)     # 浅瀬近く(歩ける緑地ではない可能性があるが位置のみ判定)
	var ml: Array = sim(m, 6.0)
	var marks: Array = fxs(E(ml), "mud_mark")
	var lands: Array = fxs(E(ml), "mud_land")
	ck("e16_mud_mark_then_land_0.8s", marks.size() == 1 and lands.size() == 1, "%d %d" % [marks.size(), lands.size()])
	if marks.size() == 1 and lands.size() == 1:
		var tm: float = ml.filter(func(x: Dictionary) -> bool: return x.e.type == "fx" and x.e.kind == "mud_mark")[0].t
		var tlnd: float = ml.filter(func(x: Dictionary) -> bool: return x.e.type == "fx" and x.e.kind == "mud_land")[0].t
		ck("e16_mark_precedes_land_by_0.8s", near(tlnd - tm, 0.8, 0.11), "%.2f" % (tlnd - tm))
	ck("e16_mud_hit_6_and_slow_50pct_2s", hero_dmg(ml, 6.0).size() == 1 and evs(E(ml), "hero_slow").size() == 1 and near(float(evs(E(ml), "hero_slow")[0].factor), 0.5) and near(float(evs(E(ml), "hero_slow")[0].seconds), 2.0), "")
	# 動けば当たらない。草・植物に作用しない
	var n: RefCounted = mk()
	sp(n, "sludge_carp", 30, 30)
	var ncrop: int = crop(n, "clover", 15, 10, true)    # 泥の着弾点(60,40)付近
	hero(n, 60, 40)
	var nl: Array = sim(n, 6.0, 0.1, func(pk: RefCounted, t: float) -> void:
		if t > 5.0:
			hero(pk, 60, 90))
	ck("e16_moving_away_avoids_mud", hero_dmg(nl).is_empty(), str(hero_dmg(nl).size()))
	ck("e16_mud_does_not_hurt_crops", evs(E(nl), "crop_damaged").is_empty() and near(float(n.crops.get_crop(ncrop).hp), 30.0), "")
	# 報酬8は撃破時1回
	var r: RefCounted = mk()
	var cr: int = sp(r, "sludge_carp", 30, 30)
	hero(r, 400, 400)
	sim(r, 5.5)
	var kill: Array = r.hit_enemy(cr, 100.0, "shot", null)
	ck("e16_surface_kill_reward_8", evs(kill, "reward").size() == 1 and int(evs(kill, "reward")[0].amount) == 8, str(R(r, cr)))

# ------------------------------------------------------------------ E17
class NestHost extends "res://scripts/content_pack/lab/lab_host.gd":
	var active: bool = true
	func nest_active(_pos: Vector2, _kind: String) -> bool:
		return active

func t_e17() -> void:
	var host: RefCounted = NestHost.new()
	var p: RefCounted = Pack.new(host, 5)
	var hill: int = sp(p, "ant_hill", 202, 82, "initial", {"tier": "mid"})
	hero(p, 400, 400)
	ck("e17_hill_2x2_blocks_cells", p.enemies.structure_at(Vector2i(50, 20)) == "ant_hill" or p.enemies.structure_rects().size() == 1, str(p.enemies.structure_rects()))
	var tl: Array = sim(p, 8.5)
	var ants: Array = p.enemies.enemy_ids().filter(func(i: int) -> bool: return R(p, i).kind == "leafcutter_ant")
	ck("e17_spawns_1_ant_per_8s_when_active", ants.size() == 1 and R(p, ants[0]).origin == "produced", str(ants.size()))
	sim(p, 100.0)
	ants = p.enemies.enemy_ids().filter(func(i: int) -> bool: return R(p, i).kind == "leafcutter_ant")
	ck("e17_max_6_active_produced_ants", ants.size() == 6, str(ants.size()))
	# 生産個体の報酬は0
	var rw: int = 0
	for i: int in ants:
		rw += evs(p.hit_enemy(i, 100.0, "shot", null), "reward").size()
	ck("e17_produced_ant_reward_0", rw == 0, str(rw))
	# 倒すと次の生産で補充
	sim(p, 9.0)
	ants = p.enemies.enemy_ids().filter(func(i: int) -> bool: return R(p, i).kind == "leafcutter_ant")
	ck("e17_replenishes_after_kill", ants.size() >= 1, str(ants.size()))
	# 巣の報酬: 初期配置は基礎30(小さな巣)、階級tierはそのまま
	var kill: Array = p.hit_enemy(hill, 100.0, "shot", null)
	ck("e17_hill_reward_30_small_nest", evs(kill, "reward").size() == 1 and int(evs(kill, "reward")[0].amount) == 30 and evs(kill, "reward")[0].tier == "mid", str(kill))
	var after: int = p.enemies.enemy_ids().filter(func(i: int) -> bool: return R(p, i).kind == "ant_hill").size()
	sim(p, 40.0)
	ck("e17_no_spawn_after_hill_destroyed", after == 0 and p.enemies.enemy_ids().filter(func(i: int) -> bool: return R(p, i).origin == "produced" and R(p, i).kind == "leafcutter_ant").size() <= ants.size(), "")
	# 停止中(非活動)は生産しない
	var d: RefCounted = NestHost.new()
	d.active = false
	var pd: RefCounted = Pack.new(d, 5)
	sp(pd, "ant_hill", 202, 82)
	hero(pd, 400, 400)
	sim(pd, 40.0)
	ck("e17_dormant_hill_produces_nothing", pd.enemies.enemy_ids().size() == 1, str(pd.enemies.enemy_ids().size()))
	# 初期配置のアリは2、株だけを狙い主人公は攻撃しない
	var a: RefCounted = mk()
	var ant: int = sp(a, "leafcutter_ant", 100, 100, "initial", {"hill_id": 0})
	var cid: int = crop(a, "clover", 35, 25, true)
	hero(a, 104, 100)
	var al: Array = sim(a, 12.0)
	ck("e17_ant_cuts_crop_2_and_ignores_hero", hero_dmg(al).is_empty() and evs(E(al), "crop_damaged").size() >= 1 and near(float(evs(E(al), "crop_damaged")[0].amount), 2.0), "")
	var kr: Array = a.hit_enemy(ant, 10.0, "shot", null)
	ck("e17_initial_ant_reward_2", evs(kr, "reward").size() == 1 and int(evs(kr, "reward")[0].amount) == 2, "")
	# 行列の分断: 途中の1匹が倒されると後続は3秒うろうろ
	var col: RefCounted = Pack.new(NestHost.new(), 5)
	var hl: int = sp(col, "ant_hill", 22, 112)
	var tgt: int = crop(col, "giant_watermelon", 40, 25, true)
	hero(col, 400, 400)
	var ids: Array = []
	for i: int in range(4):
		ids.append(sp(col, "leafcutter_ant", 40.0 + 12.0 * float(i), 112, "initial", {"hill_id": hl, "home": Vector2(22, 112)}))
	sim(col, 0.6)
	var walking: bool = ids.all(func(i: int) -> bool: return R(col, i).state == "walk")
	ck("e17_ants_march_to_crop", walking, str(ids.map(func(i: int) -> String: return R(col, i).state)))
	var mid: int = ids[2]
	var order: Array = ids.duplicate()
	order.sort_custom(func(x: int, y: int) -> bool: return R(col, x).pos.distance_to(Vector2(22, 112)) < R(col, y).pos.distance_to(Vector2(22, 112)))
	var victim: int = order[2]
	col.hit_enemy(victim, 10.0, "shot", null)
	var lost: Array = order.filter(func(i: int) -> bool: return i != victim and R(col, i).state == "lost")
	var ahead_ok: bool = R(col, order[3]).state == "walk"
	ck("e17_followers_behind_lost_leader_ahead_continues", lost.size() == 2 and ahead_ok, "%s" % str(order.map(func(i: int) -> String: return R(col, i).state if col.enemies.is_alive(i) else "dead")))
	sim(col, 2.9)
	var still_lost: bool = lost.any(func(i: int) -> bool: return R(col, i).state == "lost")
	sim(col, 0.4)
	var resumed: bool = lost.all(func(i: int) -> bool: return R(col, i).state != "lost")
	ck("e17_lost_for_3s_then_resume", still_lost and resumed, "")

# ------------------------------------------------------------------ E18
func t_e18() -> void:
	var p: RefCounted = mk()
	var m: int = sp(p, "mimic_cabbage", 102, 122)
	hero(p, 400, 400)
	ck("e18_hidden_not_detectable_cell_occupied", p.enemies.detectable_enemies().is_empty() and p.crops.check_placement("clover", Vector2i(25, 30)).reason == "occupied", "")
	ck("e18_hittable_when_shot", p.enemies.hittable_targets().size() == 1, "")
	hero(p, 112, 122)
	var tl: Array = sim(p, 0.25)
	ck("e18_windup_0.3s_no_bite_yet", hero_dmg(tl).is_empty() and R(p, m).state == "strike", str(R(p, m).state))
	var tl2: Array = sim(p, 0.3)
	ck("e18_bite_12", hero_dmg(tl2, 12.0).size() == 1 and R(p, m).state == "chase", "")
	ck("e18_after_bite_detectable_and_cell_free", p.enemies.detectable_enemies().size() == 1, "")
	var tl3: Array = sim(p, 6.5, 0.1, func(pk: RefCounted, _t: float) -> void: hero(pk, 400, 400))
	ck("e18_chases_6s_then_returns", R(p, m).state in ["return", "hidden"], str(R(p, m).state))
	sim(p, 25.0)
	ck("e18_rehides_after_3s_at_home", R(p, m).state == "hidden" and R(p, m).pos.distance_to(Vector2(102, 122)) < 3.0, "%s %s" % [R(p, m).state, str(R(p, m).pos)])
	# 種・水・攻撃で見破り
	var q: RefCounted = mk()
	var mq: int = sp(q, "mimic_cabbage", 102, 122)
	hero(q, 400, 400)
	q.enemies.notify_seed(Vector2(108, 122))
	ck("e18_seed_reveals", R(q, mq).state == "revealed" and q.enemies.detectable_enemies().size() == 1, "")
	var w: RefCounted = mk()
	var mw: int = sp(w, "mimic_cabbage", 102, 122)
	w.hit_enemy(mw, 0.0, "water", null)
	ck("e18_water_reveals", R(w, mw).state == "revealed", "")
	var s: RefCounted = mk()
	var ms: int = sp(s, "mimic_cabbage", 102, 122)
	s.hit_enemy(ms, 1.0, "shot", null)
	ck("e18_hit_reveals", R(s, ms).state == "revealed" and s.enemies.detectable_enemies().size() == 1, "")
	var k: Array = s.hit_enemy(ms, 1000.0, "shot", null)
	ck("e18_reward_8_once", evs(k, "reward").size() == 1 and int(evs(k, "reward")[0].amount) == 8, "")

# ------------------------------------------------------------------ E19
func t_e19() -> void:
	var p: RefCounted = mk()
	var k: int = sp(p, "black_kite", 100, 100)
	hero(p, 400, 400)
	var tl: Array = sim(p, 6.0)
	ck("e19_circles_untouchable_when_no_target", R(p, k).state == "circle" and p.enemies.hittable_targets().is_empty() and fxs(E(tl), "kite_shadow").is_empty(), str(R(p, k).state))
	hero(p, 150, 100)    # 縄張り(10m)に入る
	var tl2: Array = sim(p, 0.2)
	var mark: Array = fxs(E(tl2), "kite_shadow")
	ck("e19_shadow_marks_target", mark.size() == 1 and R(p, k).state == "mark", str(R(p, k).state))
	var t_mark: float = tl2.filter(func(x: Dictionary) -> bool: return x.e.type == "fx" and x.e.kind == "kite_shadow")[0].t
	# 影は1.5秒ついて回り、0.5秒前に固定
	var shadow_pos: Array = []
	var states: Array = []
	var hits_times: Array = []
	var dive_dmg: Array = []
	var phases: Array = []
	var lock_pos: Vector2 = Vector2.ZERO
	var tlx: Array = []
	for i: int in range(60):
		hero(p, 150.0 + float(i) * 0.3 if R(p, k).state == "mark" else hpos(p).x, 100)
		var ev: Array[Dictionary] = p.advance(0.1)
		for e: Dictionary in ev:
			tlx.append({"t": p.enemies.time, "e": e})
		phases.append([p.enemies.time, R(p, k).state, p.enemies.is_hittable(R(p, k)), Vector2(R(p, k).shadow)])
	var first_lock: float = -1.0
	var first_dive: float = -1.0
	var ground_t: float = -1.0
	var climb_t: float = -1.0
	var circle_again: float = -1.0
	for ph: Array in phases:
		if ph[1] == "lock" and first_lock < 0.0:
			first_lock = ph[0]
		if ph[1] == "ground" and ground_t < 0.0:
			ground_t = ph[0]
		if ph[1] == "climb" and climb_t < 0.0:
			climb_t = ph[0]
	ck("e19_mark_1.5s_then_lock_0.5s", first_lock > 0.0 and near(first_lock - t_mark, 1.5, 0.25), "lock after %.2f" % (first_lock - t_mark))
	ck("e19_hittable_only_ground_and_climb", phases.all(func(ph: Array) -> bool: return bool(ph[2]) == (ph[1] == "ground" or ph[1] == "climb")), "")
	ck("e19_dive_damage_12_radius_1m_once", hero_dmg(tlx, 12.0).size() <= 1, str(hero_dmg(tlx).size()))
	ck("e19_ground_1s_climb_1s", ground_t > 0.0 and climb_t > 0.0 and near(climb_t - ground_t, 1.0, 0.15), "%.2f" % (climb_t - ground_t))
	# 固定後に主人公が動けば当たらない
	var q: RefCounted = mk()
	var kq: int = sp(q, "black_kite", 100, 100)
	hero(q, 150, 100)
	var evq: Array = []
	var guard: int = 0
	while R(q, kq).state != "lock" and guard < 100:
		for x: Dictionary in q.advance(0.1):
			evq.append(x)
		guard += 1
	hero(q, 190, 100)   # ロック後に離れる(縄張り内: 家から90px)
	for i: int in range(15):
		for x: Dictionary in q.advance(0.1):
			evq.append(x)
	ck("e19_dodge_after_lock_no_damage", hero_dmg(evq.map(func(e: Dictionary) -> Dictionary: return {"e": e})).is_empty(), "")
	# 縄張りの外は狙わない
	var o: RefCounted = mk()
	sp(o, "black_kite", 100, 100)
	hero(o, 230, 100)
	ck("e19_outside_territory_ignored", fxs(E(sim(o, 8.0)), "kite_shadow").is_empty(), "")
	# 主人公がいなければおたすけ植物
	var h: RefCounted = mk()
	sp(h, "black_kite", 100, 100)
	hero(h, 400, 400)
	h.host.helper_list = [{"id": 8, "pos": Vector2(140, 100), "hp": 40.0, "max_hp": 40.0}]
	var hl: Array = sim(h, 4.0)
	ck("e19_targets_helper_when_no_hero", evs(E(hl), "helper_damage").size() >= 1 and near(float(evs(E(hl), "helper_damage")[0].amount), 12.0), str(evs(E(hl), "helper_damage").size()))
	# 地上で撃破→報酬8・counts_for_stability(飛行中も)
	var r: RefCounted = mk()
	var kr: int = sp(r, "black_kite", 100, 100)
	hero(r, 400, 400)
	ck("e19_flying_counts_for_stability", r.enemies.counts_for_stability(kr), "")

# ------------------------------------------------------------------ E20
func t_e20() -> void:
	var p: RefCounted = mk()
	var d: int = sp(p, "deer", 100, 100)
	var cid: int = crop(p, "clover", 50, 25, true)    # px(200,100): 100px
	hero(p, 400, 400)
	var tl: Array = sim(p, 25.0)
	var cd: Array = evs(E(tl), "crop_damaged")
	ck("e20_eats_mature_crop_3_per_sec", cd.size() >= 3 and cd.all(func(e: Dictionary) -> bool: return near(float(e.amount), 3.0)) and hero_dmg(tl).is_empty(), str(cd.size()))
	# 撃つと逃げる(3.5m/s以下)、縄張り15mから出ない、4秒走って3秒疲れる
	var q: RefCounted = mk()
	var dq: int = sp(q, "deer", 100, 100)
	hero(q, 80, 100)
	var hit: Array = q.hit_enemy(dq, 1.0, "shot", Vector2(80, 100))
	ck("e20_shot_triggers_flee", R(q, dq).state == "flee" and fxs(hit, "flee").size() == 1, str(R(q, dq).state))
	var maxd: float = 0.0
	var top: float = 0.0
	var prev: Vector2 = R(q, dq).pos
	var states: Array = []
	for i: int in range(110):
		hero(q, minf(R(q, dq).pos.x - 20.0, 240.0), 100)
		q.advance(0.1)
		top = maxf(top, R(q, dq).pos.distance_to(prev) / 0.1)
		prev = R(q, dq).pos
		maxd = maxf(maxd, R(q, dq).pos.distance_to(Vector2(100, 100)))
		states.append(R(q, dq).state)
	ck("e20_flee_speed_at_most_3.5mps", top <= 35.5 and top >= 30.0, "top=%.1f" % top)
	ck("e20_never_leaves_15m_territory", maxd <= 153.0, "max=%.1f" % maxd)
	ck("e20_flee_4s_tired_3s_pattern", states.has("tired") and states.has("flee"), "")
	var tired_idx: int = states.find("tired")
	var tired_len: int = 0
	while tired_idx + tired_len < states.size() and states[tired_idx + tired_len] == "tired":
		tired_len += 1
	ck("e20_tired_lasts_3s", tired_len >= 28 and tired_len <= 32, str(tired_len))
	# 疲れている間に撃っても再び逃げ始めない=追い詰めれば倒せる
	var hp0: float = float(R(q, dq).hp)
	while R(q, dq).state != "tired":
		hero(q, 400, 400)
		q.advance(0.1)
	var h2: Array = q.hit_enemy(dq, 5.0, "shot", Vector2(200, 100))
	ck("e20_tired_shot_does_not_restart_flee", R(q, dq).state == "tired", str(R(q, dq).state))
	var kill: Array = q.hit_enemy(dq, 1000.0, "shot", null)
	ck("e20_kill_reward_8", evs(kill, "reward").size() == 1 and int(evs(kill, "reward")[0].amount) == 8, "")
	# 主人公には攻撃しない: 近づいても無害
	var w: RefCounted = mk()
	sp(w, "deer", 100, 100)
	hero(w, 105, 100)
	ck("e20_never_attacks_hero", hero_dmg(sim(w, 6.0)).is_empty(), "")
	# ラベンダー(虫のみ)は鹿に効かない / ニンニクの範囲の株は見失う
	var g: RefCounted = mk()
	var dg: int = sp(g, "deer", 100, 100)
	crop(g, "garlic", 50, 25, true)
	hero(g, 400, 400)
	var gl: Array = sim(g, 12.0)
	ck("e20_garlic_hides_crops_from_deer", evs(E(gl), "crop_damaged").is_empty(), "")

# ------------------------------------------------------------------ E21
func t_e21() -> void:
	var p: RefCounted = mk()
	var b: int = sp(p, "iron_jaw_beetle", 100, 100)
	hero(p, 112, 100)      # 主人公は3m以内
	p.host.helper_list = [{"id": 6, "pos": Vector2(190, 100), "hp": 40.0, "max_hp": 40.0}]   # 9m
	var tl: Array = sim(p, 10.0)
	var hd: Array = evs(E(tl), "helper_damage")
	ck("e21_prioritizes_helper_over_hero", hd.size() >= 1 and near(float(hd[0].amount), 20.0) and hero_dmg(tl).is_empty(), str(hd.size()))
	var t0: float = tl.filter(func(x: Dictionary) -> bool: return x.e.type == "fx" and x.e.kind == "windup")[0].t
	var t1: float = tl.filter(func(x: Dictionary) -> bool: return x.e.type == "helper_damage")[0].t
	ck("e21_windup_0.5s", near(t1 - t0, 0.5, 0.11), "%.2f" % (t1 - t0))
	# 主人公だけ: 3m以内で8。3mより遠いと無視
	var q: RefCounted = mk()
	sp(q, "iron_jaw_beetle", 100, 100)
	hero(q, 140, 100)
	ck("e21_ignores_hero_beyond_3m", hero_dmg(sim(q, 5.0)).is_empty(), "")
	var q2: RefCounted = mk()
	sp(q2, "iron_jaw_beetle", 100, 100)
	hero(q2, 120, 100)
	var q2l: Array = sim(q2, 4.0)
	var hh: Array = hero_dmg(q2l, 8.0)
	ck("e21_hero_within_3m_gets_8_with_1.5s_recovery", hh.size() >= 1 and hh.size() <= 3, str(hh.size()))
	if hh.size() >= 2:
		ck("e21_snip_interval_ge_2s", hh[1].t - hh[0].t >= 1.9, "%.2f" % (hh[1].t - hh[0].t))
	# 12mより遠いおたすけ植物は無視
	var r: RefCounted = mk()
	sp(r, "iron_jaw_beetle", 100, 100)
	hero(r, 400, 400)
	r.host.helper_list = [{"id": 6, "pos": Vector2(230, 100), "hp": 40.0, "max_hp": 40.0}]
	ck("e21_ignores_helper_beyond_12m", evs(E(sim(r, 5.0)), "helper_damage").is_empty(), "")

# ------------------------------------------------------------------ 共通
func t_common() -> void:
	# 安定判定: 生存中の全敵(擬態・黒焦げ・飛行・水中)を数え、中立は数えない。最後の撃破で0
	var p: RefCounted = mk()
	var ids: Array = []
	ids.append(sp(p, "grass_snake", 100, 100))        # 擬態
	ids.append(sp(p, "tarachunade", 120, 100))
	p.enemies.ref(ids[1]).state = "charred"
	ids.append(sp(p, "seed_bird", 140, 100))
	p.enemies.ref(ids[2]).state = "flying"
	ids.append(sp(p, "sludge_carp", 30, 30))          # 水中(潜行)
	ids.append(sp(p, "black_kite", 160, 100))         # 飛行
	ids.append(sp(p, "moss_turtle", 180, 100))        # 擬態
	ids.append(sp(p, "paint_chameleon", 60, 100))      # 擬態
	ids.append(sp(p, "mimic_cabbage", 80, 100))        # 擬態
	var hive: int = sp(p, "honeybee_hive", 200, 120)
	var all_counted: bool = true
	for i: int in ids:
		if not p.enemies.counts_for_stability(i):
			all_counted = false
	ck("stability_counts_8_special_states", all_counted and p.enemies.living_count_for_stability() == 8, str(p.enemies.living_count_for_stability()))
	ck("stability_excludes_hive_and_swarm", not p.enemies.counts_for_stability(hive) and p.enemies.living_for_stability().all(func(d: Dictionary) -> bool: return d.kind != "honeybee_hive" and d.kind != "honeybee_swarm"), "")
	var n0: int = p.enemies.living_count_for_stability()
	p.hit_enemy(ids[0], 1000.0, "shot", null)
	ck("stability_decrements_on_final_kill", p.enemies.living_count_for_stability() == n0 - 1, "")
	# 検知からの除外
	var det_kinds: Array = p.enemies.detectable_enemies().map(func(d: Dictionary) -> String: return d.kind)
	ck("detect_excludes_disguised_four", not det_kinds.has("moss_turtle") and not det_kinds.has("paint_chameleon") and not det_kinds.has("mimic_cabbage") and not det_kinds.has("grass_snake"), str(det_kinds))
	ck("detect_includes_flying_and_underwater", det_kinds.has("black_kite") and det_kinds.has("sludge_carp") and det_kinds.has("seed_bird"), str(det_kinds))
	# 飛行・潜行は射撃が当たらない
	var ht_kinds: Array = p.enemies.hittable_targets().map(func(d: Dictionary) -> String: return d.kind)
	ck("hittable_excludes_flying_diving_includes_disguised", not ht_kinds.has("black_kite") and not ht_kinds.has("sludge_carp") and not ht_kinds.has("seed_bird") and ht_kinds.has("moss_turtle") and ht_kinds.has("mimic_cabbage"), str(ht_kinds))
	# 安定地域には入らない: 地域に向けて突進しても入らない
	var s: RefCounted = mk()
	s.host.set_stable_rect(Rect2i(30, 20, 10, 10))   # px x120..160, y80..120
	var b: int = sp(s, "shadow_brian", 80, 100)
	hero(s, 200, 100)
	sim(s, 5.0)
	var cell: Vector2i = Vector2i(floori(R(s, b).pos.x / 4.0), floori(R(s, b).pos.y / 4.0))
	ck("enemy_never_enters_stable_cell", not s.host.is_stable_cell(cell) and R(s, b).pos.x < 120.0, str(R(s, b).pos))
	# トウガラシで逃げる敵、サボテンで反撃される
	var pp: RefCounted = mk()
	var e1: int = sp(pp, "shadow_brian", 100, 100)
	var pep: int = crop(pp, "pepper", 26, 25, true)
	var r1: Array[Dictionary] = []
	pp.enemies.hurt_crop(R(pp, e1), pep, 3.0, r1)
	ck("pepper_counter_2dmg_and_flee", evs(r1, "pepper_counter").size() == 1 and near(float(R(pp, e1).hp), 58.0) and float(R(pp, e1).flee_until) > pp.enemies.time, str(R(pp, e1).hp))
	var cac: RefCounted = mk()
	var e2: int = sp(cac, "shadow_brian", 100, 100)
	var cc: int = crop(cac, "cactus", 26, 25, true)
	var r2: Array[Dictionary] = []
	cac.enemies.hurt_crop(R(cac, e2), cc, 3.0, r2)
	ck("cactus_spine_3dmg", evs(r2, "cactus_thorn").size() == 1 and near(float(R(cac, e2).hp), 57.0), str(R(cac, e2).hp))
	# ハエトリソウが小型の敵を捕まえる(30ダメージ)。報酬は通常の撃破規則(1回)
	var ft: RefCounted = mk()
	var tt: int = sp(ft, "tarachunade", 100, 100)
	crop(ft, "flytrap", 26, 25, true)    # 隣接
	hero(ft, 400, 400)
	R(ft, tt).state = "idle"
	var r3: Array[Dictionary] = []
	ft.enemies.capture_check(R(ft, tt), r3)
	ck("flytrap_captures_small_enemy_30dmg", evs(r3, "flytrap_capture").size() == 1 and (not ft.enemies.is_alive(tt)) == true, str(r3.size()))
	ck("flytrap_kill_pays_initial_reward_once", evs(r3, "reward").size() == 0 or evs(r3, "reward").size() == 1, "")
	# ラベンダー: 虫は範囲を避ける(虫以外は避けない)
	var lv: RefCounted = mk()
	crop(lv, "lavender", 40, 25, true)
	var bug: int = sp(lv, "tarachunade", 130, 100)
	R(lv, bug).state = "chase"
	var beast: int = sp(lv, "shadow_brian", 150, 112)
	hero(lv, 230, 100)     # 虫を引き寄せる主人公
	ck("lavender_zone_covers_radius4", lv.crops.is_repelled_cell(Vector2i(37, 25), ["bug"]) and not lv.crops.is_repelled_cell(Vector2i(37, 25), ["beast"]), "")
	var sm: Array[Dictionary] = []
	lv.enemies.step_move(R(lv, bug), Vector2(1, 0), 40.0, 1.0, sm)
	ck("bug_cannot_walk_into_lavender_zone", R(lv, bug).pos.x < 144.0, str(R(lv, bug).pos))
	# 保存復元: 各状態(ガス・粘液・拾い物・群れ・抽選済み・親子・怒り)を含む往復と、以後の同一進行
	var a: RefCounted = mk(77)
	var fam: Dictionary = a.enemies.spawn_mushling_family(Vector2(100, 120))
	var wolves: Array = a.enemies.spawn_wolf_pack(Vector2(200, 50))
	sp(a, "slime_slug", 60, 100)
	sp(a, "honeybee_hive", 20, 120)
	var pcr: int = crop(a, "golden_four_leaf", 40, 25, true)
	sp(a, "pouch_rabbit", 150, 100)
	a.enemies.add_junk_pile(Vector2(60, 130), 2)
	sp(a, "junk_crab", 70, 130)
	crop(a, "clover", 45, 30, false)
	hero(a, 120, 125)
	a.hit_enemy(fam.children[0], 100.0, "shot", null)
	sim(a, 12.0)
	var saved: Dictionary = rt(a.to_dict())
	var bpk: RefCounted = mk(1)
	bpk.host.hero_state = a.host.hero_state.duplicate(true)
	ck("save_restore_ok", bpk.from_dict(saved), bpk.last_error)
	ck("save_has_gas_slime_pickups_pack_rolled", a.enemies.gas.size() >= 0 and a.enemies.slime.size() > 0 and bpk.enemies.slime.size() == a.enemies.slime.size() and bpk.enemies.gas.size() == a.enemies.gas.size() and bpk.crops.pickups.size() == a.crops.pickups.size(), "slime=%d gas=%d pick=%d" % [a.enemies.slime.size(), a.enemies.gas.size(), a.crops.pickups.size()])
	ck("save_roundtrip_exact", JSON.stringify(rt(bpk.to_dict())) == JSON.stringify(saved), "")
	var ea: Array = sim(a, 20.0)
	var eb: Array = sim(bpk, 20.0)
	var sa: String = JSON.stringify(rt(a.to_dict()))
	var sb: String = JSON.stringify(rt(bpk.to_dict()))
	var diff: String = ""
	if sa != sb:
		var da: Dictionary = JSON.parse_string(sa)
		var db: Dictionary = JSON.parse_string(sb)
		for sect: String in ["rng", "crops", "enemies"]:
			if JSON.stringify(da[sect]) != JSON.stringify(db[sect]):
				diff += sect + " "
		if JSON.stringify(da.enemies) != JSON.stringify(db.enemies):
			for k: String in da.enemies:
				if JSON.stringify(da.enemies[k]) != JSON.stringify(db.enemies[k]):
					diff += "[" + k + "]"
					if k == "enemies":
						for i: int in range(mini(da.enemies[k].size(), db.enemies[k].size())):
							if JSON.stringify(da.enemies[k][i]) != JSON.stringify(db.enemies[k][i]):
								for kk: String in da.enemies[k][i]:
									if JSON.stringify(da.enemies[k][i][kk]) != JSON.stringify(db.enemies[k][i].get(kk)):
										diff += " e%d.%s a=%s b=%s" % [i, kk, JSON.stringify(da.enemies[k][i][kk]), JSON.stringify(db.enemies[k][i].get(kk))]
	ck("restore_then_identical_progress_20s", approx_eq(JSON.parse_string(sa), JSON.parse_string(sb)), diff)
	# 壊れたデータでは何も変わらない
	var snap: String = JSON.stringify(rt(a.to_dict()))
	var bad: Dictionary = rt(a.to_dict())
	bad.enemies.enemies[0].kind = "nonexistent"
	ck("corrupt_enemy_kind_rejected_unchanged", not a.from_dict(bad) and JSON.stringify(rt(a.to_dict())) == snap, "")
	var bad2: Dictionary = rt(a.to_dict())
	bad2.crops.crops[0].cell = "x"
	ck("corrupt_crop_part_rejects_whole_unchanged", not a.from_dict(bad2) and JSON.stringify(rt(a.to_dict())) == snap, "")
	var bad3: Dictionary = rt(a.to_dict())
	bad3.enemies.slime = "oops"
	ck("corrupt_slime_container_rejected_unchanged", not a.from_dict(bad3) and JSON.stringify(rt(a.to_dict())) == snap, "")
	var bad4: Dictionary = rt(a.to_dict())
	bad4.rng.state = "abc"
	ck("corrupt_rng_rejected_unchanged", not a.from_dict(bad4) and JSON.stringify(rt(a.to_dict())) == snap, "")
	# 敵だけが壊れていて作物は正常: 作物も採用されない
	var bad5: Dictionary = rt(a.to_dict())
	bad5.enemies.enemies[1].hp = "NaN"
	bad5.crops.crops[0].paid = 12345
	ck("partial_corruption_adopts_nothing", not a.from_dict(bad5) and JSON.stringify(rt(a.to_dict())) == snap, "")
	# ポーズ: advanceを呼ばなければ進まない
	var t0: float = a.time()
	var s0: String = JSON.stringify(rt(a.to_dict()))
	a.hit_enemy(-1, 0.0, "shot", null)
	ck("pause_no_advance_no_change", near(a.time(), t0, 1e-12) and JSON.stringify(rt(a.to_dict())) == s0, "")
