class_name LandscapeArt
extends RefCounted
## Original scenery rasters. Integer primitives; no rescaling, contour or blur.
## These decorative trees and rocks are not simulation plants/greening targets.

static func canvas(width: int, height: int) -> Image:
	var result: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	return result

static func box(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	image.fill_rect(Rect2i(x, y, width, height), color)

static func oval(image: Image, center: Vector2i, radii: Vector2i, color: Color, step: int = 2) -> void:
	for y: int in range(-radii.y, radii.y + 1, step):
		var distance: float = float(y) / float(radii.y)
		var half_width: int = int(float(radii.x) * sqrt(maxf(0, 1.0 - distance * distance)))
		half_width = maxi(step, half_width - half_width % step)
		box(image, center.x - half_width, center.y + y, half_width * 2, step, color)

static func polygon(image: Image, points: Array[Vector2i], color: Color) -> void:
	var min_y: int = image.get_height()
	var max_y: int = 0
	for point: Vector2i in points:
		min_y = mini(min_y, point.y)
		max_y = maxi(max_y, point.y)
	for y: int in range(min_y, max_y):
		var intersections: Array[int] = []
		for index: int in points.size():
			var a: Vector2i = points[index]
			var b: Vector2i = points[(index + 1) % points.size()]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				intersections.append(roundi(a.x + float(y - a.y) * float(b.x - a.x) / float(b.y - a.y)))
		intersections.sort()
		for index: int in range(0, intersections.size() - 1, 2):
			box(image, intersections[index], y, intersections[index + 1] - intersections[index], 1, color)

static func tree(kind: int) -> ImageTexture:
	var image: Image = canvas(64, 84)
	box(image, 28, 44, 10, 35, Color("72664a"))
	box(image, 34, 46, 4, 32, Color("514f3d"))
	polygon(image, [Vector2i(28, 73), Vector2i(21, 82), Vector2i(30, 80), Vector2i(33, 71)], Color("72664a"))
	polygon(image, [Vector2i(36, 72), Vector2i(43, 81), Vector2i(35, 80)], Color("514f3d"))
	if kind == 0:
		polygon(image, [Vector2i(12, 9), Vector2i(23, 3), Vector2i(35, 8), Vector2i(44, 5), Vector2i(53, 15), Vector2i(60, 20), Vector2i(57, 31), Vector2i(63, 34), Vector2i(58, 43), Vector2i(50, 47), Vector2i(45, 55), Vector2i(27, 58), Vector2i(17, 52), Vector2i(10, 48), Vector2i(2, 37), Vector2i(5, 24), Vector2i(2, 20)], Color("35775a"))
		polygon(image, [Vector2i(35, 24), Vector2i(57, 29), Vector2i(63, 34), Vector2i(58, 43), Vector2i(50, 47), Vector2i(45, 55), Vector2i(29, 56), Vector2i(25, 47)], Color("24634f"))
		polygon(image, [Vector2i(12, 9), Vector2i(23, 3), Vector2i(35, 8), Vector2i(38, 17), Vector2i(32, 23), Vector2i(16, 25), Vector2i(8, 19)], Color("70a86d"))
		polygon(image, [Vector2i(44, 5), Vector2i(53, 15), Vector2i(60, 20), Vector2i(57, 28), Vector2i(42, 30), Vector2i(34, 24), Vector2i(35, 14)], Color("4f9366"))
		polygon(image, [Vector2i(5, 24), Vector2i(15, 23), Vector2i(21, 29), Vector2i(20, 37), Vector2i(12, 43), Vector2i(2, 37)], Color("589b68"))
		polygon(image, [Vector2i(22, 24), Vector2i(37, 20), Vector2i(44, 28), Vector2i(41, 38), Vector2i(29, 42), Vector2i(20, 34)], Color("438b62"))
		box(image, 15, 11, 10, 4, Color("8cb976"))
		box(image, 8, 24, 8, 4, Color("7ead70"))
		box(image, 34, 20, 10, 4, Color("74a970"))
		box(image, 37, 41, 12, 4, Color("286952"))
		box(image, 19, 36, 8, 4, Color("397f5b"))
	elif kind == 1:
		for tier: int in 3:
			var top: int = 2 + tier * 15
			var bottom: int = 35 + tier * 16
			var width: int = 15 + tier * 7
			polygon(image, [Vector2i(31, top), Vector2i(22, top + 13), Vector2i(25, top + 14), Vector2i(16, top + 22), Vector2i(20, top + 23), Vector2i(31 - width, bottom - 7), Vector2i(34 - width, bottom - 4), Vector2i(28 - width, bottom), Vector2i(20, bottom + 2), Vector2i(24, bottom - 1), Vector2i(36, bottom + 4), Vector2i(48, bottom + 1), Vector2i(45, bottom - 3), Vector2i(34 + width, bottom - 2), Vector2i(29 + width, bottom - 10), Vector2i(43, top + 22), Vector2i(39, top + 21), Vector2i(37, top + 10)], Color("174e43"))
			polygon(image, [Vector2i(31, top), Vector2i(22, top + 13), Vector2i(25, top + 14), Vector2i(16, top + 22), Vector2i(20, top + 23), Vector2i(31 - width, bottom - 7), Vector2i(34 - width, bottom - 4), Vector2i(28 - width, bottom), Vector2i(24, bottom - 1), Vector2i(28, bottom), Vector2i(35, top + 16)], Color("28765a"))
			polygon(image, [Vector2i(31, top), Vector2i(20 - tier * 4, bottom - 10), Vector2i(27, bottom - 12)], Color("4b986a"))
			for branch: int in 3:
				box(image, 21 - tier * 4 + branch * 4, bottom - 10 + branch * 2, 6, 2, Color("6eaa73"))
	else:
		oval(image, Vector2i(31, 28), Vector2i(29, 23), Color("4d7960"))
		oval(image, Vector2i(25, 21), Vector2i(23, 18), Color("7a9b69"))
		oval(image, Vector2i(20, 15), Vector2i(15, 11), Color("9bad72"))
		for frond: int in 8:
			var x: int = 4 + frond * 7
			var length: int = 12 + (frond * 7) % 23
			var width: int = 3 + frond % 3
			polygon(image, [Vector2i(x, 24 + frond % 3), Vector2i(x + width, 26), Vector2i(x + width - 1, 26 + length), Vector2i(x + 1, 30 + length), Vector2i(x - 1, 37)], Color("598362") if frond % 2 == 0 else Color("70936a"))
			box(image, x, 27, 2, 6 + frond % 4, Color("93aa72"))
	return ImageTexture.create_from_image(image)

static func rock(kind: int) -> ImageTexture:
	var image: Image = canvas(40, 30)
	if kind == 0:
		polygon(image, [Vector2i(3, 16), Vector2i(13, 7), Vector2i(29, 8), Vector2i(38, 18), Vector2i(32, 27), Vector2i(9, 27)], Color("38544c"))
		polygon(image, [Vector2i(3, 16), Vector2i(13, 7), Vector2i(29, 8), Vector2i(35, 15), Vector2i(19, 20)], Color("78866b"))
		polygon(image, [Vector2i(5, 14), Vector2i(14, 8), Vector2i(24, 9), Vector2i(22, 15), Vector2i(10, 18)], Color("9ca86d"))
		box(image, 20, 11, 8, 4, Color("b3b87c"))
		box(image, 11, 20, 6, 4, Color("587c59"))
	else:
		polygon(image, [Vector2i(7, 20), Vector2i(12, 3), Vector2i(23, 1), Vector2i(29, 11), Vector2i(34, 26), Vector2i(13, 29)], Color("48665a"))
		polygon(image, [Vector2i(12, 3), Vector2i(23, 1), Vector2i(29, 11), Vector2i(18, 15), Vector2i(9, 13)], Color("869678"))
		polygon(image, [Vector2i(9, 13), Vector2i(18, 15), Vector2i(16, 25), Vector2i(7, 20)], Color("6b865e"))
		box(image, 14, 4, 8, 4, Color("a9b17b"))
		box(image, 20, 16, 6, 5, Color("587e52"))
	return ImageTexture.create_from_image(image)

static func fern() -> ImageTexture:
	var image: Image = canvas(28, 24)
	for side: int in [-1, 1]:
		for frond: int in 3:
			for leaf: int in 5:
				var x: int = 13 + side * leaf * 2
				var y: int = 19 - leaf * (3 - frond) - frond * 2
				box(image, x, y, 3, 3, Color("76a66b") if side == -1 else Color("3c7d57"))
	box(image, 13, 6, 2, 15, Color("acc17d"))
	return ImageTexture.create_from_image(image)

static func ruin() -> ImageTexture:
	var image: Image = canvas(100, 82)
	polygon(image, [Vector2i(8, 23), Vector2i(57, 9), Vector2i(60, 47), Vector2i(11, 63)], Color("64766b"))
	polygon(image, [Vector2i(57, 9), Vector2i(92, 29), Vector2i(91, 66), Vector2i(60, 47)], Color("435a52"))
	polygon(image, [Vector2i(8, 23), Vector2i(57, 9), Vector2i(64, 15), Vector2i(15, 29)], Color("a3a68a"))
	polygon(image, [Vector2i(57, 9), Vector2i(92, 29), Vector2i(85, 34), Vector2i(57, 18)], Color("879481"))
	box(image, 25, 35, 14, 24, Color("2a4b43"))
	box(image, 25, 32, 15, 4, Color("99a18c"))
	box(image, 43, 34, 10, 7, Color("86917d"))
	box(image, 13, 37, 9, 3, Color("89957e"))
	box(image, 44, 44, 10, 3, Color("53685b"))
	box(image, 68, 31, 6, 21, Color("344b44"))
	box(image, 76, 40, 11, 3, Color("637668"))
	box(image, 80, 17, 15, 13, Color.TRANSPARENT)
	box(image, 7, 19, 10, 10, Color.TRANSPARENT)
	oval(image, Vector2i(47, 16), Vector2i(17, 5), Color("729267"))
	box(image, 44, 18, 4, 19, Color("5d865d"))
	box(image, 49, 24, 4, 10, Color("8fa76c"))
	box(image, 62, 18, 5, 27, Color("568265"))
	for index: int in 5:
		oval(image, Vector2i(14 + index * 17, 70 + index % 2 * 4), Vector2i(7, 4), Color("819079"))
	return ImageTexture.create_from_image(image)

static func shadow(width: int) -> ImageTexture:
	var image: Image = canvas(width, 22)
	oval(image, Vector2i(width / 2, 11), Vector2i(width / 2 - 2, 10), Color("285646"))
	return ImageTexture.create_from_image(image)
