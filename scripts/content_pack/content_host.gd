extends RefCounted
## ホスト(ゲーム側)への接続口の基底。既定値は「何もない世界」。
## ゲーム側または仮アダプター(lab/lab_host.gd)が継承して上書きする。
## 位置は論理px(1マス=4px)、マスは Vector2i。

func in_bounds(_cell: Vector2i) -> bool:
	return false

func is_explored(_cell: Vector2i) -> bool:
	return true

## 歩行可能な地面か(水面・建物・ガラクタ置き場などは false)
func is_walkable(_cell: Vector2i) -> bool:
	return false

func is_building(_cell: Vector2i) -> bool:
	return false

## 水面(深い水・浅瀬・清水を含む)
func is_water(_cell: Vector2i) -> bool:
	return false

func is_clean_water(_cell: Vector2i) -> bool:
	return false

func is_shade(_cell: Vector2i) -> bool:
	return false

## 緑化済みの段階か(荒地・種・芽は false)
func is_green(_cell: Vector2i) -> bool:
	return false

## 栽培植物以外が占有しているか(おたすけ植物、ガラクタ置き場、巣など)
func is_blocked(_cell: Vector2i) -> bool:
	return false

## 共通基盤の成長倍率(PoC3: 未給水は0.5、給水済みは1.0)。crop は株のDictionary。
func growth_multiplier(_crop: Dictionary) -> float:
	return 1.0

## 設置費。family_count は価格系統ごとの現存数。式はホストの責任。
func price(_kind: String, _family_count: int) -> int:
	return 0

func is_day() -> bool:
	return true

## {"pos":Vector2,"hp":float,"max_hp":float,"aim":Vector2(省略可。照準方向)}。いなければ空。
func hero() -> Dictionary:
	return {}

## [{"id":int,"pos":Vector2,"hp":float,"max_hp":float}]
func helpers() -> Array:
	return []

## 新たに播種できる有効マスか(PoC3の範囲播種の条件)。水面・建物・歩けないマス・ブロックされたマス・種や草のあるマスは除く。
## 植物の占有は植物側が別に除く。仮アダプターもこの既定を写す。
func is_seedable_cell(cell: Vector2i) -> bool:
	if not in_bounds(cell) or not is_walkable(cell) or is_water(cell) or is_building(cell) or is_blocked(cell):
		return false
	return grass_stage(cell) == "wasteland"

## そのマスが給水済みか(草の給水。ヘチマが未給水の草を探すときに使う)
func is_cell_watered(_cell: Vector2i) -> bool:
	return false

## ホスト側の敵(既存のバッタなど、追加コンテンツの外にある敵)。[{"id":Variant,"pos":Vector2,"neutral":bool,"tags":Array}]
## tags に "herbivore" を含めれば、リンゴの落果の引き寄せ判定(crops.nearest_attracting_fruit)の対象になる。
## オジギソウ・ホウセンカの近接判定にも使われる。
func host_enemies() -> Array:
	return []

## 受粉するハチの巣。[{"cell":Vector2i,"size":Vector2i(省略可),"active":bool(省略可)}]
func pollinators() -> Array:
	return []

## 草の段階(敵用)。"wasteland"(荒地) / "seed"(種) / "sprout"(芽) / "grass"(成熟した草)。
## 既定は is_green から導く(緑化済みなら "grass")。
func grass_stage(cell: Vector2i) -> String:
	return "grass" if is_green(cell) else "wasteland"

## 安定した地域のマスか(敵は入らない。飛ぶ敵も上空に入らない)
func is_stable_cell(_cell: Vector2i) -> bool:
	return false

## a から b への視線が建物で遮られないか。既定は建物マスの走査。ホストが経路判定へ置き換えてよい。
func line_clear(a: Vector2, b: Vector2) -> bool:
	var d: float = a.distance_to(b)
	var n: int = int(ceil(d / 2.0))
	for i: int in range(1, n):
		var p: Vector2 = a.lerp(b, float(i) / float(n))
		if is_building(Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))):
			return false
	return true

## 固定巣(アリ塚など)が活動してよいか。統合時はここだけを共通基盤の巣の規則(主人公の接近・緑化)へ差し替える。
## 確認画面用の簡易判定: 主人公が NEST_NEAR_PX 以内、または巣の周辺 NEST_GREEN_CELLS マス以内に緑地がある。
const NEST_NEAR_PX: float = 200.0
const NEST_GREEN_CELLS: int = 8

func nest_active(pos: Vector2, _kind: String) -> bool:
	var h: Dictionary = hero()
	if not h.is_empty() and Vector2(h.pos).distance_to(pos) <= NEST_NEAR_PX:
		return true
	var c0: Vector2i = Vector2i(floori(pos.x / 4.0), floori(pos.y / 4.0))
	for dy: int in range(-NEST_GREEN_CELLS, NEST_GREEN_CELLS + 1):
		for dx: int in range(-NEST_GREEN_CELLS, NEST_GREEN_CELLS + 1):
			var c: Vector2i = c0 + Vector2i(dx, dy)
			if in_bounds(c) and is_green(c):
				return true
	return false
