extends SceneTree
## 独立検証2-A: 向き(スカンク・カガミトカゲ)、濡れたマス・ウナギ、モグラ、カバ。入口スクリプト。
const L: GDScript = preload("res://tests/content_pack/independent2/lib2.gd")
const Facing: GDScript = preload("res://scripts/content_pack/facing.gd")
const OUT: String = "res://evidence/content_pack/independent2"
var t: RefCounted = L.new()

func _initialize() -> void:
	facing_pure()
	skunk()
	lizard()
	wet_and_eel()
	mole()
	hippo()
	t.finish("animals_a", OUT, self)

func facing_pure() -> void:
	# 純粋関数: 正面120度(±60度、境界含む)、旋回上限
	var f: Vector2 = Vector2.RIGHT
	t.ck("facing_59_front", Facing.is_front(f, Vector2.ZERO, Vector2.from_angle(deg_to_rad(59.0)) * 30.0))
	t.ck("facing_61_not_front", not Facing.is_front(f, Vector2.ZERO, Vector2.from_angle(deg_to_rad(61.0)) * 30.0))
	t.ck("facing_neg59_front", Facing.is_front(f, Vector2.ZERO, Vector2.from_angle(deg_to_rad(-59.0)) * 30.0))
	t.ck("facing_back_not_front", not Facing.is_front(f, Vector2.ZERO, Vector2.LEFT * 30.0))
	t.ck("facing_null_origin_not_front", not Facing.is_front(f, Vector2.ZERO, null))
	var nf: Vector2 = Facing.turn_toward(Vector2.RIGHT, Vector2.LEFT, 90.0, 0.5)
	t.ck("turn_toward_limit_45deg", t.near(absf(rad_to_deg(Vector2.RIGHT.angle_to(nf))), 45.0, 0.01), "got %.3f" % absf(rad_to_deg(Vector2.RIGHT.angle_to(nf))))
	var nf2: Vector2 = Facing.turn_toward(Vector2.RIGHT, Vector2.from_angle(deg_to_rad(10.0)), 90.0, 0.5)
	t.ck("turn_toward_reaches_when_within_limit", t.near(rad_to_deg(nf2.angle()), 10.0, 0.01))

# ---------------------------------------------------------------- スカンク
func new_skunk(p: RefCounted, face: Vector2 = Vector2.RIGHT) -> int:
	var id: int = t.sp(p, "skunk", 160, 100)
	t.R(p, id).face = face
	return id

func shot_from(p: RefCounted, id: int, from: Vector2, kind: String = "shot") -> Array:
	return p.hit_enemy(id, 5.0, kind, from)

func skunk() -> void:
	var p: RefCounted = t.mk()
	t.hero(p, 240, 20)
	var id: int = new_skunk(p)
	# 正面から射撃 -> 予兆
	var ev: Array = shot_from(p, id, Vector2(200, 100))
	t.ck("skunk_front_shot_windup", t.R(p, id).state == "windup" and t.fxk(ev, "skunk_windup").size() == 1)
	var tl: Array = t.sim(p, 0.7)
	t.ck("skunk_cloud_after_windup", p.enemies.odor_clouds().size() == 1 and t.fxk(t.E(tl), "odor").size() == 1)
	if p.enemies.odor_clouds().size() == 1:
		var o: Dictionary = p.enemies.odor_clouds()[0]
		t.ck("skunk_cloud_dir_toward_shooter", Vector2(o.dir).dot(Vector2.RIGHT) > 0.999, str(o.dir))
		t.ck("skunk_cloud_len50_half30", t.near(float(o.length), 50.0) and t.near(float(o.half_deg), 30.0), "%s %s" % [str(o.length), str(o.half_deg)])
		t.ck("skunk_cloud_duration_8s", t.near(float(o.until) - p.enemies.time, 8.0 - 0.1, 0.25), "remaining %.2f" % (float(o.until) - p.enemies.time))
	# 横・後ろ・たいあたり・水・トゲでは噴かない(個別の個体)
	for case: Array in [["side", Vector2(160, 60), "shot"], ["back", Vector2(120, 100), "shot"], ["tackle_front", Vector2(200, 100), "tackle"],
			["water_front", Vector2(200, 100), "water"], ["spine_front", Vector2(200, 100), "spine"], ["deg61", Vector2(160, 100) + Vector2.from_angle(deg_to_rad(61.0)) * 40.0, "shot"]]:
		var q: RefCounted = t.mk()
		t.hero(q, 240, 20)
		var qid: int = new_skunk(q)
		shot_from(q, qid, case[1], case[2])
		var tl2: Array = t.sim(q, 1.0)
		t.ck("skunk_no_spray_" + case[0], q.enemies.odor_clouds().is_empty() and t.fxk(t.E(tl2), "skunk_windup").is_empty() and t.R(q, qid).state != "windup")
	for case: Array in [["deg59", Vector2(160, 100) + Vector2.from_angle(deg_to_rad(59.0)) * 40.0, "shot"], ["helper_front", Vector2(200, 100), "helper"]]:
		var q2: RefCounted = t.mk()
		t.hero(q2, 240, 20)
		var qid2: int = new_skunk(q2)
		shot_from(q2, qid2, case[1], case[2])
		t.ck("skunk_spray_" + case[0], t.R(q2, qid2).state == "windup")
	# バズーカ: 爆心から見た方向
	var qb: RefCounted = t.mk()
	t.hero(qb, 240, 20)
	var qbid: int = new_skunk(qb)
	qb.splash(Vector2(180, 100), 25.0, 5.0, "bazooka")
	t.ck("skunk_bazooka_front_windup", t.R(qb, qbid).state == "windup")
	var qb2: RefCounted = t.mk()
	t.hero(qb2, 240, 20)
	var qb2id: int = new_skunk(qb2)
	qb2.splash(Vector2(140, 100), 25.0, 5.0, "bazooka")
	t.ck("skunk_bazooka_back_no_windup", t.R(qb2, qb2id).state != "windup")
	# 間隔6秒
	var r: RefCounted = t.mk()
	t.hero(r, 240, 20)
	var rid: int = new_skunk(r)
	shot_from(r, rid, Vector2(200, 100))
	t.sim(r, 0.7)
	var t_spray: float = r.enemies.time
	t.sim(r, 4.6)   # 噴射から約5.3秒
	t.R(r, rid).face = Vector2.RIGHT
	t.R(r, rid).pos = Vector2(160, 100)
	shot_from(r, rid, Vector2(200, 100))
	t.ck("skunk_interval_blocks_before_6s", t.R(r, rid).state != "windup", "t_since=%.2f" % (r.enemies.time - t_spray))
	t.sim(r, 1.7)
	t.R(r, rid).face = Vector2.RIGHT
	t.R(r, rid).pos = Vector2(160, 100)
	shot_from(r, rid, Vector2(200, 100))
	t.ck("skunk_interval_allows_after_6s", t.R(r, rid).state == "windup", "t_since=%.2f" % (r.enemies.time - t_spray))
	# 雲の作用
	var c: RefCounted = t.mk()
	t.hero(c, 180, 100)
	t.helper(c, 77, 185, 98)
	var cropid: int = t.crop(c, "clover", 40, 23)
	var eid: int = t.sp(c, "deer", 190, 104)
	c.host.helper_list[0].pos = Vector2(185, 98)
	var cid: int = new_skunk(c)
	var hp_crop0: float = float(c.crops.get_crop(cropid).hp)
	var hp_deer0: float = float(t.R(c, eid).hp)
	shot_from(c, cid, Vector2(200, 100))
	var tlc: Array = t.sim(c, 2.0)
	t.ck("skunk_cloud_hero_slow_event", t.of_type(tlc, "hero_slow").size() > 0 and t.near(float(t.of_type(tlc, "hero_slow")[0].e.factor), 0.6))
	t.ck("skunk_cloud_hero_move_mult_0_6", t.near(c.hero_move_mult(), 0.6))
	var stops: Array = t.of_type(tlc, "helper_stop")
	t.ck("skunk_cloud_helper_stop_odor", stops.size() > 0 and stops[0].e.cause == "odor" and int(stops[0].e.helper_id) == 77)
	t.ck("skunk_cloud_no_effect_on_crop_enemy", t.near(float(c.crops.get_crop(cropid).hp), hp_crop0) and (not c.enemies.is_alive(eid) or t.near(float(t.R(c, eid).hp), hp_deer0)))
	t.hero(c, 160, 140)
	t.ck("skunk_hero_outside_cone_mult_1", t.near(c.hero_move_mult(), 1.0))
	# 雲の寿命(8秒)
	t.sim(c, 7.0)
	t.ck("skunk_cloud_gone_after_8s", c.enemies.odor_clouds().is_empty(), "clouds=%d" % c.enemies.odor_clouds().size())
	# ニンニク
	var g: RefCounted = t.mk()
	t.hero(g, 240, 20)
	t.crop(g, "garlic", 41, 25)
	var gid: int = new_skunk(g)
	shot_from(g, gid, Vector2(200, 100))
	var tlg: Array = t.sim(g, 0.8)
	t.ck("skunk_garlic_cancels_cloud", g.enemies.odor_clouds().is_empty() and t.fxk(t.E(tlg), "odor_cancel").size() == 1)
	# ニンニクの上に立つ主人公は雲の中でも減速しない
	var g2: RefCounted = t.mk()
	t.hero(g2, 180, 100)
	var gid2: int = new_skunk(g2)
	shot_from(g2, gid2, Vector2(200, 100))
	t.sim(g2, 0.7)
	t.ck("skunk_cloud_slows_hero_without_garlic", t.near(g2.hero_move_mult(), 0.6))
	t.crop(g2, "garlic", 45, 25)
	t.ck("skunk_garlic_protects_hero_from_cloud", t.near(g2.hero_move_mult(), 1.0), "mult=%s" % str(g2.hero_move_mult()))
	# 旋回上限 90度/秒
	var tp: RefCounted = t.mk()
	t.hero(tp, 130, 100)
	var tid: int = new_skunk(tp)
	t.sim(tp, 0.5)
	var a05: float = absf(t.ang_deg(t.R(tp, tid).face))
	t.sim(tp, 0.5)
	var a10: float = absf(t.ang_deg(t.R(tp, tid).face))
	t.sim(tp, 1.5)
	var to_h: Vector2 = Vector2(130, 100) - Vector2(t.R(tp, tid).pos)
	var a25: float = absf(rad_to_deg(Vector2(t.R(tp, tid).face).angle_to(to_h)))
	t.ck("skunk_turn_limit_90dps", t.near(a05, 45.0, 6.0) and t.near(a10, 90.0, 6.0) and a25 < 15.0, "0.5s=%.1f 1.0s=%.1f resid@2.5s=%.1f" % [a05, a10, a25])
	# 栽培植物をかじる 3ダメージ/2秒、主人公は攻撃しない
	var gn: RefCounted = t.mk()
	t.hero(gn, 240, 20)
	var cid2: int = t.crop(gn, "bamboo", 41, 25)
	t.sp(gn, "skunk", 160, 100)
	var tlgn: Array = t.sim(gn, 12.0)
	var dm: Array = t.of_type(tlgn, "crop_damaged")
	t.ck("skunk_gnaws_crop_3dmg", dm.size() >= 2 and t.near(float(dm[0].e.amount), 3.0), "n=%d" % dm.size())
	if dm.size() >= 2:
		t.ck("skunk_gnaw_interval_2s", t.near(float(dm[1].t) - float(dm[0].t), 2.0, 0.11), "%.2f" % (float(dm[1].t) - float(dm[0].t)))
	t.ck("skunk_never_hurts_hero", t.of_type(tlgn, "hero_damage").is_empty())
	var kp: RefCounted = t.mk()
	t.hero(kp, 240, 20)
	var kid2: int = t.sp(kp, "skunk", 160, 100)
	var kev: Array = kp.hit_enemy(kid2, 18.0, "tackle", Vector2(150, 100))
	t.ck("skunk_hp18_reward5_instant", t.evs(kev, "reward").size() == 1 and int(t.evs(kev, "reward")[0].amount) == 5 and bool(t.evs(kev, "reward")[0].get("instant", false)) and t.evs(kev, "enemy_defeated").size() == 1)

# ---------------------------------------------------------------- カガミトカゲ
func new_liz(p: RefCounted, face: Vector2 = Vector2.RIGHT) -> int:
	var id: int = t.sp(p, "mirror_lizard", 160, 100)
	t.R(p, id).face = face
	return id

func lizard() -> void:
	var p: RefCounted = t.mk()
	t.hero(p, 200, 100)   # 射手=主人公(跳ね返りの受け手)。トカゲの噛みつき範囲外ではない(8m以内)が、先に反射を見る
	var id: int = new_liz(p)
	var ev: Array = p.hit_enemy(id, 5.0, "shot", Vector2(200, 100))
	t.ck("liz_front_shot_no_damage", t.evs(ev, "enemy_damaged").is_empty() and t.near(float(t.R(p, id).hp), 30.0))
	t.ck("liz_front_shot_reflect_fx_and_projectile", t.fxk(ev, "reflect").size() == 1 and p.enemies.projectile_list().size() == 1 and p.enemies.projectile_list()[0].kind == "reflected")
	if p.enemies.projectile_list().size() == 1:
		var pr: Dictionary = p.enemies.projectile_list()[0]
		t.ck("liz_reflect_dir_back_to_shooter", Vector2(pr.dir).dot(Vector2.RIGHT) > 0.999 and t.near(float(pr.damage), 5.0), "dir=%s dmg=%s" % [str(pr.dir), str(pr.damage)])
	var tl: Array = t.sim(p, 0.6)
	var hd: Array = t.of_type(tl, "hero_damage")
	var refl: Array = hd.filter(func(x: Dictionary) -> bool: return x.e.kind == "reflected")
	t.ck("liz_reflected_hits_hero_full_power", refl.size() == 1 and t.near(float(refl[0].e.amount), 5.0), "n=%d" % refl.size())
	# 横・後ろは命中
	for case: Array in [["side", Vector2(160, 60), 5.0], ["back", Vector2(120, 100), 5.0], ["deg61", Vector2(160, 100) + Vector2.from_angle(deg_to_rad(61.0)) * 40.0, 5.0]]:
		var q: RefCounted = t.mk()
		t.hero(q, 240, 20)
		var qid: int = new_liz(q)
		var e2: Array = q.hit_enemy(qid, 5.0, "shot", case[1])
		t.ck("liz_%s_hits_normally" % case[0], t.near(float(t.R(q, qid).hp), 25.0) and q.enemies.projectile_list().is_empty() and t.evs(e2, "enemy_damaged").size() == 1)
	var q59: RefCounted = t.mk()
	t.hero(q59, 240, 20)
	var q59id: int = new_liz(q59)
	q59.hit_enemy(q59id, 5.0, "shot", Vector2(160, 100) + Vector2.from_angle(deg_to_rad(59.0)) * 40.0)
	t.ck("liz_deg59_reflects", t.near(float(t.R(q59, q59id).hp), 30.0) and q59.enemies.projectile_list().size() == 1)
	# おたすけ植物の弾も反射し、おたすけ植物に当たる
	var h: RefCounted = t.mk()
	t.hero(h, 240, 20)
	t.helper(h, 55, 200, 100)
	var hid: int = new_liz(h)
	h.hit_enemy(hid, 3.0, "helper", Vector2(200, 100))
	var tlh: Array = t.sim(h, 0.6)
	var hdm: Array = t.of_type(tlh, "helper_damage").filter(func(x: Dictionary) -> bool: return x.e.kind == "reflected")
	t.ck("liz_helper_shot_reflected_to_helper", t.near(float(t.R(h, hid).hp), 30.0) and hdm.size() >= 1 and int(hdm[0].e.helper_id) == 55 and t.near(float(hdm[0].e.amount), 3.0), "n=%d" % hdm.size())
	# バズーカ: 正面なら x0.5、跳ね返らない。横・後ろは等倍
	var bz: RefCounted = t.mk()
	t.hero(bz, 240, 20)
	var bzid: int = new_liz(bz)
	bz.splash(Vector2(180, 100), 25.0, 25.0, "bazooka")
	t.ck("liz_bazooka_front_half", t.near(float(t.R(bz, bzid).hp), 30.0 - 12.5) and bz.enemies.projectile_list().is_empty(), "hp=%s" % str(t.R(bz, bzid).hp))
	var bz2: RefCounted = t.mk()
	t.hero(bz2, 240, 20)
	var bz2id: int = new_liz(bz2)
	bz2.splash(Vector2(140, 100), 25.0, 25.0, "bazooka")
	t.ck("liz_bazooka_back_full", t.near(float(t.R(bz2, bz2id).hp), 5.0), "hp=%s" % str(t.R(bz2, bz2id).hp))
	# たいあたりは向きに関係なく効く(正面でも)
	var tk: RefCounted = t.mk()
	t.hero(tk, 240, 20)
	var tkid: int = new_liz(tk)
	tk.hit_enemy(tkid, 8.0, "tackle", Vector2(200, 100))
	t.ck("liz_tackle_front_full", t.near(float(t.R(tk, tkid).hp), 22.0) and tk.enemies.projectile_list().is_empty())
	# 旋回上限 120度/秒(主人公が真後ろ6m)
	var tn: RefCounted = t.mk()
	t.hero(tn, 100, 100)
	var tnid: int = new_liz(tn)
	t.sim(tn, 0.5)
	var a05: float = absf(t.ang_deg(t.R(tn, tnid).face))
	t.sim(tn, 0.5)
	var a10: float = absf(t.ang_deg(t.R(tn, tnid).face))
	t.sim(tn, 0.6)
	var a16: float = absf(t.ang_deg(t.R(tn, tnid).face))
	t.ck("liz_turn_limit_120dps", t.near(a05, 60.0, 8.0) and t.near(a10, 120.0, 8.0) and a16 > 170.0, "0.5s=%.1f 1.0s=%.1f 1.6s=%.1f" % [a05, a10, a16])
	# 噛みつき後0.8秒は硬直し向きを変えない
	var lk: RefCounted = t.mk()
	t.hero(lk, 168, 100)
	var lkid: int = new_liz(lk)
	var tl2: Array = t.sim(lk, 0.2)
	var bites: Array = t.of_type(tl2, "hero_damage").filter(func(x: Dictionary) -> bool: return x.e.kind == "mirror_lizard")
	t.ck("liz_bites_8", bites.size() >= 1 and t.near(float(bites[0].e.amount), 8.0), "n=%d" % bites.size())
	var f0: Vector2 = t.R(lk, lkid).face
	t.hero(lk, 100, 100)   # 主人公が真後ろへ移動
	t.sim(lk, 0.5)
	t.ck("liz_lock_keeps_facing", t.R(lk, lkid).face.distance_to(f0) < 1e-4 and t.R(lk, lkid).state == "bite", "state=%s" % str(t.R(lk, lkid).state))
	t.sim(lk, 0.6)
	t.ck("liz_turns_after_lock", t.R(lk, lkid).face.distance_to(f0) > 0.05)

# ---------------------------------------------------------------- 濡れたマスとウナギ
func wet_and_eel() -> void:
	var p: RefCounted = t.mk()
	var cells: Array = [Vector2i(20, 7), Vector2i(21, 7)]
	var ev: Array = p.water_landed(cells)
	t.ck("wet_events", t.evs(ev, "wet_cell").size() == 2)
	t.ck("wet_initially", p.common.is_wet(Vector2i(20, 7)))
	t.sim(p, 5.9)
	t.ck("wet_still_at_5_9s", p.common.is_wet(Vector2i(20, 7)))
	t.sim(p, 0.3)
	t.ck("wet_gone_after_6s", not p.common.is_wet(Vector2i(20, 7)))
	var p2: RefCounted = t.mk()
	p2.water_landed([Vector2i(20, 7)])
	t.sim(p2, 4.0)
	p2.water_landed([Vector2i(20, 7)])
	t.sim(p2, 4.0)
	t.ck("wet_extended_by_rewater", p2.common.is_wet(Vector2i(20, 7)))
	t.sim(p2, 2.2)
	t.ck("wet_expires_6s_after_rewater", not p2.common.is_wet(Vector2i(20, 7)))
	# ウナギ
	# 近距離: 放電半径3m。主人公(68,30)はウナギ(50,30)の18px先
	var e1: RefCounted = t.mk()
	t.hero(e1, 68, 30)
	var eid: int = t.sp(e1, "thunder_eel", 50, 30)
	var tl: Array = t.sim(e1, 3.0)
	var dis: Array = t.fxk(t.E(tl), "discharge")
	t.ck("eel_discharges_near_hero", dis.size() >= 1)
	var hd: Array = t.of_type(tl, "hero_damage")
	t.ck("eel_damage_10", hd.size() >= 1 and t.near(float(hd[0].e.amount), 10.0))
	# 予兆1.0秒
	var wu: Array = t.of_type(tl, "fx").filter(func(x: Dictionary) -> bool: return x.e.kind == "eel_windup")
	var dc: Array = t.of_type(tl, "fx").filter(func(x: Dictionary) -> bool: return x.e.kind == "discharge")
	if wu.size() >= 1 and dc.size() >= 1:
		t.ck("eel_windup_1s", t.near(float(dc[0].t) - float(wu[0].t), 1.0, 0.11), "%.2f" % (float(dc[0].t) - float(wu[0].t)))
	# 6秒ごと
	var tl6: Array = t.sim(e1, 14.0)
	var dcs: Array = t.of_type(tl6, "fx").filter(func(x: Dictionary) -> bool: return x.e.kind == "discharge")
	if dcs.size() >= 2:
		t.ck("eel_interval_6s", t.near(float(dcs[1].t) - float(dcs[0].t), 6.0, 0.25), "%.2f" % (float(dcs[1].t) - float(dcs[0].t)))
	else:
		t.ck("eel_interval_6s", false, "discharges=%d" % dcs.size())
	# 乾いた地面: 4m先の主人公(外側3m)は無傷
	var e2: RefCounted = t.mk()
	t.hero(e2, 100, 30)   # ウナギ(60,30)から40px=4m、水際(64)から36px=3.6m
	var e2id: int = t.sp(e2, "thunder_eel", 60, 30)
	var tl2: Array = t.sim(e2, 8.0)
	t.ck("eel_dry_no_conduction", t.of_type(tl2, "hero_damage").is_empty() and t.fxk(t.E(tl2), "discharge").size() >= 1)
	# 濡れたマスがつながっていれば届く(最大10m)
	var e3: RefCounted = t.mk()
	t.hero(e3, 100, 30)
	var e3id: int = t.sp(e3, "thunder_eel", 60, 30)
	var wet_cells: Array = []
	for x: int in range(15, 26):
		wet_cells.append(Vector2i(x, 7))
	e3.water_landed(wet_cells)
	var tl3: Array = t.sim(e3, 3.0)
	t.ck("eel_wet_chain_hits_hero_4m", t.of_type(tl3, "hero_damage").size() >= 1, "n=%d" % t.of_type(tl3, "hero_damage").size())
	# つながっていない(途中が欠けている)と届かない
	var e4: RefCounted = t.mk()
	t.hero(e4, 100, 30)
	t.sp(e4, "thunder_eel", 60, 30)
	var broken: Array = []
	for x: int in range(15, 26):
		if x != 20 and x != 21:
			broken.append(Vector2i(x, 7))
	e4.water_landed(broken)
	var tl4: Array = t.sim(e4, 3.0)
	t.ck("eel_wet_broken_chain_no_hit", t.of_type(tl4, "hero_damage").is_empty())
	# 6秒で乾いたら届かない
	var e5: RefCounted = t.mk()
	t.hero(e5, 100, 30)
	var e5id: int = t.sp(e5, "thunder_eel", 60, 30)
	e5.water_landed(wet_cells)
	t.sim(e5, 6.2)
	var tl5: Array = t.sim(e5, 6.0)
	t.ck("eel_wet_expired_no_hit", t.of_type(tl5, "hero_damage").is_empty())
	# 10mより遠いと届かない: 濡れが 100px(10m)を超えて伸びている先
	var e6: RefCounted = t.mk()
	t.hero(e6, 180, 30)   # ウナギ(60,30)から12m。水際(64)から11.6m > 6m なのでそもそも起動しない
	t.sp(e6, "thunder_eel", 60, 30)
	var far: Array = []
	for x: int in range(15, 46):
		far.append(Vector2i(x, 7))
	e6.water_landed(far)
	var tl6b: Array = t.sim(e6, 3.0)
	t.ck("eel_far_hero_untouched", t.of_type(tl6b, "hero_damage").is_empty())
	# おたすけ植物も伝導で受ける
	var e7: RefCounted = t.mk()
	t.hero(e7, 240, 20)
	t.helper(e7, 31, 100, 30)
	t.sp(e7, "thunder_eel", 60, 30)
	e7.water_landed(wet_cells)
	var tl7: Array = t.sim(e7, 3.0)
	t.ck("eel_wet_chain_hits_helper", t.of_type(tl7, "helper_damage").size() >= 1)
	# 水際から6m以内にいないと放電しない
	var e8: RefCounted = t.mk()
	t.hero(e8, 140, 30)
	t.sp(e8, "thunder_eel", 60, 30)
	var tl8: Array = t.sim(e8, 10.0)
	t.ck("eel_idle_when_no_one_near_shore", t.fxk(t.E(tl8), "discharge").is_empty())
	# 被ダメ x0.75、疲れ中 x1.5、常に当たる
	var d: RefCounted = t.mk()
	t.hero(d, 240, 20)
	var did: int = t.sp(d, "thunder_eel", 30, 30)
	d.hit_enemy(did, 10.0, "shot", Vector2(70, 30))
	t.ck("eel_damage_x0_75", t.near(float(t.R(d, did).hp), 35.0 - 7.5), "hp=%s" % str(t.R(d, did).hp))
	t.ck("eel_always_hittable", d.enemies.hittable_targets().any(func(x: Dictionary) -> bool: return x.id == did))
	var dt2: RefCounted = t.mk()
	t.hero(dt2, 68, 30)
	var dtid: int = t.sp(dt2, "thunder_eel", 50, 30)
	var ev3: Array = []
	for i: int in range(50):
		var e: Array = dt2.advance(0.1)
		ev3.append_array(e)
		if t.fxk(e, "discharge").size() > 0:
			break
	t.ck("eel_tired_after_discharge", t.R(dt2, dtid).state == "tired")
	var h0: float = float(t.R(dt2, dtid).hp)
	dt2.hit_enemy(dtid, 10.0, "shot", Vector2(70, 30))
	t.ck("eel_tired_x1_5_x0_75", t.near(h0 - float(t.R(dt2, dtid).hp), 11.25), "dealt=%.3f" % (h0 - float(t.R(dt2, dtid).hp)))
	t.sim(dt2, 2.2)
	t.ck("eel_tired_ends_2s", t.R(dt2, dtid).state != "tired")

# ---------------------------------------------------------------- ネッコモグラ
func mole() -> void:
	var p: RefCounted = t.mk()
	t.hero(p, 240, 20)
	var pid: int = t.crop(p, "potato", 60, 25)
	var mid: int = t.sp(p, "root_mole", 202, 102)
	t.ck("mole_tags_empty_underground", p.enemies.tags_of(t.R(p, mid)).is_empty())
	t.ck("mole_not_detectable_without_mounds", not p.enemies.detectable_enemies().any(func(x: Dictionary) -> bool: return x.id == mid))
	var tl: Array = t.sim(p, 1.6)
	var e: Dictionary = t.R(p, mid)
	t.ck("mole_moving_underground", e.state == "move" and (e.mounds as Array).size() >= 3, "state=%s mounds=%d" % [e.state, (e.mounds as Array).size()])
	var ok_sp: bool = true
	var ms: Array = e.mounds
	for i: int in range(1, ms.size()):
		if absf(Vector2(ms[i].pos).distance_to(Vector2(ms[i - 1].pos)) - 4.0) > 0.05:
			ok_sp = false
	t.ck("mole_mounds_every_0_4m", ok_sp)
	var det: Array = p.enemies.detectable_enemies().filter(func(x: Dictionary) -> bool: return x.id == mid)
	t.ck("mole_detect_at_last_mound", det.size() == 1 and ms.size() > 0 and Vector2(det[0].pos).distance_to(Vector2(ms[ms.size() - 1].pos)) < 1e-3)
	t.ck("mole_not_in_hittable_targets", not p.enemies.hittable_targets().any(func(x: Dictionary) -> bool: return x.id == mid))
	var h0: float = float(t.R(p, mid).hp)
	var r1: Array = p.hit_enemy(mid, 10.0, "shot", Vector2(150, 100))
	var r2: Array = p.splash(t.R(p, mid).pos, 40.0, 25.0, "bazooka")
	var r3: Array = p.splash(t.R(p, mid).pos, 40.0, 8.0, "tackle")
	t.ck("mole_immune_shot_bazooka_tackle", t.near(float(t.R(p, mid).hp), h0) and t.evs(r1 + r2 + r3, "enemy_damaged").is_empty())
	# かじる: 5ダメージ/2秒
	var tl2: Array = t.sim(p, 8.0)
	var cd: Array = t.of_type(tl2, "crop_damaged")
	t.ck("mole_gnaw_5dmg", cd.size() >= 2 and t.near(float(cd[0].e.amount), 5.0), "n=%d" % cd.size())
	if cd.size() >= 2:
		t.ck("mole_gnaw_interval_2s", t.near(float(cd[1].t) - float(cd[0].t), 2.0, 0.11))
	# 盛り土は10秒で消える
	t.sim(p, 11.0)
	var mounds_left: int = (t.R(p, mid).mounds as Array).size() if t.R(p, mid).has("mounds") else -1
	t.ck("mole_mounds_expire_10s", mounds_left == 0 or p.crops.get_crop(pid).is_empty(), "left=%d" % mounds_left)
	# 水: 0.8m以内で1秒後に飛び出し、3秒目を回す
	var w: RefCounted = t.mk()
	t.hero(w, 240, 20)
	t.crop(w, "potato", 60, 25)
	var wid: int = t.sp(w, "root_mole", 202, 102)
	t.sim(w, 1.0)
	var mpos: Vector2 = t.R(w, wid).pos
	var mc: Vector2i = Vector2i(floori(mpos.x / 4.0), floori(mpos.y / 4.0))
	# 遠い水(2マス以上離す)では反応しない
	w.water_landed([mc + Vector2i(5, 0)])
	t.ck("mole_far_water_no_effect", t.R(w, wid).state == "move" or t.R(w, wid).state == "burrow")
	var wev: Array = w.water_landed([mc])
	t.ck("mole_near_water_pop_pending", t.R(w, wid).state == "pop" and t.fxk(wev, "mole_water").size() == 1)
	t.ck("mole_still_untargetable_during_pop_delay", not w.enemies.hittable_targets().any(func(x: Dictionary) -> bool: return x.id == wid))
	t.sim(w, 1.05)
	t.ck("mole_stunned_after_1s_hittable", t.R(w, wid).state == "stunned" and w.enemies.hittable_targets().any(func(x: Dictionary) -> bool: return x.id == wid))
	t.ck("mole_up_has_beast_tag", w.enemies.tags_of(t.R(w, wid)).has("beast"))
	var hb: float = float(t.R(w, wid).hp)
	w.hit_enemy(wid, 10.0, "shot", Vector2(150, 100))
	t.ck("mole_stunned_damage_x1_5", t.near(hb - float(t.R(w, wid).hp), 15.0), "dealt=%.2f" % (hb - float(t.R(w, wid).hp)))
	var det2: Array = w.enemies.detectable_enemies().filter(func(x: Dictionary) -> bool: return x.id == wid)
	t.ck("mole_detect_at_body_when_up", det2.size() == 1 and Vector2(det2[0].pos).distance_to(t.R(w, wid).pos) < 1e-3)
	t.sim(w, 2.7)
	t.ck("mole_stunned_lasts_about_3s", t.R(w, wid).state == "stunned")
	t.sim(w, 0.5)
	t.ck("mole_dives_again", t.R(w, wid).state != "stunned" and t.R(w, wid).state != "pop")
	# スプラッシュ(水やり)でも追い出される。撃破で報酬6を即時加算(1回)
	var w2: RefCounted = t.mk()
	t.hero(w2, 240, 20)
	t.crop(w2, "potato", 60, 25)
	var w2id: int = t.sp(w2, "root_mole", 202, 102)
	t.sim(w2, 0.5)
	w2.splash(t.R(w2, w2id).pos + Vector2(5, 0), 15.0, 0.0, "water")
	t.ck("mole_splash_water_pops", t.R(w2, w2id).state == "pop")
	t.sim(w2, 1.1)
	var kev: Array = w2.hit_enemy(w2id, 100.0, "shot", Vector2(150, 100))
	var rw: Array = t.evs(kev, "reward")
	t.ck("mole_reward_6_instant_once", rw.size() == 1 and int(rw[0].amount) == 6 and bool(rw[0].get("instant", false)), "n=%d" % rw.size())
	# 株を倒すと1秒だけ顔を出す
	var k: RefCounted = t.mk()
	t.hero(k, 240, 20)
	var cid: int = t.crop(k, "tomato", 50, 26)
	var kid: int = t.sp(k, "root_mole", 202, 102)
	k.crops.crops[0].hp = 4.0
	var tlk: Array = []
	var saw_peek: bool = false
	var peek_hit: bool = false
	for i: int in range(300):
		var ev2: Array = k.advance(0.1)
		if t.fxk(ev2, "mole_peek").size() > 0:
			saw_peek = true
			peek_hit = k.enemies.hittable_targets().any(func(x: Dictionary) -> bool: return x.id == kid)
			break
	t.ck("mole_peeks_after_killing_crop", saw_peek)
	t.ck("mole_peek_is_hittable", peek_hit)
	t.sim(k, 1.2)
	t.ck("mole_peek_ends_after_1s", not k.enemies.hittable_targets().any(func(x: Dictionary) -> bool: return x.id == kid))
	# 優先: ジャガイモ(遠い)が近いトマトより優先
	var pr: RefCounted = t.mk()
	t.hero(pr, 240, 20)
	var tm: int = t.crop(pr, "tomato", 49, 26)
	var po: int = t.crop(pr, "potato", 56, 22)
	t.sp(pr, "root_mole", 202, 102)
	var tlp: Array = t.sim(pr, 25.0)
	var first_id: int = int(t.of_type(tlp, "crop_damaged")[0].e.crop_id) if t.of_type(tlp, "crop_damaged").size() > 0 else -1
	t.ck("mole_prefers_potato_over_nearer_tomato", first_id == po and first_id != tm, "first=%d potato=%d tomato=%d" % [first_id, po, tm])
	# 縄張り12m(家から)の外の株は狙わない
	var tr: RefCounted = t.mk()
	t.hero(tr, 240, 20)
	var far_c: int = t.crop(tr, "potato", 10, 28)
	t.sp(tr, "root_mole", 202, 102)
	var tlt: Array = t.sim(tr, 15.0)
	t.ck("mole_ignores_crop_outside_territory", t.of_type(tlt, "crop_damaged").is_empty())
	# クズの根を食べる(1マス2秒)
	var kz: RefCounted = t.mk()
	t.hero(kz, 240, 20)
	var kzid: int = t.crop(kz, "kudzu", 40, 27)
	var kroots: int = 0
	t.sim(kz, 32.0)
	kroots = kz.crops.root_cells(kzid).size()
	t.ck("kudzu_grew_roots_for_mole_test", kroots >= 2, "roots=%d" % kroots)
	var rc0: Vector2i = kz.crops.root_cells(kzid)[kz.crops.root_cells(kzid).size() - 1]
	var rp: Vector2 = (Vector2(rc0) + Vector2(0.5, 0.5)) * 4.0
	t.sp(kz, "root_mole", rp.x, rp.y, "initial", {"home": rp})
	var t_kz0: float = kz.enemies.time
	var tlkz: Array = t.sim(kz, 30.0)
	var eaten: Array = t.of_type(tlkz, "kudzu_root_removed")
	var reasons: Array = eaten.map(func(x: Dictionary) -> String: return str(x.e.reason))
	t.ck("mole_eats_kudzu_roots", reasons.has("eaten"), str(reasons))
	var first_eaten_t: float = -1.0
	for x: Dictionary in eaten:
		if x.e.reason == "eaten":
			first_eaten_t = float(x.t) - t_kz0
			break
	t.ck("mole_root_eat_takes_2s", first_eaten_t >= 1.9 and first_eaten_t <= 2.5, "%.2f" % first_eaten_t)

# ---------------------------------------------------------------- カバ
func near_water_cell_dist(p: RefCounted, pos: Vector2) -> float:
	var best: float = 1e9
	for cy: int in range(0, 36):
		for cx: int in range(0, 64):
			if p.host.is_water(Vector2i(cx, cy)):
				var wp: Vector2 = (Vector2(cx, cy) + Vector2(0.5, 0.5)) * 4.0
				best = minf(best, wp.distance_to(pos))
	return best

func hippo() -> void:
	var p: RefCounted = t.mk()
	t.hero(p, 240, 130)
	var id: int = t.sp(p, "hippo", 40, 30)
	var ev: Array = p.hit_enemy(id, 10.0, "shot", Vector2(200, 30))
	t.ck("hippo_water_x0_5", t.near(float(t.R(p, id).hp), 85.0), "hp=%s" % str(t.R(p, id).hp))
	t.ck("hippo_in_water_hittable", p.enemies.hittable_targets().any(func(x: Dictionary) -> bool: return x.id == id))
	# 陸の株を食べに上陸(水際から8m以内)。8ダメージ/2秒
	var c: RefCounted = t.mk()
	t.hero(c, 240, 130)
	var cid: int = t.crop(c, "bamboo", 20, 5)
	var hid: int = t.sp(c, "hippo", 40, 30)
	var tl: Array = t.sim(c, 25.0)
	var cd: Array = t.of_type(tl, "crop_damaged")
	t.ck("hippo_lands_and_eats_crop_8dmg", cd.size() >= 1 and t.near(float(cd[0].e.amount), 8.0), "n=%d" % cd.size())
	if cd.size() >= 2:
		t.ck("hippo_eat_interval_2s", t.near(float(cd[1].t) - float(cd[0].t), 2.0, 0.11))
	# 水際から遠い株(8m超)は狙わない
	var f: RefCounted = t.mk()
	t.hero(f, 240, 130)
	t.crop(f, "bamboo", 45, 5)
	var fid: int = t.sp(f, "hippo", 40, 30)
	var maxd: float = 0.0
	var tlf: Array = []
	for i: int in range(400):
		tlf.append_array(t.sim(f, 0.1))
		maxd = maxf(maxd, near_water_cell_dist(f, t.R(f, fid).pos)) if i % 10 == 0 else maxd
	t.ck("hippo_ignores_far_crop", t.of_type(tlf, "crop_damaged").is_empty(), "n=%d" % t.of_type(tlf, "crop_damaged").size())
	t.ck("hippo_stays_within_8m_of_shore", maxd <= 80.0 + 12.0 + 4.0, "maxd=%.1f" % maxd)
	# 陸で累計15ダメージで水へ戻り、10秒休む
	var r: RefCounted = t.mk()
	t.hero(r, 240, 130)
	t.crop(r, "bamboo", 20, 5)
	var rid: int = t.sp(r, "hippo", 40, 30)
	var landed: bool = false
	for i: int in range(400):
		r.advance(0.1)
		var s: String = str(t.R(r, rid).state)
		if s == "eat":
			landed = true
			break
	t.ck("hippo_reaches_eat_state", landed)
	r.hit_enemy(rid, 8.0, "shot", Vector2(120, 20))
	t.ck("hippo_no_retreat_at_8", t.R(r, rid).state != "retreat" and t.near(float(t.R(r, rid).land_dmg), 8.0))
	r.hit_enemy(rid, 8.0, "shot", Vector2(120, 20))
	t.ck("hippo_retreat_after_cumulative_15", t.R(r, rid).state == "retreat", "state=%s land=%s" % [t.R(r, rid).state, str(t.R(r, rid).land_dmg)])
	var reached: bool = false
	for i: int in range(300):
		r.advance(0.1)
		if t.R(r, rid).state == "rest":
			reached = true
			break
	t.ck("hippo_returns_to_water_and_rests", reached)
	var rest_t0: float = r.enemies.time
	var back: bool = false
	for i: int in range(150):
		r.advance(0.1)
		if t.R(r, rid).state == "float":
			back = true
			break
	t.ck("hippo_rest_10s", back and t.near(r.enemies.time - rest_t0, 10.0, 0.25), "rest=%.2f" % (r.enemies.time - rest_t0))
	# 突進: 陸で主人公が4m以内 -> 予兆0.8秒 -> 25ダメージ
	var ch: RefCounted = t.mk()
	t.hero(ch, 90, 40)
	var chid: int = t.sp(ch, "hippo", 72, 40)
	var e: Dictionary = t.R(ch, chid)
	e.state = "land"   # 上陸済みの状態から(陸の座標)
	var tlc: Array = t.sim(ch, 3.0)
	var wuc: Array = t.of_type(tlc, "fx").filter(func(x: Dictionary) -> bool: return x.e.kind == "windup")
	var hdc: Array = t.of_type(tlc, "hero_damage")
	t.ck("hippo_charge_windup_and_25", wuc.size() >= 1 and hdc.size() >= 1 and t.near(float(hdc[0].e.amount), 25.0), "wu=%d hd=%d" % [wuc.size(), hdc.size()])
	if wuc.size() >= 1 and hdc.size() >= 1:
		t.ck("hippo_windup_ge_0_8s_before_hit", float(hdc[0].t) - float(wuc[0].t) >= 0.75, "%.2f" % (float(hdc[0].t) - float(wuc[0].t)))
	# 草を食べる(水際から8mまで)
	var gr: RefCounted = t.mk()
	t.hero(gr, 240, 130)
	var gid: int = t.sp(gr, "hippo", 40, 30)
	var tlg: Array = t.sim(gr, 40.0)
	var gs: Array = t.of_type(tlg, "ground_stage").filter(func(x: Dictionary) -> bool: return x.e.cause == "hippo")
	var within: bool = true
	var worst: float = 0.0
	for x: Dictionary in gs:
		var d: float = near_water_cell_dist(gr, (Vector2(x.e.cell) + Vector2(0.5, 0.5)) * 4.0)
		worst = maxf(worst, d)
		if d > 80.0 + 4.0:
			within = false
	t.ck("hippo_eats_grass_within_8m_of_shore", gs.size() >= 1 and within and (gs[0].e.stage == "sprout"), "n=%d worst=%.1f" % [gs.size(), worst])
	# 主人公が4m以内に来ると主人公を狙う(陸へ)。水辺がないと配置しない仕様はラボ側の責務
	var kh: RefCounted = t.mk()
	t.hero(kh, 240, 130)
	var khid: int = t.sp(kh, "hippo", 40, 30)
	var khev: Array = kh.hit_enemy(khid, 180.0, "bazooka", Vector2(100, 30))   # 水中は x0.5 なので 180 -> 90(HP90)
	t.ck("hippo_hp90_reward20_instant", t.evs(khev, "reward").size() == 1 and int(t.evs(khev, "reward")[0].amount) == 20 and t.evs(khev, "enemy_defeated").size() == 1)
