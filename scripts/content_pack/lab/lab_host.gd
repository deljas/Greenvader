extends "res://scripts/content_pack/content_host.gd"
## 確認画面とテストが共用する仮アダプター。固定の小区画(64x36マス)を持つ。
## 成長倍率はPoC3の写し(未給水0.5、給水済み1.0)、価格は ceil(基本 x 1.05^n)、昼夜は手動切替。
const Defs: GDScript = preload("res://scripts/content_pack/content_defs.gd")

const W: int = 64
const H: int = 36
const GREEN: int = 0
const WASTE: int = 1
const BUILDING: int = 2
const WATER: int = 3
const SHALLOW: int = 4
const CLEAN: int = 5
const JUNK: int = 6

var terrain: PackedByteArray = PackedByteArray()
var shade: PackedByteArray = PackedByteArray()
var day: bool = true
var hero_state: Dictionary = {}
var helper_list: Array = []
var hive_list: Array = []
var blocked_cells: Dictionary = {}
var defs: Dictionary = {}
var stage_override: Dictionary = {}   # Vector2i -> "wasteland"/"seed"/"sprout"/"grass"
var stable_cells: Dictionary = {}     # Vector2i -> true

func _init() -> void:
	defs = Defs.load_crops()
	terrain.resize(W * H)
	shade.resize(W * H)
	_fill(Rect2i(2, 2, 12, 10), WATER)     # 普通の水 x2..13, y2..11
	_fill(Rect2i(14, 2, 2, 10), SHALLOW)   # 浅瀬 x14..15, y2..11
	_fill(Rect2i(2, 14, 5, 5), CLEAN)      # 清水 x2..6, y14..18
	_fill(Rect2i(7, 14, 2, 5), SHALLOW)    # 清水の隣の浅瀬 x7..8
	_fill(Rect2i(28, 14, 8, 6), BUILDING)  # 建物 x28..35, y14..19
	_fill(Rect2i(50, 6, 1, 1), JUNK)       # ガラクタ置き場
	_fill(Rect2i(52, 8, 1, 1), JUNK)
	_fill(Rect2i(44, 24, 12, 8), WASTE)    # 荒地 x44..55, y24..31
	for y: int in range(11, 14):           # 日陰: 建物の北 x28..35, y11..13
		for x: int in range(28, 36):
			shade[y * W + x] = 1

func _fill(r: Rect2i, t: int) -> void:
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			terrain[y * W + x] = t

func _t(c: Vector2i) -> int:
	return terrain[c.y * W + c.x]

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H

func is_walkable(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	var t: int = _t(c)
	return t == GREEN or t == WASTE

func is_building(c: Vector2i) -> bool:
	return in_bounds(c) and _t(c) == BUILDING

func is_water(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	var t: int = _t(c)
	return t == WATER or t == SHALLOW or t == CLEAN

func is_clean_water(c: Vector2i) -> bool:
	return in_bounds(c) and _t(c) == CLEAN

func is_shade(c: Vector2i) -> bool:
	return in_bounds(c) and shade[c.y * W + c.x] == 1

func is_green(c: Vector2i) -> bool:
	return in_bounds(c) and _t(c) == GREEN

func is_blocked(c: Vector2i) -> bool:
	return in_bounds(c) and (_t(c) == JUNK or blocked_cells.has(c))

func set_terrain(c: Vector2i, t: int) -> void:
	terrain[c.y * W + c.x] = t

func growth_multiplier(crop: Dictionary) -> float:
	return 1.0 if bool(crop.get("watered", false)) else 0.5

func price(kind: String, family_count: int) -> int:
	var base: float = float(defs.get(kind, {}).get("cost", 0))
	return int(ceil(base * pow(1.05, float(family_count)) - 1e-9))

func is_day() -> bool:
	return day

func hero() -> Dictionary:
	return hero_state

func helpers() -> Array:
	return helper_list

func pollinators() -> Array:
	return hive_list

func grass_stage(c: Vector2i) -> String:
	if stage_override.has(c):
		return str(stage_override[c])
	return "grass" if is_green(c) else "wasteland"

func set_stage(c: Vector2i, st: String) -> void:
	stage_override[c] = st

## 範囲播種の有効マス(PoC3の条件を写す): 歩ける・水面でも建物でもない・ブロックされていない・種や草のない(荒地)マス
func is_seedable_cell(c: Vector2i) -> bool:
	if not in_bounds(c) or not is_walkable(c) or is_water(c) or is_building(c) or is_blocked(c):
		return false
	return grass_stage(c) == "wasteland"

var watered_cells: Dictionary = {}    # Vector2i -> true (草の給水済み)
var host_enemy_list: Array = []       # ホスト側の敵([{"id","pos","neutral","tags"}])

func is_cell_watered(c: Vector2i) -> bool:
	return watered_cells.has(c)

func host_enemies() -> Array:
	return host_enemy_list

func is_stable_cell(c: Vector2i) -> bool:
	return stable_cells.has(c)

func set_stable_rect(r: Rect2i) -> void:
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			stable_cells[Vector2i(x, y)] = true
