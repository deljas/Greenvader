extends SceneTree
## 独立検証: 敵 追加確認(怒りの速度・黒焦げ後のHP・飛行の安定地域回避・近接)。入口スクリプト。
const Lab: GDScript = preload("res://scripts/content_pack/lab/lab_host.gd")
const Pack: GDScript = preload("res://scripts/content_pack/content_pack.gd")
const OUT_DIR: String = "res://evidence/content_pack/independent"

var checks: Array = []

func ck(name: String, ok: bool, detail: String = "") -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})

func near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps

func mk(seed: int = 3) -> RefCounted:
	return Pack.new(Lab.new(), seed)

func sp(p: RefCounted, kind: String, x: float, y: float, origin: String = "initial", opts: Dictionary = {}) -> int:
	return p.enemies.spawn(kind, Vector2(x, y), origin, opts)

func R(p: RefCounted, id: int) -> Dictionary:
	return p.enemies.ref(id)

func hero(p: RefCounted, x: float, y: float, aim: Vector2 = Vector2.RIGHT, hp: float = 100.0) -> void:
	p.host.hero_state = {"pos": Vector2(x, y), "hp": hp, "max_hp": 100.0, "aim": aim}

func hpos(p: RefCounted) -> Vector2:
	return p.host.hero_state.pos

func crop(p: RefCounted, kind: String, x: int, y: int, mature: bool = true) -> int:
	var r: Dictionary = p.crops.spawn_crop(kind, Vector2i(x, y), 0, {"mature": mature, "watered": true, "skip_check": true})
	return int(r.id) if bool(r.ok) else -1

func evs(events: Array, type: String, kind: String = "") -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if e.type == type and (kind == "" or str(e.get("kind", "")) == kind):
			out.append(e)
	return out

func fxs(events: Array, kind: String) -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if e.type == "fx" and e.kind == kind:
			out.append(e)
	return out

## secs秒を dt 刻みで進め、[{t,e}] を返す。fn(p, t) があれば各刻みの前に呼ぶ。ground_stage はホストへ反映する。
func sim(p: RefCounted, secs: float, dt: float = 0.1, fn: Callable = Callable()) -> Array:
	var out: Array = []
	var n: int = int(round(secs / dt))
	for i: int in range(n):
		if fn.is_valid():
			fn.call(p, p.enemies.time)
		var ev: Array[Dictionary] = p.advance(dt)
		for e: Dictionary in ev:
			out.append({"t": p.enemies.time, "e": e})
			if e.type == "ground_stage":
				p.host.set_stage(e.cell, e.stage)
	return out

func E(tl: Array) -> Array:
	return tl.map(func(x: Dictionary) -> Dictionary: return x.e)

func hero_dmg(tl: Array, amount: float = -1.0) -> Array:
	var out: Array = []
	for x: Dictionary in tl:
		if x.e.type == "hero_damage" and (amount < 0.0 or near(float(x.e.amount), amount, 1e-6)):
			out.append(x)
	return out

func rt(d: Dictionary) -> Dictionary:
	var v: Variant = JSON.parse_string(JSON.stringify(d))
	return v if typeof(v) == TYPE_DICTIONARY else {}

func _initialize() -> void:
	# マッシュリング: 怒り中は速度x1.6
	var spd: Array = []
	for rage: bool in [false, true]:
		var p: RefCounted = mk()
		var fam: Dictionary = p.enemies.spawn_mushling_family(Vector2(40, 120))
		for k: int in fam.children:
			p.enemies.ref(k).hp = 1000.0
			p.enemies.ref(k).state = "idle"
		hero(p, 200, 120)
		R(p, fam.parent).rage_until = p.enemies.time + (100.0 if rage else 0.0)
		R(p, fam.parent).state = "chase"
		R(p, fam.parent).home = Vector2(120, 120)
		var p0: Vector2 = R(p, fam.parent).pos
		sim(p, 1.0)
		spd.append(R(p, fam.parent).pos.distance_to(p0))
	ck("mushling_normal_speed_1.4mps", near(spd[0], 14.0, 1.6), "%.1f" % spd[0])
	ck("mushling_rage_speed_x1.6", near(spd[1], 22.4, 1.5), "%.1f" % spd[1])
	# 黒焦げ中に受けた被ダメージは復活後も残るか(仕様文: 黒焦げになる前のHPのまま復活)
	var t: RefCounted = mk()
	var ti: int = sp(t, "tarachunade", 100, 120)
	hero(t, 112, 120)
	var guard: int = 0
	while R(t, ti).state != "charred" and guard < 100:
		sim(t, 0.1)
		guard += 1
	var hp_charred: float = float(R(t, ti).hp)
	t.hit_enemy(ti, 5.0, "shot", null)
	var hp_hit: float = float(R(t, ti).hp)
	hero(t, 400, 400)
	sim(t, 16.0)
	var hp_revived: float = float(R(t, ti).hp)
	print("INFO tarachunade hp: before_hit=%.1f after_hit_in_charred=%.1f after_revive=%.1f" % [hp_charred, hp_hit, hp_revived])
	ck("tarachunade_explosion_keeps_hp_30", near(hp_charred, 30.0), "")
	ck("tarachunade_charred_damage_x2_persists_after_revive_info", near(hp_hit, 20.0), "hp=%.1f" % hp_hit)
	# トンビは安定地域の上空に入らない
	var k: RefCounted = mk()
	k.host.set_stable_rect(Rect2i(24, 22, 14, 14))    # px x96..152 y88..144
	var kid: int = sp(k, "black_kite", 100, 100)
	R(k, kid).home = Vector2(124, 100)
	R(k, kid).pos = Vector2(100, 80)
	R(k, kid).ang = (Vector2(R(k, kid).pos) - Vector2(R(k, kid).home)).angle()
	hero(k, 400, 400)
	var inside: bool = false
	for i: int in range(300):
		k.advance(0.1)
		var c: Vector2i = Vector2i(floori(R(k, kid).pos.x / 4.0), floori(R(k, kid).pos.y / 4.0))
		if k.host.is_stable_cell(c):
			inside = true
	ck("kite_never_flies_over_stable_cells", not inside, "")
	# ブリアン: 近接8/1.2秒、報酬15は1回(階級そのまま)
	var b: RefCounted = mk()
	var bi: int = sp(b, "shadow_brian", 100, 120)
	hero(b, 100, 130)
	var tl: Array = sim(b, 0.3)
	b.enemies.ref(bi).state = "recover"
	b.enemies.ref(bi).until = 1e9
	var ml: Array = sim(b, 6.0)
	var melee: Array = hero_dmg(ml, 8.0)
	ck("brian_melee_8_every_1.2s", melee.size() >= 4 and melee.size() <= 6, str(melee.size()))
	# 中立は「報酬なし」: ミツバチの巣と群れの破壊で reward イベントなし(初期配置・tierありでも)
	var h: RefCounted = mk()
	var hv: int = sp(h, "honeybee_hive", 102, 102, "initial", {"tier": "far"})
	var allev: Array = []
	for id: int in h.enemies.enemy_ids():
		allev.append_array(h.hit_enemy(id, 1000.0, "shot", null))
	ck("bees_never_pay_reward", evs(allev, "reward").is_empty() and h.enemies.enemy_ids().is_empty(), "")
	var fails: int = 0
	for c: Dictionary in checks:
		print("%s %s %s" % [c.status, c.name, c.detail])
		if c.status != "PASS":
			fails += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/extra_v.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "extra_v", "total": checks.size(), "failed": fails, "checks": checks}, "\t"))
	f.close()
	print("extra_v total=%d failed=%d" % [checks.size(), fails])
	quit(1 if fails > 0 else 0)
