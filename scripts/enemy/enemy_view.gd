class_name EnemyView
extends Node
## Shows the nests and boars as sprites in the y-sorted actors node (no outline). A boar sprite exists per boar, created and
## removed as the EnemyField changes (at most boar_cap + nest_max_count sprites). The node position of a sprite is its foot.

var enemies: EnemyField
var actors: Node2D
var tile_px: int = 4
var boar_sprites: Dictionary = {}
var nest_sprites: Dictionary = {}
## Ground layer under the y-sorted actors: carcasses, bones and the ruins of destroyed nests.
var ground: Node2D
var carcass_sprites: Dictionary = {}
var ruin_sprites: Dictionary = {}

const FLASH_COLOR: Color = Color(2.2, 2.2, 2.2, 1.0)

func setup(field: EnemyField, actors_node: Node2D, tile_size: int) -> void:
	enemies = field
	actors = actors_node
	tile_px = tile_size
	ground = Node2D.new()
	ground.name = "EnemyGround"
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var parent: Node = actors.get_parent()
	parent.add_child(ground)
	parent.move_child(ground, actors.get_index())
	refresh()

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	var present: Dictionary = {}
	for nest: Nest in enemies.nests:
		if not nest.alive:
			if not ruin_sprites.has(nest.id):
				var ruin: Sprite2D = Sprite2D.new()
				ruin.name = "NestRuin%d" % nest.id
				ruin.texture = EnemyArt.nest_ruin()
				ruin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				ruin.centered = false
				ruin.position = Vector2(nest.tile.x * tile_px, nest.tile.y * tile_px)
				ground.add_child(ruin)
				ruin_sprites[nest.id] = ruin
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
		(nest_sprites[nest.id] as Sprite2D).modulate = FLASH_COLOR if enemies.flash_bright(nest.flash_steps) else Color.WHITE
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
		sprite.modulate = FLASH_COLOR if enemies.flash_bright(boar.flash_steps) else Color.WHITE
	for id: int in boar_sprites.keys():
		if not present.has(id):
			(boar_sprites[id] as Sprite2D).queue_free()
			boar_sprites.erase(id)
	present = {}
	for carcass: Carcass in enemies.carcasses:
		present[carcass.id] = true
		var shown: Sprite2D = carcass_sprites.get(carcass.id) as Sprite2D
		if shown == null:
			shown = Sprite2D.new()
			shown.name = "Carcass%d" % carcass.id
			shown.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			shown.centered = false
			shown.position = carcass.pos.round()
			ground.add_child(shown)
			carcass_sprites[carcass.id] = shown
			shown.set_meta("stage", -1)
		if int(shown.get_meta("stage")) != carcass.stage:
			shown.set_meta("stage", carcass.stage)
			shown.texture = EnemyArt.corpse() if carcass.stage == Carcass.STAGE_CORPSE else EnemyArt.bone()
			shown.offset = Vector2(-shown.texture.get_width() / 2, -shown.texture.get_height())
	for id: int in carcass_sprites.keys():
		if not present.has(id):
			(carcass_sprites[id] as Sprite2D).queue_free()
			carcass_sprites.erase(id)
