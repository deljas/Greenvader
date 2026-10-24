extends RefCounted
## 敵の共通処理。種類ごとの行動は enemies/<種類>.gd(静的関数)に置き、ここから呼ぶ。
## 位置は論理px(1マス=4px、1m=10px)。時間は advance(dt) で進めた分だけ。出力はイベント(Array[Dictionary]、"type"キー)。
##
## 出力イベント一覧:
##   hero_damage{amount,source,kind} / helper_damage{helper_id,amount,source,kind}
##   hero_pull{to,source} / hero_slow{factor,seconds,source}
##   ground_stage{cell,stage,cause}   草の段階の変更要求(粘液で荒地、種の食害)
##   growth_pause{cell,seconds}       粘液の下の種・芽は成長しない(延長のたびに再通知)
##   fertile{pos,radius_px,cause}     撃破地点周辺の肥沃化
##   reward{enemy_id,kind,amount,tier,pos}  最終撃破かつ origin=="initial" のときだけ1回
##   enemy_damaged{enemy_id,amount,raw,kind,hp} / enemy_defeated{enemy_id,kind,pos,origin}
##   junk_pile_destroyed{pile_id,pos,cell} / junk_pile_removed{pile_id,pos,cell}(在庫切れ)
##   mushling_call{enemy_id,group_id,pos}
##   fx{kind,pos,enemy_id,...}        表示用(windup/explosion/howl/stuck/rage/gas/needle_hit/shell_break 等)
##   crop_damaged / crop_removed / pepper_counter / cactus_thorn / flytrap_capture(植物側のイベントをそのまま通す)
## 第2弾の追加イベント(出力はイベントのまま):
##   hero_stun{seconds,enemy_id} / helper_stop{helper_id,seconds,cause}   タイホウエビ(cause stun)・スカンクの雲(cause odor)
##   hero_slow{factor 0.6,source "odor"}                                   臭気の雲の中の主人公(照会は hero_odor_mult())
##   hero_damage / helper_damage の kind: reflected(カガミトカゲの反射弾) / acid(フウセンガエルの酸) / 通常の敵名
##   reward{...,instant:true}   第2弾の撃破報酬は共通備蓄へ即時加算(Common2.reward_event)。マンホールの巣の制圧は nest:"small" 付き(基礎30)
##   nest_suppressed{net_id,pos}   マンホール網がすべて塞がれた
##   ground_stage{cell,stage:"sprout",cause:"hippo"}   カバが成熟した草を食べた
##   fruit_eaten / kudzu_root_removed(reason eaten)   落果・クズの根を食べた(crop_system 側のイベントを通す)
## 照会: helper_targets()(ガラスジカを除く標的) / detectable_enemies()(category: enemy / neutral / bonus、地中のモグラは盛り土の位置、分身は除外)
##   counts_for_stability(分身・ガラスジカ・閉じたマンホールは数えない) / odor_clouds() / acid_pools() / hero_odor_mult()
const Defs: GDScript = preload("res://scripts/content_pack/content_defs.gd")
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")
const Base: GDScript = preload("res://scripts/content_pack/enemies/base.gd")
const Common2: GDScript = preload("res://scripts/content_pack/common2.gd")
const Facing: GDScript = preload("res://scripts/content_pack/facing.gd")
const BEHAVIORS: Dictionary = {
	"shadow_brian": preload("res://scripts/content_pack/enemies/shadow_brian.gd"),
	"tarachunade": preload("res://scripts/content_pack/enemies/tarachunade.gd"),
	"mushling_parent": preload("res://scripts/content_pack/enemies/mushling.gd"),
	"mushling_child": preload("res://scripts/content_pack/enemies/mushling.gd"),
	"quill_hedgehog": preload("res://scripts/content_pack/enemies/quill_hedgehog.gd"),
	"grass_snake": preload("res://scripts/content_pack/enemies/grass_snake.gd"),
	"seed_bird": preload("res://scripts/content_pack/enemies/seed_bird.gd"),
	"junk_crab": preload("res://scripts/content_pack/enemies/junk_crab.gd"),
	"stray_wolf": preload("res://scripts/content_pack/enemies/stray_wolf.gd"),
	"moss_turtle": preload("res://scripts/content_pack/enemies/moss_turtle.gd"),
	"paint_chameleon": preload("res://scripts/content_pack/enemies/paint_chameleon.gd"),
	"slime_slug": preload("res://scripts/content_pack/enemies/slime_slug.gd"),
	"pouch_rabbit": preload("res://scripts/content_pack/enemies/pouch_rabbit.gd"),
	"tongue_frog": preload("res://scripts/content_pack/enemies/tongue_frog.gd"),
	"honeybee_hive": preload("res://scripts/content_pack/enemies/honeybee.gd"),
	"honeybee_swarm": preload("res://scripts/content_pack/enemies/honeybee.gd"),
	"armadillo": preload("res://scripts/content_pack/enemies/armadillo.gd"),
	"sludge_carp": preload("res://scripts/content_pack/enemies/sludge_carp.gd"),
	"leafcutter_ant": preload("res://scripts/content_pack/enemies/ant.gd"),
	"ant_hill": preload("res://scripts/content_pack/enemies/ant.gd"),
	"mimic_cabbage": preload("res://scripts/content_pack/enemies/mimic_cabbage.gd"),
	"black_kite": preload("res://scripts/content_pack/enemies/black_kite.gd"),
	"deer": preload("res://scripts/content_pack/enemies/deer.gd"),
	"iron_jaw_beetle": preload("res://scripts/content_pack/enemies/iron_jaw_beetle.gd"),
	"root_mole": preload("res://scripts/content_pack/enemies/root_mole.gd"),
	"skunk": preload("res://scripts/content_pack/enemies/skunk.gd"),
	"hippo": preload("res://scripts/content_pack/enemies/hippo.gd"),
	"honey_bear": preload("res://scripts/content_pack/enemies/honey_bear.gd"),
	"sewer_rat": preload("res://scripts/content_pack/enemies/sewer.gd"),
	"manhole": preload("res://scripts/content_pack/enemies/sewer.gd"),
	"bat_flock": preload("res://scripts/content_pack/enemies/bat.gd"),
	"iron_rhino": preload("res://scripts/content_pack/enemies/iron_rhino.gd"),
	"thunder_eel": preload("res://scripts/content_pack/enemies/thunder_eel.gd"),
	"decoy_newt": preload("res://scripts/content_pack/enemies/newt.gd"),
	"decoy_tail": preload("res://scripts/content_pack/enemies/newt.gd"),
	"mirror_lizard": preload("res://scripts/content_pack/enemies/mirror_lizard.gd"),
	"pistol_shrimp": preload("res://scripts/content_pack/enemies/pistol_shrimp.gd"),
	"balloon_frog": preload("res://scripts/content_pack/enemies/balloon_frog.gd"),
	"glass_deer": preload("res://scripts/content_pack/enemies/glass_deer.gd"),
}

const PX_PER_M: float = 10.0
const STEP_MAX: float = 0.1
const MOVE_SUB: float = 2.0
const HERO_R: float = 4.0
const EPS: float = 1e-6
const ARRIVE_TOL: float = 0.05
const SLIDE_ANGLES: Array = [0.0, 0.6, -0.6, 1.2, -1.2]
const STRAIGHT_ANGLES: Array = [0.0]
const INT_KEYS: Array = ["id", "group_id", "parent_id", "pack_id", "slot", "target_pile", "eaten", "bounces", "target_crop", "owner", "stock", "gnaw_crop", "hive_id", "hill_id", "tid", "eat_crop", "col_crop", "swarm_id", "fruit_id", "net_id", "plug", "home_mh", "exit_id", "satiety", "rust", "target_id", "decoy_of", "glass_seed"]

var host: RefCounted
var crops: RefCounted
var rng: RandomNumberGenerator
var defs: Dictionary = {}
var time: float = 0.0
var enemies: Array = []
var next_id: int = 1
var projectiles: Array = []
var gas: Array = []
var slime: Dictionary = {}
var piles: Array = []
## 第2弾の状態。臭気の雲(スカンク)・酸(フウセンガエル)・ガラスジカの抽選の記録。common は窓口の濡れたマス(ウナギの伝導)。
var odor: Array = []
var acid: Array = []
var glass_seed: int = 0
var glass_rolls: Dictionary = {}     # 地域キー(String) -> 当たった候補の番号(-1 は当たりなし)
var common: RefCounted = null
var next_crop_tick: float = 1.0
var last_error: String = ""
var _by_id: Dictionary = {}

func _init(p_host: RefCounted, p_rng: RandomNumberGenerator, p_crops: RefCounted, p_defs: Dictionary = {}) -> void:
	host = p_host
	rng = p_rng
	crops = p_crops
	defs = p_defs if not p_defs.is_empty() else Defs.load_enemies()

# ---------------------------------------------------------------- 定義の参照
func def_of(e: Dictionary) -> Dictionary:
	return defs.get(str(e.kind), {})

func pf(e: Dictionary, key: String, fallback: float = 0.0) -> float:
	var p: Dictionary = def_of(e).get("params", {})
	return float(p.get(key, fallback))

func pm(e: Dictionary, key: String, fallback: float = 0.0) -> float:
	return pf(e, key, fallback) * PX_PER_M

func speed_px(e: Dictionary) -> float:
	return float(def_of(e).get("speed_mps", 1.0)) * PX_PER_M

func radius_px(e: Dictionary) -> float:
	return float(def_of(e).get("radius_m", 0.5)) * PX_PER_M

func territory_px(e: Dictionary) -> float:
	return float(def_of(e).get("territory_m", 10.0)) * PX_PER_M

func beh(e: Dictionary) -> GDScript:
	return BEHAVIORS.get(str(e.kind), Base)

func tags_of(e: Dictionary) -> Array:
	return beh(e).tags(self, e)

func due(t: float) -> bool:
	return time >= t - EPS

func set_state(e: Dictionary, st: String, dur: float = 0.0) -> void:
	e.state = st
	e.until = time + dur

# ---------------------------------------------------------------- 出現
## 敵を出す。origin は "initial"(初期配置) / "produced"(生産)。戻り値は敵ID(未知の種類は -1)。
## opts: tier("near"/"mid"/"far")、home、hp、group_id、parent_id、pack_id、slot、piles(ガラクタヤドカリ付属の置き場)
func spawn(kind: String, pos: Vector2, origin: String = "initial", opts: Dictionary = {}) -> int:
	if not defs.has(kind):
		return -1
	var d: Dictionary = defs[kind]
	var id: int = next_id
	next_id += 1
	var e: Dictionary = {
		"id": id, "kind": kind, "origin": origin, "tier": str(opts.get("tier", "near")),
		"pos": pos, "home": Vector2(opts.get("home", pos)), "hp": float(opts.get("hp", d.hp)), "max_hp": float(d.hp),
		"state": "idle", "until": 0.0, "face": Vector2.DOWN, "reward_paid": false, "alive": true,
		"flee_until": 0.0, "flee_from": pos, "wp": pos, "wp_valid": false, "wait_until": 0.0,
		"fruit_id": 0, "fruit_t": -1.0, "fruit_skip": 0.0,
		"last_cell": Grid.cell_of_pos(pos), "group_id": int(opts.get("group_id", 0)), "parent_id": int(opts.get("parent_id", 0)),
		"pack_id": int(opts.get("pack_id", 0)), "slot": int(opts.get("slot", 0)), "blocked": false, "melee_at": 0.0}
	enemies.append(e)
	_by_id[id] = e
	beh(e).init(self, e, opts)
	for pd: Variant in opts.get("piles", []):
		var pdd: Dictionary = pd
		add_junk_pile(Vector2(pdd.pos), int(pdd.get("stock", 2)))
	return id

## マッシュリングの親1体と子2体の組(同じ group_id)。戻り値 {"parent":id,"children":[id,id],"group_id":n}
func spawn_mushling_family(pos: Vector2, origin: String = "initial", opts: Dictionary = {}) -> Dictionary:
	var gid: int = next_id
	var pid: int = spawn("mushling_parent", pos, origin, _merge(opts, {"group_id": gid}))
	var kids: Array = []
	for i: int in range(2):
		var off: Vector2 = Vector2(-10.0 + 20.0 * float(i), 10.0)
		kids.append(spawn("mushling_child", pos + off, origin, _merge(opts, {"group_id": gid, "parent_id": pid})))
	return {"parent": pid, "children": kids, "group_id": gid}

## ノラオオカミの群れ(同じ pack_id、3匹)。戻り値は敵IDの配列。
func spawn_wolf_pack(pos: Vector2, origin: String = "initial", opts: Dictionary = {}) -> Array:
	var pk: int = next_id
	var ids: Array = []
	for i: int in range(3):
		var off: Vector2 = Vector2.from_angle(TAU * float(i) / 3.0) * 12.0
		ids.append(spawn("stray_wolf", pos + off, origin, _merge(opts, {"pack_id": pk, "slot": i, "home": pos})))
	return ids

func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var r: Dictionary = a.duplicate()
	r.merge(b, true)
	return r

## ガラクタ置き場(射撃で崩せる。HP20、報酬なし)。IDは敵と同じ空間。
func add_junk_pile(pos: Vector2, stock: int) -> int:
	var id: int = next_id
	next_id += 1
	piles.append({"id": id, "pos": pos, "stock": stock, "hp": 20.0, "max_hp": 20.0})
	return id

func get_pile(id: int) -> Dictionary:
	for p: Dictionary in piles:
		if int(p.id) == id:
			return p
	return {}

# ---------------------------------------------------------------- 固定物(巣・アリ塚)・擬態の占有
## 巣・アリ塚の占有範囲(マス)。
func rect_of_struct(e: Dictionary) -> Rect2i:
	var sz: Array = def_of(e).get("size", [1, 1])
	var size: Vector2i = Vector2i(int(sz[0]), int(sz[1]))
	return Rect2i(Grid.cell_of_pos(Vector2(e.pos) - Vector2(size) * (Grid.CELL_PX * 0.5)), size)

## このマスを占める固定物(生存中のミツバチの巣・アリ塚)の種類。なければ ""。歩けない。
func structure_at(cell: Vector2i) -> String:
	for e: Dictionary in enemies:
		if e.alive and def_of(e).has("size") and rect_of_struct(e).has_point(cell):
			return str(e.kind)
	return ""

## 巣・アリ塚の占有範囲一覧(ホストの歩行・配置判定用)。[{"id","kind","rect":Rect2i}]
func structure_rects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in enemies:
		if e.alive and def_of(e).has("size"):
			out.append({"id": e.id, "kind": e.kind, "rect": rect_of_struct(e)})
	return out

## 植付けを妨げる敵側の占有。固定物と、擬態中のミミックキャベツのマス。なければ ""。crop_system.occupy_check に接続される。
func occupied_by(cell: Vector2i) -> String:
	var k: String = structure_at(cell)
	if k != "":
		return k
	for e: Dictionary in enemies:
		if e.alive and e.kind == "mimic_cabbage" and beh(e).hidden(self, e) and Grid.cell_of_pos(e.pos) == cell:
			return "mimic_cabbage"
	return ""

## 受粉するミツバチの巣(生存中)。crop_system.pollinator_extra に接続される。巣が壊れれば消える。
func pollinator_list() -> Array:
	var out: Array = []
	for e: Dictionary in enemies:
		if e.alive and e.kind == "honeybee_hive":
			var r: Rect2i = rect_of_struct(e)
			out.append({"cell": r.position, "size": r.size, "active": true})
	return out

## 植物(オジギソウ・ホウセンカ)が近さを調べるための敵の位置。生存中で擬態中でないもの。crop_system.enemy_feed に接続される。
func threat_positions() -> Array:
	var out: Array = []
	for e: Dictionary in enemies:
		if e.alive and not is_hidden(e) and not bool(def_of(e).get("decoy", false)) and str(e.kind) != "manhole":   # 分身とマンホール(巣)は脅威に数えない
			out.append({"pos": e.pos, "neutral": bool(def_of(e).get("neutral", false))})
	return out

## ホウセンカの実がはじけたときの範囲ダメージ。中立以外の当たる敵へ倍率なしで与える。
func burst_damage(center: Vector2, radius_px_total: float, amount: float) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	for e: Dictionary in enemies.duplicate():
		if not bool(e.alive) or bool(def_of(e).get("neutral", false)) or not is_hittable(e):
			continue
		if e.pos.distance_to(center) <= radius_px_total + radius_px(e):
			deal_raw(e, amount, "balsam", ev)
	_sweep()
	return ev

## crop_system が返したイベントを敵側へ渡す(ウサギのほお袋への横取り)。advance(dt) の前に呼ぶ。
func on_crop_events(evs: Array) -> void:
	for x: Variant in evs:
		var xd: Dictionary = x
		if str(xd.get("type", "")) == "seeds_stolen":
			for e: Dictionary in enemies:
				if e.alive and e.kind == "pouch_rabbit" and int(e.gnaw_crop) == int(xd.crop_id):
					beh(e).stash(self, e, float(xd.amount))
					break

# ---------------------------------------------------------------- 照会
func get_enemy(id: int) -> Dictionary:
	if _by_id.has(id):
		return (_by_id[id] as Dictionary).duplicate(true)
	return {}

## 内部用の参照(読み取り専用で使う)
func ref(id: int) -> Dictionary:
	return _by_id.get(id, {})

func enemy_ids() -> Array:
	var out: Array = []
	for e: Dictionary in enemies:
		if e.alive:
			out.append(e.id)
	return out

func is_alive(id: int) -> bool:
	return _by_id.has(id) and bool((_by_id[id] as Dictionary).alive)

## 地域安定に数える個体か。中立(ミツバチ・ガラスジカ)・分身・閉じたマンホールは数えない。地中・水中・飛行・眠り中は数える。
func counts(e: Dictionary) -> bool:
	var d: Dictionary = def_of(e)
	return bool(e.alive) and not bool(d.get("neutral", false)) and not bool(d.get("decoy", false)) and beh(e).counts(self, e)

func counts_for_stability(id: int) -> bool:
	if not is_alive(id):
		return false
	return counts(_by_id[id])

func living_count_for_stability() -> int:
	var n: int = 0
	for e: Dictionary in enemies:
		if counts(e):
			n += 1
	return n

## 地域安定の判定用。生存中の全敵(擬態・黒焦げ・水中・飛行を含む。中立は neutral=true で区別)。
func living_for_stability() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in enemies:
		if counts(e):
			out.append({"id": e.id, "kind": e.kind, "pos": e.pos, "origin": e.origin})
	return out

func is_hittable(e: Dictionary) -> bool:
	return bool(e.alive) and beh(e).hittable(self, e)

func is_hidden(e: Dictionary) -> bool:
	return bool(e.alive) and beh(e).hidden(self, e)

## ホストの当たり判定用。飛行中・潜行中は含まない。擬態中は含む(当たれば見破り)。
## type は "enemy" または "junk_pile"。
func hittable_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in enemies:
		if is_hittable(e):
			out.append({"type": "enemy", "id": e.id, "kind": e.kind, "pos": e.pos, "radius": radius_px(e),
				"hidden": beh(e).hidden(self, e), "neutral": bool(def_of(e).get("neutral", false)),
				"decoy": bool(def_of(e).get("decoy", false)), "helper_exempt": bool(def_of(e).get("bonus", false))})
	for p: Dictionary in piles:
		out.append({"type": "junk_pile", "id": p.id, "kind": "junk_pile", "pos": p.pos, "radius": 4.0, "hidden": false, "neutral": false})
	return out

## おたすけ植物(アーミー)が狙える標的。hittable_targets からガラスジカ(helper_exempt)を除いたもの。
func helper_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in hittable_targets():
		if not bool(t.get("helper_exempt", false)):
			out.append(t)
	return out

## 画面・マップの検知表示用。擬態中は除く。見破られた敵とヒカリゴケ(夜)の範囲内は含む。
func detectable_enemies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in enemies:
		if not e.alive or bool(def_of(e).get("decoy", false)):
			continue
		if beh(e).hidden(self, e) and not crops.glow_moss_reveals(Grid.cell_of_pos(e.pos)):
			continue
		var dp: Variant = beh(e).detect_pos(self, e)   # 地中のネッコモグラは盛り土の位置。出せなければ null
		if dp == null:
			continue
		var cat: String = "bonus" if bool(def_of(e).get("bonus", false)) else ("neutral" if bool(def_of(e).get("neutral", false)) else "enemy")
		out.append({"id": e.id, "kind": e.kind, "pos": Vector2(dp), "radius": radius_px(e), "tier": e.tier, "state": e.state,
			"neutral": bool(def_of(e).get("neutral", false)), "origin": e.origin, "category": cat})
	return out

## 擬態中に動いている敵の「揺れ・揺らぎ」記号の位置(本体・マップ表示はなし)
func hint_marks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in enemies:
		if e.alive and beh(e).hint(self, e):
			out.append({"id": e.id, "kind": e.kind, "pos": e.pos})
	return out

## 主人公が通れない体(コケガメ)。[{pos,radius}]
func body_blockers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in enemies:
		if e.alive and bool(def_of(e).get("blocks_hero", false)):
			out.append({"id": e.id, "pos": e.pos, "radius": radius_px(e)})
	return out

func slime_cells() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k: Variant in slime.keys():
		var c: Vector2i = k
		var r: Dictionary = slime[c]
		out.append({"cell": c, "remaining": float(r.until) - time, "age": time - float(r.since)})
	return out

func slime_at(cell: Vector2i) -> bool:
	return slime.has(cell) and time < float((slime[cell] as Dictionary).until) - EPS

## 粘液の下の種・芽は成長しない(ホストが成長の更新で参照)
func growth_blocked(cell: Vector2i) -> bool:
	return slime_at(cell)

func gas_clouds() -> Array:
	return gas

func projectile_list() -> Array:
	return projectiles

# ---------------------------------------------------------------- 主人公・おたすけ植物
func hero_t() -> Dictionary:
	var h: Dictionary = host.hero()
	if h.is_empty():
		return {}
	return {"type": "hero", "id": 0, "pos": Vector2(h.pos), "hp": float(h.get("hp", 0.0)), "aim": Vector2(h.get("aim", Vector2.ZERO))}

func all_targets() -> Array:
	var out: Array = []
	var h: Dictionary = hero_t()
	if not h.is_empty():
		out.append(h)
	for hp: Dictionary in host.helpers():
		out.append({"type": "helper", "id": int(hp.id), "pos": Vector2(hp.pos), "hp": float(hp.get("hp", 0.0)), "aim": Vector2.ZERO})
	return out

## 主人公(hero_range内、los指定なら視線あり)を優先し、いなければ最も近いおたすけ植物(helper_range内)。
func pick_target(e: Dictionary, hero_range: float, helper_range: float, los: bool) -> Dictionary:
	var h: Dictionary = hero_t()
	if not h.is_empty() and e.pos.distance_to(h.pos) <= hero_range and (not los or host.line_clear(e.pos, h.pos)):
		return h
	return nearest_helper(e, helper_range, los)

func nearest_helper(e: Dictionary, range_px: float, los: bool) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = 1e18
	for t: Dictionary in all_targets():
		if t.type != "helper":
			continue
		var d: float = e.pos.distance_to(t.pos)
		if d <= range_px and d < bd and (not los or host.line_clear(e.pos, t.pos)):
			best = t
			bd = d
	return best

## 主人公・おたすけ植物のうち最も近いもの
func nearest_target(e: Dictionary, range_px: float, los: bool) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = 1e18
	for t: Dictionary in all_targets():
		var d: float = e.pos.distance_to(t.pos)
		if d <= range_px and d < bd and (not los or host.line_clear(e.pos, t.pos)):
			best = t
			bd = d
	return best

func in_reach(e: Dictionary, t: Dictionary) -> bool:
	return e.pos.distance_to(t.pos) <= radius_px(e) + HERO_R + 2.0

func dmg_target(e: Dictionary, t: Dictionary, amount: float, ev: Array[Dictionary]) -> void:
	if t.type == "enemy":   # 怒ったミツバチがハチミツグマを刺す
		var victim: Dictionary = ref(int(t.id))
		if not victim.is_empty():
			deal_raw(victim, amount, "sting", ev)
		return
	if t.type == "hero":
		ev.append({"type": "hero_damage", "amount": amount, "source": e.id, "kind": e.kind})
	else:
		ev.append({"type": "helper_damage", "helper_id": t.id, "amount": amount, "source": e.id, "kind": e.kind})

func fx(ev: Array[Dictionary], kind: String, pos: Vector2, e: Variant = null, extra: Dictionary = {}) -> void:
	var d: Dictionary = {"type": "fx", "kind": kind, "pos": pos, "enemy_id": (e.id if e != null else 0)}
	d.merge(extra, true)
	ev.append(d)

## 照準方向 from_pos が、敵の向きの正面(±half_deg)にあるか
func is_front(e: Dictionary, from_pos: Variant, half_deg: float) -> bool:
	if typeof(from_pos) != TYPE_VECTOR2:
		return false
	var to: Vector2 = Vector2(from_pos) - e.pos
	if to.length() < 1e-6:
		return false
	return absf(rad_to_deg(Vector2(e.face).angle_to(to))) <= half_deg

# ---------------------------------------------------------------- 植物との相互作用
func crop_rect_px(c: Dictionary) -> Rect2:
	return Rect2(Vector2(c.cell) * Grid.CELL_PX, Vector2(c.size) * Grid.CELL_PX)

func crop_center(c: Dictionary) -> Vector2:
	var r: Rect2 = crop_rect_px(c)
	return r.position + r.size * 0.5

func crop_dist(p: Vector2, c: Dictionary) -> float:
	var r: Rect2 = crop_rect_px(c)
	return p.distance_to(Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y)))

## 狙える(ラベンダー・ニンニクで除外されない)最も近い株。mature_only なら成熟株だけ。読み取り専用の参照を返す。
func nearest_crop(e: Dictionary, range_px: float, mature_only: bool) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = 1e18
	var tg: Array = tags_of(e)
	for c: Dictionary in crops.crops:
		if mature_only and not bool(c.mature):
			continue
		var d: float = crop_dist(e.pos, c)
		if d <= range_px and d < bd and crops.crop_targetable_by(tg, int(c.id)):
			best = c
			bd = d
	return best

## 株へのダメージ。植物側のイベントを通し、トウガラシの反撃(敵が逃げる)とサボテンのトゲ(敵がダメージ)を処理する。
func hurt_crop(e: Dictionary, crop_id: int, amount: float, ev: Array[Dictionary], cause: String = "attack") -> void:
	var c: Dictionary = crops.get_crop(crop_id)
	var center: Vector2 = crop_center(c) if not c.is_empty() else e.pos
	var evs: Array[Dictionary] = crops.damage_crop(crop_id, amount, {"enemy_id": e.id, "cause": cause})
	for x: Dictionary in evs:
		ev.append(x)
		if not e.alive:
			continue
		if x.type == "pepper_counter" and int(x.enemy_id) == int(e.id):
			deal_raw(e, float(x.damage), "counter", ev)
			if e.alive:
				start_flee(e, float(x.flee_seconds), center)
		elif x.type == "cactus_thorn" and int(x.enemy_id) == int(e.id):
			deal_raw(e, float(x.damage), "spine", ev)

func start_flee(e: Dictionary, seconds: float, from_pos: Vector2) -> void:
	if str(def_of(e).get("habitat", "land")) != "land" or not beh(e).hittable(self, e):
		return
	e.flee_until = time + seconds
	e.flee_from = from_pos
	beh(e).on_flee(self, e)

# ---------------------------------------------------------------- 移動(経路探索なし。統合時はここを共通の経路へ置き換える)
func can_stand(e: Dictionary, np: Vector2, opts: Dictionary = {}) -> bool:
	var cell: Vector2i = Grid.cell_of_pos(np)
	if not host.in_bounds(cell) or host.is_stable_cell(cell):
		return false
	var hab: String = str(opts.get("habitat", def_of(e).get("habitat", "land")))
	if hab == "land":
		if not host.is_walkable(cell) or host.is_blocked(cell) or crops.blocks_enemy(cell):
			return false
	elif hab == "water":
		if not host.is_water(cell):
			return false
	elif hab == "amphi":   # カバ: 水中か、水際から shore_px 以内の陸
		if host.is_building(cell) or crops.blocks_enemy(cell):
			return false
		if not host.is_water(cell):
			if not host.is_walkable(cell) or host.is_blocked(cell):
				return false
			var sh: float = float(opts.get("shore_px", 0.0))
			if sh > 0.0 and not near_water(np, sh):
				return false
	var lim: float = float(opts.get("limit_px", 0.0))
	if lim > 0.0:
		var nd: float = np.distance_to(e.home)
		if nd > lim and nd >= e.pos.distance_to(e.home):
			return false
	if hab != "air" and not bool(opts.get("ignore_repel", false)):
		var tg: Array = tags_of(e)
		if not tg.is_empty() and crops.is_repelled_cell(cell, tg) and not crops.is_repelled_cell(Grid.cell_of_pos(e.pos), tg):
			return false
	return true

## dir 方向へ speed(px/s)×dt だけ進む。障害物は左右へ回避。戻り値は進んだ距離。e.blocked に完全停止を記録。
## opts: straight(回避なし)、keep_face、habitat、limit_px、ignore_repel
func step_move(e: Dictionary, dir: Vector2, speed: float, dt: float, ev: Array[Dictionary], opts: Dictionary = {}) -> float:
	e.blocked = false
	var hab_now: String = str(opts.get("habitat", def_of(e).get("habitat", "land")))
	var spd: float = speed
	if (hab_now == "land" or hab_now == "amphi") and not bool(opts.get("no_root", false)):
		spd *= float(crops.enemy_speed_mult(Grid.cell_of_pos(e.pos)))   # クズの根のマスは敵の移動×0.6
	var rem: float = spd * dt
	if rem <= 0.0 or dir.length_squared() < 1e-9:
		return 0.0
	var d0: Vector2 = dir.normalized()
	if not bool(opts.get("keep_face", false)):
		e.face = d0
	var angles: Array = STRAIGHT_ANGLES if bool(opts.get("straight", false)) else SLIDE_ANGLES
	var moved: float = 0.0
	while rem > EPS and bool(e.alive):
		var s: float = minf(rem, MOVE_SUB)
		var done: bool = false
		for a: float in angles:
			var np: Vector2 = e.pos + d0.rotated(a) * s
			if can_stand(e, np, opts):
				e.pos = np
				moved += s
				rem -= s
				done = true
				break
		if not done:
			e.blocked = true
			break
		_check_cell(e, ev)
	return moved

func walk_to(e: Dictionary, goal: Vector2, speed: float, dt: float, ev: Array[Dictionary], stop_dist: float = 1.0, opts: Dictionary = {}) -> bool:
	e.blocked = false
	var d: float = e.pos.distance_to(goal)
	if d <= stop_dist + ARRIVE_TOL:
		return true
	step_move(e, goal - e.pos, minf(speed, (d - stop_dist) / maxf(dt, 1e-6)), dt, ev, opts)
	return e.pos.distance_to(goal) <= stop_dist + ARRIVE_TOL

func walk_away(e: Dictionary, from_pos: Vector2, speed: float, dt: float, ev: Array[Dictionary], opts: Dictionary = {}) -> float:
	var o: Dictionary = opts.duplicate()
	o["keep_face"] = true
	var dir: Vector2 = e.pos - from_pos
	if dir.length_squared() < 1e-9:
		dir = Vector2.RIGHT
	return step_move(e, dir, speed, dt, ev, o)

## 家の周りをうろつく。center を渡すとその周りを歩く。
func wander(e: Dictionary, dt: float, ev: Array[Dictionary], speed: float, radius: float, center: Variant = null) -> void:
	var c: Vector2 = Vector2(center) if center != null else Vector2(e.home)
	if not bool(e.wp_valid):
		if not due(float(e.wait_until)):
			return
		var ang: float = rng.randf() * TAU
		var dist: float = rng.randf() * radius
		e.wp = c + Vector2.from_angle(ang) * dist
		e.wp_valid = true
	var lim: float = territory_px(e)
	if walk_to(e, e.wp, speed, dt, ev, 1.5, {"limit_px": lim + radius}) or bool(e.blocked):
		e.wp_valid = false
		e.wait_until = time + 1.0 + rng.randf() * 2.0

func _check_cell(e: Dictionary, ev: Array[Dictionary]) -> void:
	var cell: Vector2i = Grid.cell_of_pos(e.pos)
	if cell == e.last_cell:
		return
	e.last_cell = cell
	_cell_effects(e, cell, ev)

## 着地などでマスを変えずに小型になったとき、ハエトリソウの捕獲だけを確認する
func capture_check(e: Dictionary, ev: Array[Dictionary]) -> void:
	if bool(e.alive) and tags_of(e).has("small"):
		var r: Dictionary = crops.flytrap_capture(e.id, Grid.cell_of_pos(e.pos), tags_of(e))
		if bool(r.captured):
			for x2: Dictionary in r.events:
				ev.append(x2)
			deal_raw(e, float(r.damage), "flytrap", ev)

func _cell_effects(e: Dictionary, cell: Vector2i, ev: Array[Dictionary]) -> void:
	for x: Dictionary in crops.enemy_moved(e.id, cell):
		ev.append(x)
		if x.type == "cactus_thorn" and bool(e.alive):
			deal_raw(e, float(x.damage), "spine", ev)
	if bool(e.alive) and tags_of(e).has("small"):
		var r: Dictionary = crops.flytrap_capture(e.id, cell, tags_of(e))
		if bool(r.captured):
			for x2: Dictionary in r.events:
				ev.append(x2)
			deal_raw(e, float(r.damage), "flytrap", ev)

# ---------------------------------------------------------------- 被弾
## 攻撃を当てる。kind: shot / bazooka / tackle / water / helper / spine。from_pos は攻撃元(正面の軽減などに使う)。
func apply_hit(enemy_id: int, amount: float, kind: String, from_pos: Variant = null) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	if _by_id.has(enemy_id):
		var e: Dictionary = _by_id[enemy_id]
		if is_hittable(e):
			_hit(e, amount, kind, from_pos, ev)
		elif kind == "water" and bool(e.alive):
			beh(e).on_water_near(self, e, e.pos, 0.0, ev)
	else:
		_hit_pile(enemy_id, amount, kind, ev)
	_sweep()
	return ev

## 範囲攻撃(バズーカの爆風・水まき)。中心 pos から radius_px の円内の当たる敵すべてに作用する。
func splash(pos: Vector2, radius: float, amount: float, kind: String) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	if kind == "water":
		wash_slime(pos, radius)
	var victims: Array = []
	for e: Dictionary in enemies:
		if is_hittable(e) and e.pos.distance_to(pos) <= radius + radius_px(e):
			victims.append(e)
		elif kind == "water" and bool(e.alive):
			beh(e).on_water_near(self, e, pos, radius, ev)
	for e: Dictionary in victims:
		_hit(e, amount, kind, pos, ev)
	if kind == "bazooka" or kind == "shot":
		for p: Dictionary in piles.duplicate():
			if p.pos.distance_to(pos) <= radius + 4.0:
				_hit_pile(int(p.id), amount, kind, ev)
	_sweep()
	return ev

## 種が地面に落ちた。近くの擬態を見破る(クサヘビ、ミミックキャベツ)。
func notify_seed(pos: Vector2) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	for e: Dictionary in enemies:
		if e.alive:
			beh(e).on_seed(self, e, pos, ev)
	return ev

func _hit(e: Dictionary, amount: float, kind: String, from_pos: Variant, ev: Array[Dictionary]) -> void:
	if not bool(e.alive):
		return
	if kind == "water":
		beh(e).on_water(self, e, ev)
		if amount <= 0.0 or not bool(e.alive):
			return
	var dealt: float = beh(e).calc_damage(self, e, amount, kind, from_pos, ev)
	if dealt > 0.0:
		e.hp = float(e.hp) - dealt
		ev.append({"type": "enemy_damaged", "enemy_id": e.id, "amount": dealt, "raw": amount, "kind": kind, "hp": e.hp})
	if float(e.hp) <= 0.0:
		_kill(e, ev)
	elif bool(e.alive):
		beh(e).on_hit(self, e, kind, from_pos, dealt, ev)

## 倍率なしのダメージ(トゲ・ハエトリソウ・反撃など)
func deal_raw(e: Dictionary, amount: float, kind: String, ev: Array[Dictionary]) -> void:
	if not bool(e.alive):
		return
	e.hp = float(e.hp) - amount
	ev.append({"type": "enemy_damaged", "enemy_id": e.id, "amount": amount, "raw": amount, "kind": kind, "hp": e.hp})
	if float(e.hp) <= 0.0:
		_kill(e, ev)

func _hit_pile(pile_id: int, amount: float, kind: String, ev: Array[Dictionary]) -> void:
	if kind == "water" or kind == "tackle" or kind == "spine":
		return
	var p: Dictionary = get_pile(pile_id)
	if p.is_empty():
		return
	p.hp = float(p.hp) - amount
	if float(p.hp) <= 0.0:
		piles.erase(p)
		ev.append({"type": "junk_pile_destroyed", "pile_id": pile_id, "pos": p.pos, "cell": Grid.cell_of_pos(p.pos)})

## 最終撃破(HPが0)。報酬は initial のときだけ1回。
func _kill(e: Dictionary, ev: Array[Dictionary]) -> void:
	if not bool(e.alive):
		return
	e.alive = false
	ev.append({"type": "enemy_defeated", "enemy_id": e.id, "kind": e.kind, "pos": e.pos, "origin": e.origin})
	if str(e.origin) == "initial" and not bool(e.reward_paid):
		e.reward_paid = true
		var amount: int = int(def_of(e).get("reward", 0))
		if amount > 0:
			if bool(def_of(e).get("instant", false)):
				ev.append(Common2.reward_event(int(e.id), str(e.kind), amount, str(e.tier), e.pos))   # 第2弾: 共通備蓄へ即時加算
			else:
				ev.append({"type": "reward", "enemy_id": e.id, "kind": e.kind, "amount": amount, "tier": e.tier, "pos": e.pos})
	beh(e).on_defeat(self, e, ev)

func _sweep() -> void:
	var keep: Array = []
	for e: Dictionary in enemies:
		if bool(e.alive):
			keep.append(e)
		else:
			_by_id.erase(int(e.id))
	enemies = keep

# ---------------------------------------------------------------- 時間
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
	for e: Dictionary in enemies.duplicate():
		if not bool(e.alive):
			continue
		if float(e.flee_until) > time + EPS and str(def_of(e).get("habitat", "land")) == "land":
			var sp: float = clampf(speed_px(e) * 2.0, 20.0, 35.0)
			walk_away(e, e.flee_from, sp, dt, ev, {"limit_px": territory_px(e)})
		elif _fruit_hook(e, dt, ev):
			pass
		else:
			beh(e).update(self, e, dt, ev)
	_update_projectiles(dt, ev)
	_update_gas(dt, ev)
	_update_odor(dt, ev)
	_update_acid(ev)
	_update_slime(dt, ev)
	_sweep()

func spawn_projectile(p: Dictionary) -> void:
	projectiles.append(p)

func _update_projectiles(dt: float, ev: Array[Dictionary]) -> void:
	for p: Dictionary in projectiles.duplicate():
		var rem: float = float(p.speed) * dt
		var gone: bool = false
		while rem > EPS and not gone:
			var st: float = minf(rem, MOVE_SUB)
			p.pos = p.pos + Vector2(p.dir) * st
			p.left = float(p.left) - st
			rem -= st
			if host.is_building(Grid.cell_of_pos(p.pos)) or not host.in_bounds(Grid.cell_of_pos(p.pos)):
				gone = true
				break
			for t: Dictionary in all_targets():
				if p.pos.distance_to(t.pos) <= HERO_R:
					var src: Dictionary = {"id": int(p.owner), "kind": str(p.kind)}
					if t.type == "hero":
						ev.append({"type": "hero_damage", "amount": float(p.damage), "source": src.id, "kind": src.kind})
					else:
						ev.append({"type": "helper_damage", "helper_id": t.id, "amount": float(p.damage), "source": src.id, "kind": src.kind})
					fx(ev, "needle_hit", p.pos)
					gone = true
					break
			if float(p.left) <= 0.0:
				gone = true
		if gone:
			projectiles.erase(p)

func add_gas(pos: Vector2, owner_id: int, radius: float, seconds: float, dps: float) -> void:
	gas.append({"pos": pos, "owner": owner_id, "radius": radius, "until": time + seconds, "dps": dps, "next_tick": time + 1.0})

func _update_gas(_dt: float, ev: Array[Dictionary]) -> void:
	for g: Dictionary in gas.duplicate():
		while float(g.next_tick) <= time + EPS and float(g.next_tick) <= float(g.until) + EPS:
			g.next_tick = float(g.next_tick) + 1.0
			for t: Dictionary in all_targets():
				if g.pos.distance_to(t.pos) <= float(g.radius):
					if t.type == "hero":
						ev.append({"type": "hero_damage", "amount": float(g.dps), "source": int(g.owner), "kind": "gas"})
					else:
						ev.append({"type": "helper_damage", "helper_id": t.id, "amount": float(g.dps), "source": int(g.owner), "kind": "gas"})
		if time >= float(g.until) - EPS:
			gas.erase(g)

# ---------------------------------------------------------------- 粘液(ネバナメクジ)
func slime_mark(e: Dictionary, cell: Vector2i, ev: Array[Dictionary]) -> void:
	var life: float = pf(e, "slime_s", 20.0)
	var rec: Dictionary = slime.get(cell, {})
	if rec.is_empty() or time >= float(rec.until) - EPS:
		rec = {"until": time + life, "since": time, "ground_sent": false}
	else:
		rec.until = time + life
	slime[cell] = rec
	if host.grass_stage(cell) in ["seed", "sprout"]:
		ev.append({"type": "growth_pause", "cell": cell, "seconds": life})

func wash_slime(pos: Vector2, radius: float) -> void:
	for k: Variant in slime.keys():
		var c: Vector2i = k
		if Grid.center_of_cell(c).distance_to(pos) <= radius:
			slime.erase(c)

func _update_slime(dt: float, ev: Array[Dictionary]) -> void:
	for k: Variant in slime.keys():
		var c: Vector2i = k
		var r: Dictionary = slime[c]
		if time >= float(r.until) - EPS:
			slime.erase(c)
			continue
		if not bool(r.ground_sent) and time - float(r.since) >= 10.0 - EPS and host.grass_stage(c) == "grass":
			r.ground_sent = true
			ev.append({"type": "ground_stage", "cell": c, "stage": "wasteland", "cause": "slime"})
	var h: Dictionary = hero_t()
	if not h.is_empty() and slime_at(Grid.cell_of_pos(h.pos)):
		ev.append({"type": "hero_slow", "factor": 0.5, "seconds": maxf(dt, 0.25), "source": "slime"})
	while next_crop_tick <= time + EPS:
		next_crop_tick += 1.0
		for cid: Variant in crops.crop_ids():
			var c2: Dictionary = crops.get_crop(int(cid))
			if c2.is_empty():
				continue
			var hit: bool = false
			for cc: Vector2i in Grid.cells_of(Rect2i(c2.cell, c2.size)):
				if slime_at(cc):
					hit = true
					break
			if hit:
				for x: Dictionary in crops.damage_crop(int(cid), 2.0, {"enemy_id": -1, "cause": "collateral"}):
					ev.append(x)

# ---------------------------------------------------------------- 第2弾の共通
## 位置 pos から r_px 以内に水面のマスがあるか(カバの「水際から8m」、ウナギの「水際から6m」)。
func near_water(pos: Vector2, r_px: float) -> bool:
	var c0: Vector2i = Grid.cell_of_pos(pos)
	var n: int = int(ceil(r_px / Grid.CELL_PX)) + 1
	for dy: int in range(-n, n + 1):
		for dx: int in range(-n, n + 1):
			var c: Vector2i = c0 + Vector2i(dx, dy)
			if host.in_bounds(c) and host.is_water(c) and Grid.center_of_cell(c).distance_to(pos) <= r_px + Grid.CELL_PX * 0.5:
				return true
	return false

## 最も近い水面マスの中心(r_px 以内)。なければ null。
func nearest_water_pos(pos: Vector2, r_px: float) -> Variant:
	var c0: Vector2i = Grid.cell_of_pos(pos)
	var n: int = int(ceil(r_px / Grid.CELL_PX)) + 1
	var best: Variant = null
	var bd: float = INF
	for dy: int in range(-n, n + 1):
		for dx: int in range(-n, n + 1):
			var c: Vector2i = c0 + Vector2i(dx, dy)
			if host.in_bounds(c) and host.is_water(c):
				var p: Vector2 = Grid.center_of_cell(c)
				var d: float = p.distance_to(pos)
				if d < bd and d <= r_px:
					bd = d
					best = p
	return best

## 窓口 water_landed からの水の着弾マス。当たらない状態(地中)の敵が反応する。
func water_cells_landed(cells: Array) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	for v: Variant in cells:
		var c: Vector2i = v
		var p: Vector2 = Grid.center_of_cell(c)
		for e: Dictionary in enemies:
			if bool(e.alive) and not is_hittable(e):
				beh(e).on_water_near(self, e, p, 0.0, ev)
	return ev

# ---- 草食タグと落果(リンゴ)。第1弾の草食と第2弾のサイは共通の割り込みで落果を最優先にする
const FRUIT_STATES: Dictionary = {
	"deer": {"free": ["graze", "approach", "eat"], "rest": "graze"},
	"pouch_rabbit": {"free": ["rest", "approach", "chew", "return"], "rest": "rest"},
	"moss_turtle": {"free": ["hidden", "walk", "eat", "revealed"], "rest": "revealed"},
	"slime_slug": {"free": ["idle", "crawl"], "rest": "idle"},
	"leafcutter_ant": {"free": ["idle", "walk", "cut"], "rest": "idle"},
	"mimic_cabbage": {"free": ["hidden", "revealed", "return"], "rest": "revealed"},
	"iron_rhino": {"free": ["idle"], "rest": "idle"},
}
const FRUIT_EAT_S: float = 3.0
const FRUIT_MARGIN_PX: float = 100.0

## 敵のきっかけの範囲(px)。種類ごとの定義値から。
func trigger_px(e: Dictionary) -> float:
	for k: String in ["seek_m", "trigger_crop_m", "trigger_m"]:
		if def_of(e).get("params", {}).has(k):
			return pm(e, k)
	return 0.0

## 草食タグの敵が引き寄せられる落果のうち最優先のもの(なければ空)。自分のきっかけの範囲内、または縄張り(家から)+10m以内。
## 安定した地域の落果は除く(再侵攻の禁止)。
func fruit_for(e: Dictionary, trig_px: float = -1.0) -> Dictionary:
	if not tags_of(e).has("herbivore"):
		return {}
	var trg: float = trig_px if trig_px >= 0.0 else trigger_px(e)
	var terr: float = territory_px(e) + FRUIT_MARGIN_PX
	var best: Dictionary = {}
	var bd: float = INF
	for f: Dictionary in crops.fruit_list():
		if host.is_stable_cell(f.cell):
			continue
		var p: Vector2 = f.pos
		var d: float = e.pos.distance_to(p)
		if (d <= trg or Vector2(e.home).distance_to(p) <= terr) and d < bd:
			bd = d
			best = f
	return best

func _fruit_hook(e: Dictionary, dt: float, ev: Array[Dictionary]) -> bool:
	var fs: Dictionary = FRUIT_STATES.get(str(e.kind), {})
	if fs.is_empty():
		return false
	if int(e.fruit_id) == 0:
		if time < float(e.fruit_skip) - EPS or not (fs.free as Array).has(str(e.state)):
			return false
		var f0: Dictionary = fruit_for(e)
		if f0.is_empty():
			return false
		e.fruit_id = int(f0.id)
		e.fruit_t = -1.0
		beh(e).on_flee(self, e)     # かじり中の状態を捨てる
		e.state = str(fs.rest)
		fx(ev, "fruit_seek", f0.pos, e)
	# 逃げる草食(シカ・ウサギ)は主人公が近づけば落果をあきらめる
	if def_of(e).get("params", {}).has("flee_trigger_m"):
		var h: Dictionary = hero_t()
		if not h.is_empty() and e.pos.distance_to(h.pos) <= pm(e, "flee_trigger_m"):
			e.fruit_id = 0
			e.fruit_t = -1.0
			return false
	var cur: Dictionary = {}
	for f: Dictionary in crops.fruit_list():
		if int(f.id) == int(e.fruit_id):
			cur = f
			break
	if cur.is_empty() or host.is_stable_cell(cur.cell):
		e.fruit_id = 0
		e.fruit_t = -1.0
		return false
	var fp: Vector2 = cur.pos
	if e.pos.distance_to(fp) > radius_px(e) + 3.0:
		e.fruit_t = -1.0
		step_move(e, fp - e.pos, speed_px(e), dt, ev, {"limit_px": territory_px(e) + FRUIT_MARGIN_PX + 20.0})
		if bool(e.blocked):
			e.fruit_id = 0
			e.fruit_skip = time + 5.0
	elif float(e.fruit_t) < 0.0:
		e.fruit_t = time + FRUIT_EAT_S
	elif due(float(e.fruit_t)):
		ev.append_array(crops.consume_fruit(int(e.fruit_id), int(e.id)))
		e.fruit_id = 0
		e.fruit_t = -1.0
	return true

# ---- 臭気の雲(スカンク)。扇形。中の主人公は移動×0.6、おたすけ植物は仕事停止
func add_odor(pos: Vector2, dir: Vector2, owner_id: int, length_px: float, half_deg: float, seconds: float) -> void:
	odor.append({"pos": pos, "dir": dir.normalized(), "owner": owner_id, "length": length_px, "half_deg": half_deg,
		"until": time + seconds, "next_tick": time})

func in_odor(p: Vector2, o: Dictionary) -> bool:
	var v: Vector2 = p - Vector2(o.pos)
	if v.length() > float(o.length) + EPS:
		return false
	if v.length_squared() < 1e-9:
		return true
	return Facing.angle_between_deg(Vector2(o.dir), v) <= float(o.half_deg) + 1e-3

func _garlic_at(p: Vector2) -> bool:
	return crops.garlic_covers_cell(Grid.cell_of_pos(p))

## 主人公が臭気の雲の中か(ニンニクの範囲に立っていれば作用しない)
func hero_in_odor() -> bool:
	var h: Dictionary = hero_t()
	if h.is_empty() or _garlic_at(h.pos):
		return false
	for o: Dictionary in odor:
		if time < float(o.until) - EPS and in_odor(h.pos, o):
			return true
	return false

## 主人公の移動速度の倍率(臭気の雲の中は×0.6)。ホストの移動処理が参照する(イベント hero_slow と同じ値)。
func hero_odor_mult() -> float:
	return 0.6 if hero_in_odor() else 1.0

func odor_clouds() -> Array:
	return odor

func _update_odor(dt: float, ev: Array[Dictionary]) -> void:
	for o: Dictionary in odor.duplicate():
		if time >= float(o.until) - EPS:
			odor.erase(o)
			continue
		var h: Dictionary = hero_t()
		if not h.is_empty() and in_odor(h.pos, o) and not _garlic_at(h.pos):
			ev.append({"type": "hero_slow", "factor": 0.6, "seconds": maxf(dt, 0.25), "source": "odor"})
		if float(o.next_tick) <= time + EPS:
			o.next_tick = time + 0.5
			for t: Dictionary in all_targets():
				if t.type == "helper" and in_odor(t.pos, o) and not _garlic_at(t.pos):
					ev.append(Common2.helper_stop_event(int(t.id), 1.0, "odor"))

# ---- 酸(フウセンガエルが割れた跡)。主人公・おたすけ植物・栽培植物に毎秒ダメージ
func add_acid(pos: Vector2, owner_id: int, radius: float, seconds: float, dps: float) -> void:
	acid.append({"pos": pos, "owner": owner_id, "radius": radius, "until": time + seconds, "dps": dps, "next_tick": time + 1.0})

func _update_acid(ev: Array[Dictionary]) -> void:
	for a: Dictionary in acid.duplicate():
		while float(a.next_tick) <= time + EPS and float(a.next_tick) <= float(a.until) + EPS:
			a.next_tick = float(a.next_tick) + 1.0
			for t: Dictionary in all_targets():
				if Vector2(a.pos).distance_to(t.pos) <= float(a.radius):
					if t.type == "hero":
						ev.append({"type": "hero_damage", "amount": float(a.dps), "source": int(a.owner), "kind": "acid"})
					else:
						ev.append({"type": "helper_damage", "helper_id": t.id, "amount": float(a.dps), "source": int(a.owner), "kind": "acid"})
			for cid: Variant in crops.crop_ids():
				var c: Dictionary = crops.get_crop(int(cid))
				if not c.is_empty() and crop_dist(a.pos, c) <= float(a.radius):
					for x: Dictionary in crops.damage_crop(int(cid), float(a.dps), {"enemy_id": int(a.owner), "cause": "collateral"}):
						ev.append(x)
		if time >= float(a.until) - EPS:
			acid.erase(a)

func acid_pools() -> Array:
	return acid

# ---- 群れ・巣の出現
## コウモリの群れ(6匹、同じ group_id)。pos はねぐら(建物のマスに隣接する地点)。戻り値は敵IDの配列。
func spawn_bat_flock(pos: Vector2, origin: String = "initial", opts: Dictionary = {}) -> Array:
	var gid: int = next_id
	var n: int = int(defs.get("bat_flock", {}).get("params", {}).get("flock", 6))
	var ids: Array = []
	for i: int in range(n):
		var off: Vector2 = Vector2.from_angle(TAU * float(i) / float(n)) * 5.0
		ids.append(spawn("bat_flock", pos + off, origin, _merge(opts, {"group_id": gid, "slot": i, "home": pos})))
	return ids

## フウセンガエル(3匹、同じ group_id)。
func spawn_frog_flock(pos: Vector2, origin: String = "initial", opts: Dictionary = {}) -> Array:
	var gid: int = next_id
	var n: int = int(defs.get("balloon_frog", {}).get("params", {}).get("flock", 3))
	var ids: Array = []
	for i: int in range(n):
		var off: Vector2 = Vector2.from_angle(TAU * float(i) / float(n)) * 8.0
		ids.append(spawn("balloon_frog", pos + off, origin, _merge(opts, {"group_id": gid, "slot": i, "home": pos})))
	return ids

## マンホールの網(2〜4個で一つの巣)。positions はマスの中心。戻り値 {"net_id","manholes":[id...]}
func spawn_manhole_net(positions: Array, origin: String = "initial", opts: Dictionary = {}) -> Dictionary:
	var net: int = next_id
	var ids: Array = []
	for v: Variant in positions:
		var p: Vector2 = v
		ids.append(spawn("manhole", Grid.center_of_cell(Grid.cell_of_pos(p)), origin, _merge(opts, {"net_id": net})))
	return {"net_id": net, "manholes": ids}

## 開いているマンホールのマスか(crop_system.manhole_check に接続される)。
func is_open_manhole_cell(cell: Vector2i) -> bool:
	for e: Dictionary in enemies:
		if e.alive and e.kind == "manhole" and Grid.cell_of_pos(e.pos) == cell:
			return true
	return false

# ---- ガラスジカの初期配置の抽選
const GLASS_CHANCE: float = 0.05

## 候補地点ごとに専用の乱数(世界の種・地域・候補の番号から作る)で5%の抽選をし、地域あたり最大1頭。
## 追加コンテンツ共通の乱数は使わない。同じ種・同じ地域なら結果は常に同じ(記録は glass_rolls に残り、保存される)。
## 戻り値は当たった候補の番号(なければ -1)。
func roll_glass_deer_region(world_seed: int, region_key: String, candidates: Array) -> int:
	if glass_rolls.has(region_key):
		return int(glass_rolls[region_key])
	glass_seed = world_seed
	var chance: float = float(defs.get("glass_deer", {}).get("params", {}).get("chance", GLASS_CHANCE))
	var hit: int = -1
	for i: int in range(candidates.size()):
		var rr: RandomNumberGenerator = RandomNumberGenerator.new()
		rr.seed = ("%d|%s|%d" % [world_seed, region_key, i]).hash()
		if rr.randf() < chance:
			hit = i
			break
	glass_rolls[region_key] = hit
	return hit

## 初期配置: regions = {地域キー: [候補地点(Vector2)...]}。当たった地点にガラスジカを出し、敵IDの配列を返す。
func place_glass_deer(world_seed: int, regions: Dictionary, opts: Dictionary = {}) -> Array:
	var ids: Array = []
	for k: Variant in regions.keys():
		var cands: Array = regions[k]
		var hit: int = roll_glass_deer_region(world_seed, str(k), cands)
		if hit >= 0 and hit < cands.size():
			ids.append(spawn("glass_deer", Vector2(cands[hit]), "initial", opts))
	return ids

# ---------------------------------------------------------------- 保存
func _enc(v: Variant) -> Variant:
	match typeof(v):
		TYPE_VECTOR2:
			var a: Vector2 = v
			return {"_v": [a.x, a.y]}
		TYPE_VECTOR2I:
			var b: Vector2i = v
			return {"_vi": [b.x, b.y]}
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for k: Variant in (v as Dictionary):
				out[str(k)] = _enc(v[k])
			return out
		TYPE_ARRAY:
			var arr: Array = []
			for x: Variant in (v as Array):
				arr.append(_enc(x))
			return arr
	return v

func _dec(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var d: Dictionary = v
			if d.size() == 1 and d.has("_v") and typeof(d["_v"]) == TYPE_ARRAY and (d["_v"] as Array).size() == 2:
				return Vector2(float(d["_v"][0]), float(d["_v"][1]))
			if d.size() == 1 and d.has("_vi") and typeof(d["_vi"]) == TYPE_ARRAY and (d["_vi"] as Array).size() == 2:
				return Vector2i(int(d["_vi"][0]), int(d["_vi"][1]))
			var out: Dictionary = {}
			for k: Variant in d:
				out[k] = _dec(d[k])
			return out
		TYPE_ARRAY:
			var arr: Array = []
			for x: Variant in (v as Array):
				arr.append(_dec(x))
			return arr
	return v

func _fix_ints(d: Dictionary) -> void:
	for k: String in INT_KEYS:
		if d.has(k):
			d[k] = int(d[k])

func to_dict() -> Dictionary:
	var sl: Array = []
	for k: Variant in slime.keys():
		var c: Vector2i = k
		var r: Dictionary = slime[c]
		sl.append([c.x, c.y, r.until, r.since, r.ground_sent])
	return {"time": time, "next_id": next_id, "next_crop_tick": next_crop_tick,
		"enemies": _enc(enemies), "projectiles": _enc(projectiles), "gas": _enc(gas), "piles": _enc(piles), "slime": sl,
		"odor": _enc(odor), "acid": _enc(acid), "glass_seed": str(glass_seed), "glass_rolls": glass_rolls.duplicate()}

func _fail(msg: String) -> bool:
	last_error = msg
	return false

func _isnum(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

## 値の型が見本と合うか(数値はint/float同一視、見本がnullなら不問)。
func _type_ok(v: Variant, tmpl: Variant) -> bool:
	if tmpl == null:
		return true
	if _isnum(tmpl):
		return _isnum(v)
	return typeof(v) == typeof(tmpl)

## 見本(同じ種類を1体出して得た辞書)の全キーが入っていて型が合うか。余分なキーは許す。
func _shape_ok(d: Dictionary, tmpl: Dictionary) -> bool:
	for k: Variant in tmpl:
		if not d.has(k) or not _type_ok(d[k], tmpl[k]):
			return false
	return true

## 種類ごとの見本。作業用の EnemySystem で実際に出して作る(手書きの一覧を持たない)。
func _enemy_template(kind: String, e: Dictionary, cache: Dictionary) -> Dictionary:
	if cache.has(kind):
		return cache[kind]
	var rr: RandomNumberGenerator = RandomNumberGenerator.new()
	rr.seed = 1
	var w: RefCounted = (get_script() as GDScript).new(host, rr, crops, defs)
	var id: int = w.spawn(kind, e.pos, "initial", {"tier": str(e.get("tier", "near"))})
	cache[kind] = (w.get_enemy(id) if id >= 0 else {}).duplicate(true)
	return cache[kind]

## 検証してから採用する。失敗時は状態を変えない。
func from_dict(d: Dictionary) -> bool:
	last_error = ""
	for k: String in ["time", "next_id", "next_crop_tick"]:
		if not d.has(k) or not _isnum(d[k]):
			return _fail("missing " + k)
	for k: String in ["enemies", "projectiles", "gas", "piles", "slime", "odor", "acid"]:
		if typeof(d.get(k)) != TYPE_ARRAY:
			return _fail("bad container " + k)
	if typeof(d.get("glass_seed")) != TYPE_STRING or not (d.glass_seed as String).is_valid_int() or typeof(d.get("glass_rolls")) != TYPE_DICTIONARY:
		return _fail("bad glass state")
	var new_rolls: Dictionary = {}
	for rk: Variant in (d.glass_rolls as Dictionary):
		if typeof(rk) != TYPE_STRING or not _isnum((d.glass_rolls as Dictionary)[rk]):
			return _fail("bad glass roll")
		new_rolls[str(rk)] = int((d.glass_rolls as Dictionary)[rk])
	var new_en: Array = []
	var new_by: Dictionary = {}
	var tcache: Dictionary = {}
	for raw: Variant in d.enemies:
		if typeof(raw) != TYPE_DICTIONARY:
			return _fail("enemy not dict")
		var e: Dictionary = _dec(raw)
		if not e.has("kind") or not defs.has(str(e.kind)) or not e.has("pos") or typeof(e.pos) != TYPE_VECTOR2:
			return _fail("bad enemy")
		for k: String in ["id", "hp", "until"]:
			if not e.has(k) or not _isnum(e[k]):
				return _fail("bad enemy field " + k)
		for k: String in ["home", "face", "flee_from", "wp"]:
			if typeof(e.get(k)) != TYPE_VECTOR2:
				return _fail("bad enemy vec " + k)
		var tmpl: Dictionary = _enemy_template(str(e.kind), e, tcache)
		if tmpl.is_empty() or not _shape_ok(e, tmpl):
			return _fail("enemy keys/types mismatch " + str(e.kind))
		_fix_ints(e)
		e.last_cell = Grid.cell_of_pos(e.pos)
		if not beh(e).validate(self, e):
			return _fail("enemy nested state invalid " + str(e.kind))
		if new_by.has(e.id):
			return _fail("duplicate id")
		new_en.append(e)
		new_by[e.id] = e
	var new_pr: Array = _dec(d.projectiles)
	var new_gas: Array = _dec(d.gas)
	var new_piles: Array = _dec(d.piles)
	var proj_t: Dictionary = {"kind": "", "owner": 0, "pos": Vector2.ZERO, "dir": Vector2.ZERO, "speed": 0.0, "left": 0.0, "damage": 0.0}
	var gas_t: Dictionary = {"pos": Vector2.ZERO, "owner": 0, "radius": 0.0, "until": 0.0, "dps": 0.0, "next_tick": 0.0}
	var pile_t: Dictionary = {"id": 0, "pos": Vector2.ZERO, "stock": 0, "hp": 0.0, "max_hp": 0.0}
	for p: Variant in new_pr:
		if typeof(p) != TYPE_DICTIONARY or not _shape_ok(p, proj_t):
			return _fail("bad projectile")
		_fix_ints(p)
	for g: Variant in new_gas:
		if typeof(g) != TYPE_DICTIONARY or not _shape_ok(g, gas_t):
			return _fail("bad gas")
		_fix_ints(g)
	for p2: Variant in new_piles:
		if typeof(p2) != TYPE_DICTIONARY or not _shape_ok(p2, pile_t):
			return _fail("bad pile")
		_fix_ints(p2)
	var new_odor: Array = _dec(d.odor)
	var new_acid: Array = _dec(d.acid)
	var odor_t: Dictionary = {"pos": Vector2.ZERO, "dir": Vector2.ZERO, "owner": 0, "until": 0.0, "length": 0.0, "half_deg": 0.0, "next_tick": 0.0}
	var acid_t: Dictionary = {"pos": Vector2.ZERO, "owner": 0, "radius": 0.0, "until": 0.0, "dps": 0.0, "next_tick": 0.0}
	for o: Variant in new_odor:
		if typeof(o) != TYPE_DICTIONARY or not _shape_ok(o, odor_t):
			return _fail("bad odor")
		_fix_ints(o)
	for a: Variant in new_acid:
		if typeof(a) != TYPE_DICTIONARY or not _shape_ok(a, acid_t):
			return _fail("bad acid")
		_fix_ints(a)
	var new_slime: Dictionary = {}
	for s: Variant in d.slime:
		if typeof(s) != TYPE_ARRAY or (s as Array).size() != 5 or not _isnum(s[0]) or not _isnum(s[1]) or not _isnum(s[2]) or not _isnum(s[3]):
			return _fail("bad slime")
		new_slime[Vector2i(int(s[0]), int(s[1]))] = {"until": float(s[2]), "since": float(s[3]), "ground_sent": bool(s[4])}
	time = float(d.time)
	next_id = int(d.next_id)
	next_crop_tick = float(d.next_crop_tick)
	enemies = new_en
	_by_id = new_by
	projectiles = new_pr
	gas = new_gas
	piles = new_piles
	slime = new_slime
	odor = new_odor
	acid = new_acid
	glass_seed = int((d.glass_seed as String).to_int())
	glass_rolls = new_rolls
	return true
