class_name EnemyArt
extends RefCounted
## Temporary flat-colour art of P2-01 (no outline): the nest mound. The boar uses the existing PixelArt.boar().

static var _nest: ImageTexture
static var _nest_ruin: ImageTexture
static var _corpse: ImageTexture
static var _bone: ImageTexture

## Colours of the carcass / bone / ruin art (flat, no outline).
const PALETTE: Dictionary = {
	"B": Color("795c58"), "b": Color("9c7469"), "t": Color("b08e78"), "d": Color("3d5149"),
	"f": Color("f0eed5"), "s": Color("d8cfa9"), "e": Color("a08e72"), "g": Color("77bd77"),
}

const NEST_SIZE_PX: int = 16

## 16x16 nest (4x4 tiles): a mound of earth with a dark hollow and a few pale bone chips. The node position is its foot
## (bottom edge). No outline: the mound's edge is just the darker earth colour.
static func nest() -> ImageTexture:
	if _nest == null:
		var image: Image = Image.create(NEST_SIZE_PX, NEST_SIZE_PX, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		var earth: Color = Color("795c58")
		var earth_light: Color = Color("9c7469")
		var top: Color = Color("c49e80")
		var hollow: Color = Color("3d5149")
		var bone: Color = Color("f0eed5")
		for y: int in NEST_SIZE_PX:
			for x: int in NEST_SIZE_PX:
				var dx: float = (float(x) + 0.5 - 8.0) / 8.0
				var dy: float = (float(y) + 0.5 - 9.5) / 6.5
				var d: float = dx * dx + dy * dy
				if d > 1.0:
					continue
				var color: Color = earth if d > 0.72 else (earth_light if d > 0.4 else top)
				image.set_pixel(x, y, color)
		for y: int in range(7, 11):
			for x: int in range(5, 11):
				var hx: float = (float(x) + 0.5 - 8.0) / 3.0
				var hy: float = (float(y) + 0.5 - 9.0) / 2.0
				if hx * hx + hy * hy <= 1.0:
					image.set_pixel(x, y, hollow)
		for spot: Vector2i in [Vector2i(3, 9), Vector2i(12, 8), Vector2i(10, 12), Vector2i(5, 12)]:
			image.set_pixel(spot.x, spot.y, bone)
		_nest = ImageTexture.create_from_image(image)
	return _nest

static func _build(rows: PackedStringArray) -> ImageTexture:
	var image: Image = Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y: int in rows.size():
		for x: int in rows[y].length():
			var key: String = rows[y].substr(x, 1)
			if PALETTE.has(key):
				image.set_pixel(x, y, PALETTE[key])
	return ImageTexture.create_from_image(image)

## 14x8 carcass: a boar lying on its side, flat colours, two pale tusk pixels and a sprig of green growing from the back.
## The node position is its foot (bottom edge, middle).
static func corpse() -> ImageTexture:
	if _corpse == null:
		_corpse = _build(PackedStringArray([
			"......g.......", ".....gg.......", "...BBBgBBBB...", "..BbbbbbbbbBB.",
			".BbbbbbbbbbbbB", ".BbbbbbbbbbbBf", "..BBbbbbbbBBBf", "...d.d..d.d...",
		]))
	return _corpse

## 10x6 bones: a few pale bone pieces and a small skull, scattered.
static func bone() -> ImageTexture:
	if _bone == null:
		_bone = _build(PackedStringArray([
			"..........", ".f.....ss.", "..ff..ssss", "...fffs.s.", ".ss..ff...", "s..s...f..",
		]))
	return _bone

## 16x16 ruin of a destroyed nest (4x4 tiles): a low flat heap of loose earth with a few pale bone chips; the hollow is gone.
static func nest_ruin() -> ImageTexture:
	if _nest_ruin == null:
		var image: Image = Image.create(NEST_SIZE_PX, NEST_SIZE_PX, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		var earth: Color = Color("795c58")
		var earth_light: Color = Color("9c7469")
		var top: Color = Color("b08e78")
		var bone_color: Color = Color("f0eed5")
		for y: int in NEST_SIZE_PX:
			for x: int in NEST_SIZE_PX:
				var dx: float = (float(x) + 0.5 - 8.0) / 7.5
				var dy: float = (float(y) + 0.5 - 11.0) / 3.5
				var d: float = dx * dx + dy * dy
				if d > 1.0:
					continue
				var color: Color = earth if d > 0.75 else (earth_light if d > 0.35 else top)
				if (x * 7 + y * 3) % 5 == 0 and d < 0.9:
					color = earth_light if color == top else top
				image.set_pixel(x, y, color)
		for spot: Vector2i in [Vector2i(4, 11), Vector2i(8, 9), Vector2i(11, 12), Vector2i(7, 13)]:
			image.set_pixel(spot.x, spot.y, bone_color)
		_nest_ruin = ImageTexture.create_from_image(image)
	return _nest_ruin
