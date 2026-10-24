extends RefCounted
## 仮スプライトの読込部品。data/content_pack/sprites.json を読み、PNGを実行時に Image.load_from_file → ImageTexture にする。
## .import やエディタのimportを前提にしない。統合時もこのまま使える(確認画面専用の処理は含まない)。
const Defs: GDScript = preload("res://scripts/content_pack/content_defs.gd")
const META_PATH: String = "res://data/content_pack/sprites.json"
const DIR: String = "res://assets/content_pack/"

var meta: Dictionary = {}
var _tex: Dictionary = {}
var _gray: Dictionary = {}
var _img: Dictionary = {}
var missing: Array = []

func _init() -> void:
	var d: Variant = Defs.load_json(META_PATH)
	if typeof(d) == TYPE_DICTIONARY:
		meta = (d as Dictionary).get("sprites", {})

func has(name: String) -> bool:
	return meta.has(name)

func names() -> Array:
	return meta.keys()

func size_of(name: String) -> Vector2i:
	var a: Array = meta.get(name, {}).get("size", [8, 8])
	return Vector2i(int(a[0]), int(a[1]))

## 足元基準(画像内px)。既定は中央下。
func foot_of(name: String) -> Vector2:
	var m: Dictionary = meta.get(name, {})
	if m.has("foot"):
		return Vector2(float(m.foot[0]), float(m.foot[1]))
	var s: Vector2i = size_of(name)
	return Vector2(float(s.x) * 0.5, float(s.y))

func image(name: String) -> Image:
	if _img.has(name):
		return _img[name]
	var m: Dictionary = meta.get(name, {})
	if m.is_empty():
		if not missing.has(name):
			missing.append(name)
		return null
	var im: Image = Image.load_from_file(DIR + str(m.file))
	if im == null:
		if not missing.has(name):
			missing.append(name)
		return null
	im.convert(Image.FORMAT_RGBA8)
	_img[name] = im
	return im

func tex(name: String) -> Texture2D:
	if _tex.has(name):
		return _tex[name]
	var im: Image = image(name)
	if im == null:
		return null
	var t: ImageTexture = ImageTexture.create_from_image(im)
	_tex[name] = t
	return t

## 灰色化(丸まり・ひっくり返り用)。状態別画像ではなく、実行時に同じ画像から作る。
func gray_tex(name: String) -> Texture2D:
	if _gray.has(name):
		return _gray[name]
	var im: Image = image(name)
	if im == null:
		return null
	var g: Image = im.duplicate()
	for y: int in range(g.get_height()):
		for x: int in range(g.get_width()):
			var c: Color = g.get_pixel(x, y)
			if c.a > 0.0:
				var l: float = c.r * 0.3 + c.g * 0.59 + c.b * 0.11
				g.set_pixel(x, y, Color(l * 0.95, l * 0.95, l, c.a))
	var t: ImageTexture = ImageTexture.create_from_image(g)
	_gray[name] = t
	return t
