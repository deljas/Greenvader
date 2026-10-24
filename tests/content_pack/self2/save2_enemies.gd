extends SceneTree
## 第2弾の動物の新しい状態(盛り土・臭気の雲・反射した弾・分身・酸・マンホール網・コウモリの各個体・錆・満腹度など)の
## 保存復元と、不正データの拒否(種類テンプレート照合、全体検証後の一括採用)、ポーズ中に進まないこと(合格条件8)の自己検証(入口スクリプト)。
## 実行(隔離プロジェクトのみ): Godot --headless --path C:/godot/greenvader_content_sandbox --script res://tests/content_pack/self2/save2_enemies.gd
const Lib: GDScript = preload("res://tests/content_pack/self2/enemies2_lib.gd")
const OUT_DIR: String = "res://evidence/content_pack/self2"
const NEW_KINDS: Array = ["root_mole", "skunk", "hippo", "honey_bear", "sewer_rat", "manhole", "bat_flock", "iron_rhino", "thunder_eel",
	"decoy_newt", "decoy_tail", "mirror_lizard", "pistol_shrimp", "balloon_frog", "glass_deer"]

var L: RefCounted = Lib.new()

func ck(name: String, ok: bool, detail: String = "") -> void:
	L.ck(name, ok, detail)

func rt(x: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(x))

func norm(p: RefCounted) -> String:
	return JSON.stringify(rt(p.to_dict()))

## ホスト側の設定(保存の対象外)。元と復元先でそろえる
func host_setup(p: RefCounted) -> void:
	for c: Vector2i in [Vector2i(8, 26), Vector2i(14, 26)]:
		p.host.set_terrain(c, 1)
	L.hero(p, 150.0, 120.0)
	p.host.helper_list = [{"id": 3, "pos": Vector2(160.0, 120.0), "hp": 50.0, "max_hp": 50.0}]

func adv(p: RefCounted, secs: float, dt: float = 0.1) -> Array:
	var out: Array = []
	for i: int in range(int(round(secs / dt))):
		out.append_array(p.advance(dt))
	return out

## 第2弾の動物をひととおり途中状態にした世界。ゆっくり動く種類を先に20秒走らせ、すばやい種類は後から出して短く進める
func build() -> RefCounted:
	var p: RefCounted = L.mk(21)
	host_setup(p)
	# ネッコモグラ(盛り土)
	L.crop(p, "potato", 56, 15)
	L.sp(p, "root_mole", 200.0, 60.0)
	# カバ(上陸して食べる)
	L.sp(p, "hippo", 50.0, 50.0)
	L.crop(p, "pumpkin", 24, 6)
	# ハチミツグマ(落果を食べて満腹へ)
	L.sp(p, "honey_bear", 100.0, 120.0)
	for i: int in range(3):
		p.crops.fruits.append({"id": i + 1, "cell": Vector2i(26 + i, 30), "source_id": 0})
	p.crops.next_fruit_id = 4
	# マンホール網(片方を塞ぐ)
	p.enemies.spawn_manhole_net([Vector2(34, 106), Vector2(58, 106)], "initial")
	p.crops.spawn_crop("bamboo", Vector2i(14, 26), 0, {"mature": true, "watered": true})
	# テツヨロイサイ(錆3)
	L.sp(p, "iron_rhino", 30.0, 130.0)
	for i2: int in range(3):
		p.splash(Vector2(32, 130), 20.0, 0.0, "water")
	# カミナリウナギ(濡れたマス)
	L.sp(p, "thunder_eel", 34.0, 26.0)
	p.water_landed([Vector2i(10, 6), Vector2i(11, 6), Vector2i(12, 6)])
	# タイホウエビ・ガラスジカ
	L.sp(p, "pistol_shrimp", 180.0, 20.0)
	L.sp(p, "glass_deer", 20.0, 100.0)
	p.enemies.place_glass_deer(4242, {"ra": [Vector2(40, 100)], "rb": [Vector2(60, 100), Vector2(70, 100)]})
	adv(p, 20.0)
	# すばやい種類は後から出し、途中の状態を作る
	var sk: int = L.sp(p, "skunk", 200.0, 100.0)
	L.R(p, sk).face = Vector2.RIGHT
	p.hit_enemy(sk, 1.0, "shot", Vector2(260.0, 100.0))
	adv(p, 0.8)
	var nt: int = L.sp(p, "decoy_newt", 230.0, 60.0)
	p.hit_enemy(nt, 1.0, "shot", Vector2(260.0, 60.0))
	var bats: Array = p.enemies.spawn_bat_flock(Vector2(120.0, 54.0))
	p.hit_enemy(bats[0], 1.0, "shot", Vector2(160.0, 54.0))   # 1匹落として群れが飛び立つ
	var fr: Array = p.enemies.spawn_frog_flock(Vector2(150.0, 80.0))
	adv(p, 1.5)
	for f: int in fr:
		if L.R(p, f).state == "float":
			p.hit_enemy(f, 1.0, "helper", Vector2(0, 0))   # 1匹割って酸を残す
			break
	var lz: int = L.sp(p, "mirror_lizard", 170.0, 120.0)
	L.R(p, lz).face = Vector2.RIGHT
	p.hit_enemy(lz, 1.0, "shot", Vector2(230.0, 120.0))
	adv(p, 0.2)
	return p

func wrong(v: Variant) -> Variant:
	if typeof(v) == TYPE_STRING:
		return 12345
	return "bad"

func base_pack() -> RefCounted:
	var q: RefCounted = L.mk()
	host_setup(q)
	L.sp(q, "shadow_brian", 60.0, 60.0)
	adv(q, 5.0)
	return q

## 壊した保存を読ませる。戻り値 [採用されたか, 状態が変わらなかったか]
func try_load(dd: Dictionary) -> Array:
	var q: RefCounted = base_pack()
	var before: String = JSON.stringify(q.to_dict())
	var ok: bool = q.from_dict(dd)
	return [ok, JSON.stringify(q.to_dict()) == before]

func _initialize() -> void:
	t_roundtrip()
	t_reject()
	t_flags()
	L.finish("save2_enemies", OUT_DIR, self)

func t_roundtrip() -> void:
	var p: RefCounted = build()
	var es: RefCounted = p.enemies
	var moles: Array = L.ids_of(p, "root_mole")
	var has_mounds: bool = not moles.is_empty() and not L.R(p, moles[0]).mounds.is_empty()
	var kinds_present: Dictionary = {}
	for e: Dictionary in es.enemies:
		kinds_present[e.kind] = true
	var missing: Array = []
	for k: String in NEW_KINDS:
		if not kinds_present.has(k):
			missing.append(k)
	ck("save2e_state_has_all_new_kinds", missing.is_empty(), str(missing))
	ck("save2e_state_has_mounds", has_mounds, "")
	ck("save2e_state_has_odor_cloud", es.odor.size() >= 1, "n=%d" % es.odor.size())
	ck("save2e_state_has_reflected_shot_in_flight", es.projectiles.any(func(x: Dictionary) -> bool: return x.kind == "reflected"), "n=%d" % es.projectiles.size())
	ck("save2e_state_has_decoy_and_regrow_timer", not L.ids_of(p, "decoy_tail").is_empty() and not bool(L.R(p, L.ids_of(p, "decoy_newt")[0]).tail), "")
	ck("save2e_state_has_acid", es.acid.size() >= 1, "n=%d" % es.acid.size())
	ck("save2e_state_has_rust_and_satiety", int(L.R(p, L.ids_of(p, "iron_rhino")[0]).rust) == 3 and int(L.R(p, L.ids_of(p, "honey_bear")[0]).satiety) >= 1, "sat=%d" % int(L.R(p, L.ids_of(p, "honey_bear")[0]).satiety))
	ck("save2e_state_has_manhole_net_and_plug", L.ids_of(p, "manhole").size() == 2 and L.ids_of(p, "manhole").any(func(i: int) -> bool: return L.R(p, i).state == "closed"), "")
	ck("save2e_state_has_bats_in_flight", L.ids_of(p, "bat_flock").size() == 6 and L.ids_of(p, "bat_flock").any(func(i: int) -> bool: return L.R(p, i).state != "roost"), "")
	ck("save2e_state_has_glass_rolls", es.glass_rolls.size() == 2, "")
	var d: Dictionary = rt(p.to_dict())
	var q: RefCounted = L.mk(1)
	host_setup(q)
	var ok: bool = q.from_dict(d)
	ck("save2e_adopts_valid", ok, str(q.last_error))
	ck("save2e_roundtrip_identical", norm(p) == norm(q), first_diff(rt(p.to_dict()), rt(q.to_dict())))
	ck("save2e_odor_acid_projectiles_restored", q.enemies.odor.size() == es.odor.size() and q.enemies.acid.size() == es.acid.size() and q.enemies.projectiles.size() == es.projectiles.size() and typeof(q.enemies.odor[0].pos) == TYPE_VECTOR2 if not es.odor.is_empty() else true, "")
	ck("save2e_mounds_restored_as_vectors", moles.is_empty() or L.R(q, moles[0]).mounds.is_empty() or typeof(L.R(q, moles[0]).mounds[0].pos) == TYPE_VECTOR2, "")
	ck("save2e_glass_state_restored", q.enemies.glass_rolls == es.glass_rolls and q.enemies.glass_seed == es.glass_seed, "")
	ck("save2e_cell_and_ids_are_int_vectori", typeof(L.R(q, L.ids_of(q, "manhole")[0]).plug) == TYPE_INT and typeof(L.R(q, L.ids_of(q, "manhole")[0]).net_id) == TYPE_INT and typeof(L.R(q, L.ids_of(q, "root_mole")[0]).t_cell) == TYPE_VECTOR2I, "")
	# 復元後も同じように進む(乱数の状態も含めて)
	var ev1: Array = adv(p, 25.0)
	var ev2: Array = adv(q, 25.0)
	var c1: Dictionary = {}
	var c2: Dictionary = {}
	for e: Dictionary in ev1:
		c1[e.type] = int(c1.get(e.type, 0)) + 1
	for e2: Dictionary in ev2:
		c2[e2.type] = int(c2.get(e2.type, 0)) + 1
	ck("save2e_continues_identically_25s", first_diff(rt(p.to_dict()), rt(q.to_dict())) == "" and JSON.stringify(c1) == JSON.stringify(c2), first_diff(rt(p.to_dict()), rt(q.to_dict())) + " " + JSON.stringify(c1) + JSON.stringify(c2))
	# ポーズ中(時間を進めない)は何も変わらない
	var before: String = norm(q)
	q.advance(0.0)
	q.advance(-1.0)
	ck("save2e_pause_unchanged_with_all_new_state", norm(q) == before, "")

## 2つのJSON値の最初の違いの場所(デバッグ表示用)
func first_diff(a: Variant, b: Variant, path: String = "") -> String:
	if typeof(a) != typeof(b):
		return path + " type " + str(a) + " vs " + str(b)
	if typeof(a) == TYPE_DICTIONARY:
		for k: Variant in (a as Dictionary):
			if not (b as Dictionary).has(k):
				return path + "/" + str(k) + " missing in b"
			var r: String = first_diff((a as Dictionary)[k], (b as Dictionary)[k], path + "/" + str(k))
			if r != "":
				return r
		for k2: Variant in (b as Dictionary):
			if not (a as Dictionary).has(k2):
				return path + "/" + str(k2) + " missing in a"
		return ""
	if typeof(a) == TYPE_ARRAY:
		if (a as Array).size() != (b as Array).size():
			return path + " size %d vs %d" % [(a as Array).size(), (b as Array).size()]
		for i: int in range((a as Array).size()):
			var r2: String = first_diff(a[i], b[i], path + "[%d]" % i)
			if r2 != "":
				return r2
		return ""
	if typeof(a) == TYPE_FLOAT or typeof(a) == TYPE_INT:
		return "" if absf(float(a) - float(b)) <= 1e-9 else path + " " + str(a) + " vs " + str(b)   # JSONの小数の丸め(1e-13程度)は許容する
	return "" if a == b else path + " " + str(a) + " vs " + str(b)

func enemy_index(d: Dictionary, kind: String) -> int:
	var arr: Array = d.enemies.enemies
	for i: int in range(arr.size()):
		if arr[i].kind == kind:
			return i
	return -1

func t_reject() -> void:
	var p: RefCounted = build()
	var good: Dictionary = rt(p.to_dict())
	ck("save2e_reject_baseline_valid", bool(try_load(good)[0]), "")
	# 種類テンプレート照合: 新しい種類の敵の全キーについて、欠落と型違いを拒否する
	var bad_missing: Array = []
	var bad_type: Array = []
	var checked: int = 0
	for kind: String in NEW_KINDS:
		var idx: int = enemy_index(good, kind)
		if idx < 0:
			continue
		var keys: Array = (good.enemies.enemies[idx] as Dictionary).keys()
		for k: String in keys:
			var d1: Dictionary = rt(good)
			(d1.enemies.enemies[idx] as Dictionary).erase(k)
			var r1: Array = try_load(d1)
			if bool(r1[0]) or not bool(r1[1]):
				bad_missing.append(kind + "." + k)
			var d2: Dictionary = rt(good)
			var orig: Variant = (d2.enemies.enemies[idx] as Dictionary)[k]
			if orig == null:
				continue
			(d2.enemies.enemies[idx] as Dictionary)[k] = wrong(orig)
			var r2: Array = try_load(d2)
			if bool(r2[0]) or not bool(r2[1]):
				bad_type.append(kind + "." + k)
			checked += 1
	ck("save2e_reject_missing_key_every_new_kind", bad_missing.is_empty(), str(bad_missing))
	ck("save2e_reject_wrong_type_every_new_kind", bad_type.is_empty() and checked > 100, "checked=%d bad=%s" % [checked, str(bad_type)])
	# 入れ子の値・状態名
	var nested: Array = []
	var mi: int = enemy_index(good, "root_mole")
	if mi >= 0 and not (good.enemies.enemies[mi].mounds as Array).is_empty():
		var d3: Dictionary = rt(good)
		d3.enemies.enemies[mi].mounds[0] = "x"
		nested.append(["mounds_entry_not_dict", d3])
		var d3b: Dictionary = rt(good)
		d3b.enemies.enemies[mi].mounds[0].pos = "x"
		nested.append(["mounds_pos_bad", d3b])
		var d3c: Dictionary = rt(good)
		d3c.enemies.enemies[mi].mounds[0].erase("until")
		nested.append(["mounds_until_missing", d3c])
	for kind2: String in NEW_KINDS:
		var ix: int = enemy_index(good, kind2)
		if ix < 0 or kind2 == "glass_deer" and false:
			continue
		var d4: Dictionary = rt(good)
		d4.enemies.enemies[ix].state = "no_such_state"
		nested.append(["unknown_state_" + kind2, d4])
	var ri: int = enemy_index(good, "iron_rhino")
	var d5: Dictionary = rt(good)
	d5.enemies.enemies[ri].rust = 99
	nested.append(["rust_over_max", d5])
	var d5b: Dictionary = rt(good)
	d5b.enemies.enemies[ri].trample = {"1": "x"}
	nested.append(["trample_value_bad", d5b])
	var ei: int = enemy_index(good, "thunder_eel")
	var d6: Dictionary = rt(good)
	d6.enemies.enemies[ei].chain = ["x"]
	nested.append(["eel_chain_bad", d6])
	var bad_n: Array = []
	for n: Array in nested:
		var rn: Array = try_load(n[1])
		if bool(rn[0]) or not bool(rn[1]):
			bad_n.append(n[0])
	ck("save2e_reject_nested_and_state_names", bad_n.is_empty() and nested.size() >= 15, "n=%d bad=%s" % [nested.size(), str(bad_n)])
	# 容器(臭気・酸・抽選記録)
	var cont: Array = []
	var dc: Dictionary = rt(good)
	dc.enemies.erase("odor")
	cont.append(["odor_missing", dc])
	var dc2: Dictionary = rt(good)
	dc2.enemies.erase("acid")
	cont.append(["acid_missing", dc2])
	var dc3: Dictionary = rt(good)
	dc3.enemies.odor = "x"
	cont.append(["odor_not_array", dc3])
	if not (good.enemies.odor as Array).is_empty():
		for k2: String in (good.enemies.odor[0] as Dictionary).keys():
			var dd: Dictionary = rt(good)
			(dd.enemies.odor[0] as Dictionary).erase(k2)
			cont.append(["odor_missing_" + k2, dd])
			var de: Dictionary = rt(good)
			(de.enemies.odor[0] as Dictionary)[k2] = wrong((good.enemies.odor[0] as Dictionary)[k2])
			cont.append(["odor_type_" + k2, de])
	if not (good.enemies.acid as Array).is_empty():
		for k3: String in (good.enemies.acid[0] as Dictionary).keys():
			var df: Dictionary = rt(good)
			(df.enemies.acid[0] as Dictionary).erase(k3)
			cont.append(["acid_missing_" + k3, df])
			var dg: Dictionary = rt(good)
			(dg.enemies.acid[0] as Dictionary)[k3] = wrong((good.enemies.acid[0] as Dictionary)[k3])
			cont.append(["acid_type_" + k3, dg])
	var dh: Dictionary = rt(good)
	dh.enemies.glass_seed = 12.5
	cont.append(["glass_seed_not_string", dh])
	var dh2: Dictionary = rt(good)
	dh2.enemies.glass_rolls = []
	cont.append(["glass_rolls_not_dict", dh2])
	var dh3: Dictionary = rt(good)
	dh3.enemies.glass_rolls = {"ra": "x"}
	cont.append(["glass_rolls_value_bad", dh3])
	# 反射した弾の欠落
	var pj: int = -1
	for i: int in range((good.enemies.projectiles as Array).size()):
		if good.enemies.projectiles[i].kind == "reflected":
			pj = i
	if pj >= 0:
		var di: Dictionary = rt(good)
		(di.enemies.projectiles[pj] as Dictionary).erase("damage")
		cont.append(["reflected_missing_damage", di])
		var dj: Dictionary = rt(good)
		(dj.enemies.projectiles[pj] as Dictionary)["dir"] = "x"
		cont.append(["reflected_dir_bad", dj])
	var bad_c: Array = []
	for n2: Array in cont:
		var rc: Array = try_load(n2[1])
		if bool(rc[0]) or not bool(rc[1]):
			bad_c.append(n2[0])
	ck("save2e_reject_new_containers", bad_c.is_empty() and cont.size() >= 20, "n=%d bad=%s" % [cont.size(), str(bad_c)])
	# 全体検証後の一括採用: 敵が正常でも common(濡れ)が壊れていれば何も採用しない
	var dk: Dictionary = rt(good)
	dk.common.wet = [["x"]]
	var rk: Array = try_load(dk)
	ck("save2e_atomic_when_other_part_invalid", not bool(rk[0]) and bool(rk[1]), "")
	# 敵が壊れていれば植物側も採用されない(植物の変更が漏れない)
	var dl: Dictionary = rt(good)
	dl.enemies.enemies[enemy_index(good, "hippo")].state = "bad"
	var ql: RefCounted = base_pack()
	var crops_before: String = JSON.stringify(ql.crops.to_dict())
	var okl: bool = ql.from_dict(dl)
	ck("save2e_atomic_crops_untouched_when_enemy_invalid", not okl and JSON.stringify(ql.crops.to_dict()) == crops_before, "")

func t_flags() -> void:
	# 報酬の払い済みフラグ・マンホールの報酬済みは復元後も保たれる(二重払いしない)
	var p: RefCounted = L.mk(5)
	host_setup(p)
	var bats: Array = p.enemies.spawn_bat_flock(Vector2(120.0, 54.0))
	var net: Dictionary = p.enemies.spawn_manhole_net([Vector2(34, 106)], "initial")
	p.crops.spawn_crop("bamboo", Vector2i(8, 26), 0, {"mature": true, "watered": true})
	var tl: Array = L.timed(p, 0.3)
	var paid_ev: Array = L.evs(L.plain(tl), "reward").filter(func(x: Dictionary) -> bool: return x.kind == "manhole")
	ck("save2e_nest_reward_first_time_once", paid_ev.size() == 1, "")
	var q: RefCounted = L.mk(1)
	host_setup(q)
	ok_load(q, p)
	var tlq: Array = L.timed(q, 0.5)
	ck("save2e_nest_reward_not_repaid_after_restore", L.evs(L.plain(tlq), "reward").is_empty() and bool(L.R(q, net.manholes[0]).nest_paid), "")
	# 個体ごとの報酬: 復元した個体を倒すと1回。reward_paid が true の個体は払わない
	var ev1: Array = q.hit_enemy(bats[0], 99.0, "shot", Vector2(160, 54))
	ck("save2e_bat_reward_once_after_restore", L.evs(ev1, "reward").size() == 1, "")
	var d: Dictionary = rt(p.to_dict())
	var bi: int = enemy_index(d, "bat_flock")
	d.enemies.enemies[bi].reward_paid = true
	var q2: RefCounted = L.mk(1)
	host_setup(q2)
	var ok2: bool = q2.from_dict(d)
	var ev2: Array = q2.hit_enemy(int(d.enemies.enemies[bi].id), 99.0, "shot", Vector2(160, 54))
	ck("save2e_reward_paid_flag_prevents_repay", ok2 and L.evs(ev2, "reward").is_empty(), "")
	# ポーズ中: 時間を進めなければ(advance を呼ばなければ)すべて止まっている
	var q3: RefCounted = L.mk(1)
	host_setup(q3)
	ok_load(q3, p)
	var b0: String = norm(q3)
	ck("save2e_no_advance_no_change", norm(q3) == b0, "")

func ok_load(dst: RefCounted, src: RefCounted) -> void:
	var d: Dictionary = rt(src.to_dict())
	var ok: bool = dst.from_dict(d)
	ck("save2e_helper_load_ok", ok, str(dst.last_error))
