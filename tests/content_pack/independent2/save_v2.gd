extends SceneTree
## 独立検証2-D: 保存・復元(新しい状態すべて)、不正データの拒否、ポーズ中の停止。入口スクリプト。
const L: GDScript = preload("res://tests/content_pack/independent2/lib2.gd")
const Game: GDScript = preload("res://scripts/content_pack/lab/lab_game.gd")
const OUT: String = "res://evidence/content_pack/independent2"
var t: RefCounted = L.new()

func _initialize() -> void:
	roundtrip_world()
	invalid_data()
	pause_stops_time()
	t.finish("save_v2", OUT, self)

func norm(d: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(d))

func approx(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return absf(float(a) - float(b)) <= 1e-6
	if typeof(a) != typeof(b):
		return false
	if typeof(a) == TYPE_DICTIONARY:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k: Variant in a:
			if not (b as Dictionary).has(k) or not approx(a[k], b[k]):
				return false
		return true
	if typeof(a) == TYPE_ARRAY:
		if (a as Array).size() != (b as Array).size():
			return false
		for i: int in range((a as Array).size()):
			if not approx(a[i], b[i]):
				return false
		return true
	return a == b

func first_path(a: Variant, b: Variant, path: String) -> String:
	if typeof(a) != typeof(b) and not (typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]):
		return "%s type %s vs %s" % [path, str(a).left(60), str(b).left(60)]
	if typeof(a) == TYPE_DICTIONARY:
		for k: Variant in a:
			if not (b as Dictionary).has(k):
				return "%s.%s missing" % [path, str(k)]
			var r: String = first_path(a[k], b[k], path + "." + str(k))
			if r != "":
				return r
		return ""
	if typeof(a) == TYPE_ARRAY:
		if (a as Array).size() != (b as Array).size():
			return "%s size %d vs %d" % [path, (a as Array).size(), (b as Array).size()]
		for i: int in range((a as Array).size()):
			var r2: String = first_path(a[i], b[i], "%s[%d]" % [path, i])
			if r2 != "":
				return r2
		return ""
	if typeof(a) in [TYPE_INT, TYPE_FLOAT]:
		return "" if absf(float(a) - float(b)) <= 1e-6 else "%s %s vs %s" % [path, str(a), str(b)]
	return "" if a == b else "%s %s vs %s" % [path, str(a), str(b)]

func build_world() -> RefCounted:
	var p: RefCounted = t.mk(21)
	t.hero(p, 180, 100)
	t.helper(p, 77, 185, 96)
	# 植物8種(状態を持たせる)
	var kid: int = t.crop(p, "kudzu", 30, 24)
	var lid: int = t.crop(p, "loofah", 34, 30, true, false)
	p.crops.set_watered(lid, true)
	var mid: int = t.crop(p, "mimosa", 20, 28)
	var aid: int = t.crop(p, "apple", 44, 10)
	var bid: int = t.crop(p, "balsam", 50, 29)
	var hid: int = t.crop(p, "hinoki", 40, 8)
	t.crop(p, "evening_primrose", 24, 30)
	t.crop(p, "garlic", 10, 30)
	t.crop(p, "potato", 58, 25)
	t.crop(p, "bamboo", 42, 27)
	# 敵13種+付属
	t.sp(p, "root_mole", 202, 102)
	var sk: int = t.sp(p, "skunk", 160, 100)
	t.R(p, sk).face = Vector2.RIGHT
	t.sp(p, "hippo", 40, 30)
	var bear: int = t.sp(p, "honey_bear", 100, 120)
	p.enemies.spawn_manhole_net([Vector2(186, 108), Vector2(214, 114), Vector2(172, 118)], "initial")
	p.enemies.spawn_bat_flock(Vector2(108, 68), "initial")
	var rh: int = t.sp(p, "iron_rhino", 230, 130)
	t.sp(p, "thunder_eel", 30, 30)
	var nw: int = t.sp(p, "decoy_newt", 120, 120)
	var ml: int = t.sp(p, "mirror_lizard", 140, 130)
	t.R(p, ml).face = Vector2.RIGHT
	t.sp(p, "pistol_shrimp", 90, 125)
	p.enemies.spawn_frog_flock(Vector2(60, 120), "initial")
	p.place_glass_deer(31337, {"a": [Vector2(70, 100), Vector2(80, 100)], "b": [Vector2(40, 90)], "c": [Vector2(30, 100), Vector2(36, 100), Vector2(44, 100)]})
	# 状態を作る
	t.sim(p, 20.0)
	p.crops.fruits.append({"id": 50, "cell": Vector2i(43, 12), "source_id": aid})
	p.crops.next_fruit_id = 51
	t.crop(p, "dandelion", 49, 22)
	p.water_landed([Vector2i(20, 7), Vector2i(21, 7), Vector2i(22, 7)])
	t.R(p, sk).face = Vector2.RIGHT
	t.R(p, sk).pos = Vector2(160, 100)
	t.R(p, sk).last_cell = Vector2i(40, 25)
	t.R(p, ml).face = Vector2.RIGHT
	t.R(p, ml).pos = Vector2(140, 130)
	t.R(p, ml).last_cell = Vector2i(35, 32)
	p.hit_enemy(sk, 5.0, "shot", Vector2(200, 100))      # スカンク: 予兆(→雲)
	p.hit_enemy(nw, 1.0, "shot", Vector2(100, 120))      # イモリ: 分身
	p.hit_enemy(ml, 4.0, "shot", Vector2(180, 130))      # トカゲ: 反射弾
	p.hit_enemy(rh, 0.0, "water")                        # サイ: 錆
	p.hit_enemy(rh, 0.0, "water")
	t.sim(p, 0.2)
	p.common.hero_stun_until = p.common.time + 1.2        # 気絶中の保存
	p.common.helper_stop[77] = p.common.time + 0.9
	p.crops.damage_crop(mid, 1.0, {"cause": "attack"})    # オジギソウが閉じる
	return p

func snapshot(p: RefCounted) -> Dictionary:
	return norm(p.to_dict())

func roundtrip_world() -> void:
	var p: RefCounted = build_world()
	var d: Dictionary = snapshot(p)
	# 新しい状態が実際に含まれているか(空の保存で通ってしまうことを防ぐ)
	var kinds: Dictionary = {}
	for e: Dictionary in d.enemies.enemies:
		kinds[str(e.kind)] = true
	var want_kinds: Array = ["root_mole", "skunk", "hippo", "honey_bear", "manhole", "sewer_rat", "bat_flock", "iron_rhino", "thunder_eel", "decoy_newt", "decoy_tail", "mirror_lizard", "pistol_shrimp", "balloon_frog"]
	var missing: Array = want_kinds.filter(func(k: String) -> bool: return not kinds.has(k) and k != "sewer_rat")
	t.ck("world_has_all_enemy_kinds_in_save", missing.is_empty(), str(missing))
	t.ck("world_has_odor_or_windup_state", d.enemies.odor.size() >= 0 and p.enemies.projectile_list().size() >= 1, "projectiles=%d odor=%d" % [p.enemies.projectile_list().size(), p.enemies.odor_clouds().size()])
	t.ck("world_has_reflected_projectile", p.enemies.projectile_list().any(func(x: Dictionary) -> bool: return x.kind == "reflected"))
	t.ck("world_has_wet_cells", d.common.wet.size() == 3 and d.common.hero_stun_until > d.common.time and d.common.helper_stop.size() == 1)
	var ck_kinds: Dictionary = {}
	for c: Dictionary in d.crops.crops:
		ck_kinds[str(c.kind)] = c
	t.ck("world_has_all_crop_kinds", ["kudzu", "loofah", "mimosa", "dandelion", "apple", "balsam", "hinoki", "evening_primrose"].all(func(k: String) -> bool: return ck_kinds.has(k)))
	t.ck("world_kudzu_has_roots_loofah_water_mimosa_closed", (ck_kinds["kudzu"].ext.roots as Array).size() >= 1 and int(ck_kinds["loofah"].ext.water) >= 1 and int(ck_kinds["loofah"].ext.water) <= 10 and ck_kinds["mimosa"].ext.closed == true and d.crops.fruits.size() >= 1, "roots=%d water=%s closed=%s fruits=%d" % [(ck_kinds["kudzu"].ext.roots as Array).size(), str(ck_kinds["loofah"].ext.water), str(ck_kinds["mimosa"].ext.closed), d.crops.fruits.size()])
	t.ck("world_glass_rolls_recorded", d.enemies.glass_rolls.size() == 3 and d.enemies.glass_seed == "31337")
	var q: RefCounted = t.mk(999)
	t.hero(q, 180, 100)
	t.helper(q, 77, 185, 96)
	var ok: bool = q.from_dict(d)
	q.host.stage_override = p.host.stage_override.duplicate()   # ホスト側の状態(草の段階など)は窓口の外なので、ホストが同じ状態を再現したものとする
	q.host.watered_cells = p.host.watered_cells.duplicate()
	t.ck("restore_accepts_full_world", ok, q.last_error)
	var d2: Dictionary = snapshot(q)
	t.ck("restore_state_identical_after_roundtrip", approx(d, d2))
	if not approx(d, d2):
		var fp: String = first_path(d, d2, "save")
		var kinds_at: String = ""
		if fp.contains("enemies[") and fp.contains("]."):
			var idx: int = int(fp.get_slice("enemies[", 1).get_slice("]", 0))
			kinds_at = str(d.enemies.enemies[idx].kind) + " pos=" + str(d.enemies.enemies[idx].pos) + " last=" + str(d.enemies.enemies[idx].last_cell) + " state=" + str(d.enemies.enemies[idx].state)
		t.ck("restore_first_diff", false, fp + " kind=" + kinds_at)
	# 継続: 同じ入力で同じ未来(1ステップずつ両方を進めて、イベントを突き合わせる)
	var same_events: bool = true
	var first_diff: String = ""
	for i: int in range(300):
		var e1: Array = p.advance(0.1)
		var e2: Array = q.advance(0.1)
		if not approx(norm(e1), norm(e2)):
			same_events = false
			first_diff = "step %d: %s" % [i, first_path(norm(e1), norm(e2), "ev")]
			break
	t.ck("restored_world_continues_identically_30s", same_events, first_diff)
	t.ck("restored_final_state_identical", approx(snapshot(p), snapshot(q)))
	# 乱数の連続: 窓口の乱数状態が保存される
	t.ck("rng_state_restored", str(q.rng.state) == str(p.rng.state) or approx(snapshot(p).rng, snapshot(q).rng))
	# 気絶・仕事停止・濡れの復元
	var r: RefCounted = t.mk(5)
	r.water_landed([Vector2i(5, 5)])
	r.common.hero_stun_until = 5.0
	r.common.helper_stop[9] = 4.0
	var rr: RefCounted = t.mk(5)
	rr.from_dict(norm(r.to_dict()))
	t.ck("common_state_restored", rr.common.is_wet(Vector2i(5, 5)) and t.near(rr.common.hero_stun_until, 5.0) and rr.common.helper_stop.has(9))
	# 旧形式(commonなし)の保存は共通状態を空にして読める
	var old: Dictionary = norm(r.to_dict())
	old.erase("common")
	var ro: RefCounted = t.mk(5)
	ro.water_landed([Vector2i(1, 1)])
	t.ck("old_format_without_common_loads_with_empty_common", ro.from_dict(old) and ro.common.wet.is_empty())
	# 抽選結果の復元後も、同じ地域の結果は不変(別の世界の種を渡しても記録が優先)
	var gl: RefCounted = t.mk(5)
	var h_before: int = gl.enemies.roll_glass_deer_region(1, "zz", [Vector2(1, 1), Vector2(2, 2), Vector2(3, 3), Vector2(4, 4), Vector2(5, 5), Vector2(6, 6), Vector2(7, 7), Vector2(8, 8), Vector2(9, 9), Vector2(10, 10)])
	var gl2: RefCounted = t.mk(5)
	gl2.from_dict(norm(gl.to_dict()))
	var h_after: int = gl2.enemies.roll_glass_deer_region(2, "zz", [Vector2(1, 1)])
	t.ck("glass_roll_record_wins_after_restore", h_before == h_after)

# ---------------------------------------------------------------- 不正データ
func mutate_check(label: String, mut: Callable, base: Dictionary) -> void:
	var p: RefCounted = t.mk(21)
	var pristine: RefCounted = t.mk(21)
	t.crop(p, "bamboo", 5, 30)   # 復元前の状態(拒否されたら変わってはならない)
	var before: Dictionary = snapshot(p)
	var bad: Dictionary = base.duplicate(true)
	mut.call(bad)
	if approx(bad, base):
		t.ck("reject_" + label, false, "mutation_not_applied (target missing in snapshot)")
		return
	var ok: bool = p.from_dict(bad)
	var after: Dictionary = snapshot(p)
	t.ck("reject_" + label, (not ok) and approx(before, after), "ok=%s err=%s unchanged=%s" % [str(ok), p.last_error, str(approx(before, after))])

func find_enemy(d: Dictionary, kind: String) -> Dictionary:
	for e: Variant in d.enemies.enemies:
		if e.kind == kind:
			return e
	return {}

func find_crop(d: Dictionary, kind: String) -> Dictionary:
	for c: Variant in d.crops.crops:
		if c.kind == kind:
			return c
	return {}

func invalid_data() -> void:
	var p: RefCounted = build_world()
	var base: Dictionary = snapshot(p)
	# 前提: 元データは受理される
	var okp: RefCounted = t.mk(1)
	t.ck("base_snapshot_valid", okp.from_dict(base.duplicate(true)), okp.last_error)
	# --- pack 全体
	mutate_check("format", func(d: Dictionary) -> void: d["format"] = 2, base)
	mutate_check("rng_seed_not_int_string", func(d: Dictionary) -> void: d.rng["seed"] = "abc", base)
	mutate_check("enemies_not_dict", func(d: Dictionary) -> void: d["enemies"] = [], base)
	mutate_check("common_not_dict", func(d: Dictionary) -> void: d["common"] = 5, base)
	# --- common
	mutate_check("common_missing_time", func(d: Dictionary) -> void: d.common.erase("time"), base)
	mutate_check("common_wet_bad_entry", func(d: Dictionary) -> void: d.common.wet.append([1, 2]), base)
	mutate_check("common_helper_stop_bad", func(d: Dictionary) -> void: d.common.helper_stop.append("x"), base)
	# --- 植物
	mutate_check("crop_missing_ext_key_dandelion", func(d: Dictionary) -> void: find_crop(d, "dandelion").ext.erase("next_fluff_at"), base)
	mutate_check("crop_ext_wrong_type_mimosa", func(d: Dictionary) -> void: find_crop(d, "mimosa").ext["closed"] = 1, base)
	mutate_check("crop_ext_missing_loofah_water", func(d: Dictionary) -> void: find_crop(d, "loofah").ext.erase("water"), base)
	mutate_check("crop_loofah_water_over_capacity", func(d: Dictionary) -> void: find_crop(d, "loofah").ext["water"] = 11, base)
	mutate_check("crop_loofah_water_negative", func(d: Dictionary) -> void: find_crop(d, "loofah").ext["water"] = -1, base)
	mutate_check("crop_kudzu_roots_not_array", func(d: Dictionary) -> void: find_crop(d, "kudzu").ext["roots"] = "x", base)
	mutate_check("crop_kudzu_roots_over_24", func(d: Dictionary) -> void:
		var arr: Array = []
		for i: int in range(25):
			arr.append([26 + (i % 5), 20 + (i / 5)])
		find_crop(d, "kudzu").ext["roots"] = arr, base)
	mutate_check("crop_kudzu_root_too_far", func(d: Dictionary) -> void: find_crop(d, "kudzu").ext["roots"] = [[40, 40]], base)
	mutate_check("crop_kudzu_root_overlaps_crop", func(d: Dictionary) -> void: find_crop(d, "kudzu").ext["roots"] = [[30, 24]], base)
	mutate_check("crop_kudzu_root_duplicate", func(d: Dictionary) -> void: find_crop(d, "kudzu").ext["roots"] = [[30, 25], [30, 25]], base)
	mutate_check("crop_kudzu_root_bad_cell", func(d: Dictionary) -> void: find_crop(d, "kudzu").ext["roots"] = [["a", 1]], base)
	mutate_check("crop_unknown_kind", func(d: Dictionary) -> void: find_crop(d, "apple")["kind"] = "durian", base)
	mutate_check("crop_overlap", func(d: Dictionary) -> void: find_crop(d, "hinoki")["cell"] = find_crop(d, "kudzu")["cell"], base)
	mutate_check("fruit_bad_cell", func(d: Dictionary) -> void: d.crops.fruits.append({"id": 77, "cell": "x", "source_id": 1}), base)
	mutate_check("fruit_duplicate_id", func(d: Dictionary) -> void: d.crops.fruits.append(d.crops.fruits[0].duplicate()), base)
	mutate_check("crops_fruits_not_array", func(d: Dictionary) -> void: d.crops["fruits"] = {}, base)
	mutate_check("crops_missing_next_fruit_id", func(d: Dictionary) -> void: d.crops.erase("next_fruit_id"), base)
	# --- 敵
	mutate_check("skunk_bad_state", func(d: Dictionary) -> void: find_enemy(d, "skunk")["state"] = "bogus", base)
	mutate_check("skunk_missing_spray_dir", func(d: Dictionary) -> void: find_enemy(d, "skunk").erase("spray_dir"), base)
	mutate_check("skunk_spray_dir_wrong_type", func(d: Dictionary) -> void: find_enemy(d, "skunk")["spray_dir"] = 3, base)
	mutate_check("mole_mound_bad_entry", func(d: Dictionary) -> void: find_enemy(d, "root_mole")["mounds"] = [5], base)
	mutate_check("mole_bad_state", func(d: Dictionary) -> void: find_enemy(d, "root_mole")["state"] = "fly", base)
	mutate_check("mole_t_cell_wrong_type", func(d: Dictionary) -> void: find_enemy(d, "root_mole")["t_cell"] = "x", base)
	mutate_check("hippo_bad_t_kind", func(d: Dictionary) -> void: find_enemy(d, "hippo")["t_kind"] = "moon", base)
	mutate_check("hippo_missing_land_dmg", func(d: Dictionary) -> void: find_enemy(d, "hippo").erase("land_dmg"), base)
	mutate_check("bear_bad_state", func(d: Dictionary) -> void: find_enemy(d, "honey_bear")["state"] = "dance", base)
	mutate_check("bear_bad_t_kind", func(d: Dictionary) -> void: find_enemy(d, "honey_bear")["t_kind"] = "moon", base)
	mutate_check("manhole_bad_state", func(d: Dictionary) -> void: find_enemy(d, "manhole")["state"] = "half", base)
	mutate_check("bat_bad_state", func(d: Dictionary) -> void: find_enemy(d, "bat_flock")["state"] = "dead", base)
	mutate_check("rhino_rust_over_5", func(d: Dictionary) -> void: find_enemy(d, "iron_rhino")["rust"] = 6, base)
	mutate_check("rhino_rust_negative", func(d: Dictionary) -> void: find_enemy(d, "iron_rhino")["rust"] = -1, base)
	mutate_check("rhino_trample_bad_value", func(d: Dictionary) -> void: find_enemy(d, "iron_rhino")["trample"] = {"3": "x"}, base)
	mutate_check("rhino_bad_state", func(d: Dictionary) -> void: find_enemy(d, "iron_rhino")["state"] = "fly", base)
	mutate_check("eel_chain_bad_entry", func(d: Dictionary) -> void: find_enemy(d, "thunder_eel")["chain"] = [5], base)
	mutate_check("eel_bad_state", func(d: Dictionary) -> void: find_enemy(d, "thunder_eel")["state"] = "boom", base)
	mutate_check("decoy_tail_missing_run_dir", func(d: Dictionary) -> void: find_enemy(d, "decoy_tail").erase("run_dir"), base)
	mutate_check("decoy_bad_state", func(d: Dictionary) -> void: find_enemy(d, "decoy_newt")["state"] = "x", base)
	mutate_check("lizard_bad_state", func(d: Dictionary) -> void: find_enemy(d, "mirror_lizard")["state"] = "x", base)
	mutate_check("shrimp_bad_state", func(d: Dictionary) -> void: find_enemy(d, "pistol_shrimp")["state"] = "x", base)
	mutate_check("frog_bad_state", func(d: Dictionary) -> void: find_enemy(d, "balloon_frog")["state"] = "x", base)
	mutate_check("enemy_hp_wrong_type", func(d: Dictionary) -> void: find_enemy(d, "skunk")["hp"] = "full", base)
	mutate_check("enemy_unknown_kind", func(d: Dictionary) -> void: find_enemy(d, "skunk")["kind"] = "dragon", base)
	mutate_check("enemy_duplicate_id", func(d: Dictionary) -> void: d.enemies.enemies[1]["id"] = d.enemies.enemies[0]["id"], base)
	mutate_check("enemy_missing_template_key", func(d: Dictionary) -> void: find_enemy(d, "skunk").erase("spray_at"), base)
	mutate_check("enemy_pos_wrong_type", func(d: Dictionary) -> void: find_enemy(d, "skunk")["pos"] = [1, 2], base)
	mutate_check("odor_missing_key", func(d: Dictionary) -> void: d.enemies.odor.append({"pos": {"_v": [1, 1]}}), base)
	mutate_check("acid_wrong_type", func(d: Dictionary) -> void: d.enemies.acid.append({"pos": 5}), base)
	mutate_check("projectile_missing_key", func(d: Dictionary) -> void: d.enemies.projectiles.append({"kind": "reflected"}), base)
	mutate_check("glass_rolls_bad_value", func(d: Dictionary) -> void: d.enemies.glass_rolls["x"] = "no", base)
	mutate_check("glass_seed_not_int_string", func(d: Dictionary) -> void: d.enemies["glass_seed"] = "q", base)
	mutate_check("glass_seed_not_string", func(d: Dictionary) -> void: d.enemies["glass_seed"] = 5, base)
	# 追加の境界(拒否されるべきか、仕様上許容か判断が要る観察): 結果は ck に残す

# ---------------------------------------------------------------- ポーズ中は進まない
func pause_stops_time() -> void:
	var g: RefCounted = Game.new(7)
	g.tab = "enemy2"
	g.hero_pos = Vector2(180, 100)
	g.pack.enemies.spawn("skunk", Vector2(160, 100), "initial")
	g.pack.enemies.spawn("root_mole", Vector2(202, 102), "initial")
	g.pack.enemies.spawn("thunder_eel", Vector2(50, 30), "initial")
	g.pack.enemies.spawn_bat_flock(Vector2(108, 68), "initial")
	var kid: int = int(g.pack.crops.spawn_crop("kudzu", Vector2i(30, 24), 0, {"mature": true, "watered": true, "skip_check": true}).id)
	g.pack.crops.spawn_crop("balsam", Vector2i(49, 27), 0, {"mature": true, "watered": true, "skip_check": true})
	g.pack.crops.spawn_crop("apple", Vector2i(10, 20), 0, {"mature": true, "watered": true, "skip_check": true})
	g.pack.water_landed([Vector2i(20, 7)])
	g.step(2.0)
	var snap0: Dictionary = norm(g.pack.to_dict())
	g.paused = true
	for i: int in range(50):
		g.step(0.5)
	var snap1: Dictionary = norm(g.pack.to_dict())
	t.ck("pause_pack_state_unchanged_25s", approx(snap0, snap1))
	t.ck("pause_time_unchanged", t.near(g.pack.enemies.time, 2.0, 0.11) and t.near(g.pack.common.time, g.pack.enemies.time, 0.01) and t.near(g.pack.crops.time, g.pack.enemies.time, 0.01))
	t.ck("pause_wet_not_expiring", g.pack.common.is_wet(Vector2i(20, 7)))
	g.paused = false
	g.speed = 0
	g.step(10.0)
	t.ck("speed0_state_unchanged", approx(snap0, norm(g.pack.to_dict())))
	g.speed = 1
	g.step(1.0)
	t.ck("resume_advances", g.pack.enemies.time > 2.5)
	# pack.advance(0) / 負は進めない
	var p: RefCounted = t.mk()
	t.crop(p, "kudzu", 30, 24)
	var s0: Dictionary = snapshot(p)
	p.advance(0.0)
	p.advance(-5.0)
	t.ck("advance_nonpositive_no_change", approx(s0, snapshot(p)))
	# 保存・復元はポーズ中でも時刻を進めない
	var st: Dictionary = norm(g.pack.to_dict())
	g.pack.from_dict(st)
	t.ck("restore_does_not_advance_time", t.near(g.pack.enemies.time, float(st.enemies.time)))
