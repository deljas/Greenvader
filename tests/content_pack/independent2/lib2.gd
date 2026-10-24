extends RefCounted
## 独立検証(第2弾)の共通部品。入口スクリプトではない(--script で直接起動しない。入口から preload して使う)。
## self2 の部品は使わず、窓口(content_pack)と仮アダプターの公開口だけを使う。
const Lab: GDScript = preload("res://scripts/content_pack/lab/lab_host.gd")
const Pack: GDScript = preload("res://scripts/content_pack/content_pack.gd")

var checks: Array = []

func ck(name: String, ok: bool, detail: String = "") -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})

## 観察(合否の対象外。仕様の読み方に幅がある点や、ホスト側の責任の点を記録する)
func note(name: String, detail: String) -> void:
	checks.append({"name": name, "status": "NOTE", "detail": detail})

func near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps

func mk(seed: int = 5) -> RefCounted:
	return Pack.new(Lab.new(), seed)

func sp(p: RefCounted, kind: String, x: float, y: float, origin: String = "initial", opts: Dictionary = {}) -> int:
	return p.enemies.spawn(kind, Vector2(x, y), origin, opts)

func R(p: RefCounted, id: int) -> Dictionary:
	return p.enemies.ref(id)

func hero(p: RefCounted, x: float, y: float, aim: Vector2 = Vector2.RIGHT) -> void:
	p.host.hero_state = {"pos": Vector2(x, y), "hp": 100.0, "max_hp": 100.0, "aim": aim}

func helper(p: RefCounted, id: int, x: float, y: float) -> void:
	p.host.helper_list.append({"id": id, "pos": Vector2(x, y), "hp": 50.0, "max_hp": 50.0})

func crop(p: RefCounted, kind: String, x: int, y: int, mature: bool = true, watered: bool = true) -> int:
	var r: Dictionary = p.crops.spawn_crop(kind, Vector2i(x, y), 20, {"mature": mature, "watered": watered, "skip_check": true})
	return int(r.id) if bool(r.ok) else -1

func evs(events: Array, type: String, kind: String = "") -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if e.type == type and (kind == "" or str(e.get("kind", "")) == kind):
			out.append(e)
	return out

func fxk(events: Array, kind: String) -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if e.type == "fx" and e.get("kind", "") == kind:
			out.append(e)
	return out

## secs秒を dt 刻みで進め、[{t, e}] を返す(t は窓口の時刻)。fn(p) があれば各刻みの前に呼ぶ。
func sim(p: RefCounted, secs: float, dt: float = 0.1, fn: Callable = Callable()) -> Array:
	var out: Array = []
	var n: int = int(round(secs / dt))
	for i: int in range(n):
		if fn.is_valid():
			fn.call(p)
		var ev: Array[Dictionary] = p.advance(dt)
		for e: Dictionary in ev:
			out.append({"t": p.enemies.time, "e": e})
			if e.type == "ground_stage":
				p.host.set_stage(e.cell, e.stage)
			elif e.type == "seed_sow":
				p.host.set_stage(e.cell, "seed")
	return out

func E(tl: Array) -> Array:
	var out: Array = []
	for x: Dictionary in tl:
		out.append(x.e)
	return out

func of_type(tl: Array, type: String, kind: String = "") -> Array:
	var out: Array = []
	for x: Dictionary in tl:
		if x.e.type == type and (kind == "" or str(x.e.get("kind", "")) == kind):
			out.append(x)
	return out

func ang_deg(v: Vector2) -> float:
	return rad_to_deg(v.angle())

func finish(suite: String, out_dir: String, tree: SceneTree) -> void:
	var fails: int = 0
	var lines: Array = []
	for c: Dictionary in checks:
		var line: String = "%s %s %s" % [c.status, c.name, c.detail]
		print(line)
		lines.append(line)
		if c.status == "FAIL":
			fails += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var f: FileAccess = FileAccess.open(out_dir + "/" + suite + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": suite, "total": checks.size(), "failed": fails, "checks": checks}, "\t"))
	f.close()
	var lf: FileAccess = FileAccess.open(out_dir + "/" + suite + ".log", FileAccess.WRITE)
	lf.store_string("\n".join(lines) + "\n%s total=%d failed=%d\n" % [suite, checks.size(), fails])
	lf.close()
	print("%s total=%d failed=%d" % [suite, checks.size(), fails])
	tree.quit(1 if fails > 0 else 0)
