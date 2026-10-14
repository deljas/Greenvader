class_name DemoTerrain
extends Node2D
## One canvas item for terrain. P0 map is presentation only, not region state.

const TILE: int = 16
const SIZE: Vector2i = Vector2i(80, 50)

func _draw() -> void:
	for y: int in SIZE.y:
		for x: int in SIZE.x:
			var tile_position: Vector2 = Vector2(x * TILE, y * TILE)
			var variation: int = (x * 17 + y * 31) % 7
			var grass: bool = (x - 27) * (x - 27) + (y - 23) * (y - 23) < 225
			var water: bool = x > 37 and x < 49 and y > 14 and y < 34
			var ground: Color = Color("957e69")
			if grass:
				ground = Color("5e956e")
			if water:
				ground = Color("518c9d")
			ground = ground.lightened(float(variation) * 0.008)
			draw_rect(Rect2(tile_position, Vector2(TILE, TILE)), ground)
			if water:
				draw_rect(Rect2(tile_position + Vector2(3, 6 + variation), Vector2(7, 1)), Color("83bcc0"))
			elif grass:
				draw_rect(Rect2(tile_position + Vector2(4, 4 + variation), Vector2(2, 3)), Color("82b476"))
				draw_rect(Rect2(tile_position + Vector2(11, 10), Vector2(2, 2)), Color("467e62"))
			else:
				draw_rect(Rect2(tile_position + Vector2(3 + variation, 8), Vector2(3, 1)), Color("b19c81"))
	# Ruin blocks, different color faces without an outline.
	draw_rect(Rect2(310, 270, 46, 20), Color("69746d"))
	draw_rect(Rect2(310, 264, 46, 6), Color("93998a"))
	draw_rect(Rect2(332, 252, 12, 24), Color("858e7d"))
