class_name EnemyView
extends Node
## Shows the nests and boars as sprites in the y-sorted actors node (no outline). A boar sprite exists per boar, created and
## removed as the EnemyField changes (at most boar_cap + nest_max_count sprites). The node position of a sprite is its foot.

var enemies: EnemyField
var actors: Node2D
var tile_px: int = 4
var boar_sprites: Dictionary = {}
var nest_sprites: Dictionary = {}

func setup(field: EnemyField, actors_node: Node2D, tile_size: int) -> void:
	enemies = field
	actors = actors_node
	tile_px = tile_size
	refresh()

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	var present: Dictionary = {}
	for nest: Nest in enemies.nests:
		if not nest.alive:
			continue
		present[nest.id] = true
		if not nest_sprites.has(nest.id):
			var sprite: Sprite2D = Sprite2D.new()
			sprite.name = "Nest%d" % nest.id
			sprite.texture = EnemyArt.nest()
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.centered = false
			sprite.offset = Vector2(0, -nest.size * tile_px)
			sprite.position = Vector2(nest.tile.x * tile_px, (nest.tile.y + nest.size) * tile_px)
			actors.add_child(sprite)
			nest_sprites[nest.id] = sprite
	for id: int in nest_sprites.keys():
		if not present.has(id):
			(nest_sprites[id] as Sprite2D).queue_free()
			nest_sprites.erase(id)
	present = {}
	for boar: Boar in enemies.boars:
		present[boar.id] = true
		var sprite: Sprite2D = boar_sprites.get(boar.id) as Sprite2D
		if sprite == null:
			sprite = Sprite2D.new()
			sprite.name = "Boar%d" % boar.id
			sprite.texture = PixelArt.boar()
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.centered = false
			sprite.offset = Vector2(-16, -16)
			actors.add_child(sprite)
			boar_sprites[boar.id] = sprite
		sprite.position = boar.pos.round()
		sprite.flip_h = boar.facing < 0
	for id: int in boar_sprites.keys():
		if not present.has(id):
			(boar_sprites[id] as Sprite2D).queue_free()
			boar_sprites.erase(id)
