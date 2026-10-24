extends SceneTree
## 独立検証: 植物(カタログ3節)。期待値はカタログの数値から手計算。入口スクリプト。
const Lab: GDScript = preload("res://scripts/content_pack/lab/lab_host.gd")
const Pack: GDScript = preload("res://scripts/content_pack/content_pack.gd")
const OUT_DIR: String = "res://evidence/content_pack/independent"

var checks: Array = []

func ck(name: String, ok: bool, detail: String = "") -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})

func near(a: float, b: float, eps: float = 1e-6) -> bool:
	return absf(a - b) <= eps

func mk(seed: int = 7) -> RefCounted:
	return Pack.new(Lab.new(), seed)

func put(p: RefCounted, kind: String, x: int, y: int, mature: bool = true, paid: int = 0) -> int:
	var r: Dictionary = p.crops.spawn_crop(kind, Vector2i(x, y), paid, {"mature": mature, "watered": true, "skip_check": true})
	return int(r.id) if bool(r.ok) else -1

func rate(p: RefCounted, id: int) -> float:
	return float(p.crops.production_info(id).rate)

func evs(events: Array, type: String) -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if e.type == type:
			out.append(e)
	return out

func run_for(p: RefCounted, secs: float, dt: float = 1.0) -> Array:
	var out: Array = []
	var n: int = int(round(secs / dt))
	for i: int in range(n):
		out.append_array(p.advance(dt))
	return out

func rt(d: Dictionary) -> Dictionary:
	var v: Variant = JSON.parse_string(JSON.stringify(d))
	return v if typeof(v) == TYPE_DICTIONARY else {}

func _initialize() -> void:
	t_placement()
	t_poison()
	t_variants()
	t_gold_bee()
	t_conditions()
	t_misc()
	t_save()
	var fails: int = 0
	var lines: Array = []
	for c: Dictionary in checks:
		var line: String = "%s %s %s" % [c.status, c.name, c.detail]
		print(line)
		lines.append(line)
		if c.status != "PASS":
			fails += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/crops_v.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "crops_v", "total": checks.size(), "failed": fails, "checks": checks}, "\t"))
	f.close()
	print("crops_v total=%d failed=%d" % [checks.size(), fails])
	quit(1 if fails > 0 else 0)

# 条件3/4: 配置制約と占有
func t_placement() -> void:
	var p: RefCounted = mk()
	var C: RefCounted = p.crops
	# ワサビ: 清水(x2..6,y14..18)から距離2以内。(4,20)は距離2、(4,21)は3。浅瀬だけの近くは不可
	ck("wasabi_ok_dist2", bool(C.check_placement("wasabi", Vector2i(4, 20)).ok), "")
	ck("wasabi_fail_dist3", C.check_placement("wasabi", Vector2i(4, 21)).reason == "needs_clean_water", str(C.check_placement("wasabi", Vector2i(4, 21))))
	ck("wasabi_fail_near_plain_shallow_only", not bool(C.check_placement("wasabi", Vector2i(17, 5)).ok), "")
	ck("wasabi_cheb_diag_corner", bool(C.check_placement("wasabi", Vector2i(8, 20)).ok), "(8,20): clean(6,18)へ dx2 dy2")
	ck("wasabi_cheb_diag_corner_far", not bool(C.check_placement("wasabi", Vector2i(9, 21)).ok), "dx3")
	# スイカ6x6
	ck("watermelon_ok_36cells", bool(C.check_placement("giant_watermelon", Vector2i(20, 20)).ok), "")
	var wm: Dictionary = C.place_crop("giant_watermelon", Vector2i(20, 20))
	ck("watermelon_placed_paid_450", bool(wm.ok) and int(wm.paid) == 450, str(wm.get("paid")))
	var all36: bool = true
	for y: int in range(20, 26):
		for x: int in range(20, 26):
			if C.crop_id_at(Vector2i(x, y)) != int(wm.id):
				all36 = false
	ck("watermelon_occupies_exactly_36", all36 and C.crop_id_at(Vector2i(26, 20)) == 0 and C.crop_id_at(Vector2i(20, 26)) == 0 and C.crop_id_at(Vector2i(19, 20)) == 0, "")
	ck("watermelon_second_price_473", C.quote("giant_watermelon") == 473, str(C.quote("giant_watermelon")))
	ck("overlap_one_cell_blocks_clover", C.check_placement("clover", Vector2i(25, 25)).reason == "occupied", "")
	ck("overlap_one_cell_blocks_watermelon", not bool(C.check_placement("giant_watermelon", Vector2i(25, 25)).ok), "")
	var q: RefCounted = mk()
	ck("watermelon_building_one_col_fails", not bool(q.crops.check_placement("giant_watermelon", Vector2i(24, 16)).ok), "x28は建物")
	ck("watermelon_waste_two_cols_fails", not bool(q.crops.check_placement("giant_watermelon", Vector2i(40, 24)).ok), "x44,45は荒地")
	ck("watermelon_edge_outside", q.crops.check_placement("giant_watermelon", Vector2i(60, 20)).reason == "outside_map", "")
	var q2: RefCounted = mk()
	q2.host.set_terrain(Vector2i(25, 25), q2.host.WASTE)
	ck("watermelon_one_nongreen_cell_fails", q2.crops.check_placement("giant_watermelon", Vector2i(20, 20)).reason == "requires_green", "")
	var q3: RefCounted = mk()
	q3.host.blocked_cells[Vector2i(20, 20)] = true
	ck("watermelon_one_blocked_cell_fails", q3.crops.check_placement("giant_watermelon", Vector2i(20, 20)).reason == "occupied", "")
	ck("watermelon_origin_shift_ok", bool(q3.crops.check_placement("giant_watermelon", Vector2i(21, 20)).ok), "")
	# サボテン
	var cp: RefCounted = mk()
	var cr: Dictionary = cp.crops.place_crop("cactus", Vector2i(46, 26))
	ck("cactus_on_wasteland_ok_with_seed_event", bool(cr.ok) and evs(cr.events, "ground_seed").size() == 1, str(cr.get("reason")))
	ck("clover_on_wasteland_fails", cp.crops.check_placement("clover", Vector2i(48, 26)).reason == "requires_green", "")
	ck("cactus_on_water_fails", not bool(cp.crops.check_placement("cactus", Vector2i(5, 5)).ok), "")
	ck("cactus_on_building_fails", not bool(cp.crops.check_placement("cactus", Vector2i(30, 15)).ok), "")
	ck("cactus_on_junk_fails", not bool(cp.crops.check_placement("cactus", Vector2i(50, 6)).ok), "")
	ck("cactus_on_green_ok", bool(cp.crops.check_placement("cactus", Vector2i(20, 30)).ok), "")
	# ハス
	var lp: RefCounted = mk()
	ck("lotus_shore_ok", bool(lp.crops.check_placement("lotus", Vector2i(14, 2)).ok), "")
	ck("lotus_south_shore_ok", bool(lp.crops.check_placement("lotus", Vector2i(5, 10)).ok), "")
	ck("lotus_mid_water_no_shore_fails", lp.crops.check_placement("lotus", Vector2i(5, 5)).reason == "needs_shore", "")
	ck("lotus_one_land_cell_fails", lp.crops.check_placement("lotus", Vector2i(15, 10)).reason == "not_water", "")
	ck("lotus_on_land_fails", lp.crops.check_placement("lotus", Vector2i(30, 25)).reason == "not_water", "")
	var lr: Dictionary = lp.crops.place_crop("lotus", Vector2i(14, 2))
	ck("lotus_placed_occupies_4", bool(lr.ok) and lp.crops.crop_id_at(Vector2i(15, 3)) == int(lr.id), "")
	ck("lotus_overlap_fails", not bool(lp.crops.check_placement("lotus", Vector2i(14, 3)).ok), "")
	ck("lotus_does_not_make_green", not lp.host.is_green(Vector2i(14, 2)), "")
	# イネ
	var rp: RefCounted = mk()
	ck("rice_dist2_water_ok", bool(rp.crops.check_placement("rice", Vector2i(17, 5)).ok), "")
	ck("rice_dist3_fails", rp.crops.check_placement("rice", Vector2i(18, 5)).reason == "needs_water", "")
	ck("rice_near_clean_water_ok", bool(rp.crops.check_placement("rice", Vector2i(4, 20)).ok), "")
	# 任意設置不可
	ck("four_leaf_not_placeable", p.crops.place_crop("four_leaf_clover", Vector2i(30, 30)).reason == "not_placeable", "")
	ck("golden_four_not_placeable", p.crops.place_crop("golden_four_leaf", Vector2i(30, 30)).reason == "not_placeable", "")
	# 敵の占有: ミミック・巣・アリ塚
	var ep: RefCounted = mk()
	ep.enemies.spawn("mimic_cabbage", Vector2(122, 122))   # cell (30,30)
	ck("mimic_cell_blocks_planting", ep.crops.check_placement("clover", Vector2i(30, 30)).reason == "occupied", str(ep.crops.check_placement("clover", Vector2i(30, 30))))
	ck("mimic_neighbor_cell_ok", bool(ep.crops.check_placement("clover", Vector2i(31, 30)).ok), "")
	ep.enemies.spawn("honeybee_hive", Vector2(82, 82))      # cell(20,20)
	ep.enemies.spawn("ant_hill", Vector2(162, 82))          # cell(40,20)付近の2x2
	var hv_cell: Vector2i = Vector2i(20, 20)
	ck("hive_cell_blocks_planting", ep.crops.check_placement("clover", hv_cell).reason == "occupied", str(ep.crops.check_placement("clover", hv_cell)))
	var ant_ok: bool = false
	for st: Dictionary in ep.enemies.structure_rects():
		if str(st.get("kind", "")) == "ant_hill":
			ant_ok = true
			var r: Rect2i = st.rect if st.has("rect") else Rect2i()
			ck("anthill_2x2_blocks", r.size == Vector2i(2, 2) and ep.crops.check_placement("clover", r.position + Vector2i(1, 1)).reason == "occupied", str(st))
	ck("anthill_found_in_structures", ant_ok, str(ep.enemies.structure_rects()))

# 条件5: 毒
func t_poison() -> void:
	var p: RefCounted = mk()
	var ol: int = put(p, "oleander", 20, 20)      # x20..21,y20..21
	var in_c: int = put(p, "clover", 24, 20)      # dist 3
	var out_c: int = put(p, "clover", 25, 20)     # dist 4
	var ol2: int = put(p, "oleander", 20, 23)     # 他のキョウチクトウ(dist 2)
	var wm: int = put(p, "giant_watermelon", 26, 30)
	p.host.helper_list = [{"id": 1, "pos": Vector2(90, 90), "hp": 50.0, "max_hp": 50.0}]
	p.host.set_stage(Vector2i(22, 22), "grass")
	var ev: Array = run_for(p, 14.5, 0.5)
	var c_in: Dictionary = p.crops.get_crop(in_c)
	ck("poison_two_ticks_by_14.5", int(c_in.poison) == 2 and not c_in.is_empty(), str(c_in.get("poison")))
	ev.append_array(run_for(p, 0.5, 0.5))
	ck("poison_dies_at_15s", p.crops.get_crop(in_c).is_empty(), "")
	var rem: Array = evs(ev, "crop_removed")
	ck("poison_removal_reason_refund0", rem.size() == 1 and rem[0].reason == "poison" and int(rem[0].refund) == 0, str(rem))
	ck("poison_releases_occupancy", p.crops.crop_id_at(Vector2i(24, 20)) == 0 and p.crops.check_placement("clover", Vector2i(24, 20)).ok, "")
	ck("poison_out_of_range_unaffected", not p.crops.get_crop(out_c).is_empty() and int(p.crops.get_crop(out_c).poison) == 0, "")
	run_for(p, 60.0, 1.0)
	ck("oleander_not_poisoned_by_oleander", not p.crops.get_crop(ol).is_empty() and not p.crops.get_crop(ol2).is_empty() and int(p.crops.get_crop(ol).poison) == 0, "")
	ck("poison_helper_and_grass_unchanged", p.host.helper_list[0].hp == 50.0 and p.host.grass_stage(Vector2i(22, 22)) == "grass", "")
	# 巨大スイカは矩形が近いので毒を受ける(26..31,30..35は oleander(20..21,23..24)からdy6 → 範囲外)。別シナリオ
	var q: RefCounted = mk()
	put(q, "oleander", 20, 20)
	var bw: int = put(q, "giant_watermelon", 24, 20)   # dist 3(矩形)
	run_for(q, 15.0, 0.5)
	ck("giant_watermelon_poisoned_by_rect_distance", q.crops.get_crop(bw).is_empty(), "")
	# 複数のキョウチクトウでも1回の判定で+1
	var m: RefCounted = mk()
	put(m, "oleander", 20, 20)
	put(m, "oleander", 24, 22)
	var mc: int = put(m, "clover", 22, 23)    # 両方の範囲内
	run_for(m, 10.0, 0.5)
	var mcd: Dictionary = m.crops.get_crop(mc)
	ck("two_sources_still_plus1_per_tick", not mcd.is_empty() and int(mcd.poison) == 2, str(mcd.get("poison")))
	run_for(m, 5.0, 0.5)
	ck("two_sources_dies_at_15_not_earlier", m.crops.get_crop(mc).is_empty(), "")
	# ニンニクの保護
	var g: RefCounted = mk()
	put(g, "oleander", 20, 20)
	var gl: int = put(g, "garlic", 24, 20)        # 毒範囲内(dist3)、ニンニク自身も保護
	var prot: int = put(g, "clover", 24, 22)      # ニンニク範囲(dist<=3)
	var unprot: int = put(g, "clover", 24, 24)    # oleander(rect y20..21)からdy3, garlic(24,20)からdy4 → 範囲外
	var unprot_in: int = put(g, "clover", 23, 24)  # dx2,dy3 oleander範囲内; garlic(24,20)からdy4
	run_for(g, 60.0, 1.0)
	ck("garlic_protects_self", not g.crops.get_crop(gl).is_empty() and int(g.crops.get_crop(gl).poison) == 0, "")
	ck("garlic_protects_in_range", not g.crops.get_crop(prot).is_empty() and int(g.crops.get_crop(prot).poison) == 0, "")
	ck("garlic_range_edge_unprotected_dies", g.crops.get_crop(unprot_in).is_empty(), "")
	# 未成熟ニンニクは守らない
	var g2: RefCounted = mk()
	put(g2, "oleander", 20, 20)
	var im: int = put(g2, "garlic", 24, 20, false)
	var tgt: int = put(g2, "clover", 24, 22)
	run_for(g2, 14.0, 0.5)
	ck("immature_garlic_no_protection", int(g2.crops.get_crop(tgt).poison) == 2, str(g2.crops.get_crop(tgt).get("poison")))
	# 未成熟キョウチクトウは毒を出さない
	var u: RefCounted = mk()
	put(u, "oleander", 20, 20, false)
	var ut: int = put(u, "clover", 24, 20)
	run_for(u, 10.0, 0.5)
	ck("immature_oleander_no_poison", int(u.crops.get_crop(ut).poison) == 0, "")
	run_for(u, 40.0, 0.5)
	ck("oleander_after_mature_poisons_then_kills", u.crops.get_crop(ut).is_empty(), "")
	# 撤去で蓄積が戻る
	var r: RefCounted = mk()
	var ro: int = put(r, "oleander", 20, 20)
	var rc: int = put(r, "clover", 24, 20)
	run_for(r, 10.5, 0.5)
	var before: int = int(r.crops.get_crop(rc).poison)
	r.crops.remove_crop(ro, "manual")
	run_for(r, 5.0, 0.5)
	ck("poison_resets_after_source_removed", before == 2 and int(r.crops.get_crop(rc).poison) == 0, str(before))
	# 毒枯死の現存数減少
	ck("poison_death_reduces_family_count", mk().crops.family_count("clover") == 0 and p.crops.family_count("clover") == 1, str(p.crops.family_count("clover")))

# 条件6: 四葉・黄金の四葉
func t_variants() -> void:
	var p: RefCounted = mk(11)
	var ids: Array = []
	var paid_by: Dictionary = {}
	for i: int in range(600):
		var x: int = 17 + (i % 40)
		var y: int = 20 + int(i / 40)
		var r: Dictionary = p.crops.spawn_crop("clover", Vector2i(x, y), 10 + (i % 3), {"watered": true, "skip_check": true})
		ids.append(int(r.id))
		paid_by[int(r.id)] = 10 + (i % 3)
	# 一部は未給水(成熟が遅い)。成熟前にはイベントなし
	var ev0: Array = run_for(p, 19.0, 1.0)
	ck("no_roll_before_maturity", evs(ev0, "variant_roll").is_empty(), "")
	var ev1: Array = run_for(p, 2.0, 1.0)
	var rolls: Array = evs(ev1, "variant_roll")
	var hits: Array = evs(ev1, "variant")
	ck("each_clover_rolled_exactly_once_on_maturity", rolls.size() == 600, str(rolls.size()))
	ck("four_leaf_rate_about_1_in_50", hits.size() >= 3 and hits.size() <= 30, "hits=%d expect~12" % hits.size())
	ck("variant_events_not_debug", rolls.all(func(e: Dictionary) -> bool: return not bool(e.debug)), "")
	var kept: bool = true
	var detail: String = ""
	for h: Dictionary in hits:
		var c: Dictionary = p.crops.get_crop(int(h.crop_id))
		var okc: bool = c.kind == "four_leaf_clover" and int(c.paid) == int(paid_by[int(h.crop_id)]) and bool(c.watered) and bool(c.mature) \
			and p.crops.crop_id_at(c.cell) == int(c.id) and c.size == Vector2i(1, 1) and float(c.grow) >= 20.0
		if not okc:
			kept = false
			detail = str(c)
	ck("variant_keeps_id_paid_watered_occupancy_progress", kept and hits.size() > 0, detail)
	if hits.size() > 0:
		var fid: int = int(hits[0].crop_id)
		ck("four_leaf_rate_7x", near(rate(p, fid), 2.0 / 60.0 * 7.0, 1e-9), str(rate(p, fid)))
		ck("four_leaf_rate_is_14_per_min", near(rate(p, fid) * 60.0, 14.0, 1e-7), "")
	var four_n: int = hits.size()
	ck("price_family_four_leaf_counts_as_clover", p.crops.family_count("clover") == 600, str(p.crops.family_count("clover")))
	# 再抽選しない: 続けても変種数・ロール数は不変
	var ev2: Array = run_for(p, 200.0, 1.0)
	ck("no_reroll_after_maturity", evs(ev2, "variant_roll").is_empty() and evs(ev2, "variant").is_empty(), "")
	var cnt4: int = 0
	for id: int in ids:
		if p.crops.get_crop(id).kind == "four_leaf_clover":
			cnt4 += 1
	ck("four_leaf_count_stable", cnt4 == four_n, "%d vs %d" % [cnt4, four_n])
	# 保存復元後も再抽選しない
	var d: Dictionary = rt(p.to_dict())
	var p2: RefCounted = mk(999)
	ck("restore_ok", p2.from_dict(d), p2.last_error)
	var ev3: Array = run_for(p2, 100.0, 1.0)
	ck("no_reroll_after_restore", evs(ev3, "variant_roll").is_empty(), "")
	var cnt4b: int = 0
	for id: int in ids:
		if p2.crops.get_crop(id).kind == "four_leaf_clover":
			cnt4b += 1
	ck("restore_keeps_four_leaf_ids", cnt4b == four_n, "")
	# 抽選の再現性: 成熟前保存→復元後、元と同じ順の結果
	var a: RefCounted = mk(5)
	for i: int in range(300):
		a.crops.spawn_crop("clover", Vector2i(17 + (i % 40), 20 + int(i / 40)), 10, {"watered": true, "skip_check": true})
	run_for(a, 10.0, 1.0)
	var saved: Dictionary = rt(a.to_dict())
	var b: RefCounted = mk(123)
	b.from_dict(saved)
	var ea: Array = run_for(a, 15.0, 1.0)
	var eb: Array = run_for(b, 15.0, 1.0)
	var sa: Array = evs(ea, "variant").map(func(e: Dictionary) -> int: return int(e.crop_id))
	var sb: Array = evs(eb, "variant").map(func(e: Dictionary) -> int: return int(e.crop_id))
	ck("roll_sequence_identical_after_restore", sa == sb and evs(ea, "variant_roll").size() == 300, "%s vs %s" % [str(sa), str(sb)])
	# 黄金: 1/77 (強制成熟による通常抽選経路)
	var g: RefCounted = mk(3)
	var gids: Array = []
	for i: int in range(1000):
		var r: Dictionary = g.crops.spawn_crop("golden_clover", Vector2i(17 + (i % 40), 12 + int(i / 40)), 777, {"skip_check": true, "watered": true})
		gids.append(int(r.id))
	var gev: Array = []
	for id: int in gids:
		gev.append_array(g.crops.debug_force_mature(id, true))
	var gh: Array = evs(gev, "variant")
	ck("golden_four_rate_about_1_in_77", gh.size() >= 4 and gh.size() <= 30 and evs(gev, "variant_roll").size() == 1000, "hits=%d expect~13" % gh.size())
	if gh.size() > 0:
		var gc: Dictionary = g.crops.get_crop(int(gh[0].crop_id))
		ck("golden_four_keeps_paid_and_family", gc.kind == "golden_four_leaf" and int(gc.paid) == 777 and g.crops.family_count("golden_clover") == 1000, str(gc.kind))
		ck("golden_four_rate_777x", near(rate(g, int(gc.id)) * 60.0, 2.0 * 777.0 * 1.0 * (1.0 + 0.07 * float(g.crops.gold_k(gc))), 1e-3), str(rate(g, int(gc.id)) * 60.0))
	# デバッグ強制抽選は別イベント(debug=true)で一度だけ
	var d2: RefCounted = mk()
	var dc: int = put(d2, "clover", 20, 20, true)
	var f1: Array = d2.crops.debug_force_roll(dc, true)
	var f2: Array = d2.crops.debug_force_roll(dc, false)
	ck("debug_roll_flagged_and_once", evs(f1, "variant_roll").size() == 1 and bool(f1[0].debug) and f2.is_empty() and d2.crops.get_crop(dc).kind == "four_leaf_clover", str(f1))

# 条件7: 黄金とミツバチ
func t_gold_bee() -> void:
	var p: RefCounted = mk()
	var base: float = 2.0 / 60.0
	var g1: int = put(p, "golden_clover", 30, 30)
	var t_in: int = put(p, "clover", 37, 30)      # dist 7
	var t_out: int = put(p, "clover", 38, 30)     # dist 8
	var t_diag: int = put(p, "clover", 37, 37)    # チェビシェフ7(斜め)
	var t_diag2: int = put(p, "clover", 37, 38)    # 8
	ck("gold_dist7_inclusive_plus7pct", near(rate(p, t_in), base * 1.07, 1e-9), str(rate(p, t_in)))
	ck("gold_dist8_none", near(rate(p, t_out), base, 1e-9), "")
	ck("gold_chebyshev_diagonal_7_in", near(rate(p, t_diag), base * 1.07, 1e-9), "")
	ck("gold_chebyshev_diagonal_8_out", near(rate(p, t_diag2), base, 1e-9), "")
	ck("gold_self_excluded", near(rate(p, g1), base, 1e-9), str(rate(p, g1)))
	var g2: int = put(p, "golden_clover", 31, 33)
	ck("two_golds_add_to_target_1.14", near(rate(p, t_in), base * 1.14, 1e-9), str(rate(p, t_in)))
	ck("golds_affect_each_other_1.07", near(rate(p, g1), base * 1.07, 1e-9) and near(rate(p, g2), base * 1.07, 1e-9), "")
	# k上限7
	var k: RefCounted = mk()
	var tt: int = put(k, "clover", 30, 30)
	for i: int in range(9):
		put(k, "golden_clover", 31 + i, 31)
	ck("gold_k_capped_at_7_gives_1.49", near(rate(k, tt), base * 1.49, 1e-9) and k.crops.gold_k(k.crops.get_crop(tt)) == 7, str(rate(k, tt) / base))
	# 未成熟の黄金は作用しない
	var im: RefCounted = mk()
	var it: int = put(im, "clover", 30, 30)
	put(im, "golden_clover", 31, 30, false)
	ck("immature_gold_no_effect", near(rate(im, it), base, 1e-9), "")
	# 矩形間距離: 6x6スイカと黄金
	var w: RefCounted = mk()
	var wm: int = put(w, "giant_watermelon", 30, 20)    # x30..35,y20..25
	var wb: float = 160.0 / 60.0
	put(w, "golden_clover", 42, 20)                     # x42-35=7
	ck("gold_to_large_rect_dist7_in", near(rate(w, wm), wb * 1.07, 1e-9), str(rate(w, wm) / wb))
	var w2: RefCounted = mk()
	var wm2: int = put(w2, "giant_watermelon", 30, 20)
	put(w2, "golden_clover", 43, 20)
	ck("gold_to_large_rect_dist8_out", near(rate(w2, wm2), wb, 1e-9), "")
	# 黄金の四葉: 黄金と同じ範囲効果、自己除外、生産777倍
	var f: RefCounted = mk()
	var gf: int = put(f, "golden_four_leaf", 30, 30)
	var ft: int = put(f, "clover", 37, 30)
	ck("golden_four_aura_same", near(rate(f, ft), base * 1.07, 1e-9) and near(rate(f, gf), base * 777.0, 1e-6), str(rate(f, gf) * 60.0))
	ck("golden_four_1554_per_min", near(rate(f, gf) * 60.0, 1554.0, 1e-6), "")
	# ミツバチ: 巣から8、通常+10%、花+20%、重複しない、黄金と加算
	var b: RefCounted = mk()
	b.host.hive_list = [{"cell": Vector2i(30, 30), "size": Vector2i(1, 1), "active": true}]
	var c8: int = put(b, "clover", 38, 30)
	var c9: int = put(b, "clover", 39, 30)
	var sf: int = put(b, "sunflower", 30, 38)
	var lv: int = put(b, "lavender", 30, 22)
	var gp: int = put(b, "golden_clover", 22, 30, true)
	ck("bee_dist8_plus10pct", near(rate(b, c8), base * 1.10, 1e-9) and near(rate(b, c9), base, 1e-9), str(rate(b, c8) / base))
	ck("bee_flower_plus20pct_sunflower", near(rate(b, sf), 3.0 / 60.0 * 1.5 * 1.2, 1e-9), str(rate(b, sf)))
	ck("bee_flower_plus20pct_lavender", near(rate(b, lv), 1.5 / 60.0 * 1.2, 1e-9), "")
	b.host.hive_list.append({"cell": Vector2i(32, 30), "size": Vector2i(1, 1), "active": true})
	ck("two_hives_do_not_stack", near(rate(b, c8), base * 1.10, 1e-9) and near(rate(b, sf), 3.0 / 60.0 * 1.5 * 1.2, 1e-9), str(rate(b, c8) / base))
	b.host.hive_list = [{"cell": Vector2i(30, 30), "size": Vector2i(1, 1), "active": true}]
	# 黄金(22,30)から c8 (38,30): dist16 範囲外。近い位置に別の標的を置く
	var tg: int = put(b, "clover", 30, 31)
	put(b, "golden_clover", 29, 30)
	put(b, "golden_clover", 28, 30)
	ck("gold_and_bee_add_1.24", near(rate(b, tg), base * (1.0 + 0.14 + 0.10), 1e-9), str(rate(b, tg) / base))
	# 実際のミツバチの巣(敵)経由の受粉
	var e: RefCounted = mk()
	var hid: int = e.enemies.spawn("honeybee_hive", Vector2(122, 122))   # cell(30,30)
	var ec: int = put(e, "clover", 38, 30)
	ck("real_hive_pollinates_clover", near(rate(e, ec), base * 1.10, 1e-9), str(rate(e, ec) / base))
	e.hit_enemy(hid, 100.0, "shot", null)
	ck("destroyed_hive_loses_pollination", near(rate(e, ec), base, 1e-9) and not e.enemies.is_alive(hid), str(rate(e, ec) / base))
	# 補正は栽培植物のみ: 1.3節。ここでは生産が加算でまとまる(+7%と+10%を加算、乗算でない)
	ck("additive_not_multiplicative", not near(rate(b, tg), base * 1.14 * 1.10, 1e-9), "")

func grow_after(p: RefCounted, id: int, secs: float) -> float:
	run_for(p, secs, 1.0)
	return float(p.crops.get_crop(id).grow)

# 条件7続き: 条件付き倍率
func t_conditions() -> void:
	# エダマメ+5%/株、上限5株
	var p: RefCounted = mk()
	var tc: int = p.crops.spawn_crop("clover", Vector2i(30, 30), 10, {"watered": true, "skip_check": true}).id
	p.crops.spawn_crop("edamame", Vector2i(29, 30), 20, {"mature": true, "skip_check": true})
	var g1: float = grow_after(p, tc, 10.0)
	ck("edamame_1_plus5pct_growth", near(g1, 10.5, 1e-6), str(g1))
	var q: RefCounted = mk()
	var tq: int = q.crops.spawn_crop("clover", Vector2i(30, 30), 10, {"watered": true, "skip_check": true}).id
	for pos: Vector2i in [Vector2i(29, 29), Vector2i(30, 29), Vector2i(31, 29), Vector2i(29, 30), Vector2i(31, 30), Vector2i(29, 31), Vector2i(30, 31)]:
		q.crops.spawn_crop("edamame", pos, 20, {"mature": true, "skip_check": true})
	var g7: float = grow_after(q, tq, 10.0)
	ck("edamame_cap_5_gives_plus25pct", near(g7, 12.5, 1e-6), str(g7))
	# 未給水は半分
	var u: RefCounted = mk()
	var tu: int = u.crops.spawn_crop("clover", Vector2i(30, 30), 10, {"watered": false, "skip_check": true}).id
	u.crops.spawn_crop("edamame", Vector2i(29, 30), 20, {"mature": true, "skip_check": true})
	ck("unwatered_half_speed_with_edamame", near(grow_after(u, tu, 10.0), 5.25, 1e-6), "")
	# エダマメは互いに加速しない/範囲2は不可
	var s: RefCounted = mk()
	var se: int = s.crops.spawn_crop("edamame", Vector2i(30, 30), 20, {"watered": true, "skip_check": true}).id
	s.crops.spawn_crop("edamame", Vector2i(31, 30), 20, {"mature": true, "skip_check": true})
	ck("edamame_no_self_or_mutual_boost", near(grow_after(s, se, 10.0), 10.0, 1e-6), "")
	var d2: RefCounted = mk()
	var t2: int = d2.crops.spawn_crop("clover", Vector2i(30, 30), 10, {"watered": true, "skip_check": true}).id
	d2.crops.spawn_crop("edamame", Vector2i(32, 30), 20, {"mature": true, "skip_check": true})
	ck("edamame_dist2_no_effect", near(grow_after(d2, t2, 10.0), 10.0, 1e-6), "")
	var im: RefCounted = mk()
	var ti: int = im.crops.spawn_crop("clover", Vector2i(30, 30), 10, {"watered": true, "skip_check": true}).id
	im.crops.spawn_crop("edamame", Vector2i(29, 30), 20, {"mature": false, "watered": false, "skip_check": true})
	ck("immature_edamame_no_effect", near(grow_after(im, ti, 10.0), 10.0, 1e-6), "")
	# ドクダミ 日陰: 成長x1.5、生産x2
	var d: RefCounted = mk()
	var dsh: int = d.crops.spawn_crop("dokudami", Vector2i(30, 12), 15, {"watered": true, "skip_check": true}).id
	var dno: int = d.crops.spawn_crop("dokudami", Vector2i(30, 25), 15, {"watered": true, "skip_check": true}).id
	run_for(d, 10.0)
	ck("dokudami_shade_growth_1.5", near(float(d.crops.get_crop(dsh).grow), 15.0, 1e-6) and near(float(d.crops.get_crop(dno).grow), 10.0, 1e-6), "")
	var dm1: int = put(d, "dokudami", 31, 12)
	var dm2: int = put(d, "dokudami", 31, 25)
	ck("dokudami_shade_production_x2", near(rate(d, dm1), 4.0 / 60.0, 1e-9) and near(rate(d, dm2), 2.0 / 60.0, 1e-9), "")
	# ヒマワリ昼夜
	var h: RefCounted = mk()
	var sf: int = put(h, "sunflower", 20, 20)
	ck("sunflower_day_4.5_per_min", near(rate(h, sf) * 60.0, 4.5, 1e-9), "")
	h.host.day = false
	ck("sunflower_night_0.9_per_min", near(rate(h, sf) * 60.0, 0.9, 1e-9), "")
	# トマト壁際
	var t: RefCounted = mk()
	var tm1: int = put(t, "tomato", 27, 15)    # 建物x28に隣接
	var tm2: int = put(t, "tomato", 26, 15)
	var tm3: int = put(t, "tomato", 27, 13)    # 斜め
	var tm4: int = put(t, "tomato", 30, 13)    # 北に隣接
	ck("tomato_wall_adjacent_7_per_min", near(rate(t, tm1) * 60.0, 7.0, 1e-9) and near(rate(t, tm4) * 60.0, 7.0, 1e-9), str(rate(t, tm1) * 60.0))
	ck("tomato_not_adjacent_4_per_min", near(rate(t, tm2) * 60.0, 4.0, 1e-9) and near(rate(t, tm3) * 60.0, 4.0, 1e-9), "")
	# ブドウ直線
	var g: RefCounted = mk()
	var gr: Array = []
	for i: int in range(4):
		gr.append(put(g, "grape", 20 + i, 20))
	var below: int = put(g, "grape", 21, 21)
	var gb: float = 2.0 / 60.0
	ck("grape_line4_x1.45", near(rate(g, gr[0]), gb * 1.45, 1e-9) and near(rate(g, gr[3]), gb * 1.45, 1e-9), str(rate(g, gr[0]) / gb))
	ck("grape_vertical_pair_x1.15", near(rate(g, below), gb * 1.15, 1e-9), str(rate(g, below) / gb))
	var g8: RefCounted = mk()
	var line10: Array = []
	for i: int in range(10):
		line10.append(put(g8, "grape", 10 + i, 20))
	ck("grape_cap_L8_x2.05", near(rate(g8, line10[5]), gb * 2.05, 1e-9), str(rate(g8, line10[5]) / gb))
	var gd: RefCounted = mk()
	var d0: int = put(gd, "grape", 20, 20)
	put(gd, "grape", 21, 21)
	ck("grape_diagonal_not_counted", near(rate(gd, d0), gb, 1e-9), "")
	# イネ: 矩形面積
	var r: RefCounted = mk()
	var rids: Dictionary = {}
	for y: int in range(4, 7):
		for x: int in range(16, 18):
			rids[Vector2i(x, y)] = put(r, "rice", x, y)
	var tail: int = put(r, "rice", 16, 7)
	var rb: float = 1.5 / 60.0
	ck("rice_rect_2x3_x1.2", near(rate(r, rids[Vector2i(17, 4)]), rb * 1.2, 1e-9), str(rate(r, rids[Vector2i(17, 4)]) / rb))
	ck("rice_tail_not_rect_x1.12", near(rate(r, tail), rb * 1.12, 1e-9), str(rate(r, tail) / rb))
	var rb5: RefCounted = mk()
	var big: int = -1
	for y: int in range(10, 16):
		for x: int in range(20, 26):
			var i2: int = put(rb5, "rice", x, y)
			if x == 22 and y == 12:
				big = i2
	ck("rice_6x6_cap_A25_x1.96", near(rate(rb5, big), rb * 1.96, 1e-9), str(rate(rb5, big) / rb))
	# トウモロコシ三姉妹
	var c: RefCounted = mk()
	var cn: int = put(c, "corn", 20, 20)
	var cb: float = 3.0 / 60.0
	ck("corn_alone_x1", near(rate(c, cn), cb, 1e-9), "")
	put(c, "edamame", 19, 20)
	ck("corn_edamame_x1.3", near(rate(c, cn), cb * 1.3, 1e-9), "")
	put(c, "edamame", 19, 21)
	ck("corn_two_edamame_still_x1.3", near(rate(c, cn), cb * 1.3, 1e-9), str(rate(c, cn) / cb))
	put(c, "pumpkin", 21, 20)
	ck("corn_both_x1.8", near(rate(c, cn), cb * 1.8, 1e-9), str(rate(c, cn) / cb))
	var c2: RefCounted = mk()
	var cn2: int = put(c2, "corn", 20, 20)
	put(c2, "pumpkin", 21, 19)   # 2x2 x21..22,y19..20 隣接(辺)
	ck("corn_pumpkin_only_x1.3", near(rate(c2, cn2), cb * 1.3, 1e-9), "")
	var c3: RefCounted = mk()
	var cn3: int = put(c3, "corn", 20, 20)
	put(c3, "edamame", 19, 20, false)
	ck("corn_immature_edamame_x1", near(rate(c3, cn3), cb, 1e-9), "")
	# チャノキ熟成
	var tea: RefCounted = mk()
	var tei: int = put(tea, "tea", 20, 20)
	var tb: float = 3.0 / 60.0
	run_for(tea, 650.0, 5.0)
	ck("tea_after_650s_x1.2", near(rate(tea, tei), tb * 1.2, 1e-9), str(rate(tea, tei) / tb))
	run_for(tea, 5000.0, 50.0)
	ck("tea_cap_x2", near(rate(tea, tei), tb * 2.0, 1e-9), str(rate(tea, tei) / tb))
	# サクラ
	var sk: RefCounted = mk()
	var si: int = put(sk, "sakura", 20, 20)
	var sb: float = 6.0 / 60.0
	run_for(sk, 10.0)
	ck("sakura_bloom_x4_early", near(rate(sk, si), sb * 4.0, 1e-9), "")
	run_for(sk, 90.0)
	ck("sakura_off_at_100s", near(rate(sk, si), sb, 1e-9), "")
	run_for(sk, 150.0)
	ck("sakura_bloom_again_at_250s", near(rate(sk, si), sb * 4.0, 1e-9), "")
	# ハエトリソウ: 消化中x3、捕獲は20秒に1回
	var f: RefCounted = mk()
	var fi: int = put(f, "flytrap", 20, 20)
	var cap1: Dictionary = f.crops.flytrap_capture(1, Vector2i(21, 20), ["small"])
	var cap_big: Dictionary = f.crops.flytrap_capture(2, Vector2i(21, 20), ["beast"])
	ck("flytrap_captures_small_30dmg", bool(cap1.captured) and near(float(cap1.damage), 30.0), "")
	ck("flytrap_digesting_blocks_second", not bool(f.crops.flytrap_capture(3, Vector2i(20, 21), ["small"]).captured), "")
	ck("flytrap_digest_rate_x3", near(rate(f, fi), 0.5 / 60.0 * 3.0, 1e-9), "")
	run_for(f, 20.5)
	ck("flytrap_ready_after_20s_rate_normal", near(rate(f, fi), 0.5 / 60.0, 1e-9) and bool(f.crops.flytrap_capture(4, Vector2i(20, 19), ["small"]).captured), "")
	ck("flytrap_ignores_non_small", not bool(cap_big.captured), "")

# 他: ミント・イチゴ・ジャガイモ・アロエ・カボチャ・トウガラシ・サボテン・返還
func t_misc() -> void:
	# ジャガイモ
	var p: RefCounted = mk()
	var pt: int = put(p, "potato", 20, 20, true, 30)
	var ev: Array = run_for(p, 100.0, 1.0)
	var st: float = float(p.crops.get_crop(pt).storage)
	ck("potato_stores_8_per_min", near(st, 8.0 / 60.0 * 100.0, 1e-6), str(st))
	ck("potato_no_continuous_seeds", evs(ev, "seeds").is_empty(), "")
	run_for(p, 3000.0, 10.0)
	ck("potato_cap_10x_paid", near(float(p.crops.get_crop(pt).storage), 300.0, 1e-6), str(p.crops.get_crop(pt).storage))
	var rm: Dictionary = p.crops.remove_crop(pt, "manual")
	ck("potato_remove_refund_6_plus_300", int(rm.refund) == 306, str(rm.refund))
	var p2: RefCounted = mk()
	var pt2: int = put(p2, "potato", 20, 20, true, 30)
	run_for(p2, 100.0, 1.0)
	ck("potato_killed_by_enemy_loses_storage_refund0", int(p2.crops.remove_crop(pt2, "enemy").refund) == 0, "")
	var p3: RefCounted = mk()
	var pt3: int = put(p3, "potato", 20, 20, true, 30)
	run_for(p3, 100.0, 1.0)   # 13.33
	ck("potato_refund_floors_storage", int(p3.crops.remove_crop(pt3, "manual").refund) == 6 + 13, "")
	# 返還
	var rf: RefCounted = mk()
	var a: int = put(rf, "golden_clover", 20, 20, true, 777)
	ck("manual_refund_20pct_floor", int(rf.crops.remove_crop(a, "manual").refund) == 155, "")
	var b: int = put(rf, "clover", 22, 20, true, 14)
	ck("refund_floor_14_is_2", int(rf.crops.remove_crop(b, "manual").refund) == 2, "")
	var c: int = put(rf, "clover", 24, 20, true, 777)
	ck("enemy_kill_refund0", int(rf.crops.remove_crop(c, "enemy").refund) == 0, "")
	# ミント
	var m: RefCounted = mk()
	var m1: int = put(m, "mint", 20, 25, true, 15)
	var m2: int = put(m, "mint", 40, 25, true, 15)
	run_for(m, 31.0, 1.0)
	var n1: int = m.crops.family_count("mint")
	ck("mint_spreads_one_per_30s", n1 == 4, str(n1))
	run_for(m, 3000.0, 2.0)
	var col1: int = 0
	var col2: int = 0
	var free_paid: bool = true
	for cid: int in m.crops.crop_ids():
		var cc: Dictionary = m.crops.get_crop(cid)
		if int(cc.colony_id) == m1:
			col1 += 1
		elif int(cc.colony_id) == m2:
			col2 += 1
		if cid != m1 and cid != m2 and int(cc.paid) != 0:
			free_paid = false
	ck("mint_colony_caps_at_9_each", col1 == 9 and col2 == 9, "%d %d" % [col1, col2])
	ck("mint_spread_paid_0", free_paid, "")
	ck("mint_family_count_includes_spread", m.crops.family_count("mint") == 18, "")
	var spread_id: int = -1
	for cid: int in m.crops.crop_ids():
		if cid != m1 and cid != m2:
			spread_id = cid
			break
	ck("mint_spread_remove_refund0", int(m.crops.remove_crop(spread_id, "manual").refund) == 0, "")
	ck("mint_original_refund_3", int(m.crops.remove_crop(m1, "manual").refund) == 3, "")
	ck("mint_count_decreases_on_remove", m.crops.family_count("mint") == 16, str(m.crops.family_count("mint")))
	# 連結性: 増えた株は元の株と辺でつながる
	var m3: RefCounted = mk()
	var r0: int = put(m3, "mint", 20, 25, true, 15)
	run_for(m3, 200.0, 1.0)
	var cells: Dictionary = {}
	for cid: int in m3.crops.crop_ids():
		cells[m3.crops.get_crop(cid).cell] = true
	var conn: bool = true
	for cell: Vector2i in cells.keys():
		if cell == Vector2i(20, 25):
			continue
		var has_nb: bool = false
		for dv: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if cells.has(cell + dv):
				has_nb = true
		if not has_nb:
			conn = false
	ck("mint_spread_is_orthogonally_adjacent", conn and cells.size() == 9, str(cells.size()))
	# イチゴ
	var s: RefCounted = mk()
	var sb: int = put(s, "strawberry", 20, 20)
	s.host.hero_state = {"pos": Vector2(400, 400), "hp": 100.0, "max_hp": 100.0}
	run_for(s, 200.0, 1.0)
	ck("strawberry_max_3_pickups_6_each", s.crops.pickups.size() == 3 and s.crops.pickups.all(func(pk: Dictionary) -> bool: return int(pk.amount) == 6), str(s.crops.pickups.size()))
	var adj_ok: bool = true
	for pk: Dictionary in s.crops.pickups:
		var cell: Vector2i = Vector2i(floori(pk.pos.x / 4.0), floori(pk.pos.y / 4.0))
		if absi(cell.x - 20) + absi(cell.y - 20) != 1:
			adj_ok = false
	ck("strawberry_pickups_on_adjacent_cells", adj_ok, "")
	var kept: Array = s.crops.pickups.duplicate(true)
	s.crops.remove_crop(sb, "manual")
	ck("strawberry_pickups_persist_after_removal", s.crops.pickups.size() == 3, "")
	var s2: RefCounted = mk()
	ck("strawberry_pickups_survive_save", s2.from_dict(rt(s.to_dict())) and s2.crops.pickups.size() == 3, s2.last_error)
	s2.host.hero_state = {"pos": Vector2(kept[0].pos) + Vector2(5, 0), "hp": 100.0, "max_hp": 100.0}
	var cev: Array = s2.advance(0.1)
	ck("pickup_collected_when_hero_within_0.8m", evs(cev, "pickup_collected").size() >= 1 and int(evs(cev, "pickup_collected")[0].amount) == 6, "")
	s2.host.hero_state = {"pos": Vector2(Vector2(kept[0].pos).x + 20.0, Vector2(kept[0].pos).y), "hp": 100.0, "max_hp": 100.0}
	# アロエ
	var al: RefCounted = mk()
	put(al, "aloe", 20, 20)
	al.host.hero_state = {"pos": Vector2(20 * 4 + 22, 82), "hp": 40.0, "max_hp": 100.0}   # cell(25,20) dist5? x=102/4=25.5->25, rect x20 -> dx5
	al.host.helper_list = [{"id": 5, "pos": Vector2(80, 82), "hp": 10.0, "max_hp": 50.0}]  # cell(20,20)... 隣
	var aev: Array = run_for(al, 1.0, 0.5)
	var heals: Array = evs(aev, "heal")
	ck("aloe_heals_lowest_ratio_in_range_30", heals.size() == 1 and heals[0].target == "helper" and near(float(heals[0].amount), 30.0), str(heals))
	var aev2: Array = run_for(al, 50.0, 1.0)
	ck("aloe_cooldown_60s_blocks", evs(aev2, "heal").is_empty(), "")
	var aev3: Array = run_for(al, 15.0, 1.0)
	ck("aloe_heals_again_after_cooldown", evs(aev3, "heal").size() >= 1, "")
	var al2: RefCounted = mk()
	put(al2, "aloe", 20, 20)
	al2.host.hero_state = {"pos": Vector2(20 * 4 + 22, 82), "hp": 40.0, "max_hp": 100.0}
	ck("aloe_dist5_out_of_range", evs(run_for(al2, 2.0, 0.5), "heal").is_empty(), "")
	al2.host.hero_state = {"pos": Vector2(20 * 4 + 18, 82), "hp": 50.0, "max_hp": 100.0}
	ck("aloe_exactly_50pct_no_heal", evs(run_for(al2, 2.0, 0.5), "heal").is_empty(), "")
	al2.host.hero_state = {"pos": Vector2(20 * 4 + 18, 82), "hp": 49.0, "max_hp": 100.0}
	ck("aloe_dist4_below50_heals_hero", evs(run_for(al2, 2.0, 0.5), "heal").size() == 1, "")
	# カボチャ軽減
	var pm: RefCounted = mk()
	var pk: int = put(pm, "pumpkin", 20, 20)
	var tg: int = put(pm, "clover", 22, 20)     # 隣接
	var far: int = put(pm, "clover", 24, 20)    # dist2
	pm.crops.damage_crop(tg, 10.0)
	pm.crops.damage_crop(far, 10.0)
	pm.crops.damage_crop(pk, 10.0)
	ck("pumpkin_x0.7_adjacent", near(float(pm.crops.get_crop(tg).hp), 30.0 - 7.0, 1e-6), "")
	ck("pumpkin_no_effect_dist2", near(float(pm.crops.get_crop(far).hp), 20.0, 1e-6), "")
	ck("pumpkin_not_self", near(float(pm.crops.get_crop(pk).hp), 60.0, 1e-6), "")
	put(pm, "pumpkin", 22, 22)
	var tg2: int = put(pm, "clover", 22, 21)    # 2つのカボチャに隣接
	pm.crops.damage_crop(tg2, 10.0)
	ck("two_pumpkins_do_not_stack", near(float(pm.crops.get_crop(tg2).hp), 23.0, 1e-6), str(pm.crops.get_crop(tg2).hp))
	# トウガラシ・サボテン
	var pp: RefCounted = mk()
	var pep: int = put(pp, "pepper", 20, 20)
	var e1: Array = pp.crops.damage_crop(pep, 3.0, {"enemy_id": 9})
	ck("pepper_counter_on_attack", evs(e1, "pepper_counter").size() == 1 and near(float(evs(e1, "pepper_counter")[0].damage), 2.0) and near(float(evs(e1, "pepper_counter")[0].flee_seconds), 3.0), "")
	ck("pepper_same_enemy_5s_cooldown", evs(pp.crops.damage_crop(pep, 3.0, {"enemy_id": 9}), "pepper_counter").is_empty(), "")
	ck("pepper_other_enemy_ok", evs(pp.crops.damage_crop(pep, 3.0, {"enemy_id": 10}), "pepper_counter").size() == 1, "")
	ck("pepper_collateral_no_counter", evs(pp.crops.damage_crop(pep, 1.0, {"enemy_id": 11, "cause": "collateral"}), "pepper_counter").is_empty(), "")
	pp.advance(5.1)
	ck("pepper_cooldown_expires", evs(pp.crops.damage_crop(pep, 1.0, {"enemy_id": 9}), "pepper_counter").size() == 1, "")
	var cc: RefCounted = mk()
	var cac: int = put(cc, "cactus", 20, 20)
	ck("cactus_thorn_adjacent_cell_3dmg", evs(cc.crops.enemy_moved(4, Vector2i(21, 20)), "cactus_thorn").size() == 1, "")
	ck("cactus_thorn_1s_cooldown_same_enemy", cc.crops.enemy_moved(4, Vector2i(21, 21)).is_empty() and cc.crops.enemy_moved(4, Vector2i(22, 20)).is_empty(), "")
	ck("cactus_thorn_diagonal_not_adjacent", cc.crops.enemy_moved(8, Vector2i(21, 21)).is_empty(), "")
	ck("cactus_attacked_thorn", evs(cc.crops.damage_crop(cac, 5.0, {"enemy_id": 12}), "cactus_thorn").size() == 1, "")
	# タケ
	var bb: RefCounted = mk()
	var bi: int = bb.crops.spawn_crop("bamboo", Vector2i(20, 20), 10, {"watered": true, "skip_check": true}).id
	ck("bamboo_blocks_only_when_mature", not bb.crops.blocks_enemy(Vector2i(20, 20)), "")
	run_for(bb, 8.0)
	ck("bamboo_matures_8s_and_blocks", bb.crops.blocks_enemy(Vector2i(20, 20)) and not bb.crops.blocks_enemy(Vector2i(21, 20)), "")
	# ラベンダー・ニンニクの狙い除外
	var lv: RefCounted = mk()
	put(lv, "lavender", 20, 20)
	var lt: int = put(lv, "clover", 24, 20)
	var lt2: int = put(lv, "clover", 25, 20)
	ck("lavender_removes_bug_targeting_radius4", not lv.crops.crop_targetable_by(["bug"], lt) and lv.crops.crop_targetable_by(["bug"], lt2) and lv.crops.crop_targetable_by(["beast"], lt), "")
	var ga: RefCounted = mk()
	put(ga, "garlic", 20, 20)
	var gt: int = put(ga, "clover", 23, 20)
	var gt2: int = put(ga, "clover", 24, 20)
	ck("garlic_hides_crops_radius3_all_enemy_types", not ga.crops.crop_targetable_by(["beast"], gt) and ga.crops.crop_targetable_by(["beast"], gt2), "")
	# ヒカリゴケ
	var gm: RefCounted = mk()
	put(gm, "glow_moss", 20, 20)
	ck("glow_moss_day_no_reveal", not gm.crops.glow_moss_reveals(Vector2i(25, 20)), "")
	gm.host.day = false
	ck("glow_moss_night_radius5", gm.crops.glow_moss_reveals(Vector2i(25, 20)) and not gm.crops.glow_moss_reveals(Vector2i(26, 20)), "")
	# 生産量: 成長前は0、生産合計の整合(クローバー20s成熟後60sで2種)
	var pr: RefCounted = mk()
	var cl: int = pr.crops.spawn_crop("clover", Vector2i(20, 20), 10, {"watered": true, "skip_check": true, "variant_rolled": true}).id
	var prv: Array = run_for(pr, 20.0)
	ck("immature_zero_production", near(float(pr.crops.produced.get("clover", 0.0)), 0.0, 1e-9) , str(pr.crops.produced))
	run_for(pr, 60.0)
	ck("clover_2_per_min_after_maturity", near(float(pr.crops.produced.get("clover", 0.0)), 2.0, 1e-6), str(pr.crops.produced))

# 条件8: 保存復元と壊れたデータ
func t_save() -> void:
	var p: RefCounted = mk(21)
	put(p, "oleander", 20, 20)
	put(p, "clover", 24, 20)
	put(p, "mint", 40, 25, true, 15)
	run_for(p, 7.0)
	var snap: String = JSON.stringify(p.to_dict())
	var bad: Dictionary = rt(p.to_dict())
	bad.crops.crops[1].kind = "no_such_plant"
	ck("corrupt_unknown_kind_rejected", not p.from_dict(bad), "")
	ck("corrupt_leaves_state_unchanged", JSON.stringify(p.to_dict()) == snap, "")
	var bad2: Dictionary = rt(p.to_dict())
	bad2.crops.crops[2].hp = "x"
	ck("corrupt_field_type_rejected_unchanged", not p.from_dict(bad2) and JSON.stringify(p.to_dict()) == snap, "")
	var bad3: Dictionary = rt(p.to_dict())
	bad3.crops.crops[0].cell = [21, 20]   # 重なり(clover 24,20 と oleander の別)ではなく無効な組合せ: 位置重複
	bad3.crops.crops[1].cell = [21, 20]
	ck("corrupt_overlap_rejected_unchanged", not p.from_dict(bad3) and JSON.stringify(p.to_dict()) == snap, "")
	var bad4: Dictionary = rt(p.to_dict())
	bad4.erase("rng")
	ck("corrupt_missing_rng_rejected_unchanged", not p.from_dict(bad4) and JSON.stringify(p.to_dict()) == snap, "")
	var bad5: Dictionary = rt(p.to_dict())
	bad5.enemies = {"junk": 1}
	var r5: bool = p.from_dict(bad5)
	ck("corrupt_enemies_rejects_whole_unchanged", (not r5) and JSON.stringify(p.to_dict()) == snap, "r5=%s err=%s" % [str(r5), p.last_error])
	# 正常復元の往復
	var q: RefCounted = mk(1)
	ck("good_roundtrip_ok", q.from_dict(rt(p.to_dict())) and JSON.stringify(q.to_dict()) == snap, q.last_error)
	# ポーズ: advanceを呼ばなければ進まない
	var t0: float = p.time()
	var s0: String = JSON.stringify(p.to_dict())
	ck("no_advance_no_progress", near(p.time(), t0) and JSON.stringify(p.to_dict()) == s0, "")
	ck("advance_zero_is_noop", p.advance(0.0).is_empty() and near(p.time(), t0), "")
	ck("advance_negative_is_noop", p.advance(-1.0).is_empty() and near(p.time(), t0), "")
