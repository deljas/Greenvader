extends SceneTree
## 独立検証(差戻し後): 正常な保存が誤って拒否されないか/型違いが拒否されるか。
const Lab: GDScript = preload("res://scripts/content_pack/lab/lab_host.gd")
const Pack: GDScript = preload("res://scripts/content_pack/content_pack.gd")
const OUT_DIR: String = "res://evidence/content_pack/independent"
const KINDS: Array = ["shadow_brian", "tarachunade", "quill_hedgehog", "grass_snake", "seed_bird", "junk_crab", "moss_turtle", "paint_chameleon", "slime_slug", "pouch_rabbit", "tongue_frog", "honeybee_hive", "armadillo", "sludge_carp", "ant_hill", "mimic_cabbage", "black_kite", "deer", "iron_jaw_beetle"]
var checks: Array = []
var PROVOKE: bool = true

func ck(name: String, ok: bool, detail: String = "") -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})

func rt(d: Dictionary) -> Dictionary:
	var v: Variant = JSON.parse_string(JSON.stringify(d))
	return v if typeof(v) == TYPE_DICTIONARY else {}

func scene(seed: int) -> RefCounted:
	var p: RefCounted = Pack.new(Lab.new(), seed)
	var i: int = 0
	for k: String in KINDS:
		var pos: Vector2 = Vector2(30, 30) if k == "sludge_carp" else Vector2(60 + (i % 6) * 55, 60 + (i / 6) * 55)
		p.enemies.spawn(k, pos)
		i += 1
	p.enemies.spawn_mushling_family(Vector2(120, 330))
	p.enemies.spawn_wolf_pack(Vector2(350, 300))
	p.enemies.add_junk_pile(Vector2(250, 330), 3)
	p.crops.spawn_crop("golden_four_leaf", Vector2i(10, 12), 0, {"mature": true, "watered": true, "skip_check": true})
	p.crops.spawn_crop("clover", Vector2i(12, 12), 0, {"mature": false, "watered": true, "skip_check": true})
	p.host.hero_state = {"pos": Vector2(180, 160), "hp": 100.0, "max_hp": 100.0, "aim": Vector2.RIGHT}
	return p

func run(p: RefCounted, secs: float) -> void:
	for n: int in range(int(secs / 0.1)):
		if PROVOKE and n % 10 == 0 and p.enemies.enemies.size() > 0:
			var tgt: Dictionary = p.enemies.enemies[(n / 10 + int(p.enemies.time)) % p.enemies.enemies.size()]
			p.host.hero_state.pos = tgt.pos + Vector2(14, 0)
			p.hit_enemy(int(tgt.id), 6.0, "shot", null)
		for e: Dictionary in p.advance(0.1):
			if e.type == "ground_stage":
				p.host.set_stage(e.cell, e.stage)

func _initialize() -> void:
	var total_ok: int = 0
	var total: int = 0
	var worst: String = ""
	for seed: int in [5, 21]:
		var a: RefCounted = scene(seed)
		var t: float = 0.0
		var stat: Dictionary = {}
		for step: int in range(8):
			run(a, 8.0)
			t += 8.0
			for e: Dictionary in a.enemies.enemies:
				stat[str(e.kind) + ":" + str(e.state)] = true
			var saved: Dictionary = rt(a.to_dict())
			var b: RefCounted = Pack.new(Lab.new(), 1)
			b.host.hero_state = a.host.hero_state.duplicate(true)
			var ok: bool = b.from_dict(saved)
			total += 1
			if ok:
				total_ok += 1
			else:
				worst = "seed%d t%d: %s" % [seed, int(t), b.enemies.last_error]
			ck("adopt_seed%d_t%d" % [seed, int(t)], ok, b.enemies.last_error if not ok else "enemies=%d proj=%d gas=%d piles=%d slime=%d" % [a.enemies.enemies.size(), a.enemies.projectiles.size(), a.enemies.gas.size(), a.enemies.piles.size(), a.enemies.slime.size()])
			if ok and step in [2, 5, 7]:
				var sa0: String = JSON.stringify(rt(b.to_dict()))
				ck("roundtrip_exact_seed%d_t%d" % [seed, int(t)], sa0 == JSON.stringify(saved), "")
				var a2: RefCounted = Pack.new(Lab.new(), 1)
				a2.from_dict(saved)
				a2.host.hero_state = a.host.hero_state.duplicate(true)
				run(a2, 20.0)
				run(b, 20.0)
				ck("progress_identical_seed%d_t%d" % [seed, int(t)], JSON.stringify(rt(a2.to_dict())) == JSON.stringify(rt(b.to_dict())), "")
		print("STATES seed%d: %s" % [seed, ",".join(stat.keys())])
	ck("all_snapshots_adopted", total_ok == total, "%d/%d %s" % [total_ok, total, worst])
	# 型違いの拒否
	var base: RefCounted = scene(9)
	run(base, 30.0)
	var snap: String = JSON.stringify(rt(base.to_dict()))
	var rejected: int = 0
	var cases: int = 0
	var unchanged: bool = true
	var all_bad: Array = []
	var en0: Dictionary = rt(base.to_dict()).enemies.enemies[0]
	for kidx: int in range(base.enemies.enemies.size()):
		var keys: Array = base.enemies.enemies[kidx].keys()
		var kind: String = str(base.enemies.enemies[kidx].kind)
		# 各個体で型を持つ数値/文字列/真偽キーを1つずつ壊す(個体あたり最大3件)
		var done: int = 0
		for key: String in keys:
			var v: Variant = base.enemies.enemies[kidx][key]
			if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and key != "id" and done < 3:
				var d: Dictionary = rt(base.to_dict())
				d.enemies.enemies[kidx][key] = "bad"
				var q: RefCounted = Pack.new(Lab.new(), 1)
				var before: String = JSON.stringify(rt(q.to_dict()))
				var ok: bool = q.from_dict(d)
				cases += 1
				if not ok: rejected += 1
				else: all_bad.append("%s.%s" % [kind, key])
				if JSON.stringify(rt(q.to_dict())) != before: unchanged = false
				done += 1
	ck("type_mismatch_rejected", all_bad.is_empty() and cases > 30, "cases=%d rejected=%d accepted_bad=%s" % [cases, rejected, ",".join(all_bad)])
	ck("rejection_leaves_state_unchanged", unchanged, "")
	# 付属物の型違い
	var extra_cases: Array = []
	for sect: String in ["projectiles", "gas", "piles"]:
		var arr: Array = base.enemies.get(sect)
		if arr.size() > 0:
			var d2: Dictionary = rt(base.to_dict())
			var k0: String = d2.enemies[sect][0].keys()[0]
			d2.enemies[sect][0].damage = "x" if sect == "projectiles" else d2.enemies[sect][0].get("damage", 0)
			var key2: String = {"projectiles": "speed", "gas": "radius", "piles": "stock"}[sect]
			d2.enemies[sect][0][key2] = "x"
			var q2: RefCounted = Pack.new(Lab.new(), 1)
			extra_cases.append(sect + ":" + str(not q2.from_dict(d2)))
	print("EXTRA type cases: " + ",".join(extra_cases))
	ck("attachment_type_mismatch_rejected_if_present", not extra_cases.has("projectiles:false") and not extra_cases.has("gas:false") and not extra_cases.has("piles:false"), ",".join(extra_cases))
	var pass_n: int = 0
	for c: Dictionary in checks:
		if c.status == "PASS": pass_n += 1
		else: print("FAIL " + c.name + " " + c.detail)
	print("ROBUST2 %d PASS / %d" % [pass_n, checks.size()])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/robust_v2_r2.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(checks, "\t"))
	f.close()
	quit(0 if pass_n == checks.size() else 1)
