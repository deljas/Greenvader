extends RefCounted
## 第2弾の敵テストの共通部品(入口スクリプトではない。入口から preload して使う)。
const Lab: GDScript = preload("res://scripts/content_pack/lab/lab_host.gd")
const Pack: GDScript = preload("res://scripts/content_pack/content_pack.gd")

var checks: Array = []

func ck(name: String, ok: bool, detail: String = "") -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})

func near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps

func mk(seed: int = 1) -> RefCounted:
	return Pack.new(Lab.new(), seed)

func sp(p: RefCounted, kind: String, x: float, y: float, origin: String = "initial", opts: Dictionary = {}) -> int:
	return p.enemies.spawn(kind, Vector2(x, y), origin, opts)

func E(p: RefCounted, id: int) -> Dictionary:
	return p.enemies.get_enemy(id)

func R(p: RefCounted, id: int) -> Dictionary:
	return p.enemies.ref(id)

func hero(p: RefCounted, x: float, y: float, aim: Vector2 = Vector2.RIGHT) -> void:
	p.host.hero_state = {"pos": Vector2(x, y), "hp": 100.0, "max_hp": 100.0, "aim": aim}

func helper(p: RefCounted, id: int, x: float, y: float) -> void:
	p.host.helper_list.append({"id": id, "pos": Vector2(x, y), "hp": 50.0, "max_hp": 50.0})

func crop(p: RefCounted, kind: String, x: int, y: int, mature: bool = true) -> int:
	var r: Dictionary = p.crops.spawn_crop(kind, Vector2i(x, y), 0, {"mature": mature, "watered": true, "skip_check": true})
	return int(r.id) if bool(r.ok) else -1

func evs(events: Array, type: String, kind: String = "") -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if e.type == type and (kind == "" or str(e.get("kind", "")) == kind):
			out.append(e)
	return out

## 秒数ぶん進めてイベントを集める(各要素 {"t": 敵側の時刻, "e": イベント})
func timed(p: RefCounted, secs: float, dt: float = 0.1) -> Array:
	var out: Array = []
	var n: int = int(round(secs / dt))
	for i: int in range(n):
		var ev: Array[Dictionary] = p.advance(dt)
		for e: Dictionary in ev:
			out.append({"t": p.enemies.time, "e": e})
	return out

func only(tl: Array, type: String, kind: String = "") -> Array:
	var out: Array = []
	for x: Dictionary in tl:
		var e: Dictionary = x.e
		if e.type == type and (kind == "" or str(e.get("kind", "")) == kind):
			out.append(x)
	return out

func plain(tl: Array) -> Array:
	var out: Array = []
	for x: Dictionary in tl:
		out.append(x.e)
	return out

func fx_of(tl: Array, kind: String) -> Array:
	var out: Array = []
	for x: Dictionary in tl:
		var e: Dictionary = x.e
		if e.type == "fx" and e.get("kind", "") == kind:
			out.append(x)
	return out

func roundtrip(d: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(d))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func ids_of(p: RefCounted, kind: String) -> Array:
	var out: Array = []
	for e: Dictionary in p.enemies.enemies:
		if e.alive and e.kind == kind:
			out.append(int(e.id))
	return out

func has_target(p: RefCounted, id: int) -> bool:
	for t: Dictionary in p.enemies.hittable_targets():
		if t.type == "enemy" and int(t.id) == id:
			return true
	return false

func finish(suite: String, out_dir: String, tree: SceneTree) -> void:
	var fails: int = 0
	var lines: Array = []
	for c: Dictionary in checks:
		var line: String = "%s %s %s" % [c.status, c.name, c.detail]
		print(line)
		lines.append(line)
		if c.status != "PASS":
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
