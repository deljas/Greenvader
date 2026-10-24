class_name StudyRaster
extends RefCounted
## Original integer-pixel study. No imported reference pixels, outlines or filters.
## Position hashes accept world coordinates, so future 4px dirty blocks can sample
## the same pattern without storing a Node per blade. A/B are cached once by the view.

const SIZE: Vector2i = Vector2i(640, 360)
const FIELD: Rect2i = Rect2i(0, 44, 640, 278)
const TREE_POSITION: Vector2i = Vector2i(208, 108)
const FLOWER_POSITION: Vector2i = Vector2i(314, 210)
const SEED_POSITION: Vector2i = Vector2i(352, 220)
const BOAR_POSITION: Vector2i = Vector2i(388, 230)
const ROOT: Color = Color("31594e")
const BLADE: Color = Color("54844e")
const TIP: Color = Color("7e9d5b")

static func position_hash(x: int, y: int, salt: int = 0) -> int:
	return absi((x * 374761393 + y * 668265263 + salt * 1274126177) ^ ((x + salt) * 13849)) % 10007

static func boundary(y: int) -> int:
	# 4px steps describe a decorative sample boundary; no game state is changed.
	return 452 + int(sin(float(y) * 0.026) * 23.0 + sin(float(y) * 0.067) * 8.0) / 4 * 4

static func is_grass(x: int, y: int) -> bool:
	return FIELD.has_point(Vector2i(x, y)) and x < boundary(y)

static func short_grass_color(_x: int, _y: int) -> Color:
	# Fixed material base; broad illumination belongs to a future lighting layer.
	return Color("466d46")

static func tall_centers(rich: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	# Many clumps inside a few larger colonies, with shared open areas in both A/B.
	for gy: int in range(62, 318, 10):
		for gx: int in range(12, 455, 11):
			var x: int = gx + position_hash(gx, gy, 11) % 9 - 4
			var y: int = gy + position_hash(gx, gy, 12) % 7 - 3
			var colony: float = sin(float(x) * 0.039 + sin(float(y) * 0.045)) + cos(float(y) * 0.067 - float(x) * 0.021)
			var threshold: int = (60 if rich else 31) if colony > 0.4 else (9 if rich else 3)
			if x < boundary(y) - 7 and position_hash(gx, gy, 5) % 100 < threshold:
				result.append(Vector2i(x, y))
	return result

static func ground(rich: bool) -> Image:
	var image: Image = LandscapeArt.canvas(SIZE.x, SIZE.y)
	image.fill(Color("202f2d"))
	for y: int in range(FIELD.position.y, FIELD.end.y):
		for x: int in SIZE.x:
			var soil: Color = Color("716c60")
			image.set_pixel(x, y, short_grass_color(x, y) if is_grass(x, y) else soil)
	# A continuous carpet: short blades throughout the whole green area. Irregular
	# spacing and connected 2-4px strokes avoid a repeating checkerboard / dot field.
	for gy: int in range(48, 323, 4):
		for gx: int in range(2, 479, 4):
			var h: int = position_hash(gx, gy, 3)
			var x: int = gx + h % 3 - 1
			var y: int = gy + (h / 7) % 3 - 1
			if not is_grass(x + 2, y) or y > 320:
				continue
			var base: Color = short_grass_color(x, y)
			var leaf: Color = base.lerp(Color("7b9b55"), 0.25 if h % 4 == 0 else 0.15)
			image.fill_rect(Rect2i(x, y - 1, 1, 2), leaf)
			if h % 3 != 0:
				image.fill_rect(Rect2i(x + 1, y, 2, 1), leaf)
			if h % 5 == 0:
				image.set_pixel(x - 1, y, base.lerp(ROOT, 0.3))
	# B is an exact superset of A clumps. Palette, positions, short carpet and light
	# direction remain identical; density is the only comparison variable.
	for center: Vector2i in tall_centers(rich):
		_tuft(image, center, position_hash(center.x, center.y, 6))
	# Quiet stepped transition: uneven short fronds extend a little into the soil.
	for y: int in range(49, 320, 5):
		var x: int = boundary(y)
		image.fill_rect(Rect2i(x - 3, y, 5, 2), Color("5c754e"))
		image.fill_rect(Rect2i(x, y - 1, 1, 2), Color("7b8a57"))
	# Sparse connected soil chips, well away from the grass carpet.
	for y: int in range(56, 320, 13):
		for x: int in range(478, 631, 17):
			if position_hash(x, y, 7) % 3 == 0:
				image.fill_rect(Rect2i(x, y, 3, 1), Color("85806b"))
	return image

static func _tuft(image: Image, p: Vector2i, variant: int) -> void:
	var height: int = 6 + variant % 4
	# Broken, staggered basal shade, with no horizontal underline.
	image.fill_rect(Rect2i(p.x - 2, p.y + 1, 2, 1), ROOT)
	image.fill_rect(Rect2i(p.x + 1, p.y, 2, 2), ROOT)
	var count: int = 3 + variant % 3
	for blade: int in count:
		var fan: int = blade - count / 2
		var base: Vector2i = p + Vector2i(fan, (variant / (blade + 2)) % 3 - 1)
		var bh: int = height - absi(fan) + (variant / (blade + 1)) % 3
		var tip: Vector2i = base + Vector2i(fan * 2 - 1, -bh)
		var bend: Vector2i = base + Vector2i(fan, -bh / 2)
		# Two one-pixel stepped segments form a bent leaf. The tips spread out,
		# leaving ground visible; the blades never become one solid rectangular cap.
		_blade_segment(image, base, bend, BLADE)
		_blade_segment(image, bend, tip, BLADE)
		if blade < count - 1:
			_blade_segment(image, tip + Vector2i(0, 1), tip, TIP)

static func _blade_segment(image: Image, start: Vector2i, finish: Vector2i, color: Color) -> void:
	var steps: int = maxi(absi(finish.x - start.x), absi(finish.y - start.y))
	for i: int in range(steps + 1):
		var point: Vector2i = Vector2i(Vector2(start).lerp(Vector2(finish), float(i) / float(maxi(1, steps))).round())
		if FIELD.has_point(point):
			image.set_pixelv(point, color)

static func tree() -> Image:
	var image: Image = LandscapeArt.canvas(64, 84)
	# Trunk and roots use broad warm faces, with a light side exposed at silhouette.
	LandscapeArt.polygon(image, [Vector2i(28, 41), Vector2i(37, 42), Vector2i(36, 73), Vector2i(46, 81), Vector2i(35, 79), Vector2i(31, 75), Vector2i(19, 82), Vector2i(26, 72)], Color("6c6245"))
	LandscapeArt.polygon(image, [Vector2i(29, 49), Vector2i(33, 48), Vector2i(31, 74), Vector2i(23, 79), Vector2i(28, 70)], Color("9a8050"))
	LandscapeArt.polygon(image, [Vector2i(33, 58), Vector2i(40, 51), Vector2i(42, 53), Vector2i(35, 65)], Color("877047"))
	# Whole-crown masses, then overlapping leaf sprays in back-to-front tiers.
	_lobe(image, Vector2i(33, 34), Vector2i(27, 28), Color("143f38"), 0)
	_lobe(image, Vector2i(24, 23), Vector2i(23, 18), Color("2b6e49"), 1)
	_leaf_plane(image, Vector2i(22, 18), Vector2i(17, 13), Color("558e4a"))
	var centers: Array[Vector2i] = [Vector2i(31, 9), Vector2i(17, 17), Vector2i(44, 18), Vector2i(9, 29), Vector2i(28, 26), Vector2i(48, 32), Vector2i(18, 39), Vector2i(36, 40), Vector2i(54, 45), Vector2i(9, 48), Vector2i(26, 52), Vector2i(44, 54)]
	var radii: Array[Vector2i] = [Vector2i(13, 8), Vector2i(13, 10), Vector2i(12, 8), Vector2i(8, 11), Vector2i(15, 10), Vector2i(11, 13), Vector2i(15, 8), Vector2i(12, 10), Vector2i(8, 9), Vector2i(8, 6), Vector2i(14, 9), Vector2i(11, 7)]
	for i: int in centers.size():
		var c: Vector2i = centers[i]
		var radius: Vector2i = radii[i]
		var shadow_side: bool = c.x > 36 or c.y > 42
		var shade: Color = Color("143f38") if shadow_side else Color("235f43")
		_lobe(image, c, radius, shade, i + 2)
		# Upper-left lit plane touches the silhouette in many sprays. Bottom-right
		# shade separates sprays without encircling the crown with a dark line.
		var plane: Color = Color("2d6b48") if shadow_side else Color("548c49")
		var plane_radius: Vector2i = Vector2i(radius.x - 2, maxi(3, radius.y - 4))
		_leaf_plane(image, c + Vector2i(-2, -3), plane_radius, plane)
		if not shadow_side:
			_leaf_plane(image, c + Vector2i(-4, -5), Vector2i(maxi(4, radius.x - 5), 3), Color("79a052") if c.y < 27 else Color("69994e"))
		# Only a handful of joined leaf tips in the lit half; lower/right sprays
		# are deliberately quieter, allowing deep shadows to form large masses.
		if c.x < 32 and c.y < 32:
			image.fill_rect(Rect2i(c.x - 4, c.y - 4, 4, 2), Color("8bab59"))
			image.fill_rect(Rect2i(c.x - 2, c.y - 6, 3, 2), Color("8bab59"))
	return image

static func _leaf_plane(image: Image, c: Vector2i, r: Vector2i, color: Color) -> void:
	# A connected irregular spray with several stepped leaf ends, not a round ball.
	LandscapeArt.polygon(image, [c + Vector2i(-r.x, -1), c + Vector2i(-r.x + 2, -4), c + Vector2i(-4, -r.y), c + Vector2i(0, -r.y - 1), c + Vector2i(2, -r.y + 1), c + Vector2i(r.x - 3, -r.y + 1), c + Vector2i(r.x, -2), c + Vector2i(r.x - 2, 1), c + Vector2i(3, 2), c + Vector2i(0, 4), c + Vector2i(-4, 2), c + Vector2i(-r.x + 2, 2)], color)

static func _lobe(image: Image, center: Vector2i, radius: Vector2i, color: Color, salt: int) -> void:
	# A few intentional steps, not a smooth ellipse or randomized pixel fringe.
	for y: int in range(-radius.y, radius.y + 1, 2):
		var t: float = float(y) / float(radius.y + 1)
		var half: int = maxi(1, int(float(radius.x) * sqrt(1.0 - t * t)))
		var notch: int = 1 if (y + radius.y + salt) % 7 < 2 else 0
		image.fill_rect(Rect2i(center.x - half + notch, center.y + y, half * 2 - notch, 2), color)

static func composition(rich: bool) -> Image:
	var image: Image = ground(rich)
	# All samples retain their existing source-pixel size. The tree has no resize.
	LandscapeArt.oval(image, TREE_POSITION + Vector2i(39, 77), Vector2i(34, 11), Color("36594a"), 1)
	image.blend_rect(tree(), Rect2i(0, 0, 64, 84), TREE_POSITION)
	LandscapeArt.oval(image, FLOWER_POSITION + Vector2i(8, 15), Vector2i(8, 2), Color("355346"), 1)
	image.blend_rect(PixelArt.flower().get_image(), Rect2i(0, 0, 16, 16), FLOWER_POSITION)
	# Three ground seed samples make the tiny pickup scale readable in context.
	var seed_image: Image = PlayArt.fruit().get_image()
	for offset: Vector2i in [Vector2i.ZERO, Vector2i(20, -9), Vector2i(-9, 20)]:
		image.blend_rect(seed_image, Rect2i(0, 0, 4, 4), SEED_POSITION + offset)
	image.blend_rect(PlayArt.plant_fruit().get_image(), Rect2i(0, 0, 4, 4), SEED_POSITION + Vector2i(23, 17))
	image.blend_rect(PixelArt.boar().get_image(), Rect2i(0, 0, 32, 18), BOAR_POSITION)
	return image
