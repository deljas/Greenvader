extends SceneTree
## 第2弾の栽培植物8種(P29〜P36)の規則の自己検証(入口スクリプト)。1条件1回、時間は早送り。
## 実行(隔離プロジェクトのみ): Godot --headless --path C:/godot/greenvader_content_sandbox --script res://tests/content_pack/self2/crops2_logic.gd
const Lab: GDScript = preload("res://scripts/content_pack/lab/lab_host.gd")
const Pack: GDScript = preload("res://scripts/content_pack/content_pack.gd")
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")
const OUT_DIR: String = "res://evidence/content_pack/self2"

var checks: Array = []

func ck(name: String, ok: bool, detail: String = "") -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})

func near(a: float, b: float, eps: float = 1e-6) -> bool:
	return absf(a - b) <= eps * maxf(1.0, absf(b))

func mk(seed: int = 1) -> RefCounted:
	return Pack.new(Lab.new(), seed)

func sp(p: RefCounted, kind: String, x: int, y: int, mature: bool = true, watered: bool = true) -> int:
	var cost: int = int(p.crops.def_of(kind).cost)
	var r: Dictionary = p.crops.spawn_crop(kind, Vector2i(x, y), cost, {"mature": mature, "watered": watered})
	return int(r.id) if bool(r.ok) else -1

func rate(p: RefCounted, id: int) -> float:
	return float(p.crops.production_info(id).rate)

func cond(p: RefCounted, id: int) -> float:
	return float(p.crops.production_info(id).condition)

func evs(events: Array, type: String) -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if e.type == type:
			out.append(e)
	return out

func adv(p: RefCounted, secs: float) -> Array:
	var all: Array = []
	var left: float = secs
	while left > 1e-9:
		var s: float = minf(left, 5.0)
		all.append_array(p.advance(s))
		left -= s
	return all

func _initialize() -> void:
	t_defs()
	t_primrose()
	t_dandelion()
	t_mimosa()
	t_kudzu()
	t_loofah()
	t_apple()
	t_balsam()
	var fails: int = 0
	for c: Dictionary in checks:
		print("%s %s %s" % [c.status, c.name, c.detail])
		if c.status != "PASS":
			fails += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/crops2_logic.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "crops2_logic", "total": checks.size(), "failed": fails, "checks": checks}, "\t"))
	f.close()
	print("crops2_logic total=%d failed=%d" % [checks.size(), fails])
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------ 定義
func t_defs() -> void:
	var p: RefCounted = mk()
	var table: Dictionary = {
		"evening_primrose": ["P29", 1, 25, 3.0, 30, 30], "dandelion": ["P30", 1, 20, 1.0, 25, 20], "mimosa": ["P31", 1, 25, 3.0, 30, 40],
		"kudzu": ["P32", 1, 20, 1.0, 30, 40], "loofah": ["P33", 1, 25, 1.5, 35, 30], "hinoki": ["P34", 3, 120, 4.0, 150, 150],
		"apple": ["P35", 2, 60, 2.0, 90, 80], "balsam": ["P36", 1, 20, 1.5, 25, 25]}
	var bad: Array = []
	for k: String in table:
		var d: Dictionary = p.crops.def_of(k)
		var t: Array = table[k]
		if d.is_empty() or d.id != t[0] or int(d.size[0]) != t[1] or int(d.cost) != t[2] or not near(float(d.rate_per_min), t[3]) or int(d.maturity) != t[4] or int(d.hp) != t[5]:
			bad.append(k)
	ck("defs_8_new_kinds_match_table", bad.is_empty(), str(bad))
	ck("defs_total_37_with_clover_parent", p.crops.defs.size() == 37, str(p.crops.defs.size()))
	var h: Dictionary = p.crops.place_crop("hinoki", Vector2i(20, 22))
	ck("hinoki_3x3_occupancy", bool(h.ok) and p.crops.crop_id_at(Vector2i(22, 24)) == int(h.id) and p.crops.crop_id_at(Vector2i(23, 24)) == 0, "")
	var a: Dictionary = p.crops.place_crop("apple", Vector2i(30, 24))
	ck("apple_2x2_occupancy", bool(a.ok) and p.crops.crop_id_at(Vector2i(31, 25)) == int(a.id) and p.crops.crop_id_at(Vector2i(32, 25)) == 0, "")
	ck("hinoki_needs_9_green", p.crops.place_crop("hinoki", Vector2i(43, 24)).reason == "requires_green", "")

# ------------------------------------------------------------------ P29 ツキミソウ
func t_primrose() -> void:
	var p: RefCounted = mk()
	var id: int = sp(p, "evening_primrose", 22, 24)
	p.host.day = false
	var night: float = rate(p, id)
	var flower_night: bool = p.crops.is_flower(p.crops.get_crop(id))
	p.host.day = true
	var day: float = rate(p, id)
	var flower_day: bool = p.crops.is_flower(p.crops.get_crop(id))
	ck("primrose_night_4_5_day_0_9_per_min", near(night * 60.0, 4.5) and near(day * 60.0, 0.9), "night=%.3f day=%.3f" % [night * 60.0, day * 60.0])
	ck("primrose_flower_tag_only_at_night", flower_night and not flower_day, "")
	# 夜の間だけ花タグ -> ミツバチ +20%(昼は+10%)
	p.host.hive_list = [{"cell": Vector2i(24, 24), "active": true}]
	var bonus_day: float = float(p.crops.production_info(id).bee_bonus)
	p.host.day = false
	var bonus_night: float = float(p.crops.production_info(id).bee_bonus)
	ck("primrose_bee_bonus_20pct_night_10pct_day", near(bonus_day, 0.10) and near(bonus_night, 0.20), "")
	p.host.day = false
	var before: float = 0.0
	var ev: Array = p.advance(10.0)
	var sum: float = 0.0
	for e: Dictionary in evs(ev, "seeds"):
		sum += float(e.amount)
	ck("primrose_production_events_at_night", near(sum, 0.075 * 1.2 * 10.0, 1e-4) and before == 0.0, "sum=%.4f" % sum)

# ------------------------------------------------------------------ P30 タンポポ
func t_dandelion() -> void:
	var p: RefCounted = mk()
	var id: int = sp(p, "dandelion", 22, 24)
	var rng0: int = p.rng.state
	var ev: Array = adv(p, 39.0)
	ck("dandelion_not_before_40s", evs(ev, "seed_sow").is_empty(), "")
	ev = adv(p, 2.0)
	ck("dandelion_no_candidate_no_fluff_no_rng", evs(ev, "seed_sow").is_empty() and p.rng.state == rng0, "all cells are grass")
	# 候補を用意する: A(距離4,有効) B(距離3,植物占有) C(距離2,近すぎ) D(距離7,遠すぎ) E(距離4,水面)
	var A: Vector2i = Vector2i(26, 24)
	for c: Vector2i in [A, Vector2i(25, 24), Vector2i(24, 24), Vector2i(29, 24)]:
		p.host.set_stage(c, "wasteland")
	sp(p, "bamboo", 25, 24)
	var n_crops: int = p.crops.crops.size()
	ev = adv(p, 40.0)   # time 80 で2回目
	var sow: Array = evs(ev, "seed_sow")
	ck("dandelion_sows_only_valid_cell_3_to_6_away", sow.size() == 1 and sow[0].cell == A and sow[0].source == "dandelion" and sow[0].crop_id == id, str(sow))
	ck("dandelion_no_stock_consumed_and_no_new_plant", sow.size() == 1 and sow[0].consume_stock == false and p.crops.crops.size() == n_crops, "")
	ev = adv(p, 20.0)
	ck("dandelion_interval_40s", evs(ev, "seed_sow").is_empty(), "")
	# 建物・水面は有効マスではない
	var q: RefCounted = mk()
	sp(q, "dandelion", 24, 16)
	q.host.set_stage(Vector2i(28, 16), "wasteland")   # 建物のマス(距離4)
	var ev2: Array = adv(q, 41.0)
	ck("dandelion_building_cell_not_valid", evs(ev2, "seed_sow").is_empty(), "")
	var w: RefCounted = mk()
	sp(w, "dandelion", 18, 5)
	w.host.set_stage(Vector2i(14, 5), "wasteland")    # 浅瀬(距離4)
	ck("dandelion_water_cell_not_valid", evs(adv(w, 41.0), "seed_sow").is_empty(), "")

# ------------------------------------------------------------------ P31 オジギソウ
func t_mimosa() -> void:
	var p: RefCounted = mk()
	var id: int = sp(p, "mimosa", 22, 24)
	var open_rate: float = rate(p, id)
	ck("mimosa_open_produces_3_per_min", near(open_rate * 60.0, 3.0), "")
	# 中立の敵は閉じさせない
	p.host.host_enemy_list = [{"id": 1, "pos": Vector2(90, 115), "neutral": true, "tags": ["bee"]}]
	adv(p, 2.0)
	ck("mimosa_neutral_does_not_close", not bool(p.crops.get_crop(id).ext.closed), "")
	# 2m(20px)以内の敵: 下端(y=100)から 18px
	p.host.host_enemy_list = [{"id": 2, "pos": Vector2(90, 118), "neutral": false, "tags": ["bug"]}]
	var ev: Array = adv(p, 1.0)
	ck("mimosa_closes_when_enemy_within_2m", bool(p.crops.get_crop(id).ext.closed) and evs(ev, "mimosa_closed").size() == 1, "")
	ck("mimosa_closed_production_zero", near(rate(p, id), 0.0), "")
	var hp0: float = float(p.crops.get_crop(id).hp)
	p.crops.damage_crop(id, 10.0)
	ck("mimosa_closed_damage_x0_2", near(hp0 - float(p.crops.get_crop(id).hp), 2.0), "")
	# 2m の外へ出ても4秒は閉じたまま、4秒後に開く
	p.host.host_enemy_list = [{"id": 2, "pos": Vector2(90, 125), "neutral": false, "tags": ["bug"]}]
	adv(p, 3.0)
	var still: bool = bool(p.crops.get_crop(id).ext.closed)
	ev = adv(p, 1.5)
	ck("mimosa_reopens_4s_after_enemy_leaves", still and not bool(p.crops.get_crop(id).ext.closed) and evs(ev, "mimosa_opened").size() == 1, "")
	ck("mimosa_open_production_restored", near(rate(p, id), open_rate), "")
	# 攻撃を受けても閉じる(最初の一撃は閉じる前の扱い)
	p.host.host_enemy_list = []
	var hp1: float = float(p.crops.get_crop(id).hp)
	p.crops.damage_crop(id, 10.0)
	var first: float = hp1 - float(p.crops.get_crop(id).hp)
	ck("mimosa_hit_closes_first_hit_full", near(first, 10.0) and bool(p.crops.get_crop(id).ext.closed), "")
	# カボチャ×0.7と乗算
	var q: RefCounted = mk()
	var m2: int = sp(q, "mimosa", 22, 24)
	sp(q, "pumpkin", 23, 24)
	q.host.host_enemy_list = [{"id": 2, "pos": Vector2(90, 118), "neutral": false, "tags": ["bug"]}]
	adv(q, 1.0)
	var h0: float = float(q.crops.get_crop(m2).hp)
	q.crops.damage_crop(m2, 10.0)
	ck("mimosa_closed_times_pumpkin_0_7", near(h0 - float(q.crops.get_crop(m2).hp), 10.0 * 0.7 * 0.2), "")
	# 実際の敵(窓口の敵一覧)でも閉じる
	var r: RefCounted = mk()
	var m3: int = sp(r, "mimosa", 22, 24)
	r.enemies.spawn("shadow_brian", Vector2(90, 118), "initial")
	r.advance(1.0)
	ck("mimosa_closes_for_real_enemy_from_enemy_system", bool(r.crops.get_crop(m3).ext.closed), "")

# ------------------------------------------------------------------ P32 クズ
func t_kudzu() -> void:
	var p: RefCounted = mk()
	var stock: Vector2i = Vector2i(22, 24)
	var id: int = sp(p, "kudzu", stock.x, stock.y)
	ck("kudzu_base_production_1_per_min", near(rate(p, id) * 60.0, 1.0), "")
	var ev: Array = adv(p, 14.0)
	ck("kudzu_no_root_before_15s", evs(ev, "kudzu_root_added").is_empty(), "")
	ev = adv(p, 1.0)
	var added: Array = evs(ev, "kudzu_root_added")
	ck("kudzu_first_root_adjacent_to_stock_at_15s", added.size() == 1 and (Grid.adjacent_cells(Rect2i(stock, Vector2i.ONE)).has(added[0].cell)), str(added))
	ck("kudzu_one_root_production_1_15", near(rate(p, id) * 60.0, 1.15), "%.4f" % (rate(p, id) * 60.0))
	adv(p, 15.0 * 30.0)
	var roots: Array = p.crops.root_cells(id)
	var within: bool = true
	for r: Vector2i in roots:
		if Grid.rect_distance(Rect2i(stock, Vector2i.ONE), Rect2i(r, Vector2i.ONE)) > 4:
			within = false
	ck("kudzu_max_24_roots", roots.size() == 24, str(roots.size()))
	ck("kudzu_roots_within_chebyshev_4", within, "")
	ck("kudzu_max_production_4_6_per_min", near(rate(p, id) * 60.0, 4.6), "%.4f" % (rate(p, id) * 60.0))
	var rc: Vector2i = roots[0]
	ck("kudzu_root_cell_occupied_for_other_plants", p.crops.place_crop("bamboo", rc).reason == "occupied" and p.crops.root_owner(rc) == id, "")
	ck("kudzu_root_walkable_enemy_slowed_0_6", p.host.is_walkable(rc) and near(p.crops.enemy_speed_mult(rc), 0.6) and near(p.crops.enemy_speed_mult(stock + Vector2i(8, 0)), 1.0), "")
	ck("kudzu_roots_not_counted_in_family", p.crops.family_count("kudzu") == 1 and p.crops.quote("kudzu") == 21, "quote=%d" % p.crops.quote("kudzu"))
	# 隣接する他種の基礎生産 x0.8(重複なし)
	var two_adj: Vector2i = Vector2i(-99, -99)
	var one_adj: Vector2i = Vector2i(-99, -99)
	for y: int in range(19, 30):
		for x: int in range(17, 28):
			var c: Vector2i = Vector2i(x, y)
			if not bool(p.crops.check_placement("bamboo", c).ok):
				continue
			var n: int = 0
			for ac: Vector2i in Grid.adjacent_cells(Rect2i(c, Vector2i.ONE)):
				if p.crops.root_owner(ac) != 0:
					n += 1
			if n >= 2 and two_adj.x < 0:
				two_adj = c
			if n == 1 and one_adj.x < 0:
				one_adj = c
	var b2: int = sp(p, "bamboo", two_adj.x, two_adj.y) if two_adj.x >= 0 else -1
	var b1: int = sp(p, "bamboo", one_adj.x, one_adj.y) if one_adj.x >= 0 else -1
	var far: int = sp(p, "bamboo", 36, 30)
	ck("kudzu_adjacent_other_kind_x0_8", b1 > 0 and near(cond(p, b1), 0.8) and near(cond(p, far), 1.0), "")
	ck("kudzu_multiple_adjacent_roots_not_stacked", b2 > 0 and near(cond(p, b2), 0.8), "")
	ck("kudzu_stock_itself_not_penalised", near(cond(p, id), 1.0 + 0.15 * 24.0), "")
	# 根の個別撤去(返還0)とモグラ用の食害
	var cnt: int = p.crops.root_cells(id).size()
	var rr: Dictionary = p.crops.remove_root(rc)
	ck("kudzu_remove_single_root_refund_0", bool(rr.ok) and int(rr.refund) == 0 and p.crops.root_cells(id).size() == cnt - 1 and p.crops.root_owner(rc) == 0, "")
	var eat: Array = p.crops.eat_root(roots[1])
	ck("kudzu_eat_root_event_for_mole", eat.size() == 1 and eat[0].type == "kudzu_root_removed" and eat[0].reason == "eaten" and p.crops.root_cells(id).size() == cnt - 2, "")
	# 株の喪失で根は全消滅(返還0、占有解除)
	var left: int = p.crops.root_cells(id).size()
	var dev: Array = p.crops.damage_crop(id, 9999.0)
	ck("kudzu_stock_lost_removes_all_roots", evs(dev, "kudzu_root_removed").size() == left and p.crops.root_cells().is_empty() and bool(p.crops.place_crop("bamboo", roots[2]).ok) and p.crops.root_owner(roots[2]) == 0, "left=%d" % left)
	# 手動撤去でも根は消え、返還は株の分だけ
	var q: RefCounted = mk()
	var k2: int = sp(q, "kudzu", 22, 24)
	adv(q, 60.0)
	var nroots: int = q.crops.root_cells(k2).size()
	var rm: Dictionary = q.crops.remove_crop(k2, "manual")
	ck("kudzu_manual_remove_clears_roots_refund_stock_only", nroots == 4 and int(rm.refund) == 4 and q.crops.root_cells().is_empty(), "n=%d refund=%d" % [nroots, int(rm.refund)])
	# 通常の栽培条件: 荒地(緑化されていない)には根を伸ばせない
	var w: RefCounted = mk()
	var k3: int = sp(w, "kudzu", 46, 23)
	adv(w, 400.0)
	var any_waste: bool = false
	for r2: Vector2i in w.crops.root_cells(k3):
		if r2.y >= 24 and r2.x >= 44:
			any_waste = true
	ck("kudzu_roots_only_on_plantable_cells", w.crops.root_cells(k3).size() > 0 and not any_waste, "n=%d" % w.crops.root_cells(k3).size())

# ------------------------------------------------------------------ P33 ヘチマ
func t_loofah() -> void:
	var p: RefCounted = mk()
	var id: int = sp(p, "loofah", 22, 24, true, false)
	ck("loofah_empty_before_water", p.crops.loofah_water(id) == 0, "")
	p.crops.set_watered(id, true)
	ck("loofah_gets_10_when_watered", p.crops.loofah_water(id) == 10, "")
	var near_b: int = sp(p, "bamboo", 24, 24, false, false)
	var far_b: int = sp(p, "bamboo", 30, 24, false, false)
	var ev: Array = adv(p, 9.0)
	ck("loofah_no_water_before_10s", evs(ev, "water_crop").is_empty(), "")
	ev = adv(p, 1.0)
	var wc: Array = evs(ev, "water_crop")
	ck("loofah_waters_unwatered_crop_within_3", wc.size() == 1 and wc[0].crop_id == near_b and bool(p.crops.get_crop(near_b).watered) and not bool(p.crops.get_crop(far_b).watered) and p.crops.loofah_water(id) == 9, str(wc))
	# 栽培植物がなければ、未給水で成長中の草を1マス
	var cell: Vector2i = Vector2i(23, 26)
	p.host.set_stage(cell, "sprout")
	p.host.set_stage(Vector2i(22, 28), "sprout")   # 距離4: 範囲外
	ev = adv(p, 10.0)
	var wcell: Array = evs(ev, "water_cell")
	ck("loofah_waters_growing_grass_cell_when_no_crop", wcell.size() == 1 and wcell[0].cell == cell and p.crops.loofah_water(id) == 8, str(wcell))
	p.host.watered_cells[cell] = true
	ev = adv(p, 10.0)
	ck("loofah_no_target_no_consumption", evs(ev, "water_cell").is_empty() and evs(ev, "water_crop").is_empty() and p.crops.loofah_water(id) == 8, "")
	# 水が当たると10に補充(10未満のときだけ)
	var rf: Array = p.water_landed([Vector2i(22, 24)])
	ck("loofah_refill_to_10_on_water_hit", evs(rf, "loofah_refill").size() == 1 and p.crops.loofah_water(id) == 10, "")
	ck("loofah_no_refill_event_when_full", evs(p.water_landed([Vector2i(22, 24)]), "loofah_refill").is_empty(), "")
	# 空のヘチマは未給水と同優先でスプリンクラーの対象
	for y: int in range(21, 24):
		for x: int in range(19, 22):
			p.host.set_stage(Vector2i(x, y), "sprout")
	adv(p, 130.0)
	ck("loofah_drains_to_0", p.crops.loofah_water(id) == 0, "water=%d" % p.crops.loofah_water(id))
	var tg: Array = p.crops.sprinkler_targets()
	ck("loofah_empty_listed_for_sprinkler_like_unwatered", tg.has(id) and tg.has(far_b) and bool(p.crops.get_crop(id).watered), str(tg))
	p.water_landed([Vector2i(22, 24)])
	ck("loofah_removed_from_targets_after_refill", not p.crops.sprinkler_targets().has(id) and p.crops.sprinkler_targets().has(far_b), "")

# ------------------------------------------------------------------ P35 リンゴ
func t_apple() -> void:
	var p: RefCounted = mk()
	var id: int = sp(p, "apple", 22, 24)
	var rect: Rect2i = Rect2i(22, 24, 2, 2)
	var ev: Array = adv(p, 29.0)
	ck("apple_no_fruit_before_30s", p.crops.fruit_list().is_empty(), "")
	ev = adv(p, 1.0)
	var fd: Array = evs(ev, "fruit_dropped")
	ck("apple_drops_one_adjacent_fruit_at_30s", fd.size() == 1 and Grid.adjacent_cells(rect).has(fd[0].cell), str(fd))
	adv(p, 120.0)
	var fl: Array = p.crops.fruit_list()
	var cells: Dictionary = {}
	for f: Dictionary in fl:
		cells[f.cell] = true
	ck("apple_max_3_fruits_distinct_cells", fl.size() == 3 and cells.size() == 3, str(fl.size()))
	ck("apple_fruit_is_decoy_not_pickup", p.crops.pickups.is_empty(), "")
	var tags: Array = ["beast", "herbivore"]
	var center: Vector2 = Vector2(96, 104)
	var best: Dictionary = p.crops.nearest_attracting_fruit(tags, center, 100.0)
	ck("apple_attracts_herbivore_not_others", not best.is_empty() and p.crops.nearest_attracting_fruit(["beast"], center, 100.0).is_empty(), "")
	# 安定した地域の落果は引き寄せ対象外
	p.host.set_stable_rect(Rect2i(best.cell, Vector2i.ONE))
	var other: Dictionary = p.crops.nearest_attracting_fruit(tags, center, 100.0)
	ck("apple_stable_region_fruit_excluded_only_that_one", not other.is_empty() and other.id != best.id, "")
	# 食べて消す
	var eaten: Array = p.crops.consume_fruit(int(other.id), 9)
	ck("apple_consume_fruit_removes_it", eaten.size() == 1 and eaten[0].type == "fruit_eaten" and p.crops.fruit_list().size() == 2, "")
	ev = adv(p, 31.0)
	ck("apple_refills_after_consumption", p.crops.fruit_list().size() == 3, "")
	# 実の上に植えると、その実は消える
	var fcell: Vector2i = p.crops.fruit_list()[0].cell
	var pl: Dictionary = p.crops.place_crop("bamboo", fcell)
	ck("apple_planting_on_fruit_removes_fruit", bool(pl.ok) and evs(pl.events, "fruit_removed").size() == 1 and p.crops.fruit_list().size() == 2, str(pl.get("reason")))
	ck("apple_id_valid", id > 0, "")

# ------------------------------------------------------------------ P36 ホウセンカ
func t_balsam() -> void:
	var p: RefCounted = mk()
	var id: int = sp(p, "balsam", 22, 24)
	# 周り2マスの有効マス: 近い5つ(+範囲外1つ)
	var cands: Array = [Vector2i(20, 24), Vector2i(21, 22), Vector2i(24, 26), Vector2i(24, 24), Vector2i(22, 22)]
	for c: Vector2i in cands:
		p.host.set_stage(c, "wasteland")
	p.host.set_stage(Vector2i(25, 24), "wasteland")   # 距離3: 範囲外
	# 実際の敵(シカ)を 1.4m 以内に置く。もう1体は半径2mの外、中立の巣は範囲内でも無傷
	var deer_in: int = p.enemies.spawn("shadow_brian", Vector2(106, 98), "initial")
	var deer_out: int = p.enemies.spawn("tarachunade", Vector2(150, 98), "initial")
	var hive: int = p.enemies.spawn("honeybee_hive", Vector2(100, 110), "initial")
	var hp_in: float = float(p.enemies.get_enemy(deer_in).hp)
	var hp_out: float = float(p.enemies.get_enemy(deer_out).hp)
	var hp_hive: float = float(p.enemies.get_enemy(hive).hp)
	var ev: Array = p.advance(1.0)
	var burst: Array = evs(ev, "balsam_burst")
	ck("balsam_bursts_when_enemy_within_1_5m", burst.size() == 1 and burst[0].cause == "enemy" and near(float(burst[0].radius_px), 20.0) and near(float(burst[0].damage), 4.0), str(burst))
	ck("balsam_burst_4_damage_in_radius_2m_only_non_neutral", near(hp_in - float(p.enemies.get_enemy(deer_in).hp), 4.0) and near(hp_out - float(p.enemies.get_enemy(deer_out).hp), 0.0) and near(hp_hive - float(p.enemies.get_enemy(hive).hp), 0.0), "")
	var sow: Array = evs(ev, "seed_sow")
	var seen: Dictionary = {}
	var ok_cells: bool = true
	for s: Dictionary in sow:
		seen[s.cell] = true
		if not cands.has(s.cell) or s.consume_stock != false or s.source != "balsam":
			ok_cells = false
	ck("balsam_sows_max_3_distinct_valid_cells_no_stock", sow.size() == 3 and seen.size() == 3 and ok_cells, str(sow.size()))
	# 間隔8秒: すぐ次は出ない。8秒後に敵がまだ近ければまた出る
	p.enemies.get_enemy(deer_in)   # 参照のみ
	var ev2: Array = p.advance(1.0)
	ck("balsam_enemy_trigger_cooldown_8s", evs(ev2, "balsam_burst").is_empty(), "")
	var q: RefCounted = mk()
	var b2: int = sp(q, "balsam", 22, 24)
	q.host.host_enemy_list = [{"id": 1, "pos": Vector2(106, 98), "neutral": false, "tags": []}]
	var bursts_at: Array = []
	for i: int in range(18):
		var e: Array = q.advance(1.0)
		if not evs(e, "balsam_burst").is_empty():
			bursts_at.append(i + 1)
	ck("balsam_repeats_every_8s_while_enemy_near", bursts_at == [1, 9, 17], str(bursts_at))
	# 敵がいなくても20秒ごと
	var r: RefCounted = mk()
	sp(r, "balsam", 22, 24)
	var e1: Array = adv(r, 19.0)
	var e2: Array = adv(r, 1.0)
	ck("balsam_periodic_every_20s", evs(e1, "balsam_burst").is_empty() and evs(e2, "balsam_burst").size() == 1 and evs(e2, "balsam_burst")[0].cause == "periodic", "")
	# 候補が2マスなら2マス
	var s2: RefCounted = mk()
	sp(s2, "balsam", 22, 24)
	s2.host.set_stage(Vector2i(20, 24), "wasteland")
	s2.host.set_stage(Vector2i(24, 24), "wasteland")
	ck("balsam_sows_only_as_many_as_valid", evs(adv(s2, 20.0), "seed_sow").size() == 2, "")
	ck("balsam_ids", id > 0 and b2 > 0, "")
