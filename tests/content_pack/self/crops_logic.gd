extends SceneTree
## 栽培植物の規則の自己検証(入口スクリプト)。1条件1回、時間は大きな刻みで早送り。
## 実行(隔離プロジェクトのみ): Godot --headless --path C:/godot/greenvader_content_sandbox --script res://tests/content_pack/self/crops_logic.gd
const Lab: GDScript = preload("res://scripts/content_pack/lab/lab_host.gd")
const Pack: GDScript = preload("res://scripts/content_pack/content_pack.gd")
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")
const OUT_DIR: String = "res://evidence/content_pack/self"

var checks: Array = []

func ck(name: String, ok: bool, detail: String = "") -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})

func near(a: float, b: float, eps: float = 1e-6) -> bool:
	return absf(a - b) <= eps * maxf(1.0, absf(b))

func mk(seed: int = 1) -> RefCounted:
	return Pack.new(Lab.new(), seed)

## 配置(給水済み、既定で成熟済み)。失敗時は -1
func sp(p: RefCounted, kind: String, x: int, y: int, mature: bool = true, watered: bool = true) -> int:
	var cost: int = int(p.crops.def_of(kind).cost)
	var r: Dictionary = p.crops.spawn_crop(kind, Vector2i(x, y), cost, {"mature": mature, "watered": watered})
	return int(r.id) if bool(r.ok) else -1

func rate(p: RefCounted, id: int) -> float:
	return float(p.crops.production_info(id).rate)

func evs(events: Array, type: String) -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if e.type == type:
			out.append(e)
	return out

func seed_where(hit: bool, thr: float) -> int:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	for s: int in range(1, 100000):
		r.seed = s
		if (r.randf() < thr) == hit:
			return s
	return 1

func roundtrip(d: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(d))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func snap(p: RefCounted) -> String:
	var rows: Array = []
	for c: Dictionary in p.crops.crops:
		rows.append("%d:%s:%d,%d:%s:%d:%s" % [c.id, c.kind, c.cell.x, c.cell.y, str(c.mature), c.poison, str(c.variant_rolled)])
	rows.sort()
	var pk: Array = []
	for q: Dictionary in p.crops.pickups:
		pk.append("%d:%.2f,%.2f:%d" % [q.id, q.pos.x, q.pos.y, q.amount])
	pk.sort()
	return "|".join(rows) + "#" + "|".join(pk) + "#" + str(p.rng.state)

func _initialize() -> void:
	t_defs()
	t_placement()
	t_growth()
	t_gold_bee()
	t_pumpkin()
	t_poison()
	t_variants()
	t_mint()
	t_strawberry_potato()
	t_conditions()
	t_abilities()
	t_enemy_api()
	t_refund_price()
	t_save_restore()
	var fails: int = 0
	for c: Dictionary in checks:
		print("%s %s %s" % [c.status, c.name, c.detail])
		if c.status != "PASS":
			fails += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/crops_logic.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "crops_logic", "total": checks.size(), "failed": fails, "checks": checks}, "\t"))
	f.close()
	print("crops_logic total=%d failed=%d" % [checks.size(), fails])
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------ 定義
func t_defs() -> void:
	var p: RefCounted = mk()
	var n: int = 0
	var missing: Array = []
	for i: int in range(1, 29):
		var found: bool = false
		for k: String in p.crops.defs:
			if p.crops.defs[k].id == "P%02d" % i:
				found = true
		if found:
			n += 1
		else:
			missing.append(i)
	ck("defs_28_kinds", n == 28 and missing.is_empty(), "found=%d missing=%s" % [n, str(missing)])
	var g: Dictionary = p.crops.def_of("giant_watermelon")
	var s: Dictionary = p.crops.def_of("sakura")
	ck("defs_values", int(g.size[0]) == 6 and int(g.size[1]) == 6 and int(g.cost) == 450 and int(s.size[0]) == 3 and int(s.size[1]) == 3 and int(s.cost) == 150 and int(p.crops.def_of("golden_four_leaf").variant_mult) == 777, "")

# ------------------------------------------------------------------ 配置
func t_placement() -> void:
	var p: RefCounted = mk()
	var c: RefCounted = p.crops
	var r1: Dictionary = c.place_crop("bamboo", Vector2i(20, 22))
	ck("place_normal_ok", bool(r1.ok) and int(r1.paid) == 10, str(r1.reason))
	ck("place_occupied", c.place_crop("bamboo", Vector2i(20, 22)).reason == "occupied", "")
	ck("place_wasteland_denied_for_normal", c.place_crop("clover", Vector2i(46, 26)).reason == "requires_green", "")
	ck("place_water_denied_for_normal", c.place_crop("clover", Vector2i(5, 5)).reason == "blocked_ground", "")
	ck("place_outside_denied", c.place_crop("clover", Vector2i(-1, 0)).reason == "outside_map", "")
	ck("place_junk_denied", c.place_crop("clover", Vector2i(50, 6)).reason == "occupied", "")
	ck("place_variant_not_placeable", c.place_crop("four_leaf_clover", Vector2i(22, 22)).reason == "not_placeable" and c.place_crop("golden_four_leaf", Vector2i(22, 22)).reason == "not_placeable", "")
	# ワサビ: 清水(水の種類ではなく清水)から2タイル以内
	ck("wasabi_near_clean_ok", bool(c.place_crop("wasabi", Vector2i(8, 20)).ok), "(8,20) is 2 from clean water")
	ck("wasabi_shallow_only_denied", c.place_crop("wasabi", Vector2i(10, 15)).reason == "needs_clean_water", "shallow near but clean 4 away")
	ck("wasabi_far_denied", c.place_crop("wasabi", Vector2i(30, 28)).reason == "needs_clean_water", "")
	# ハス: 水面4マス、陸に隣接
	var lot: Dictionary = c.place_crop("lotus", Vector2i(12, 2))
	ck("lotus_surface_ok", bool(lot.ok), str(lot.reason))
	ck("lotus_overlap_denied", c.place_crop("lotus", Vector2i(13, 2)).reason == "occupied", "")
	ck("lotus_no_shore_denied", c.place_crop("lotus", Vector2i(6, 6)).reason == "needs_shore", "")
	ck("lotus_on_land_denied", c.place_crop("lotus", Vector2i(30, 5)).reason == "not_water", "")
	# サボテン: 荒地可。下地を種にするイベント
	var cac: Dictionary = c.place_crop("cactus", Vector2i(46, 26))
	ck("cactus_wasteland_ok_with_ground_seed", bool(cac.ok) and evs(cac.events, "ground_seed").size() == 1, "")
	ck("cactus_on_water_denied", c.place_crop("cactus", Vector2i(5, 5)).reason == "blocked_ground", "")
	# イネ: 水辺2タイル
	ck("rice_near_water_ok", bool(c.place_crop("rice", Vector2i(16, 5)).ok), "")
	ck("rice_far_denied", c.place_crop("rice", Vector2i(30, 30)).reason == "needs_water", "")
	ck("rice_on_water_denied", c.place_crop("rice", Vector2i(13, 5)).reason == "blocked_ground", "")
	# 6x6
	var wm: Dictionary = c.place_crop("giant_watermelon", Vector2i(20, 24))
	ck("watermelon_6x6_occupancy", bool(wm.ok) and c.crop_id_at(Vector2i(25, 29)) == int(wm.id) and c.crop_id_at(Vector2i(26, 29)) == 0, "")
	ck("watermelon_overlap_denied", c.place_crop("giant_watermelon", Vector2i(22, 26)).reason == "occupied", "")
	ck("watermelon_needs_all_36_green", c.place_crop("giant_watermelon", Vector2i(40, 24)).reason == "requires_green", "x44,45 are wasteland")
	var rm: Dictionary = c.remove_crop(int(wm.id), "manual")
	ck("watermelon_remove_frees_and_refund_20pct", int(rm.refund) == 90 and c.crop_id_at(Vector2i(25, 29)) == 0 and bool(c.place_crop("giant_watermelon", Vector2i(20, 24)).ok), "refund=%d" % int(rm.refund))

# ------------------------------------------------------------------ 成長
func t_growth() -> void:
	var p: RefCounted = mk()
	var w: int = sp(p, "bamboo", 20, 22, false, true)
	var d: int = sp(p, "bamboo", 24, 22, false, false)
	p.advance(7.5)
	ck("growth_watered_not_yet_at_7_5", not bool(p.crops.get_crop(w).mature), "")
	p.advance(0.5)
	ck("growth_watered_mature_at_T", bool(p.crops.get_crop(w).mature) and not bool(p.crops.get_crop(d).mature), "T=8 watered=8s, unwatered half speed")
	p.advance(8.0)
	ck("growth_unwatered_mature_at_2T", bool(p.crops.get_crop(d).mature), "16s")
	# エダマメ
	var q: RefCounted = mk()
	var t: int = sp(q, "bamboo", 22, 22, false, true)
	sp(q, "edamame", 21, 21)
	sp(q, "edamame", 22, 21)
	ck("edamame_2_gives_plus_10pct", near(q.crops.growth_rate(t), 1.10), str(q.crops.growth_rate(t)))
	for cell: Vector2i in [Vector2i(23, 21), Vector2i(21, 22), Vector2i(23, 22), Vector2i(21, 23), Vector2i(22, 23)]:
		sp(q, "edamame", cell.x, cell.y)
	ck("edamame_cap_5_plus_25pct", near(q.crops.growth_rate(t), 1.25), "7 around, k capped: %f" % q.crops.growth_rate(t))
	var e_id: int = q.crops.crop_id_at(Vector2i(21, 21))
	var imm: int = sp(q, "edamame", 30, 30, false, true)
	sp(q, "edamame", 31, 30)
	ck("edamame_does_not_affect_edamame_or_self", near(q.crops.growth_rate(imm), 1.0) and near(q.crops.growth_rate(e_id), 1.0), "")
	q.advance(6.0)
	var before: bool = bool(q.crops.get_crop(t).mature)
	q.advance(1.0)
	ck("edamame_speeds_maturity", not before and bool(q.crops.get_crop(t).mature), "bamboo T=8 at x1.25: not at 7.5, yes at 8.75")
	# ドクダミの日陰
	var r: RefCounted = mk()
	var s1: int = sp(r, "dokudami", 30, 12, false, false)
	var s2: int = sp(r, "dokudami", 30, 25, false, false)
	ck("dokudami_shade_growth_x1_5", near(r.crops.growth_rate(s1), 0.75) and near(r.crops.growth_rate(s2), 0.5), "")

# ------------------------------------------------------------------ 黄金系・ミツバチ
func t_gold_bee() -> void:
	var p: RefCounted = mk()
	var cl: int = sp(p, "clover", 20, 22)
	ck("gold_none_baseline", near(rate(p, cl), 2.0 / 60.0), "")
	var g1: int = sp(p, "golden_clover", 20, 25)
	ck("gold_1_plus7pct", near(rate(p, cl), 2.0 / 60.0 * 1.07), "")
	var g2: int = sp(p, "golden_clover", 20, 27)
	ck("gold_2_clover_rate_2per_min_x1_14", near(rate(p, cl), 2.0 / 60.0 * 1.14), str(rate(p, cl) * 60.0))
	ck("gold_self_excluded_goldens_affect_each_other", near(rate(p, g1), 2.0 / 60.0 * 1.07) and near(rate(p, g2), 2.0 / 60.0 * 1.07), "")
	var q: RefCounted = mk()
	var c2: int = sp(q, "clover", 30, 30)
	for x: int in range(24, 30):
		sp(q, "golden_clover", x, 33)
	for x: int in range(24, 27):
		sp(q, "golden_clover", x, 31)
	ck("gold_cap_k7_plus49pct_with_9_sources", near(rate(q, c2), 2.0 / 60.0 * 1.49), "")
	var r: RefCounted = mk()
	var c3: int = sp(r, "clover", 10, 22)
	sp(r, "golden_clover", 2, 22)
	ck("gold_range_8_excluded", near(rate(r, c3), 2.0 / 60.0), "")
	sp(r, "golden_clover", 17, 22)
	ck("gold_range_7_included", near(rate(r, c3), 2.0 / 60.0 * 1.07), "")
	sp(r, "golden_clover", 10, 24, false)
	ck("gold_immature_source_ignored", near(rate(r, c3), 2.0 / 60.0 * 1.07), "")
	# ミツバチ
	var b: RefCounted = mk()
	var bc: int = sp(b, "clover", 20, 22)
	var sf: int = sp(b, "sunflower", 20, 26)
	b.host.hive_list = [{"cell": Vector2i(28, 22)}]
	ck("bee_range_8_plus10pct", near(rate(b, bc), 2.0 / 60.0 * 1.10), "")
	b.host.hive_list = [{"cell": Vector2i(29, 22)}]
	ck("bee_range_9_excluded", near(rate(b, bc), 2.0 / 60.0), "")
	b.host.hive_list = [{"cell": Vector2i(28, 26)}]
	ck("bee_flower_plus20pct", near(rate(b, sf), 3.0 / 60.0 * 1.5 * 1.20), "sunflower day")
	b.host.hive_list = [{"cell": Vector2i(28, 22)}, {"cell": Vector2i(27, 22)}]
	ck("bee_not_stacking", near(rate(b, bc), 2.0 / 60.0 * 1.10), "")
	b.host.hive_list = [{"cell": Vector2i(28, 22), "active": false}]
	ck("bee_inactive_ignored", near(rate(b, bc), 2.0 / 60.0), "")
	var m: RefCounted = mk()
	var mc: int = sp(m, "clover", 20, 22)
	sp(m, "golden_clover", 20, 25)
	sp(m, "golden_clover", 20, 27)
	m.host.hive_list = [{"cell": Vector2i(28, 22)}]
	ck("gold_and_bee_additive_1_24", near(rate(m, mc), 2.0 / 60.0 * 1.24), "")

# ------------------------------------------------------------------ カボチャ
func t_pumpkin() -> void:
	var p: RefCounted = mk()
	var pk: int = sp(p, "pumpkin", 20, 22)
	var t: int = sp(p, "bamboo", 22, 22)
	var e1: Array = p.crops.damage_crop(t, 10.0, {"enemy_id": 1})
	ck("pumpkin_reduces_damage_x0_7", near(float(evs(e1, "crop_damaged")[0].amount), 7.0), "")
	sp(p, "pumpkin", 23, 23)
	var e2: Array = p.crops.damage_crop(t, 10.0, {"enemy_id": 1})
	ck("pumpkin_not_stacking", near(float(evs(e2, "crop_damaged")[0].amount), 7.0), "")
	var q: RefCounted = mk()
	var lone: int = sp(q, "pumpkin", 20, 22)
	var e3: Array = q.crops.damage_crop(lone, 10.0, {"enemy_id": 1})
	ck("pumpkin_self_excluded", near(float(evs(e3, "crop_damaged")[0].amount), 10.0), "")
	var imm_p: RefCounted = mk()
	sp(imm_p, "pumpkin", 20, 22, false)
	var tt: int = sp(imm_p, "bamboo", 22, 22)
	ck("pumpkin_immature_no_effect", near(float(evs(imm_p.crops.damage_crop(tt, 10.0, {}), "crop_damaged")[0].amount), 10.0), "")
	ck("pumpkin_id_valid", pk > 0, "")

# ------------------------------------------------------------------ 毒
func t_poison() -> void:
	var p: RefCounted = mk()
	var ol: int = sp(p, "oleander", 20, 22)
	var ol2: int = sp(p, "oleander", 20, 26)
	var near_c: int = sp(p, "clover", 23, 22, false, false)
	var far_c: int = sp(p, "clover", 25, 22, false, false)
	p.host.helper_list = [{"id": 5, "pos": Vector2(90, 90), "hp": 50.0, "max_hp": 80.0}]
	var all: Array = []
	all.append_array(p.advance(5.0))
	ck("poison_tick_5s_adds_1", int(p.crops.get_crop(near_c).poison) == 1 and int(p.crops.get_crop(far_c).poison) == 0, "range 3: dist2 in, dist4 out")
	all.append_array(p.advance(5.0))
	ck("poison_2_after_10s", int(p.crops.get_crop(near_c).poison) == 2, "")
	ck("poison_alive_before_15s", not p.crops.get_crop(near_c).is_empty(), "")
	all.append_array(p.advance(5.0))
	var rem: Array = evs(all, "crop_removed")
	ck("poison_death_at_15s_refund0_reason", p.crops.get_crop(near_c).is_empty() and rem.size() == 1 and rem[0].reason == "poison" and int(rem[0].refund) == 0, "")
	ck("poison_same_kind_excluded_and_far_unaffected", not p.crops.get_crop(ol).is_empty() and not p.crops.get_crop(ol2).is_empty() and int(p.crops.get_crop(ol2).poison) == 0 and int(p.crops.get_crop(far_c).poison) == 0, "")
	ck("poison_frees_cells_and_family_count", bool(p.crops.place_crop("clover", Vector2i(23, 22)).ok) and p.crops.family_count("clover") == 2, "")
	ck("poison_does_not_touch_helpers", p.host.helper_list.size() == 1 and float(p.host.helper_list[0].hp) == 50.0, "events only target crops")
	var two: RefCounted = mk()
	sp(two, "oleander", 20, 22)
	sp(two, "oleander", 25, 22)
	var tc: int = sp(two, "clover", 23, 24, false, false)
	two.advance(5.0)
	ck("poison_two_sources_still_plus_1", int(two.crops.get_crop(tc).poison) == 1, "")
	# ニンニクの保護
	var g: RefCounted = mk()
	sp(g, "oleander", 20, 22)
	var gc: int = sp(g, "clover", 23, 22, false, false)
	var gg: int = sp(g, "garlic", 23, 24)
	g.advance(30.0)
	ck("garlic_protects_in_range_incl_self", not g.crops.get_crop(gc).is_empty() and not g.crops.get_crop(gg).is_empty() and int(g.crops.get_crop(gc).poison) == 0, "")
	# 範囲外へ出ると0に戻る
	var o: RefCounted = mk()
	var oo: int = sp(o, "oleander", 20, 22)
	var oc: int = sp(o, "clover", 23, 22, false, false)
	o.advance(5.0)
	var was: int = int(o.crops.get_crop(oc).poison)
	o.crops.remove_crop(oo, "manual")
	o.advance(5.0)
	ck("poison_resets_to_0_when_out_of_range", was == 1 and int(o.crops.get_crop(oc).poison) == 0, "")
	var im: RefCounted = mk()
	sp(im, "oleander", 20, 22, false, false)
	var ic: int = sp(im, "clover", 23, 22, false, false)
	im.advance(10.0)
	ck("poison_immature_oleander_inert", int(im.crops.get_crop(ic).poison) == 0, "")

# ------------------------------------------------------------------ 希少変化
func t_variants() -> void:
	var hit: int = seed_where(true, 1.0 / 50.0)
	var p: RefCounted = mk(hit)
	var r: Dictionary = p.crops.place_crop("clover", Vector2i(20, 22))
	var id: int = int(r.id)
	p.crops.set_watered(id, true)
	var ev: Array = p.advance(21.0)
	var c: Dictionary = p.crops.get_crop(id)
	ck("variant_hit_converts_at_maturity", c.kind == "four_leaf_clover" and evs(ev, "variant").size() == 1, "seed=%d" % hit)
	ck("variant_keeps_id_paid_cell_water_progress", int(c.id) == id and int(c.paid) == 10 and c.cell == Vector2i(20, 22) and bool(c.watered) and float(c.grow) >= 20.0 and bool(c.variant_rolled), "")
	ck("variant_x7_rate_and_family", near(rate(p, id), 2.0 / 60.0 * 7.0) and p.crops.family_count("clover") == 1 and p.crops.family_count("golden_clover") == 0, "14/min")
	var st: String = str(p.rng.state)
	var saved: Dictionary = roundtrip(p.to_dict())
	var p2: RefCounted = mk(999)
	var ok: bool = p2.from_dict(saved)
	p.advance(100.0)
	p2.advance(100.0)
	ck("variant_no_reroll_after_save_restore", ok and str(p.rng.state) == st and str(p2.rng.state) == st and p2.crops.get_crop(id).kind == "four_leaf_clover", "")
	# 外れ
	var miss: int = seed_where(false, 1.0 / 50.0)
	var m: RefCounted = mk(miss)
	var mid: int = int(m.crops.place_crop("clover", Vector2i(20, 22)).id)
	m.crops.set_watered(mid, true)
	m.advance(21.0)
	var st2: String = str(m.rng.state)
	m.advance(1000.0)
	ck("variant_miss_stays_and_no_reroll", m.crops.get_crop(mid).kind == "clover" and bool(m.crops.get_crop(mid).variant_rolled) and str(m.rng.state) == st2, "seed=%d" % miss)
	# 黄金の四葉
	var gh: int = seed_where(true, 1.0 / 77.0)
	var g: RefCounted = mk(gh)
	var gid: int = int(g.crops.place_crop("golden_clover", Vector2i(20, 22)).id)
	g.crops.set_watered(gid, true)
	g.advance(778.0)
	ck("golden_variant_x777_and_family", g.crops.get_crop(gid).kind == "golden_four_leaf" and near(rate(g, gid), 2.0 / 60.0 * 777.0) and g.crops.family_count("golden_clover") == 1, "25.9/s")
	ck("golden_variant_price_family_quote", g.crops.quote("golden_clover") == 816, str(g.crops.quote("golden_clover")))
	# 強制抽選(デバッグ)
	var d: RefCounted = mk(3)
	var did: int = sp(d, "clover", 20, 22)
	var de: Array = d.crops.debug_force_roll(did, true)
	var again: Array = d.crops.debug_force_roll(did, true)
	ck("debug_force_roll_once_and_marked", d.crops.get_crop(did).kind == "four_leaf_clover" and bool(evs(de, "variant")[0].debug) and again.is_empty(), "")

# ------------------------------------------------------------------ ミント
func t_mint() -> void:
	var p: RefCounted = mk(5)
	var id: int = int(p.crops.place_crop("mint", Vector2i(20, 22)).id)
	p.crops.set_watered(id, true)
	p.crops.debug_force_mature(id)
	var ev: Array = p.advance(31.0)
	var sp_ev: Array = evs(ev, "mint_spread")
	var nid: int = int(sp_ev[0].crop_id) if sp_ev.size() == 1 else -1
	var nc: Dictionary = p.crops.get_crop(nid)
	var adj: bool = not nc.is_empty() and absi(nc.cell.x - 20) + absi(nc.cell.y - 22) == 1
	ck("mint_spread_30s_adjacent_paid0_same_colony", sp_ev.size() == 1 and adj and int(nc.paid) == 0 and int(nc.colony_id) == id and not bool(nc.mature), "")
	ck("mint_spread_counts_in_family", p.crops.family_count("mint") == 2 and p.host.price("mint", 2) == 17, "")
	ck("mint_spread_refund_0", int(p.crops.remove_crop(nid, "manual").refund) == 0, "")
	var q: RefCounted = mk(6)
	var qid: int = int(q.crops.place_crop("mint", Vector2i(30, 30)).id)
	q.crops.set_watered(qid, true)
	q.crops.debug_force_mature(qid)
	var peak: int = 0
	for i: int in range(0, 120):
		q.advance(10.0)
		peak = maxi(peak, q.crops.family_count("mint"))
	var paid_sum: int = 0
	for c: Dictionary in q.crops.crops:
		paid_sum += int(c.paid)
	ck("mint_colony_cap_9_total", peak == 9 and q.crops.family_count("mint") == 9, "peak=%d" % peak)
	ck("mint_next_price_counts_spread", q.crops.quote("mint") == 24 and paid_sum == 15, "quote=%d paid_sum=%d" % [q.crops.quote("mint"), paid_sum])

# ------------------------------------------------------------------ イチゴ・ジャガイモ
func t_strawberry_potato() -> void:
	var p: RefCounted = mk(7)
	var id: int = sp(p, "strawberry", 20, 22)
	p.advance(21.0)
	var first: Dictionary = p.crops.pickups[0] if p.crops.pickups.size() > 0 else {}
	var ccell: Vector2i = Grid.cell_of_pos(first.pos) if not first.is_empty() else Vector2i.ZERO
	ck("strawberry_drops_adjacent_6_seeds", p.crops.pickups.size() == 1 and int(first.amount) == 6 and (ccell.x == 19 or ccell.x == 21 or ccell.y == 21 or ccell.y == 23) and absi(ccell.x - 20) + absi(ccell.y - 22) == 1, str(ccell))
	p.advance(100.0)
	ck("strawberry_max_3_pickups", p.crops.pickups.size() == 3, str(p.crops.pickups.size()))
	var target: Vector2 = p.crops.pickups[0].pos
	p.host.hero_state = {"pos": target, "hp": 50.0, "max_hp": 100.0}
	var ev: Array = p.advance(1.0)
	var got: Array = evs(ev, "pickup_collected")
	ck("strawberry_pickup_collected_by_hero", got.size() >= 1 and int(got[0].amount) == 6 and p.crops.pickups.size() <= 2, "")
	p.host.hero_state = {}
	p.advance(21.0)
	var left: int = p.crops.pickups.size()
	p.crops.remove_crop(id, "manual")
	var p2: RefCounted = mk(7)
	var ok: bool = p2.from_dict(roundtrip(p.to_dict()))
	ck("strawberry_pickups_persist_after_remove_and_restore", ok and p.crops.pickups.size() == left and p2.crops.pickups.size() == left and left >= 1, "")
	# ジャガイモ
	var q: RefCounted = mk()
	var pid: int = sp(q, "potato", 20, 22)
	var ev2: Array = q.advance(100.0)
	var stor: float = float(q.crops.get_crop(pid).storage)
	ck("potato_stores_instead_of_producing", near(stor, 100.0 * 8.0 / 60.0) and evs(ev2, "seeds").is_empty(), "storage=%f" % stor)
	var rm: Dictionary = q.crops.remove_crop(pid, "manual")
	ck("potato_remove_refund_floor20pct_plus_floor_storage", int(rm.refund) == 6 + 13, "refund=%d" % int(rm.refund))
	var cap: int = sp(q, "potato", 24, 22)
	q.advance(2500.0)
	ck("potato_cap_is_paid_x10", near(float(q.crops.get_crop(cap).storage), 300.0), "")
	ck("potato_full_refund_306", int(q.crops.remove_crop(cap, "manual").refund) == 306, "")
	var e: int = sp(q, "potato", 24, 22)
	q.advance(100.0)
	var dm: Array = q.crops.damage_crop(e, 1000.0, {"enemy_id": 3})
	var rr: Array = evs(dm, "crop_removed")
	ck("potato_destroyed_by_enemy_refund_0", rr.size() == 1 and rr[0].reason == "enemy" and int(rr[0].refund) == 0, "")

# ------------------------------------------------------------------ 条件付き倍率
func t_conditions() -> void:
	var p: RefCounted = mk()
	var t1: int = sp(p, "tomato", 27, 16)
	var t2: int = sp(p, "tomato", 25, 16)
	ck("tomato_wall_adjacent_x1_75", near(rate(p, t1), 7.0 / 60.0) and near(rate(p, t2), 4.0 / 60.0), "")
	# ブドウ
	var g: RefCounted = mk()
	var ids: Array = []
	for x: int in range(20, 24):
		ids.append(sp(g, "grape", x, 22))
	ck("grape_line_4_x1_45", near(rate(g, ids[0]), 2.0 / 60.0 * 1.45), "")
	sp(g, "grape", 20, 23)
	var last: int = sp(g, "grape", 20, 24)
	ck("grape_uses_longer_of_row_col", near(rate(g, ids[0]), 2.0 / 60.0 * 1.45) and near(rate(g, last), 2.0 / 60.0 * 1.30), "")
	var g2: RefCounted = mk()
	var first: int = sp(g2, "grape", 10, 30)
	for x: int in range(11, 20):
		sp(g2, "grape", x, 30)
	ck("grape_cap_L8_x2_05", near(rate(g2, first), 2.0 / 60.0 * 2.05), "")
	# イネ
	var r: RefCounted = mk()
	var rid: int = sp(r, "rice", 16, 4)
	for cell: Vector2i in [Vector2i(17, 4), Vector2i(16, 5), Vector2i(17, 5), Vector2i(16, 6), Vector2i(17, 6)]:
		sp(r, "rice", cell.x, cell.y)
	var ext: int = sp(r, "rice", 16, 7)
	ck("rice_max_rect_area6_x1_2", near(rate(r, rid), 1.5 / 60.0 * 1.2), "")
	ck("rice_L_shape_uses_own_max_rect", near(rate(r, ext), 1.5 / 60.0 * 1.12), "extra cell: 1x4=4")
	# トウモロコシ
	var c: RefCounted = mk()
	var corn: int = sp(c, "corn", 20, 22)
	var ed: int = sp(c, "edamame", 21, 22, false)
	ck("corn_immature_partner_ignored", near(rate(c, corn), 3.0 / 60.0), "")
	c.crops.debug_force_mature(ed)
	ck("corn_edamame_x1_3", near(rate(c, corn), 3.0 / 60.0 * 1.3), "")
	sp(c, "pumpkin", 18, 22)
	ck("corn_three_sisters_x1_8", near(rate(c, corn), 3.0 / 60.0 * 1.8), "")
	c.crops.remove_crop(ed, "manual")
	ck("corn_pumpkin_only_x1_3", near(rate(c, corn), 3.0 / 60.0 * 1.3), "")
	# チャノキ
	var t: RefCounted = mk()
	var tea: int = sp(t, "tea", 20, 22)
	t.advance(120.0)
	ck("tea_aging_plus4pct_at_120s", near(float(t.crops.production_info(tea).condition), 1.04), "")
	t.advance(2880.0)
	ck("tea_cap_x2", near(rate(t, tea), 3.0 / 60.0 * 2.0), "")
	t.advance(3000.0)
	ck("tea_stays_capped", near(rate(t, tea), 3.0 / 60.0 * 2.0), "")
	# サクラ
	var s: RefCounted = mk()
	var sk: int = sp(s, "sakura", 20, 22)
	s.advance(10.0)
	ck("sakura_bloom_x4", near(rate(s, sk), 6.0 / 60.0 * 4.0), "")
	s.host.hive_list = [{"cell": Vector2i(28, 22)}]
	ck("sakura_bloom_is_flower_bee_plus20", near(rate(s, sk), 24.0 / 60.0 * 1.2), "")
	s.advance(40.0)
	ck("sakura_off_bloom_x1_not_flower", near(rate(s, sk), 6.0 / 60.0 * 1.1), "since=50")
	s.host.hive_list = []
	s.advance(190.0)
	ck("sakura_next_cycle_blooms_at_240", near(rate(s, sk), 24.0 / 60.0), "")
	# ヒマワリ
	var f: RefCounted = mk()
	var sf: int = sp(f, "sunflower", 20, 22)
	var ev: Array = f.advance(60.0)
	var sum: float = 0.0
	for e: Dictionary in evs(ev, "seeds"):
		sum += float(e.amount)
	ck("sunflower_day_60s_yields_4_5", near(sum, 4.5), str(sum))
	f.host.day = false
	ck("sunflower_night_x0_3", near(rate(f, sf), 3.0 / 60.0 * 0.3), "")
	# ドクダミ
	var d: RefCounted = mk()
	var s1: int = sp(d, "dokudami", 30, 12)
	var s2: int = sp(d, "dokudami", 30, 25)
	ck("dokudami_shade_production_x2", near(rate(d, s1), 4.0 / 60.0) and near(rate(d, s2), 2.0 / 60.0), "")

# ------------------------------------------------------------------ 能力(ハエトリソウ・アロエ)
func t_abilities() -> void:
	var p: RefCounted = mk()
	var fl: int = sp(p, "flytrap", 20, 22)
	ck("flytrap_beast_not_captured", not bool(p.crops.flytrap_capture(1, Vector2i(21, 22), ["beast"]).captured), "")
	ck("flytrap_2_away_not_captured", not bool(p.crops.flytrap_capture(1, Vector2i(22, 22), ["small"]).captured), "")
	var cap: Dictionary = p.crops.flytrap_capture(1, Vector2i(21, 22), ["small"])
	ck("flytrap_small_adjacent_captured_30dmg", bool(cap.captured) and near(float(cap.damage), 30.0), "")
	ck("flytrap_digesting_cannot_capture_and_x3", not bool(p.crops.flytrap_capture(2, Vector2i(19, 22), ["small"]).captured) and near(rate(p, fl), 0.5 / 60.0 * 3.0), "")
	p.advance(21.0)
	ck("flytrap_digest_ends_after_20s", near(rate(p, fl), 0.5 / 60.0) and bool(p.crops.flytrap_capture(2, Vector2i(19, 22), ["small"]).captured), "")
	# アロエ
	var a: RefCounted = mk()
	sp(a, "aloe", 20, 22)
	a.host.hero_state = {"pos": Vector2(90, 90), "hp": 20.0, "max_hp": 100.0}
	var heals: Array = evs(a.advance(1.0), "heal")
	ck("aloe_heals_30_below_50pct", heals.size() == 1 and near(float(heals[0].amount), 30.0) and heals[0].target == "hero", "")
	var h2: Array = evs(a.advance(30.0), "heal")
	ck("aloe_cooldown_60s", h2.is_empty(), "")
	var h3: Array = evs(a.advance(31.0), "heal")
	ck("aloe_heals_again_after_cooldown", h3.size() == 1, "")
	var b: RefCounted = mk()
	sp(b, "aloe", 20, 22)
	b.host.hero_state = {"pos": Vector2(90, 90), "hp": 60.0, "max_hp": 100.0}
	ck("aloe_no_heal_at_60pct", evs(b.advance(5.0), "heal").is_empty(), "")
	b.host.hero_state = {"pos": Vector2(90, 90), "hp": 40.0, "max_hp": 100.0}
	b.host.helper_list = [{"id": 7, "pos": Vector2(94, 90), "hp": 10.0, "max_hp": 100.0}]
	var hh: Array = evs(b.advance(1.0), "heal")
	ck("aloe_picks_lowest_ratio_helper", hh.size() == 1 and hh[0].target == "helper" and int(hh[0].target_id) == 7, "")
	var far: RefCounted = mk()
	sp(far, "aloe", 20, 22)
	far.host.hero_state = {"pos": Vector2(300, 90), "hp": 5.0, "max_hp": 100.0}
	ck("aloe_out_of_range_no_heal", evs(far.advance(5.0), "heal").is_empty(), "")

# ------------------------------------------------------------------ 第2段(敵)が使う口
func t_enemy_api() -> void:
	var p: RefCounted = mk()
	var pep: int = sp(p, "pepper", 20, 22)
	var e1: Array = p.crops.damage_crop(pep, 5.0, {"enemy_id": 1})
	var c1: Array = evs(e1, "pepper_counter")
	ck("pepper_counter_2dmg_flee3", c1.size() == 1 and near(float(c1[0].damage), 2.0) and near(float(c1[0].flee_seconds), 3.0), "")
	ck("pepper_same_enemy_5s_cooldown", evs(p.crops.damage_crop(pep, 5.0, {"enemy_id": 1}), "pepper_counter").is_empty(), "")
	ck("pepper_other_enemy_triggers", evs(p.crops.damage_crop(pep, 5.0, {"enemy_id": 2}), "pepper_counter").size() == 1, "")
	ck("pepper_collateral_does_not_trigger", evs(p.crops.damage_crop(pep, 5.0, {"enemy_id": 3, "cause": "collateral"}), "pepper_counter").is_empty(), "")
	p.advance(6.0)
	ck("pepper_triggers_again_after_5s", evs(p.crops.damage_crop(pep, 1.0, {"enemy_id": 1}), "pepper_counter").size() == 1, "")
	# サボテン
	var c: RefCounted = mk()
	c.crops.place_crop("cactus", Vector2i(46, 26))
	ck("cactus_thorn_on_adjacent_cell", evs(c.crops.enemy_moved(9, Vector2i(47, 26)), "cactus_thorn").size() == 1, "")
	ck("cactus_thorn_1s_cooldown", evs(c.crops.enemy_moved(9, Vector2i(47, 26)), "cactus_thorn").is_empty(), "")
	ck("cactus_diagonal_not_adjacent", evs(c.crops.enemy_moved(8, Vector2i(47, 27)), "cactus_thorn").is_empty(), "")
	c.advance(1.5)
	var thorn: Array = evs(c.crops.damage_crop(c.crops.crop_id_at(Vector2i(46, 26)), 4.0, {"enemy_id": 9}), "cactus_thorn")
	ck("cactus_thorn_on_attack_3dmg", thorn.size() == 1 and near(float(thorn[0].damage), 3.0), "")
	# ラベンダー・ニンニク・タケ
	var l: RefCounted = mk()
	sp(l, "lavender", 20, 22)
	var tgt: int = sp(l, "bamboo", 23, 22)
	var far_t: int = sp(l, "bamboo", 30, 30)
	var zones: Array = l.crops.repel_zones("bug")
	ck("lavender_zone_bug_radius4", zones.size() == 1 and zones[0].rect == Rect2i(16, 18, 9, 9) and l.crops.repel_zones("beast").is_empty(), "")
	ck("lavender_is_repelled_cell", l.crops.is_repelled_cell(Vector2i(16, 18), ["bug"]) and not l.crops.is_repelled_cell(Vector2i(15, 18), ["bug"]), "")
	ck("lavender_untargets_crops_for_bugs_only", not l.crops.crop_targetable_by(["bug"], tgt) and l.crops.crop_targetable_by(["beast"], tgt) and l.crops.crop_targetable_by(["bug"], far_t), "")
	var im: RefCounted = mk()
	sp(im, "lavender", 20, 22, false)
	ck("lavender_immature_inactive", im.crops.repel_zones("bug").is_empty(), "")
	var g: RefCounted = mk()
	sp(g, "garlic", 20, 22)
	var gin: int = sp(g, "bamboo", 23, 22)
	var gout: int = sp(g, "bamboo", 24, 22)
	ck("garlic_untargetable_for_all_tags_in_3", not g.crops.crop_targetable_by(["beast"], gin) and not g.crops.crop_targetable_by(["bug", "small"], gin) and g.crops.crop_targetable_by(["beast"], gout), "")
	var b: RefCounted = mk()
	var bm: int = sp(b, "bamboo", 20, 22)
	var bi: int = sp(b, "bamboo", 22, 22, false)
	ck("bamboo_blocks_only_when_mature", b.crops.blocks_enemy(Vector2i(20, 22)) and not b.crops.blocks_enemy(Vector2i(22, 22)) and not b.crops.blocks_enemy(Vector2i(21, 22)), "")
	var kill: Array = b.crops.damage_crop(bm, 100.0, {"enemy_id": 1})
	var rm: Array = evs(kill, "crop_removed")
	ck("bamboo_destroyed_by_enemy_refund0", rm.size() == 1 and int(rm[0].refund) == 0 and not b.crops.blocks_enemy(Vector2i(20, 22)) and bi > 0, "")
	# ヒカリゴケ
	var m: RefCounted = mk()
	sp(m, "glow_moss", 20, 22)
	sp(m, "glow_moss", 40, 22, false)
	m.host.day = false
	ck("glow_moss_reveals_at_night_within_5", m.crops.glow_moss_reveals(Vector2i(25, 22)) and not m.crops.glow_moss_reveals(Vector2i(26, 22)) and not m.crops.glow_moss_reveals(Vector2i(40, 22)), "")
	m.host.day = true
	ck("glow_moss_inactive_by_day", not m.crops.glow_moss_reveals(Vector2i(25, 22)), "")
	# ウサギの横取り
	var r: RefCounted = mk()
	var sf: int = sp(r, "sunflower", 20, 22)
	r.crops.set_gnawed(sf, true)
	var ev: Array = r.advance(1.0)
	ck("gnawed_production_goes_to_seeds_stolen", evs(ev, "seeds").is_empty() and evs(ev, "seeds_stolen").size() == 1 and near(float(evs(ev, "seeds_stolen")[0].amount), 4.5 / 60.0), "")
	r.crops.set_gnawed(sf, false)
	ck("gnawed_cleared_returns_to_player", evs(r.advance(1.0), "seeds").size() == 1, "")

# ------------------------------------------------------------------ 返還・価格系統
func t_refund_price() -> void:
	var p: RefCounted = mk()
	var a: int = int(p.crops.place_crop("clover", Vector2i(20, 22)).id)
	ck("manual_refund_20pct_floor_clover", int(p.crops.remove_crop(a, "manual").refund) == 2, "")
	var g: int = int(p.crops.spawn_crop("golden_clover", Vector2i(20, 22), 777).id)
	ck("manual_refund_golden_155", int(p.crops.remove_crop(g, "manual").refund) == 155, "")
	var q: RefCounted = mk()
	q.crops.place_crop("clover", Vector2i(20, 22))
	sp(q, "four_leaf_clover", 22, 22)
	ck("family_clover_counts_four_leaf_price_12", q.crops.family_count("clover") == 2 and q.crops.quote("clover") == 12, "ceil(10*1.05^2)")
	sp(q, "golden_clover", 24, 22)
	sp(q, "golden_four_leaf", 26, 22)
	ck("family_golden_counts_golden_four_price_857", q.crops.family_count("golden_clover") == 2 and q.crops.quote("golden_clover") == 857, "ceil(777*1.05^2)")
	var e: int = int(q.crops.place_crop("bamboo", Vector2i(30, 30)).id)
	var ev: Array = q.crops.damage_crop(e, 1000.0, {"enemy_id": 1})
	ck("enemy_loss_refund_0_and_count_drops", int(evs(ev, "crop_removed")[0].refund) == 0 and q.crops.family_count("bamboo") == 0, "")

# ------------------------------------------------------------------ 保存復元・ポーズ
func t_save_restore() -> void:
	var a: RefCounted = mk(42)
	var m: int = int(a.crops.place_crop("mint", Vector2i(30, 30)).id)
	a.crops.set_watered(m, true)
	for x: int in range(10, 16):
		var cid: int = int(a.crops.place_crop("clover", Vector2i(x, 24)).id)
		a.crops.set_watered(cid, true)
	var s: int = int(a.crops.place_crop("strawberry", Vector2i(20, 30)).id)
	a.crops.set_watered(s, true)
	sp(a, "oleander", 40, 22)
	sp(a, "clover", 43, 22, false, false)
	sp(a, "tea", 50, 22)
	var po: int = sp(a, "potato", 50, 20)
	for i: int in range(0, 20):
		a.advance(5.0)
	var saved: Dictionary = roundtrip(a.to_dict())
	var b: RefCounted = mk(1)
	var ok: bool = b.from_dict(saved)
	for i: int in range(0, 60):
		a.advance(5.0)
		b.advance(5.0)
	ck("restore_then_same_result_incl_rng_pickups", ok and snap(a) == snap(b) and near(float(a.time()), float(b.time())), snap(a).substr(0, 120))
	ck("restore_potato_storage_close", absf(float(a.crops.get_crop(po).storage) - float(b.crops.get_crop(po).storage)) < 1e-6, "")
	# 不正データは状態を変えない
	var before: String = JSON.stringify(a.to_dict())
	var bad1: Dictionary = roundtrip(a.to_dict())
	bad1.crops.crops[0].kind = "no_such_kind"
	var bad2: Dictionary = roundtrip(a.to_dict())
	bad2.crops.crops[1].cell = bad2.crops.crops[0].cell
	var bad3: Dictionary = roundtrip(a.to_dict())
	bad3.rng.state = "abc"
	var bad4: Dictionary = roundtrip(a.to_dict())
	bad4.crops.crops[0].grow = "x"
	var res: Array = [a.from_dict(bad1), a.from_dict(bad2), a.from_dict(bad3), a.from_dict(bad4), a.from_dict({})]
	ck("from_dict_rejects_invalid_and_keeps_state", not res.has(true) and JSON.stringify(a.to_dict()) == before, str(res))
	# ポーズ
	var ev1: Array = a.advance(0.0)
	var ev2: Array = a.advance(-3.0)
	ck("paused_no_advance_no_change", ev1.is_empty() and ev2.is_empty() and JSON.stringify(a.to_dict()) == before, "advance not called/0 => unchanged")
