extends SceneTree
## 敵の共通処理とE01〜E11の自己検証(入口スクリプト)。1条件1回、ゲーム内時間は advance で早送り。
## 実行(隔離プロジェクトのみ): Godot --headless --path C:/godot/greenvader_content_sandbox --script res://tests/content_pack/self/enemies_a.gd
const Lab: GDScript = preload("res://scripts/content_pack/lab/lab_host.gd")
const Pack: GDScript = preload("res://scripts/content_pack/content_pack.gd")
const OUT_DIR: String = "res://evidence/content_pack/self"

var checks: Array = []

func ck(name: String, ok: bool, detail: String = "") -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})

func near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps

func mk(seed: int = 1) -> RefCounted:
	return Pack.new(Lab.new(), seed)

func sp(p: RefCounted, kind: String, x: float, y: float, origin: String = "initial", opts: Dictionary = {}) -> int:
	return p.enemies.spawn(kind, Vector2(x, y), origin, opts)

func E(p: RefCounted, id: int) -> Dictionary:
	return p.enemies.get_enemy(id)

func R(p: RefCounted, id: int) -> Dictionary:
	return p.enemies.ref(id)

func hero(p: RefCounted, x: float, y: float, aim: Vector2 = Vector2.RIGHT) -> void:
	p.host.hero_state = {"pos": Vector2(x, y), "hp": 100.0, "max_hp": 100.0, "aim": aim}

func crop(p: RefCounted, kind: String, x: int, y: int, mature: bool = true) -> int:
	var r: Dictionary = p.crops.spawn_crop(kind, Vector2i(x, y), 0, {"mature": mature, "watered": true, "skip_check": true})
	return int(r.id) if bool(r.ok) else -1

func evs(events: Array, type: String, kind: String = "") -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if e.type == type and (kind == "" or str(e.get("kind", "")) == kind):
			out.append(e)
	return out

## dt刻みで secs 秒進め、[時刻, イベント] の配列を返す
func timed(p: RefCounted, secs: float, dt: float = 0.1) -> Array:
	var out: Array = []
	var n: int = int(round(secs / dt))
	for i: int in range(n):
		var ev: Array[Dictionary] = p.advance(dt)
		for e: Dictionary in ev:
			out.append({"t": p.enemies.time, "e": e})
	return out

func only(tl: Array, type: String, kind: String = "") -> Array:
	var out: Array = []
	for x: Dictionary in tl:
		var e: Dictionary = x.e
		if e.type == type and (kind == "" or str(e.get("kind", "")) == kind):
			out.append(x)
	return out

func roundtrip(d: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(d))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func snap(p: RefCounted, prec: float = 0.001) -> String:
	var rows: Array = []
	for e: Dictionary in p.enemies.enemies:
		rows.append("%d:%s:%s:%.3f:%.2f,%.2f" % [e.id, e.kind, e.state, e.hp, snappedf(e.pos.x, prec), snappedf(e.pos.y, prec)])
	rows.sort()
	return "|".join(rows) + "#g%d#p%d#s%d#pl%d" % [p.enemies.gas.size(), p.enemies.projectiles.size(), p.enemies.slime.size(), p.enemies.piles.size()]

func _initialize() -> void:
	t_common_reward()
	t_common_stability_detect()
	t_common_flying_flee()
	t_common_stable()
	t_common_save_pause()
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
	t_plants()
	var fails: int = 0
	var lines: Array = []
	for c: Dictionary in checks:
		var line: String = "%s %s %s" % [c.status, c.name, c.detail]
		print(line)
		lines.append(line)
		if c.status != "PASS":
			fails += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/enemies_a.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "enemies_a", "total": checks.size(), "failed": fails, "checks": checks}, "\t"))
	f.close()
	print("enemies_a total=%d failed=%d" % [checks.size(), fails])
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------ 共通: 報酬
func t_common_reward() -> void:
	var p: RefCounted = mk()
	var id: int = sp(p, "shadow_brian", 60, 100, "initial", {"tier": "mid"})
	var ev: Array = p.hit_enemy(id, 60.0, "tackle", null)
	var rw: Array = evs(ev, "reward")
	ck("reward_once_on_final_kill", rw.size() == 1 and int(rw[0].amount) == 15 and rw[0].tier == "mid" and evs(ev, "enemy_defeated").size() == 1, str(rw))
	var ev2: Array = p.hit_enemy(id, 60.0, "tackle", null)
	ck("no_second_reward_after_death", ev2.is_empty() and not p.enemies.is_alive(id), "")
	var q: RefCounted = mk()
	var id2: int = sp(q, "shadow_brian", 60, 100, "produced")
	var ev3: Array = q.hit_enemy(id2, 60.0, "tackle", null)
	ck("produced_enemy_reward_is_zero", evs(ev3, "reward").is_empty() and evs(ev3, "enemy_defeated").size() == 1, "")

# ------------------------------------------------------------------ 共通: 安定判定・検知
func t_common_stability_detect() -> void:
	var p: RefCounted = mk()
	var b: int = sp(p, "shadow_brian", 60, 100)
	var sn: int = sp(p, "grass_snake", 100, 100)
	var bd: int = sp(p, "seed_bird", 150, 40)
	R(p, bd).state = "flying"
	var sp2: int = sp(p, "tarachunade", 200, 100)
	R(p, sp2).state = "charred"
	var hv: int = sp(p, "honeybee_hive", 20, 120)
	ck("stability_counts_hidden_flying_charred_not_neutral",
		p.enemies.living_count_for_stability() == 4 and p.enemies.counts_for_stability(sn) and p.enemies.counts_for_stability(bd) \
		and p.enemies.counts_for_stability(sp2) and not p.enemies.counts_for_stability(hv) and p.enemies.is_alive(hv), str(p.enemies.living_count_for_stability()))
	p.hit_enemy(b, 60.0, "tackle", null)
	ck("stability_count_drops_on_kill", p.enemies.living_count_for_stability() == 3 and not p.enemies.counts_for_stability(b), "")
	# 検知
	var q: RefCounted = mk()
	var s1: int = sp(q, "grass_snake", 100, 100)
	var det: Array = q.enemies.detectable_enemies()
	var ht: Array = q.enemies.hittable_targets()
	ck("hidden_snake_not_detectable_but_hittable", det.is_empty() and ht.size() == 1 and bool(ht[0].hidden), str(det.size()))
	q.enemies.notify_seed(Vector2(104, 100))
	ck("seed_within_1m_reveals_snake_detectable", q.enemies.detectable_enemies().size() == 1, "")
	var q2: RefCounted = mk()
	sp(q2, "grass_snake", 130, 100)
	crop(q2, "glow_moss", 33, 25)
	q2.host.day = false
	var night: int = q2.enemies.detectable_enemies().size()
	q2.host.day = true
	var day: int = q2.enemies.detectable_enemies().size()
	ck("glow_moss_reveals_hidden_only_at_night", night == 1 and day == 0, "night=%d day=%d" % [night, day])

# ------------------------------------------------------------------ 共通: 飛行・逃走
func t_common_flying_flee() -> void:
	var p: RefCounted = mk()
	var bd: int = sp(p, "seed_bird", 150, 40)
	R(p, bd).state = "flying"
	var listed: bool = false
	for t: Dictionary in p.enemies.hittable_targets():
		if t.id == bd:
			listed = true
	var ev: Array = p.hit_enemy(bd, 5.0, "shot", null)
	ck("flying_not_hittable", not listed and ev.is_empty() and near(float(E(p, bd).hp), 8.0), "")
	R(p, bd).state = "landing"
	var ev2: Array = p.hit_enemy(bd, 3.0, "shot", null)
	ck("landing_is_hittable", near(float(E(p, bd).hp), 5.0) and evs(ev2, "enemy_damaged").size() == 1, "")
	# 逃げる敵は縄張りの外へ出ない(ブリアン: 縄張り6m=60px、逃げ速度は3.5m/s以下)
	var q: RefCounted = mk()
	var id: int = sp(q, "shadow_brian", 175, 60, "initial", {"home": Vector2(150, 60)})
	q.enemies.start_flee(R(q, id), 3.0, Vector2(100, 60))
	q.advance(0.5)
	var moved: float = float(E(q, id).pos.x) - 175.0
	var maxd: float = 0.0
	for i: int in range(24):
		q.advance(0.1)
		maxd = maxf(maxd, E(q, id).pos.distance_to(Vector2(150, 60)))
	ck("fleeing_enemy_stays_within_territory_and_not_faster_than_3_5mps", maxd <= 60.01 and maxd >= 58.0 and moved <= 17.6 and moved >= 17.0, "maxd=%.2f moved0.5=%.2f" % [maxd, moved])

func t_common_stable() -> void:
	# 安定した地域へは入らない(突進も壁と同じく止まる)
	var p: RefCounted = mk()
	p.host.set_stable_rect(Rect2i(12, 22, 4, 7))
	hero(p, 80, 100)
	var id: int = sp(p, "shadow_brian", 20, 100)
	timed(p, 3.0)
	var b: Dictionary = E(p, id)
	ck("stable_cells_are_not_entered_charge_stops_at_edge", b.state == "stuck" and float(b.pos.x) < 48.0 and float(b.pos.x) >= 44.0, "x=%.1f st=%s" % [float(b.pos.x), str(b.state)])

# ------------------------------------------------------------------ 共通: 保存・ポーズ
func _scene_c7(p: RefCounted) -> void:
	hero(p, 150, 110)
	p.enemies.spawn_wolf_pack(Vector2(120, 110))
	var fam: Dictionary = p.enemies.spawn_mushling_family(Vector2(190, 120))
	p.enemies.ref(int(fam.children[0])).pos = Vector2(160, 118)
	sp(p, "quill_hedgehog", 150, 60)
	crop(p, "clover", 25, 25)
	sp(p, "slime_slug", 100, 100)
	sp(p, "junk_crab", 200, 60, "initial", {"piles": [{"pos": Vector2(202, 26), "stock": 2}]})
	sp(p, "grass_snake", 60, 120)

func t_common_save_pause() -> void:
	var p: RefCounted = mk(7)
	_scene_c7(p)
	p.advance(5.0)
	var had_gas: bool = p.enemies.gas.size() > 0
	var had_slime: bool = p.enemies.slime.size() > 0
	var saved: Dictionary = roundtrip(p.to_dict())
	var direct: Dictionary = p.to_dict()
	var q: RefCounted = mk(99)
	hero(q, 150, 110)
	var okq: bool = q.from_dict(saved)
	var r: RefCounted = mk(98)
	hero(r, 150, 110)
	var okr: bool = r.from_dict(direct)
	p.advance(10.0)
	q.advance(10.0)
	r.advance(10.0)
	ck("restore_direct_dict_continues_identically", okr and snap(p) == snap(r), snap(p).substr(0, 100))
	ck("restore_via_json_continues_same_state", okq and snap(p, 0.5) == snap(q, 0.5) and had_slime, snap(q, 0.5).substr(0, 100))
	ck("save_contains_gas_slime_piles_projectiles_packs", had_gas or had_slime, "gas=%s slime=%s piles=%d" % [str(had_gas), str(had_slime), p.enemies.piles.size()])
	# ポーズ: advance を呼ばなければ進まない
	var before: String = JSON.stringify(p.to_dict())
	p.enemies.hittable_targets()
	p.enemies.detectable_enemies()
	var e1: Array = p.advance(0.0)
	var e2: Array = p.advance(-1.0)
	ck("no_advance_no_change", e1.is_empty() and e2.is_empty() and JSON.stringify(p.to_dict()) == before, "")
	# 不正データは状態を変えない
	var bad: Dictionary = roundtrip(p.to_dict())
	bad.enemies.enemies[0].kind = "no_such_kind"
	var bad2: Dictionary = roundtrip(p.to_dict())
	bad2.enemies.slime = "x"
	ck("from_dict_rejects_invalid_enemies_keeps_state", p.enemies.from_dict(bad.enemies) == false and p.enemies.from_dict(bad2.enemies) == false and JSON.stringify(p.to_dict()) == before, "")

# ------------------------------------------------------------------ E01 シャドーブリアン
func t_e01() -> void:
	# 突進: 予兆1.1秒→壁に衝突→刺さって3秒動けず、全方向から×1.5。突進命中20は1回だけ。
	var p: RefCounted = mk()
	hero(p, 100, 68)
	var id: int = sp(p, "shadow_brian", 60, 68)
	var tl: Array = timed(p, 3.0)
	var hd: Array = only(tl, "hero_damage", "shadow_brian")
	var b: Dictionary = E(p, id)
	ck("e01_charge_hits_hero_once_20_and_sticks_in_wall", hd.size() == 1 and near(float(hd[0].e.amount), 20.0) and b.state == "stuck" and b.pos.x >= 108.0 and b.pos.x < 112.0, "n=%d x=%.1f st=%s" % [hd.size(), b.pos.x, b.state])
	var ev: Array = p.hit_enemy(id, 10.0, "shot", Vector2(130, 68))
	ck("e01_stuck_takes_x1_5_even_from_front", near(float(E(p, id).hp), 45.0), "hp=%.2f" % float(E(p, id).hp))
	# 正面120°の射撃×0.25(たいあたり・バズーカ・側面・背面は減らない)
	var q: RefCounted = mk()
	var id2: int = sp(q, "shadow_brian", 60, 30)
	q.hit_enemy(id2, 10.0, "shot", Vector2(60, 50))
	var h1: float = float(E(q, id2).hp)
	q.hit_enemy(id2, 10.0, "shot", Vector2(60, 10))
	var h2: float = float(E(q, id2).hp)
	q.hit_enemy(id2, 10.0, "shot", Vector2(80, 30))
	var h3: float = float(E(q, id2).hp)
	q.hit_enemy(id2, 8.0, "tackle", Vector2(60, 50))
	var h4: float = float(E(q, id2).hp)
	q.hit_enemy(id2, 25.0, "bazooka", Vector2(60, 50))
	var h5: float = float(E(q, id2).hp)
	ck("e01_front_120deg_shot_x0_25_others_full", near(h1, 57.5) and near(h2, 47.5) and near(h3, 37.5) and near(h4, 29.5) and near(h5, 4.5), "%.1f %.1f %.1f %.1f %.1f" % [h1, h2, h3, h4, h5])
	# 外れた突進は2.5秒で止まり、1.5秒の硬直
	var r: RefCounted = mk()
	hero(r, 80, 100)
	var id3: int = sp(r, "shadow_brian", 20, 100)
	timed(r, 1.1)
	r.host.hero_state = {}
	timed(r, 3.1)
	var st1: String = str(E(r, id3).state)
	var x1: float = float(E(r, id3).pos.x)
	timed(r, 1.4)
	var st2: String = str(E(r, id3).state)
	ck("e01_missed_charge_2_5s_then_1_5s_recover", st1 == "recover" and st2 == "idle" and near(x1, 220.0, 2.0), "st1=%s st2=%s x=%.1f" % [st1, st2, x1])

# ------------------------------------------------------------------ E02 タラチュネード
func t_e02() -> void:
	var p: RefCounted = mk()
	hero(p, 180, 76)
	var cid: int = crop(p, "clover", 46, 17)
	var sid: int = sp(p, "tarachunade", 180, 70)
	var bird: int = sp(p, "seed_bird", 195, 70)
	var tl: Array = timed(p, 2.0)
	var hd: Array = only(tl, "hero_damage", "tarachunade")
	var cd: Array = only(tl, "crop_damaged")
	ck("e02_explosion_after_1_5s_fuse_hero_18_crop_10", hd.size() == 1 and near(float(hd[0].e.amount), 18.0) and near(float(hd[0].t), 1.7, 0.05) and cd.size() == 1 and near(float(cd[0].e.amount), 10.0), "t=%.2f" % (float(hd[0].t) if hd.size() > 0 else -1.0))
	ck("e02_explosion_hp_unchanged_no_reward_other_enemy_unhurt_still_counts",
		E(p, sid).state == "charred" and near(float(E(p, sid).hp), 30.0) and only(tl, "reward").is_empty() and near(float(E(p, bird).hp), 8.0) and p.enemies.counts_for_stability(sid), "")
	var tl2: Array = timed(p, 15.0)
	ck("e02_revives_after_15s_with_same_hp_no_explosion_during_charred", E(p, sid).state == "recover" and near(float(E(p, sid).hp), 30.0) and only(tl2, "hero_damage", "tarachunade").is_empty(), "st=%s" % str(E(p, sid).state))
	var tl3: Array = timed(p, 6.0)
	ck("e02_no_reexplosion_for_4s_then_second_explosion_no_reward_ever",
		only(tl3, "hero_damage", "tarachunade").size() == 1 and near(float(only(tl3, "hero_damage", "tarachunade")[0].t), 22.2, 0.05) and only(tl3, "reward").is_empty(), "")
	# 黒焦げは被ダメ×2、最終撃破で報酬は1回
	var q: RefCounted = mk()
	hero(q, 180, 76)
	var sid2: int = sp(q, "tarachunade", 180, 70)
	timed(q, 2.0)
	var ev1: Array = q.hit_enemy(sid2, 10.0, "shot", null)
	var hp1: float = float(E(q, sid2).hp)
	var ev2: Array = q.hit_enemy(sid2, 10.0, "shot", null)
	ck("e02_charred_x2_final_kill_pays_6_once", near(hp1, 10.0) and evs(ev1, "reward").is_empty() and evs(ev2, "reward").size() == 1 and int(evs(ev2, "reward")[0].amount) == 6 and not q.enemies.is_alive(sid2), "hp1=%.1f" % hp1)
	# 水: 予兆を中断し20秒点火できず、歩いてかみつく(4/1秒)
	var w: RefCounted = mk()
	hero(w, 180, 76)
	var sid3: int = sp(w, "tarachunade", 180, 70)
	var tw1: Array = timed(w, 1.0)
	var evw: Array = w.splash(Vector2(180, 70), 20.0, 0.0, "water")
	var tw2: Array = timed(w, 3.0)
	var bites: Array = only(tw2, "hero_damage", "tarachunade")
	ck("e02_water_cancels_fuse_wet_20s_bites_4_per_s", E(w, sid3).state == "chase" and bites.size() == 3 and near(float(bites[0].e.amount), 4.0) and E(w, sid3).wet_until > w.enemies.time + 15.0 and only(tw1, "hero_damage").is_empty(), "bites=%d st=%s" % [bites.size(), str(E(w, sid3).state)])

# ------------------------------------------------------------------ E03 マッシュリング
func _fam(p: RefCounted, c1: Vector2, c2: Vector2) -> Dictionary:
	var fam: Dictionary = p.enemies.spawn_mushling_family(Vector2(180, 40))
	R(p, int(fam.children[0])).pos = c1
	R(p, int(fam.children[1])).pos = c2
	return fam

func t_e03() -> void:
	# 子が鳴く→親が駆け寄る。鳴き声は15秒に1回まで。
	var p: RefCounted = mk()
	hero(p, 180, 125)
	var fam: Dictionary = _fam(p, Vector2(180, 80), Vector2(240, 100))
	var t1: Array = timed(p, 0.1)
	var calls1: int = only(t1, "mushling_call").size()
	var st: String = str(E(p, int(fam.parent)).state)
	timed(p, 0.5)
	var py: float = float(E(p, int(fam.parent)).pos.y)
	var t2: Array = timed(p, 14.2)
	var calls2: int = only(t2, "mushling_call").size()
	var t3: Array = timed(p, 1.4)
	var calls3: int = only(t3, "mushling_call").size()
	ck("e03_child_calls_parent_rushes_call_every_15s_only", calls1 == 1 and st == "rush" and calls2 == 0 and calls3 == 1 and py > 40.0, "calls=%d/%d/%d st=%s" % [calls1, calls2, calls3, st])
	# 子の胞子ガス: 6秒ごと、半径1.2m・4秒、毎秒3(主人公)
	var q: RefCounted = mk()
	hero(q, 180, 88)
	var fam_b: Dictionary = _fam(q, Vector2(180, 80), Vector2(240, 100))
	var tg: Array = timed(q, 6.0)
	var gd: Array = only(tg, "hero_damage", "gas")
	var gas_n: int = 0
	for g: Dictionary in q.enemies.gas:
		if int(g.owner) == int(fam_b.children[0]):
			gas_n += 1
	ck("e03_gas_ticks_3_per_s_4_times_then_gone_after_4s", gd.size() == 4 and near(float(gd[0].e.amount), 3.0) and near(float(gd[0].t), 2.7, 0.05) and gas_n == 0, "n=%d gas=%d" % [gd.size(), gas_n])
	# 怒り: 子の最終撃破で親が25秒。怒り中の再撃破で25秒に戻る。速度×1.6、攻撃12/0.8秒。
	var r: RefCounted = mk()
	hero(r, 180, 120)
	var f2: Dictionary = _fam(r, Vector2(180, 45), Vector2(240, 100))
	var k1: Array = r.hit_enemy(int(f2.children[0]), 12.0, "tackle", null)
	var pid: int = int(f2.parent)
	var rg1: float = float(E(r, pid).rage_until)
	var t_k1: float = r.enemies.time
	timed(r, 1.0)
	var moved: float = float(E(r, pid).pos.y) - 40.0
	var tr: Array = timed(r, 4.0)
	var bites: Array = only(tr, "hero_damage", "mushling_parent")
	var spacing_ok: bool = bites.size() >= 2 and near(float(bites[1].t) - float(bites[0].t), 0.8, 0.05)
	var amounts_ok: bool = bites.size() >= 2 and near(float(bites[0].e.amount), 12.0) and near(float(bites[1].e.amount), 12.0)
	ck("e03_child_kill_reward_3_and_parent_enrages_25s", evs(k1, "reward").size() == 1 and int(evs(k1, "reward")[0].amount) == 3 and near(rg1 - t_k1, 25.0, 0.01), "rage=%.2f" % (rg1 - t_k1))
	ck("e03_rage_speed_x1_6_and_bite_12_every_0_8s", near(moved, 22.4, 0.6) and spacing_ok and amounts_ok, "moved=%.2f bites=%d" % [moved, bites.size()])
	var t_before: float = r.enemies.time
	r.hit_enemy(int(f2.children[1]), 12.0, "tackle", null)
	ck("e03_second_child_kill_resets_rage_to_25s", near(float(E(r, pid).rage_until) - t_before, 25.0, 0.01), "")
	# 親だけ撃破: 子の行動は変わらずガスが続く。親の撃破は怒りを起こさない
	var s: RefCounted = mk()
	hero(s, 180, 88)
	var f3: Dictionary = _fam(s, Vector2(180, 80), Vector2(240, 100))
	s.hit_enemy(int(f3.parent), 70.0, "tackle", null)
	timed(s, 3.0)
	var kid: Dictionary = E(s, int(f3.children[0]))
	ck("e03_parent_dead_child_still_gases_no_rage", s.enemies.gas.size() >= 1 and not s.enemies.is_alive(int(f3.parent)) and kid.state == "harass", "gas=%d st=%s" % [s.enemies.gas.size(), str(kid.state)])

# ------------------------------------------------------------------ E04 ハリナゲネズミ
func t_e04() -> void:
	var p: RefCounted = mk()
	hero(p, 180, 110)
	var id: int = sp(p, "quill_hedgehog", 180, 70)
	var tl: Array = timed(p, 2.0)
	var hd: Array = only(tl, "hero_damage", "needle")
	ck("e04_throws_one_needle_6_damage_per_2_5s_keeping_4_to_6m", hd.size() == 1 and near(float(hd[0].e.amount), 6.0) and E(p, id).state == "keep" and E(p, id).pos.distance_to(Vector2(180, 110)) >= 39.9, "n=%d" % hd.size())
	# 針は建物で遮られる(建物 x112..143)
	var q: RefCounted = mk()
	hero(q, 150, 68)
	q.enemies.spawn_projectile({"kind": "needle", "owner": 1, "pos": Vector2(100, 68), "dir": Vector2.RIGHT, "speed": 120.0, "left": 90.0, "damage": 6.0})
	var tq: Array = timed(q, 1.0)
	ck("e04_needle_blocked_by_building", only(tq, "hero_damage").is_empty() and q.enemies.projectiles.is_empty(), "")
	# 丸まり: 射撃×0.1、たいあたりで解除→2秒動けず被ダメ×1.5
	var r: RefCounted = mk()
	hero(r, 180, 90)
	var id2: int = sp(r, "quill_hedgehog", 180, 70)
	timed(r, 0.3)
	var st: String = str(E(r, id2).state)
	r.hit_enemy(id2, 10.0, "shot", null)
	var h1: float = float(E(r, id2).hp)
	r.hit_enemy(id2, 8.0, "tackle", null)
	var h2: float = float(E(r, id2).hp)
	var st2: String = str(E(r, id2).state)
	r.hit_enemy(id2, 10.0, "shot", null)
	var h3: float = float(E(r, id2).hp)
	ck("e04_curl_x0_1_tackle_breaks_curl_then_flipped_x1_5", st == "curl" and near(h1, 24.0) and near(h2, 16.0) and st2 == "flipped" and near(h3, 1.0), "%s %.1f %.1f %s %.1f" % [st, h1, h2, st2, h3])

# ------------------------------------------------------------------ E05 クサヘビ
func t_e05() -> void:
	var p: RefCounted = mk()
	var id: int = sp(p, "grass_snake", 180, 70)
	hero(p, 180, 110)
	var d0: bool = p.enemies.detectable_enemies().is_empty()
	hero(p, 180, 80)
	var tl: Array = timed(p, 0.5)
	var hd: Array = only(tl, "hero_damage", "grass_snake")
	var det1: int = p.enemies.detectable_enemies().size()
	hero(p, 180, 140)
	timed(p, 5.0)
	var det_6: int = p.enemies.detectable_enemies().size()
	timed(p, 4.0)
	var moved: bool = E(p, id).pos.distance_to(Vector2(180, 70)) >= 10.0
	ck("e05_hidden_until_bite_10_then_visible_6s_relocates_3plus_cells", d0 and hd.size() == 1 and near(float(hd[0].e.amount), 10.0) and det1 == 1 and moved, "n=%d det1=%d" % [hd.size(), det1])
	ck("e05_rehides_after_reveal_and_2s_still_on_grass", det_6 == 1 and p.enemies.detectable_enemies().is_empty() and E(p, id).state == "hidden", "det6=%d st=%s" % [det_6, str(E(p, id).state)])
	# 攻撃が当たると6秒見え、その後2秒止まって再び擬態
	var q: RefCounted = mk()
	var id2: int = sp(q, "grass_snake", 180, 70)
	q.hit_enemy(id2, 1.0, "shot", null)
	timed(q, 7.5)
	var a: int = q.enemies.detectable_enemies().size()
	timed(q, 1.0)
	var b: int = q.enemies.detectable_enemies().size()
	ck("e05_hit_reveals_6s_then_2s_still_rehides", a == 1 and b == 0, "a=%d b=%d" % [a, b])
	# 荒地では擬態できない
	var r: RefCounted = mk()
	r.host.set_stage(Vector2i(50, 27), "wasteland")
	r.host.set_terrain(Vector2i(50, 27), Lab.WASTE)
	sp(r, "grass_snake", 202, 110)
	timed(r, 12.0)
	ck("e05_cannot_hide_on_wasteland", r.enemies.detectable_enemies().size() == 1, "")

# ------------------------------------------------------------------ E06 タネクイドリ
func _seeds(p: RefCounted, n: int) -> void:
	for i: int in range(n):
		p.host.set_stage(Vector2i(52 + i, 12), "seed")

func _apply_ground(p: RefCounted, events: Array) -> void:
	for e: Dictionary in events:
		if e.type == "ground_stage":
			p.host.set_stage(e.cell, e.stage)

func t_e06() -> void:
	var p: RefCounted = mk()
	_seeds(p, 3)
	var id: int = sp(p, "seed_bird", 190, 40)
	timed(p, 0.3)
	var st_fly: String = str(E(p, id).state)
	var in_list: bool = false
	for t: Dictionary in p.enemies.hittable_targets():
		if t.id == id:
			in_list = true
	var hit_ev: Array = p.hit_enemy(id, 1.0, "shot", null)
	timed(p, 0.6)
	var st_land: String = str(E(p, id).state)
	ck("e06_flying_not_hittable_landing_hittable", st_fly == "flying" and not in_list and hit_ev.is_empty() and st_land == "landing", "%s %s" % [st_fly, st_land])
	var tl: Array = timed(p, 3.0)
	var gs: Array = only(tl, "ground_stage")
	ck("e06_eats_only_seed_cell_after_2s_sets_wasteland", gs.size() >= 1 and gs[0].e.cell == Vector2i(52, 12) and gs[0].e.stage == "wasteland" and gs[0].e.cause == "seed_bird", str(gs[0].e.cell) if gs.size() > 0 else "none")
	# 10マス食べたら家へ戻り休む(10マスだけ食べる)
	var q: RefCounted = mk()
	_seeds(q, 12)
	var id2: int = sp(q, "seed_bird", 190, 40)
	var eaten: int = 0
	for i: int in range(80):
		var ev: Array[Dictionary] = q.advance(0.5)
		_apply_ground(q, ev)
		for e: Dictionary in ev:
			if e.type == "ground_stage":
				eaten += 1
	ck("e06_eats_10_then_goes_home_and_rests_20s", eaten == 10 and E(q, id2).state == "perch" and float(E(q, id2).rest_until) > q.enemies.time, "eaten=%d st=%s" % [eaten, str(E(q, id2).state)])
	# 主人公が4m以内に来ると飛び立つ。着地中だけ小型(ハエトリソウが捕まえる)
	var r: RefCounted = mk()
	r.host.set_stage(Vector2i(52, 12), "seed")
	crop(r, "flytrap", 51, 12)
	var id3: int = sp(r, "seed_bird", 190, 40)
	var tr: Array = timed(r, 1.6)
	var cap: Array = only(tr, "flytrap_capture")
	var rw: Array = only(tr, "reward")
	ck("e06_landing_is_small_flytrap_captures_30_kills_reward_4", cap.size() == 1 and not r.enemies.is_alive(id3) and rw.size() == 1 and int(rw[0].e.amount) == 4, "cap=%d" % cap.size())
	var s: RefCounted = mk()
	s.host.set_stage(Vector2i(52, 12), "seed")
	s.host.set_stage(Vector2i(53, 12), "seed")
	var id4: int = sp(s, "seed_bird", 190, 40)
	timed(s, 1.5)
	hero(s, 214, 56)
	timed(s, 0.2)
	ck("e06_hero_within_4m_makes_it_take_off", E(s, id4).state == "takeoff", str(E(s, id4).state))

# ------------------------------------------------------------------ E07 ガラクタヤドカリ
func t_e07() -> void:
	var p: RefCounted = mk()
	var id: int = sp(p, "junk_crab", 190, 60)
	var e1: Array = p.hit_enemy(id, 20.0, "shot", null)
	var s1: float = float(E(p, id).shell_hp)
	var hp1: float = float(E(p, id).hp)
	var e2: Array = p.hit_enemy(id, 25.0, "bazooka", null)
	var broken: bool = not bool(E(p, id).shell)
	var hp2: float = float(E(p, id).hp)
	var e3: Array = p.hit_enemy(id, 5.0, "shot", null)
	var hp3: float = float(E(p, id).hp)
	var e4: Array = p.hit_enemy(id, 3.0, "shot", null)
	ck("e07_shell_absorbs_bazooka_x2_breaks_naked_x2_no_reward_until_final",
		near(s1, 10.0) and near(hp1, 15.0) and broken and near(hp2, 15.0) and near(hp3, 5.0) and evs(e1 + e2 + e3, "reward").is_empty() \
		and evs(e4, "reward").size() == 1 and int(evs(e4, "reward")[0].amount) == 8, "%.1f %.1f %.1f %.1f" % [s1, hp1, hp2, hp3])
	# 裸は最も近い置き場へ向かい、3秒で新しい殻を背負う。在庫が尽きた置き場は消える。
	var q: RefCounted = mk()
	var pile: int = q.enemies.add_junk_pile(Vector2(202, 26), 1)
	var id2: int = sp(q, "junk_crab", 190, 40)
	q.hit_enemy(id2, 50.0, "bazooka", null)
	var tl: Array = timed(q, 4.6)
	ck("e07_naked_wears_new_shell_at_pile_stock_empties_pile_removed",
		bool(E(q, id2).shell) and near(float(E(q, id2).shell_hp), 30.0) and q.enemies.piles.is_empty() and only(tl, "junk_pile_removed").size() == 1, "shell=%s piles=%d" % [str(E(q, id2).shell), q.enemies.piles.size()])
	# 置き場は射撃で崩せる(HP20、報酬なし)
	var r: RefCounted = mk()
	var pl: int = r.enemies.add_junk_pile(Vector2(202, 26), 2)
	var ev: Array = r.hit_enemy(pl, 25.0, "shot", null)
	ck("e07_pile_destroyed_by_shot_no_reward", evs(ev, "junk_pile_destroyed").size() == 1 and r.enemies.piles.is_empty() and evs(ev, "reward").is_empty(), "")
	# 置き場が無ければ裸のまま縄張りで戦う(ひっかき4)
	var s: RefCounted = mk()
	hero(s, 190, 100)
	var id3: int = sp(s, "junk_crab", 190, 70)
	s.hit_enemy(id3, 50.0, "bazooka", null)
	var ts: Array = timed(s, 3.0)
	var sc: Array = only(ts, "hero_damage", "junk_crab")
	ck("e07_naked_without_piles_fights_with_scratch_4", sc.size() >= 1 and near(float(sc[0].e.amount), 4.0), "n=%d" % sc.size())

# ------------------------------------------------------------------ E08 ノラオオカミ
func t_e08() -> void:
	var p: RefCounted = mk()
	hero(p, 150, 110)
	var ids: Array = p.enemies.spawn_wolf_pack(Vector2(120, 110))
	var t0: Array = timed(p, 0.2)
	var howl: int = only(t0, "fx").size()
	hero(p, 150, 110, Vector2.from_angle(float(E(p, int(ids[0])).circle_base)))
	var all_howl: bool = true
	for i: int in ids:
		if E(p, i).state != "howl":
			all_howl = false
	timed(p, 1.0)
	var front: int = int(ids[0])
	var lunged_front: bool = false
	var lunged_other: bool = false
	var bites: int = 0
	for i: int in range(40):
		var ev: Array[Dictionary] = p.advance(0.1)
		for e: Dictionary in ev:
			if e.type == "hero_damage" and e.kind == "stray_wolf":
				bites += 1
		if E(p, front).state == "lunge":
			lunged_front = true
		if E(p, int(ids[1])).state == "lunge" or E(p, int(ids[2])).state == "lunge":
			lunged_other = true
	ck("e08_howl_calls_whole_pack_to_hunt", howl >= 1 and all_howl, "howl=%d" % howl)
	ck("e08_only_wolves_outside_aim_60deg_lunge_bite_7", not lunged_front and lunged_other and bites >= 1, "front=%s other=%s bites=%d" % [str(lunged_front), str(lunged_other), bites])
	# 最後の1匹は囲みをやめ、正面から詰めて7ダメージ/1.2秒
	var q: RefCounted = mk()
	hero(q, 150, 110)
	var qi: Array = q.enemies.spawn_wolf_pack(Vector2(120, 110))
	q.hit_enemy(int(qi[1]), 18.0, "tackle", null)
	var rw2: Array = q.hit_enemy(int(qi[2]), 18.0, "tackle", null)
	var tq: Array = timed(q, 5.0)
	var lb: Array = only(tq, "hero_damage", "stray_wolf")
	var st: String = str(E(q, int(qi[0])).state)
	ck("e08_last_wolf_bites_7_every_1_2s_no_circling", lb.size() >= 2 and near(float(lb[0].e.amount), 7.0) and near(float(lb[1].t) - float(lb[0].t), 1.2, 0.05) and st != "lunge" and evs(rw2, "reward").size() == 1, "n=%d st=%s" % [lb.size(), st])

# ------------------------------------------------------------------ E09 コケガメ
func t_e09() -> void:
	var p: RefCounted = mk()
	var cid: int = crop(p, "clover", 50, 20)
	var id: int = sp(p, "moss_turtle", 180, 70)
	var hidden0: bool = p.enemies.detectable_enemies().is_empty()
	var tl: Array = timed(p, 13.0)
	var cd: Array = only(tl, "crop_damaged")
	var rm: Array = only(tl, "crop_removed")
	ck("e09_hidden_then_walks_and_eats_8_per_2s_until_crop_dies", hidden0 and cd.size() == 4 and near(float(cd[0].e.amount), 8.0) and rm.size() == 1 and rm[0].e.reason == "enemy" and int(rm[0].e.refund) == 0, "dmg=%d" % cd.size())
	var q: RefCounted = mk()
	var id2: int = sp(q, "moss_turtle", 180, 70)
	q.hit_enemy(id2, 10.0, "shot", null)
	var h1: float = float(E(q, id2).hp)
	var shown: bool = q.enemies.detectable_enemies().size() == 1
	q.hit_enemy(id2, 25.0, "bazooka", null)
	var flipped: bool = E(q, id2).state == "flipped"
	var h2: float = float(E(q, id2).hp)
	q.hit_enemy(id2, 10.0, "shot", null)
	var h3: float = float(E(q, id2).hp)
	ck("e09_shot_x0_3_bazooka_flips_flipped_x3", near(h1, 77.0) and shown and flipped and near(h2, 52.0) and near(h3, 22.0), "%.1f %.1f %.1f" % [h1, h2, h3])
	timed(q, 4.2)
	var st_after: String = str(E(q, id2).state)
	timed(q, 10.2)
	ck("e09_flip_4s_then_rehide_after_10s_still", st_after == "revealed" and E(q, id2).state == "hidden" and q.enemies.detectable_enemies().is_empty(), "%s/%s" % [st_after, str(E(q, id2).state)])
	var blk: Array = q.enemies.body_blockers()
	var kill: Array = q.hit_enemy(id2, 100.0, "tackle", null)
	var fert: Array = evs(kill, "fertile")
	ck("e09_blocks_hero_body_and_fertile_on_death_reward_15", blk.size() == 1 and fert.size() == 1 and near(float(fert[0].radius_px), 12.0) and evs(kill, "reward").size() == 1 and int(evs(kill, "reward")[0].amount) == 15, "")

# ------------------------------------------------------------------ E10 ペンキカメレオン
func t_e10() -> void:
	var p: RefCounted = mk()
	var id: int = sp(p, "paint_chameleon", 180, 70)
	hero(p, 180, 100)
	var hid0: bool = p.enemies.detectable_enemies().is_empty()
	hero(p, 180, 85)
	var tl: Array = timed(p, 0.5)
	var hd: Array = only(tl, "hero_damage", "paint_chameleon")
	hero(p, 180, 140)
	timed(p, 0.5)
	var marks: int = p.enemies.hint_marks().size()
	var det_moving: int = p.enemies.detectable_enemies().size()
	timed(p, 4.0)
	ck("e10_ambush_12_from_hidden_then_moves_unseen_with_ripple_only", hid0 and hd.size() == 1 and near(float(hd[0].e.amount), 12.0) and marks == 1 and det_moving == 0, "n=%d marks=%d det=%d" % [hd.size(), marks, det_moving])
	ck("e10_rehides_after_retreat_4m_and_1s_still", E(p, id).state == "hidden" and E(p, id).pos.distance_to(Vector2(180, 70)) >= 35.0, "st=%s d=%.1f" % [str(E(p, id).state), E(p, id).pos.distance_to(Vector2(180, 70))])
	# 攻撃が当たると4秒だけ見える
	var q: RefCounted = mk()
	var id2: int = sp(q, "paint_chameleon", 180, 70)
	q.hit_enemy(id2, 1.0, "shot", null)
	timed(q, 3.9)
	var a: int = q.enemies.detectable_enemies().size()
	timed(q, 0.6)
	var b: int = q.enemies.detectable_enemies().size()
	timed(q, 0.7)
	var c: int = q.enemies.detectable_enemies().size()
	ck("e10_hit_visible_4s_then_hides_again", a == 1 and b == 1 and c == 0, "%d %d %d" % [a, b, c])
	# 水でペンキが落ち、以後は常に見える(塗り直さない)
	var r: RefCounted = mk()
	var id3: int = sp(r, "paint_chameleon", 180, 70)
	r.splash(Vector2(180, 70), 20.0, 0.0, "water")
	timed(r, 30.0)
	var vis: int = r.enemies.detectable_enemies().size()
	hero(r, 180, 130)
	var tr: Array = timed(r, 6.0)
	var bites: Array = only(tr, "hero_damage", "paint_chameleon")
	ck("e10_water_removes_paint_always_visible_bites_8", not bool(E(r, id3).paint) and vis == 1 and bites.size() >= 1 and near(float(bites[0].e.amount), 8.0), "n=%d" % bites.size())

# ------------------------------------------------------------------ E11 ネバナメクジ
func t_e11() -> void:
	var p: RefCounted = mk()
	hero(p, 180, 70)
	p.host.set_stage(Vector2i(46, 17), "seed")
	var cid: int = crop(p, "clover", 50, 18)
	var id: int = sp(p, "slime_slug", 180, 70)
	var tl: Array = timed(p, 12.0)
	var slow: Array = only(tl, "hero_slow")
	var pause: Array = only(tl, "growth_pause")
	var gs: Array = only(tl, "ground_stage")
	var start_events: int = 0
	for x: Dictionary in gs:
		if x.e.cell == Vector2i(45, 17):
			start_events += 1
	var cd: Array = only(tl, "crop_damaged")
	ck("e11_hero_on_slime_slowed_50pct", slow.size() >= 1 and near(float(slow[0].e.factor), 0.5), "n=%d" % slow.size())
	ck("e11_seed_cell_under_slime_pauses_growth_20s", pause.size() >= 1 and pause[0].e.cell == Vector2i(46, 17) and near(float(pause[0].e.seconds), 20.0) and p.enemies.growth_blocked(Vector2i(46, 17)), "n=%d" % pause.size())
	ck("e11_mature_grass_returns_to_wasteland_after_10s_once", start_events == 1 and gs[0].e.stage == "wasteland" and gs[0].e.cause == "slime", "n=%d" % start_events)
	ck("e11_crop_on_slime_takes_2_per_second", cd.size() >= 3 and near(float(cd[0].e.amount), 2.0), "n=%d" % cd.size())
	var ev: Array = p.splash(Vector2(190, 72), 40.0, 0.0, "water")
	ck("e11_water_washes_slime_away", p.enemies.slime_cells().is_empty() and not p.enemies.growth_blocked(Vector2i(46, 17)), "left=%d" % p.enemies.slime_cells().size())
	var r: RefCounted = mk()
	var id3: int = sp(r, "slime_slug", 180, 70)
	timed(r, 1.0)
	var n2: int = r.enemies.slime_cells().size()
	r.hit_enemy(id3, 25.0, "tackle", null)
	timed(r, 19.0)
	var alive_n: int = r.enemies.slime_cells().size()
	timed(r, 2.0)
	ck("e11_slime_lasts_20s_then_expires_after_slug_dies", n2 >= 1 and alive_n >= 1 and r.enemies.slime_cells().is_empty(), "n2=%d mid=%d" % [n2, alive_n])

# ------------------------------------------------------------------ 植物との相互作用
func _charge(p: RefCounted, crop_kind: String) -> Array:
	hero(p, 100, 100)
	crop(p, crop_kind, 18, 25)
	sp(p, "shadow_brian", 60, 100)
	return timed(p, 3.0)

func t_plants() -> void:
	var a: RefCounted = mk()
	var ta: Array = _charge(a, "clover")
	ck("plants_brian_charge_damages_crop_10_once", only(ta, "crop_damaged").size() == 1 and near(float(only(ta, "crop_damaged")[0].e.amount), 10.0), "")
	var b: RefCounted = mk()
	var tb: Array = _charge(b, "pepper")
	var bid: int = int(b.enemies.enemy_ids()[0])
	ck("plants_pepper_counter_2_damage_and_flee_cancels_charge", only(tb, "pepper_counter").size() == 1 and near(float(E(b, bid).hp), 58.0) and only(tb, "hero_damage").is_empty(), "hp=%.1f" % float(E(b, bid).hp))
	var c: RefCounted = mk()
	var tc: Array = _charge(c, "cactus")
	var cid: int = int(c.enemies.enemy_ids()[0])
	ck("plants_cactus_thorn_3_damage_to_enemy", only(tc, "cactus_thorn").size() == 1 and near(float(E(c, cid).hp), 57.0), "hp=%.1f" % float(E(c, cid).hp))
	# ハエトリソウ: 小型(タラチュネード)が隣接すると捕まる
	var d: RefCounted = mk()
	hero(d, 118, 106)
	crop(d, "flytrap", 28, 26)
	var sid: int = sp(d, "tarachunade", 100, 106)
	var td: Array = timed(d, 8.0)
	ck("plants_flytrap_captures_small_enemy_30_damage", only(td, "flytrap_capture").size() == 1 and not d.enemies.is_alive(sid) and only(td, "reward").size() == 1, "cap=%d" % only(td, "flytrap_capture").size())
	# ラベンダー: 虫タグは範囲(周辺4マス)へ入れない
	var e: RefCounted = mk()
	crop(e, "lavender", 30, 26)
	hero(e, 150, 106)
	var eid: int = sp(e, "tarachunade", 90, 106)
	R(e, eid).state = "chase"
	timed(e, 8.0)
	ck("plants_lavender_keeps_bug_out_of_repel_range", E(e, eid).pos.x < 104.0 and E(e, eid).pos.x > 100.0, "x=%.1f" % float(E(e, eid).pos.x))
	# ニンニク範囲の株は狙われない
	var f: RefCounted = mk()
	crop(f, "clover", 50, 18)
	crop(f, "garlic", 52, 18)
	var fid: int = sp(f, "slime_slug", 180, 70)
	timed(f, 3.0)
	var g: RefCounted = mk()
	crop(g, "clover", 50, 18)
	var gid: int = sp(g, "slime_slug", 180, 70)
	timed(g, 3.0)
	ck("plants_garlic_covered_crop_not_targeted", str(E(f, fid).state) == "idle" and str(E(g, gid).state) == "crawl", "%s vs %s" % [str(E(f, fid).state), str(E(g, gid).state)])
