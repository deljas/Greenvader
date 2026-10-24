extends RefCounted
## data/content_pack/*.json を読む。数値は仮値で、ここでは解釈しない。
## 第2弾の共通: 草食タグ(リンゴの落果に引き寄せられる)
const TAG_HERBIVORE: String = "herbivore"
const CROPS_PATH: String = "res://data/content_pack/crops.json"

static func load_json(path: String) -> Variant:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())

## 種類ID -> 定義Dictionary
static func load_crops() -> Dictionary:
	var d: Variant = load_json(CROPS_PATH)
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	var dd: Dictionary = d
	return dd.get("crops", {})

const ENEMIES_PATH: String = "res://data/content_pack/enemies.json"

## 敵の種類ID -> 定義Dictionary
static func load_enemies() -> Dictionary:
	var d: Variant = load_json(ENEMIES_PATH)
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	var dd: Dictionary = d
	return dd.get("enemies", {})
