class_name DemoTerrain
extends Node2D
## Decorative ground, never the future simulation grid or greening target set.
const TILE: int = 16
const SIZE: Vector2i = Vector2i(80, 50)
var ground_texture: ImageTexture

func _ready() -> void:
	var image: Image = LandscapeArt.canvas(SIZE.x * TILE, SIZE.y * TILE)
	image.fill(Color("345f48"))
	LandscapeArt.oval(image, Vector2i(460, 370), Vector2i(290, 185), Color("64834d"), 4)
	LandscapeArt.oval(image, Vector2i(452, 385), Vector2i(226, 136), Color("87a45d"), 4)
	LandscapeArt.oval(image, Vector2i(390, 392), Vector2i(170, 89), Color("9bb567"), 4)
	LandscapeArt.oval(image, Vector2i(580, 276), Vector2i(146, 63), Color("78995b"), 4)
	LandscapeArt.oval(image, Vector2i(281, 300), Vector2i(109, 71), Color("55754b"), 4)
	LandscapeArt.oval(image, Vector2i(340, 510), Vector2i(165, 66), Color("557b4e"), 4)
	LandscapeArt.polygon(image, [Vector2i(326, 610), Vector2i(380, 495), Vector2i(421, 412), Vector2i(446, 356), Vector2i(451, 314), Vector2i(539, 253), Vector2i(587, 202), Vector2i(616, 211), Vector2i(562, 278), Vector2i(484, 330), Vector2i(483, 367), Vector2i(457, 429), Vector2i(419, 510), Vector2i(377, 622)], Color("b1ac75"))
	LandscapeArt.oval(image, Vector2i(471, 370), Vector2i(48, 31), Color("b1ac75"), 2)
	var stream: Array[Vector2i] = [Vector2i(716, 0), Vector2i(732, 150), Vector2i(687, 232), Vector2i(651, 285), Vector2i(662, 338), Vector2i(724, 418), Vector2i(775, 482), Vector2i(799, 554), Vector2i(768, 666), Vector2i(730, 800), Vector2i(834, 800), Vector2i(863, 673), Vector2i(884, 554), Vector2i(853, 465), Vector2i(800, 399), Vector2i(735, 321), Vector2i(728, 292), Vector2i(774, 239), Vector2i(811, 157), Vector2i(792, 0)]
	var bank: Array[Vector2i] = []
	for point: Vector2i in stream:
		bank.append(point + Vector2i(-8, 8))
	LandscapeArt.polygon(image, bank, Color("2e5547"))
	LandscapeArt.polygon(image, stream, Color("39869a"))
	LandscapeArt.polygon(image, [Vector2i(739, 152), Vector2i(705, 235), Vector2i(674, 291), Vector2i(684, 332), Vector2i(751, 414), Vector2i(800, 492), Vector2i(821, 554), Vector2i(795, 661), Vector2i(773, 751), Vector2i(808, 740), Vector2i(840, 553), Vector2i(817, 483), Vector2i(767, 405), Vector2i(702, 327), Vector2i(699, 293), Vector2i(735, 243), Vector2i(763, 160)], Color("4fa6b0"))
	LandscapeArt.polygon(image, [Vector2i(638, 278), Vector2i(651, 285), Vector2i(662, 338), Vector2i(681, 362), Vector2i(669, 362), Vector2i(650, 340)], Color("7c8d60"))
	LandscapeArt.polygon(image, [Vector2i(714, 408), Vector2i(724, 418), Vector2i(775, 482), Vector2i(764, 482), Vector2i(720, 430)], Color("8ca16b"))
	for patch: Vector2i in [Vector2i(254, 375), Vector2i(312, 448), Vector2i(370, 337), Vector2i(540, 420), Vector2i(590, 330), Vector2i(605, 457), Vector2i(483, 279), Vector2i(275, 492)]:
		for index: int in 13:
			var x: int = patch.x + (index * 17) % 58
			var y: int = patch.y + (index * 11) % 28
			var hue: Color = Color("749650") if index % 3 else Color("b5c777")
			LandscapeArt.box(image, x, y, 2, 4, hue)
			LandscapeArt.box(image, x + 3, y + 2, 2, 3, hue)
	for index: int in 18:
		var x: int = 683 + (index * 37) % 85
		var y: int = 224 + index * 13
		if x > 712 + (y - 338) / 2 and y > 338:
			LandscapeArt.box(image, x, y, 12, 1, Color("8ac9c3"))
		elif y < 328 and x > 696:
			LandscapeArt.box(image, x, y, 10, 1, Color("8ac9c3"))
	for stone: Vector2i in [Vector2i(430, 429), Vector2i(460, 335), Vector2i(523, 278), Vector2i(392, 480)]:
		LandscapeArt.box(image, stone.x, stone.y, 5, 2, Color("c4bf8d"))
	ground_texture = ImageTexture.create_from_image(image)
	queue_redraw()

func _draw() -> void:
	if ground_texture != null:
		draw_texture(ground_texture, Vector2.ZERO)
