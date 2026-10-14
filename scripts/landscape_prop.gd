class_name LandscapeProp
extends Node2D
## Occluding scenery fades while the player is behind its visible footprint.

var sprite: Sprite2D
var player: FlowerPlayer
var fades_for_player: bool = false

func initialize(texture: Texture2D, location: Vector2, flower: FlowerPlayer, fades: bool) -> void:
	position = location.round()
	player = flower
	fades_for_player = fades
	sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = Vector2(-floorf(texture.get_width() / 2.0), -texture.get_height() + 5)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	set_process(fades)

func _process(_delta: float) -> void:
	var relative: Vector2 = player.global_position - global_position
	var area: Rect2 = Rect2(sprite.position - Vector2(4, 0), sprite.texture.get_size() + Vector2(8, 0))
	var behind: bool = relative.y < 0 and area.has_point(relative)
	sprite.modulate.a = 0.42 if behind else 1.0
