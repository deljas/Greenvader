extends RefCounted
## 栽培植物28種(+親のクローバー)のロジック。ホストのデータは書き換えず、イベント(Dictionary、"type"キー)で返す。
## 生産(1.3節): 定義値 x 変種倍率 x 自分の条件 = 基礎、基礎 x (1 + 黄金系 + ミツバチ) = 補正後。
const Defs: GDScript = preload("res://scripts/content_pack/content_defs.gd")
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")

const STEP_MAX: float = 1.0
const GOLD_RADIUS: int = 7
const GOLD_STEP: float = 0.07
const GOLD_K_MAX: int = 7
const BEE_RADIUS: int = 8
const BEE_BASE: float = 0.10
const BEE_FLOWER: float = 0.20
const PICKUP_RADIUS_PX: float = 8.0
const REFUND_DIVISOR: float = 5.0
const PX_PER_M: float = 10.0

var host: RefCounted
var rng: RandomNumberGenerator
var defs: Dictionary = {}
var time: float = 0.0
var crops: Array = []
var next_id: int = 1
var poison_next_at: float = 5.0
var pickups: Array = []
var next_pickup_id: int = 1
var produced: Dictionary = {}
var last_error: String = ""
## 敵側の占有(擬態中のミミック、巣、アリ塚)。Callable(cell: Vector2i) -> String(占有する種類。なければ "")。
var occupy_check: Callable = Callable()
## 敵側の受粉源。Callable() -> Array([{"cell","size","active"}])。ホストの pollinators() に加えて数える。
var pollinator_extra: Callable = Callable()
## 敵の位置の供給。Callable() -> Array([{"pos":Vector2,"neutral":bool}])。オジギソウ・ホウセンカが近くの敵を調べる。
## ホスト側の敵(既存のバッタなど)は host.host_enemies() から加わる。
var enemy_feed: Callable = Callable()
## 開いているマンホールのマスか(第2弾)。Callable(cell: Vector2i) -> bool。該当マスには「緑化済み」の条件を除いて栽培植物を植えられる(塞ぐ)。
var manhole_check: Callable = Callable()
## リンゴの落果。[{"id","cell"(Vector2i),"source_id"}]。拾えない囮で、敵側が参照・消費する。
var fruits: Array = []
var next_fruit_id: int = 1
var _by_id: Dictionary = {}
var _occ: Dictionary = {}
var _root_occ: Dictionary = {}   # クズの根のマス(Vector2i) -> 株のID

func _init(p_host: RefCounted, p_rng: RandomNumberGenerator, p_defs: Dictionary = {}) -> void:
	host = p_host
	rng = p_rng
	defs = p_defs if not p_defs.is_empty() else Defs.load_crops()

# ---------------------------------------------------------------- 定義
func def_of(kind: String) -> Dictionary:
	return defs.get(kind, {})

func size_of(kind: String) -> Vector2i:
	var s: Array = def_of(kind).get("size", [1, 1])
	return Vector2i(int(s[0]), int(s[1]))

func _param(kind: String, key: String, fallback: float) -> float:
	var p: Dictionary = def_of(kind).get("params", {})
	return float(p.get(key, fallback))

func rect_of(c: Dictionary) -> Rect2i:
	return Rect2i(c.cell, c.size)

func get_crop(id: int) -> Dictionary:
	if _by_id.has(id):
		var c: Dictionary = _by_id[id]
		return c.duplicate(true)
	return {}

func crop_ids() -> Array:
	var out: Array = []
	for c: Dictionary in crops:
		out.append(c.id)
	return out

func crop_id_at(cell: Vector2i) -> int:
	return int(_occ.get(cell, 0))

func family_count(family: String) -> int:
	var n: int = 0
	for c: Dictionary in crops:
		if str(def_of(c.kind).get("price_family", c.kind)) == family:
			n += 1
	return n

func quote(kind: String) -> int:
	var fam: String = str(def_of(kind).get("price_family", kind))
	return int(host.price(kind, family_count(fam)))

# ---------------------------------------------------------------- 配置
func check_placement(kind: String, cell: Vector2i) -> Dictionary:
	if not defs.has(kind):
		return {"ok": false, "reason": "unknown_kind"}
	var d: Dictionary = def_of(kind)
	var rect: Rect2i = Rect2i(cell, size_of(kind))
	var mode: String = str(d.get("place", "normal"))
	for c: Vector2i in Grid.cells_of(rect):
		if not host.in_bounds(c):
			return {"ok": false, "reason": "outside_map"}
		if not host.is_explored(c):
			return {"ok": false, "reason": "unexplored"}
		if _root_occ.has(c):
			return {"ok": false, "reason": "occupied", "by": "kudzu_root"}
		if _occ.has(c) or host.is_blocked(c):
			return {"ok": false, "reason": "occupied"}
		if occupy_check.is_valid():
			var by: String = str(occupy_check.call(c))
			if by != "":
				return {"ok": false, "reason": "occupied", "by": by}
		if mode == "surface":
			if not host.is_water(c):
				return {"ok": false, "reason": "not_water"}
			continue
		if not host.is_walkable(c):
			return {"ok": false, "reason": "blocked_ground"}
		if mode == "normal" and not host.is_green(c):
			if manhole_check.is_valid() and bool(manhole_check.call(c)):
				continue   # マンホールのマスは緑化済みでなくても植えられる(それ以外の条件は通常どおり)
			return {"ok": false, "reason": "requires_green"}
	if mode == "surface":
		var shore: bool = false
		for c: Vector2i in Grid.adjacent_cells(rect):
			if host.in_bounds(c) and host.is_walkable(c) and not host.is_water(c):
				shore = true
				break
		if not shore:
			return {"ok": false, "reason": "needs_shore"}
	if d.has("near_clean_water"):
		if not _any_near(rect, int(d.near_clean_water), true):
			return {"ok": false, "reason": "needs_clean_water"}
	if d.has("near_water"):
		if not _any_near(rect, int(d.near_water), false):
			return {"ok": false, "reason": "needs_water"}
	return {"ok": true, "reason": ""}

func _any_near(rect: Rect2i, n: int, clean: bool) -> bool:
	for c: Vector2i in Grid.cells_of(Grid.expanded(rect, n)):
		if not host.in_bounds(c):
			continue
		if (host.is_clean_water(c) if clean else host.is_water(c)):
			return true
	return false

## プレイヤーの設置。価格はホストの式で決まり、支払いはホストが行う(結果の paid を使う)。
func place_crop(kind: String, cell: Vector2i) -> Dictionary:
	if not defs.has(kind):
		return {"ok": false, "reason": "unknown_kind", "events": []}
	if not bool(def_of(kind).get("placeable", true)):
		return {"ok": false, "reason": "not_placeable", "events": []}
	var chk: Dictionary = check_placement(kind, cell)
	if not bool(chk.ok):
		return {"ok": false, "reason": chk.reason, "events": []}
	return _create(kind, cell, quote(kind), 0, {})

## 内部・デバッグ用の生成。opts: skip_check, mature, watered, colony_id, variant_rolled
func spawn_crop(kind: String, cell: Vector2i, paid: int, opts: Dictionary = {}) -> Dictionary:
	if not defs.has(kind):
		return {"ok": false, "reason": "unknown_kind", "events": []}
	if not bool(opts.get("skip_check", false)):
		var chk: Dictionary = check_placement(kind, cell)
		if not bool(chk.ok):
			return {"ok": false, "reason": chk.reason, "events": []}
	return _create(kind, cell, paid, int(opts.get("colony_id", 0)), opts)

func _create(kind: String, cell: Vector2i, paid: int, colony_id: int, opts: Dictionary) -> Dictionary:
	var ev: Array[Dictionary] = []
	var d: Dictionary = def_of(kind)
	var id: int = next_id
	next_id += 1
	var c: Dictionary = {
		"id": id, "kind": kind, "cell": cell, "size": size_of(kind), "paid": paid,
		"grow": 0.0, "mature": false, "since_mature": 0.0, "watered": bool(opts.get("watered", false)),
		"hp": float(d.hp), "variant_rolled": bool(opts.get("variant_rolled", d.has("variant_from"))),
		"poison": 0, "colony_id": colony_id if colony_id != 0 else (id if kind == "mint" else 0),
		"next_spread_at": 0.0, "next_drop_at": 0.0, "storage": 0.0, "digest_until": 0.0,
		"ready_at": 0.0, "wall_adj": false, "gnawed": false, "hit_log": {}, "ext": _new_ext(kind)}
	var rect: Rect2i = Rect2i(cell, c.size)
	for cc: Vector2i in Grid.cells_of(rect):
		_occ[cc] = id
		if kind == "cactus" and not host.is_green(cc):
			ev.append({"type": "ground_seed", "cell": cc})
	for ac: Vector2i in Grid.adjacent_cells(rect):
		if host.is_building(ac):
			c.wall_adj = true
			break
	for f: Dictionary in fruits.duplicate():
		if rect.has_point(f.cell):
			fruits.erase(f)
			ev.append({"type": "fruit_removed", "fruit_id": f.id, "cell": f.cell, "reason": "planted"})
	crops.append(c)
	_by_id[id] = c
	ev.append({"type": "crop_placed", "crop_id": id, "kind": kind, "cell": cell, "paid": paid})
	if float(d.maturity) <= 0.0 or bool(opts.get("mature", false)):
		_mature(c, ev, false)
	return {"ok": true, "reason": "", "id": id, "paid": paid, "events": ev}

func set_watered(id: int, watered: bool) -> void:
	if _by_id.has(id):
		var c: Dictionary = _by_id[id]
		# ヘチマは給水されると貯水を満たす(未給水から給水済みへ変わった時)
		if watered and not bool(c.watered) and c.kind == "loofah":
			c.ext.water = int(_param("loofah", "capacity", 10.0))
		c.watered = watered

func set_gnawed(id: int, gnawed: bool) -> void:
	if _by_id.has(id):
		_by_id[id].gnawed = gnawed

## 種類固有の状態(第2弾)。保存の照合では、この見本の全キー・型が必要。
func _new_ext(kind: String) -> Dictionary:
	match kind:
		"dandelion":
			return {"next_fluff_at": 0.0}
		"mimosa":
			return {"closed": false, "open_at": 0.0}
		"kudzu":
			return {"roots": [], "next_grow_at": 0.0}
		"loofah":
			return {"water": 0, "next_water_at": 0.0}
		"apple":
			return {"next_fruit_at": 0.0}
		"balsam":
			return {"next_pop_at": 0.0, "trigger_ok_at": 0.0}
	return {}

# ---------------------------------------------------------------- 撤去・喪失
## reason: manual(返還あり) / enemy / poison(返還0)
func remove_crop(id: int, reason: String = "manual") -> Dictionary:
	if not _by_id.has(id):
		return {"ok": false, "reason": "not_found", "refund": 0, "events": []}
	var c: Dictionary = _by_id[id]
	var refund: int = 0
	if reason == "manual":
		refund = floori(float(c.paid) / REFUND_DIVISOR)
		if c.kind == "potato":
			refund += floori(float(c.storage))
	for cc: Vector2i in Grid.cells_of(rect_of(c)):
		_occ.erase(cc)
	crops.erase(c)
	_by_id.erase(id)
	var ev: Array[Dictionary] = [{"type": "crop_removed", "crop_id": id, "kind": c.kind, "reason": reason,
		"refund": refund, "cell": c.cell, "size": c.size, "paid": c.paid}]
	# クズの株を失うと根は全消滅(返還0)
	if c.kind == "kudzu":
		for rc: Vector2i in c.ext.roots:
			_root_occ.erase(rc)
			ev.append({"type": "kudzu_root_removed", "crop_id": id, "cell": rc, "reason": "stock_lost"})
		c.ext.roots = []
	return {"ok": true, "reason": "", "refund": refund, "events": ev}

# ---------------------------------------------------------------- 範囲・条件
func _near(a: Dictionary, b: Dictionary, n: int) -> bool:
	return Grid.within(rect_of(a), rect_of(b), n)

func gold_k(c: Dictionary) -> int:
	var k: int = 0
	for o: Dictionary in crops:
		if o.id == c.id or not o.mature:
			continue
		if bool(def_of(o.kind).get("gold_aura", false)) and _near(c, o, GOLD_RADIUS):
			k += 1
	return mini(k, GOLD_K_MAX)

func is_bloom(c: Dictionary) -> bool:
	if c.kind != "sakura" or not c.mature:
		return false
	return fmod(float(c.since_mature), _param("sakura", "cycle", 240.0)) < _param("sakura", "bloom", 40.0)

func is_flower(c: Dictionary) -> bool:
	var d: Dictionary = def_of(c.kind)
	if bool(d.get("flower", false)):
		return true
	if bool(d.get("flower_at_night", false)) and not host.is_day():
		return true
	return bool(d.get("flower_when_bloom", false)) and is_bloom(c)

func bee_bonus(c: Dictionary) -> float:
	var best: float = 0.0
	var hives: Array = host.pollinators()
	if pollinator_extra.is_valid():
		hives = hives + (pollinator_extra.call() as Array)
	for h: Dictionary in hives:
		if not bool(h.get("active", true)):
			continue
		var hr: Rect2i = Rect2i(h.cell, h.get("size", Vector2i.ONE))
		if Grid.within(hr, rect_of(c), BEE_RADIUS):
			best = maxf(best, BEE_FLOWER if is_flower(c) else BEE_BASE)
	return best

func _count_mature_near(c: Dictionary, kind: String, n: int) -> int:
	var k: int = 0
	for o: Dictionary in crops:
		if o.id != c.id and o.kind == kind and o.mature and _near(c, o, n):
			k += 1
	return k

func edamame_k(c: Dictionary) -> int:
	if c.kind == "edamame":
		return 0
	var a: Dictionary = def_of("edamame").get("growth_aura", {})
	return mini(_count_mature_near(c, "edamame", int(a.get("radius", 1))), int(a.get("max_count", 5)))

func _any_shade(c: Dictionary) -> bool:
	for cc: Vector2i in Grid.cells_of(rect_of(c)):
		if is_shaded(cc):
			return true
	return false

## 日陰か。ホストの静的な shade 属性と、ヒノキの動的な日陰(成熟後、占有の北側)の論理和。常時判定。
func is_shaded(cell: Vector2i) -> bool:
	return host.is_shade(cell) or dynamic_shade_has(cell)

func _shade_rect_of(o: Dictionary) -> Rect2i:
	var depth: int = int(_param(o.kind, "shade_depth", 2.0))
	var width: int = int(_param(o.kind, "shade_width", 3.0))
	var r: Rect2i = rect_of(o)
	var x0: int = r.position.x + int(floor(float(r.size.x - width) * 0.5))
	return Rect2i(x0, r.position.y - depth, width, depth)

func dynamic_shade_has(cell: Vector2i) -> bool:
	for o: Dictionary in crops:
		if o.mature and bool(def_of(o.kind).get("dynamic_shade", false)) and _shade_rect_of(o).has_point(cell):
			return true
	return false

## 動的な日陰のマス一覧(重複なし、並びは安定)
func dynamic_shade_cells() -> Array[Vector2i]:
	var seen: Dictionary = {}
	var out: Array[Vector2i] = []
	for o: Dictionary in crops:
		if o.mature and bool(def_of(o.kind).get("dynamic_shade", false)):
			for cc: Vector2i in Grid.cells_of(_shade_rect_of(o)):
				if not seen.has(cc):
					seen[cc] = true
					out.append(cc)
	return out

## 成長の進む速さ(1秒の経過あたり、成熟秒Tに対する進捗秒)
func growth_rate_of(c: Dictionary) -> float:
	var r: float = float(host.growth_multiplier(c))
	var a: Dictionary = def_of("edamame").get("growth_aura", {})
	r *= 1.0 + float(a.get("step", 0.05)) * float(edamame_k(c))
	if c.kind == "dokudami" and _any_shade(c):
		r *= _param("dokudami", "shade_growth", 1.5)
	return r

func growth_rate(id: int) -> float:
	return growth_rate_of(_by_id[id]) if _by_id.has(id) else 0.0

func _same_kind_cells(kind: String) -> Dictionary:
	var cells: Dictionary = {}
	for o: Dictionary in crops:
		if o.kind == kind:
			for cc: Vector2i in Grid.cells_of(rect_of(o)):
				cells[cc] = true
	return cells

## 自分の条件による倍率(配置・時刻・自分の経過だけで決まる)
func condition_multiplier(c: Dictionary) -> float:
	var m: float = _condition_core(c)
	# クズの根に隣接する他種の栽培植物は基礎生産×0.8(重複しない)
	if c.kind != "kudzu" and _kudzu_root_adjacent(c):
		m *= _param("kudzu", "neighbor_mult", 0.8)
	return m

func _condition_core(c: Dictionary) -> float:
	var kind: String = c.kind
	match kind:
		"evening_primrose":
			return _param(kind, "day_mult", 0.3) if host.is_day() else _param(kind, "night_mult", 1.5)
		"mimosa":
			return 0.0 if bool(c.ext.closed) else 1.0
		"kudzu":
			return 1.0 + _param(kind, "per_root", 0.15) * float((c.ext.roots as Array).size())
		"sunflower":
			return _param(kind, "day_mult", 1.5) if host.is_day() else _param(kind, "night_mult", 0.3)
		"tomato":
			return _param(kind, "wall_mult", 1.75) if bool(c.wall_adj) else 1.0
		"grape":
			var l: int = mini(Grid.line_length(_same_kind_cells(kind), c.cell), int(_param(kind, "max_len", 8)))
			return 1.0 + _param(kind, "step", 0.15) * float(maxi(l - 1, 0))
		"rice":
			var a: int = mini(Grid.max_rect_area(_same_kind_cells(kind), c.cell, int(_param(kind, "max_area", 25))), int(_param(kind, "max_area", 25)))
			return 1.0 + _param(kind, "step", 0.04) * float(maxi(a - 1, 0))
		"corn":
			var radius: int = int(_param(kind, "radius", 1))
			var e: bool = _count_mature_near(c, "edamame", radius) > 0
			var p: bool = _count_mature_near(c, "pumpkin", radius) > 0
			if e and p:
				return _param(kind, "both_mult", 1.8)
			if e or p:
				return _param(kind, "one_mult", 1.3)
			return 1.0
		"tea":
			var steps: float = floorf(float(c.since_mature) / _param(kind, "period", 60.0))
			return 1.0 + minf(_param(kind, "max_bonus", 1.0), steps * _param(kind, "step", 0.02))
		"sakura":
			return _param(kind, "bloom_mult", 4.0) if is_bloom(c) else 1.0
		"dokudami":
			return _param(kind, "shade_prod", 2.0) if _any_shade(c) else 1.0
		"flytrap":
			return _param(kind, "digest_mult", 3.0) if float(c.digest_until) > time else 1.0
	return 1.0

## 生産量の内訳(種/秒)。未成熟は全て0。
func production_info(id: int) -> Dictionary:
	if not _by_id.has(id):
		return {}
	var c: Dictionary = _by_id[id]
	var d: Dictionary = def_of(c.kind)
	var info: Dictionary = {"defined": float(d.rate_per_min) / 60.0, "variant_mult": float(d.get("variant_mult", 1.0)),
		"condition": 1.0, "base": 0.0, "gold_k": 0, "gold_bonus": 0.0, "bee_bonus": 0.0, "rate": 0.0}
	if not c.mature:
		return info
	info.condition = condition_multiplier(c)
	info.base = float(info.defined) * float(info.variant_mult) * float(info.condition)
	info.gold_k = gold_k(c)
	info.gold_bonus = GOLD_STEP * float(info.gold_k)
	info.bee_bonus = bee_bonus(c)
	info.rate = float(info.base) * (1.0 + float(info.gold_bonus) + float(info.bee_bonus))
	return info

# ---------------------------------------------------------------- 時間経過
func advance(dt: float) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	if dt <= 0.0:
		return ev
	var left: float = dt
	while left > 1e-9:
		var s: float = minf(left, STEP_MAX)
		_step(s, ev)
		left -= s
	return ev

func _step(dt: float, ev: Array[Dictionary]) -> void:
	time += dt
	var mature_before: Array = []
	for c: Dictionary in crops:
		if c.mature:
			c.since_mature = float(c.since_mature) + dt
			mature_before.append(c)
		else:
			c.grow = float(c.grow) + dt * growth_rate_of(c)
	for c: Dictionary in crops.duplicate():
		if not c.mature and float(c.grow) >= float(def_of(c.kind).maturity):
			_mature(c, ev, true)
	_mimosa_update(ev)
	for c: Dictionary in mature_before:
		_produce(c, dt, ev)
	while poison_next_at <= time:
		_poison_tick(ev)
		poison_next_at += 5.0
	for c: Dictionary in mature_before:
		if not _by_id.has(c.id):
			continue
		match c.kind:
			"mint":
				if time >= float(c.next_spread_at):
					_mint_spread(c, ev)
			"strawberry":
				if time >= float(c.next_drop_at):
					_strawberry_drop(c)
			"aloe":
				_aloe(c, ev)
			"dandelion":
				if time >= float(c.ext.next_fluff_at):
					_dandelion_fluff(c, ev)
			"kudzu":
				if time >= float(c.ext.next_grow_at):
					_kudzu_grow(c, ev)
			"loofah":
				if time >= float(c.ext.next_water_at):
					_loofah_tick(c, ev)
			"apple":
				if time >= float(c.ext.next_fruit_at):
					_apple_drop(c, ev)
			"balsam":
				_balsam_tick(c, ev)
	_collect_pickups(ev)

func _produce(c: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	if not _by_id.has(c.id):
		return
	var rate: float = float(production_info(c.id).rate)
	var amount: float = rate * dt
	if amount <= 0.0:
		return
	if c.kind == "potato":
		var cap: float = float(c.paid) * _param("potato", "cap_mult", 10.0)
		c.storage = minf(cap, float(c.storage) + amount)
		return
	produced[c.kind] = float(produced.get(c.kind, 0.0)) + amount
	if bool(c.gnawed):
		ev.append({"type": "seeds_stolen", "crop_id": c.id, "kind": c.kind, "amount": amount})
	else:
		ev.append({"type": "seeds", "crop_id": c.id, "kind": c.kind, "amount": amount})

func _mature(c: Dictionary, ev: Array[Dictionary], roll: bool) -> void:
	c.mature = true
	c.grow = maxf(float(c.grow), float(def_of(c.kind).maturity))
	c.since_mature = 0.0
	c.next_spread_at = time + _param("mint", "interval", 30.0)
	c.next_drop_at = time + _param("strawberry", "interval", 20.0)
	c.ready_at = time
	match c.kind:
		"dandelion":
			c.ext.next_fluff_at = time + _param("dandelion", "interval", 40.0)
		"kudzu":
			c.ext.next_grow_at = time + _param("kudzu", "interval", 15.0)
		"loofah":
			c.ext.next_water_at = time + _param("loofah", "interval", 10.0)
		"apple":
			c.ext.next_fruit_at = time + _param("apple", "interval", 30.0)
		"balsam":
			c.ext.next_pop_at = time + _param("balsam", "interval", 20.0)
			c.ext.trigger_ok_at = time
	ev.append({"type": "crop_matured", "crop_id": c.id, "kind": c.kind})
	if roll:
		_roll_variant(c, ev, -1, false)

## forced: -1=乱数, 0=外れ, 1=当たり。抽選は一度だけ(variant_rolled)。
func _roll_variant(c: Dictionary, ev: Array[Dictionary], forced: int, debug: bool) -> void:
	var v: Dictionary = def_of(c.kind).get("variant", {})
	if v.is_empty() or bool(c.variant_rolled):
		return
	c.variant_rolled = true
	var hit: bool = false
	if forced >= 0:
		hit = forced == 1
	else:
		hit = rng.randf() < 1.0 / float(v.denominator)
	ev.append({"type": "variant_roll", "crop_id": c.id, "kind": c.kind, "hit": hit, "debug": debug})
	if hit:
		var from_kind: String = c.kind
		c.kind = str(v.to)
		c.hp = minf(float(c.hp), float(def_of(c.kind).hp))
		ev.append({"type": "variant", "crop_id": c.id, "from": from_kind, "to": c.kind, "debug": debug})

# ---------------------------------------------------------------- 毒
func _is_garlic_covered(c: Dictionary) -> bool:
	for o: Dictionary in crops:
		if not o.mature or not def_of(o.kind).has("garlic_aura"):
			continue
		if _near(c, o, int(def_of(o.kind).garlic_aura.radius)):
			return true
	return false

func _poison_tick(ev: Array[Dictionary]) -> void:
	var sources: Array = []
	for o: Dictionary in crops:
		if o.mature and bool(def_of(o.kind).get("poison_source", false)):
			sources.append(o)
	var dead: Array = []
	for c: Dictionary in crops:
		if bool(def_of(c.kind).get("poison_source", false)):
			continue
		var exposed: bool = false
		for s: Dictionary in sources:
			if _near(c, s, int(_param("oleander", "radius", 3.0))):
				exposed = true
				break
		if exposed and _is_garlic_covered(c):
			exposed = false
		if exposed:
			c.poison = int(c.poison) + 1
			ev.append({"type": "poison_tick", "crop_id": c.id, "poison": c.poison})
			if int(c.poison) >= int(_param("oleander", "limit", 3.0)):
				dead.append(c.id)
		else:
			c.poison = 0
	for id: int in dead:
		ev.append_array(remove_crop(id, "poison").events)

# ---------------------------------------------------------------- ミント・イチゴ・アロエ
func _colony_count(colony_id: int) -> int:
	var n: int = 0
	for c: Dictionary in crops:
		if c.kind == "mint" and int(c.colony_id) == colony_id:
			n += 1
	return n

func _mint_spread(c: Dictionary, ev: Array[Dictionary]) -> void:
	c.next_spread_at = time + _param("mint", "interval", 30.0)
	if _colony_count(int(c.colony_id)) >= int(_param("mint", "colony_max", 9.0)):
		return
	var options: Array[Vector2i] = []
	for cell: Vector2i in Grid.adjacent_cells(rect_of(c)):
		if bool(check_placement("mint", cell).ok):
			options.append(cell)
	if options.is_empty():
		return
	var pick: Vector2i = options[rng.randi_range(0, options.size() - 1)]
	var r: Dictionary = spawn_crop("mint", pick, 0, {"colony_id": int(c.colony_id)})
	if bool(r.ok):
		ev.append_array(r.events)
		ev.append({"type": "mint_spread", "from": c.id, "crop_id": r.id, "cell": pick})

func _strawberry_drop(c: Dictionary) -> void:
	c.next_drop_at = time + _param("strawberry", "interval", 20.0)
	var n: int = 0
	for p: Dictionary in pickups:
		if int(p.source_id) == int(c.id):
			n += 1
	if n >= int(_param("strawberry", "max_pickups", 3.0)):
		return
	var options: Array[Vector2i] = []
	for cell: Vector2i in Grid.adjacent_cells(rect_of(c)):
		if not host.in_bounds(cell) or not host.is_walkable(cell) or host.is_blocked(cell) or _occ.has(cell):
			continue
		var taken: bool = false
		for p: Dictionary in pickups:
			if Grid.cell_of_pos(p.pos) == cell:
				taken = true
		if not taken:
			options.append(cell)
	if options.is_empty():
		return
	var pick: Vector2i = options[rng.randi_range(0, options.size() - 1)]
	add_pickup(Grid.center_of_cell(pick), int(_param("strawberry", "amount", 6.0)), int(c.id), "strawberry")

## 地面の拾い物(イチゴ、ウサギが落とす種など)
func add_pickup(pos: Vector2, amount: int, source_id: int = 0, kind: String = "seeds") -> int:
	var id: int = next_pickup_id
	next_pickup_id += 1
	pickups.append({"id": id, "pos": pos, "amount": amount, "source_id": source_id, "kind": kind})
	return id

func _collect_pickups(ev: Array[Dictionary]) -> void:
	var hero: Dictionary = host.hero()
	if hero.is_empty():
		return
	for p: Dictionary in pickups.duplicate():
		if Vector2(hero.pos).distance_to(p.pos) <= PICKUP_RADIUS_PX:
			pickups.erase(p)
			ev.append({"type": "pickup_collected", "pickup_id": p.id, "amount": p.amount, "kind": p.kind})

func _aloe(c: Dictionary, ev: Array[Dictionary]) -> void:
	if time < float(c.ready_at):
		return
	var cands: Array = []
	var hero: Dictionary = host.hero()
	if not hero.is_empty():
		cands.append({"target": "hero", "id": 0, "pos": hero.pos, "hp": hero.hp, "max_hp": hero.max_hp})
	for h: Dictionary in host.helpers():
		cands.append({"target": "helper", "id": h.id, "pos": h.pos, "hp": h.hp, "max_hp": h.max_hp})
	var best: Dictionary = {}
	var best_ratio: float = 2.0
	for t: Dictionary in cands:
		var cell: Vector2i = Grid.cell_of_pos(t.pos)
		if not Grid.within(rect_of(c), Rect2i(cell, Vector2i.ONE), int(_param("aloe", "radius", 4.0))):
			continue
		var ratio: float = float(t.hp) / maxf(float(t.max_hp), 0.001)
		if ratio < _param("aloe", "threshold", 0.5) and ratio < best_ratio:
			best_ratio = ratio
			best = t
	if best.is_empty():
		return
	c.ready_at = time + _param("aloe", "cooldown", 60.0)
	ev.append({"type": "heal", "crop_id": c.id, "target": best.target, "target_id": best.id, "amount": _param("aloe", "heal", 30.0)})

# ---------------------------------------------------------------- 第2弾: 植物8種
func _threats() -> Array:
	var out: Array = []
	if enemy_feed.is_valid():
		out.append_array(enemy_feed.call() as Array)
	out.append_array(host.host_enemies())
	return out

func _enemy_near(c: Dictionary, radius_px: float) -> bool:
	var r: Rect2 = Rect2(Vector2(c.cell) * Grid.CELL_PX, Vector2(c.size) * Grid.CELL_PX)
	for t: Dictionary in _threats():
		if bool(t.get("neutral", false)):
			continue
		var p: Vector2 = t.pos
		var q: Vector2 = Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		if p.distance_to(q) <= radius_px:
			return true
	return false

## 新たに播種できる有効マスか(タンポポ・ホウセンカ)。ホストの判定に加え、植物・クズの根・敵側の占有を除く。
func is_seed_target(cell: Vector2i) -> bool:
	if not host.in_bounds(cell) or not host.is_explored(cell):
		return false
	if _occ.has(cell) or _root_occ.has(cell):
		return false
	if occupy_check.is_valid() and str(occupy_check.call(cell)) != "":
		return false
	return host.is_seedable_cell(cell)

func _cells_by_order(cells: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for v: Variant in cells:
		out.append(v)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out

func _dandelion_fluff(c: Dictionary, ev: Array[Dictionary]) -> void:
	c.ext.next_fluff_at = time + _param("dandelion", "interval", 40.0)
	var lo: int = int(_param("dandelion", "min_range", 3.0))
	var hi: int = int(_param("dandelion", "max_range", 6.0))
	var rect: Rect2i = rect_of(c)
	var raw: Array = []
	for cc: Vector2i in Grid.cells_of(Grid.expanded(rect, hi)):
		var d: int = Grid.rect_distance(rect, Rect2i(cc, Vector2i.ONE))
		if d >= lo and d <= hi and is_seed_target(cc):
			raw.append(cc)
	if raw.is_empty():
		return   # 候補がなければ飛ばさない(乱数も使わない)
	var options: Array[Vector2i] = _cells_by_order(raw)
	var pick: Vector2i = options[rng.randi_range(0, options.size() - 1)]
	ev.append({"type": "seed_sow", "cell": pick, "source": "dandelion", "crop_id": c.id, "consume_stock": false})

func _mimosa_close(c: Dictionary, ev: Array[Dictionary]) -> void:
	var was: bool = bool(c.ext.closed)
	c.ext.closed = true
	c.ext.open_at = time + _param("mimosa", "reopen_s", 4.0)
	if not was:
		ev.append({"type": "mimosa_closed", "crop_id": c.id})

func _mimosa_update(ev: Array[Dictionary]) -> void:
	for c: Dictionary in crops:
		if c.kind != "mimosa":
			continue
		if _enemy_near(c, _param("mimosa", "radius_m", 2.0) * PX_PER_M):
			_mimosa_close(c, ev)
		elif bool(c.ext.closed) and time >= float(c.ext.open_at):
			c.ext.closed = false
			ev.append({"type": "mimosa_opened", "crop_id": c.id})

# ---- クズ
func _kudzu_grow(c: Dictionary, ev: Array[Dictionary]) -> void:
	c.ext.next_grow_at = time + _param("kudzu", "interval", 15.0)
	var roots: Array = c.ext.roots
	if roots.size() >= int(_param("kudzu", "max_roots", 24.0)):
		return
	var reach: int = int(_param("kudzu", "reach", 4.0))
	var stock: Rect2i = rect_of(c)
	var seen: Dictionary = {}
	var raw: Array = []
	var bases: Array = Grid.adjacent_cells(stock)
	for rc: Vector2i in roots:
		bases.append_array(Grid.adjacent_cells(Rect2i(rc, Vector2i.ONE)))
	for cc: Vector2i in bases:
		if seen.has(cc):
			continue
		seen[cc] = true
		if roots.has(cc) or Grid.rect_distance(stock, Rect2i(cc, Vector2i.ONE)) > reach:
			continue
		if bool(check_placement("kudzu", cc).ok):
			raw.append(cc)
	if raw.is_empty():
		return
	var options: Array[Vector2i] = _cells_by_order(raw)
	var pick: Vector2i = options[rng.randi_range(0, options.size() - 1)]
	roots.append(pick)
	_root_occ[pick] = c.id
	ev.append({"type": "kudzu_root_added", "crop_id": c.id, "cell": pick})

## 根のマス一覧。id=0 なら全部。
func root_cells(id: int = 0) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for o: Dictionary in crops:
		if o.kind == "kudzu" and (id == 0 or o.id == id):
			for rc: Vector2i in o.ext.roots:
				out.append(rc)
	return out

## そのマスの根を持つクズの株ID(なければ0)。歩行は妨げない。
func root_owner(cell: Vector2i) -> int:
	return int(_root_occ.get(cell, 0))

## 敵の移動速度の倍率(根のマスは×0.6)。敵側の移動処理が参照する。
func enemy_speed_mult(cell: Vector2i) -> float:
	return _param("kudzu", "enemy_speed_mult", 0.6) if _root_occ.has(cell) else 1.0

func _kudzu_root_adjacent(c: Dictionary) -> bool:
	if _root_occ.is_empty():
		return false
	for ac: Vector2i in Grid.adjacent_cells(rect_of(c)):
		if _root_occ.has(ac):
			return true
	return false

## 根を1マス撤去する。reason: manual(返還0) / eaten(ネッコモグラ) など
func remove_root(cell: Vector2i, reason: String = "manual") -> Dictionary:
	if not _root_occ.has(cell):
		return {"ok": false, "reason": "no_root", "refund": 0, "events": []}
	var id: int = int(_root_occ[cell])
	var c: Dictionary = _by_id[id]
	(c.ext.roots as Array).erase(cell)
	_root_occ.erase(cell)
	return {"ok": true, "reason": "", "refund": 0, "events": [{"type": "kudzu_root_removed", "crop_id": id, "cell": cell, "reason": reason}]}

## 根のマスを食べる(モグラ用の入力)。
func eat_root(cell: Vector2i) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	ev.append_array(remove_root(cell, "eaten").events)
	return ev

# ---- ヘチマ
func loofah_water(id: int) -> int:
	return int(_by_id[id].ext.water) if _by_id.has(id) and _by_id[id].kind == "loofah" else 0

func _loofah_tick(c: Dictionary, ev: Array[Dictionary]) -> void:
	c.ext.next_water_at = time + _param("loofah", "interval", 10.0)
	if int(c.ext.water) <= 0:
		return
	var rect: Rect2i = rect_of(c)
	var n: int = int(_param("loofah", "radius", 3.0))
	var best: Dictionary = {}
	var bd: int = 1 << 20
	for o: Dictionary in crops:
		if o.id == c.id or bool(o.watered) or not Grid.within(rect, rect_of(o), n):
			continue
		var d: int = Grid.rect_distance(rect, rect_of(o))
		if d < bd or (d == bd and o.id < best.id):
			best = o
			bd = d
	if not best.is_empty():
		c.ext.water = int(c.ext.water) - 1
		set_watered(int(best.id), true)   # 給水済みとして扱う(ホストは水を適用する)
		ev.append({"type": "water_crop", "crop_id": best.id, "source": "loofah", "source_id": c.id, "water_left": c.ext.water})
		return
	var raw: Array = []
	for cc: Vector2i in Grid.cells_of(Grid.expanded(rect, n)):
		if host.in_bounds(cc) and not _occ.has(cc) and not _root_occ.has(cc) and not host.is_cell_watered(cc):
			var st: String = host.grass_stage(cc)
			if st == "seed" or st == "sprout":
				raw.append(cc)
	if raw.is_empty():
		return
	var cells: Array[Vector2i] = _cells_by_order(raw)
	var pick: Vector2i = cells[0]
	var pd: int = Grid.rect_distance(rect, Rect2i(pick, Vector2i.ONE))
	for cc2: Vector2i in cells:
		var d2: int = Grid.rect_distance(rect, Rect2i(cc2, Vector2i.ONE))
		if d2 < pd:
			pd = d2
			pick = cc2
	c.ext.water = int(c.ext.water) - 1
	ev.append({"type": "water_cell", "cell": pick, "source": "loofah", "source_id": c.id, "water_left": c.ext.water})

## 水(主人公の水やり・スプリンクラー)が着弾したマス。貯水が足りないヘチマは10に戻る。
func on_water_cells(cells: Array) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	var cap: int = int(_param("loofah", "capacity", 10.0))
	for o: Dictionary in crops:
		if o.kind != "loofah" or int(o.ext.water) >= cap:
			continue
		for v: Variant in cells:
			if rect_of(o).has_point(v):
				o.ext.water = cap
				ev.append({"type": "loofah_refill", "crop_id": o.id, "water": cap})
				break
	return ev

## 給水の優先対象(スプリンクラー用)。未給水の栽培植物と、貯水が空のヘチマ。
func needs_water(id: int) -> bool:
	if not _by_id.has(id):
		return false
	var c: Dictionary = _by_id[id]
	return not bool(c.watered) or (c.kind == "loofah" and int(c.ext.water) <= 0)

func sprinkler_targets() -> Array[int]:
	var out: Array[int] = []
	for c: Dictionary in crops:
		if needs_water(int(c.id)):
			out.append(int(c.id))
	return out

# ---- リンゴ
func _fruit_at(cell: Vector2i) -> bool:
	for f: Dictionary in fruits:
		if f.cell == cell:
			return true
	return false

func _apple_drop(c: Dictionary, ev: Array[Dictionary]) -> void:
	c.ext.next_fruit_at = time + _param("apple", "interval", 30.0)
	var n: int = 0
	for f: Dictionary in fruits:
		if int(f.source_id) == int(c.id):
			n += 1
	if n >= int(_param("apple", "max_fruits", 3.0)):
		return
	var raw: Array = []
	for cell: Vector2i in Grid.adjacent_cells(rect_of(c)):
		if not host.in_bounds(cell) or not host.is_walkable(cell) or host.is_blocked(cell):
			continue
		if _occ.has(cell) or _root_occ.has(cell) or _fruit_at(cell):
			continue
		if occupy_check.is_valid() and str(occupy_check.call(cell)) != "":
			continue
		raw.append(cell)
	if raw.is_empty():
		return
	var options: Array[Vector2i] = _cells_by_order(raw)
	var pick: Vector2i = options[rng.randi_range(0, options.size() - 1)]
	var fid: int = next_fruit_id
	next_fruit_id += 1
	fruits.append({"id": fid, "cell": pick, "source_id": c.id})
	ev.append({"type": "fruit_dropped", "crop_id": c.id, "fruit_id": fid, "cell": pick})

func fruit_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f: Dictionary in fruits:
		var d: Dictionary = f.duplicate()
		d["pos"] = Grid.center_of_cell(f.cell)
		out.append(d)
	return out

## 草食タグの敵が引き寄せられる落果のうち、from_pos から range_px 以内で最も近いもの。安定した地域の落果は対象外。
## 敵のきっかけの範囲・縄張りから10m以内か、という範囲の判断は呼び出し側(range_px で渡す)。なければ空。
func nearest_attracting_fruit(enemy_tags: Array, from_pos: Vector2, range_px: float) -> Dictionary:
	if not enemy_tags.has(Defs.TAG_HERBIVORE):
		return {}
	var best: Dictionary = {}
	var bd: float = INF
	for f: Dictionary in fruits:
		if host.is_stable_cell(f.cell):
			continue
		var p: Vector2 = Grid.center_of_cell(f.cell)
		var d: float = from_pos.distance_to(p)
		if d <= range_px and d < bd:
			bd = d
			best = f.duplicate()
			best["pos"] = p
	return best

## 落果を食べる(消費)。
func consume_fruit(fruit_id: int, by: Variant = null) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	for f: Dictionary in fruits:
		if int(f.id) == fruit_id:
			fruits.erase(f)
			ev.append({"type": "fruit_eaten", "fruit_id": fruit_id, "cell": f.cell, "source_id": f.source_id, "by": by if by != null else 0})
			break
	return ev

# ---- ホウセンカ
func _balsam_tick(c: Dictionary, ev: Array[Dictionary]) -> void:
	var cause: String = ""
	if time >= float(c.ext.next_pop_at):
		cause = "periodic"
	elif time >= float(c.ext.trigger_ok_at) and _enemy_near(c, _param("balsam", "trigger_m", 1.5) * PX_PER_M):
		cause = "enemy"
	if cause == "":
		return
	c.ext.next_pop_at = time + _param("balsam", "interval", 20.0)
	c.ext.trigger_ok_at = time + _param("balsam", "trigger_cd", 8.0)
	var center: Vector2 = (Vector2(c.cell) + Vector2(c.size) * 0.5) * Grid.CELL_PX
	ev.append({"type": "balsam_burst", "crop_id": c.id, "center": center, "radius_px": _param("balsam", "radius_m", 2.0) * PX_PER_M,
		"damage": _param("balsam", "damage", 4.0), "cause": cause})
	var rect: Rect2i = rect_of(c)
	var raw: Array = []
	for cc: Vector2i in Grid.cells_of(Grid.expanded(rect, int(_param("balsam", "seed_radius", 2.0)))):
		if is_seed_target(cc):
			raw.append(cc)
	var options: Array[Vector2i] = _cells_by_order(raw)
	var count: int = mini(int(_param("balsam", "seed_count", 3.0)), options.size())
	for i: int in range(count):
		var k: int = rng.randi_range(0, options.size() - 1)
		ev.append({"type": "seed_sow", "cell": options[k], "source": "balsam", "crop_id": c.id, "consume_stock": false})
		options.remove_at(k)

# ---------------------------------------------------------------- 敵(第2段)が使う口
## 敵が株を狙えるか。tags は敵の分類タグ(例 "beast","bug","small")。
func crop_targetable_by(enemy_tags: Array, crop_id: int) -> bool:
	if not _by_id.has(crop_id):
		return false
	var c: Dictionary = _by_id[crop_id]
	if _is_garlic_covered(c):
		return false
	for o: Dictionary in crops:
		if not o.mature:
			continue
		var r: Dictionary = def_of(o.kind).get("repel", {})
		if not r.is_empty() and enemy_tags.has(str(r.tag)) and _near(c, o, int(r.radius)):
			return false
	return true

## tag を遠ざける範囲。[{"crop_id","rect"(拡張後Rect2i),"radius"}]
func repel_zones(tag: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o: Dictionary in crops:
		if not o.mature:
			continue
		var r: Dictionary = def_of(o.kind).get("repel", {})
		if not r.is_empty() and str(r.tag) == tag:
			out.append({"crop_id": o.id, "rect": Grid.expanded(rect_of(o), int(r.radius)), "radius": int(r.radius)})
	return out

func is_repelled_cell(cell: Vector2i, enemy_tags: Array) -> bool:
	for t: Variant in enemy_tags:
		for z: Dictionary in repel_zones(str(t)):
			if Rect2i(z.rect).has_point(cell):
				return true
	return false

## 成熟したタケがこのマスにあるか(敵は通れない。射撃は遮らない)
func blocks_enemy(cell: Vector2i) -> bool:
	if not _occ.has(cell):
		return false
	var c: Dictionary = _by_id[_occ[cell]]
	return bool(c.mature) and bool(def_of(c.kind).get("blocks_enemy", false))

## 株が受けるダメージ(カボチャ軽減、トウガラシ・サボテン反撃、HP0で返還0の除去)。
## source: {"enemy_id": 任意, "cause": "attack"(既定) / "collateral"}
func damage_crop(id: int, amount: float, source: Dictionary = {}) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	if not _by_id.has(id):
		return ev
	var c: Dictionary = _by_id[id]
	var dmg: float = amount
	for o: Dictionary in crops:
		var g: Dictionary = def_of(o.kind).get("guard_aura", {})
		if o.id != c.id and o.mature and not g.is_empty() and _near(c, o, int(g.radius)):
			dmg = amount * float(g.mult)
			break
	if c.kind == "mimosa":
		if bool(c.ext.closed):
			dmg *= _param("mimosa", "closed_dmg_mult", 0.2)
		_mimosa_close(c, ev)   # 攻撃を受けると閉じる(この一撃は閉じる前の扱い)
	c.hp = float(c.hp) - dmg
	ev.append({"type": "crop_damaged", "crop_id": id, "amount": dmg, "hp": c.hp})
	var enemy_key: String = str(source.get("enemy_id", -1))
	if str(source.get("cause", "attack")) == "attack":
		if c.kind == "pepper" and _cooldown_ok(c, enemy_key, _param("pepper", "cooldown", 5.0)):
			ev.append({"type": "pepper_counter", "crop_id": id, "enemy_id": source.get("enemy_id", -1),
				"damage": _param("pepper", "damage", 2.0), "flee_seconds": _param("pepper", "flee", 3.0)})
		elif c.kind == "cactus" and _cooldown_ok(c, enemy_key, _param("cactus", "cooldown", 1.0)):
			ev.append({"type": "cactus_thorn", "crop_id": id, "enemy_id": source.get("enemy_id", -1), "damage": _param("cactus", "thorn", 3.0)})
	if float(c.hp) <= 0.0:
		ev.append_array(remove_crop(id, "enemy").events)
	return ev

func _cooldown_ok(c: Dictionary, key: String, cooldown: float) -> bool:
	var hl: Dictionary = c.hit_log
	if hl.has(key) and time - float(hl[key]) < cooldown:
		return false
	hl[key] = time
	return true

## 敵がマスへ入ったとき呼ぶ。サボテンに隣接していればトゲのイベントを返す。
func enemy_moved(enemy_id: Variant, cell: Vector2i) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	for c: Dictionary in crops:
		if c.kind != "cactus":
			continue
		if Grid.adjacent_cells(rect_of(c)).has(cell) and _cooldown_ok(c, str(enemy_id), _param("cactus", "cooldown", 1.0)):
			ev.append({"type": "cactus_thorn", "crop_id": c.id, "enemy_id": enemy_id, "damage": _param("cactus", "thorn", 3.0)})
	return ev

## ハエトリソウの捕獲判定。小型タグで、占有マスか隣接マスにいて、消化中でなければ捕まえる。
func flytrap_capture(enemy_id: Variant, enemy_cell: Vector2i, enemy_tags: Array) -> Dictionary:
	if not enemy_tags.has("small"):
		return {"captured": false, "events": []}
	for c: Dictionary in crops:
		if c.kind != "flytrap" or not c.mature or float(c.digest_until) > time:
			continue
		var rect: Rect2i = rect_of(c)
		if rect.has_point(enemy_cell) or Grid.adjacent_cells(rect).has(enemy_cell):
			c.digest_until = time + _param("flytrap", "digest", 20.0)
			var dmg: float = _param("flytrap", "damage", 30.0)
			return {"captured": true, "crop_id": c.id, "damage": dmg,
				"events": [{"type": "flytrap_capture", "crop_id": c.id, "enemy_id": enemy_id, "damage": dmg}]}
	return {"captured": false, "events": []}

## ニンニクの範囲(成熟した株から周辺Nタイル)にあるマスか。スカンクの臭気が出ない範囲の判定に使う。
func garlic_covers_cell(cell: Vector2i) -> bool:
	for o: Dictionary in crops:
		if o.mature and def_of(o.kind).has("garlic_aura"):
			if Grid.within(rect_of(o), Rect2i(cell, Vector2i.ONE), int(def_of(o.kind).garlic_aura.radius)):
				return true
	return false

## ヒカリゴケの範囲(成熟した株から周辺Nタイル)にあるマスか。昼夜を問わない(コウモリの急降下の抑止に使う)。
func moss_covers_cell(cell: Vector2i) -> bool:
	for c: Dictionary in crops:
		if c.kind == "glow_moss" and c.mature and Grid.within(rect_of(c), Rect2i(cell, Vector2i.ONE), int(_param("glow_moss", "radius", 5.0))):
			return true
	return false

## 夜、成熟したヒカリゴケの範囲内なら擬態を見破る
func glow_moss_reveals(cell: Vector2i) -> bool:
	if host.is_day():
		return false
	for c: Dictionary in crops:
		if c.kind == "glow_moss" and c.mature and Grid.within(rect_of(c), Rect2i(cell, Vector2i.ONE), int(_param("glow_moss", "radius", 5.0))):
			return true
	return false

## 成熟した株(敵が狙う候補)。複製を返す。
func mature_crops() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Dictionary in crops:
		if c.mature:
			out.append(c.duplicate(true))
	return out

# ---------------------------------------------------------------- デバッグ(通常の抽選とは別扱い)
func debug_force_mature(id: int, roll: bool = false) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	if _by_id.has(id) and not _by_id[id].mature:
		_mature(_by_id[id], ev, roll)
	return ev

## 強制抽選。成否を指定する。変種の定義がある株で、まだ抽選していなければ有効。
func debug_force_roll(id: int, hit: bool) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	if _by_id.has(id):
		_roll_variant(_by_id[id], ev, 1 if hit else 0, true)
	return ev

# ---------------------------------------------------------------- 保存・復元
func to_dict() -> Dictionary:
	var arr: Array = []
	for c: Dictionary in crops:
		var cd: Dictionary = c.duplicate(true)
		cd.cell = [c.cell.x, c.cell.y]
		cd.size = [c.size.x, c.size.y]
		if c.kind == "kudzu":
			var rl: Array = []
			for rc: Vector2i in c.ext.roots:
				rl.append([rc.x, rc.y])
			cd.ext.roots = rl
		arr.append(cd)
	var pk: Array = []
	for p: Dictionary in pickups:
		var pd: Dictionary = p.duplicate(true)
		pd.pos = [p.pos.x, p.pos.y]
		pk.append(pd)
	var fr: Array = []
	for f: Dictionary in fruits:
		fr.append({"id": f.id, "cell": [f.cell.x, f.cell.y], "source_id": f.source_id})
	return {"time": time, "next_id": next_id, "poison_next_at": poison_next_at, "next_pickup_id": next_pickup_id,
		"produced": produced.duplicate(), "crops": arr, "pickups": pk, "fruits": fr, "next_fruit_id": next_fruit_id}

func _isnum(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

func _vec(v: Variant) -> Variant:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 2 or not _isnum(v[0]) or not _isnum(v[1]):
		return null
	return Vector2i(int(v[0]), int(v[1]))

## ext の値の型が見本と合うか(数値はint/float同一視、bool・Arrayは同じ型)
func _ext_type_ok(v: Variant, tmpl: Variant) -> bool:
	if _isnum(tmpl):
		return _isnum(v)
	return typeof(v) == typeof(tmpl)

func _fail(msg: String) -> bool:
	last_error = msg
	return false

## 検証してから採用する。失敗時は状態を変えない。
func from_dict(d: Dictionary) -> bool:
	last_error = ""
	for k: String in ["time", "next_id", "poison_next_at", "next_pickup_id", "next_fruit_id"]:
		if not d.has(k) or not _isnum(d[k]):
			return _fail("missing " + k)
	if typeof(d.get("crops")) != TYPE_ARRAY or typeof(d.get("pickups")) != TYPE_ARRAY or typeof(d.get("fruits")) != TYPE_ARRAY or typeof(d.get("produced")) != TYPE_DICTIONARY:
		return _fail("bad containers")
	var new_crops: Array = []
	var new_occ: Dictionary = {}
	var new_by: Dictionary = {}
	for raw: Variant in d.crops:
		if typeof(raw) != TYPE_DICTIONARY:
			return _fail("crop not dict")
		var r: Dictionary = raw
		if not r.has("kind") or not defs.has(str(r.kind)):
			return _fail("unknown kind")
		var cell: Variant = _vec(r.get("cell"))
		if cell == null:
			return _fail("bad cell")
		for k: String in ["id", "paid", "grow", "since_mature", "hp", "poison", "colony_id", "next_spread_at", "next_drop_at", "storage", "digest_until", "ready_at"]:
			if not r.has(k) or not _isnum(r[k]):
				return _fail("bad crop field " + k)
		for k: String in ["mature", "watered", "variant_rolled", "wall_adj", "gnawed"]:
			if typeof(r.get(k)) != TYPE_BOOL:
				return _fail("bad crop bool " + k)
		if typeof(r.get("hit_log")) != TYPE_DICTIONARY:
			return _fail("bad hit_log")
		var kind: String = str(r.kind)
		# 種類テンプレート照合: その種類の見本の全キーがあり、型が合うこと(第2弾の種類固有の状態)
		if typeof(r.get("ext")) != TYPE_DICTIONARY:
			return _fail("bad ext")
		var tmpl: Dictionary = _new_ext(kind)
		var ext_in: Dictionary = r.ext
		var new_ext: Dictionary = {}
		for tk: Variant in tmpl:
			if not ext_in.has(tk) or not _ext_type_ok(ext_in[tk], tmpl[tk]):
				return _fail("ext mismatch " + kind + "." + str(tk))
			new_ext[tk] = ext_in[tk]
		for tk: Variant in new_ext.keys():
			var tv: Variant = tmpl[tk]
			if typeof(tv) == TYPE_BOOL:
				pass
			elif typeof(tv) == TYPE_ARRAY:
				pass   # 根の一覧は下で検証
			elif kind == "loofah" and tk == "water":
				new_ext[tk] = int(new_ext[tk])
			else:
				new_ext[tk] = float(new_ext[tk])
		if kind == "loofah" and (int(new_ext.water) < 0 or int(new_ext.water) > int(_param("loofah", "capacity", 10.0))):
			return _fail("loofah water range")
		var c: Dictionary = {"id": int(r.id), "kind": kind, "cell": cell, "size": size_of(kind), "paid": int(r.paid),
			"grow": float(r.grow), "mature": r.mature, "since_mature": float(r.since_mature), "watered": r.watered,
			"hp": float(r.hp), "variant_rolled": r.variant_rolled, "poison": int(r.poison), "colony_id": int(r.colony_id),
			"next_spread_at": float(r.next_spread_at), "next_drop_at": float(r.next_drop_at), "storage": float(r.storage),
			"digest_until": float(r.digest_until), "ready_at": float(r.ready_at), "wall_adj": r.wall_adj,
			"gnawed": r.gnawed, "hit_log": (r.hit_log as Dictionary).duplicate(), "ext": new_ext}
		if new_by.has(c.id):
			return _fail("duplicate id")
		for cc: Vector2i in Grid.cells_of(Rect2i(c.cell, c.size)):
			if new_occ.has(cc):
				return _fail("overlap")
			new_occ[cc] = c.id
		new_crops.append(c)
		new_by[c.id] = c
	# クズの根の検証(個数・距離・重なり)
	var new_root: Dictionary = {}
	for c2: Dictionary in new_crops:
		if c2.kind != "kudzu":
			continue
		var in_roots: Variant = c2.ext.roots
		if typeof(in_roots) != TYPE_ARRAY or (in_roots as Array).size() > int(_param("kudzu", "max_roots", 24.0)):
			return _fail("kudzu roots")
		var conv: Array = []
		for rv: Variant in in_roots:
			var rcell: Variant = _vec(rv)
			if rcell == null:
				return _fail("bad root cell")
			var rc2: Vector2i = rcell
			if new_occ.has(rc2) or new_root.has(rc2):
				return _fail("root overlap")
			if Grid.rect_distance(Rect2i(c2.cell, c2.size), Rect2i(rc2, Vector2i.ONE)) > int(_param("kudzu", "reach", 4.0)):
				return _fail("root too far")
			new_root[rc2] = c2.id
			conv.append(rc2)
		c2.ext.roots = conv
	var new_fruits: Array = []
	var fruit_ids: Dictionary = {}
	for raw: Variant in d.fruits:
		if typeof(raw) != TYPE_DICTIONARY:
			return _fail("fruit not dict")
		var fr: Dictionary = raw
		var fcell: Variant = _vec(fr.get("cell"))
		if fcell == null or not fr.has("id") or not _isnum(fr.id) or not fr.has("source_id") or not _isnum(fr.source_id):
			return _fail("bad fruit")
		if fruit_ids.has(int(fr.id)):
			return _fail("duplicate fruit id")
		fruit_ids[int(fr.id)] = true
		new_fruits.append({"id": int(fr.id), "cell": fcell, "source_id": int(fr.source_id)})
	var new_pick: Array = []
	for raw: Variant in d.pickups:
		if typeof(raw) != TYPE_DICTIONARY:
			return _fail("pickup not dict")
		var p: Dictionary = raw
		var pos: Variant = _vec(p.get("pos"))
		if pos == null:
			# 拾い物の位置は小数のため、Vector2iではなく配列で直接読む
			if typeof(p.get("pos")) != TYPE_ARRAY or (p.pos as Array).size() != 2 or not _isnum(p.pos[0]) or not _isnum(p.pos[1]):
				return _fail("bad pickup pos")
		for k: String in ["id", "amount", "source_id"]:
			if not p.has(k) or not _isnum(p[k]):
				return _fail("bad pickup field " + k)
		new_pick.append({"id": int(p.id), "pos": Vector2(float(p.pos[0]), float(p.pos[1])), "amount": int(p.amount),
			"source_id": int(p.source_id), "kind": str(p.get("kind", "seeds"))})
	var new_prod: Dictionary = {}
	for k: Variant in d.produced:
		if not _isnum(d.produced[k]):
			return _fail("bad produced")
		new_prod[str(k)] = float(d.produced[k])
	time = float(d.time)
	next_id = int(d.next_id)
	poison_next_at = float(d.poison_next_at)
	next_pickup_id = int(d.next_pickup_id)
	crops = new_crops
	_occ = new_occ
	_by_id = new_by
	pickups = new_pick
	produced = new_prod
	_root_occ = new_root
	fruits = new_fruits
	next_fruit_id = int(d.next_fruit_id)
	return true
