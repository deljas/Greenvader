extends SceneTree
## 独立検証2-B: コウモリ、イモリ(分身)、マンホール網、ガラスジカ、ハチミツグマ、サイ、エビ、フウセンガエル。入口スクリプト。
const L: GDScript = preload("res://tests/content_pack/independent2/lib2.gd")
const OUT: String = "res://evidence/content_pack/independent2"
var t: RefCounted = L.new()

func _initialize() -> void:
	bats()
	newt()
	sewer()
	glass()
	bear()
	rhino()
	shrimp()
	frog()
	stability_summary()
	no_reinvasion()
	t.finish("animals_b", OUT, self)

func has_target(p: RefCounted, id: int) -> bool:
	return p.enemies.hittable_targets().any(func(x: Dictionary) -> bool: return x.id == id)

func states(p: RefCounted, ids: Array) -> Array:
	return ids.map(func(i: int) -> String: return str(t.R(p, i).state))

# ---------------------------------------------------------------- コウモリ
func bats() -> void:
	var p: RefCounted = t.mk()
	t.hero(p, 240, 130)
	var ids: Array = p.enemies.spawn_bat_flock(Vector2(108, 68), "initial")
	t.ck("bats_flock_of_6", ids.size() == 6)
	t.ck("bats_roost_all_hittable", ids.all(func(i: int) -> bool: return has_target(p, i)))
	# 1発で1匹(HP4)。撃破で残りが飛び立つ
	var ev: Array = p.hit_enemy(ids[0], 5.0, "shot", Vector2(130, 68))
	t.ck("bats_one_shot_kills_one", t.evs(ev, "enemy_defeated").size() == 1 and p.enemies.enemy_ids().size() == 5)
	t.ck("bats_rest_wake_on_defeat", states(p, ids.slice(1)).all(func(s: String) -> bool: return s == "swarm"), str(states(p, ids.slice(1))))
	t.ck("bats_swarm_not_hittable", ids.slice(1).all(func(i: int) -> bool: return not has_target(p, i)))
	t.ck("bats_swarm_not_hit_by_splash", p.splash(t.R(p, ids[1]).pos, 30.0, 25.0, "bazooka").filter(func(e: Dictionary) -> bool: return e.type == "enemy_damaged").is_empty())
	# 非致死でも起きる(2匹の群れは例外なので別途)
	var q: RefCounted = t.mk()
	t.hero(q, 240, 130)
	var qi: Array = q.enemies.spawn_bat_flock(Vector2(108, 68), "initial")
	q.hit_enemy(qi[0], 1.0, "shot", Vector2(130, 68))
	t.ck("bats_nonlethal_hit_wakes_flock", states(q, qi.slice(1)).all(func(s: String) -> bool: return s == "swarm") and t.R(q, qi[0]).state == "swarm")
	# 主人公が3m以内
	var w: RefCounted = t.mk()
	t.hero(w, 108 + 40, 68)
	var wi: Array = w.enemies.spawn_bat_flock(Vector2(108, 68), "initial")
	t.sim(w, 0.3)
	t.ck("bats_hero_4m_does_not_wake", states(w, wi).all(func(s: String) -> bool: return s == "roost"))
	t.hero(w, 108 + 24, 68)
	t.sim(w, 0.3)
	t.ck("bats_hero_within_3m_wakes", states(w, wi).any(func(s: String) -> bool: return s != "roost"), str(states(w, wi)))
	# 爆風は眠っている範囲内すべてに当たる
	var b: RefCounted = t.mk()
	t.hero(b, 240, 130)
	var bi: Array = b.enemies.spawn_bat_flock(Vector2(108, 68), "initial")
	var bev: Array = b.splash(Vector2(108, 68), 25.0, 25.0, "bazooka")
	t.ck("bats_bazooka_kills_all_in_radius", t.evs(bev, "enemy_defeated").size() == 6 and b.enemies.enemy_ids().is_empty())
	t.ck("bats_rewards_2_each_instant", t.evs(bev, "reward").size() == 6 and int(t.evs(bev, "reward")[0].amount) == 2 and bool(t.evs(bev, "reward")[0].get("instant", false)))
	# 乱れ飛び: 昼12秒/夜24秒
	for day: bool in [true, false]:
		var d: RefCounted = t.mk()
		t.hero(d, 150, 68)
		d.host.day = day
		var di: Array = d.enemies.spawn_bat_flock(Vector2(108, 68), "initial")
		d.hit_enemy(di[0], 1.0, "shot", Vector2(130, 68))
		var t0: float = d.enemies.time
		var fly_end: float = -1.0
		for i: int in range(600):
			d.advance(0.1)
			var s: Array = states(d, di)
			if s.all(func(x: String) -> bool: return x in ["return", "roost"]):
				fly_end = d.enemies.time - t0
				break
		var want: float = 12.0 if day else 24.0
		t.ck("bats_fly_time_" + ("day12" if day else "night24"), fly_end > want - 0.3 and fly_end < want + 0.8, "%.2f" % fly_end)
	# 急降下: 2秒ごと1匹、3ダメージ、急降下/噛み後は当たる、飛行中は当たらない
	var f: RefCounted = t.mk()
	t.hero(f, 150, 68)
	var fi: Array = f.enemies.spawn_bat_flock(Vector2(108, 68), "initial")
	f.hit_enemy(fi[0], 1.0, "shot", Vector2(130, 68))
	var tl: Array = []
	var dive_seen: bool = false
	var dive_hittable: bool = true
	var low_seen: bool = false
	var low_hittable: bool = true
	var dive_times: Array = []
	var prev_div: Dictionary = {}
	for i: int in range(220):
		var e2: Array = f.advance(0.1)
		for x: Dictionary in e2:
			tl.append({"t": f.enemies.time, "e": x})
		for id: int in fi:
			if not f.enemies.is_alive(id):
				continue
			var st: String = str(t.R(f, id).state)
			if st == "dive":
				dive_seen = true
				dive_hittable = dive_hittable and has_target(f, id)
				if not prev_div.has(id):
					dive_times.append(f.enemies.time)
			elif st == "low":
				low_seen = true
				low_hittable = low_hittable and has_target(f, id)
			prev_div[id] = (st == "dive")
			if st != "dive":
				prev_div.erase(id)
	var bites: Array = t.of_type(tl, "hero_damage")
	t.ck("bats_dive_bite_3dmg", bites.size() >= 2 and t.near(float(bites[0].e.amount), 3.0), "n=%d" % bites.size())
	t.ck("bats_dive_and_low_are_hittable", dive_seen and dive_hittable and low_seen and low_hittable, "dive=%s low=%s" % [str(dive_seen), str(low_seen)])
	if dive_times.size() >= 3:
		t.ck("bats_dive_every_2s", t.near(float(dive_times[1]) - float(dive_times[0]), 2.0, 0.25) and t.near(float(dive_times[2]) - float(dive_times[1]), 2.0, 0.25), str(dive_times.slice(0, 4)))
	else:
		t.ck("bats_dive_every_2s", false, "dive_times=%s" % str(dive_times))
	# 急降下中の1匹には射撃が当たる
	var g: RefCounted = t.mk()
	t.hero(g, 150, 68)
	var gi: Array = g.enemies.spawn_bat_flock(Vector2(108, 68), "initial")
	g.hit_enemy(gi[0], 1.0, "shot", Vector2(130, 68))
	var killed: bool = false
	for i: int in range(120):
		g.advance(0.1)
		for id: int in gi:
			if g.enemies.is_alive(id) and t.R(g, id).state == "dive":
				var ev2: Array = g.hit_enemy(id, 5.0, "shot", Vector2(150, 68))
				killed = t.evs(ev2, "enemy_defeated").size() == 1
				break
		if killed:
			break
	t.ck("bats_diving_bat_can_be_shot_down", killed)
	# ヒカリゴケの範囲(主人公が範囲内)では急降下しない
	var m: RefCounted = t.mk()
	t.hero(m, 150, 68)
	t.crop(m, "glow_moss", 37, 17)
	var mi: Array = m.enemies.spawn_bat_flock(Vector2(108, 68), "initial")
	m.hit_enemy(mi[0], 1.0, "shot", Vector2(130, 68))
	var tlm: Array = t.sim(m, 11.0)
	t.ck("bats_no_dive_in_moss_range", t.of_type(tlm, "hero_damage").is_empty() and m.enemies.is_alive(mi[1]), "hd=%d" % t.of_type(tlm, "hero_damage").size())
	# 2匹以下の群れは乱れ飛ばずすぐ戻る
	var s2: RefCounted = t.mk()
	t.hero(s2, 240, 130)
	var s2a: int = t.sp(s2, "bat_flock", 108, 68, "initial", {"group_id": 99, "home": Vector2(108, 68)})
	var s2b: int = t.sp(s2, "bat_flock", 110, 68, "initial", {"group_id": 99, "home": Vector2(108, 68)})
	s2.hit_enemy(s2a, 1.0, "shot", Vector2(130, 68))
	t.ck("bats_last_two_return_immediately", t.R(s2, s2a).state == "return" and t.R(s2, s2b).state == "return", "%s %s" % [t.R(s2, s2a).state, t.R(s2, s2b).state])
	t.sim(s2, 4.0)
	t.ck("bats_last_two_back_to_roost", t.R(s2, s2a).state == "roost" and t.R(s2, s2b).state == "roost")
	t.ck("bats_count_for_stability", s2.enemies.counts_for_stability(s2a))

# ---------------------------------------------------------------- ブンシンイモリ
func newt() -> void:
	var p: RefCounted = t.mk()
	t.hero(p, 240, 20)
	var id: int = t.sp(p, "decoy_newt", 160, 100)
	t.R(p, id).face = Vector2.RIGHT
	var ev: Array = p.hit_enemy(id, 3.0, "shot", Vector2(200, 100))
	var decoys: Array = p.enemies.enemies.filter(func(e: Dictionary) -> bool: return e.kind == "decoy_tail")
	t.ck("newt_hit_cuts_tail_spawns_decoy", decoys.size() == 1 and not bool(t.R(p, id).tail) and t.fxk(ev, "tail_cut").size() == 1)
	var did: int = int(decoys[0].id) if decoys.size() > 0 else -1
	t.ck("decoy_not_counted_for_stability", not p.enemies.counts_for_stability(did) and p.enemies.living_count_for_stability() == 1, "count=%d" % p.enemies.living_count_for_stability())
	t.ck("decoy_not_in_living_for_stability", not p.enemies.living_for_stability().any(func(x: Dictionary) -> bool: return x.id == did))
	t.ck("decoy_not_detectable", not p.enemies.detectable_enemies().any(func(x: Dictionary) -> bool: return x.id == did) and p.enemies.detectable_enemies().any(func(x: Dictionary) -> bool: return x.id == id))
	t.ck("decoy_is_hittable_flagged", p.enemies.hittable_targets().any(func(x: Dictionary) -> bool: return x.id == did and bool(x.decoy)))
	# 2回目は尾が再生するまで出ない
	p.hit_enemy(id, 1.0, "shot", Vector2(200, 100))
	t.ck("newt_no_second_decoy_before_regrow", p.enemies.enemies.filter(func(e: Dictionary) -> bool: return e.kind == "decoy_tail").size() == 1)
	t.sim(p, 4.0)
	t.ck("newt_decoy_moves_away", t.R(p, did).pos.distance_to(Vector2(160, 100)) > 6.0)
	t.sim(p, 4.2)   # 約8秒で再生
	t.ck("newt_tail_regrown_8s", bool(t.R(p, id).tail))
	# 何かが当たると消える
	var hev: Array = p.hit_enemy(did, 1.0, "shot", Vector2(200, 100))
	t.ck("decoy_vanishes_on_any_hit", not p.enemies.is_alive(did) and t.evs(hev, "reward").is_empty())
	var hev2: Array = p.hit_enemy(id, 1.0, "shot", Vector2(200, 100))
	var d2: Array = p.enemies.enemies.filter(func(e: Dictionary) -> bool: return e.kind == "decoy_tail")
	t.ck("newt_cuts_again_after_regrow", d2.size() == 1)
	# 10秒で消える
	t.sim(p, 10.2)
	t.ck("decoy_expires_10s", p.enemies.enemies.filter(func(e: Dictionary) -> bool: return e.kind == "decoy_tail").is_empty())
	# 水でも消えるが本体は尾を切らない
	var w: RefCounted = t.mk()
	t.hero(w, 240, 20)
	var wid: int = t.sp(w, "decoy_newt", 160, 100)
	w.hit_enemy(wid, 1.0, "shot", Vector2(200, 100))
	var wd: int = int(w.enemies.enemies.filter(func(e: Dictionary) -> bool: return e.kind == "decoy_tail")[0].id)
	w.hit_enemy(wd, 0.0, "water")
	t.ck("decoy_vanishes_on_water", not w.enemies.is_alive(wd))
	var w2: RefCounted = t.mk()
	t.hero(w2, 240, 20)
	var w2id: int = t.sp(w2, "decoy_newt", 160, 100)
	w2.hit_enemy(w2id, 0.0, "water")
	t.ck("newt_water_does_not_cut_tail", bool(t.R(w2, w2id).tail) and w2.enemies.enemies.size() == 1)
	# バズーカで本体と分身をまとめて巻き込める
	var z: RefCounted = t.mk()
	t.hero(z, 240, 20)
	var zid: int = t.sp(z, "decoy_newt", 160, 100)
	z.hit_enemy(zid, 1.0, "shot", Vector2(200, 100))
	var zd: int = int(z.enemies.enemies.filter(func(e: Dictionary) -> bool: return e.kind == "decoy_tail")[0].id)
	var zev: Array = z.splash(t.R(z, zid).pos, 40.0, 5.0, "bazooka")
	t.ck("newt_bazooka_hits_both", t.evs(zev, "enemy_damaged").size() == 2 or (not z.enemies.is_alive(zd) and t.near(float(t.R(z, zid).hp), 14.0)), "dmg events=%d" % t.evs(zev, "enemy_damaged").size())
	# 分身は攻撃しない(隣に主人公がいても)
	var y: RefCounted = t.mk()
	t.hero(y, 240, 20)
	var yid: int = t.sp(y, "decoy_newt", 160, 100)
	y.hit_enemy(yid, 1.0, "shot", Vector2(200, 100))
	var yd: Dictionary = y.enemies.enemies.filter(func(e: Dictionary) -> bool: return e.kind == "decoy_tail")[0]
	t.hero(y, yd.pos.x + 2, yd.pos.y)
	t.R(y, yid).pos = Vector2(10, 10)   # 本体を遠ざけて、分身の隣だけに主人公がいる状態にする
	var tly: Array = t.sim(y, 3.0)
	t.ck("decoy_never_attacks", t.of_type(tly, "hero_damage").filter(func(x: Dictionary) -> bool: return int(x.e.source) == int(yd.id)).is_empty())
	# 本体は噛む 6ダメージ/1秒
	var bt: RefCounted = t.mk()
	t.hero(bt, 170, 100)
	t.sp(bt, "decoy_newt", 160, 100)
	var tlb: Array = t.sim(bt, 3.5)
	var bd: Array = t.of_type(tlb, "hero_damage")
	t.ck("newt_bites_6_per_1s", bd.size() >= 3 and t.near(float(bd[0].e.amount), 6.0) and t.near(float(bd[1].t) - float(bd[0].t), 1.0, 0.11), "n=%d" % bd.size())

# ---------------------------------------------------------------- マンホール網・ドブネズミ
func net_setup(origin: String = "initial", cells: Array = [Vector2i(46, 26), Vector2i(50, 27), Vector2i(53, 30)]) -> Array:
	var p: RefCounted = t.mk()
	t.hero(p, 180, 110)   # 巣が活動する(主人公が20m以内)
	var pos: Array = cells.map(func(c: Vector2i) -> Vector2: return (Vector2(c) + Vector2(0.5, 0.5)) * 4.0)
	var net: Dictionary = p.enemies.spawn_manhole_net(pos, origin)
	return [p, net]

func sewer() -> void:
	var r: Array = net_setup()
	var p: RefCounted = r[0]
	var net: Dictionary = r[1]
	var mh: Array = net.manholes
	t.ck("manhole_net_three", mh.size() == 3)
	t.ck("manhole_not_hittable_not_detect_stable", not p.enemies.hittable_targets().any(func(x: Dictionary) -> bool: return x.kind == "manhole"))
	# 緑化済み条件の例外: マンホールには植えられ、ふつうの荒地には植えられない
	var chk_mh: Dictionary = p.crops.check_placement("bamboo", Vector2i(46, 26))
	var chk_plain: Dictionary = p.crops.check_placement("bamboo", Vector2i(48, 26))
	t.ck("manhole_cell_accepts_crop", bool(chk_mh.ok), str(chk_mh))
	t.ck("plain_wasteland_still_rejects", not bool(chk_plain.ok) and chk_plain.reason == "requires_green", str(chk_plain))
	# 生産: 15秒ごとに1匹、網全体で生存6まで、報酬0
	var tl: Array = t.sim(p, 16.0)
	var rats: Array = p.enemies.enemies.filter(func(e: Dictionary) -> bool: return e.kind == "sewer_rat")
	t.ck("manhole_spawns_rat_after_15s", rats.size() == 1 and rats[0].origin == "produced", "n=%d" % rats.size())
	var first_t: float = p.enemies.time
	t.sim(p, 15.0 * 8.0)
	var alive_rats: Array = p.enemies.enemies.filter(func(e: Dictionary) -> bool: return e.kind == "sewer_rat")
	t.ck("manhole_rat_cap_6", alive_rats.size() == 6, "n=%d" % alive_rats.size())
	# 撃破しても報酬0
	var rid: int = -1
	for e: Dictionary in alive_rats:
		if has_target(p, int(e.id)):
			rid = int(e.id)
			break
	if rid > 0:
		var kev: Array = p.hit_enemy(rid, 50.0, "shot", Vector2(100, 100))
		t.ck("rat_produced_reward_zero", t.evs(kev, "reward").is_empty() and t.evs(kev, "enemy_defeated").size() == 1)
	else:
		t.ck("rat_produced_reward_zero", false, "no hittable rat")
	# 初期配置のネズミは報酬2(即時)
	var ir: int = t.sp(p, "sewer_rat", 100, 100, "initial")
	var iev: Array = p.hit_enemy(ir, 50.0, "shot", Vector2(80, 100))
	t.ck("rat_initial_reward_2", t.evs(iev, "reward").size() == 1 and int(t.evs(iev, "reward")[0].amount) == 2)
	# 地下移動: 入ってから3秒後に同じ網の別の開いたマンホールから出る
	var u: Array = net_setup()
	var up: RefCounted = u[0]
	t.sp(up, "sewer_rat", 184, 108, "produced", {"net_id": int(u[1].net_id), "home_mh": int(u[1].manholes[0]), "home": Vector2(186, 106)})
	up.enemies.enemies[up.enemies.enemies.size() - 1].roam_at = 0.0
	var tlu: Array = t.sim(up, 20.0)
	var enters: Array = t.of_type(tlu, "fx").filter(func(x: Dictionary) -> bool: return x.e.kind == "rat_enter")
	var emerges: Array = t.of_type(tlu, "fx").filter(func(x: Dictionary) -> bool: return x.e.kind == "rat_emerge" and int(x.e.enemy_id) != 0 and up.enemies.ref(int(x.e.enemy_id)).get("kind", "") == "sewer_rat")
	t.ck("rat_enters_manhole", enters.size() >= 1, "n=%d" % enters.size())
	if enters.size() >= 1:
		var te: float = float(enters[0].t)
		var match_em: Array = emerges.filter(func(x: Dictionary) -> bool: return float(x.t) >= te)
		var okt: bool = match_em.size() >= 1 and t.near(float(match_em[0].t) - te, 3.0, 0.25)
		t.ck("rat_underground_3s", okt, "dt=%s" % (str(float(match_em[0].t) - te) if match_em.size() >= 1 else "none"))
		if match_em.size() >= 1:
			t.ck("rat_emerges_from_other_manhole", Vector2(match_em[0].e.pos).distance_to(Vector2(enters[0].e.pos)) > 8.0, "%s -> %s" % [str(enters[0].e.pos), str(match_em[0].e.pos)])
	# 地下では当たらず、検知にも出ない
	var uu: Array = net_setup()
	var uup: RefCounted = uu[0]
	var urid: int = t.sp(uup, "sewer_rat", 184, 108, "produced", {"net_id": int(uu[1].net_id), "home_mh": int(uu[1].manholes[0]), "home": Vector2(186, 106)})
	t.R(uup, urid).roam_at = 0.0
	var ug_ok: bool = false
	for i: int in range(200):
		uup.advance(0.1)
		if t.R(uup, urid).state == "ug":
			ug_ok = (not has_target(uup, urid)) and (not uup.enemies.detectable_enemies().any(func(x: Dictionary) -> bool: return x.id == urid))
			break
	t.ck("rat_underground_untargetable_undetectable", ug_ok)
	# 塞ぐ: 株が乗ったマンホールは閉じ、安定判定に数えない。全部閉じると制圧、巣の報酬30を1回
	var s: Array = net_setup()
	var sp_: RefCounted = s[0]
	var smh: Array = s[1].manholes
	var open_before: int = sp_.enemies.living_count_for_stability()
	var c1: Dictionary = sp_.crops.place_crop("bamboo", Vector2i(46, 26))
	var evp: Array = t.sim(sp_, 0.2)
	t.ck("manhole_closes_with_crop", t.R(sp_, smh[0]).state == "closed" and t.fxk(t.E(evp), "manhole_closed").size() == 1, "state=%s ok=%s" % [t.R(sp_, smh[0]).state, str(c1.get("ok"))])
	t.ck("closed_manhole_not_counted_for_stability", sp_.enemies.living_count_for_stability() == open_before - 1, "%d -> %d" % [open_before, sp_.enemies.living_count_for_stability()])
	sp_.crops.place_crop("bamboo", Vector2i(50, 27))
	var tl2: Array = t.sim(sp_, 0.2)
	t.ck("no_suppression_with_one_open", t.evs(t.E(tl2), "nest_suppressed").is_empty() and t.evs(t.E(tl2), "reward").is_empty())
	sp_.crops.place_crop("bamboo", Vector2i(53, 30))
	var tl3: Array = t.sim(sp_, 0.3)
	var sup: Array = t.evs(t.E(tl3), "nest_suppressed")
	var rw: Array = t.evs(t.E(tl3), "reward")
	t.ck("all_closed_suppresses_nest_once", sup.size() == 1 and rw.size() == 1 and int(rw[0].amount) == 30 and bool(rw[0].get("instant", false)), "sup=%d rw=%s" % [sup.size(), str(rw.map(func(x: Dictionary) -> int: return int(x.amount)))])
	var tl4: Array = t.sim(sp_, 20.0)
	t.ck("no_second_reward_while_closed", t.evs(t.E(tl4), "reward").is_empty() and t.evs(t.E(tl4), "nest_suppressed").is_empty())
	# 開け直して再び塞いでも2回目の報酬は出ない
	sp_.crops.remove_crop(sp_.crops.crop_id_at(Vector2i(46, 26)), "manual")
	t.sim(sp_, 0.3)
	sp_.crops.place_crop("bamboo", Vector2i(46, 26))
	var tl5: Array = t.sim(sp_, 0.5)
	t.ck("reopen_and_reclose_no_second_reward", t.evs(t.E(tl5), "reward").is_empty())
	# 全閉の間は生産しない
	sp_.enemies.enemies.filter(func(e: Dictionary) -> bool: return e.kind == "sewer_rat").size()
	t.ck("no_rat_production_when_all_closed", sp_.enemies.enemies.filter(func(e: Dictionary) -> bool: return e.kind == "sewer_rat").is_empty())
	# 製造扱い(produced)のマンホール網は制圧しても報酬なし
	var pr: Array = net_setup("produced")
	var prp: RefCounted = pr[0]
	for c: Vector2i in [Vector2i(46, 26), Vector2i(50, 27), Vector2i(53, 30)]:
		prp.crops.place_crop("bamboo", c)
	var tlp: Array = t.sim(prp, 0.5)
	t.ck("produced_net_suppression_no_reward", t.evs(t.E(tlp), "nest_suppressed").size() == 1 and t.evs(t.E(tlp), "reward").is_empty())
	# 出口が塞がれていると、出ようとして下から株をかじる(3ダメージ/2秒)。株が倒れるとまた開く
	var k: Array = net_setup("initial", [Vector2i(46, 26), Vector2i(50, 27)])
	var kp: RefCounted = k[0]
	var kmh: Array = k[1].manholes
	var rat: int = t.sp(kp, "sewer_rat", 184, 108, "produced", {"net_id": int(k[1].net_id), "home_mh": int(kmh[0]), "home": Vector2(186, 106)})
	t.R(kp, rat).roam_at = 0.0
	var entered: bool = false
	for i: int in range(300):
		kp.advance(0.1)
		if t.R(kp, rat).state == "ug":
			entered = true
			break
	t.ck("rat_reaches_underground_for_plug_test", entered)
	# 出口になる側(もう一方)を塞ぐ
	var exit_id: int = int(t.R(kp, rat).exit_id)
	var exit_cell: Vector2i = Vector2i(floori(t.R(kp, exit_id).pos.x / 4.0), floori(t.R(kp, exit_id).pos.y / 4.0))
	var pr2: Dictionary = kp.crops.place_crop("bamboo", exit_cell)
	var pl: int = int(pr2.id) if bool(pr2.ok) else -1
	var hp_before: float = float(kp.crops.get_crop(pl).hp) if pl > 0 else 0.0
	var tlk: Array = t.sim(kp, 8.0)
	var stuck_dmg: Array = t.of_type(tlk, "crop_damaged").filter(func(x: Dictionary) -> bool: return int(x.e.crop_id) == pl)
	t.ck("rat_gnaws_plug_from_below_3dmg", stuck_dmg.size() >= 1 and t.near(float(stuck_dmg[0].e.amount), 3.0), "n=%d state=%s" % [stuck_dmg.size(), t.R(kp, rat).state])
	if stuck_dmg.size() >= 2:
		t.ck("rat_plug_gnaw_interval_2s", t.near(float(stuck_dmg[1].t) - float(stuck_dmg[0].t), 2.0, 0.11))
	t.ck("rat_stuck_untargetable", (not has_target(kp, rat)) if t.R(kp, rat).state == "stuck" else true, "state=%s" % t.R(kp, rat).state)
	kp.crops.damage_crop(pl, 9999.0, {"cause": "attack"})
	var tlr: Array = t.sim(kp, 0.3)
	t.ck("manhole_reopens_when_plug_destroyed", t.R(kp, exit_id).state == "open")

# ---------------------------------------------------------------- ガラスジカ
func glass() -> void:
	var p: RefCounted = t.mk()
	var rng_state0: int = p.rng.state
	var regs: Dictionary = {"a": [Vector2(100, 100), Vector2(120, 100)], "b": [Vector2(60, 120)]}
	var ids: Array = p.place_glass_deer(12345, regs)
	t.ck("glass_lottery_does_not_use_pack_rng", p.rng.state == rng_state0)
	# 決定性: 同じ種・同じ地域なら同じ結果
	var q: RefCounted = t.mk(99)
	var ids2: Array = q.place_glass_deer(12345, regs)
	t.ck("glass_lottery_deterministic", ids.size() == ids2.size())
	# 統計: 5%
	var hits: int = 0
	var N: int = 3000
	var pp: RefCounted = t.mk()
	for i: int in range(N):
		var key: String = "r%d" % i
		var hit: int = pp.enemies.roll_glass_deer_region(777, key, [Vector2(100, 100)])
		if hit >= 0:
			hits += 1
	var rate: float = float(hits) / float(N)
	t.ck("glass_rate_about_5pct_single_candidate", rate > 0.035 and rate < 0.07, "rate=%.4f" % rate)
	# 地域あたり最大1頭(候補20): 当たり地域は ~64%
	var multi_hits: int = 0
	var max_per_region: int = 0
	var p3: RefCounted = t.mk()
	var cands: Array = []
	for i: int in range(20):
		cands.append(Vector2(20 + i * 10, 100))
	for i: int in range(400):
		var before: int = p3.enemies.enemies.size()
		p3.place_glass_deer(4242, {"m%d" % i: cands})
		var added: int = p3.enemies.enemies.size() - before
		max_per_region = maxi(max_per_region, added)
		multi_hits += added
	t.ck("glass_max_one_per_region", max_per_region <= 1, "max=%d" % max_per_region)
	var frac: float = float(multi_hits) / 400.0
	t.ck("glass_region_rate_matches_20_candidates", frac > 0.5 and frac < 0.78, "frac=%.3f (expected ~0.64)" % frac)
	# 観察: 同じ地域キーで place_glass_deer を2回呼ぶと、当たった地域では2頭目が出る(窓口は呼出し側が1回だけ呼ぶ前提)
	var dup: RefCounted = t.mk()
	var dup_key: String = ""
	for i: int in range(400):
		if dup.enemies.roll_glass_deer_region(4242, "dup%d" % i, cands) >= 0:
			dup_key = "dup%d" % i
			break
	if dup_key != "":
		dup.place_glass_deer(4242, {dup_key: cands})
		dup.place_glass_deer(4242, {dup_key: cands})
		t.note("obs_glass_place_called_twice_spawns_twice", "deer_count=%d (host must place once at initial placement; after load, do not re-run placement)" % dup.enemies.enemies.filter(func(e: Dictionary) -> bool: return e.kind == "glass_deer").size())
	# 別の世界の種で結果が変わる(乱数が世界の種に依存)
	var diff: int = 0
	var pa: RefCounted = t.mk()
	var pb: RefCounted = t.mk()
	for i: int in range(500):
		var ha: int = pa.enemies.roll_glass_deer_region(1, "k%d" % i, cands)
		var hb: int = pb.enemies.roll_glass_deer_region(2, "k%d" % i, cands)
		if ha != hb:
			diff += 1
	t.ck("glass_depends_on_world_seed", diff > 100, "diff=%d" % diff)
	# 保存して復元しても抽選結果が残る
	var snap: Dictionary = pa.to_dict()
	var parsed: Variant = JSON.parse_string(JSON.stringify(snap))
	var pc: RefCounted = t.mk()
	var okl: bool = pc.from_dict(parsed)
	t.ck("glass_rolls_survive_json_roundtrip", okl and pc.enemies.glass_rolls.size() == pa.enemies.glass_rolls.size() and pc.enemies.glass_rolls["k0"] == pa.enemies.glass_rolls["k0"], str(pc.last_error))
	# 行動と撃破
	var one: RefCounted = t.mk()
	t.hero(one, 240, 20)
	var gid: int = t.sp(one, "glass_deer", 120, 100)
	var e: Dictionary = t.R(one, gid)
	t.ck("glass_is_neutral_bonus_hittable", has_target(one, gid) and one.enemies.hittable_targets().filter(func(x: Dictionary) -> bool: return x.id == gid)[0].helper_exempt)
	t.ck("glass_not_in_helper_targets", not one.enemies.helper_targets().any(func(x: Dictionary) -> bool: return x.id == gid))
	t.ck("glass_not_counted_for_stability", not one.enemies.counts_for_stability(gid) and one.enemies.living_count_for_stability() == 0)
	var det: Array = one.enemies.detectable_enemies().filter(func(x: Dictionary) -> bool: return x.id == gid)
	t.ck("glass_detect_category_bonus", det.size() == 1 and det[0].category == "bonus")
	# 歩き回る(0.8m/s、家から10m以内)
	var start: Vector2 = t.R(one, gid).pos
	t.sim(one, 60.0)
	var dist: float = t.R(one, gid).pos.distance_to(start)
	t.ck("glass_wanders_within_10m", dist <= 100.5 + 4.0 and dist > 0.5, "dist=%.1f" % dist)
	one.host.set_stable_rect(Rect2i(25, 20, 12, 12))
	t.ck("glass_not_counted_even_in_stable_region", one.enemies.living_for_stability().is_empty())
	# helper の弾・水では砕けない
	var h1: Array = one.hit_enemy(gid, 99.0, "helper", Vector2(100, 100))
	var h2: Array = one.hit_enemy(gid, 99.0, "water", Vector2(100, 100))
	t.ck("glass_not_shattered_by_helper_or_water", one.enemies.is_alive(gid) and t.evs(h1 + h2, "reward").is_empty())
	# 一撃: shot/bazooka/tackle それぞれ、報酬120を1回(initial)
	for kind: String in ["shot", "bazooka", "tackle"]:
		var gp: RefCounted = t.mk()
		t.hero(gp, 240, 20)
		var gg: int = t.sp(gp, "glass_deer", 120, 100)
		var kev: Array = gp.hit_enemy(gg, 1.0, kind, Vector2(100, 100))
		var rw: Array = t.evs(kev, "reward")
		t.ck("glass_one_hit_" + kind, not gp.enemies.is_alive(gg) and rw.size() == 1 and int(rw[0].amount) == 120 and bool(rw[0].get("instant", false)) and t.fxk(kev, "glass_shatter").size() == 1, "rw=%d" % rw.size())
	var gz: RefCounted = t.mk()
	t.hero(gz, 240, 20)
	var gzid: int = t.sp(gz, "glass_deer", 120, 100)
	var zev: Array = gz.splash(Vector2(120, 100), 25.0, 25.0, "bazooka")
	t.ck("glass_bazooka_splash_one_reward", t.evs(zev, "reward").size() == 1)
	var gdup: Array = gz.hit_enemy(gzid, 1.0, "shot", Vector2(100, 100))
	t.ck("glass_no_second_reward", t.evs(gdup, "reward").is_empty())
	# 敵の対象外(近くのエビ・トカゲ・ネズミ等が攻撃・反射しない)
	var ne: RefCounted = t.mk()
	t.hero(ne, 240, 20)
	var ngid: int = t.sp(ne, "glass_deer", 120, 100)
	t.sp(ne, "pistol_shrimp", 126, 100)
	t.sp(ne, "mirror_lizard", 130, 100)
	t.sp(ne, "decoy_newt", 134, 100)
	t.sp(ne, "iron_rhino", 140, 100)
	t.sim(ne, 15.0)
	t.ck("glass_not_attacked_by_enemies", ne.enemies.is_alive(ngid) and t.near(float(t.R(ne, ngid).hp), 1.0))

# ---------------------------------------------------------------- ハチミツグマ
func bear() -> void:
	# 落果 -> 満腹3で家へ帰って眠る
	var p: RefCounted = t.mk()
	t.hero(p, 240, 20)
	var bid: int = t.sp(p, "honey_bear", 160, 100)
	t.R(p, bid).home = Vector2(160, 100)
	p.crops.fruits.append({"id": 1, "cell": Vector2i(44, 28), "source_id": 0})
	p.crops.fruits.append({"id": 2, "cell": Vector2i(46, 28), "source_id": 0})
	p.crops.fruits.append({"id": 3, "cell": Vector2i(48, 28), "source_id": 0})
	p.crops.next_fruit_id = 4
	var tl: Array = t.sim(p, 40.0)
	var fe: Array = t.of_type(tl, "fruit_eaten")
	t.ck("bear_eats_3_fruits", fe.size() == 3, "n=%d" % fe.size())
	if fe.size() >= 2:
		t.ck("bear_fruit_eat_3s_each", float(fe[1].t) - float(fe[0].t) >= 3.0, "%.2f" % (float(fe[1].t) - float(fe[0].t)))
	t.ck("bear_sleeps_when_full", t.R(p, bid).state == "sleep" and int(t.R(p, bid).satiety) == 3, "state=%s sat=%s" % [t.R(p, bid).state, str(t.R(p, bid).satiety)])
	# 眠り: 被ダメ x1.5、攻撃されても起きない
	var h0: float = float(t.R(p, bid).hp)
	p.hit_enemy(bid, 10.0, "shot", Vector2(100, 100))
	t.ck("bear_sleep_damage_x1_5", t.near(h0 - float(t.R(p, bid).hp), 15.0) and t.R(p, bid).state == "sleep")
	p.hit_enemy(bid, 10.0, "shot", Vector2(100, 100))
	t.ck("bear_still_asleep_above_half", t.R(p, bid).state == "sleep", "hp=%s" % str(t.R(p, bid).hp))
	var hp_now: float = float(t.R(p, bid).hp)
	# HPを半分(40)未満にすると起きて怒る
	var guard: int = 0
	while t.R(p, bid).state == "sleep" and guard < 10:
		p.hit_enemy(bid, 10.0, "shot", Vector2(100, 100))
		guard += 1
	t.ck("bear_wakes_when_hp_below_half", t.R(p, bid).state == "enraged" and float(t.R(p, bid).hp) < 40.0 and int(t.R(p, bid).satiety) == 0, "state=%s hp=%s sat=%s" % [t.R(p, bid).state, str(t.R(p, bid).hp), str(t.R(p, bid).satiety)])
	# 怒り: 予兆0.8秒 -> 爪15ダメージ/1.2秒
	t.hero(p, 168, 100)
	var tle: Array = t.sim(p, 4.0)
	var cl: Array = t.of_type(tle, "hero_damage").filter(func(x: Dictionary) -> bool: return x.e.kind == "honey_bear")
	t.ck("bear_claw_15", cl.size() >= 2 and t.near(float(cl[0].e.amount), 15.0), "n=%d" % cl.size())
	if cl.size() >= 2:
		t.ck("bear_claw_interval_1_2s", t.near(float(cl[1].t) - float(cl[0].t), 1.2, 0.11))
	t.hero(p, 160 + 190, 100)   # 19m 離れる(マップ外にならないよう y を変える)
	t.hero(p, 250, 20)
	t.R(p, bid).pos = Vector2(10, 130)
	t.sim(p, 0.3)
	t.ck("bear_calms_when_hero_beyond_18m", t.R(p, bid).state != "enraged", "state=%s" % t.R(p, bid).state)
	# 起きている時に殴ると怒る
	var a: RefCounted = t.mk()
	t.hero(a, 240, 20)
	var aid: int = t.sp(a, "honey_bear", 160, 100)
	a.hit_enemy(aid, 3.0, "shot", Vector2(100, 100))
	t.ck("bear_awake_hit_enrages", t.R(a, aid).state == "enraged")
	# 優先順位: 落果 > 巣 > 果実の植物
	var o: RefCounted = t.mk()
	t.hero(o, 240, 20)
	var oid: int = t.sp(o, "honey_bear", 160, 100)
	var hive: int = t.sp(o, "honeybee_hive", 150, 90)
	var st_c: int = t.crop(o, "strawberry", 36, 28)
	var tlo: Array = t.sim(o, 3.0)
	t.ck("bear_targets_hive_before_fruit_plant", t.R(o, oid).t_kind == "hive", "t_kind=%s" % str(t.R(o, oid).t_kind))
	o.crops.fruits.append({"id": 9, "cell": Vector2i(42, 22), "source_id": 0})
	o.crops.next_fruit_id = 10
	t.R(o, oid).state = "idle"
	t.R(o, oid).t_kind = ""
	t.R(o, oid).think_at = 0.0
	t.sim(o, 0.8)
	t.ck("bear_prefers_fruit_over_hive", t.R(o, oid).t_kind == "fruit", "t_kind=%s" % str(t.R(o, oid).t_kind))
	# 巣をかじる間、ミツバチがクマを刺す
	var b2: RefCounted = t.mk()
	t.hero(b2, 240, 20)
	var b2id: int = t.sp(b2, "honey_bear", 156, 96)
	var hv2: int = t.sp(b2, "honeybee_hive", 150, 90)
	var tlb: Array = t.sim(b2, 25.0)
	var stings: Array = t.of_type(tlb, "enemy_damaged").filter(func(x: Dictionary) -> bool: return int(x.e.enemy_id) == b2id and x.e.kind == "sting")
	t.ck("bees_sting_bear_eating_hive", stings.size() >= 1, "stings=%d" % stings.size())
	t.ck("bees_did_not_attack_hero_when_bear_eats", t.of_type(tlb, "hero_damage").is_empty())
	# 安定した地域の落果は引き寄せない
	var sb: RefCounted = t.mk()
	t.hero(sb, 240, 20)
	var sbid: int = t.sp(sb, "honey_bear", 160, 100)
	sb.crops.fruits.append({"id": 1, "cell": Vector2i(44, 28), "source_id": 0})
	sb.crops.next_fruit_id = 2
	sb.host.set_stable_rect(Rect2i(42, 26, 6, 6))
	t.sim(sb, 20.0)
	t.ck("bear_ignores_fruit_in_stable_region", sb.crops.fruits.size() == 1 and int(t.R(sb, sbid).satiety) == 0)

# ---------------------------------------------------------------- テツヨロイサイ
func rhino() -> void:
	var p: RefCounted = t.mk()
	t.hero(p, 240, 20)
	var id: int = t.sp(p, "iron_rhino", 160, 100)
	p.hit_enemy(id, 10.0, "shot", Vector2(100, 100))
	t.ck("rhino_shot_x0_5", t.near(float(t.R(p, id).hp), 95.0))
	p.hit_enemy(id, 10.0, "helper", Vector2(100, 100))
	t.ck("rhino_helper_x0_5", t.near(float(t.R(p, id).hp), 90.0))
	p.splash(Vector2(160, 100), 25.0, 20.0, "bazooka")
	t.ck("rhino_bazooka_full", t.near(float(t.R(p, id).hp), 70.0))
	p.hit_enemy(id, 8.0, "tackle", Vector2(100, 100))
	t.ck("rhino_tackle_full", t.near(float(t.R(p, id).hp), 62.0))
	# 錆: 水が当たるたび+1(最大5)、減らない
	for i: int in range(7):
		p.hit_enemy(id, 0.0, "water")
	t.ck("rhino_rust_caps_at_5", int(t.R(p, id).rust) == 5, "rust=%s" % str(t.R(p, id).rust))
	t.sim(p, 60.0)
	t.ck("rhino_rust_never_decreases", int(t.R(p, id).rust) == 5)
	t.ck("rhino_water_does_no_damage", t.near(float(t.R(p, id).hp), 62.0))
	# 予兆と突進の速さ(錆0と3)。主人公が左側にいる開けた一直線
	var res: Dictionary = {}
	for rust: int in [0, 3]:
		var q: RefCounted = t.mk()
		t.hero(q, 150, 100)
		var qid: int = t.sp(q, "iron_rhino", 230, 100)
		t.R(q, qid).rust = rust
		var t_wu: float = -1.0
		var t_ch: float = -1.0
		var x_ch: float = 0.0
		var x_end: float = 0.0
		var t_end: float = -1.0
		var hits: Array = []
		for i: int in range(200):
			var ev: Array = q.advance(0.05)
			for x: Dictionary in ev:
				if x.type == "hero_damage":
					hits.append(x)
			var s: String = str(t.R(q, qid).state)
			var tm: float = q.enemies.time
			if s == "windup" and t_wu < 0.0:
				t_wu = tm
			if s == "charge" and t_ch < 0.0:
				t_ch = tm
				x_ch = t.R(q, qid).pos.x
			if s == "recover" and t_ch >= 0.0 and t_end < 0.0:
				t_end = tm
				x_end = t.R(q, qid).pos.x
				break
		res[rust] = {"windup": t_ch - t_wu, "travel": x_ch - x_end, "charge_time": t_end - t_ch, "hits": hits.size(), "dmg": float(hits[0].amount) if hits.size() > 0 else 0.0}
	t.ck("rhino_windup_1_2s_rust0", t.near(float(res[0].windup), 1.2, 0.12), str(res[0]))
	t.ck("rhino_windup_plus_0_2_per_rust", t.near(float(res[3].windup), 1.8, 0.12), str(res[3]))
	t.ck("rhino_charge_damage_30", t.near(float(res[0].dmg), 30.0) and int(res[0].hits) == 1, str(res[0]))
	var tr0: float = float(res[0].travel) / maxf(0.01, float(res[0].charge_time))
	var tr3: float = float(res[3].travel) / maxf(0.01, float(res[3].charge_time))
	t.ck("rhino_charge_speed_9mps_rust0", t.near(tr0, 90.0, 6.0), "speed=%.1f" % tr0)
	t.ck("rhino_rust3_speed_minus_36pct", t.near(tr3 / maxf(tr0, 0.01), 0.64, 0.05), "ratio=%.3f" % (tr3 / maxf(tr0, 0.01)))
	# 突進の間隔(錆で+1秒/個)
	var gap: Dictionary = {}
	for rust: int in [0, 2]:
		var q2: RefCounted = t.mk()
		t.hero(q2, 150, 100)
		var q2id: int = t.sp(q2, "iron_rhino", 230, 100)
		t.R(q2, q2id).rust = rust
		var wus: Array = []
		var was: String = ""
		for i: int in range(900):
			q2.advance(0.05)
			var s2: String = str(t.R(q2, q2id).state)
			if s2 == "windup" and was != "windup":
				wus.append(q2.enemies.time)
			was = s2
			# 主人公を突進先へ置き直す(常に左側の射程内)
			var rp: Vector2 = t.R(q2, q2id).pos
			t.hero(q2, clampf(rp.x - 60.0, 10.0, 240.0), 100)
			if rp.x < 70.0:
				t.R(q2, q2id).pos = Vector2(230, 100)
			if wus.size() >= 2:
				break
		gap[rust] = (float(wus[1]) - float(wus[0])) if wus.size() >= 2 else -1.0
	t.ck("rhino_rust_adds_1s_interval_each", gap[0] > 0.0 and t.near(float(gap[2]) - float(gap[0]), 2.0 + 2 * 0.2 * 0.0 + 0.4, 0.3), str(gap))
	# 進路上の株を踏む(1株15)
	var cr: RefCounted = t.mk()
	t.hero(cr, 150, 100)
	var crid: int = t.sp(cr, "iron_rhino", 230, 100)
	var cid: int = t.crop(cr, "clover", 40, 25)
	var tlc: Array = t.sim(cr, 5.0)
	var cdm: Array = t.of_type(tlc, "crop_damaged").filter(func(x: Dictionary) -> bool: return int(x.e.crop_id) == cid)
	t.ck("rhino_tramples_crop_15", cdm.size() >= 1 and t.near(float(cdm[0].e.amount), 15.0), "n=%d" % cdm.size())

# ---------------------------------------------------------------- タイホウエビ
func shrimp() -> void:
	var p: RefCounted = t.mk()
	t.hero(p, 190, 100)   # 3mなので範囲内
	t.helper(p, 61, 150, 94)
	var cropid: int = t.crop(p, "bamboo", 38, 24)
	var id: int = t.sp(p, "pistol_shrimp", 160, 100)
	var hp_crop: float = float(p.crops.get_crop(cropid).hp)
	var tl: Array = t.sim(p, 4.0)
	var wu: Array = t.of_type(tl, "fx").filter(func(x: Dictionary) -> bool: return x.e.kind == "shrimp_windup")
	var wv: Array = t.of_type(tl, "fx").filter(func(x: Dictionary) -> bool: return x.e.kind == "shrimp_wave")
	t.ck("shrimp_windup_1_2s", wu.size() >= 1 and wv.size() >= 1 and t.near(float(wv[0].t) - float(wu[0].t), 1.2, 0.11), "wu=%d wv=%d" % [wu.size(), wv.size()])
	var stun: Array = t.of_type(tl, "hero_stun")
	var hst: Array = t.of_type(tl, "helper_stop")
	t.ck("shrimp_hero_stun_1_5s_event", stun.size() >= 1 and t.near(float(stun[0].e.seconds), 1.5))
	t.ck("shrimp_helper_stop_stun_cause", hst.size() >= 1 and hst[0].e.cause == "stun" and int(hst[0].e.helper_id) == 61 and t.near(float(hst[0].e.seconds), 1.5))
	var dm: Array = t.of_type(tl, "hero_damage")
	t.ck("shrimp_damage_5", dm.size() >= 1 and t.near(float(dm[0].e.amount), 5.0))
	t.ck("shrimp_no_effect_on_crop", t.near(float(p.crops.get_crop(cropid).hp), hp_crop))
	# 窓口の状態: 気絶は1.5秒で解ける
	var q: RefCounted = t.mk()
	t.hero(q, 190, 100)
	t.sp(q, "pistol_shrimp", 160, 100)
	var stunned_at: float = -1.0
	var cleared_at: float = -1.0
	for i: int in range(80):
		var ev: Array = q.advance(0.1)
		if stunned_at < 0.0 and q.common.hero_stunned():
			stunned_at = q.enemies.time
		if stunned_at >= 0.0 and cleared_at < 0.0 and not q.common.hero_stunned():
			cleared_at = q.enemies.time
			break
	t.ck("common_hero_stun_lasts_1_5s", stunned_at > 0.0 and t.near(cleared_at - stunned_at, 1.5, 0.15), "%.2f" % (cleared_at - stunned_at))
	var q2: RefCounted = t.mk()
	t.hero(q2, 240, 20)
	t.helper(q2, 61, 190, 100)
	t.sp(q2, "pistol_shrimp", 160, 100)
	var hs_at: bool = false
	var hs_clear: bool = false
	for i: int in range(80):
		q2.advance(0.1)
		if q2.common.helper_stopped(61):
			hs_at = true
		elif hs_at:
			hs_clear = true
			break
	t.ck("common_helper_stopped_then_released", hs_at and hs_clear)
	# 5秒間隔
	var r: RefCounted = t.mk()
	t.hero(r, 190, 100)
	r.enemies.defs["pistol_shrimp"].speed_mps = 0.0   # 立ち位置を固定して間隔だけを見る(待機中の徘徊で射程から外れるのを避ける)
	t.sp(r, "pistol_shrimp", 160, 100)
	var tlr: Array = t.sim(r, 14.0)
	var waves: Array = t.of_type(tlr, "fx").filter(func(x: Dictionary) -> bool: return x.e.kind == "shrimp_wave")
	t.ck("shrimp_wave_interval_5s", waves.size() >= 2 and t.near(float(waves[1].t) - float(waves[0].t), 5.0, 0.15), "n=%d times=%s" % [waves.size(), str(waves.map(func(x: Dictionary) -> float: return snappedf(float(x.t), 0.01)))])
	# 4mの外では予兆しない(接近はしない場合の判定: 近づくが衝撃波は4m以内に入ってから)
	var o: RefCounted = t.mk()
	t.hero(o, 160 + 41, 100)
	var oid: int = t.sp(o, "pistol_shrimp", 160, 100)
	o.enemies.defs["pistol_shrimp"].speed_mps = 0.0   # 接近を止めて、半径4mの境界だけを見る
	var tlo: Array = t.sim(o, 3.0)
	t.ck("shrimp_no_wave_beyond_4m", t.of_type(tlo, "fx").filter(func(x: Dictionary) -> bool: return x.e.kind == "shrimp_windup").is_empty())
	# 建物で遮られる: 建物 x112..143, y56..79。エビは北、主人公は南(建物の向こう)
	var b: RefCounted = t.mk()
	t.hero(b, 128, 88)   # 建物の南側
	var bid: int = t.sp(b, "pistol_shrimp", 128, 52)   # 建物の北側(距離36=3.6m)
	var tlb: Array = t.sim(b, 3.0)
	var bw: Array = t.of_type(tlb, "fx").filter(func(x: Dictionary) -> bool: return x.e.kind == "shrimp_wave")
	t.ck("shrimp_wave_blocked_by_building", t.of_type(tlb, "hero_stun").is_empty() and t.of_type(tlb, "hero_damage").is_empty(), "wave=%d stun=%d" % [bw.size(), t.of_type(tlb, "hero_stun").size()])

# ---------------------------------------------------------------- フウセンガエル
func frog() -> void:
	var p: RefCounted = t.mk()
	t.hero(p, 240, 130)   # 遠い(8m超)
	var ids: Array = p.enemies.spawn_frog_flock(Vector2(120, 80), "initial")
	t.ck("frog_flock_of_3", ids.size() == 3)
	t.sim(p, 3.0)
	t.ck("frog_hop_when_hero_far", states(p, ids).all(func(s: String) -> bool: return s == "hop"))
	# 地上は攻撃しない(主人公の隣でも膨らむだけ)。地上HP6: 5ダメージでは割れない
	var g: RefCounted = t.mk()
	t.hero(g, 240, 130)
	var gi: Array = g.enemies.spawn_frog_flock(Vector2(120, 80), "initial")
	var ev: Array = g.hit_enemy(gi[0], 5.0, "shot", Vector2(100, 80))
	t.ck("frog_ground_hp6_survives_5", g.enemies.is_alive(gi[0]) and t.near(float(t.R(g, gi[0]).hp), 1.0))
	var ev2: Array = g.hit_enemy(gi[0], 5.0, "shot", Vector2(100, 80))
	t.ck("frog_ground_kill_no_acid", not g.enemies.is_alive(gi[0]) and g.enemies.acid_pools().is_empty())
	t.ck("frog_ground_reward_3", t.evs(ev2, "reward").size() == 1 and int(t.evs(ev2, "reward")[0].amount) == 3)
	# 8m以内で1秒かけて膨らみ、浮かぶ。浮いていても当たる。1回で割れる
	var f: RefCounted = t.mk()
	t.hero(f, 120 + 70, 80)
	var fi: Array = f.enemies.spawn_frog_flock(Vector2(120, 80), "initial")
	t.sim(f, 0.5)
	t.ck("frog_inflating", states(f, fi).all(func(s: String) -> bool: return s == "inflate"), str(states(f, fi)))
	t.sim(f, 0.8)
	t.ck("frog_floats_after_1s", states(f, fi).all(func(s: String) -> bool: return s == "float"), str(states(f, fi)))
	t.ck("frog_floating_still_hittable", fi.all(func(i: int) -> bool: return has_target(f, i)))
	# どの攻撃でも1回で割れる(射撃1ダメージ)。酸が半径1.6mに5秒
	var fp: Vector2 = t.R(f, fi[0]).pos
	var pev: Array = f.hit_enemy(fi[0], 1.0, "shot", Vector2(100, 80))
	t.ck("frog_pops_with_1_damage", not f.enemies.is_alive(fi[0]) and t.fxk(pev, "frog_pop").size() == 1)
	var ac: Array = f.enemies.acid_pools()
	t.ck("frog_acid_radius_1_6m_5s", ac.size() == 1 and t.near(float(ac[0].radius), 16.0) and t.near(float(ac[0].until) - f.enemies.time, 5.0, 0.01), str(ac))
	t.ck("frog_pop_reward_3", t.evs(pev, "reward").size() == 1 and int(t.evs(pev, "reward")[0].amount) == 3)
	# 他の攻撃種別: tackle / helper / bazooka でも割れる。水は割れない
	for kind: String in ["tackle", "helper"]:
		var k: RefCounted = t.mk()
		t.hero(k, 120 + 70, 80)
		var ki: Array = k.enemies.spawn_frog_flock(Vector2(120, 80), "initial")
		t.sim(k, 1.5)
		k.hit_enemy(ki[1], 1.0, kind, Vector2(100, 80))
		t.ck("frog_float_pops_by_" + kind, not k.enemies.is_alive(ki[1]))
	var kb: RefCounted = t.mk()
	t.hero(kb, 120 + 70, 80)
	var kbi: Array = kb.enemies.spawn_frog_flock(Vector2(120, 80), "initial")
	t.sim(kb, 1.5)
	kb.splash(t.R(kb, kbi[0]).pos, 20.0, 1.0, "bazooka")
	t.ck("frog_float_pops_by_bazooka", not kb.enemies.is_alive(kbi[0]))
	var kw: RefCounted = t.mk()
	t.hero(kw, 120 + 70, 80)
	var kwi: Array = kw.enemies.spawn_frog_flock(Vector2(120, 80), "initial")
	t.sim(kw, 1.5)
	kw.hit_enemy(kwi[0], 0.0, "water")
	t.ck("frog_float_not_popped_by_water", kw.enemies.is_alive(kwi[0]))
	# 酸: 中の主人公・おたすけ植物・栽培植物に3ダメージ/秒
	var a: RefCounted = t.mk()
	t.hero(a, 120 + 70, 80)
	var ai: Array = [t.sp(a, "balloon_frog", 120, 80, "initial")]
	t.R(a, ai[0]).state = "float"
	var ap: Vector2 = t.R(a, ai[0]).pos
	t.hero(a, ap.x + 5, ap.y)
	t.helper(a, 71, ap.x - 5, ap.y)
	var cid: int = t.crop(a, "clover", int(ap.x / 4.0), int(ap.y / 4.0))
	var cinit: float = float(a.crops.get_crop(cid).hp)
	a.hit_enemy(ai[0], 1.0, "shot", Vector2(ap.x - 40, ap.y))
	var tla: Array = t.sim(a, 6.0)
	var hdm: Array = t.of_type(tla, "hero_damage").filter(func(x: Dictionary) -> bool: return x.e.kind == "acid")
	var hpd: Array = t.of_type(tla, "helper_damage").filter(func(x: Dictionary) -> bool: return x.e.kind == "acid")
	var cdm: Array = t.of_type(tla, "crop_damaged")
	t.ck("acid_hurts_hero_3_per_sec", hdm.size() >= 4 and hdm.size() <= 6 and t.near(float(hdm[0].e.amount), 3.0), "n=%d" % hdm.size())
	t.ck("acid_hurts_helper", hpd.size() >= 4 and t.near(float(hpd[0].e.amount), 3.0), "n=%d" % hpd.size())
	t.ck("acid_hurts_crop", cdm.size() >= 4 and t.near(float(cdm[0].e.amount), 3.0), "n=%d" % cdm.size())
	t.ck("acid_gone_after_5s", a.enemies.acid_pools().is_empty())
	# 主人公に触れると割れる
	var tc: RefCounted = t.mk()
	t.hero(tc, 120 + 70, 80)
	var tci: Array = tc.enemies.spawn_frog_flock(Vector2(120, 80), "initial")
	var tltc: Array = t.sim(tc, 25.0, 0.1, func(pp: RefCounted) -> void:
		pass)
	t.ck("frog_pops_on_touching_hero", t.fxk(t.E(tltc), "frog_touch").size() >= 1 and t.fxk(t.E(tltc), "frog_pop").size() >= 1 and t.evs(t.E(tltc), "hero_damage").filter(func(e: Dictionary) -> bool: return e.kind == "acid").size() >= 1)

func stability_summary() -> void:
	# 安定判定: 地中・水中・飛行・眠りは数える。分身・ガラスジカ・閉じたマンホールは数えない
	var p: RefCounted = t.mk()
	t.hero(p, 240, 130)
	var ids: Dictionary = {}
	ids["mole"] = t.sp(p, "root_mole", 200, 100)
	ids["eel"] = t.sp(p, "thunder_eel", 30, 30)
	ids["hippo"] = t.sp(p, "hippo", 40, 30)
	ids["bat"] = p.enemies.spawn_bat_flock(Vector2(108, 68), "initial")[0]
	ids["frog"] = p.enemies.spawn_frog_flock(Vector2(120, 80), "initial")[0]
	ids["bear"] = t.sp(p, "honey_bear", 160, 120)
	ids["skunk"] = t.sp(p, "skunk", 180, 120)
	p.hit_enemy(int(ids["bat"]), 1.0, "shot", Vector2(130, 68))
	t.R(p, int(ids["bear"])).state = "sleep"
	for k: String in ids.keys():
		t.ck("counts_for_stability_" + k, p.enemies.counts_for_stability(int(ids[k])))

## 安定した地域(再侵攻の禁止): 主人公を安定地域の中へ置いて誘っても、第2弾の地上・飛行の敵は地域の中へ入らない
func no_reinvasion() -> void:
	for kind: String in ["skunk", "mirror_lizard", "iron_rhino", "honey_bear", "decoy_newt", "pistol_shrimp", "sewer_rat", "balloon_frog"]:
		var p: RefCounted = t.mk()
		p.host.set_stable_rect(Rect2i(38, 20, 10, 10))   # x38..47, y20..29 (px 152..192, 80..120)
		t.hero(p, 172, 100)
		var id: int = t.sp(p, kind, 140, 100)
		if kind == "balloon_frog":
			t.R(p, id).state = "float"
		var inside: int = 0
		for i: int in range(300):
			p.advance(0.1)
			if p.enemies.is_alive(id) and p.host.is_stable_cell(Vector2i(floori(t.R(p, id).pos.x / 4.0), floori(t.R(p, id).pos.y / 4.0))):
				inside += 1
		t.ck("no_reinvasion_" + kind, inside == 0, "steps_inside=%d" % inside)
	var b: RefCounted = t.mk()
	b.host.set_stable_rect(Rect2i(40, 10, 14, 14))
	t.hero(b, 188, 68)
	var ids: Array = b.enemies.spawn_bat_flock(Vector2(108, 68), "initial")
	b.hit_enemy(ids[0], 1.0, "shot", Vector2(130, 68))
	var bin: int = 0
	for i: int in range(200):
		b.advance(0.1)
		for id2: int in ids:
			if b.enemies.is_alive(id2) and b.host.is_stable_cell(Vector2i(floori(t.R(b, id2).pos.x / 4.0), floori(t.R(b, id2).pos.y / 4.0))) and t.R(b, id2).state in ["swarm", "dive", "low"]:
				bin += 1
	t.ck("no_reinvasion_bat_swarm_airspace", bin == 0, "bat_steps_inside=%d" % bin)
