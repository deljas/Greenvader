class_name CultivatedView
extends Node
## Shows the cultivated plants as 8x8 sprites in the y-sorted actors node (no outline, young / mature art).
## Rebuilds its sprites when Cultivation reports a change (a plant was placed or matured): at most a few dozen sprites.

var cultivation: Cultivation
var actors: Node2D
var tile_px: int = 4
var sprites: Dictionary = {}

func setup(cultivation_state: Cultivation, actors_node: Node2D, tile_size: int) -> void:
	cultivation = cultivation_state
	actors = actors_node
	tile_px = tile_size
	cultivation.changed.connect(refresh)
	refresh()

func refresh() -> void:
	var present: Dictionary = {}
	for plant: CultivatedPlant in cultivation.plants:
		present[plant.uid] = true
		var sprite: Sprite2D = sprites.get(plant.uid) as Sprite2D
		if sprite == null:
			sprite = Sprite2D.new()
			sprite.name = "Cultivated%d" % plant.uid
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.centered = false
			var size_px: int = plant.size * tile_px
			sprite.offset = Vector2(0, -size_px)
			# The node position is the foot of the plant, so the y-sort puts it in front of / behind the player correctly.
			sprite.position = Vector2(plant.tile.x * tile_px, (plant.tile.y + plant.size) * tile_px)
			actors.add_child(sprite)
			sprites[plant.uid] = sprite
		sprite.texture = PlayArt.cultivated(plant.key, plant.mature)
	for uid: int in sprites.keys():
		if not present.has(uid):
			(sprites[uid] as Sprite2D).queue_free()
			sprites.erase(uid)
