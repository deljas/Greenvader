extends SceneTree
## 独立検証: 壊れた保存(敵ごとの固有キー欠落・型違い)が採用されないか。採用された場合に進行で落ちないか。
const Lab: GDScript = preload("res://scripts/content_pack/lab/lab_host.gd")
const Pack: GDScript = preload("res://scripts/content_pack/content_pack.gd")
const CORE: Array = ["id", "kind", "origin", "tier", "pos", "home", "hp", "max_hp", "state", "until", "face", "reward_paid", "alive", "flee_until", "flee_from", "wp", "wp_valid", "wait_until", "last_cell", "group_id", "parent_id", "pack_id", "slot", "blocked", "melee_at"]
const KINDS: Array = ["shadow_brian", "tarachunade", "mushling_parent", "mushling_child", "quill_hedgehog", "grass_snake", "seed_bird", "junk_crab", "stray_wolf", "moss_turtle", "paint_chameleon", "slime_slug", "pouch_rabbit", "tongue_frog", "honeybee_hive", "armadillo", "sludge_carp", "ant_hill", "mimic_cabbage", "black_kite", "deer", "iron_jaw_beetle"]

func _initialize() -> void:
	var adopted: Array = []
	var rejected: int = 0
	for kind: String in KINDS:
		var p: RefCounted = Pack.new(Lab.new(), 1)
		var pos: Vector2 = Vector2(30, 30) if kind == "sludge_carp" else Vector2(100, 100)
		p.enemies.spawn(kind, pos)
		p.host.hero_state = {"pos": pos + Vector2(10, 0), "hp": 100.0, "max_hp": 100.0, "aim": Vector2.RIGHT}
		var d: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
		var extra: Array = []
		for k: String in d.enemies.enemies[0].keys():
			if not CORE.has(k):
				extra.append(k)
		for k: String in extra:
			var q: RefCounted = Pack.new(Lab.new(), 1)
			var dd: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
			dd.enemies.enemies[0].erase(k)
			var before: String = JSON.stringify(q.to_dict())
			var ok: bool = q.from_dict(dd)
			if ok:
				adopted.append("%s.%s" % [kind, k])
				q.host.hero_state = p.host.hero_state
				for i: int in range(20):
					q.advance(0.1)
			else:
				rejected += 1
	print("ROBUST adopted_missing_key=%d rejected=%d" % [adopted.size(), rejected])
	print("ROBUST adopted: " + ",".join(adopted))
	quit(0)
