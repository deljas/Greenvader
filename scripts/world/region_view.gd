class_name RegionView
extends Node2D
## Draws the whole region as 64x64-tile blocks (256x256 px images), no per-tile Nodes.
## Only the tiles that changed (WorldState dirty list) are repainted, and only the
## blocks containing them are re-uploaded. No per-frame full scan.
##
## Tile look (4x4 px, flat colours, no outline):
##   ground : terrain ground_color
##   seed   : 1 px at the tile's sprout slot (one of the centre 2x2 pixels)
##   sprout1: 1x1 px at the slot
##   sprout2: 1 wide x 2 tall, grows upward from the slot pixel
##   mature : the whole tile green; the 1 px ring on each side WITHOUT a mature 4-neighbour
##            is mature colour at edge_alpha, composited over the ground colour.
##            Diagonal neighbours are ignored; the map border counts as "no neighbour".

const TILE: int = 4
const BLOCK_TILES: int = 64
const BLOCK_PX: int = BLOCK_TILES * TILE
const TILE_RECT: Rect2i = Rect2i(0, 0, TILE, TILE)

var world: WorldState
var tuning: SimTuning
var blocks_x: int = 0
var blocks_y: int = 0
var block_images: Array[Image] = []
var block_textures: Array[ImageTexture] = []
var block_flag: PackedByteArray = PackedByteArray()
var ground_colors: Array[Color] = []
var edge_colors: Array[Color] = []
var ground_tiles: Array[Image] = []
var sprout_tiles: Array[Image] = []
var mature_tiles: Array[Image] = []
## Observability for tests: tiles repainted / blocks uploaded by the latest flush, and totals.
var last_flush_tiles: int = 0
var last_flush_blocks: int = 0
var total_tiles_rendered: int = 0

func setup(world_state: WorldState, sim_tuning: SimTuning) -> void:
	world = world_state
	tuning = sim_tuning
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	position = Vector2.ZERO
	blocks_x = ceili(float(world.width) / BLOCK_TILES)
	blocks_y = ceili(float(world.height) / BLOCK_TILES)
	_build_color_tables()
	_build_tile_images()
	render_all()

func _build_color_tables() -> void:
	ground_colors.clear()
	edge_colors.clear()
	for def: TerrainDef in world.terrain_defs:
		ground_colors.append(def.ground_color)
		# Opaque pixels holding "mature colour at edge_alpha over the ground".
		var blended: Color = def.ground_color.lerp(tuning.mature_color, tuning.edge_alpha)
		blended.a = 1.0
		edge_colors.append(blended)

## Full repaint. Used once at start (and by tests). Fast: ground runs + only non-empty tiles.
func render_all() -> void:
	var width: int = world.width
	var tile_map: Image = Image.create(width, world.height, false, Image.FORMAT_RGBA8)
	for y: int in world.height:
		var run_start: int = 0
		var run_id: int = world.terrain[y * width]
		for x: int in range(1, width + 1):
			var id: int = world.terrain[y * width + x] if x < width else -1
			if id != run_id:
				tile_map.fill_rect(Rect2i(run_start, y, x - run_start, 1), ground_colors[run_id])
				run_start = x
				run_id = id
	tile_map.resize(world.width * TILE, world.height * TILE, Image.INTERPOLATE_NEAREST)
	block_images.clear()
	block_textures.clear()
	block_flag = PackedByteArray()
	block_flag.resize(blocks_x * blocks_y)
	for by: int in blocks_y:
		for bx: int in blocks_x:
			var image: Image = Image.create(BLOCK_PX, BLOCK_PX, false, Image.FORMAT_RGBA8)
			image.blit_rect(tile_map, Rect2i(bx * BLOCK_PX, by * BLOCK_PX, BLOCK_PX, BLOCK_PX), Vector2i.ZERO)
			block_images.append(image)
	var stage: PackedByteArray = world.stage
	for index: int in world.tile_count():
		if stage[index] != WorldState.STAGE_EMPTY:
			_render_tile(index)
	for block: int in block_images.size():
		block_textures.append(ImageTexture.create_from_image(block_images[block]))
	block_flag.fill(0)
	world.clear_dirty()
	last_flush_tiles = world.tile_count()
	last_flush_blocks = block_images.size()
	queue_redraw()

## Repaints the dirty tiles and uploads the blocks they touch. Cheap when nothing changed.
## `limit` >= 0 repaints at most that many of the oldest dirty tiles and leaves the rest for the next call
## (P1-04: bounds the work of one frame); negative = all of them.
func flush(limit: int = -1) -> void:
	if world.dirty_tiles.is_empty():
		last_flush_tiles = 0
		last_flush_blocks = 0
		return
	var tiles: PackedInt32Array = world.take_dirty(limit)
	for index: int in tiles:
		_render_tile(index)
	var uploaded: int = 0
	for block: int in block_flag.size():
		if block_flag[block] == 1:
			block_flag[block] = 0
			block_textures[block].update(block_images[block])
			uploaded += 1
	last_flush_tiles = tiles.size()
	last_flush_blocks = uploaded
	total_tiles_rendered += tiles.size()

func _process(_delta: float) -> void:
	flush(tuning.render_tiles_per_frame)

func _draw() -> void:
	for by: int in blocks_y:
		for bx: int in blocks_x:
			draw_texture(block_textures[by * blocks_x + bx], Vector2(bx * BLOCK_PX, by * BLOCK_PX))

func block_of_tile(x: int, y: int) -> int:
	return (y / BLOCK_TILES) * blocks_x + (x / BLOCK_TILES)

## Pre-rendered 4x4 tile images (one blit per repainted tile instead of several fills):
##   ground_tiles[terrain]
##   sprout_tiles[(terrain * 3 + stage - 1) * 4 + slot]    (seed, sprout 1, sprout 2)
##   mature_tiles[terrain * 16 + mask]                      mask bit 0 / 1 / 2 / 3 = no mature neighbour above / below / left / right
func _build_tile_images() -> void:
	ground_tiles.clear()
	sprout_tiles.clear()
	mature_tiles.clear()
	for terrain_id: int in world.terrain_defs.size():
		var ground: Color = ground_colors[terrain_id]
		var base: Image = Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
		base.fill(ground)
		ground_tiles.append(base)
		for stage: int in range(WorldState.STAGE_SEED, WorldState.STAGE_SPROUT2 + 1):
			for slot: int in WorldState.SLOT_COUNT:
				var image: Image = base.duplicate()
				var px: int = 1 + (slot & 1)
				var py: int = 1 + (slot >> 1)
				if stage == WorldState.STAGE_SEED:
					image.set_pixel(px, py, tuning.seed_color)
				elif stage == WorldState.STAGE_SPROUT1:
					image.set_pixel(px, py, tuning.sprout_color)
				else:
					image.set_pixel(px, py, tuning.sprout_color)
					image.set_pixel(px, py - 1, tuning.sprout_color)
				sprout_tiles.append(image)
		for mask: int in 16:
			var mature: Image = Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
			mature.fill(tuning.mature_color)
			var edge: Color = edge_colors[terrain_id]
			if mask & 1:
				mature.fill_rect(Rect2i(0, 0, TILE, 1), edge)
			if mask & 2:
				mature.fill_rect(Rect2i(0, TILE - 1, TILE, 1), edge)
			if mask & 4:
				mature.fill_rect(Rect2i(0, 0, 1, TILE), edge)
			if mask & 8:
				mature.fill_rect(Rect2i(TILE - 1, 0, 1, TILE), edge)
			mature_tiles.append(mature)

func _render_tile(index: int) -> void:
	var width: int = world.width
	var x: int = index % width
	var y: int = index / width
	var block: int = (y / BLOCK_TILES) * blocks_x + (x / BLOCK_TILES)
	block_flag[block] = 1
	var origin: Vector2i = Vector2i((x % BLOCK_TILES) * TILE, (y % BLOCK_TILES) * TILE)
	var terrain_id: int = world.terrain[index]
	var stage_array: PackedByteArray = world.stage
	var stage: int = stage_array[index]
	var image: Image = block_images[block]
	if stage == WorldState.STAGE_MATURE:
		# The 1 px ring on each side WITHOUT a mature 4-neighbour is the half-transparent edge; the map border counts
		# as "no neighbour"; diagonals are ignored.
		var mask: int = 0
		if y == 0 or stage_array[index - width] != WorldState.STAGE_MATURE:
			mask |= 1
		if y == world.height - 1 or stage_array[index + width] != WorldState.STAGE_MATURE:
			mask |= 2
		if x == 0 or stage_array[index - 1] != WorldState.STAGE_MATURE:
			mask |= 4
		if x == width - 1 or stage_array[index + 1] != WorldState.STAGE_MATURE:
			mask |= 8
		image.blit_rect(mature_tiles[terrain_id * 16 + mask], TILE_RECT, origin)
	elif stage == WorldState.STAGE_EMPTY:
		image.blit_rect(ground_tiles[terrain_id], TILE_RECT, origin)
	else:
		image.blit_rect(sprout_tiles[(terrain_id * 3 + stage - 1) * 4 + world.sprout_slot[index]], TILE_RECT, origin)
