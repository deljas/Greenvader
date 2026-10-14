class_name PixelArt
extends RefCounted
## Original temporary raster art. Every character is exactly one source pixel.

const PALETTE: Dictionary = {
	"p": Color("f6a8bf"), "P": Color("ef7299"), "y": Color("ffe5a0"),
	"g": Color("77bd77"), "G": Color("408863"), "l": Color("badc83"),
	"b": Color("9c7469"), "B": Color("795c58"), "t": Color("c49e80"),
	"e": Color("f7d5a0"), "s": Color("dcab72"), "w": Color("9fe3ed"),
	"W": Color("63b8cf"), "d": Color("3d5149"), "f": Color("f0eed5")
}

static func texture(rows: PackedStringArray) -> ImageTexture:
	var image: Image = Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y: int in rows.size():
		for x: int in rows[y].length():
			var key: String = rows[y].substr(x, 1)
			if PALETTE.has(key):
				image.set_pixel(x, y, PALETTE[key])
	return ImageTexture.create_from_image(image)

static func flower() -> ImageTexture:
	return texture([
		"................", "......pppp......", ".....ppPPpp.....", "..pppppyyppppp..",
		"..pPPpyyyypPPp..", "..ppppyyyypppp..", ".....ppPPpp.....", "......pppp......",
		".......GG.......", "...gg..GG..gg...", "....gggGGggg....", ".......GG.......",
		".......GG.......", "......G..G......", ".....GG..GG.....", "................"
	])

static func sprout() -> ImageTexture:
	return texture(["........", "........", ".ll..ll.", "..lGGl..", "...GG...", "...GG...", "..GGGG..", "........"])

static func mature() -> ImageTexture:
	return texture([
		"......lll.......", "....llgggll.....", "...lggllgggl....", "..lgglgglgggl...",
		"..lgggggggggl...", "...GgggggggG....", "....GGgggGG.....", "......GGG.......",
		"......GGG.......", "..gg..GGG..gg...", "...gggGGGggg....", "......GGG.......",
		"......GGG.......", ".....GGGGG......", "....GGGGGGG.....", "................"
	])

static func boar() -> ImageTexture:
	return texture([
		"................................", "................................",
		"....................tt....tt....", "...................tttt..tttt...",
		".......tttttttttttttttttttt.....", ".....ttttttttttttttttttttttt....",
		"....tttttttttttttttttttttttt....", "...tttttttttttttttttttetttttt...",
		"...ttttttttttttttttttttttttttt..", "...tttttttttttttttttttttttssst..",
		"...tttttttttttttttttttttttssst..", "....tttbbbbbbbbbbttttttttff....",
		".....ttttttttttttttttttttt......", "......BBBttttttttttttBBB........",
		"......BBB............BBB........", "......BBB............BBB........",
		"................................", "................................"
	])

static func seed() -> ImageTexture:
	# Highlight reaches the silhouette; shading is only on one lower face.
	return texture(["..yy..", ".yyys.", ".yyss.", "..ss.."])

static func water() -> ImageTexture:
	return texture(["..ww..", ".wwww.", "wwWWww", ".wwww."])

static func halo() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	var result: GradientTexture2D = GradientTexture2D.new()
	result.gradient = gradient
	result.width = 96
	result.height = 96
	result.fill = GradientTexture2D.FILL_RADIAL
	result.fill_from = Vector2(0.5, 0.5)
	result.fill_to = Vector2(1.0, 0.5)
	return result
