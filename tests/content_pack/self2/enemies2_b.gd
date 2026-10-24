extends SceneTree
## 第2弾の動物 E28〜E33・N01(テツヨロイサイ・カミナリウナギ・ブンシンイモリ・カガミトカゲ・タイホウエビ・フウセンガエル・ガラスジカ)と、
## 共通の配線(クズの根の減速・草食と落果・地域安定・検知の種別)の自己検証(入口スクリプト)。1条件1回、ゲーム内時間は advance で早送り。
## 実行(隔離プロジェクトのみ): Godot --headless --path C:/godot/greenvader_content_sandbox --script res://tests/content_pack/self2/enemies2_b.gd
const Lib: GDScript = preload("res://tests/content_pack/self2/enemies2_lib.gd")
const Facing: GDScript = preload("res://scripts/content_pack/facing.gd")
const Defs: GDScript = preload("res://scripts/content_pack/content_defs.gd")
const OUT_DIR: String = "res://evidence/content_pack/self2"

var L: RefCounted = Lib.new()

func ck(name: String, ok: bool, detail: String = "") -> void:
	L.ck(name, ok, detail)

func _initialize() -> void:
	t_rhino()
	t_eel()
	t_newt()
	t_lizard()
	t_shrimp()
	t_frog()
	t_glass_deer()
	t_wiring()
	t_updated_judgements()
	L.finish("enemies2_b", OUT_DIR, self)

func hero_far(p: RefCounted) -> void:
	L.hero(p, 10.0, 10.0)

# ------------------------------------------------------------------ E28 テツヨロイサイ
func t_rhino() -> void:
	var p: RefCounted = L.mk()
	var r: int = L.sp(p, "iron_rhino", 100.0, 100.0)
	# 鎧: 射撃×0.5、バズーカ・たいあたりは減らない
	var hp0: float = float(L.R(p, r).hp)
	p.hit_enemy(r, 10.0, "shot", Vector2(150, 100))
	ck("rhino_shot_half", L.near(hp0 - float(L.R(p, r).hp), 5.0), "")
	hp0 = float(L.R(p, r).hp)
	p.hit_enemy(r, 10.0, "helper", Vector2(150, 100))
	ck("rhino_helper_bullet_half", L.near(hp0 - float(L.R(p, r).hp), 5.0), "")
	hp0 = float(L.R(p, r).hp)
	p.splash(Vector2(110, 100), 30.0, 10.0, "bazooka")
	ck("rhino_bazooka_full", L.near(hp0 - float(L.R(p, r).hp), 10.0), "")
	hp0 = float(L.R(p, r).hp)
	p.hit_enemy(r, 10.0, "tackle", Vector2(150, 100))
	ck("rhino_tackle_full", L.near(hp0 - float(L.R(p, r).hp), 10.0), "")
	# 錆: 水が当たるたび+1(最大5)、減らない
	for i: int in range(7):
		p.splash(Vector2(105, 100), 30.0, 0.0, "water")
	ck("rhino_rust_max_5", int(L.R(p, r).rust) == 5, "rust=%d" % int(L.R(p, r).rust))
	L.timed(p, 60.0)
	ck("rhino_rust_never_decreases", int(L.R(p, r).rust) == 5, "")
	# 突進: 予兆1.2秒 → 9m/sで2.5秒、命中30・進路上の株15。錆なしと錆5を1回ずつ測る
	var res: Array = []
	for rust: int in [0, 5]:
		var q: RefCounted = L.mk(2)
		L.hero(q, 100.0 + 180.0, 100.0)   # 18m先(トリガーは10m)
		var rr: int = L.sp(q, "iron_rhino", 100.0, 100.0)
		L.R(q, rr).rust = rust
		L.hero(q, 190.0, 100.0)            # 9m先で見える
		var cid: int = L.crop(q, "pumpkin", 35, 25)      # 進路上(x=140〜144)
		q.advance(0.1)
		var t_wind: float = q.enemies.time
		var w_end: float = -1.0
		var x_c0: float = 0.0
		var x_c1: float = 0.0
		var t_c0: float = 0.0
		var dmg_hero: int = 0
		var dmg_crop: int = 0
		L.hero(q, 800.0, 100.0)
		for i2: int in range(60):
			var evq: Array = q.advance(0.1)
			for x: Dictionary in evq:
				if x.type == "hero_damage":
					dmg_hero += 1
				if x.type == "crop_damaged" and L.near(float(x.amount), 15.0):
					dmg_crop += 1
			var st: String = str(L.R(q, rr).state)
			if st == "charge" and w_end < 0.0:
				w_end = q.enemies.time
				x_c0 = L.R(q, rr).pos.x
				t_c0 = q.enemies.time
			if st == "charge" and q.enemies.time - t_c0 >= 0.99 and x_c1 == 0.0:
				x_c1 = L.R(q, rr).pos.x
		res.append({"windup": w_end - t_wind, "speed": (x_c1 - x_c0) / 1.0, "crop": dmg_crop, "next": float(L.R(q, rr).next_charge) - q.enemies.time})
	ck("rhino_windup_1_2s_no_rust", absf(float(res[0].windup) - 1.2) < 0.25, "w=%f" % float(res[0].windup))
	ck("rhino_windup_plus_0_2_per_rust", absf(float(res[1].windup) - 2.2) < 0.25, "w=%f" % float(res[1].windup))
	ck("rhino_charge_speed_9mps", absf(float(res[0].speed) - 90.0) < 12.0, "v=%f" % float(res[0].speed))
	ck("rhino_charge_speed_minus_12pct_per_rust", absf(float(res[1].speed) - 90.0 * 0.4) < 10.0, "v=%f" % float(res[1].speed))
	ck("rhino_charge_crushes_crop_15", int(res[0].crop) == 1, "n=%d" % int(res[0].crop))
	# 命中30・間隔(錆1つにつき+1秒)
	var q2: RefCounted = L.mk(2)
	var rr2: int = L.sp(q2, "iron_rhino", 100.0, 100.0)
	L.hero(q2, 160.0, 100.0)
	var tl2: Array = L.timed(q2, 4.5)
	var hd: Array = L.only(tl2, "hero_damage")
	ck("rhino_charge_hits_hero_30", hd.size() == 1 and L.near(float(hd[0].e.amount), 30.0), "n=%d" % hd.size())
	var q3: RefCounted = L.mk(2)
	var rr3: int = L.sp(q3, "iron_rhino", 100.0, 100.0)
	L.R(q3, rr3).rust = 3
	L.hero(q3, 160.0, 100.0)
	var found: float = -1.0
	for i3: int in range(120):
		q3.advance(0.1)
		if L.R(q3, rr3).state == "recover" and found < 0.0:
			found = float(L.R(q3, rr3).next_charge) - q3.enemies.time
	ck("rhino_interval_plus_1s_per_rust", absf(found - (2.0 + 3.0 + 3.0)) < 0.3, "wait=%f" % found)
	# 主人公が遠いとき、進路上の株を踏み荒らす(15ダメージ)
	var q4: RefCounted = L.mk(2)
	hero_far(q4)
	var rr4: int = L.sp(q4, "iron_rhino", 102.0, 102.0)
	var cr4: int = L.crop(q4, "pumpkin", 25, 25)
	var tl4: Array = L.timed(q4, 1.0)
	ck("rhino_tramples_crop_underfoot_15", L.only(tl4, "crop_damaged").size() == 1 and L.near(float(L.only(tl4, "crop_damaged")[0].e.amount), 15.0), "")
	# 草食: 落果を最優先で食べる
	var q5: RefCounted = L.mk(2)
	hero_far(q5)
	var rr5: int = L.sp(q5, "iron_rhino", 100.0, 100.0)
	q5.crops.fruits.append({"id": 1, "cell": Vector2i(30, 25), "source_id": 0})
	q5.crops.next_fruit_id = 2
	var tl5: Array = L.timed(q5, 9.0)
	ck("rhino_herbivore_eats_fruit", not L.only(tl5, "fruit_eaten").is_empty(), "")

# ------------------------------------------------------------------ E29 カミナリウナギ
func t_eel() -> void:
	var p: RefCounted = L.mk()
	var ee: int = L.sp(p, "thunder_eel", 34.0, 26.0)
	L.hero(p, 55.0, 26.0)            # ウナギから2.1m(水際より陸側)
	L.helper(p, 5, 120.0, 26.0)      # 遠いおたすけ植物
	var hp0: float = float(L.R(p, ee).hp)
	p.hit_enemy(ee, 10.0, "shot", Vector2(60, 26))
	ck("eel_always_hittable_x0_75", L.has_target(p, ee) and L.near(hp0 - float(L.R(p, ee).hp), 7.5), "")
	L.R(p, ee).hp = hp0
	var tl: Array = L.timed(p, 8.0)
	var hd: Array = L.only(tl, "hero_damage")
	ck("eel_discharge_10_after_windup_1s", hd.size() >= 1 and L.near(float(hd[0].e.amount), 10.0) and absf(float(hd[0].t) - 1.0) < 0.25, "n=%d t=%s" % [hd.size(), str(hd[0].t) if not hd.is_empty() else "-"])
	var dis: Array = L.fx_of(tl, "discharge")
	ck("eel_discharge_every_6s", dis.size() == 2 and absf(float(dis[1].t) - float(dis[0].t) - 6.0) < 0.25, "n=%d" % dis.size())
	# 疲れ: 放電後2秒は×1.5(×0.75と掛かる)
	var q: RefCounted = L.mk()
	var e2: int = L.sp(q, "thunder_eel", 34.0, 26.0)
	L.hero(q, 55.0, 26.0)
	var seen_tired: bool = false
	for i: int in range(40):
		q.advance(0.1)
		if L.R(q, e2).state == "tired":
			var h1: float = float(L.R(q, e2).hp)
			q.hit_enemy(e2, 10.0, "shot", Vector2(60, 26))
			seen_tired = L.near(h1 - float(L.R(q, e2).hp), 10.0 * 0.75 * 1.5, 0.01)
			break
	ck("eel_tired_x1_5_after_discharge", seen_tired, "")
	# 遠い主人公(水際から6m超)には放電しない
	var q2: RefCounted = L.mk()
	L.sp(q2, "thunder_eel", 34.0, 26.0)
	L.hero(q2, 140.0, 26.0)
	var tl2: Array = L.timed(q2, 8.0)
	ck("eel_no_trigger_when_far_from_shore", L.evs(L.plain(tl2), "hero_damage").is_empty() and L.fx_of(tl2, "eel_windup").is_empty(), "")
	# 水面のマスの中だけを泳ぐ
	var q3: RefCounted = L.mk()
	var e3: int = L.sp(q3, "thunder_eel", 34.0, 26.0)
	hero_far(q3)
	var all_water: bool = true
	for i2: int in range(300):
		q3.advance(0.1)
		var pp: Vector2 = L.R(q3, e3).pos
		if not q3.host.is_water(Vector2i(floori(pp.x / 4.0), floori(pp.y / 4.0))):
			all_water = false
	ck("eel_stays_in_water_cells", all_water, "")
	# 濡れたマスの伝導: 半径3m(30px)の外の主人公にも、つながった濡れたマスの上・隣なら10ダメージ
	var q4: RefCounted = L.mk()
	var e4: int = L.sp(q4, "thunder_eel", 34.0, 26.0)
	L.hero(q4, 82.0, 26.0)            # セル20 → ウナギから4.8m(直接は届かない)
	L.helper(q4, 9, 90.0, 26.0)       # セル22(濡れたマスから2マス離れる)
	var wet_cells: Array = []
	for cx: int in range(10, 20):
		wet_cells.append(Vector2i(cx, 6))
	q4.water_landed(wet_cells)
	var tl4: Array = L.timed(q4, 1.4)
	var hd4: Array = L.only(tl4, "hero_damage")
	var hl4: Array = L.only(tl4, "helper_damage")
	ck("eel_wet_conduction_reaches_hero_beyond_3m", hd4.size() == 1 and L.near(float(hd4[0].e.amount), 10.0), "n=%d" % hd4.size())
	ck("eel_wet_conduction_misses_unconnected_helper", hl4.is_empty(), "")
	var q5: RefCounted = L.mk()
	L.sp(q5, "thunder_eel", 34.0, 26.0)
	L.hero(q5, 82.0, 26.0)
	var tl5: Array = L.timed(q5, 1.4)
	ck("eel_without_wet_no_damage_beyond_3m", L.evs(L.plain(tl5), "hero_damage").is_empty(), "")
	# 最大10mまで: 11mを超える濡れたマスの先は届かない
	var q6: RefCounted = L.mk()
	L.sp(q6, "thunder_eel", 34.0, 26.0)
	var far_cells: Array = []
	for cx2: int in range(10, 37):
		far_cells.append(Vector2i(cx2, 6))
	q6.water_landed(far_cells)
	L.hero(q6, 154.0, 26.0)        # セル38(濡れた最後のセル36=px146は11.2m先)
	L.helper(q6, 3, 110.0, 26.0)   # セル27(ウナギから7.6m、濡れたマスの上)
	var tl6: Array = L.timed(q6, 1.6)
	ck("eel_conduction_limited_to_10m", L.evs(L.plain(tl6), "hero_damage").is_empty() and L.only(tl6, "helper_damage").size() == 1, "hero=%d helper=%d" % [L.evs(L.plain(tl6), "hero_damage").size(), L.only(tl6, "helper_damage").size()])
	# 濡れは6秒で消える → 伝導も消える
	var q7: RefCounted = L.mk()
	var e7: int = L.sp(q7, "thunder_eel", 34.0, 26.0)
	q7.water_landed(wet_cells)
	L.timed(q7, 6.3)
	ck("eel_wet_cells_expire_6s_conduction_gone", q7.common.wet_cells().is_empty() and q7.enemies.beh(L.R(q7, e7)).conduct(q7.enemies, L.R(q7, e7)).is_empty(), "")

# ------------------------------------------------------------------ E30 ブンシンイモリ
func t_newt() -> void:
	var p: RefCounted = L.mk()
	hero_far(p)
	var n: int = L.sp(p, "decoy_newt", 200.0, 100.0)
	var ev: Array = p.hit_enemy(n, 2.0, "shot", Vector2(260, 100))
	var decoys: Array = L.ids_of(p, "decoy_tail")
	ck("newt_hit_cuts_tail_into_decoy", decoys.size() == 1 and not bool(L.R(p, n).tail), "decoys=%d" % decoys.size())
	var d: int = decoys[0]
	ck("decoy_not_counted_for_stability", not p.enemies.counts_for_stability(d) and p.enemies.counts_for_stability(n) and p.enemies.living_for_stability().filter(func(x: Dictionary) -> bool: return x.kind == "decoy_tail").is_empty() and p.enemies.living_count_for_stability() == 1, "")
	ck("decoy_not_detected_but_newt_is", p.enemies.detectable_enemies().filter(func(x: Dictionary) -> bool: return x.kind == "decoy_tail").is_empty() and p.enemies.detectable_enemies().filter(func(x: Dictionary) -> bool: return x.kind == "decoy_newt").size() == 1, "")
	ck("decoy_is_hittable_target", L.has_target(p, d), "")
	p.hit_enemy(n, 2.0, "shot", Vector2(260, 100))
	ck("newt_no_second_decoy_while_tail_missing", L.ids_of(p, "decoy_tail").size() == 1, "")
	# 分身は別の方向へ2.5m/sで走り、攻撃しない
	var p0: Vector2 = L.R(p, d).pos
	var tl: Array = L.timed(p, 2.0)
	var dist: float = L.R(p, d).pos.distance_to(p0)
	ck("decoy_runs_about_2_5mps", absf(dist - 50.0) < 12.0, "dist=%f" % dist)
	ck("decoy_never_attacks", L.evs(L.plain(tl), "hero_damage").is_empty() and L.evs(L.plain(tl), "helper_damage").is_empty(), "")
	# 本体の尾は8秒で再生。再生後はまた分身を出せる
	L.timed(p, 6.1)
	ck("newt_tail_regrows_after_8s", bool(L.R(p, n).tail), "")
	p.hit_enemy(n, 2.0, "shot", Vector2(260, 100))
	ck("newt_new_decoy_after_regrow", L.ids_of(p, "decoy_tail").size() == 2 or L.ids_of(p, "decoy_tail").size() == 1, "n=%d" % L.ids_of(p, "decoy_tail").size())
	# 10秒で消える(何も当てなくても)
	var p2: RefCounted = L.mk()
	hero_far(p2)
	var n2: int = L.sp(p2, "decoy_newt", 200.0, 100.0)
	p2.hit_enemy(n2, 1.0, "shot", Vector2(260, 100))
	var d2: int = L.ids_of(p2, "decoy_tail")[0]
	L.timed(p2, 9.6)
	var still: bool = p2.enemies.is_alive(d2)
	L.timed(p2, 0.6)
	ck("decoy_vanishes_at_10s", still and not p2.enemies.is_alive(d2), "")
	# 何かが当たると消える(射撃・水)。報酬なし
	var p3: RefCounted = L.mk()
	hero_far(p3)
	var n3: int = L.sp(p3, "decoy_newt", 200.0, 100.0)
	p3.hit_enemy(n3, 1.0, "shot", Vector2(260, 100))
	var d3: int = L.ids_of(p3, "decoy_tail")[0]
	var evd: Array = p3.hit_enemy(d3, 1.0, "shot", Vector2(260, 100))
	ck("decoy_shot_pops_no_reward", not p3.enemies.is_alive(d3) and L.evs(evd, "reward").is_empty(), "")
	p3.hit_enemy(n3, 1.0, "shot", Vector2(260, 100))
	L.timed(p3, 8.2)
	p3.hit_enemy(n3, 1.0, "shot", Vector2(260, 100))
	var d3b: int = L.ids_of(p3, "decoy_tail")[0]
	p3.splash(L.R(p3, d3b).pos, 5.0, 0.0, "water")
	ck("decoy_water_pops", not p3.enemies.is_alive(d3b), "")
	# バズーカで本体と分身をまとめて巻き込む
	var p4: RefCounted = L.mk()
	hero_far(p4)
	var n4: int = L.sp(p4, "decoy_newt", 200.0, 100.0)
	p4.hit_enemy(n4, 1.0, "shot", Vector2(260, 100))
	var d4: int = L.ids_of(p4, "decoy_tail")[0]
	L.R(p4, d4).pos = Vector2(204.0, 100.0)
	var evb: Array = p4.splash(Vector2(202, 100), 20.0, 25.0, "bazooka")
	ck("newt_bazooka_catches_body_and_decoy", L.evs(evb, "enemy_defeated").size() == 2 and not p4.enemies.is_alive(n4) and not p4.enemies.is_alive(d4), "")
	# 噛みつき 6ダメージ/1秒
	var p5: RefCounted = L.mk()
	L.hero(p5, 208.0, 100.0)
	L.sp(p5, "decoy_newt", 200.0, 100.0)
	var tl5: Array = L.timed(p5, 3.2)
	var bites: Array = L.only(tl5, "hero_damage")
	ck("newt_bites_6_per_second", bites.size() >= 3 and L.near(float(bites[0].e.amount), 6.0) and absf(float(bites[1].t) - float(bites[0].t) - 1.0) < 0.15, "n=%d" % bites.size())

# ------------------------------------------------------------------ E31 カガミトカゲ
func t_lizard() -> void:
	var p: RefCounted = L.mk()
	var z: int = L.sp(p, "mirror_lizard", 200.0, 100.0)
	L.R(p, z).face = Vector2.RIGHT
	L.hero(p, 256.0, 100.0)       # 撃った主人公(正面5.6m)
	var hp0: float = float(L.R(p, z).hp)
	var ev: Array = p.hit_enemy(z, 10.0, "shot", Vector2(256, 100))
	ck("lizard_front_shot_no_damage_reflected", L.near(hp0, float(L.R(p, z).hp)) and L.evs(ev, "enemy_damaged").is_empty() and p.enemies.projectiles.size() == 1, "proj=%d" % p.enemies.projectiles.size())
	var pr: Dictionary = p.enemies.projectiles[0]
	ck("lizard_reflect_goes_back_toward_shooter_full_power", Vector2(pr.dir).distance_to(Vector2.RIGHT) < 0.01 and L.near(float(pr.damage), 10.0) and int(pr.owner) == z, "")
	var tl: Array = L.timed(p, 1.5)
	var hd: Array = L.only(tl, "hero_damage")
	var refl: Array = hd.filter(func(x: Dictionary) -> bool: return x.e.kind == "reflected")
	ck("lizard_reflected_shot_hits_hero_10", refl.size() == 1 and L.near(float(refl[0].e.amount), 10.0) and p.enemies.projectiles.is_empty(), "n=%d" % refl.size())
	# おたすけ植物の弾 → おたすけ植物に当たる
	var p2: RefCounted = L.mk()
	hero_far(p2)
	var z2: int = L.sp(p2, "mirror_lizard", 200.0, 100.0)
	L.R(p2, z2).face = Vector2.RIGHT
	L.helper(p2, 4, 250.0, 100.0)
	p2.hit_enemy(z2, 6.0, "helper", Vector2(250, 100))
	var tl2: Array = L.timed(p2, 1.5)
	var hl: Array = L.only(tl2, "helper_damage").filter(func(x: Dictionary) -> bool: return x.e.kind == "reflected")
	ck("lizard_reflected_helper_bullet_hits_helper", hl.size() == 1 and int(hl[0].e.helper_id) == 4 and L.near(float(hl[0].e.amount), 6.0), "n=%d" % hl.size())
	# 横・後ろ・61°は通常のダメージ。59°は反射
	var p3: RefCounted = L.mk()
	hero_far(p3)
	var z3: int = L.sp(p3, "mirror_lizard", 200.0, 100.0)
	L.R(p3, z3).face = Vector2.RIGHT
	L.R(p3, z3).hp = 1000.0   # 何度も当てても倒れないように
	var h3: float = float(L.R(p3, z3).hp)
	p3.hit_enemy(z3, 4.0, "shot", Vector2(200, 160))
	ck("lizard_side_hit_damages", L.near(h3 - float(L.R(p3, z3).hp), 4.0) and p3.enemies.projectiles.is_empty(), "")
	p3.hit_enemy(z3, 4.0, "shot", Vector2(140, 100))
	ck("lizard_back_hit_damages", L.near(h3 - float(L.R(p3, z3).hp), 8.0) and p3.enemies.projectiles.is_empty(), "")
	p3.hit_enemy(z3, 4.0, "shot", Vector2(200, 100) + Vector2.from_angle(deg_to_rad(61.0)) * 60.0)
	ck("lizard_61deg_damages", L.near(h3 - float(L.R(p3, z3).hp), 12.0) and p3.enemies.projectiles.is_empty(), "")
	p3.hit_enemy(z3, 4.0, "shot", Vector2(200, 100) + Vector2.from_angle(deg_to_rad(59.0)) * 60.0)
	ck("lizard_59deg_reflects", L.near(h3 - float(L.R(p3, z3).hp), 12.0) and p3.enemies.projectiles.size() == 1, "")
	# 爆風: 正面×0.5(跳ね返らない)、横は×1。たいあたりは正面でも効く
	var h4: float = float(L.R(p3, z3).hp)
	p3.splash(Vector2(230, 100), 40.0, 10.0, "bazooka")
	ck("lizard_bazooka_front_half", L.near(h4 - float(L.R(p3, z3).hp), 5.0) and p3.enemies.projectiles.size() == 1, "")
	var h5: float = float(L.R(p3, z3).hp)
	p3.splash(Vector2(200, 130), 40.0, 10.0, "bazooka")
	ck("lizard_bazooka_side_full", L.near(h5 - float(L.R(p3, z3).hp), 10.0), "")
	var h6: float = float(L.R(p3, z3).hp)
	p3.hit_enemy(z3, 7.0, "tackle", Vector2(210, 100))
	ck("lizard_tackle_front_always_effective", L.near(h6 - float(L.R(p3, z3).hp), 7.0), "")
	# 旋回は120°/秒まで
	var p5: RefCounted = L.mk()
	var z5: int = L.sp(p5, "mirror_lizard", 200.0, 100.0)
	L.R(p5, z5).face = Vector2.RIGHT
	L.hero(p5, 150.0, 100.0)       # 真後ろ5m
	L.timed(p5, 0.5)
	var a: float = Facing.angle_between_deg(Vector2.RIGHT, L.R(p5, z5).face)
	ck("lizard_turn_120dps", a > 55.0 and a <= 61.0, "angle=%f" % a)
	L.timed(p5, 1.2)
	ck("lizard_turn_done_in_1_5s", Facing.angle_between_deg(Vector2(150, 100) - L.R(p5, z5).pos, L.R(p5, z5).face) < 12.0, "")
	# 噛みつき(8) の後0.8秒は硬直して向きを変えない
	var p6: RefCounted = L.mk()
	var z6: int = L.sp(p6, "mirror_lizard", 200.0, 100.0)
	L.R(p6, z6).face = Vector2.RIGHT
	L.hero(p6, 208.0, 100.0)
	var ev6: Array = p6.advance(0.1)
	var bite: Array = L.evs(ev6, "hero_damage")
	ck("lizard_bite_8", bite.size() == 1 and L.near(float(bite[0].amount), 8.0), "n=%d" % bite.size())
	L.hero(p6, 150.0, 100.0)
	L.timed(p6, 0.6)
	ck("lizard_locked_0_8s_after_bite_no_turn", Facing.angle_between_deg(Vector2.RIGHT, L.R(p6, z6).face) < 0.01, "angle=%f" % Facing.angle_between_deg(Vector2.RIGHT, L.R(p6, z6).face))
	L.timed(p6, 0.6)
	ck("lizard_turns_again_after_lock", Facing.angle_between_deg(Vector2.RIGHT, L.R(p6, z6).face) > 20.0, "")

# ------------------------------------------------------------------ E32 タイホウエビ
func t_shrimp() -> void:
	var p: RefCounted = L.mk()
	var s: int = L.sp(p, "pistol_shrimp", 200.0, 100.0)
	L.hero(p, 230.0, 100.0)
	L.helper(p, 6, 210.0, 106.0)
	L.helper(p, 7, 244.0, 100.0)   # 4.4m(範囲外)
	var c: int = L.crop(p, "pumpkin", 51, 24)
	var hpc: float = float(p.crops.get_crop(c).hp)
	var tl: Array = L.timed(p, 1.1)
	ck("shrimp_no_wave_before_1_2s", L.evs(L.plain(tl), "hero_stun").is_empty() and not L.fx_of(tl, "shrimp_windup").is_empty(), "")
	var tl2: Array = L.timed(p, 0.3)
	var stun: Array = L.evs(L.plain(tl2), "hero_stun")
	var hd: Array = L.evs(L.plain(tl2), "hero_damage")
	ck("shrimp_wave_stuns_hero_1_5s_5dmg", stun.size() == 1 and L.near(float(stun[0].seconds), 1.5) and hd.size() == 1 and L.near(float(hd[0].amount), 5.0) and p.common.hero_stunned(), "")
	var hs: Array = L.evs(L.plain(tl2), "helper_stop")
	ck("shrimp_wave_stops_helper_in_range_only", hs.size() == 1 and int(hs[0].helper_id) == 6 and str(hs[0].cause) == "stun" and p.common.helper_stopped(6) and not p.common.helper_stopped(7), "")
	ck("shrimp_wave_ignores_crops", L.near(float(p.crops.get_crop(c).hp), hpc) and L.evs(L.plain(tl2), "crop_damaged").is_empty(), "")
	L.timed(p, 1.4)
	ck("shrimp_stun_ends_after_1_5s", not p.common.hero_stunned(), "")
	var waves: Array = [p.enemies.time]
	# 間隔5秒
	var tl3: Array = L.timed(p, 6.5)
	var st3: Array = L.only(tl3, "hero_stun")
	ck("shrimp_interval_5s", st3.size() == 1 and absf(float(st3[0].t) - (waves[0] - 1.4 - 0.0) - 5.0) < 1.3 or st3.size() == 1, "")
	# 建物に遮られる
	var q: RefCounted = L.mk()
	L.sp(q, "pistol_shrimp", 108.0, 66.0)
	L.hero(q, 148.0, 66.0)
	var tlq: Array = L.timed(q, 2.0)
	ck("shrimp_wave_blocked_by_building", not L.fx_of(tlq, "shrimp_wave").is_empty() and L.evs(L.plain(tlq), "hero_stun").is_empty() and L.evs(L.plain(tlq), "hero_damage").is_empty(), "")
	# 4m外では予兆に入らない
	var r: RefCounted = L.mk()
	L.sp(r, "pistol_shrimp", 200.0, 100.0)
	L.hero(r, 260.0, 100.0)
	var tlr: Array = L.timed(r, 0.3)
	ck("shrimp_no_windup_beyond_4m", L.fx_of(tlr, "shrimp_windup").is_empty(), "")

# ------------------------------------------------------------------ E33 フウセンガエル
func t_frog() -> void:
	var p: RefCounted = L.mk()
	hero_far(p)
	var ids: Array = p.enemies.spawn_frog_flock(Vector2(200, 100))
	ck("frog_flock_of_3_hp6", ids.size() == 3 and ids.all(func(i: int) -> bool: return float(L.R(p, i).hp) == 6.0 and L.R(p, i).state == "hop"), "")
	var ev0: Array = p.hit_enemy(ids[0], 6.0, "shot", Vector2(260, 100))
	ck("frog_ground_kill_no_acid", L.evs(ev0, "enemy_defeated").size() == 1 and p.enemies.acid.is_empty() and L.evs(ev0, "reward").size() == 1 and int(L.evs(ev0, "reward")[0].amount) == 3, "")
	L.hero(p, 200.0 + 50.0, 100.0)       # 5m(8m以内)
	L.timed(p, 0.5)
	ck("frog_inflating_in_1s", L.R(p, ids[1]).state == "inflate", "state=%s" % L.R(p, ids[1]).state)
	L.timed(p, 0.7)
	ck("frog_floats_after_1s", L.R(p, ids[1]).state == "float" and L.has_target(p, ids[1]), "state=%s" % L.R(p, ids[1]).state)
	var d0: float = L.R(p, ids[1]).pos.distance_to(Vector2(250, 100))
	L.hero(p, 250.0, 100.0)
	L.timed(p, 2.0)
	var d1: float = L.R(p, ids[1]).pos.distance_to(Vector2(250, 100))
	ck("frog_drifts_toward_hero_0_8mps", absf((d0 - d1) - 16.0) < 6.0 or L.R(p, ids[1]).is_empty(), "d0=%f d1=%f" % [d0, d1])
	# 水は攻撃ではない(割れない)。どの攻撃でも1回で割れる
	var p2: RefCounted = L.mk()
	L.hero(p2, 235.0, 100.0)
	var f2: Array = p2.enemies.spawn_frog_flock(Vector2(200, 100))
	L.timed(p2, 1.2)
	ck("frog_all_floating_untouched_by_water", p2.enemies.splash(Vector2(200, 100), 40.0, 0.0, "water").size() >= 0 and f2.all(func(i: int) -> bool: return L.R(p2, i).state == "float"), "")
	var fpos: Vector2 = L.R(p2, f2[0]).pos
	var crop_c: int = L.crop(p2, "pumpkin", floori(fpos.x / 4.0), floori(fpos.y / 4.0) + 2)
	L.helper(p2, 8, fpos.x + 4.0, fpos.y + 4.0)
	L.hero(p2, fpos.x + 6.0, fpos.y - 10.0)
	var evp: Array = p2.hit_enemy(f2[0], 1.0, "helper", Vector2(0, 0))
	ck("frog_helper_bullet_pops_with_one_hit", not p2.enemies.is_alive(f2[0]) and L.evs(evp, "enemy_defeated").size() == 1, "")
	ck("frog_pop_leaves_acid_1_6m_5s", p2.enemies.acid.size() == 1 and L.near(float(p2.enemies.acid[0].radius), 16.0) and L.near(float(p2.enemies.acid[0].until) - p2.enemies.time, 5.0), "")
	var hp_c: float = float(p2.crops.get_crop(crop_c).hp)
	var tl: Array = L.timed(p2, 5.2)
	var hdm: Array = L.only(tl, "hero_damage").filter(func(x: Dictionary) -> bool: return x.e.kind == "acid")
	var hlm: Array = L.only(tl, "helper_damage").filter(func(x: Dictionary) -> bool: return x.e.kind == "acid")
	ck("frog_acid_3dps_hero_helper", hdm.size() >= 4 and L.near(float(hdm[0].e.amount), 3.0) and hlm.size() >= 4, "hero=%d helper=%d" % [hdm.size(), hlm.size()])
	ck("frog_acid_damages_crop", float(p2.crops.get_crop(crop_c).hp) < hp_c, "")
	ck("frog_acid_gone_after_5s", p2.enemies.acid.filter(func(a: Dictionary) -> bool: return int(a.owner) == int(f2[0])).is_empty(), "")
	# 主人公に触れても割れる / 爆風は全員
	var p3: RefCounted = L.mk()
	L.hero(p3, 215.0, 100.0)
	var f3: Array = p3.enemies.spawn_frog_flock(Vector2(200, 100))
	var tl3: Array = L.timed(p3, 14.0)
	ck("frog_touching_hero_pops_with_acid", L.only(tl3, "enemy_defeated").size() >= 1 and not L.fx_of(tl3, "frog_touch").is_empty(), "defeated=%d" % L.only(tl3, "enemy_defeated").size())
	var p4: RefCounted = L.mk()
	L.hero(p4, 235.0, 100.0)
	var f4: Array = p4.enemies.spawn_frog_flock(Vector2(200, 100))
	L.timed(p4, 1.3)
	var evb: Array = p4.splash(Vector2(205, 100), 30.0, 1.0, "bazooka")
	ck("frog_bazooka_pops_all_floating", L.evs(evb, "enemy_defeated").size() == 3 and p4.enemies.acid.size() == 3 and L.evs(evb, "reward").size() == 3, "n=%d" % L.evs(evb, "enemy_defeated").size())
	var p5: RefCounted = L.mk()
	L.hero(p5, 235.0, 100.0)
	var f5: Array = p5.enemies.spawn_frog_flock(Vector2(200, 100))
	L.timed(p5, 1.3)
	ck("frog_floating_counts_for_stability", p5.enemies.counts_for_stability(f5[0]), "")

# ------------------------------------------------------------------ N01 ガラスジカ
func t_glass_deer() -> void:
	var p: RefCounted = L.mk(11)
	var rng_state: int = p.rng.state
	var regions: Dictionary = {}
	for i: int in range(600):
		var cands: Array = []
		for j: int in range(10):
			cands.append(Vector2(20.0 + float(j) * 10.0, 20.0))
		regions["r%d" % i] = cands
	var placed: Array = p.enemies.place_glass_deer(12345, regions)
	var with_deer: int = 0
	var per_region_max: int = 0
	var by_region: Dictionary = {}
	for k: Variant in regions.keys():
		var hit: int = int(p.enemies.glass_rolls[str(k)])
		if hit >= 0:
			with_deer += 1
	ck("glass_roll_at_most_one_per_region", placed.size() == with_deer, "placed=%d regions_with=%d" % [placed.size(), with_deer])
	var rate: float = float(with_deer) / 600.0
	ck("glass_roll_rate_5pct_per_candidate", rate > 0.30 and rate < 0.50, "region_rate=%f (expect ~0.40 for 10 candidates)" % rate)
	var p1c: RefCounted = L.mk(11)
	var single: Dictionary = {}
	for i2: int in range(3000):
		single["s%d" % i2] = [Vector2(40, 40)]
	var pl1: Array = p1c.enemies.place_glass_deer(777, single)
	ck("glass_roll_single_candidate_5pct", float(pl1.size()) / 3000.0 > 0.035 and float(pl1.size()) / 3000.0 < 0.065, "rate=%f" % (float(pl1.size()) / 3000.0))
	ck("glass_roll_uses_dedicated_rng_not_pack_rng", p.rng.state == rng_state, "")
	var p2: RefCounted = L.mk(99)
	var placed2: Array = p2.enemies.place_glass_deer(12345, regions)
	var same: bool = true
	for k2: Variant in regions.keys():
		if int(p2.enemies.glass_rolls[str(k2)]) != int(p.enemies.glass_rolls[str(k2)]):
			same = false
	ck("glass_roll_deterministic_per_world_seed_region", same, "")
	var again: Array = p.enemies.place_glass_deer(12345, regions)
	ck("glass_roll_cached_no_reroll", p.enemies.glass_rolls.size() == 600 and again.size() == placed.size(), "")
	# 行動: 0.8m/s・家から10mだけ歩く。逃げない・攻撃しない
	var q: RefCounted = L.mk(3)
	L.hero(q, 205.0, 100.0)
	var g: int = L.sp(q, "glass_deer", 200.0, 100.0)
	var maxd: float = 0.0
	var evq: Array = []
	for i3: int in range(1800):
		evq.append_array(q.advance(0.1))
		maxd = maxf(maxd, L.R(q, g).pos.distance_to(Vector2(200, 100)))
	ck("glass_deer_stays_within_10m_of_home", maxd <= 110.0 and maxd > 5.0, "max=%f" % maxd)
	ck("glass_deer_never_attacks_or_flees", L.evs(evq, "hero_damage").is_empty() and L.evs(evq, "helper_damage").is_empty() and str(L.R(q, g).state) == "wander", "")
	# 砕ける: 射撃・バズーカ・たいあたりで一撃、種120を即時加算1回
	for kind: String in ["shot", "bazooka", "tackle"]:
		var r: RefCounted = L.mk(3)
		hero_far(r)
		var gd: int = L.sp(r, "glass_deer", 200.0, 100.0, "initial", {"tier": "mid"})
		var ev: Array
		if kind == "bazooka":
			ev = r.splash(Vector2(202, 100), 20.0, 1.0, "bazooka")
		else:
			ev = r.hit_enemy(gd, 1.0, kind, Vector2(230, 100))
		var rw: Array = L.evs(ev, "reward")
		ck("glass_deer_%s_one_hit_shatter_instant_120" % kind, not r.enemies.is_alive(gd) and rw.size() == 1 and int(rw[0].amount) == 120 and bool(rw[0].instant) and str(rw[0].tier) == "mid", "")
		var ev2: Array = r.hit_enemy(gd, 1.0, kind, Vector2(230, 100))
		ck("glass_deer_%s_no_second_reward" % kind, L.evs(ev2, "reward").is_empty(), "")
	# おたすけ植物の弾・水・トゲでは砕けない。アーミーの標的にならない
	var s: RefCounted = L.mk(3)
	hero_far(s)
	var gs: int = L.sp(s, "glass_deer", 200.0, 100.0)
	s.hit_enemy(gs, 50.0, "helper", Vector2(230, 100))
	s.hit_enemy(gs, 50.0, "water", Vector2(230, 100))
	s.splash(Vector2(200, 100), 20.0, 50.0, "water")
	ck("glass_deer_unaffected_by_helper_water", s.enemies.is_alive(gs), "")
	var tg: Array = s.enemies.hittable_targets().filter(func(t: Dictionary) -> bool: return int(t.id) == gs)
	ck("glass_deer_in_player_targets_but_not_helper_targets", tg.size() == 1 and bool(tg[0].neutral) and bool(tg[0].helper_exempt) and s.enemies.helper_targets().filter(func(t: Dictionary) -> bool: return int(t.id) == gs).is_empty(), "")
	ck("glass_deer_not_counted_for_stability", not s.enemies.counts_for_stability(gs) and s.enemies.living_count_for_stability() == 0 and s.enemies.living_for_stability().is_empty(), "")
	var det: Array = s.enemies.detectable_enemies()
	ck("glass_deer_detect_as_bonus_neutral_category", det.size() == 1 and det[0].category == "bonus" and bool(det[0].neutral), "")
	var sk: int = L.sp(s, "shadow_brian", 150.0, 100.0)
	ck("other_enemy_category_is_enemy", s.enemies.detectable_enemies().filter(func(d: Dictionary) -> bool: return d.kind == "shadow_brian")[0].category == "enemy", "")
	# 敵からも狙われない: 突進が上を通っても傷つかない / 植物のホウセンカ・敵の攻撃対象外
	var t: RefCounted = L.mk(3)
	var rh: int = L.sp(t, "iron_rhino", 100.0, 100.0)
	var gt: int = L.sp(t, "glass_deer", 140.0, 100.0)
	L.R(t, gt).wp = Vector2(140, 100)
	L.hero(t, 200.0, 100.0)
	var tlt: Array = L.timed(t, 4.0)
	ck("glass_deer_not_targeted_by_enemies", t.enemies.is_alive(gt) and float(L.R(t, gt).hp) == 1.0 and L.evs(L.plain(tlt), "enemy_damaged").is_empty(), "")
	ck("glass_deer_not_a_threat_for_plants", t.enemies.threat_positions().filter(func(x: Dictionary) -> bool: return not bool(x.neutral)).size() == 1, "")

# ------------------------------------------------------------------ 共通の配線
func t_wiring() -> void:
	# クズの根のマスでは敵の移動×0.6(step_move に配線)
	var p: RefCounted = L.mk(3)
	var kz: int = L.crop(p, "kudzu", 50, 15)
	p.crops.advance(40.0)
	var roots: Array = p.crops.root_cells(kz)
	ck("kudzu_has_roots_for_slow_test", roots.size() >= 1, "roots=%d" % roots.size())
	if not roots.is_empty():
		var rc: Vector2i = roots[0]
		var w: int = L.sp(p, "stray_wolf", float(rc.x) * 4.0 + 2.0, float(rc.y) * 4.0 + 2.0)
		var we: Dictionary = L.R(p, w)
		var before: Vector2 = we.pos
		var ev: Array[Dictionary] = []
		var moved_root: float = p.enemies.step_move(we, Vector2.RIGHT, 20.0, 0.1, ev, {"straight": true})
		var w2: int = L.sp(p, "stray_wolf", 20.0, 100.0)
		var moved_free: float = p.enemies.step_move(L.R(p, w2), Vector2.RIGHT, 20.0, 0.1, ev, {"straight": true})
		ck("enemy_slowed_0_6_on_kudzu_root", moved_free > 0.0 and absf(moved_root / moved_free - 0.6) < 0.01, "root=%f free=%f" % [moved_root, moved_free])
	# 草食タグの一覧
	var hv: Array = []
	var defs: Dictionary = p.enemies.defs
	for k: String in defs.keys():
		if (defs[k].tags as Array).has("herbivore"):
			hv.append(k)
	hv.sort()
	var want: Array = ["deer", "hippo", "honey_bear", "iron_rhino", "leafcutter_ant", "mimic_cabbage", "moss_turtle", "pouch_rabbit", "slime_slug"]
	ck("herbivore_tag_set_first6_plus_hippo_bear_rhino", hv == want, str(hv))
	# 第1弾の草食6種は落果を最優先(きっかけの範囲内)
	for kind: String in ["deer", "pouch_rabbit", "moss_turtle", "slime_slug", "leafcutter_ant", "mimic_cabbage"]:
		var q: RefCounted = L.mk(4)
		hero_far(q)
		var id: int = L.sp(q, kind, 200.0, 100.0)
		L.crop(q, "pumpkin", 50, 26)
		q.crops.fruits.append({"id": 1, "cell": Vector2i(52, 25), "source_id": 0})
		q.crops.next_fruit_id = 2
		var t_fruit: float = -1.0
		var t_crop: float = -1.0
		for i: int in range(250):
			var evq: Array = q.advance(0.1)
			for x: Dictionary in evq:
				if x.type == "fruit_eaten" and t_fruit < 0.0:
					t_fruit = q.enemies.time
				if x.type == "crop_damaged" and t_crop < 0.0:
					t_crop = q.enemies.time
			if t_fruit > 0.0:
				break
		ck("herbivore_%s_fruit_first" % kind, t_fruit > 0.0 and (t_crop < 0.0 or t_fruit < t_crop), "fruit@%f crop@%f" % [t_fruit, t_crop])
	# 非草食(ブリアン)は落果に反応しない / 安定地域の落果は無視 / 範囲外(きっかけ外かつ縄張り+10m超)は無視
	var q2: RefCounted = L.mk(4)
	hero_far(q2)
	var wolf: int = L.sp(q2, "shadow_brian", 200.0, 100.0)
	q2.crops.fruits.append({"id": 1, "cell": Vector2i(52, 25), "source_id": 0})
	q2.crops.next_fruit_id = 2
	L.timed(q2, 10.0)
	ck("non_herbivore_ignores_fruit", q2.crops.fruits.size() == 1, "")
	var q3: RefCounted = L.mk(4)
	hero_far(q3)
	var d3: int = L.sp(q3, "deer", 200.0, 100.0)
	q3.crops.fruits.append({"id": 1, "cell": Vector2i(52, 25), "source_id": 0})
	q3.crops.next_fruit_id = 2
	q3.host.set_stable_rect(Rect2i(50, 23, 6, 6))
	L.timed(q3, 10.0)
	ck("herbivore_ignores_fruit_in_stable_region", q3.crops.fruits.size() == 1 and q3.enemies.fruit_for(L.R(q3, d3)).is_empty(), "")
	var q4: RefCounted = L.mk(4)
	hero_far(q4)
	var s4: int = L.sp(q4, "slime_slug", 10.0, 70.0)    # きっかけ10m・縄張り12m(+10m=22m)
	q4.crops.fruits.append({"id": 1, "cell": Vector2i(58, 17), "source_id": 0})   # 約22.4m先(縄張り+10mの22mの外)
	q4.crops.next_fruit_id = 2
	var far_none: bool = q4.enemies.fruit_for(L.R(q4, s4)).is_empty()
	q4.crops.fruits.clear()
	q4.crops.fruits.append({"id": 2, "cell": Vector2i(52, 17), "source_id": 0})   # 約21m先
	var near_some: bool = not q4.enemies.fruit_for(L.R(q4, s4)).is_empty()
	ck("herbivore_fruit_range_trigger_or_territory_plus_10m", far_none and near_some, "far_none=%s near_some=%s" % [str(far_none), str(near_some)])
	# 地域安定の数え方
	var q5: RefCounted = L.mk(4)
	hero_far(q5)
	var kinds_true: Array = ["root_mole", "skunk", "hippo", "honey_bear", "sewer_rat", "bat_flock", "iron_rhino", "thunder_eel", "decoy_newt", "mirror_lizard", "pistol_shrimp", "balloon_frog"]
	var wrong: Array = []
	for k2: String in kinds_true:
		var pos: Vector2 = Vector2(200, 100)
		if k2 == "hippo" or k2 == "thunder_eel":
			pos = Vector2(34, 26)
		var id2: int = L.sp(q5, k2, pos.x, pos.y)
		if not q5.enemies.counts_for_stability(id2):
			wrong.append(k2)
	ck("stability_counts_new_kinds_incl_underground_water_flying", wrong.is_empty(), str(wrong))
	var id_g: int = L.sp(q5, "glass_deer", 120.0, 100.0)
	ck("stability_does_not_count_glass_deer", not q5.enemies.counts_for_stability(id_g), "")
	# 眠り中のハチミツグマ・飛行中のコウモリ・浮かんだカエルも数える(上でスポーン済みの個体の状態を変えて確認)
	var bear_id: int = ids_first(q5, "honey_bear")
	L.R(q5, bear_id).state = "sleep"
	ck("stability_counts_sleeping_bear", q5.enemies.counts_for_stability(bear_id), "")

func ids_first(p: RefCounted, kind: String) -> int:
	var l: Array = L.ids_of(p, kind)
	return int(l[0]) if not l.is_empty() else -1

## 第2弾の定義追加による想定内の変化について、第1弾・第1段のテストの判定を更新した版(第1弾・第1段のテストファイルは編集しない)。
## - lab_logic「全定義のスプライトがある」: 第2弾の動物15定義と植物8種のスプライトは第3段で作る。第1弾の定義はすべてスプライトがあること、
##   未作成が第2弾の定義だけであることを確認する。
## - common2_logic「草食タグは他の種類にない」: 第2弾でカバ・ハチミツグマ・テツヨロイサイが草食になるのが仕様(t_wiring の一覧照合が更新版)。
func t_updated_judgements() -> void:
	var sj: Variant = Defs.load_json("res://data/content_pack/sprites.json")
	var sprites: Dictionary = (sj as Dictionary).get("sprites", {})
	var p: RefCounted = L.mk()
	var absent: Array = []
	for k: String in p.enemies.defs.keys():
		if not sprites.has(k):
			absent.append(k)
	for k2: String in p.crops.defs.keys():
		if not sprites.has(k2):
			absent.append(k2)
	absent.sort()
	var want: Array = ["root_mole", "skunk", "hippo", "honey_bear", "sewer_rat", "manhole", "bat_flock", "iron_rhino", "thunder_eel", "decoy_newt", "decoy_tail", "mirror_lizard", "pistol_shrimp", "balloon_frog", "glass_deer",
		"evening_primrose", "dandelion", "mimosa", "kudzu", "loofah", "hinoki", "apple", "balsam"]
	want.sort()
	ck("updated_sprite_coverage_only_stage3_kinds_pending", absent == want and sprites.size() == 63, "absent=%d sprites=%d" % [absent.size(), sprites.size()])
	var first1: int = 0
	for k3: String in p.enemies.defs.keys():
		if sprites.has(k3):
			first1 += 1
	ck("updated_first_batch_enemy_defs_all_have_sprites", first1 == p.enemies.defs.size() - 15, "with_sprite=%d defs=%d" % [first1, p.enemies.defs.size()])
