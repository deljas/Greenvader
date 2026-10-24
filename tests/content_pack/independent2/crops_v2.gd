extends SceneTree
## 独立検証2-C: 栽培植物8種と第1弾との関わり。入口スクリプト。
const L: GDScript = preload("res://tests/content_pack/independent2/lib2.gd")
const OUT: String = "res://evidence/content_pack/independent2"
var t: RefCounted = L.new()

func _initialize() -> void:
	primrose()
	dandelion()
	mimosa()
	kudzu()
	loofah()
	hinoki()
	apple()
	balsam()
	catalog_numbers()
	t.finish("crops_v2", OUT, self)

func rate(p: RefCounted, id: int) -> float:
	return float(p.crops.production_info(id).rate) * 60.0

func cond(p: RefCounted, id: int) -> float:
	return float(p.crops.production_info(id).condition)

# ---------------------------------------------------------------- ツキミソウ
func primrose() -> void:
	var p: RefCounted = t.mk()
	var id: int = t.crop(p, "evening_primrose", 10, 20)
	p.host.day = true
	t.ck("primrose_day_x0_3", t.near(cond(p, id), 0.3) and t.near(rate(p, id), 0.9, 0.001), "cond=%s rate=%s" % [str(cond(p, id)), str(rate(p, id))])
	p.host.day = false
	t.ck("primrose_night_x1_5", t.near(cond(p, id), 1.5) and t.near(rate(p, id), 4.5, 0.001), "rate=%s" % str(rate(p, id)))
	# ヒマワリと逆
	var sf: int = t.crop(p, "sunflower", 14, 20)
	t.ck("sunflower_opposite_night_low", cond(p, sf) < 1.0)
	p.host.day = true
	t.ck("sunflower_day_high", cond(p, sf) > 1.0)
	# 夜だけ花のタグ(ミツバチ+20%): 巣を近くに置く
	p.host.hive_list = [{"cell": Vector2i(10, 24), "size": Vector2i(1, 1), "active": true}]
	p.host.day = true
	var b_day: float = float(p.crops.bee_bonus(p.crops.get_crop(id)))
	p.host.day = false
	var b_night: float = float(p.crops.bee_bonus(p.crops.get_crop(id)))
	t.ck("primrose_flower_tag_only_at_night", t.near(b_day, 0.10) and t.near(b_night, 0.20), "day=%s night=%s" % [str(b_day), str(b_night)])
	# 未成熟は生産しない
	var im: int = t.crop(p, "evening_primrose", 20, 20, false)
	t.ck("primrose_immature_zero", t.near(float(p.crops.production_info(im).rate), 0.0))
	# 成長: 30秒(給水済み x1.0)
	var gp: RefCounted = t.mk()
	var gid: int = t.crop(gp, "evening_primrose", 10, 20, false)
	t.sim(gp, 29.0, 1.0)
	var m1: bool = bool(gp.crops.get_crop(gid).mature)
	t.sim(gp, 2.0, 1.0)
	t.ck("primrose_matures_at_30s", (not m1) and bool(gp.crops.get_crop(gid).mature))

# ---------------------------------------------------------------- タンポポ
func dandelion() -> void:
	var p: RefCounted = t.mk(11)
	var id: int = t.crop(p, "dandelion", 49, 27)   # 荒地(播種できる有効マスがあるのは荒地)
	var stock0: int = p.crops.crops.size()
	var tl: Array = t.sim(p, 39.0, 1.0)
	t.ck("dandelion_no_sow_before_40s", t.of_type(tl, "seed_sow").is_empty())
	tl.append_array(t.sim(p, 2.0, 1.0))
	var sows: Array = t.of_type(tl, "seed_sow")
	t.ck("dandelion_sows_one_at_40s", sows.size() == 1 and t.near(float(sows[0].t), 40.0, 1.1), "n=%d t=%s" % [sows.size(), str(sows[0].t) if sows.size() > 0 else "-"])
	if sows.size() == 1:
		var e: Dictionary = sows[0].e
		var cell: Vector2i = e.cell
		var dist: int = maxi(absi(cell.x - 49), absi(cell.y - 27))
		t.ck("dandelion_range_3_to_6", dist >= 3 and dist <= 6, "dist=%d" % dist)
		t.ck("dandelion_no_stock_consumption", e.consume_stock == false and e.source == "dandelion")
	t.ck("dandelion_does_not_multiply", p.crops.crops.size() == stock0 and p.crops.family_count("dandelion") == 1)
	# 有効マスだけ: 候補を2マスだけ残して、あとはブロック/水/種にする
	var q: RefCounted = t.mk(11)
	var qid: int = t.crop(q, "dandelion", 49, 27)
	var keep: Array = [Vector2i(52, 27), Vector2i(49, 30)]
	for y: int in range(20, 35):
		for x: int in range(42, 58):
			var c: Vector2i = Vector2i(x, y)
			var d: int = maxi(absi(x - 49), absi(y - 27))
			if d >= 3 and d <= 6 and not keep.has(c):
				q.host.blocked_cells[c] = true
	var seen: Dictionary = {}
	for i: int in range(6):
		var qt: Array = t.sim(q, 41.0, 1.0)
		for s: Dictionary in t.of_type(qt, "seed_sow"):
			seen[Vector2i(s.e.cell)] = true
			q.host.set_stage(Vector2i(s.e.cell), "grass")   # 播種済みのマスを草にして、次は別の候補だけが残る状態にする
	t.ck("dandelion_only_valid_cells", seen.size() >= 1 and seen.keys().all(func(c: Vector2i) -> bool: return keep.has(c)), str(seen.keys()))
	# 候補なし: 飛ばさない。乱数も使わない
	var n: RefCounted = t.mk(11)
	t.crop(n, "dandelion", 49, 27)
	for y: int in range(18, 36):
		for x: int in range(40, 60):
			if maxi(absi(x - 49), absi(y - 27)) >= 3 and maxi(absi(x - 49), absi(y - 27)) <= 6:
				n.host.blocked_cells[Vector2i(x, y)] = true
	var rs0: int = n.rng.state
	var nt: Array = t.sim(n, 45.0, 1.0)
	t.ck("dandelion_no_candidates_no_sow_no_rng", t.of_type(nt, "seed_sow").is_empty() and n.rng.state == rs0)
	# 専用の乱数: 同じシードで同じ結果、グローバル乱数の影響を受けない
	var r1: Array = []
	for seed: int in [5, 5, 6]:
		seed(12345)
		var pr: RefCounted = t.mk(seed)
		t.crop(pr, "dandelion", 49, 27)
		var rt: Array = t.sim(pr, 41.0, 1.0)
		var ss: Array = t.of_type(rt, "seed_sow")
		r1.append(Vector2i(ss[0].e.cell) if ss.size() > 0 else Vector2i(-1, -1))
	t.ck("dandelion_rng_deterministic_by_pack_seed", r1[0] == r1[1], str(r1))
	# 成熟前は飛ばさない
	var im: RefCounted = t.mk(11)
	t.crop(im, "dandelion", 49, 27, false)
	var imt: Array = t.sim(im, 20.0, 1.0)
	t.ck("dandelion_immature_no_sow", t.of_type(imt, "seed_sow").is_empty())

# ---------------------------------------------------------------- オジギソウ
func mimosa() -> void:
	var p: RefCounted = t.mk()
	t.hero(p, 240, 130)
	var id: int = t.crop(p, "mimosa", 20, 20)   # px (80..84, 80..84)
	t.ck("mimosa_open_production", t.near(cond(p, id), 1.0))
	# 2m(20px)の外
	var far: int = t.sp(p, "skunk", 84 + 25, 82)
	p.enemies.defs["skunk"].speed_mps = 0.0
	t.sim(p, 0.5, 0.5)
	t.ck("mimosa_open_when_enemy_beyond_2m", not bool(p.crops.get_crop(id).ext.closed))
	t.R(p, far).pos = Vector2(84 + 15, 82)
	t.sim(p, 0.5, 0.5)
	var c: Dictionary = p.crops.get_crop(id)
	t.ck("mimosa_closes_when_enemy_within_2m", bool(c.ext.closed) and t.near(cond(p, id), 0.0))
	t.ck("mimosa_closed_production_zero", t.near(float(p.crops.production_info(id).rate), 0.0))
	# 被ダメ x0.2
	var hp0: float = float(p.crops.get_crop(id).hp)
	p.crops.damage_crop(id, 10.0, {"cause": "collateral"})
	t.ck("mimosa_closed_damage_x0_2", t.near(hp0 - float(p.crops.get_crop(id).hp), 2.0), "dealt=%s" % str(hp0 - float(p.crops.get_crop(id).hp)))
	# 離れて4秒で開く
	t.R(p, far).pos = Vector2(200, 130)
	t.sim(p, 3.0, 0.5)
	t.ck("mimosa_still_closed_3s", bool(p.crops.get_crop(id).ext.closed))
	t.sim(p, 1.5, 0.5)
	t.ck("mimosa_reopens_after_4s", not bool(p.crops.get_crop(id).ext.closed))
	# 攻撃を受けても閉じる(この一撃は閉じる前の扱い)
	var q: RefCounted = t.mk()
	var qid: int = t.crop(q, "mimosa", 20, 20)
	var h1: float = float(q.crops.get_crop(qid).hp)
	q.crops.damage_crop(qid, 10.0, {"cause": "attack"})
	t.ck("mimosa_first_hit_full_then_closes", t.near(h1 - float(q.crops.get_crop(qid).hp), 10.0) and bool(q.crops.get_crop(qid).ext.closed))
	# 中立(ガラスジカ)では閉じない
	var nn: RefCounted = t.mk()
	t.hero(nn, 240, 130)
	var nid: int = t.crop(nn, "mimosa", 20, 20)
	var gd: int = t.sp(nn, "glass_deer", 90, 82)
	nn.enemies.defs["glass_deer"].speed_mps = 0.0
	t.sim(nn, 1.0, 0.5)
	t.ck("mimosa_ignores_neutral", not bool(nn.crops.get_crop(nid).ext.closed))
	# ミツバチ(中立)の群れでも同様
	# カボチャと掛け合わせ: 10 -> 0.7 -> 0.2 = 1.4
	var pk: RefCounted = t.mk()
	var mid: int = t.crop(pk, "mimosa", 20, 20)
	t.crop(pk, "pumpkin", 21, 20)
	pk.crops.damage_crop(mid, 1.0, {"cause": "collateral"})   # 先に閉じる
	var hb: float = float(pk.crops.get_crop(mid).hp)
	pk.crops.damage_crop(mid, 10.0, {"cause": "collateral"})
	t.ck("mimosa_pumpkin_stack_1_4", t.near(hb - float(pk.crops.get_crop(mid).hp), 1.4, 0.001), "dealt=%s" % str(hb - float(pk.crops.get_crop(mid).hp)))
	# 敵がいなくなってからではなく、敵が居続ける間は開かない
	var st: RefCounted = t.mk()
	t.hero(st, 240, 130)
	var sid: int = t.crop(st, "mimosa", 20, 20)
	var sk: int = t.sp(st, "skunk", 99, 82)
	st.enemies.defs["skunk"].speed_mps = 0.0
	t.sim(st, 10.0, 0.5)
	t.ck("mimosa_stays_closed_while_enemy_near", bool(st.crops.get_crop(sid).ext.closed))

# ---------------------------------------------------------------- クズ
func kudzu() -> void:
	var p: RefCounted = t.mk(3)
	var id: int = t.crop(p, "kudzu", 30, 24)
	var tl: Array = t.sim(p, 14.0, 1.0)
	t.ck("kudzu_no_root_before_15s", t.of_type(tl, "kudzu_root_added").is_empty())
	tl.append_array(t.sim(p, 2.0, 1.0))
	t.ck("kudzu_first_root_at_15s", t.of_type(tl, "kudzu_root_added").size() == 1 and t.near(float(t.of_type(tl, "kudzu_root_added")[0].t), 15.0, 1.1))
	var r0: Vector2i = p.crops.root_cells(id)[0]
	t.ck("kudzu_first_root_adjacent_to_stock", maxi(absi(r0.x - 30), absi(r0.y - 24)) == 1 and (r0.x == 30 or r0.y == 24), str(r0))
	# 生産 1 + 0.15/根
	t.ck("kudzu_production_with_root", t.near(cond(p, id), 1.15, 0.001) and t.near(rate(p, id), 1.15, 0.001), "cond=%s" % str(cond(p, id)))
	# 根のマスに他の植物は植えられない(占有)
	var chk: Dictionary = p.crops.check_placement("clover", r0)
	t.ck("kudzu_root_occupied", not bool(chk.ok) and chk.reason == "occupied", str(chk))
	# 隣接する他種は x0.8、同種は影響なし
	var side: Vector2i = r0 + Vector2i(1, 0) if p.crops.crop_id_at(r0 + Vector2i(1, 0)) == 0 else r0 + Vector2i(-1, 0)
	var adj_other: Vector2i = Vector2i(-1, -1)
	for dd: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var cc: Vector2i = r0 + dd
		if p.crops.crop_id_at(cc) == 0 and p.crops.root_owner(cc) == 0 and cc != Vector2i(30, 24):
			adj_other = cc
			break
	var oid: int = t.crop(p, "clover", adj_other.x, adj_other.y)
	t.ck("kudzu_neighbor_other_kind_x0_8", t.near(cond(p, oid), 0.8, 0.001), "cond=%s" % str(cond(p, oid)))
	var far_c: int = t.crop(p, "clover", 5, 30)
	t.ck("kudzu_nonadjacent_unaffected", t.near(cond(p, far_c), 1.0))
	# 敵が根を通ると移動 x0.6
	t.ck("kudzu_enemy_speed_x0_6_on_root", t.near(p.crops.enemy_speed_mult(r0), 0.6) and t.near(p.crops.enemy_speed_mult(Vector2i(0, 0)), 1.0))
	# 実際の敵の移動で確認: 根の上と外で同じ時間に進む距離の比
	var sp1: RefCounted = t.mk(3)
	var kid: int = t.crop(sp1, "kudzu", 30, 24)
	sp1.crops.crops[0].ext.roots.append(Vector2i(28, 28))
	sp1.crops._root_occ[Vector2i(28, 28)] = kid
	t.hero(sp1, 240, 130)
	var wolf: int = t.sp(sp1, "stray_wolf", 114, 114)   # 根のマス(28,28)の中
	var w2: int = t.sp(sp1, "stray_wolf", 40, 114)
	var pos0: Vector2 = t.R(sp1, wolf).pos
	var ev0: Array[Dictionary] = []
	sp1.enemies.step_move(t.R(sp1, wolf), Vector2.LEFT, 100.0, 0.1, ev0)
	var moved_root: float = pos0.distance_to(t.R(sp1, wolf).pos)
	var pos1: Vector2 = t.R(sp1, w2).pos
	sp1.enemies.step_move(t.R(sp1, w2), Vector2.LEFT, 100.0, 0.1, ev0)
	var moved_plain: float = pos1.distance_to(t.R(sp1, w2).pos)
	t.ck("kudzu_root_slows_enemy_actual_move", t.near(moved_root / maxf(moved_plain, 1e-6), 0.6, 0.02), "root=%.2f plain=%.2f" % [moved_root, moved_plain])
	# 距離4まで・最大24・順次
	var tl2: Array = t.sim(p, 15.0 * 30.0, 1.0)
	var roots: Array = p.crops.root_cells(id)
	var maxd: int = 0
	for rc: Vector2i in roots:
		maxd = maxi(maxd, maxi(absi(rc.x - 30), absi(rc.y - 24)))
	t.ck("kudzu_roots_max_24", roots.size() == 24, "n=%d" % roots.size())
	t.ck("kudzu_roots_within_chebyshev_4", maxd <= 4, "maxd=%d" % maxd)
	var uniq_roots: Dictionary = {}
	for rc2: Vector2i in roots:
		uniq_roots[rc2] = true
	t.ck("kudzu_roots_unique_and_free", uniq_roots.size() == roots.size() and not roots.has(Vector2i(30, 24)))
	t.ck("kudzu_max_production", t.near(cond(p, id), 1.0 + 0.15 * 24.0, 0.001) and rate(p, id) <= 4.6 + 0.001, "rate=%s" % str(rate(p, id)))
	# 根は現存数に数えない(価格)
	var fam: int = p.crops.family_count("kudzu")
	t.ck("kudzu_roots_not_counted_in_family", fam == 1, "fam=%d" % fam)
	# 根は生産しない(株だけ): 生産イベントは株ID
	var pe: Array = t.of_type(t.sim(p, 5.0, 1.0), "seeds")
	t.ck("kudzu_only_stock_produces", pe.all(func(x: Dictionary) -> bool: return x.e.kind != "kudzu" or int(x.e.crop_id) == id))
	# 根の撤去: 1マス返還0
	var rr: Dictionary = p.crops.remove_root(roots[0], "manual")
	t.ck("kudzu_remove_single_root_refund0", bool(rr.ok) and int(rr.refund) == 0 and p.crops.root_cells(id).size() == 23)
	# 無効マス(水・建物・荒地)には伸びない: 荒地内のクズ
	var w: RefCounted = t.mk(3)
	var wid: int = t.crop(w, "kudzu", 47, 27, true)   # 荒地の中: 通常の栽培条件(緑化)を満たさない
	t.sim(w, 200.0, 1.0)
	t.ck("kudzu_roots_only_on_valid_cells", w.crops.root_cells(wid).is_empty(), "roots=%d" % w.crops.root_cells(wid).size())
	var wb: RefCounted = t.mk(3)
	var wbid: int = t.crop(wb, "kudzu", 27, 16)   # 建物(28..35,14..19)の隣
	t.sim(wb, 15.0 * 40.0, 1.0)
	var bad: bool = false
	for rc: Vector2i in wb.crops.root_cells(wbid):
		if wb.host.is_building(rc) or wb.host.is_water(rc) or not wb.host.is_green(rc):
			bad = true
	t.ck("kudzu_roots_avoid_building_and_water", not bad and wb.crops.root_cells(wbid).size() > 0)
	# 株を撤去すると根は全消滅(返還0の根) / 敵に倒されても全消滅
	var s1: RefCounted = t.mk(3)
	var s1id: int = t.crop(s1, "kudzu", 30, 24)
	t.sim(s1, 61.0, 1.0)
	var nroots: int = s1.crops.root_cells(s1id).size()
	var rm: Dictionary = s1.crops.remove_crop(s1id, "manual")
	var rem_ev: Array = t.evs(rm.events, "kudzu_root_removed")
	t.ck("kudzu_stock_removed_all_roots_gone", nroots >= 3 and s1.crops.root_cells().is_empty() and rem_ev.size() == nroots and rem_ev.all(func(e: Dictionary) -> bool: return e.reason == "stock_lost"), "roots=%d ev=%d" % [nroots, rem_ev.size()])
	t.ck("kudzu_root_cells_free_after_loss", s1.crops.check_placement("clover", Vector2i(30, 25)).ok if true else false)
	var s2: RefCounted = t.mk(3)
	var s2id: int = t.crop(s2, "kudzu", 30, 24)
	t.sim(s2, 46.0, 1.0)
	var dmg: Array = s2.crops.damage_crop(s2id, 9999.0, {"cause": "attack", "enemy_id": 1})
	t.ck("kudzu_destroyed_by_enemy_removes_roots", s2.crops.root_cells().is_empty() and t.evs(dmg, "kudzu_root_removed").size() >= 1)
	# 未成熟のクズは根を伸ばさない
	var im: RefCounted = t.mk(3)
	var imid: int = t.crop(im, "kudzu", 30, 24, false)
	t.sim(im, 25.0, 1.0)
	t.ck("kudzu_immature_no_roots", im.crops.root_cells(imid).is_empty())

# ---------------------------------------------------------------- ヘチマ
func loofah() -> void:
	var p: RefCounted = t.mk()
	var lid: int = t.crop(p, "loofah", 30, 24, true, false)
	var a: int = t.crop(p, "clover", 32, 24, true, false)
	var b: int = t.crop(p, "clover", 33, 26, true, false)
	var far: int = t.crop(p, "clover", 36, 24, true, false)   # 距離5(矩形距離)=範囲外
	t.ck("loofah_starts_empty", p.crops.loofah_water(lid) == 0)
	var tl0: Array = t.sim(p, 25.0, 1.0)
	t.ck("loofah_empty_waters_nothing", t.of_type(tl0, "water_crop").is_empty())
	p.crops.set_watered(lid, true)
	t.ck("loofah_filled_to_10_when_watered", p.crops.loofah_water(lid) == 10)
	var tl: Array = t.sim(p, 10.2, 1.0)
	var wc: Array = t.of_type(tl, "water_crop")
	t.ck("loofah_waters_one_per_10s", wc.size() == 1 and int(wc[0].e.crop_id) == a and p.crops.loofah_water(lid) == 9, "n=%d" % wc.size())
	t.ck("loofah_target_becomes_watered", bool(p.crops.get_crop(a).watered))
	var tl2: Array = t.sim(p, 10.2, 1.0)
	var wc2: Array = t.of_type(tl2, "water_crop")
	t.ck("loofah_next_target_nearest_unwatered", wc2.size() == 1 and int(wc2[0].e.crop_id) == b)
	var tl3: Array = t.sim(p, 40.0, 1.0)
	t.ck("loofah_never_waters_out_of_range_or_self", t.of_type(tl3, "water_crop").is_empty() and not bool(p.crops.get_crop(far).watered))
	# 栽培植物がなければ未給水で成長中の草を給水
	var g: RefCounted = t.mk()
	var gid: int = t.crop(g, "loofah", 30, 24, true, false)
	g.crops.set_watered(gid, true)
	g.host.set_stage(Vector2i(32, 24), "seed")
	g.host.set_stage(Vector2i(33, 24), "sprout")
	g.host.set_stage(Vector2i(31, 22), "grass")
	var tlg: Array = t.sim(g, 10.2, 1.0)
	var wcell: Array = t.of_type(tlg, "water_cell")
	t.ck("loofah_waters_growing_grass_when_no_crops", wcell.size() == 1 and (Vector2i(wcell[0].e.cell) in [Vector2i(32, 24), Vector2i(34, 24)]), str(wcell.map(func(x: Dictionary) -> Vector2i: return x.e.cell)))
	g.host.watered_cells[Vector2i(wcell[0].e.cell)] = true
	var tlg2: Array = t.sim(g, 10.2, 1.0)
	var wcell2: Array = t.of_type(tlg2, "water_cell")
	t.ck("loofah_grass_other_cell_next", wcell2.size() == 1 and wcell2[0].e.cell != wcell[0].e.cell)
	# 補充: 水が当たれば10に戻る(10未満のとき)
	var f: RefCounted = t.mk()
	var fid: int = t.crop(f, "loofah", 30, 24, true, false)
	t.ck("loofah_needs_water_when_empty_for_sprinkler", f.crops.sprinkler_targets().has(fid))
	var rev: Array = f.water_landed([Vector2i(30, 24)])
	t.ck("loofah_refilled_by_water", f.crops.loofah_water(fid) == 10 and t.evs(rev, "loofah_refill").size() == 1)
	var rev2: Array = f.water_landed([Vector2i(30, 24)])
	t.ck("loofah_no_refill_event_when_full", t.evs(rev2, "loofah_refill").is_empty())
	# 水が隣のマスにしか当たらなければ補充しない
	var f2: RefCounted = t.mk()
	var f2id: int = t.crop(f2, "loofah", 30, 24, true, false)
	f2.water_landed([Vector2i(29, 24), Vector2i(31, 24)])
	t.ck("loofah_not_refilled_by_adjacent_water", f2.crops.loofah_water(f2id) == 0)
	# 貯水0のヘチマはスプリンクラーの優先対象、満タン(給水済み)は対象外
	var f3: RefCounted = t.mk()
	var f3id: int = t.crop(f3, "loofah", 30, 24, true, true)
	t.ck("loofah_empty_but_watered_still_priority", f3.crops.needs_water(f3id))
	f3.crops.set_watered(f3id, false)
	f3.crops.set_watered(f3id, true)
	t.ck("loofah_full_watered_not_priority", not f3.crops.needs_water(f3id))

# ---------------------------------------------------------------- ヒノキ
func hinoki() -> void:
	var p: RefCounted = t.mk()
	# 3x3 を (30,24)-(32,26)。北側2マス x 幅3 = (30..32, 22..23)
	var hid: int = t.crop(p, "hinoki", 30, 24, false)
	t.ck("hinoki_immature_no_shade", not p.crops.is_shaded(Vector2i(31, 23)) and p.crops.dynamic_shade_cells().is_empty())
	var dk: int = t.crop(p, "dokudami", 31, 22, true)
	var base: float = cond(p, dk)
	t.ck("dokudami_not_shaded_before_hinoki_matures", t.near(base, 1.0))
	p.crops.debug_force_mature(hid, false)
	var cells: Array = p.crops.dynamic_shade_cells()
	var want: Array = []
	for y: int in [22, 23]:
		for x: int in [30, 31, 32]:
			want.append(Vector2i(x, y))
	var okc: bool = cells.size() == 6 and want.all(func(c: Vector2i) -> bool: return cells.has(c))
	t.ck("hinoki_shade_2x3_north", okc, str(cells))
	t.ck("hinoki_shade_not_south_or_sides", not p.crops.is_shaded(Vector2i(31, 27)) and not p.crops.is_shaded(Vector2i(29, 23)) and not p.crops.is_shaded(Vector2i(33, 23)) and not p.crops.is_shaded(Vector2i(31, 21)))
	t.ck("dokudami_gets_shade_multiplier_dynamically", t.near(cond(p, dk), 2.0), "cond=%s" % str(cond(p, dk)))
	var dk_out: int = t.crop(p, "dokudami", 40, 22, true)
	t.ck("dokudami_outside_shade_normal", t.near(cond(p, dk_out), 1.0))
	# 成長速度 x1.5 (未成熟のドクダミ)
	# ヒノキを失うと日陰が消え、ドクダミの倍率も消える(常時判定)
	p.crops.remove_crop(hid, "manual")
	t.ck("hinoki_removed_shade_gone", p.crops.dynamic_shade_cells().is_empty() and not p.crops.is_shaded(Vector2i(31, 23)))
	t.ck("dokudami_multiplier_gone_with_hinoki", t.near(cond(p, dk), 1.0), "cond=%s" % str(cond(p, dk)))
	# ホスト静的日陰との論理和
	t.ck("static_shade_still_works", p.crops.is_shaded(Vector2i(30, 12)) == p.host.is_shade(Vector2i(30, 12)))
	# 未成熟ドクダミの成長速度が日陰で x1.5
	var q: RefCounted = t.mk()
	var qh: int = t.crop(q, "hinoki", 30, 24, true)
	var qd: int = t.crop(q, "dokudami", 31, 22, false)
	var qd2: int = t.crop(q, "dokudami", 40, 22, false)
	t.ck("dokudami_growth_x1_5_in_hinoki_shade", t.near(q.crops.growth_rate(qd) / q.crops.growth_rate(qd2), 1.5, 0.001), "%s / %s" % [str(q.crops.growth_rate(qd)), str(q.crops.growth_rate(qd2))])
	# 通常設置で日陰に植えられる/占有
	var occ: Dictionary = q.crops.check_placement("clover", Vector2i(31, 25))
	t.ck("hinoki_occupies_3x3", not bool(occ.ok) and occ.reason == "occupied")
	var qh_def: Dictionary = q.crops.def_of("hinoki")
	t.ck("hinoki_def_size_hp_cost", q.crops.size_of("hinoki") == Vector2i(3, 3) and int(qh_def.hp) == 150 and int(qh_def.cost) == 120 and int(qh_def.maturity) == 150)

# ---------------------------------------------------------------- リンゴ
func apple() -> void:
	var p: RefCounted = t.mk(2)
	t.hero(p, 240, 130)
	var aid: int = t.crop(p, "apple", 20, 20)
	var tl: Array = t.sim(p, 29.0, 1.0)
	t.ck("apple_no_drop_before_30s", t.of_type(tl, "fruit_dropped").is_empty())
	tl.append_array(t.sim(p, 2.0, 1.0))
	var fd: Array = t.of_type(tl, "fruit_dropped")
	t.ck("apple_drops_at_30s", fd.size() == 1 and t.near(float(fd[0].t), 30.0, 1.1))
	var fc: Vector2i = fd[0].e.cell if fd.size() > 0 else Vector2i(-9, -9)
	var rect: Rect2i = Rect2i(20, 20, 2, 2)
	var adjacent: bool = not rect.has_point(fc) and Rect2i(19, 19, 4, 4).has_point(fc) and (fc.x >= 20 and fc.x <= 21 or fc.y >= 20 and fc.y <= 21)
	t.ck("apple_fruit_on_adjacent_cell", adjacent, str(fc))
	t.sim(p, 200.0, 1.0)
	t.ck("apple_max_3_fruits", p.crops.fruits.size() == 3, "n=%d" % p.crops.fruits.size())
	# 拾い物ではない: pickups に増えない
	t.ck("apple_fruit_not_a_pickup", p.crops.pickups.is_empty())
	# 落果が歩けない/占有マスには落ちない
	var o: RefCounted = t.mk(2)
	t.crop(o, "apple", 20, 20)
	for c: Vector2i in [Vector2i(19, 20), Vector2i(19, 21), Vector2i(22, 20), Vector2i(22, 21), Vector2i(20, 19), Vector2i(21, 19), Vector2i(20, 22)]:
		o.host.blocked_cells[c] = true
	t.sim(o, 400.0, 1.0)
	var only: bool = o.crops.fruits.size() == 1 and Vector2i(o.crops.fruits[0].cell) == Vector2i(21, 22)
	t.ck("apple_fruit_only_on_open_adjacent_cell", only, str(o.crops.fruits))
	# 草食の敵が引き寄せられる(各種)
	var herb: Array = ["deer", "pouch_rabbit", "moss_turtle", "slime_slug", "leafcutter_ant", "mimic_cabbage", "iron_rhino", "hippo", "honey_bear"]
	var carn: Array = ["skunk", "root_mole", "stray_wolf", "mirror_lizard", "pistol_shrimp", "decoy_newt", "sewer_rat", "bat_flock", "thunder_eel", "balloon_frog", "shadow_brian", "black_kite"]
	var q0: RefCounted = t.mk()
	var herb_bad: Array = []
	for k: String in herb:
		var i: int = t.sp(q0, k, 100, 100)
		if not q0.enemies.tags_of(t.R(q0, i)).has("herbivore"):
			herb_bad.append(k)
	t.ck("herbivore_tag_catalog_set", herb_bad.is_empty(), str(herb_bad))
	var carn_bad: Array = []
	for k: String in carn:
		var i2: int = t.sp(q0, k, 100, 100)
		if i2 >= 0 and q0.enemies.tags_of(t.R(q0, i2)).has("herbivore"):
			carn_bad.append(k)
	t.ck("non_herbivores_not_tagged", carn_bad.is_empty(), str(carn_bad))
	# 鹿: 落果を食べに行って食べる(3秒)
	var d: RefCounted = t.mk()
	t.hero(d, 240, 130)
	d.crops.fruits.append({"id": 1, "cell": Vector2i(30, 25), "source_id": 0})
	d.crops.next_fruit_id = 2
	var did: int = t.sp(d, "deer", 160, 100)
	var tld: Array = t.sim(d, 40.0, 0.1)
	var fe: Array = t.of_type(tld, "fruit_eaten")
	t.ck("herbivore_deer_eats_fruit", fe.size() == 1 and d.crops.fruits.is_empty(), "n=%d" % fe.size())
	var seek: Array = t.of_type(tld, "fx").filter(func(x: Dictionary) -> bool: return x.e.kind == "fruit_seek")
	t.ck("herbivore_fruit_seek_fx", seek.size() >= 1)
	# 非草食(オオカミ)は無視
	var w: RefCounted = t.mk()
	t.hero(w, 240, 130)
	w.crops.fruits.append({"id": 1, "cell": Vector2i(30, 25), "source_id": 0})
	w.crops.next_fruit_id = 2
	t.sp(w, "stray_wolf", 124, 100)
	t.sim(w, 30.0, 0.1)
	t.ck("wolf_ignores_fruit", w.crops.fruits.size() == 1)
	# 安定した地域の落果は除外
	var s: RefCounted = t.mk()
	t.hero(s, 240, 130)
	s.crops.fruits.append({"id": 1, "cell": Vector2i(30, 25), "source_id": 0})
	s.crops.next_fruit_id = 2
	s.host.set_stable_rect(Rect2i(28, 23, 6, 6))
	var sid: int = t.sp(s, "deer", 100, 100)
	t.sim(s, 40.0, 0.1)
	t.ck("stable_region_fruit_not_attractive", s.crops.fruits.size() == 1 and s.enemies.fruit_for(t.R(s, sid)).is_empty())
	# 範囲外(縄張り+10m / きっかけ範囲外)は引き寄せない
	var far: RefCounted = t.mk()
	far.crops.fruits.append({"id": 1, "cell": Vector2i(63, 1), "source_id": 0})
	far.crops.next_fruit_id = 2
	var fid2: int = t.sp(far, "deer", 4, 140)
	t.ck("fruit_out_of_range_not_attractive", far.enemies.fruit_for(t.R(far, fid2)).is_empty())
	# 植えると落果は消える
	var pl: RefCounted = t.mk()
	pl.crops.fruits.append({"id": 1, "cell": Vector2i(30, 25), "source_id": 0})
	var r: Dictionary = pl.crops.spawn_crop("clover", Vector2i(30, 25), 0, {"mature": true})
	t.ck("planting_on_fruit_removes_fruit", pl.crops.fruits.is_empty() and t.evs(r.events, "fruit_removed").size() == 1)

# ---------------------------------------------------------------- ホウセンカ
func balsam() -> void:
	var p: RefCounted = t.mk(4)
	t.hero(p, 240, 130)
	var bid: int = t.crop(p, "balsam", 49, 27)
	var tl: Array = t.sim(p, 19.0, 0.5)
	t.ck("balsam_no_burst_before_20s", t.of_type(tl, "balsam_burst").is_empty())
	tl.append_array(t.sim(p, 2.0, 0.5))
	var bu: Array = t.of_type(tl, "balsam_burst")
	t.ck("balsam_bursts_at_20s_periodic", bu.size() == 1 and bu[0].e.cause == "periodic" and t.near(float(bu[0].t), 20.0, 0.6))
	var sows: Array = t.of_type(tl, "seed_sow")
	t.ck("balsam_sows_max_3", sows.size() == 3, "n=%d" % sows.size())
	var okc: bool = true
	for s: Dictionary in sows:
		var c: Vector2i = s.e.cell
		if maxi(absi(c.x - 49), absi(c.y - 27)) > 3 or maxi(absi(c.x - 49), absi(c.y - 27)) < 1 or s.e.consume_stock != false or s.e.source != "balsam":
			okc = false
	var uniq: Dictionary = {}
	for s: Dictionary in sows:
		uniq[Vector2i(s.e.cell)] = true
	t.ck("balsam_sow_cells_within_2_tiles_no_stock", okc and uniq.size() == sows.size())
	t.ck("balsam_does_not_multiply", p.crops.crops.size() == 1)
	# 敵が1.5m以内に来たらはじける(間隔8秒)。中立は除く。ダメージ4を半径2mの敵に
	var q: RefCounted = t.mk(4)
	t.hero(q, 240, 130)
	var qid: int = t.crop(q, "balsam", 20, 20)
	var e1: int = t.sp(q, "skunk", 84 + 10, 82, "initial")
	var e_far: int = t.sp(q, "skunk", 84 + 40, 82, "initial")   # 半径2m(20px)の外
	var glass: int = t.sp(q, "glass_deer", 84 + 12, 90, "initial")
	for k: String in ["skunk", "glass_deer"]:
		q.enemies.defs[k].speed_mps = 0.0
	var h1: float = float(t.R(q, e1).hp)
	var hf: float = float(t.R(q, e_far).hp)
	var tq: Array = t.sim(q, 2.0, 0.5)
	var qb: Array = t.of_type(tq, "balsam_burst")
	t.ck("balsam_enemy_trigger_burst", qb.size() == 1 and qb[0].e.cause == "enemy", "n=%d" % qb.size())
	t.ck("balsam_damage_4_to_hostile_in_2m", t.near(h1 - float(t.R(q, e1).hp), 4.0) and t.near(hf - float(t.R(q, e_far).hp), 0.0), "e1=%s far=%s" % [str(h1 - float(t.R(q, e1).hp)), str(hf - float(t.R(q, e_far).hp))])
	t.ck("balsam_neutral_unharmed", t.near(float(t.R(q, glass).hp), 1.0) and q.enemies.is_alive(glass))
	# 8秒クールダウン
	var tq2: Array = t.sim(q, 6.0, 0.5)
	t.ck("balsam_enemy_trigger_cooldown_8s", t.of_type(tq2, "balsam_burst").is_empty())
	var tq3: Array = t.sim(q, 2.5, 0.5)
	var qb3: Array = t.of_type(tq3, "balsam_burst")
	t.ck("balsam_enemy_trigger_again_after_8s", qb3.size() >= 1, "n=%d" % qb3.size())
	# 中立だけが近い場合ははじけない
	var n: RefCounted = t.mk(4)
	t.hero(n, 240, 130)
	t.crop(n, "balsam", 20, 20)
	var gn: int = t.sp(n, "glass_deer", 84 + 6, 82)
	n.enemies.defs["glass_deer"].speed_mps = 0.0
	var tn: Array = t.sim(n, 10.0, 0.5)
	t.ck("balsam_neutral_does_not_trigger", t.of_type(tn, "balsam_burst").is_empty())
	# 有効マスがなければ種はまかないが、ダメージははじける
	var z: RefCounted = t.mk(4)
	t.hero(z, 240, 130)
	t.crop(z, "balsam", 49, 27)
	for y: int in range(23, 32):
		for x: int in range(45, 54):
			if not Rect2i(49, 27, 1, 1).has_point(Vector2i(x, y)):
				z.host.blocked_cells[Vector2i(x, y)] = true
	var zt: Array = t.sim(z, 21.0, 0.5)
	t.ck("balsam_no_valid_cells_no_sow_but_burst", t.of_type(zt, "seed_sow").is_empty() and t.of_type(zt, "balsam_burst").size() == 1)
	# 撃破は報酬を出す(窓口経由で敵に倍率なしの4ダメージ)
	var k: RefCounted = t.mk(4)
	t.hero(k, 240, 130)
	t.crop(k, "balsam", 20, 20)
	var kid: int = t.sp(k, "bat_flock", 90, 82, "initial")
	k.enemies.defs["bat_flock"].speed_mps = 0.0
	var tk: Array = t.sim(k, 2.0, 0.5)
	t.ck("balsam_kills_hp4_enemy_with_reward", t.evs(t.E(tk), "enemy_defeated").size() == 1 and t.evs(t.E(tk), "reward").size() == 1, "ev=%d" % tk.size())

func q0size(p: RefCounted, k: String) -> Vector2i:
	return p.crops.size_of(k)

func catalog_numbers() -> void:
	var p: RefCounted = t.mk()
	var want: Dictionary = {
		"evening_primrose": [25, 3.0, 30, 30, [1, 1]], "dandelion": [20, 1.0, 25, 20, [1, 1]], "mimosa": [25, 3.0, 30, 40, [1, 1]],
		"kudzu": [20, 1.0, 30, 40, [1, 1]], "loofah": [25, 1.5, 35, 30, [1, 1]], "hinoki": [120, 4.0, 150, 150, [3, 3]],
		"apple": [60, 2.0, 90, 80, [2, 2]], "balsam": [20, 1.5, 25, 25, [1, 1]]}
	var bad: Array = []
	for k: String in want.keys():
		var d: Dictionary = p.crops.def_of(k)
		var w: Array = want[k]
		if int(d.cost) != int(w[0]) or not t.near(float(d.rate_per_min), float(w[1])) or int(d.maturity) != int(w[2]) or int(d.hp) != int(w[3]) or q0size(p, k) != Vector2i(int(w[4][0]), int(w[4][1])) or not bool(d.placeable):
			bad.append(k)
	t.ck("crop_defs_match_catalog_table", bad.is_empty(), str(bad))
	# 価格系統: 設置するたびに価格が上がるのは同種のみ。クズの根は数えない
	var q: RefCounted = t.mk()
	var before: int = q.crops.quote("kudzu")
	var kid: int = t.crop(q, "kudzu", 30, 24)
	var after1: int = q.crops.quote("kudzu")
	t.sim(q, 61.0, 1.0)
	var after2: int = q.crops.quote("kudzu")
	t.ck("kudzu_price_rises_per_stock_not_per_root", after1 > before and after2 == after1 and q.crops.root_cells(kid).size() >= 3, "%d %d %d" % [before, after1, after2])
