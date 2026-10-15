class_name EnemyArt
extends RefCounted
## Temporary flat-colour art of P2-01 (no outline): the nest mound. The boar uses the existing PixelArt.boar().

static var _nest: ImageTexture
static var _nest_ruin: ImageTexture

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
