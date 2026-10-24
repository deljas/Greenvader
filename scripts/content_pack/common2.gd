extends RefCounted
## 第2弾の共通状態(CONTENT_CATALOG_2 1.4 濡れたマス、気絶・仕事停止、1.6 報酬の即時加算)。
## ホストのデータは書き換えず、状態はこの中に持ち、出力はイベント。時間は advance(dt) で進めた分だけ(ポーズ中は進まない)。
##   wet_cell{cell,until}                         水の着弾マスが濡れた(6秒)
##   hero_stun{seconds,enemy_id}                  主人公の気絶(移動・攻撃・水やり不可)
##   helper_stop{helper_id,seconds,cause}         おたすけ植物の仕事停止(cause: stun / odor)
const WET_SECONDS: float = 6.0

var time: float = 0.0
var wet: Dictionary = {}              # Vector2i -> 濡れが消える時刻
var hero_stun_until: float = 0.0
var helper_stop: Dictionary = {}      # helper_id(int) -> 停止が終わる時刻
var last_error: String = ""

func advance(dt: float) -> void:
	if dt <= 0.0:
		return
	time += dt
	for k: Variant in wet.keys():
		if float(wet[k]) <= time:
			wet.erase(k)
	for k: Variant in helper_stop.keys():
		if float(helper_stop[k]) <= time:
			helper_stop.erase(k)

# ---------------------------------------------------------------- 濡れたマス
## 水(水やり・スプリンクラー)が着弾したマス。6秒間濡れ。重ねて当たれば6秒に延長。
func water_landed(cells: Array) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	for v: Variant in cells:
		var c: Vector2i = v
		var until: float = time + WET_SECONDS
		wet[c] = until
		ev.append({"type": "wet_cell", "cell": c, "until": until})
	return ev

func is_wet(cell: Vector2i) -> bool:
	return wet.has(cell) and float(wet[cell]) > time

func wet_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k: Variant in wet.keys():
		if float(wet[k]) > time:
			out.append(k)
	return out

# ---------------------------------------------------------------- 気絶・仕事停止
static func hero_stun_event(seconds: float, enemy_id: int) -> Dictionary:
	return {"type": "hero_stun", "seconds": seconds, "enemy_id": enemy_id}

static func helper_stop_event(helper_id: int, seconds: float, cause: String) -> Dictionary:
	return {"type": "helper_stop", "helper_id": helper_id, "seconds": seconds, "cause": cause}

## 窓口を通るイベントを見て状態を更新する(敵が出した気絶・停止を窓口が受け取る)
func note_events(evs: Array) -> void:
	for x: Variant in evs:
		var e: Dictionary = x
		match str(e.get("type", "")):
			"hero_stun":
				hero_stun_until = maxf(hero_stun_until, time + float(e.seconds))
			"helper_stop":
				var id: int = int(e.helper_id)
				helper_stop[id] = maxf(float(helper_stop.get(id, 0.0)), time + float(e.seconds))

func hero_stunned() -> bool:
	return hero_stun_until > time

func helper_stopped(helper_id: int) -> bool:
	return helper_stop.has(helper_id) and float(helper_stop[helper_id]) > time

# ---------------------------------------------------------------- 報酬の即時加算
## 撃破時に共通備蓄へ即時加算する報酬イベント。地面の拾い物は作らない。階級倍率は共通基盤が掛ける。
static func reward_event(enemy_id: int, kind: String, amount: int, tier: String, pos: Vector2) -> Dictionary:
	return {"type": "reward", "enemy_id": enemy_id, "kind": kind, "amount": amount, "tier": tier, "pos": pos, "instant": true}

# ---------------------------------------------------------------- 保存・復元
func to_dict() -> Dictionary:
	var w: Array = []
	for k: Variant in wet.keys():
		var c: Vector2i = k
		w.append([c.x, c.y, float(wet[k])])
	var hs: Array = []
	for k: Variant in helper_stop.keys():
		hs.append([int(k), float(helper_stop[k])])
	return {"time": time, "wet": w, "hero_stun_until": hero_stun_until, "helper_stop": hs}

func _isnum(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

func _fail(msg: String) -> bool:
	last_error = msg
	return false

func from_dict(d: Dictionary) -> bool:
	last_error = ""
	for k: String in ["time", "hero_stun_until"]:
		if not d.has(k) or not _isnum(d[k]):
			return _fail("missing " + k)
	if typeof(d.get("wet")) != TYPE_ARRAY or typeof(d.get("helper_stop")) != TYPE_ARRAY:
		return _fail("bad containers")
	var nw: Dictionary = {}
	for r: Variant in d.wet:
		if typeof(r) != TYPE_ARRAY or (r as Array).size() != 3 or not _isnum(r[0]) or not _isnum(r[1]) or not _isnum(r[2]):
			return _fail("bad wet")
		nw[Vector2i(int(r[0]), int(r[1]))] = float(r[2])
	var nh: Dictionary = {}
	for r: Variant in d.helper_stop:
		if typeof(r) != TYPE_ARRAY or (r as Array).size() != 2 or not _isnum(r[0]) or not _isnum(r[1]):
			return _fail("bad helper_stop")
		nh[int(r[0])] = float(r[1])
	time = float(d.time)
	hero_stun_until = float(d.hero_stun_until)
	wet = nw
	helper_stop = nh
	return true
