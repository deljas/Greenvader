extends SceneTree
## 第2弾の新しい状態(植物8種の種類固有の状態・落果・濡れ・気絶/停止)の保存復元と、不正データの拒否の自己検証(入口スクリプト)。
## 実行(隔離プロジェクトのみ): Godot --headless --path C:/godot/greenvader_content_sandbox --script res://tests/content_pack/self2/save2_logic.gd
const Lab: GDScript = preload("res://scripts/content_pack/lab/lab_host.gd")
const Pack: GDScript = preload("res://scripts/content_pack/content_pack.gd")
const Common2: GDScript = preload("res://scripts/content_pack/common2.gd")
const OUT_DIR: String = "res://evidence/content_pack/self2"
const NEW_KINDS: Array = ["evening_primrose", "dandelion", "mimosa", "kudzu", "loofah", "hinoki", "apple", "balsam"]

var checks: Array = []

func ck(name: String, ok: bool, detail: String = "") -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})

func mk(seed: int = 1) -> RefCounted:
	return Pack.new(Lab.new(), seed)

func sp(p: RefCounted, kind: String, x: int, y: int) -> int:
	var r: Dictionary = p.crops.spawn_crop(kind, Vector2i(x, y), int(p.crops.def_of(kind).cost), {"mature": true, "watered": true})
	return int(r.id) if bool(r.ok) else -1

func adv(p: RefCounted, secs: float) -> Array:
	var all: Array = []
	var left: float = secs
	while left > 1e-9:
		var s: float = minf(left, 5.0)
		all.append_array(p.advance(s))
		left -= s
	return all

func rt(x: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(x))

func norm(p: RefCounted) -> String:
	return JSON.stringify(rt(p.to_dict()))

## 第2弾の状態をひととおり持つ途中状態
func build() -> RefCounted:
	var p: RefCounted = mk(7)
	sp(p, "kudzu", 20, 24)
	var lf: int = sp(p, "loofah", 30, 22)
	sp(p, "mimosa", 30, 26)
	sp(p, "apple", 34, 26)
	sp(p, "dandelion", 38, 22)
	sp(p, "balsam", 40, 26)
	sp(p, "evening_primrose", 38, 30)
	sp(p, "hinoki", 30, 30)
	p.host.set_stage(Vector2i(31, 24), "sprout")
	p.host.host_enemy_list = [{"id": 1, "pos": Vector2(122, 124), "neutral": false, "tags": []}]
	adv(p, 75.0)
	p.host.host_enemy_list = []
	p.crops.set_watered(lf, true)
	p.water_landed([Vector2i(5, 5), Vector2i(31, 24)])
	p.relay_events([Common2.hero_stun_event(3.0, 4), Common2.helper_stop_event(2, 3.0, "odor")])
	return p

func base_pack() -> RefCounted:
	var q: RefCounted = mk()
	sp(q, "kudzu", 20, 24)
	q.enemies.spawn("shadow_brian", Vector2(60, 60))
	adv(q, 20.0)
	return q

## 壊した保存を読ませる。戻り値 [採用されたか, 状態が変わらなかったか]
func try_load(dd: Dictionary) -> Array:
	var q: RefCounted = base_pack()
	var before: String = JSON.stringify(q.to_dict())
	var ok: bool = q.from_dict(dd)
	return [ok, JSON.stringify(q.to_dict()) == before]

func crop_index(d: Dictionary, kind: String) -> int:
	var arr: Array = d.crops.crops
	for i: int in range(arr.size()):
		if arr[i].kind == kind:
			return i
	return -1

func wrong(v: Variant) -> Variant:
	if typeof(v) == TYPE_STRING:
		return 12345
	return "bad"

func _initialize() -> void:
	t_roundtrip()
	t_reject()
	var fails: int = 0
	for c: Dictionary in checks:
		print("%s %s %s" % [c.status, c.name, c.detail])
		if c.status != "PASS":
			fails += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/save2_logic.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "save2_logic", "total": checks.size(), "failed": fails, "checks": checks}, "\t"))
	f.close()
	print("save2_logic total=%d failed=%d" % [checks.size(), fails])
	quit(1 if fails > 0 else 0)

func t_roundtrip() -> void:
	var p: RefCounted = build()
	var d: Dictionary = rt(p.to_dict())
	var kudzu_roots: int = p.crops.root_cells().size()
	var fruits: int = p.crops.fruit_list().size()
	var mim_closed: bool = false
	for c: Dictionary in p.crops.crops:
		if c.kind == "mimosa":
			mim_closed = bool(c.ext.closed)
	ck("save2_state_has_content", kudzu_roots >= 4 and fruits >= 1 and p.common.wet_cells().size() == 2 and p.common.hero_stunned(), "roots=%d fruits=%d" % [kudzu_roots, fruits])
	var q: RefCounted = mk(1)
	var ok: bool = q.from_dict(d)
	ck("save2_adopts_valid", ok, str(q.last_error))
	ck("save2_roundtrip_identical", norm(p) == norm(q), "")
	ck("save2_roots_and_occupancy_restored", q.crops.root_cells().size() == kudzu_roots and q.crops.root_owner(p.crops.root_cells()[0]) != 0 and q.crops.place_crop("bamboo", p.crops.root_cells()[0]).reason == "occupied", "")
	ck("save2_fruits_restored", q.crops.fruit_list().size() == fruits, "")
	ck("save2_wet_and_stun_restored", q.common.is_wet(Vector2i(5, 5)) and q.common.hero_stunned() and q.common.helper_stopped(2), "")
	ck("save2_loofah_water_restored", q.crops.loofah_water(q.crops.crop_id_at(Vector2i(30, 22))) == p.crops.loofah_water(p.crops.crop_id_at(Vector2i(30, 22))), "")
	ck("save2_mimosa_state_restored", mim_closed == bool(q.crops.get_crop(q.crops.crop_id_at(Vector2i(30, 26))).ext.closed), "closed=%s" % str(mim_closed))
	# 復元後も同じように進む(乱数の状態も含めて)
	q.host.set_stage(Vector2i(31, 24), "sprout")   # ホスト側の地形状態は保存の対象外なので同じにそろえる
	var e1: Array = adv(p, 90.0)
	var e2: Array = adv(q, 90.0)
	var t1: Dictionary = {}
	var t2: Dictionary = {}
	for e: Dictionary in e1:
		t1[e.type] = int(t1.get(e.type, 0)) + 1
	for e: Dictionary in e2:
		t2[e.type] = int(t2.get(e.type, 0)) + 1
	var da: Dictionary = rt(p.to_dict())
	var db: Dictionary = rt(q.to_dict())
	var prod_ok: bool = true
	for k: Variant in da.crops.produced:
		if not db.crops.produced.has(k) or absf(float(da.crops.produced[k]) - float(db.crops.produced[k])) > 1e-6:
			prod_ok = false
	# 生産量の累計は小数の丸めだけが違いうるため許容誤差で比べ、それ以外は完全一致を求める
	da.crops.erase("produced")
	db.crops.erase("produced")
	ck("save2_continues_identically_90s", prod_ok and JSON.stringify(da) == JSON.stringify(db) and JSON.stringify(t1) == JSON.stringify(t2), "events=%s" % JSON.stringify(t1))
	# 時間を進めない(ポーズ)間は保存内容が変わらない
	var before: String = norm(q)
	q.advance(0.0)
	ck("save2_pause_unchanged", norm(q) == before, "")

func t_reject() -> void:
	var p: RefCounted = build()
	var good: Dictionary = rt(p.to_dict())
	var ok_base: Array = try_load(rt(good))
	ck("reject_baseline_valid_adopted", ok_base[0], "")
	# 種類ごとの ext: 各キーの欠落と型違い
	var missing_adopted: Array = []
	var wrong_adopted: Array = []
	var changed: Array = []
	var n_keys: int = 0
	for kind: String in NEW_KINDS:
		var i: int = crop_index(good, kind)
		if i < 0:
			missing_adopted.append("no " + kind)
			continue
		var ext: Dictionary = good.crops.crops[i].ext
		for k: String in ext.keys():
			n_keys += 1
			var d1: Dictionary = rt(good)
			(d1.crops.crops[i].ext as Dictionary).erase(k)
			var r1: Array = try_load(d1)
			if r1[0]:
				missing_adopted.append(kind + "." + k)
			if not r1[1]:
				changed.append(kind + "-" + k)
			var d2: Dictionary = rt(good)
			d2.crops.crops[i].ext[k] = wrong(ext[k])
			var r2: Array = try_load(d2)
			if r2[0]:
				wrong_adopted.append(kind + "." + k)
			if not r2[1]:
				changed.append(kind + "~" + k)
	ck("reject_ext_key_missing", missing_adopted.is_empty(), "keys=%d adopted=%s" % [n_keys, str(missing_adopted)])
	ck("reject_ext_key_wrong_type", wrong_adopted.is_empty(), str(wrong_adopted))
	ck("reject_ext_state_unchanged", changed.is_empty(), str(changed))
	# ext そのものの欠落・型違い(旧形式の保存)
	var d3: Dictionary = rt(good)
	(d3.crops.crops[0] as Dictionary).erase("ext")
	var r3: Array = try_load(d3)
	var d4: Dictionary = rt(good)
	d4.crops.crops[0].ext = "bad"
	var r4: Array = try_load(d4)
	ck("reject_ext_absent_or_not_dict", not r3[0] and r3[1] and not r4[0] and r4[1], "")
	# クズの根の不正
	var ki: int = crop_index(good, "kudzu")
	var roots: Array = good.crops.crops[ki].ext.roots
	var cases: Dictionary = {}
	var d5: Dictionary = rt(good)
	var many: Array = []
	for i2: int in range(25):
		many.append([14 + i2 % 5, 22 + i2 / 5])
	d5.crops.crops[ki].ext.roots = many
	cases["roots_over_24"] = d5
	var d6: Dictionary = rt(good)
	d6.crops.crops[ki].ext.roots = [roots[0], roots[0]]
	cases["roots_duplicate"] = d6
	var d7: Dictionary = rt(good)
	d7.crops.crops[ki].ext.roots = [[20, 24]]
	cases["root_on_stock"] = d7
	var d8: Dictionary = rt(good)
	d8.crops.crops[ki].ext.roots = [[20, 30]]
	cases["root_beyond_reach_4"] = d8
	var d9: Dictionary = rt(good)
	d9.crops.crops[ki].ext.roots = [[21, "x"]]
	cases["root_bad_cell"] = d9
	var d10: Dictionary = rt(good)
	d10.crops.crops[ki].ext.roots = [[30, 22]]   # 別の株(ヘチマ)の上
	cases["root_overlaps_other_crop"] = d10
	var d10b: Dictionary = rt(good)
	d10b.crops.crops[ki].ext.roots = "bad"
	cases["roots_not_array"] = d10b
	var bad_roots: Array = []
	for name: String in cases:
		var r: Array = try_load(cases[name])
		if r[0] or not r[1]:
			bad_roots.append(name)
	ck("reject_kudzu_roots_invalid", bad_roots.is_empty(), str(bad_roots))
	# ヘチマの貯水の範囲
	var li: int = crop_index(good, "loofah")
	var lw: Array = []
	for v: Variant in [11, -1]:
		var d11: Dictionary = rt(good)
		d11.crops.crops[li].ext.water = v
		var r11: Array = try_load(d11)
		if r11[0] or not r11[1]:
			lw.append(v)
	ck("reject_loofah_water_out_of_range", lw.is_empty(), str(lw))
	# 落果
	var fcases: Dictionary = {}
	var f1: Dictionary = rt(good)
	f1.erase("fruits")
	f1.crops.erase("fruits")
	fcases["fruits_missing"] = f1
	var f2: Dictionary = rt(good)
	f2.crops.fruits = [{"id": 1, "cell": "x", "source_id": 1}]
	fcases["fruit_bad_cell"] = f2
	var f3: Dictionary = rt(good)
	f3.crops.fruits = [{"id": 1, "cell": [1, 1], "source_id": 1}, {"id": 1, "cell": [2, 1], "source_id": 1}]
	fcases["fruit_duplicate_id"] = f3
	var f4: Dictionary = rt(good)
	f4.crops.erase("next_fruit_id")
	fcases["next_fruit_id_missing"] = f4
	var f5: Dictionary = rt(good)
	f5.crops.fruits = [5]
	fcases["fruit_not_dict"] = f5
	var bad_fruit: Array = []
	for name2: String in fcases:
		var r5: Array = try_load(fcases[name2])
		if r5[0] or not r5[1]:
			bad_fruit.append(name2)
	ck("reject_fruits_invalid", bad_fruit.is_empty(), str(bad_fruit))
	# 濡れ・気絶(共通状態)
	var ccases: Dictionary = {}
	var c1: Dictionary = rt(good)
	c1.common.wet = [[1, 2]]
	ccases["wet_short"] = c1
	var c2: Dictionary = rt(good)
	c2.common.erase("hero_stun_until")
	ccases["stun_missing"] = c2
	var c3: Dictionary = rt(good)
	c3.common = "bad"
	ccases["common_not_dict"] = c3
	var c4: Dictionary = rt(good)
	c4.common.helper_stop = [["a", 1]]
	ccases["helper_stop_bad"] = c4
	var bad_common: Array = []
	for name3: String in ccases:
		var r6: Array = try_load(ccases[name3])
		if r6[0] or not r6[1]:
			bad_common.append(name3)
	ck("reject_common_invalid", bad_common.is_empty(), str(bad_common))
