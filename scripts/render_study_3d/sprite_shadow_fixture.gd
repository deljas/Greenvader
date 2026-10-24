extends RefCounted
## Original 32x48 technical walking fixture. Flat pixel blocks, no outline.
const SIZE: Vector2i = Vector2i(32, 48)

static func frames() -> Array[ImageTexture]:
	var result: Array[ImageTexture] = []
	for index: int in 4:
		var image: Image = Image.create(32,48,false,Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		var skin: Color = Color("efc68e")
		var shirt: Color = Color("d97654")
		var sleeve: Color = Color("e9915d")
		var trousers: Color = Color("507b88")
		var boots: Color = Color("655746")
		# Head and cap, with one lit face, no dark perimeter.
		block(image,11,4,11,10,skin)
		block(image,9,1,14,5,Color("75a8b3"))
		block(image,9,5,17,2,Color("9ec6c7"))
		block(image,20,8,2,2,Color("626d62"))
		block(image,14,13,5,4,skin)
		block(image,9,16,14,14,shirt)
		block(image,9,16,5,12,sleeve)
		block(image,9,28,14,3,Color("dec28a"))
		if index == 0:
			block(image,4,18,6,5,sleeve)
			block(image,1,20,6,4,skin)
			block(image,22,19,5,9,shirt)
			block(image,24,27,5,4,skin)
			block(image,10,30,6,16,trousers)
			block(image,4,45,12,3,boots)
			block(image,17,31,6,9,trousers)
			block(image,20,38,8,4,boots)
		elif index == 2:
			block(image,5,18,5,10,sleeve)
			block(image,3,27,5,4,skin)
			block(image,22,18,6,5,shirt)
			block(image,26,20,5,4,skin)
			block(image,9,31,6,9,trousers)
			block(image,4,38,9,4,boots)
			block(image,17,30,6,16,trousers)
			block(image,17,45,12,3,boots)
		else:
			block(image,5,18,5,10,sleeve)
			block(image,4,27,5,4,skin)
			block(image,22,18,5,10,shirt)
			block(image,23,27,5,4,skin)
			block(image,10,30,5,15,trousers)
			block(image,18,30,5,15,trousers)
			block(image,7,45,8,3,boots)
			block(image,18,45,9,3,boots)
			if index == 3:
				block(image,10,34,3,5,Color("6c96a1"))
		result.append(ImageTexture.create_from_image(image))
	return result

static func block(image: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	image.fill_rect(Rect2i(x,y,w,h),color)
