class_name PickupView
extends Node2D
## Draws the ground pickups of a PlayState at integer pixel positions (no per-item nodes).

var play: PlayState

func setup(play_state: PlayState) -> void:
	play = play_state
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if play == null:
		return
	var texture: ImageTexture = PlayArt.fruit()
	var half: Vector2 = Vector2(texture.get_size()) / 2.0
	for item: Dictionary in play.pickups.items:
		draw_texture(texture, (Vector2(float(item["x"]), float(item["y"])) - half).round())
