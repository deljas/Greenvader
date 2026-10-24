extends RefCounted
## 種類ごとの行動の既定(静的関数)。各種類はこれを継承して必要な関数だけ上書きする。
## s は enemy_system、e は敵のDictionary(種類固有の値もこの中へ直接置く。JSONで往復できる値だけ)。

static func init(_s: RefCounted, _e: Dictionary, _opts: Dictionary) -> void:
	pass

static func update(_s: RefCounted, _e: Dictionary, _dt: float, _ev: Array[Dictionary]) -> void:
	pass

## 現在の分類タグ(状態によって変わる種類は上書き)
static func tags(s: RefCounted, e: Dictionary) -> Array:
	return s.def_of(e).get("tags", [])

## 射撃が当たるか(飛行中・潜行中は false)
static func hittable(_s: RefCounted, _e: Dictionary) -> bool:
	return true

## 擬態中か(検知の対象外)
static func hidden(_s: RefCounted, _e: Dictionary) -> bool:
	return false

## 擬態中に動いていて「揺れ・揺らぎ」記号だけが見える状態か
static func hint(_s: RefCounted, _e: Dictionary) -> bool:
	return false

static func damage_mult(_s: RefCounted, _e: Dictionary, _kind: String, _from: Variant) -> float:
	return 1.0

## 実際にHPへ入るダメージ(殻など、倍率以外の扱いは上書き)
static func calc_damage(s: RefCounted, e: Dictionary, amount: float, kind: String, from: Variant, _ev: Array[Dictionary]) -> float:
	return amount * float(s.beh(e).damage_mult(s, e, kind, from))

static func on_hit(_s: RefCounted, _e: Dictionary, _kind: String, _from: Variant, _dealt: float, _ev: Array[Dictionary]) -> void:
	pass

static func on_water(_s: RefCounted, _e: Dictionary, _ev: Array[Dictionary]) -> void:
	pass

static func on_seed(_s: RefCounted, _e: Dictionary, _pos: Vector2, _ev: Array[Dictionary]) -> void:
	pass

static func on_defeat(_s: RefCounted, _e: Dictionary, _ev: Array[Dictionary]) -> void:
	pass

## トウガラシの反撃で逃げ始めるとき、行動中の状態を捨てる
static func on_flee(s: RefCounted, e: Dictionary) -> void:
	e.state = "idle"
	e.until = s.time

# ---- 第2弾の追加フック
## マップ・画面の検知に出す位置。null なら出さない(地中のネッコモグラは盛り土の位置)。
static func detect_pos(_s: RefCounted, e: Dictionary) -> Variant:
	return e.pos

## 地域安定の判定に数えるか(閉じたマンホールは数えない)
static func counts(_s: RefCounted, _e: Dictionary) -> bool:
	return true

## 当たらない状態の敵の近くに水が当たった(pos と radius は着弾の中心・半径px)。地中のネッコモグラが追い出される。
static func on_water_near(_s: RefCounted, _e: Dictionary, _pos: Vector2, _radius: float, _ev: Array[Dictionary]) -> void:
	pass

## 保存の復元時に、種類ごとの入れ子の値(盛り土の列など)と状態名を検証する。見本照合の後に呼ぶ。
static func validate(_s: RefCounted, _e: Dictionary) -> bool:
	return true
