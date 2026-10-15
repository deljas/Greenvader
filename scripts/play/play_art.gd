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

## 4x4 seed fruit of a mature plant (P1-06): a pale-pink top over a rose-red middle and a dark crimson base. Colours and
## brightness are chosen so it stays readable on mature green (3f9b4a), sprout green, sand and wasteland ground (bright
## and dark pixels both differ in brightness from the green; the hue is far from green and sand), and it is clearly not
## the seed source's warm yellow fruit nor the kiwi's brown-and-green healing fruit. No outline.
static func plant_fruit() -> ImageTexture:
	if _plant_fruit == null:
		_plant_fruit = _build(PackedStringArray([".ww.", "wwwr", "rRRR", ".RR."]))
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

# ---- P1-05: cultivated plants (8x8 = 2x2 tiles) and the healing fruit ------------------------------------------

## Colours of the cultivated plant art (flat, no outline). Letters are used by the row strings below.
const CULTIVATED_PALETTE: Dictionary = {
	"g": Color("77bd77"), "G": Color("408863"), "l": Color("badc83"),
	"o": Color("f09a4a"), "O": Color("c9692f"), "b": Color("9c7469"), "B": Color("795c58"),
	"k": Color("a8d65a"), "K": Color("6fa83a"),
	"w": Color("ffd6de"), "r": Color("e4566b"), "R": Color("a82746"),
}

static var _cultivated: Dictionary = {}
static var _heal_fruit: ImageTexture

static func _build(rows: PackedStringArray) -> ImageTexture:
	var image: Image = Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y: int in rows.size():
		for x: int in rows[y].length():
			var key: String = rows[y].substr(x, 1)
			if CULTIVATED_PALETTE.has(key):
				image.set_pixel(x, y, CULTIVATED_PALETTE[key])
	return ImageTexture.create_from_image(image)

## 8x8 art of a cultivated plant: `key` is the PlantDef key, `mature` the stage. Unknown keys get a plain sprout
## so a new data-only plant still shows something. The node position of the sprite is its foot (bottom).
static func cultivated(key: StringName, mature: bool) -> ImageTexture:
	var id: String = "%s_%s" % [key, "mature" if mature else "young"]
	if not _cultivated.has(id):
		var rows: PackedStringArray
		match key:
			&"carrot":
				rows = PackedStringArray(["..g..g..", ".gGg.gg.", "..gGgg..", "...gg...", "..oooo..", "..oooO..", "...oO...", "....O..."]) if mature else PackedStringArray(["........", "........", "...g.g..", "....g...", "...GG...", "...oo...", "....O...", "........"])
			&"kiwi":
				rows = PackedStringArray(["..gggg..", ".gGgGgg.", "gggbbggg", "gGbbbbgG", ".gbbbbg.", ".ggbbgg.", "..GggG..", "...GG..."]) if mature else PackedStringArray(["........", "........", "...gg...", "..gGgg..", "...gG...", "...GG...", "...GG...", "........"])
			_:
				rows = PackedStringArray(["..l..l..", "..lGGl..", "...GG...", "...GG...", "..GGGG..", "........", "........", "........"]) if mature else PackedStringArray(["........", "........", "........", "...ll...", "...GG...", "...GG...", "........", "........"])
		_cultivated[id] = _build(rows)
	return _cultivated[id]

## 4x4 healing fruit (kiwi coloured: brown skin, green flesh). Anchored by its centre like the seed fruits.
static func heal_fruit() -> ImageTexture:
	if _heal_fruit == null:
		_heal_fruit = _build(PackedStringArray([".bb.", "bkKb", "bKkb", ".bb."]))
	return _heal_fruit

static var _flower_down: ImageTexture

## The player's flower lying on its side (P2-03): the standing sprite turned a quarter, so every pixel stays a whole pixel.
## The node using it is drawn dimmed (a modulate, no outline).
static func flower_down() -> ImageTexture:
	if _flower_down == null:
		var image: Image = PixelArt.flower().get_image()
		image.rotate_90(CLOCKWISE)
		_flower_down = ImageTexture.create_from_image(image)
	return _flower_down
