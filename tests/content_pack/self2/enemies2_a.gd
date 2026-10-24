extends SceneTree
## 第2弾の動物 E22〜E27(ネッコモグラ・スカンク・カバ・ハチミツグマ・ドブネズミ/マンホール・コウモリ)と、
## 向きの判定(合格条件2)・地中/水中/飛行(3)・マンホール網(4)・第1弾との関わり(7)の一部の自己検証(入口スクリプト)。1条件1回、ゲーム内時間は advance で早送り。
## 実行(隔離プロジェクトのみ): Godot --headless --path C:/godot/greenvader_content_sandbox --script res://tests/content_pack/self2/enemies2_a.gd
const Lib: GDScript = preload("res://tests/content_pack/self2/enemies2_lib.gd")
const Facing: GDScript = preload("res://scripts/content_pack/facing.gd")
const OUT_DIR: String = "res://evidence/content_pack/self2"

var L: RefCounted = Lib.new()

func ck(name: String, ok: bool, detail: String = "") -> void:
	L.ck(name, ok, detail)

func _initialize() -> void:
	t_mole()
	t_mole_roots()
	t_skunk()
	t_facing_rules()
	t_hippo()
	t_bear()
	t_sewer()
	t_bat()
	L.finish("enemies2_a", OUT_DIR, self)

# ------------------------------------------------------------------ E22 ネッコモグラ
func t_mole() -> void:
	var p: RefCounted = L.mk()
	var potato: int = L.crop(p, "potato", 56, 15)
	var pumpkin: int = L.crop(p, "pumpkin", 52, 15)   # ジャガイモより近いが、根の多い株を優先する
	var m: int = L.sp(p, "root_mole", 200.0, 60.0)
	var tl: Array = L.timed(p, 0.7)
	var e: Dictionary = L.E(p, m)
	ck("mole_priority_potato_over_nearer_crop", e.state == "move" and int(e.target_crop) == potato, "state=%s target=%d potato=%d pumpkin=%d" % [e.state, int(e.target_crop), potato, pumpkin])
	ck("mole_underground_not_hittable", not L.has_target(p, m) and L.evs(p.hit_enemy(m, 10.0, "shot", Vector2(260, 60)), "enemy_damaged").is_empty() and L.evs(p.splash(Vector2(205, 60), 40.0, 10.0, "bazooka"), "enemy_damaged").is_empty(), "")
	ck("mole_tackle_no_effect", L.evs(p.hit_enemy(m, 10.0, "tackle", Vector2(205, 60)), "enemy_damaged").is_empty(), "")
	L.timed(p, 1.5)
	var det: Array = p.enemies.detectable_enemies()
	var mole_det: Array = det.filter(func(d: Dictionary) -> bool: return d.kind == "root_mole")
	var mounds: Array = L.R(p, m).mounds
	var is_mound: bool = false
	if not mole_det.is_empty() and not mounds.is_empty():
		for mo: Dictionary in mounds:
			if Vector2(mo.pos).distance_to(mole_det[0].pos) < 0.01:
				is_mound = true
	ck("mole_detect_at_mound_position", mole_det.size() == 1 and is_mound, "detect=%d mounds=%d" % [mole_det.size(), mounds.size()])
	# 盛り土: 0.4m(4px)ごと、10秒で消える
	var spacing_ok: bool = true
	for i: int in range(1, mounds.size()):
		var dd: float = Vector2(mounds[i].pos).distance_to(Vector2(mounds[i - 1].pos))
		if dd < 3.0 or dd > 4.5:
			spacing_ok = false
	ck("mole_mound_every_0_4m", spacing_ok and mounds.size() >= 3, "n=%d" % mounds.size())
	var tl2: Array = L.timed(p, 6.0)
	var gn: Array = L.only(tl2, "crop_damaged")
	ck("mole_gnaw_5dmg_every_2s", gn.size() >= 2 and L.near(float(gn[0].e.amount), 5.0) and absf(float(gn[1].t) - float(gn[0].t) - 2.0) < 0.15, "n=%d" % gn.size())
	var hp_p: float = float(p.crops.get_crop(potato).hp)
	ck("mole_gnaw_reduces_hp_in_5s", hp_p < float(p.crops.def_of("potato").hp) and L.near(fmod(float(p.crops.def_of("potato").hp) - hp_p, 5.0), 0.0) and L.R(p, m).state == "gnaw", "hp=%f state=%s" % [hp_p, L.R(p, m).state])
	# 株を倒すと1秒だけ顔を出す(当たる)
	for c: Dictionary in p.crops.crops:
		if int(c.id) == potato:
			c.hp = 3.0
	var tl3: Array = L.timed(p, 2.2)
	var peek_seen: bool = false
	var removed: bool = not L.only(tl3, "crop_removed").is_empty()
	ck("mole_felling_crop_removes_it", removed, "")
	var p2: RefCounted = L.mk()
	var pot2: int = L.crop(p2, "potato", 50, 15)
	var m2: int = L.sp(p2, "root_mole", 200.0, 62.0)
	for c2: Dictionary in p2.crops.crops:
		c2.hp = 3.0
	var peek_hit: bool = false
	var peek_time: float = -1.0
	var left_peek: float = -1.0
	for i2: int in range(80):
		p2.advance(0.1)
		var st: String = str(L.R(p2, m2).state)
		if st == "peek":
			if peek_time < 0.0:
				peek_time = p2.enemies.time
			if L.has_target(p2, m2):
				peek_hit = true
		elif peek_time >= 0.0 and left_peek < 0.0:
			left_peek = p2.enemies.time
	ck("mole_peek_one_second_hittable", peek_hit and peek_time > 0.0 and left_peek > 0.0 and absf((left_peek - peek_time) - 1.0) < 0.15, "peek=%f left=%f" % [peek_time, left_peek])
	# 水で追い出す: 0.8m(8px)以内なら1秒後に地上へ、3秒目を回す(被ダメ×1.5)
	var p3: RefCounted = L.mk()
	L.crop(p3, "potato", 56, 15)
	var m3: int = L.sp(p3, "root_mole", 200.0, 60.0)
	L.timed(p3, 1.0)
	var mp: Vector2 = L.R(p3, m3).pos
	var far_ev: Array = p3.water_landed([Vector2i(int(mp.x / 4.0) + 4, int(mp.y / 4.0))])   # 約1.6m離れた着弾
	L.timed(p3, 1.5)
	ck("mole_water_far_no_effect", not L.has_target(p3, m3) and L.R(p3, m3).state != "pop" and L.R(p3, m3).state != "stunned", "state=%s" % L.R(p3, m3).state)
	mp = L.R(p3, m3).pos
	p3.water_landed([Vector2i(floori(mp.x / 4.0), floori(mp.y / 4.0))])
	var t_water: float = p3.enemies.time
	L.timed(p3, 0.8)
	var before_pop: bool = not L.has_target(p3, m3)
	L.timed(p3, 0.4)
	var e3: Dictionary = L.E(p3, m3)
	ck("mole_water_pops_after_1s", before_pop and e3.state == "stunned" and L.has_target(p3, m3), "state=%s" % e3.state)
	var hp0: float = float(e3.hp)
	var ev3: Array = p3.hit_enemy(m3, 10.0, "shot", Vector2(260, 60))
	ck("mole_stunned_damage_x1_5", L.near(hp0 - float(L.E(p3, m3).hp), 15.0), "dealt=%f" % (hp0 - float(L.E(p3, m3).hp)))
	L.timed(p3, 3.2)
	ck("mole_dives_again_after_3s", not L.has_target(p3, m3) and L.R(p3, m3).state != "stunned", "state=%s" % L.R(p3, m3).state)
	# 水やりの splash でも同様(0.8m以内)
	var p4: RefCounted = L.mk()
	L.crop(p4, "potato", 56, 15)
	var m4: int = L.sp(p4, "root_mole", 200.0, 60.0)
	L.timed(p4, 1.0)
	p4.splash(L.R(p4, m4).pos + Vector2(5, 0), 0.0, 0.0, "water")
	L.timed(p4, 1.2)
	ck("mole_water_splash_also_pops", L.R(p4, m4).state == "stunned", "state=%s" % L.R(p4, m4).state)
	# 地中でも安定判定には数える。地上へ出ている間だけ獣タグの作用を受ける
	ck("mole_counts_for_stability_underground", p.enemies.counts_for_stability(m), "")
	var p5: RefCounted = L.mk()
	var m5: int = L.sp(p5, "root_mole", 100.0, 60.0)
	ck("mole_tags_only_when_surfaced", p5.enemies.tags_of(L.R(p5, m5)).is_empty(), "")
	L.R(p5, m5).state = "stunned"
	ck("mole_beast_tag_when_surfaced", p5.enemies.tags_of(L.R(p5, m5)).has("beast"), "")
	# 盛り土は10秒で消える(消えた分は検知にも出ない)
	var p6: RefCounted = L.mk()
	L.crop(p6, "potato", 56, 15)
	var m6: int = L.sp(p6, "root_mole", 200.0, 60.0)
	L.timed(p6, 4.0)
	var n_early: int = L.R(p6, m6).mounds.size()
	var first_until: float = float(L.R(p6, m6).mounds[0].until) if n_early > 0 else 0.0
	L.R(p6, m6).state = "burrow"
	L.R(p6, m6).think_at = 1e9      # 以後は動かさず、盛り土が消えるのを見る
	L.timed(p6, 11.0)
	var det6: Array = p6.enemies.detectable_enemies().filter(func(d: Dictionary) -> bool: return d.kind == "root_mole")
	ck("mole_mounds_expire_after_10s", n_early >= 3 and L.R(p6, m6).mounds.is_empty() and det6.is_empty() and p6.enemies.time > first_until, "early=%d now=%d" % [n_early, L.R(p6, m6).mounds.size()])

func t_mole_roots() -> void:
	var p: RefCounted = L.mk(3)
	var kz: int = L.crop(p, "kudzu", 50, 15)
	p.crops.advance(40.0)
	var roots: Array = p.crops.root_cells(kz)
	if roots.is_empty():
		ck("mole_root_eat_setup", false, "no roots")
		return
	# 株から最も遠い根のマスの上に巣穴を置く → 株より近い根を優先して食べる
	var far: Vector2i = roots[0]
	var stock_c: Vector2 = Vector2(51.0 * 4.0, 16.0 * 4.0)
	for rc: Vector2i in roots:
		if Vector2(rc).distance_to(stock_c / 4.0) > Vector2(far).distance_to(stock_c / 4.0):
			far = rc
	var home: Vector2 = Vector2(far) * 4.0 + Vector2(2, 2)
	var n0: int = roots.size()
	var m: int = L.sp(p, "root_mole", home.x, home.y)
	L.timed(p, 0.7)
	var e: Dictionary = L.E(p, m)
	ck("mole_prefers_root_cell_target", str(e.t_kind) == "root" and Vector2i(e.t_cell) == far, "kind=%s cell=%s far=%s" % [e.t_kind, str(e.t_cell), str(far)])
	var tl: Array = L.timed(p, 3.0)
	var ate: Array = L.only(tl, "kudzu_root_removed")
	ck("mole_eats_root_cell_in_2s", ate.size() >= 1 and str(ate[0].e.reason) == "eaten" and p.crops.root_cells(kz).size() == n0 - 1 and not p.crops.root_cells(kz).has(far), "events=%d roots=%d->%d" % [ate.size(), n0, p.crops.root_cells(kz).size()])

# ------------------------------------------------------------------ E23 スカンク
func t_skunk() -> void:
	var p: RefCounted = L.mk()
	var sk: int = L.sp(p, "skunk", 200.0, 100.0)
	L.R(p, sk).face = Vector2.RIGHT
	hero_far(p)
	# 横(90°)・後ろ(180°)・境界外(61°)からは噴かない
	var side: Array = p.hit_enemy(sk, 1.0, "shot", Vector2(200, 150))
	ck("skunk_side_hit_no_windup", L.R(p, sk).state != "windup", "state=%s" % L.R(p, sk).state)
	p.hit_enemy(sk, 1.0, "shot", Vector2(140, 100))
	ck("skunk_back_hit_no_windup", L.R(p, sk).state != "windup", "")
	var a61: Vector2 = Vector2(200, 100) + Vector2.from_angle(deg_to_rad(61.0)) * 60.0
	p.hit_enemy(sk, 1.0, "shot", a61)
	ck("skunk_61deg_no_windup", L.R(p, sk).state != "windup", "")
	var a59: Vector2 = Vector2(200, 100) + Vector2.from_angle(deg_to_rad(59.0)) * 60.0
	# たいあたりでは噴かない(正面でも)
	p.hit_enemy(sk, 1.0, "tackle", Vector2(230, 100))
	ck("skunk_tackle_front_no_windup", L.R(p, sk).state != "windup", "")
	ck("skunk_no_cloud_before_frontal", p.enemies.odor.is_empty(), "")
	# 正面の射撃 → 0.6秒の予兆 → 撃った相手の方向へ扇形
	p.hit_enemy(sk, 1.0, "shot", a59)
	var t0: float = p.enemies.time
	ck("skunk_front_59deg_windup", L.R(p, sk).state == "windup", "")
	L.timed(p, 0.5)
	ck("skunk_no_cloud_during_windup", p.enemies.odor.is_empty(), "")
	L.timed(p, 0.2)
	ck("skunk_cloud_after_0_6s", p.enemies.odor.size() == 1, "n=%d" % p.enemies.odor.size())
	var cl: Dictionary = p.enemies.odor[0]
	var want: Vector2 = (a59 - Vector2(200, 100)).normalized()
	ck("skunk_cloud_toward_shooter", Vector2(cl.dir).distance_to(want) < 0.01 and L.near(float(cl.length), 50.0) and L.near(float(cl.half_deg), 30.0) and L.near(float(cl.until) - t0, 8.6, 0.15), "dir=%s until-t0=%f" % [str(cl.dir), float(cl.until) - t0])
	# 雲の中: 主人公 ×0.6、おたすけ植物は仕事停止(odor)。外・敵・株・草には作用しない
	var inside: Vector2 = Vector2(200, 100) + want * 25.0
	var outside_angle: Vector2 = Vector2(200, 100) + want.rotated(deg_to_rad(45.0)) * 25.0
	L.hero(p, inside.x, inside.y)
	L.helper(p, 7, inside.x + 2.0, inside.y)
	L.helper(p, 8, outside_angle.x, outside_angle.y)
	var c1: int = L.crop(p, "pumpkin", int(inside.x / 4.0), int(inside.y / 4.0) + 3)
	var hp_c: float = float(p.crops.get_crop(c1).hp)
	var tl: Array = L.timed(p, 1.0)
	var slow: Array = L.only(tl, "hero_slow")
	ck("skunk_cloud_hero_slow_0_6", slow.size() >= 1 and L.near(float(slow[0].e.factor), 0.6) and str(slow[0].e.source) == "odor" and L.near(p.enemies.hero_odor_mult(), 0.6), "n=%d" % slow.size())
	var stops: Array = L.only(tl, "helper_stop")
	var stop_ids: Array = stops.map(func(x: Dictionary) -> int: return int(x.e.helper_id))
	ck("skunk_cloud_helper_stop_odor", stops.size() >= 1 and stop_ids.has(7) and not stop_ids.has(8) and str(stops[0].e.cause) == "odor" and p.common.helper_stopped(7), "ids=%s" % str(stop_ids))
	ck("skunk_cloud_no_effect_on_crop_enemy", L.near(float(p.crops.get_crop(c1).hp), hp_c) and L.evs(L.plain(tl), "enemy_damaged").is_empty(), "")
	# 間隔6秒: 噴いた直後の正面命中では噴かない。6秒後は噴ける
	p.hit_enemy(sk, 1.0, "shot", a59)
	ck("skunk_interval_blocks_second_spray", L.R(p, sk).state != "windup", "")
	L.timed(p, 5.2)
	L.hero(p, 10.0, 10.0)
	L.R(p, sk).face = Vector2.RIGHT
	p.hit_enemy(sk, 1.0, "shot", a59)
	ck("skunk_sprays_again_after_6s", L.R(p, sk).state == "windup", "")
	L.timed(p, 0.7)
	L.timed(p, 8.5)
	ck("skunk_cloud_gone_after_8s", p.enemies.odor.is_empty(), "")
	# バズーカ(爆心が正面)・おたすけ植物の弾(発射元が正面)でも噴く
	var p2: RefCounted = L.mk()
	var s2: int = L.sp(p2, "skunk", 200.0, 100.0)
	L.R(p2, s2).face = Vector2.RIGHT
	hero_far(p2)
	p2.splash(Vector2(230, 100), 40.0, 1.0, "bazooka")
	ck("skunk_bazooka_front_windup", L.R(p2, s2).state == "windup", "")
	var p3: RefCounted = L.mk()
	var s3: int = L.sp(p3, "skunk", 200.0, 100.0)
	L.R(p3, s3).face = Vector2.RIGHT
	hero_far(p3)
	p3.hit_enemy(s3, 1.0, "helper", Vector2(240, 100))
	ck("skunk_helper_bullet_front_windup", L.R(p3, s3).state == "windup", "")
	# ニンニクの範囲内では雲が出ない
	var p4: RefCounted = L.mk()
	var s4: int = L.sp(p4, "skunk", 200.0, 100.0)
	L.R(p4, s4).face = Vector2.RIGHT
	hero_far(p4)
	L.crop(p4, "garlic", 51, 25)
	p4.hit_enemy(s4, 1.0, "shot", Vector2(240, 100))
	var tl4: Array = L.timed(p4, 1.0)
	ck("skunk_garlic_cancels_cloud", p4.enemies.odor.is_empty() and not L.fx_of(tl4, "odor_cancel").is_empty(), "")
	# 旋回は90°/秒まで(主人公が6m以内で背後にいる)
	var p5: RefCounted = L.mk()
	var s5: int = L.sp(p5, "skunk", 200.0, 100.0)
	L.R(p5, s5).face = Vector2.RIGHT
	L.hero(p5, 160.0, 100.0)
	L.timed(p5, 0.5)
	var ang: float = Facing.angle_between_deg(Vector2.RIGHT, L.R(p5, s5).face)
	ck("skunk_turn_90dps_half_second", ang > 40.0 and ang <= 45.5, "angle=%f" % ang)
	L.timed(p5, 1.6)
	ck("skunk_turn_completes_in_2s", Facing.angle_between_deg(Vector2(160.0, 100.0) - L.R(p5, s5).pos, L.R(p5, s5).face) < 8.0, "face=%s pos=%s" % [str(L.R(p5, s5).face), str(L.R(p5, s5).pos)])
	# 縄張り内の成熟した株をかじる(3ダメージ/2秒)
	var p6: RefCounted = L.mk()
	var s6: int = L.sp(p6, "skunk", 200.0, 100.0)
	var cp: int = L.crop(p6, "pumpkin", 54, 25)
	var tl6: Array = L.timed(p6, 8.0)
	var dm: Array = L.only(tl6, "crop_damaged")
	ck("skunk_gnaws_crop_3dmg", dm.size() >= 1 and L.near(float(dm[0].e.amount), 3.0, 1.0), "n=%d amount=%s" % [dm.size(), str(dm[0].e.amount) if not dm.is_empty() else "-"])

func hero_far(p: RefCounted) -> void:
	L.hero(p, 10.0, 10.0)

# ------------------------------------------------------------------ 向きの判定(共通部品)
func t_facing_rules() -> void:
	ck("facing_front_boundary_60", Facing.is_front(Vector2.RIGHT, Vector2.ZERO, Vector2.from_angle(deg_to_rad(60.0)) * 10.0) and not Facing.is_front(Vector2.RIGHT, Vector2.ZERO, Vector2.from_angle(deg_to_rad(60.5)) * 10.0), "")
	ck("facing_origin_by_kind", Facing.attack_origin("shot", Vector2(1, 2), Vector2(3, 4), Vector2(5, 6)) == Vector2(1, 2) and Facing.attack_origin("bazooka", Vector2(1, 2), Vector2(3, 4), Vector2(5, 6)) == Vector2(3, 4) and Facing.attack_origin("tackle", Vector2(1, 2), Vector2(3, 4), Vector2(5, 6)) == Vector2(5, 6) and Facing.attack_origin("water", Vector2(1, 2), Vector2(3, 4), Vector2(5, 6)) == null, "")
	var f: Vector2 = Facing.turn_toward(Vector2.RIGHT, Vector2.LEFT, 120.0, 0.5)
	ck("facing_turn_limit", L.near(Facing.angle_between_deg(Vector2.RIGHT, f), 60.0, 0.1), "")

# ------------------------------------------------------------------ E24 カバ
func t_hippo() -> void:
	var p: RefCounted = L.mk()
	var h: int = L.sp(p, "hippo", 50.0, 50.0)
	var c: int = L.crop(p, "pumpkin", 24, 6)          # 水際(x=64px)から約3m
	var far_c: int = L.crop(p, "pumpkin", 44, 6)       # 水際から11m以上 → 狙わない
	var in_water: bool = p.host.is_water(Vector2i(12, 12))
	var tl: Array = L.timed(p, 1.2)
	ck("hippo_habitat_water_start", p.host.is_water(Vector2i(floori(L.R(p, h).pos.x / 4.0), floori(L.R(p, h).pos.y / 4.0))), "")
	# 水中の被ダメ×0.5
	var hp0: float = float(L.R(p, h).hp)
	p.hit_enemy(h, 10.0, "shot", Vector2(120, 50))
	ck("hippo_in_water_hittable_half", L.near(hp0 - float(L.R(p, h).hp), 5.0), "")
	# 上陸して株を食べる(8ダメージ/2秒)
	var tl2: Array = L.timed(p, 14.0)
	var dm: Array = L.only(tl2, "crop_damaged")
	var e: Dictionary = L.E(p, h)
	var on_land: bool = not p.host.is_water(Vector2i(floori(e.pos.x / 4.0), floori(e.pos.y / 4.0)))
	ck("hippo_lands_and_eats_crop_8dmg", dm.size() >= 1 and L.near(float(dm[0].e.amount), 8.0) and on_land, "n=%d state=%s land=%s" % [dm.size(), e.state, str(on_land)])
	ck("hippo_far_crop_untouched", float(p.crops.get_crop(far_c).hp) >= 29.9 or p.crops.get_crop(far_c).is_empty() == false, "")
	# 陸では×1。累計15ダメージで水へ戻り、10秒休む
	var hp1: float = float(L.R(p, h).hp)
	p.hit_enemy(h, 10.0, "shot", Vector2(150, 60))
	ck("hippo_on_land_full_damage", L.near(hp1 - float(L.R(p, h).hp), 10.0), "dealt=%f" % (hp1 - float(L.R(p, h).hp)))
	ck("hippo_not_yet_retreat_at_10", L.R(p, h).state != "retreat", "state=%s" % L.R(p, h).state)
	p.hit_enemy(h, 6.0, "shot", Vector2(150, 60))
	ck("hippo_retreat_at_15_cumulative", L.R(p, h).state == "retreat", "state=%s" % L.R(p, h).state)
	var tl3: Array = L.timed(p, 14.0)
	var rested: bool = false
	var rest_t: float = -1.0
	var up_t: float = -1.0
	var p2: RefCounted = L.mk()
	var h2: int = L.sp(p2, "hippo", 50.0, 50.0)
	L.crop(p2, "pumpkin", 24, 6)
	var seen_rest: float = -1.0
	var seen_after: float = -1.0
	for i: int in range(400):
		p2.advance(0.1)
		var e2: Dictionary = L.R(p2, h2)
		if seen_rest < 0.0 and e2.state == "land" or (seen_rest < 0.0 and e2.state == "eat"):
			# 上陸中に15ダメージを与えて撤退させる
			L.R(p2, h2).land_dmg = 14.0
			p2.hit_enemy(h2, 2.0, "shot", Vector2(160, 40))
			seen_rest = -2.0
		if seen_rest == -2.0 and L.R(p2, h2).state == "rest":
			seen_rest = p2.enemies.time
		if seen_rest > 0.0 and L.R(p2, h2).state == "float" and seen_after < 0.0:
			seen_after = p2.enemies.time
	ck("hippo_rests_10s_then_returns", seen_rest > 0.0 and seen_after > 0.0 and absf((seen_after - seen_rest) - 10.0) < 0.3, "rest@%f float@%f" % [seen_rest, seen_after])
	# 草(成熟)を食べ、段階を1つ戻すイベント
	var p3: RefCounted = L.mk()
	var h3: int = L.sp(p3, "hippo", 50.0, 50.0)
	var tl4: Array = L.timed(p3, 14.0)
	var gs: Array = L.only(tl4, "ground_stage")
	ck("hippo_eats_grass_stage_back", gs.size() >= 1 and gs[0].e.stage == "sprout" and gs[0].e.cause == "hippo", "n=%d" % gs.size())
	# 陸の行動範囲は水際から8m(80px)まで
	var max_shore: float = 0.0
	var p4: RefCounted = L.mk()
	var h4: int = L.sp(p4, "hippo", 50.0, 50.0)
	L.crop(p4, "pumpkin", 35, 6)   # 水際から約7.6m
	for i3: int in range(200):
		p4.advance(0.1)
		var pos: Vector2 = L.R(p4, h4).pos
		var ws: Variant = p4.enemies.nearest_water_pos(pos, 200.0)
		if ws != null and not p4.host.is_water(Vector2i(floori(pos.x / 4.0), floori(pos.y / 4.0))):
			max_shore = maxf(max_shore, pos.distance_to(Vector2(ws)))
	ck("hippo_land_within_8m_of_shore", max_shore <= 82.0 and max_shore > 20.0, "max=%f" % max_shore)
	# 突進: 陸で主人公が4m以内 → 予兆0.8秒 → 7m/sで直進(命中25)
	var p5: RefCounted = L.mk()
	var h5: int = L.sp(p5, "hippo", 90.0, 26.0)
	L.R(p5, h5).state = "land"
	L.hero(p5, 118.0, 26.0)
	p5.advance(0.1)
	ck("hippo_windup_when_hero_within_4m_on_land", L.R(p5, h5).state == "windup", "state=%s" % L.R(p5, h5).state)
	var tl5: Array = L.timed(p5, 2.5)
	var hd: Array = L.only(tl5, "hero_damage")
	ck("hippo_charge_hits_25", hd.size() >= 1 and L.near(float(hd[0].e.amount), 25.0), "n=%d" % hd.size())
	ck("hippo_herbivore_tag", p5.enemies.tags_of(L.R(p5, h5)).has("herbivore"), "")
	# 落果(リンゴ)を水際から8m以内で食べる
	var p6: RefCounted = L.mk()
	var h6: int = L.sp(p6, "hippo", 50.0, 50.0)
	p6.crops.fruits.append({"id": 1, "cell": Vector2i(22, 12), "source_id": 0})
	p6.crops.next_fruit_id = 2
	var tl6: Array = L.timed(p6, 14.0)
	ck("hippo_eats_fallen_fruit", not L.only(tl6, "fruit_eaten").is_empty() and p6.crops.fruits.is_empty(), "")

# ------------------------------------------------------------------ E25 ハチミツグマ
func t_bear() -> void:
	var p: RefCounted = L.mk()
	hero_far(p)
	var b: int = L.sp(p, "honey_bear", 200.0, 100.0)
	p.crops.fruits.append({"id": 1, "cell": Vector2i(52, 28), "source_id": 0})
	p.crops.next_fruit_id = 2
	var hive: int = L.sp(p, "honeybee_hive", 220.0, 112.0)
	var straw: int = L.crop(p, "strawberry", 46, 30)
	L.timed(p, 0.7)
	var e: Dictionary = L.E(p, b)
	ck("bear_priority_fruit_first", str(e.t_kind) == "fruit", "kind=%s" % e.t_kind)
	var order: Array = []
	var slept_at: float = -1.0
	var sat_seen: Array = []
	var anger_enemy: bool = false
	var bear_stung: float = 0.0
	var all_tl: Array = []
	for i: int in range(600):
		var ev: Array = p.advance(0.1)
		for x: Dictionary in ev:
			if x.type == "enemy_damaged" and x.kind == "sting":
				bear_stung += float(x.amount)
		var eb: Dictionary = L.R(p, b)
		if order.is_empty() or order[order.size() - 1] != str(eb.t_kind):
			if str(eb.t_kind) != "":
				order.append(str(eb.t_kind))
		var hv: Dictionary = L.R(p, hive)
		if not hv.is_empty() and hv.get("ttype", "") == "enemy" and hv.state == "angry":
			anger_enemy = true
		if eb.state == "sleep":
			slept_at = p.enemies.time
			break
	ck("bear_order_fruit_hive_then_sleep", order.size() >= 2 and order[0] == "fruit" and order[1] == "hive", "order=%s" % str(order))
	ck("bear_hive_destroyed_swarm_gone", L.R(p, hive).is_empty() and L.ids_of(p, "honeybee_swarm").is_empty(), "")
	ck("bear_bees_sting_bear_while_gnawing", anger_enemy and bear_stung > 0.0, "angry_at_bear=%s stung=%f" % [str(anger_enemy), bear_stung])
	ck("bear_sleeps_at_satiety_3", slept_at > 0.0 and int(L.R(p, b).satiety) >= 3 and L.R(p, b).pos.distance_to(L.R(p, b).home) < 8.0, "sat=%d" % int(L.R(p, b).satiety))
	ck("bear_fruit_consumed", p.crops.fruits.is_empty(), "")
	# 眠り中: 被ダメ×1.5、攻撃されても起きない。HPが半分を切ると起きて怒る
	L.R(p, b).hp = 80.0   # 巣のミツバチに刺された分を戻す
	var hp0: float = float(L.R(p, b).hp)
	p.hit_enemy(b, 10.0, "shot", Vector2(260, 100))
	ck("bear_sleep_damage_x1_5_no_wake", L.near(hp0 - float(L.R(p, b).hp), 15.0) and L.R(p, b).state == "sleep", "")
	p.hit_enemy(b, 10.0, "shot", Vector2(260, 100))
	ck("bear_sleep_still_asleep_above_half", L.R(p, b).state == "sleep" and float(L.R(p, b).hp) >= 40.0, "hp=%f" % float(L.R(p, b).hp))
	p.hit_enemy(b, 8.0, "shot", Vector2(260, 100))
	ck("bear_wakes_enraged_below_half", L.R(p, b).state == "enraged" and float(L.R(p, b).hp) < 40.0 and int(L.R(p, b).satiety) == 0, "state=%s" % L.R(p, b).state)
	# 怒り: 予兆0.8秒 → 爪15ダメージ / 1.2秒、18mより離れると落ち着く
	L.hero(p, L.R(p, b).pos.x + 14.0, L.R(p, b).pos.y)
	var tl: Array = L.timed(p, 3.0)
	var claws: Array = L.only(tl, "hero_damage")
	ck("bear_claw_15_after_windup", claws.size() >= 1 and L.near(float(claws[0].e.amount), 15.0) and float(claws[0].t) - p.enemies.time + 3.0 >= 0.75, "n=%d" % claws.size())
	if claws.size() >= 2:
		ck("bear_claw_interval_1_2s", absf(float(claws[1].t) - float(claws[0].t) - 1.2) < 0.15, "")
	else:
		ck("bear_claw_interval_1_2s", false, "claws=%d" % claws.size())
	L.hero(p, 20.0, 20.0)
	L.timed(p, 0.3)
	ck("bear_calms_when_hero_beyond_18m", L.R(p, b).state != "enraged", "state=%s" % L.R(p, b).state)
	# 満腹度: 落果3つで眠る(2つでは眠らない)
	var p2: RefCounted = L.mk()
	hero_far(p2)
	var b2: int = L.sp(p2, "honey_bear", 200.0, 100.0)
	for i2: int in range(3):
		p2.crops.fruits.append({"id": i2 + 1, "cell": Vector2i(52 + i2, 28), "source_id": 0})
	p2.crops.next_fruit_id = 4
	var sat_at_2: bool = false
	var slept: bool = false
	for i3: int in range(900):
		p2.advance(0.1)
		var eb2: Dictionary = L.R(p2, b2)
		if p2.crops.fruits.size() == 1 and int(eb2.satiety) == 2 and eb2.state != "sleep" and eb2.state != "return":
			sat_at_2 = true
		if eb2.state == "sleep":
			slept = true
			break
	ck("bear_three_fruits_sleep_two_do_not", sat_at_2 and slept and int(L.R(p2, b2).satiety) == 3, "sat=%d" % int(L.R(p2, b2).satiety))
	# 果実の植物(イチゴ): 株を倒すと満腹度+2、6ダメージ/2秒
	var p3: RefCounted = L.mk()
	hero_far(p3)
	var b3: int = L.sp(p3, "honey_bear", 200.0, 100.0)
	var st3: int = L.crop(p3, "strawberry", 52, 25)
	for c: Dictionary in p3.crops.crops:
		c.hp = 11.0
	var tl3: Array = L.timed(p3, 14.0)
	var dm3: Array = L.only(tl3, "crop_damaged")
	ck("bear_eats_fruit_plant_6dmg_satiety_2", dm3.size() >= 2 and L.near(float(dm3[0].e.amount), 6.0) and int(L.R(p3, b3).satiety) == 2, "n=%d sat=%d" % [dm3.size(), int(L.R(p3, b3).satiety)])
	# 起きている間に攻撃されると立ち上がって怒る
	p3.hit_enemy(b3, 3.0, "shot", Vector2(260, 100))
	ck("bear_awake_hit_enrages", L.R(p3, b3).state == "enraged", "")

# ------------------------------------------------------------------ E26 ドブネズミとマンホール
func t_sewer() -> void:
	var p: RefCounted = L.mk(5)
	hero_far(p)
	for c: Vector2i in [Vector2i(8, 26), Vector2i(14, 26), Vector2i(20, 26)]:
		p.host.set_terrain(c, 1)   # 荒地(緑化済みでないマス)
	var net: Dictionary = p.enemies.spawn_manhole_net([Vector2(34, 106), Vector2(58, 106), Vector2(82, 106)], "initial")
	var mhs: Array = net.manholes
	ck("manhole_net_of_3", mhs.size() == 3 and L.R(p, mhs[0]).net_id == net.net_id, "")
	ck("manhole_not_hittable_not_shootable", not L.has_target(p, mhs[0]) and L.evs(p.hit_enemy(mhs[0], 99.0, "shot"), "enemy_damaged").is_empty(), "")
	ck("manhole_detectable_as_nest", p.enemies.detectable_enemies().filter(func(d: Dictionary) -> bool: return d.kind == "manhole").size() == 3, "")
	# 生産: 15秒ごと、網全体で生存6匹まで、報酬0
	L.timed(p, 14.0)
	ck("sewer_none_before_15s", L.ids_of(p, "sewer_rat").is_empty(), "")
	L.timed(p, 1.5)
	var rats: Array = L.ids_of(p, "sewer_rat")
	ck("sewer_first_rat_at_15s", rats.size() == 1 and L.R(p, rats[0]).origin == "produced", "n=%d" % rats.size())
	var max_alive: int = 0
	var saw_ug: bool = false
	var exits: Dictionary = {}
	var all_ev: Array = []
	for i: int in range(1400):
		var ev: Array = p.advance(0.1)
		all_ev.append_array(ev)
		var n: int = L.ids_of(p, "sewer_rat").size()
		max_alive = maxi(max_alive, n)
		for rid: int in L.ids_of(p, "sewer_rat"):
			var r: Dictionary = L.R(p, rid)
			if r.state == "ug":
				saw_ug = true
				exits[int(r.exit_id)] = true
	ck("sewer_alive_capped_at_6", max_alive == 6, "max=%d" % max_alive)
	ck("sewer_underground_move_3s_to_other_manhole", saw_ug and exits.size() >= 2, "exits=%d" % exits.size())
	ck("sewer_produced_reward_zero", L.evs(all_ev, "reward").filter(func(x: Dictionary) -> bool: return x.kind == "sewer_rat").is_empty(), "")
	for rid2: int in L.ids_of(p, "sewer_rat"):
		var r2: Dictionary = L.R(p, rid2)
		if r2.state == "ug":
			var in_det: bool = p.enemies.detectable_enemies().any(func(d: Dictionary) -> bool: return int(d.id) == rid2)
			ck("sewer_underground_hidden_from_hit_and_detect", not L.has_target(p, rid2) and not in_det, "")
			break
	# 初期配置のネズミは報酬2。小型・獣タグ(ハエトリソウの対象)
	var p2: RefCounted = L.mk()
	var r_i: int = L.sp(p2, "sewer_rat", 100.0, 100.0)
	ck("sewer_rat_tags_small_beast", p2.enemies.tags_of(L.R(p2, r_i)).has("small") and p2.enemies.tags_of(L.R(p2, r_i)).has("beast"), "")
	var ev2: Array = p2.hit_enemy(r_i, 10.0, "shot", Vector2(150, 100))
	var rw: Array = L.evs(ev2, "reward")
	ck("sewer_rat_initial_reward_2_instant", rw.size() == 1 and int(rw[0].amount) == 2 and bool(rw[0].get("instant", false)), "")
	# マンホールへの例外的な設置(緑化済み以外の通常条件は有効)
	var p3: RefCounted = L.mk(5)
	hero_far(p3)
	for c3: Vector2i in [Vector2i(8, 26), Vector2i(14, 26), Vector2i(20, 26), Vector2i(30, 26)]:
		p3.host.set_terrain(c3, 1)
	var net3: Dictionary = p3.enemies.spawn_manhole_net([Vector2(34, 106), Vector2(58, 106), Vector2(82, 106)], "initial")
	ck("manhole_cell_placement_exception", bool(p3.crops.check_placement("pumpkin", Vector2i(8, 26)).ok), str(p3.crops.check_placement("pumpkin", Vector2i(8, 26))))
	ck("normal_waste_cell_still_requires_green", p3.crops.check_placement("pumpkin", Vector2i(30, 26)).reason == "requires_green", "")
	ck("manhole_other_conditions_still_apply", not bool(p3.crops.check_placement("wasabi", Vector2i(8, 26)).ok), str(p3.crops.check_placement("wasabi", Vector2i(8, 26))))
	var rr: Array = []
	for i4: int in range(3):
		var cell: Vector2i = [Vector2i(8, 26), Vector2i(14, 26), Vector2i(20, 26)][i4]
		var pl: Dictionary = p3.crops.spawn_crop("pumpkin", cell, 0, {"mature": true, "watered": true, "skip_check": false})
		rr.append(int(pl.id) if bool(pl.ok) else -1)
	ck("manhole_plugs_placed_via_normal_check", not rr.has(-1), str(rr))
	var tl3: Array = L.timed(p3, 0.3)
	var rw3: Array = L.evs(L.plain(tl3), "reward").filter(func(x: Dictionary) -> bool: return x.kind == "manhole")
	ck("manhole_all_closed_suppresses_nest_reward_30_once", rw3.size() == 1 and int(rw3[0].amount) == 30 and bool(rw3[0].instant) and L.R(p3, net3.manholes[0]).state == "closed", "n=%d" % rw3.size())
	ck("manhole_closed_not_counted_for_stability", p3.enemies.living_for_stability().filter(func(d: Dictionary) -> bool: return d.kind == "manhole").is_empty(), "")
	var tl3b: Array = L.timed(p3, 20.0)
	ck("manhole_no_rat_production_when_closed", L.ids_of(p3, "sewer_rat").is_empty() and L.evs(L.plain(tl3b), "reward").is_empty(), "")
	# 株が倒されると再び開く。再び塞いでも報酬は1回だけ
	p3.crops.remove_crop(rr[0], "enemy")
	L.timed(p3, 0.3)
	ck("manhole_reopens_when_plug_lost", L.R(p3, net3.manholes[0]).state == "open" and p3.enemies.living_for_stability().filter(func(d: Dictionary) -> bool: return d.kind == "manhole").size() == 1, "")
	var again: Dictionary = p3.crops.spawn_crop("pumpkin", Vector2i(8, 26), 0, {"mature": true, "watered": true})
	var tl3c: Array = L.timed(p3, 0.3)
	ck("manhole_second_close_no_second_reward", L.evs(L.plain(tl3c), "reward").is_empty(), "")
	# 塞がれた出口から出ようとするネズミは下から株をかじる(3ダメージ/2秒)
	var p4: RefCounted = L.mk(9)
	hero_far(p4)
	for c4: Vector2i in [Vector2i(8, 26), Vector2i(14, 26)]:
		p4.host.set_terrain(c4, 1)
	var net4: Dictionary = p4.enemies.spawn_manhole_net([Vector2(34, 106), Vector2(58, 106)], "initial")
	var rat: int = L.sp(p4, "sewer_rat", 34.0, 106.0, "initial", {"net_id": net4.net_id, "home_mh": net4.manholes[0]})
	L.R(p4, rat).state = "enter"
	L.R(p4, rat).exit_id = net4.manholes[0]
	L.timed(p4, 0.3)
	var rr4: Dictionary = p4.crops.spawn_crop("bamboo", Vector2i(14, 26), 0, {"mature": true, "watered": true})
	var plug_id: int = int(rr4.id)
	ck("rat_entered_underground_toward_other_manhole", L.R(p4, rat).state == "ug" and int(L.R(p4, rat).exit_id) == int(net4.manholes[1]), "state=%s" % L.R(p4, rat).state)
	L.timed(p4, 3.4)
	ck("rat_stuck_when_exit_plugged", L.R(p4, rat).state == "stuck" and not L.has_target(p4, rat), "state=%s" % L.R(p4, rat).state)
	var hp_b: float = float(p4.crops.get_crop(plug_id).hp)
	var tl4: Array = L.timed(p4, 4.1)
	var dd: Array = L.only(tl4, "crop_damaged")
	ck("rat_gnaws_plug_from_below_3dmg_per_2s", dd.size() == 2 and L.near(float(dd[0].e.amount), 3.0) and L.near(hp_b - float(p4.crops.get_crop(plug_id).hp), 6.0), "n=%d" % dd.size())
	p4.crops.remove_crop(plug_id, "enemy")
	L.timed(p4, 0.3)
	ck("rat_emerges_when_plug_lost", L.R(p4, rat).state == "idle" and L.has_target(p4, rat), "state=%s" % L.R(p4, rat).state)

# ------------------------------------------------------------------ E27 コウモリ
func t_bat() -> void:
	var roost: Vector2 = Vector2(120.0, 54.0)   # 建物(x28..35,y14..19)の北側に隣接
	var p: RefCounted = L.mk(4)
	hero_far(p)
	var ids: Array = p.enemies.spawn_bat_flock(roost)
	ck("bat_flock_of_6_roosting_hittable", ids.size() == 6 and ids.all(func(i: int) -> bool: return L.has_target(p, i)), "")
	# 1発で1匹。当たると群れ全員が飛び立つ(飛行中は当たらない)
	var ev: Array = p.hit_enemy(ids[0], 4.0, "shot", Vector2(160, 54))
	ck("bat_one_shot_one_kill_reward_2", L.evs(ev, "enemy_defeated").size() == 1 and L.evs(ev, "reward").size() == 1 and int(L.evs(ev, "reward")[0].amount) == 2, "")
	ck("bat_hit_wakes_flock_flying_untargetable", ids.slice(1).all(func(i: int) -> bool: return L.R(p, i).state == "swarm" and not L.has_target(p, i)), "")
	# 爆風は範囲内のすべて(1匹目で飛び立っても全員に当たる)
	var p2: RefCounted = L.mk(4)
	hero_far(p2)
	var ids2: Array = p2.enemies.spawn_bat_flock(roost)
	var evb: Array = p2.splash(roost + Vector2(2, 0), 30.0, 4.0, "bazooka")
	ck("bat_bazooka_hits_all_roosting", L.evs(evb, "enemy_defeated").size() == 6 and L.evs(evb, "reward").size() == 6, "n=%d" % L.evs(evb, "enemy_defeated").size())
	# 主人公が3m以内で飛び立つ
	var p3: RefCounted = L.mk(4)
	L.hero(p3, 120.0, 90.0)
	var ids3: Array = p3.enemies.spawn_bat_flock(roost)
	L.timed(p3, 0.3)
	ck("bat_hero_beyond_3m_stays_roosting", ids3.all(func(i: int) -> bool: return L.R(p3, i).state == "roost"), "")
	L.hero(p3, 120.0, 80.0)
	L.timed(p3, 0.3)
	ck("bat_hero_within_3m_wakes", ids3.all(func(i: int) -> bool: return L.R(p3, i).state != "roost"), "")
	# 乱れ飛び: 2秒ごとに1匹が急降下(3ダメージ)。急降下と噛んだ後0.5秒は当たる。昼12秒・戻ってぶら下がる
	var dives: Array = []
	var dive_hittable: bool = false
	var low_hittable: bool = false
	var hd_times: Array = []
	var tstart: float = p3.enemies.time
	var back_at: float = -1.0
	for i: int in range(250):
		if i == 110:
			L.hero(p3, 200.0, 130.0)   # 飛行の終わり際に主人公が離れる(ぶら下がりに戻ったあと再び飛び立たないように)
		var evs3: Array = p3.advance(0.1)
		for x: Dictionary in evs3:
			if x.type == "hero_damage" and x.kind == "bat_flock" and p3.enemies.time - tstart < 11.0:
				hd_times.append(p3.enemies.time - tstart)
		for bid: int in ids3:
			var b: Dictionary = L.R(p3, bid)
			if b.is_empty():
				continue
			if b.state == "dive" and L.has_target(p3, bid):
				dive_hittable = true
			if b.state == "low" and L.has_target(p3, bid):
				low_hittable = true
		if back_at < 0.0 and ids3.all(func(i2: int) -> bool: return L.R(p3, i2).state == "roost") and p3.enemies.time - tstart > 3.0:
			back_at = p3.enemies.time - tstart
	ck("bat_dive_3dmg_every_2s", hd_times.size() >= 4 and hd_times.size() <= 6, "bites=%d times=%s" % [hd_times.size(), str(hd_times)])
	ck("bat_dive_and_low_are_hittable", dive_hittable and low_hittable, "dive=%s low=%s" % [str(dive_hittable), str(low_hittable)])
	ck("bat_day_flight_about_12s_then_roost", back_at > 11.0 and back_at < 17.0, "back@%f" % back_at)
	# 夜は24秒
	var pn: RefCounted = L.mk(4)
	pn.host.day = false
	L.hero(pn, 120.0, 80.0)
	var idn: Array = pn.enemies.spawn_bat_flock(roost)
	L.timed(pn, 0.3)
	var fu: float = float(L.R(pn, idn[0]).fly_until) - pn.enemies.time
	ck("bat_night_flight_24s_vs_day_12s", fu > 23.5 and fu < 24.01 and float(L.R(p3, ids3[0]).fly_until) - tstart < 13.0, "night_left=%f" % fu)
	# ヒカリゴケの範囲では急降下しない
	var pm: RefCounted = L.mk(4)
	L.hero(pm, 120.0, 80.0)
	L.crop(pm, "glow_moss", 30, 20)
	var idm: Array = pm.enemies.spawn_bat_flock(roost)
	var tlm: Array = L.timed(pm, 13.0)
	ck("bat_no_dive_in_glow_moss_range", L.evs(L.plain(tlm), "hero_damage").is_empty() and L.fx_of(tlm, "bat_wake").size() >= 1, "bites=%d" % L.evs(L.plain(tlm), "hero_damage").size())
	# 2匹以下は乱れ飛ばず、すぐねぐらへ戻る
	var p5: RefCounted = L.mk(4)
	L.hero(p5, 120.0, 80.0)
	var id5: Array = [L.sp(p5, "bat_flock", 118.0, 54.0, "initial", {"group_id": 77}), L.sp(p5, "bat_flock", 122.0, 54.0, "initial", {"group_id": 77})]
	var alive5: Array = L.ids_of(p5, "bat_flock")
	var swarm_seen: bool = false
	var tl5: Array = []
	for i5: int in range(80):
		tl5.append_array(p5.advance(0.1))
		for bid5: int in alive5:
			if L.R(p5, bid5).state == "swarm" or L.R(p5, bid5).state == "dive":
				swarm_seen = true
	ck("bat_last_two_do_not_swarm_return_fast", alive5.size() == 2 and not swarm_seen and L.evs(tl5, "hero_damage").is_empty(), "alive=%d" % alive5.size())
	# 飛行中は安定判定に数える
	ck("bat_counts_for_stability_while_flying", p.enemies.counts_for_stability(ids[1]), "")

