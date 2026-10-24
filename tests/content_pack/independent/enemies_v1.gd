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

func rt(d: Dictionary) -> Dictionary:
	var v: Variant = JSON.parse_string(JSON.stringify(d))
	return v if typeof(v) == TYPE_DICTIONARY else {}

func _initialize() -> void:
	t_e01()
	t_e02()
	t_e03()
	t_e04()
	t_e05()
	t_e06()
	t_e07()
	t_e08()
	t_e09()
	t_e10()
	t_e11()
	var fails: int = 0
	var lines: Array = []
	for c: Dictionary in checks:
		var line: String = "%s %s %s" % [c.status, c.name, c.detail]
		print(line)
		lines.append(line)
		if c.status != "PASS":
			fails += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/enemies_v1.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "enemies_v1", "total": checks.size(), "failed": fails, "checks": checks}, "\t"))
	f.close()
	print("enemies_v1 total=%d failed=%d" % [checks.size(), fails])
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------ E01
func t_e01() -> void:
	var p: RefCounted = mk()
	var b: int = sp(p, "shadow_brian", 100, 120)    # face=DOWN(初期)
	# 正面(下)からの射撃は x0.25、背面は x1、たいあたり・バズーカは減らない
	var e1: Array = p.hit_enemy(b, 10.0, "shot", Vector2(100, 150))
	ck("e01_front_shot_x0.25", near(float(evs(e1, "enemy_damaged")[0].amount), 2.5), str(e1))
	var e2: Array = p.hit_enemy(b, 10.0, "shot", Vector2(100, 90))
	ck("e01_back_shot_x1", near(float(evs(e2, "enemy_damaged")[0].amount), 10.0), "")
	var e3: Array = p.hit_enemy(b, 4.0, "tackle", Vector2(100, 150))
	var e4: Array = p.hit_enemy(b, 4.0, "bazooka", Vector2(100, 150))
	ck("e01_front_tackle_bazooka_not_reduced", near(float(evs(e3, "enemy_damaged")[0].amount), 4.0) and near(float(evs(e4, "enemy_damaged")[0].amount), 4.0), "")
	var e5: Array = p.hit_enemy(b, 10.0, "shot", Vector2(150, 120))    # 真横(90度)は正面外
	ck("e01_side_shot_x1", near(float(evs(e5, "enemy_damaged")[0].amount), 10.0), "")
	# 予兆1.1秒→突進(8m/s)。主人公に20を1回
	var q: RefCounted = mk()
	var bq: int = sp(q, "shadow_brian", 100, 120)
	hero(q, 170, 120)
	var tl: Array = sim(q, 1.0)
	ck("e01_windup_1.1s_no_move_before", R(q, bq).state == "windup" and near(R(q, bq).pos.x, 100.0, 0.01) and fxs(E(tl), "windup").size() == 1, str(R(q, bq).state))
	var tl2: Array = sim(q, 2.5)
	var hd: Array = hero_dmg(tl2, 20.0)
	ck("e01_charge_hits_hero_20_once", hd.size() == 1, str(hero_dmg(tl2).map(func(x: Dictionary) -> float: return x.e.amount)))
	ck("e01_after_miss_recover_idle_or_stuck_at_map_edge", R(q, bq).state in ["idle", "recover", "stuck"], str(R(q, bq).state))
	# 壁に刺さる: 3秒動けず全方向x1.5。進路上の株は1株につき1回10
	var w: RefCounted = mk()
	var bw: int = sp(w, "shadow_brian", 128, 100)
	var cr: int = crop(w, "giant_watermelon", 0, 0, true)   # 無関係(位置は左上)
	w.crops.remove_crop(cr, "enemy")
	var cid: int = crop(w, "pumpkin", 31, 22, true)         # x124..131 y88..95 進路上(北)
	hero(w, 128, 150)
	sim(w, 0.5)
	hero(w, 128, 40)     # 予兆中に主人公が北へ(建物の向こう)
	var tw: Array = sim(w, 2.4)
	var stuck: Array = fxs(E(tw), "stuck")
	ck("e01_stuck_on_building", stuck.size() == 1 and R(w, bw).state == "stuck", str(R(w, bw).state))
	var cd: Array = evs(E(tw), "crop_damaged")
	ck("e01_crop_hit_exactly_once_10", cd.size() == 1 and near(float(cd[0].amount), 10.0, 0.001), str(cd.map(func(e: Dictionary) -> float: return e.amount)))
	var hp0: float = float(R(w, bw).hp)
	var e6: Array = w.hit_enemy(bw, 10.0, "shot", Vector2(100, 150))
	ck("e01_stuck_x1.5_all_directions", near(float(evs(e6, "enemy_damaged")[0].amount), 15.0), str(e6))
	sim(w, 3.1)
	ck("e01_stuck_ends_after_3s", R(w, bw).state != "stuck", str(R(w, bw).state))

# ------------------------------------------------------------------ E02
func t_e02() -> void:
	var p: RefCounted = mk()
	var t: int = sp(p, "tarachunade", 100, 120, "initial", {"tier": "mid"})
	hero(p, 115, 120)
	p.host.helper_list = [{"id": 7, "pos": Vector2(100, 135), "hp": 50.0, "max_hp": 50.0}]
	var c_in: int = crop(p, "clover", 25, 31)    # px(100..104,124..128): 距離 ~4px
	var c_out: int = crop(p, "clover", 40, 31)   # 距離 ~60px
	var other: int = sp(p, "shadow_brian", 100, 126)   # 爆発範囲内の別の敵
	R(p, other).state = "stuck"; R(p, other).until = 1e9
	var tl: Array = sim(p, 2.5)
	var ex: Array = fxs(E(tl), "explosion")
	ck("e02_explodes_once_with_windup", ex.size() == 1 and fxs(E(tl), "windup").size() == 1, str(ex.size()))
	var windup_t: float = tl.filter(func(x: Dictionary) -> bool: return x.e.type == "fx" and x.e.kind == "windup")[0].t
	var boom_t: float = tl.filter(func(x: Dictionary) -> bool: return x.e.type == "fx" and x.e.kind == "explosion")[0].t
	ck("e02_fuse_1.5s", near(boom_t - windup_t, 1.5, 0.11), "%.2f" % (boom_t - windup_t))
	ck("e02_blast_hero18_helper18", hero_dmg(tl, 18.0).size() == 1 and evs(E(tl), "helper_damage").size() == 1 and near(float(evs(E(tl), "helper_damage")[0].amount), 18.0), "")
	var cdm: Array = evs(E(tl), "crop_damaged")
	ck("e02_blast_crop10_only_in_radius", cdm.size() == 1 and near(float(cdm[0].amount), 10.0) and int(cdm[0].crop_id) == c_in and near(float(p.crops.get_crop(c_out).hp), 30.0), "")
	ck("e02_self_blast_no_hp_loss", near(float(R(p, t).hp), 30.0) and R(p, t).state == "charred", str(R(p, t).hp))
	ck("e02_blast_does_not_hurt_other_enemies", near(float(R(p, other).hp), 60.0), "")
	ck("e02_charred_counts_for_stability", p.enemies.counts_for_stability(t) and p.enemies.is_alive(t), "")
	# 黒焦げ15秒: 動かず攻撃しない、被ダメx2
	var pos0: Vector2 = R(p, t).pos
	var tl2: Array = sim(p, 10.0)
	ck("e02_charred_no_move_no_attack", R(p, t).pos == pos0 and hero_dmg(tl2).is_empty() and evs(E(tl2), "helper_damage").is_empty(), "")
	var h1: Array = p.hit_enemy(t, 3.0, "shot", null)
	ck("e02_charred_x2_damage", near(float(evs(h1, "enemy_damaged")[0].amount), 6.0), "")
	sim(p, 5.2)
	ck("e02_revive_after_15s_keeps_hp_state", R(p, t).state in ["recover", "chase"], str(R(p, t).state))
	var hp_after: float = float(R(p, t).hp)
	# 復活直後4秒は再爆発しない
	var nofuse_ok: bool = true
	var tl3: Array = sim(p, 3.5)
	if fxs(E(tl3), "explosion").size() > 0:
		nofuse_ok = false
	ck("e02_no_reexplode_for_4s_after_revive", nofuse_ok, "")
	var tl4: Array = sim(p, 4.0)
	ck("e02_reexplodes_later", fxs(E(tl4), "explosion").size() == 1, str(fxs(E(tl4), "explosion").size()))
	# 反復しても報酬は最終撃破の1回だけ。HPは減らない(黒焦げ中の被ダメ6を除く)
	var rewards: int = 0
	for i: int in range(3):
		var ex2: Array = sim(p, 25.0)
		rewards += evs(E(ex2), "reward").size()
	ck("e02_no_reward_from_blasts", rewards == 0 and p.enemies.is_alive(t), str(rewards))
	# 黒焦げ中に最終撃破
	var guard: int = 0
	while R(p, t).state != "charred" and guard < 400:
		sim(p, 0.5)
		guard += 1
	var fin: Array = p.hit_enemy(t, 100.0, "shot", null)
	ck("e02_final_kill_in_charred_one_reward_6", evs(fin, "reward").size() == 1 and int(evs(fin, "reward")[0].amount) == 6 and evs(fin, "reward")[0].tier == "mid" and not p.enemies.is_alive(t), str(fin.size()))
	ck("e02_no_second_reward", p.hit_enemy(t, 100.0, "shot", null).is_empty(), "")
	# 水: 予兆中の爆発を中断、湿り20秒は点火しない、歩いてかみつく
	var w: RefCounted = mk()
	var tw: int = sp(w, "tarachunade", 100, 120)
	hero(w, 112, 120)
	var wl: Array = sim(w, 0.6)
	ck("e02_water_setup_in_fuse", R(w, tw).state == "fuse", str(R(w, tw).state))
	w.hit_enemy(tw, 0.0, "water", null)
	var wl2: Array = sim(w, 19.0)
	ck("e02_wet_prevents_ignition_19s", fxs(E(wl2), "explosion").is_empty() and R(w, tw).state != "fuse", str(R(w, tw).state))
	var bites: Array = hero_dmg(wl2, 4.0)
	ck("e02_wet_bites_4_per_sec", bites.size() >= 14 and bites.size() <= 20, str(bites.size()))
	ck("e02_wet_counts_for_stability", w.enemies.counts_for_stability(tw), "")
	var wl3: Array = sim(w, 4.0)
	ck("e02_after_wet_can_ignite_again", fxs(E(wl3), "explosion").size() >= 1, str(fxs(E(wl3), "explosion").size()))
	# 待機はその場で動かない
	var idle: RefCounted = mk()
	var ti: int = sp(idle, "tarachunade", 100, 120)
	hero(idle, 200, 120)
	sim(idle, 10.0)
	ck("e02_idle_stays_put_when_far", R(idle, ti).pos == Vector2(100, 120) and R(idle, ti).state == "idle", "")
	# 7m以内を歩いて近づく(2m以内で始動)。2mより外では動かない
	var far: RefCounted = mk()
	var tf: int = sp(far, "tarachunade", 100, 120)
	hero(far, 140, 120)    # 4m: trigger(2m)の外
	sim(far, 3.0)
	ck("e02_no_trigger_outside_2m", R(far, tf).pos == Vector2(100, 120), "")

# ------------------------------------------------------------------ E03
func t_e03() -> void:
	var p: RefCounted = mk()
	var fam: Dictionary = p.enemies.spawn_mushling_family(Vector2(100, 120))
	var par: int = fam.parent
	var k1: int = fam.children[0]
	var k2: int = fam.children[1]
	ck("e03_family_group_and_parent_links", R(p, k1).group_id == fam.group_id and R(p, k1).parent_id == par and R(p, par).group_id == fam.group_id, "")
	# 生産しない
	hero(p, 400, 400)
	sim(p, 40.0)
	ck("e03_no_production", p.enemies.enemy_ids().size() == 3, str(p.enemies.enemy_ids().size()))
	# 子が主人公を5m以内で見つけ鳴く→親が25m以内なら4.5m/sで駆け寄る
	var q: RefCounted = mk()
	var fq: Dictionary = q.enemies.spawn_mushling_family(Vector2(40, 120))
	R(q, fq.parent).pos = Vector2(200, 125)
	R(q, fq.parent).home = Vector2(200, 125)
	hero(q, 130, 120)    # 子(30,130)/(50,130)から80px以上→5m外
	var nc: Array = sim(q, 2.0)
	ck("e03_no_call_when_hero_beyond_5m", evs(E(nc), "mushling_call").is_empty() and R(q, fq.parent).state != "rush", str(R(q, fq.parent).state))
	hero(q, 50, 160)   # 子1(50,130)から30px
	var ql: Array = sim(q, 0.3)
	var calls: Array = evs(E(ql), "mushling_call")
	ck("e03_child_calls_when_hero_within_5m", calls.size() >= 1, str(calls.size()))
	var p0: Vector2 = R(q, fq.parent).pos
	var ql2: Array = sim(q, 1.0)
	var moved: float = R(q, fq.parent).pos.distance_to(p0)
	ck("e03_parent_rushes_4.5mps", R(q, fq.parent).state == "rush" and moved > 38.0 and moved < 47.0, "moved=%.1f state=%s" % [moved, R(q, fq.parent).state])
	var calls_total: int = calls.size() + evs(E(ql2), "mushling_call").size()
	# 鳴き声は子ごとに15秒に1回まで
	var cnt: Dictionary = {}
	var q2: RefCounted = mk()
	var f2: Dictionary = q2.enemies.spawn_mushling_family(Vector2(100, 120))
	hero(q2, 110, 150)
	var ql4: Array = sim(q2, 31.0)
	for x: Dictionary in evs(E(ql4), "mushling_call"):
		cnt[x.enemy_id] = int(cnt.get(x.enemy_id, 0)) + 1
	var maxc: int = 0
	for k: Variant in cnt:
		maxc = maxi(maxc, int(cnt[k]))
	ck("e03_call_at_most_once_per_15s_each", maxc <= 3 and maxc >= 2, str(cnt))
	# ガス: 子が6秒ごと、半径1.2m、4秒、毎秒3。栽培植物には作用しない
	var gp: RefCounted = mk()
	var fg: Dictionary = gp.enemies.spawn_mushling_family(Vector2(100, 120))
	R(gp, fg.parent).hp = 70.0
	hero(gp, 108, 126)
	var gcrop: int = crop(gp, "clover", 27, 31)
	var gl: Array = sim(gp, 14.0)
	var gasd: Array = gl.filter(func(x: Dictionary) -> bool: return x.e.type == "hero_damage" and x.e.kind == "gas")
	ck("e03_gas_deals_3_per_sec_to_hero", gasd.size() >= 3 and gasd.all(func(x: Dictionary) -> bool: return near(float(x.e.amount), 3.0)), str(gasd.size()))
	ck("e03_gas_does_not_hurt_crops", evs(E(gl), "crop_damaged").size() == 0 and near(float(gp.crops.get_crop(gcrop).hp), 30.0), str(evs(E(gl), "crop_damaged").size()))
	ck("e03_gas_cloud_radius_and_duration", gp.enemies.gas_clouds().all(func(g: Dictionary) -> bool: return near(float(g.radius), 12.0) and float(g.until) - gp.enemies.time <= 4.0 + 0.01), str(gp.enemies.gas_clouds().size()))
	# 子が最終撃破→親は25秒怒る(速度x1.6、攻撃x1.5)。さらに子を倒すと25秒に戻る
	var r: RefCounted = mk()
	var fr: Dictionary = r.enemies.spawn_mushling_family(Vector2(100, 120))
	hero(r, 130, 120)
	var kill1: Array = r.hit_enemy(fr.children[0], 100.0, "shot", null)
	ck("e03_child_reward_3", evs(kill1, "reward").size() == 1 and int(evs(kill1, "reward")[0].amount) == 3, "")
	ck("e03_rage_fx_and_25s", fxs(kill1, "rage").size() == 1 and near(float(R(r, fr.parent).rage_until) - r.enemies.time, 25.0, 0.001), "")
	sim(r, 10.0)
	r.hit_enemy(fr.children[1], 100.0, "shot", null)
	ck("e03_rage_resets_to_25s", near(float(R(r, fr.parent).rage_until) - r.enemies.time, 25.0, 0.001), "")
	# 怒り中の近接: 8x1.5=12、間隔0.8秒
	hero(r, R(r, fr.parent).pos.x + 12.0, R(r, fr.parent).pos.y)
	var rl: Array = sim(r, 4.0)
	var hits: Array = hero_dmg(rl)
	ck("e03_rage_melee_12_every_0.8s", hits.size() >= 4 and hits.all(func(x: Dictionary) -> bool: return near(float(x.e.amount), 12.0)), str(hits.map(func(x: Dictionary) -> float: return x.t)))
	if hits.size() >= 3:
		ck("e03_rage_interval_0.8", near(hits[2].t - hits[1].t, 0.8, 0.11), "%.2f" % (hits[2].t - hits[1].t))
	var rr: Array = sim(r, 30.0, 0.1, func(pk: RefCounted, _t: float) -> void: hero(pk, 400, 400))
	ck("e03_rage_ends_parent_returns_to_normal", not r.enemies.is_alive(fr.children[0]) and float(R(r, fr.parent).rage_until) < r.enemies.time, "")
	# 親だけ: 鳴き声なし・通常の追跡。親を先に倒しても子は変わらない
	var s2: RefCounted = mk()
	var fs: Dictionary = s2.enemies.spawn_mushling_family(Vector2(100, 120))
	hero(s2, 112, 126)
	s2.hit_enemy(fs.parent, 1000.0, "shot", null)
	var sl: Array = sim(s2, 3.0)
	ck("e03_children_keep_calling_gassing_without_parent", evs(E(sl), "mushling_call").size() >= 1 and s2.enemies.is_alive(fs.children[0]), "")
	ck("e03_parent_death_no_rage", fxs(E(sl), "rage").is_empty(), "")
	var s3: RefCounted = mk()
	var f3: Dictionary = s3.enemies.spawn_mushling_family(Vector2(100, 120))
	s3.hit_enemy(f3.children[0], 1000.0, "shot", null)
	s3.hit_enemy(f3.children[1], 1000.0, "shot", null)
	hero(s3, 400, 400)
	sim(s3, 40.0)
	hero(s3, 112, 120)
	var s3l: Array = sim(s3, 3.0)
	ck("e03_parent_alone_no_calls_chases_normally", evs(E(s3l), "mushling_call").is_empty() and hero_dmg(s3l, 8.0).size() >= 1, str(hero_dmg(s3l).size()))

# ------------------------------------------------------------------ E04
func t_e04() -> void:
	var p: RefCounted = mk()
	var h: int = sp(p, "quill_hedgehog", 100, 120)
	hero(p, 155, 120)    # 5.5m
	var tl: Array = sim(p, 8.0)
	var needles: Array = hero_dmg(tl, 6.0)
	ck("e04_needles_6_dmg_every_2.5s", needles.size() >= 2 and needles.size() <= 4, str(needles.map(func(x: Dictionary) -> float: return x.t)))
	var d: float = R(p, h).pos.distance_to(hpos(p))
	ck("e04_keeps_4_to_6m", d >= 38.0 and d <= 62.0, "d=%.1f" % d)
	# 建物に遮られる
	var w: RefCounted = mk()
	sp(w, "quill_hedgehog", 128, 100)
	hero(w, 128, 40)
	var wl: Array = sim(w, 8.0)
	ck("e04_no_attack_without_line_of_sight", hero_dmg(wl).is_empty(), "")
	# 丸まり: 2.5m以内で、射撃x0.1。たいあたりで解けて2秒無防備(x1.5)
	var c: RefCounted = mk()
	var hc: int = sp(c, "quill_hedgehog", 100, 120)
	hero(c, 115, 120)
	sim(c, 0.3)
	ck("e04_curls_when_hero_within_2.5m", R(c, hc).state == "curl", str(R(c, hc).state))
	var s1: Array = c.hit_enemy(hc, 10.0, "shot", null)
	ck("e04_curl_shot_x0.1", near(float(evs(s1, "enemy_damaged")[0].amount), 1.0), "")
	var t1: Array = c.hit_enemy(hc, 2.0, "tackle", null)
	ck("e04_tackle_flips", R(c, hc).state == "flipped", str(R(c, hc).state))
	var s2: Array = c.hit_enemy(hc, 10.0, "shot", null)
	ck("e04_flipped_x1.5", near(float(evs(s2, "enemy_damaged")[0].amount), 15.0), "")
	sim(c, 2.1)
	ck("e04_flipped_ends_2s", R(c, hc).state != "flipped", str(R(c, hc).state))
	# 主人公が7m以内にいなければおたすけ植物を狙う
	var hp: RefCounted = mk()
	sp(hp, "quill_hedgehog", 100, 120)
	hero(hp, 220, 120)
	hp.host.helper_list = [{"id": 3, "pos": Vector2(150, 120), "hp": 30.0, "max_hp": 30.0}]
	var hl: Array = sim(hp, 6.0)
	ck("e04_targets_helper_when_hero_far", evs(E(hl), "helper_damage").size() >= 1 and hero_dmg(hl).is_empty(), str(evs(E(hl), "helper_damage").size()))

# ------------------------------------------------------------------ E05
func t_e05() -> void:
	var p: RefCounted = mk()
	var s: int = sp(p, "grass_snake", 100, 120)
	ck("e05_hidden_on_grass_not_detectable_but_hittable", p.enemies.detectable_enemies().is_empty() and p.enemies.hittable_targets().size() == 1, "")
	# 自分からは追わない(1.5m=15pxの外)
	hero(p, 125, 120)
	var tl0: Array = sim(p, 8.0)
	ck("e05_does_not_chase", R(p, s).pos == Vector2(100, 120) and hero_dmg(tl0).is_empty() and R(p, s).state == "hidden", "")
	hero(p, 112, 120)
	var tl: Array = sim(p, 0.3)
	ck("e05_windup_0.4s_then_bite", hero_dmg(tl).is_empty() and R(p, s).state == "strike", str(R(p, s).state))
	var tl1: Array = sim(p, 0.2)
	ck("e05_bite_10", hero_dmg(tl1, 10.0).size() == 1, "")
	hero(p, 400, 400)
	ck("e05_after_bite_visible_and_relocating", p.enemies.detectable_enemies().size() == 1 and R(p, s).state == "moving", str(R(p, s).state))
	var mv: Array = sim(p, 12.0)
	var dist: float = R(p, s).pos.distance_to(Vector2(100, 120))
	ck("e05_relocated_3plus_cells", dist >= 11.5, "dist=%.1f" % dist)
	ck("e05_rehides_in_grass", R(p, s).state == "hidden" and p.enemies.detectable_enemies().is_empty(), str(R(p, s).state))
	# 荒地では擬態できない
	var w: RefCounted = mk()
	var sw: int = sp(w, "grass_snake", 200, 110)     # 荒地(x176..224, y96..128)
	hero(w, 400, 400)
	sim(w, 10.0)
	ck("e05_wasteland_snake_always_visible", w.enemies.detectable_enemies().size() == 1 and R(w, sw).state == "revealed", str(R(w, sw).state))
	# 芽の段階でも擬態できない
	var sp2: RefCounted = mk()
	sp2.host.set_stage(Vector2i(25, 30), "sprout")
	var sn2: int = sp(sp2, "grass_snake", 102, 122)
	hero(sp2, 400, 400)
	sim(sp2, 6.0)
	ck("e05_sprout_cell_no_hide", sp2.enemies.detectable_enemies().size() == 1, "")
	# 見破り: 種(1m以内)・攻撃。6秒見える→2秒止まると擬態に戻る
	var r: RefCounted = mk()
	var sr: int = sp(r, "grass_snake", 100, 120)
	hero(r, 400, 400)
	r.enemies.notify_seed(Vector2(105, 120))
	ck("e05_seed_within_1m_reveals", r.enemies.detectable_enemies().size() == 1, "")
	sim(r, 5.5)
	ck("e05_still_visible_before_6s", r.enemies.detectable_enemies().size() == 1, "")
	sim(r, 2.7)
	ck("e05_hides_again_after_6s_plus_2s", r.enemies.detectable_enemies().is_empty(), str(R(r, sr).state))
	var far: RefCounted = mk()
	sp(far, "grass_snake", 100, 120)
	far.enemies.notify_seed(Vector2(115, 120))
	ck("e05_seed_beyond_1m_no_reveal", far.enemies.detectable_enemies().is_empty(), "")
	var hit: RefCounted = mk()
	var sh: int = sp(hit, "grass_snake", 100, 120)
	hit.hit_enemy(sh, 1.0, "shot", null)
	ck("e05_hit_reveals", hit.enemies.detectable_enemies().size() == 1, "")
	# ヒカリゴケ: 夜は見破る(昼は不可)
	var g: RefCounted = mk()
	sp(g, "grass_snake", 100, 120)
	crop(g, "glow_moss", 22, 30)
	ck("e05_glow_moss_day_no_reveal", g.enemies.detectable_enemies().is_empty(), "")
	g.host.day = false
	ck("e05_glow_moss_night_reveals", g.enemies.detectable_enemies().size() == 1, "")

# ------------------------------------------------------------------ E06
func t_e06() -> void:
	var p: RefCounted = mk()
	var b: int = sp(p, "seed_bird", 100, 100)
	hero(p, 400, 400)
	for cx: int in range(45, 49):
		p.host.set_stage(Vector2i(cx, 26), "seed")
	crop(p, "clover", 40, 26, true)
	var tl: Array = sim(p, 1.5)
	ck("e06_flies_to_seed_and_is_untouchable", R(p, b).state == "flying" and p.enemies.hittable_targets().is_empty() and p.hit_enemy(b, 5.0, "shot", null).is_empty() and near(float(R(p, b).hp), 8.0), str(R(p, b).state))
	var guard: int = 0
	while R(p, b).state == "flying" and guard < 300:
		sim(p, 0.1)
		guard += 1
	ck("e06_landing_is_hittable", R(p, b).state == "landing" and p.enemies.hittable_targets().size() == 1, str(R(p, b).state))
	ck("e06_landing_small_tag_for_flytrap", p.enemies.tags_of(R(p, b)).has("small"), "")
	var tl2: Array = sim(p, 6.5)
	var eaten: Array = evs(E(tl2), "ground_stage")
	ck("e06_eats_one_cell_per_2s", eaten.size() >= 2 and eaten.size() <= 4 and eaten.all(func(e: Dictionary) -> bool: return e.stage == "wasteland" and e.cause == "seed_bird"), str(eaten.size()))
	ck("e06_never_hurts_hero_or_crop", hero_dmg(tl2).is_empty() and evs(E(tl2), "crop_damaged").is_empty() and p.crops.crop_ids().size() == 1, "")
	# 主人公が4m以内: 離陸中は当たる→飛行へ
	hero(p, R(p, b).pos.x + 30.0, R(p, b).pos.y)
	sim(p, 0.3)
	ck("e06_hero_within_4m_takeoff_hittable", R(p, b).state == "takeoff" and p.enemies.is_hittable(R(p, b)), str(R(p, b).state))
	sim(p, 1.0)
	ck("e06_then_airborne_untouchable", R(p, b).state == "flying" or R(p, b).state == "perch", str(R(p, b).state))
	# 10マス食べたら家へ戻り20秒休む
	var q: RefCounted = mk()
	var bq: int = sp(q, "seed_bird", 100, 100)
	hero(q, 400, 400)
	for cx: int in range(25, 45):
		q.host.set_stage(Vector2i(cx, 26), "seed")
	var ql: Array = sim(q, 40.0)
	var n_eat: int = evs(E(ql), "ground_stage").size()
	ck("e06_eats_exactly_10_then_goes_home", n_eat == 10, str(n_eat))
	ck("e06_rests_at_perch", R(q, bq).state == "perch" and R(q, bq).pos.distance_to(Vector2(100, 100)) < 3.0, "%s %s" % [R(q, bq).state, str(R(q, bq).pos)])
	var t10: float = ql.filter(func(x: Dictionary) -> bool: return x.e.type == "ground_stage")[9].t
	var ql2: Array = sim(q, 70.0)
	var in_rest: Array = ql2.filter(func(x: Dictionary) -> bool: return x.e.type == "ground_stage" and x.t < t10 + 20.0)
	var after_rest: Array = ql2.filter(func(x: Dictionary) -> bool: return x.e.type == "ground_stage" and x.t >= t10 + 20.0)
	ck("e06_no_eating_for_20s_after_10th", in_rest.is_empty(), str(in_rest.size()))
	ck("e06_resumes_after_rest", after_rest.size() >= 1 and (after_rest[0].t - t10) < 40.0, "first resume %.1fs after 10th" % ((after_rest[0].t - t10) if after_rest.size() > 0 else -1.0))
	# 成熟した草は食べない
	var g: RefCounted = mk()
	sp(g, "seed_bird", 100, 100)
	hero(g, 400, 400)
	var gl: Array = sim(g, 20.0)
	ck("e06_ignores_grown_grass", evs(E(gl), "ground_stage").is_empty(), "")

# ------------------------------------------------------------------ E07
func t_e07() -> void:
	var p: RefCounted = mk()
	var a: int = p.enemies.add_junk_pile(Vector2(100, 120), 2)
	var b: int = p.enemies.add_junk_pile(Vector2(200, 120), 1)
	var c: int = sp(p, "junk_crab", 80, 120)
	hero(p, 400, 400)
	var s1: Array = p.hit_enemy(c, 20.0, "shot", null)
	ck("e07_shell_absorbs_shot", near(float(R(p, c).shell_hp), 10.0) and near(float(R(p, c).hp), 15.0) and evs(s1, "enemy_damaged").is_empty(), str(R(p, c).shell_hp))
	var s2: Array = p.hit_enemy(c, 5.0, "bazooka", null)
	ck("e07_bazooka_x2_on_shell_and_breaks", not bool(R(p, c).shell) and near(float(R(p, c).hp), 15.0) and evs(s2, "reward").is_empty(), str(R(p, c).shell))
	ck("e07_shell_break_no_reward", evs(s1 + s2, "reward").is_empty(), "")
	var tl: Array = sim(p, 6.0)
	ck("e07_naked_goes_to_pile_and_wears_shell_3s", fxs(E(tl), "shell_wear").size() == 1 and bool(R(p, c).shell) and near(float(R(p, c).shell_hp), 30.0), str(fxs(E(tl), "shell_wear").size()))
	ck("e07_pile_stock_decrements", p.enemies.get_pile(a).get("stock", -1) == 1, str(p.enemies.get_pile(a)))
	# 裸はx2。裸のとき倒すと報酬8を1回
	p.hit_enemy(c, 1000.0, "bazooka", null)
	var s3: Array = p.hit_enemy(c, 8.0, "shot", null)
	ck("e07_naked_x2_damage", near(float(evs(s3, "enemy_damaged")[0].amount), 16.0) and not p.enemies.is_alive(c), str(s3))
	ck("e07_final_kill_reward_8_once", evs(s3, "reward").size() == 1 and int(evs(s3, "reward")[0].amount) == 8, "")
	# 置き場は射撃で崩せる(HP20、報酬なし)。水・たいあたりは無効。消えた置き場は空きになる
	var q: RefCounted = mk()
	var pq: int = q.enemies.add_junk_pile(Vector2(100, 120), 2)
	ck("e07_pile_ignores_water", q.hit_enemy(pq, 20.0, "water", null).is_empty() and q.enemies.get_pile(pq).hp == 20.0, "")
	var h1: Array = q.hit_enemy(pq, 12.0, "shot", null)
	ck("e07_pile_hp20_survives_12", q.enemies.get_pile(pq).hp == 8.0 and h1.is_empty(), "")
	var h2: Array = q.hit_enemy(pq, 12.0, "shot", null)
	ck("e07_pile_destroyed_no_reward", evs(h2, "junk_pile_destroyed").size() == 1 and evs(h2, "reward").is_empty() and q.enemies.get_pile(pq).is_empty(), str(h2))
	# 主人公が置き場の2m以内なら次に近い置き場へ。在庫が尽きた置き場は消える
	var r: RefCounted = mk()
	var near_pile: int = r.enemies.add_junk_pile(Vector2(100, 120), 1)
	var far_pile: int = r.enemies.add_junk_pile(Vector2(180, 120), 2)
	var rc: int = sp(r, "junk_crab", 90, 120)
	R(r, rc).shell = false
	R(r, rc).shell_hp = 0.0
	hero(r, 108, 120)    # 近い置き場の2m以内(80? 8px)
	var rl: Array = sim(r, 6.0)
	ck("e07_skips_pile_when_hero_within_2m", R(r, rc).state != "wearing" and r.enemies.get_pile(near_pile).stock == 1, str(R(r, rc).state))
	# 置き場がなければ裸のまま戦う
	var n: RefCounted = mk()
	var nc: int = sp(n, "junk_crab", 100, 120)
	R(n, nc).shell = false
	R(n, nc).shell_hp = 0.0
	hero(n, 120, 120)
	var nl: Array = sim(n, 5.0)
	ck("e07_no_piles_stays_naked_and_scratches_4", not bool(R(n, nc).shell) and hero_dmg(nl, 4.0).size() >= 1, str(hero_dmg(nl).size()))
	# 殻付きの挟み: 6ダメージ
	var m: RefCounted = mk()
	var mc: int = sp(m, "junk_crab", 100, 120)
	hero(m, 112, 120)
	var ml: Array = sim(m, 5.0)
	ck("e07_shelled_claw_6", hero_dmg(ml, 6.0).size() >= 2, str(hero_dmg(ml).size()))

# ------------------------------------------------------------------ E08
func t_e08() -> void:
	var p: RefCounted = mk()
	var ids: Array = p.enemies.spawn_wolf_pack(Vector2(200, 46))
	ck("e08_pack_of_3_same_pack_id", ids.size() == 3 and R(p, ids[0]).pack_id == R(p, ids[1]).pack_id and R(p, ids[1]).pack_id == R(p, ids[2]).pack_id, "")
	hero(p, 200, 88)     # 約4m: 9m以内 → 遠吠え
	var tl: Array = sim(p, 0.2)
	ck("e08_howl_alerts_whole_pack", fxs(E(tl), "howl").size() >= 1 and ids.all(func(i: int) -> bool: return R(p, i).state == "howl"), str(ids.map(func(i: int) -> String: return R(p, i).state)))
	var tl2: Array = sim(p, 1.0)
	ck("e08_howl_1s_then_circle", ids.all(func(i: int) -> bool: return R(p, i).state in ["circle", "lunge", "recover"]), "")
	# 回り込み: 主人公の照準の±60°の外からだけ飛びかかる
	var aim: Vector2 = Vector2.LEFT
	hero(p, 200, 88, aim)
	var lunges: Array = []
	var tl3: Array = sim(p, 15.0, 0.1, func(pk: RefCounted, _t: float) -> void: hero(pk, 200, 88, aim))
	for x: Dictionary in tl3:
		if x.e.type == "fx" and x.e.kind == "windup":
			lunges.append(x.e.pos)
	var all_behind: bool = lunges.size() > 0
	for lp: Vector2 in lunges:
		var ang: float = absf(rad_to_deg(aim.angle_to(lp - hpos(p))))
		if ang <= 60.0:
			all_behind = false
	ck("e08_lunges_only_from_outside_front_arc", all_behind, "lunges=%d" % lunges.size())
	ck("e08_bites_7", hero_dmg(tl3, 7.0).size() >= 1, str(hero_dmg(tl3).size()))
	# 最後の1匹: 囲みをやめて正面から詰めて噛む、逃げない
	p.hit_enemy(ids[0], 1000.0, "shot", null)
	p.hit_enemy(ids[1], 1000.0, "shot", null)
	var tl4: Array = sim(p, 8.0, 0.1, func(pk: RefCounted, _t: float) -> void: hero(pk, 200, 88, aim))
	var last: Dictionary = R(p, ids[2])
	ck("e08_last_wolf_closes_in_and_bites_every_1.2s", hero_dmg(tl4, 7.0).size() >= 4 and last.pos.distance_to(hpos(p)) < 16.0, "d=%.1f bites=%d" % [last.pos.distance_to(hpos(p)), hero_dmg(tl4, 7.0).size()])
	# 報酬: 1匹ごと6
	var q: RefCounted = mk()
	var qi: Array = q.enemies.spawn_wolf_pack(Vector2(100, 110))
	var rw: int = 0
	for i: int in qi:
		rw += evs(q.hit_enemy(i, 1000.0, "shot", null), "reward").size()
	ck("e08_reward_each_wolf_once", rw == 3, str(rw))
	# 建物を背にすると背後に回れない: 壁際で囲みが失敗(噛みつきが減る)
	var w: RefCounted = mk()
	var wi: Array = w.enemies.spawn_wolf_pack(Vector2(128, 100))
	var wl: Array = sim(w, 15.0, 0.1, func(pk: RefCounted, _t: float) -> void: hero(pk, 128, 84, Vector2.DOWN))
	ck("e08_wall_at_back_reduces_bites", hero_dmg(wl).size() <= hero_dmg(tl3).size(), "wall=%d open=%d" % [hero_dmg(wl).size(), hero_dmg(tl3).size()])

# ------------------------------------------------------------------ E09
func t_e09() -> void:
	var p: RefCounted = mk()
	var t: int = sp(p, "moss_turtle", 100, 120)
	hero(p, 400, 400)
	ck("e09_hidden_not_detectable_but_hittable", p.enemies.detectable_enemies().is_empty() and p.enemies.hittable_targets().size() == 1, "")
	var cid: int = crop(p, "clover", 30, 30, true)    # px(120..124,120..124): 20px
	var tl: Array = sim(p, 6.0)
	ck("e09_moves_and_reveals_when_crop_within_6m", p.enemies.detectable_enemies().size() == 1 and R(p, t).state in ["walk", "eat"], str(R(p, t).state))
	var cd: Array = evs(E(tl), "crop_damaged")
	ck("e09_eats_crop_8_per_2s", cd.size() >= 1 and near(float(cd[0].amount), 8.0), str(cd.size()))
	# 反撃: 2m以内の主人公に噛みつく8
	hero(p, R(p, t).pos.x + 15.0, R(p, t).pos.y)
	var tl2: Array = sim(p, 3.0)
	ck("e09_bites_hero_within_2m_8", hero_dmg(tl2, 8.0).size() >= 1, "")
	hero(p, 400, 400)
	# 射撃x0.3、バズーカでひっくり返して4秒x3
	var s1: Array = p.hit_enemy(t, 10.0, "shot", null)
	ck("e09_shell_shot_x0.3", near(float(evs(s1, "enemy_damaged")[0].amount), 3.0), "")
	var s2: Array = p.hit_enemy(t, 10.0, "bazooka", null)
	ck("e09_bazooka_flips_4s", R(p, t).state == "flipped" and near(float(evs(s2, "enemy_damaged")[0].amount), 10.0), "")
	var s3: Array = p.hit_enemy(t, 10.0, "shot", null)
	ck("e09_flipped_x3", near(float(evs(s3, "enemy_damaged")[0].amount), 30.0), "")
	sim(p, 4.2)
	ck("e09_flip_ends_4s", R(p, t).state != "flipped", str(R(p, t).state))
	ck("e09_blocks_hero_body", p.enemies.body_blockers().size() == 1, "")
	# 擬態に戻る: 株がなければ10秒止まって擬態
	p.crops.remove_crop(cid, "manual")
	sim(p, 3.0)
	ck("e09_revealed_after_losing_crop", p.enemies.detectable_enemies().size() == 1, str(R(p, t).state))
	sim(p, 5.0)
	ck("e09_still_visible_before_10s", p.enemies.detectable_enemies().size() == 1, str(R(p, t).state))
	sim(p, 3.0)
	ck("e09_disguises_again_after_10s", p.enemies.detectable_enemies().is_empty(), str(R(p, t).state))
	var fin: Array = p.hit_enemy(t, 1000.0, "bazooka", null)
	ck("e09_death_fertile_1.2m_and_reward_15", evs(fin, "fertile").size() == 1 and near(float(evs(fin, "fertile")[0].radius_px), 12.0) and evs(fin, "reward").size() == 1 and int(evs(fin, "reward")[0].amount) == 15, str(fin.size()))
	# 通路ふさぎ: 死ぬと消える
	ck("e09_blocker_gone_after_death", p.enemies.body_blockers().is_empty(), "")

# ------------------------------------------------------------------ E10
func t_e10() -> void:
	var p: RefCounted = mk()
	var c: int = sp(p, "paint_chameleon", 100, 120)
	hero(p, 400, 400)
	ck("e10_hidden_not_detectable", p.enemies.detectable_enemies().is_empty(), "")
	hero(p, 112, 120)
	var tl: Array = sim(p, 0.5)
	ck("e10_ambush_12_from_hiding", hero_dmg(tl, 12.0).size() == 1, str(hero_dmg(tl).map(func(x: Dictionary) -> float: return x.e.amount)))
	var after: Vector2 = R(p, c).pos
	hero(p, 400, 400)
	ck("e10_moving_after_bite_with_hint_only", R(p, c).state == "moving" and p.enemies.detectable_enemies().is_empty() and p.enemies.hint_marks().size() == 1, "%s hint=%d" % [R(p, c).state, p.enemies.hint_marks().size()])
	sim(p, 6.0)
	ck("e10_retreated_about_4m", R(p, c).pos.distance_to(Vector2(100, 120)) > 30.0, "")
	# 攻撃が当たると4秒だけ見える
	var q: RefCounted = mk()
	var cq: int = sp(q, "paint_chameleon", 100, 120)
	hero(q, 400, 400)
	q.hit_enemy(cq, 1.0, "shot", null)
	ck("e10_hit_reveals", q.enemies.detectable_enemies().size() == 1, "")
	sim(q, 3.5)
	ck("e10_visible_for_4s_after_hit", q.enemies.detectable_enemies().size() == 1, "")
	sim(q, 2.5)
	ck("e10_hides_again_after_hit_reveal", q.enemies.detectable_enemies().is_empty(), str(R(q, cq).state))
	# 水でペンキが落ち、以後は常に見える。かみつきは8
	var w: RefCounted = mk()
	var cw: int = sp(w, "paint_chameleon", 100, 120)
	hero(w, 400, 400)
	w.hit_enemy(cw, 0.0, "water", null)
	ck("e10_water_removes_paint_visible", w.enemies.detectable_enemies().size() == 1 and not bool(R(w, cw).paint), "")
	sim(w, 40.0)
	ck("e10_visible_forever_after_water", w.enemies.detectable_enemies().size() == 1, str(R(w, cw).state))
	hero(w, 112, 120)
	var wl: Array = sim(w, 6.0)
	ck("e10_visible_bite_8", hero_dmg(wl, 8.0).size() >= 1 and hero_dmg(wl, 12.0).is_empty(), str(hero_dmg(wl).map(func(x: Dictionary) -> float: return x.e.amount)))
	# 夜のヒカリゴケで見破られる
	var g: RefCounted = mk()
	sp(g, "paint_chameleon", 100, 120)
	crop(g, "glow_moss", 25, 31)
	g.host.day = false
	ck("e10_glow_moss_night_reveals", g.enemies.detectable_enemies().size() == 1, "")

# ------------------------------------------------------------------ E11
func t_e11() -> void:
	var p: RefCounted = mk()
	var s: int = sp(p, "slime_slug", 102, 122)
	var cid: int = crop(p, "clover", 40, 30, true)
	hero(p, 400, 400)
	p.host.set_stage(Vector2i(26, 31), "sprout")
	var tl: Array = sim(p, 25.0)
	ck("e11_never_attacks_hero", hero_dmg(tl).is_empty(), "")
	ck("e11_crawls_toward_crop_leaving_slime", p.enemies.slime_cells().size() >= 3 and R(p, s).pos.x > 100.0, str(p.enemies.slime_cells().size()))
	ck("e11_slime_damages_crop_2_per_sec", evs(E(tl), "crop_damaged").size() >= 1 and evs(E(tl), "crop_damaged").all(func(e: Dictionary) -> bool: return near(float(e.amount), 2.0)), str(evs(E(tl), "crop_damaged").size()))
	ck("e11_grass_returns_to_wasteland_after_10s", evs(E(tl), "ground_stage").size() >= 1 and evs(E(tl), "ground_stage")[0].cause == "slime", str(evs(E(tl), "ground_stage").size()))
	# 主人公は粘液で50%減速
	var cells: Array = p.enemies.slime_cells()
	var best_i: int = 0
	for i: int in range(cells.size()):
		if float(cells[i].remaining) > float(cells[best_i].remaining):
			best_i = i
	var cc: Vector2i = cells[best_i].cell
	hero(p, float(cc.x) * 4.0 + 2.0, float(cc.y) * 4.0 + 2.0)
	var hl: Array = sim(p, 0.5)
	var slow: Array = evs(E(hl), "hero_slow")
	ck("e11_hero_slowed_50pct_on_slime", slow.size() >= 1 and near(float(slow[0].factor), 0.5), str(slow.size()))
	# 水で洗い流す
	p.enemies.splash(Vector2(float(cc.x) * 4.0 + 2.0, float(cc.y) * 4.0 + 2.0), 30.0, 0.0, "water")
	ck("e11_water_washes_slime_in_radius", not p.enemies.slime_at(cc), "")
	# 粘液は20秒で消える(スラッグ死亡後)
	p.hit_enemy(s, 1000.0, "shot", null)
	var remaining: int = p.enemies.slime_cells().size()
	sim(p, 21.0)
	ck("e11_slime_expires_after_20s", remaining > 0 and p.enemies.slime_cells().is_empty(), "%d -> %d" % [remaining, p.enemies.slime_cells().size()])
	# 種・芽の粘液で成長停止
	var q: RefCounted = mk()
	var sq: int = sp(q, "slime_slug", 102, 122)
	hero(q, 400, 400)
	var qs: Vector2i = Vector2i(25, 30)
	q.host.set_stage(qs, "seed")
	var ql: Array = sim(q, 1.0)
	ck("e11_seed_cell_growth_blocked_while_slime", evs(E(ql), "growth_pause").size() >= 1 and q.enemies.growth_blocked(qs), "")
	# 生産個体も報酬0・initialは6
	var rw: Array = q.hit_enemy(sq, 1000.0, "shot", null)
	ck("e11_reward_6", evs(rw, "reward").size() == 1 and int(evs(rw, "reward")[0].amount) == 6, "")
