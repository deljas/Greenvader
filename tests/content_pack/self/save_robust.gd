extends SceneTree
## 壊れた保存(種類固有キーの欠落・型違い)を拒否し状態を変えないことの自己検証(入口スクリプト)。
## 実行(隔離プロジェクトのみ): Godot --headless --path C:/godot/greenvader_content_sandbox --script res://tests/content_pack/self/save_robust.gd
const Lab: GDScript = preload("res://scripts/content_pack/lab/lab_host.gd")
const Pack: GDScript = preload("res://scripts/content_pack/content_pack.gd")
const OUT_DIR: String = "res://evidence/content_pack/self"
const KINDS: Array = ["shadow_brian", "tarachunade", "mushling_parent", "mushling_child", "quill_hedgehog", "grass_snake", "seed_bird", "junk_crab", "stray_wolf", "moss_turtle", "paint_chameleon", "slime_slug", "pouch_rabbit", "tongue_frog", "honeybee_hive", "armadillo", "sludge_carp", "ant_hill", "mimic_cabbage", "black_kite", "deer", "iron_jaw_beetle"]

var checks: Array = []

func ck(name: String, ok: bool, detail: String = "") -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})

func mk() -> RefCounted:
	return Pack.new(Lab.new(), 1)

func rt(p: RefCounted) -> Dictionary:
	return JSON.parse_string(JSON.stringify(p.to_dict()))

func base_pack() -> RefCounted:
	var q: RefCounted = mk()
	q.enemies.spawn("shadow_brian", Vector2(60, 60))
	q.advance(0.3)
	return q

## 壊した保存を読ませて拒否と状態不変を調べる。戻り値: 採用されたか
func try_load(dd: Dictionary) -> Array:
	var q: RefCounted = base_pack()
	var before: String = JSON.stringify(q.to_dict())
	var ok: bool = q.from_dict(dd)
	var same: bool = JSON.stringify(q.to_dict()) == before
	return [ok, same]

func wrong_value(v: Variant) -> Variant:
	if typeof(v) == TYPE_STRING:
		return 12345
	return "bad"

func check_container(label: String, p: RefCounted, section: String, list_key: String) -> void:
	var d: Dictionary = rt(p)
	var arr: Array = d[section][list_key]
	if arr.is_empty():
		ck(label + "_present", false, "no item")
		return
	var keys: Array = (arr[0] as Dictionary).keys()
	var bad_adopt: Array = []
	var not_same: Array = []
	for k: String in keys:
		if k == "size":
			continue  # 作物のsizeは種類から導出する値で読み込まない(欠落しても無害)
		var d1: Dictionary = rt(p)
		(d1[section][list_key][0] as Dictionary).erase(k)
		var r: Array = try_load(d1)
		if r[0]:
			bad_adopt.append("-" + k)
		if not r[1]:
			not_same.append("-" + k)
		var d2: Dictionary = rt(p)
		var orig: Variant = d2[section][list_key][0][k]
		if orig != null:
			d2[section][list_key][0][k] = wrong_value(orig)
			var r2: Array = try_load(d2)
			if r2[0]:
				bad_adopt.append("~" + k)
			if not r2[1]:
				not_same.append("~" + k)
	ck(label + "_broken_rejected_state_unchanged", bad_adopt.is_empty() and not_same.is_empty(), "keys=%d adopted=%s changed=%s" % [keys.size(), ",".join(bad_adopt), ",".join(not_same)])
	var good: RefCounted = base_pack()
	var gok: bool = good.from_dict(rt(p))
	ck(label + "_valid_adopted", gok, good.last_error)

func _initialize() -> void:
	for kind: String in KINDS:
		var p: RefCounted = mk()
		var pos: Vector2 = Vector2(30, 30) if kind == "sludge_carp" else Vector2(100, 100)
		var id: int = p.enemies.spawn(kind, pos)
		p.host.hero_state = {"pos": pos + Vector2(10, 0), "hp": 100.0, "max_hp": 100.0, "aim": Vector2.RIGHT}
		# 敵の先頭(spawnした本体)の全キーを1つずつ消す/型違いにする
		var d0: Dictionary = rt(p)
		var idx: int = 0
		for i: int in range(d0.enemies.enemies.size()):
			if int(d0.enemies.enemies[i].id) == id:
				idx = i
		var keys: Array = (d0.enemies.enemies[idx] as Dictionary).keys()
		var bad_adopt: Array = []
		var not_same: Array = []
		for k: String in keys:
			var d1: Dictionary = rt(p)
			(d1.enemies.enemies[idx] as Dictionary).erase(k)
			var r: Array = try_load(d1)
			if r[0]:
				bad_adopt.append("-" + k)
			if not r[1]:
				not_same.append("-" + k)
			var orig: Variant = d0.enemies.enemies[idx][k]
			if orig != null:
				var d2: Dictionary = rt(p)
				d2.enemies.enemies[idx][k] = wrong_value(orig)
				var r2: Array = try_load(d2)
				if r2[0]:
					bad_adopt.append("~" + k)
				if not r2[1]:
					not_same.append("~" + k)
		ck(kind + "_broken_rejected_state_unchanged", bad_adopt.is_empty() and not_same.is_empty(), "keys=%d adopted=%s changed=%s" % [keys.size(), ",".join(bad_adopt), ",".join(not_same)])
		var good: RefCounted = base_pack()
		var gok: bool = good.from_dict(rt(p))
		for i: int in range(20):
			good.advance(0.1)
		ck(kind + "_valid_adopted_and_advances", gok)
	# 家族・群れ・置き場付きのカニ
	var fam: RefCounted = mk()
	fam.enemies.spawn_mushling_family(Vector2(100, 100))
	var okq: bool = base_pack().from_dict(rt(fam))
	ck("mushling_family_valid", okq)
	var wolf: RefCounted = mk()
	wolf.enemies.spawn_wolf_pack(Vector2(100, 100))
	ck("wolf_pack_valid", base_pack().from_dict(rt(wolf)))
	# 付属物
	var pa: RefCounted = mk()
	pa.enemies.spawn_projectile({"kind": "needle", "owner": 1, "pos": Vector2(50, 50), "dir": Vector2.RIGHT, "speed": 30.0, "left": 40.0, "damage": 2.0})
	pa.enemies.add_gas(Vector2(60, 60), 1, 20.0, 5.0, 1.0)
	pa.enemies.add_junk_pile(Vector2(70, 70), 2)
	check_container("projectile", pa, "enemies", "projectiles")
	check_container("gas", pa, "enemies", "gas")
	check_container("pile", pa, "enemies", "piles")
	# 作物側: 全種類を植えて正常採用と、各キー欠落の拒否
	var cp: RefCounted = mk()
	var n: int = 0
	for ck_kind: String in cp.crops.defs.keys():
		var r: Dictionary = cp.crops.spawn_crop(ck_kind, Vector2i(2 + (n % 6) * 8, 4 + (n / 6) * 8), 0, {"mature": true, "watered": true})
		if bool(r.ok):
			n += 1
	ck("crops_planted", n > 0, str(n))
	check_container("crop", cp, "crops", "crops")
	print_results()

func print_results() -> void:
	var fails: int = 0
	var lines: Array = []
	for c: Dictionary in checks:
		var line: String = "%s %s %s" % [c.status, c.name, c.detail]
		print(line)
		lines.append(line)
		if c.status != "PASS":
			fails += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/save_robust.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "save_robust", "total": checks.size(), "failed": fails, "checks": checks}, "\t"))
	f.close()
	var lf: FileAccess = FileAccess.open(OUT_DIR + "/save_robust.log", FileAccess.WRITE)
	lf.store_string("\n".join(lines) + "\nsave_robust total=%d failed=%d\n" % [checks.size(), fails])
	lf.close()
	print("save_robust total=%d failed=%d" % [checks.size(), fails])
	quit(1 if fails > 0 else 0)
