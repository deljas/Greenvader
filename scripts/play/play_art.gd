class_name PlayArt
extends RefCounted
## Temporary flat-colour art for P1-02 (no outlines): the seed source and the seed fruit.

static var _fruit: ImageTexture
static var _source: ImageTexture
static var _plant_fruit: ImageTexture

## 4x4 seed fruit: warm light top, one shaded lower face. Anchored by its centre.
static func fruit() -> ImageTexture:
	if _fruit == null:
		_fruit = PixelArt.texture([".yy.", "yyye", "yees", ".ss."])
	return _fruit

## 4x4 seed fruit of a mature plant: same shape, greener so it can be told from the source's fruit.
static func plant_fruit() -> ImageTexture:
	if _plant_fruit == null:
		_plant_fruit = PixelArt.texture([".ll.", "llyg", "lggG", ".GG."])
	return _plant_fruit

## 10x10 provisional seed source (pedestal with a glowing seed on top). The node position is its foot.
static func source() -> ImageTexture:
	if _source == null:
		_source = PixelArt.texture([
			"...eeee...", "..eyyyye..", "..eyyyye..", "...eeee...",
			"..tttttt..", ".tttttttt.", ".tttttttt.", ".tttttttts",
			".ssssssss.", "..........",
		])
	return _source
