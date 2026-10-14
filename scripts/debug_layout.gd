class_name DebugLayout
extends RefCounted
## Debug / test layout: every growth stage and edge case side by side, starting at tile `origin`.
## Used by `main.tscn -- --debug-layout` for the render check and by tests. Not gameplay.

static func apply(world: WorldState, origin: Vector2i) -> void:
	# Isolated single tiles: seed, sprout1, sprout2, mature.
	for stage: int in range(1, 5):
		set_tile(world, origin + Vector2i((stage - 1) * 3, 0), stage)
	# Strips: show the per-tile random sprout positions.
	for x: int in 12:
		set_tile(world, origin + Vector2i(x, 3), WorldState.STAGE_SEED)
		set_tile(world, origin + Vector2i(x, 5), WorldState.STAGE_SPROUT1)
		set_tile(world, origin + Vector2i(x, 7), WorldState.STAGE_SPROUT2)
	# Mature edge cases.
	var row: int = 10
	set_tile(world, origin + Vector2i(0, row), WorldState.STAGE_MATURE)
	set_tile(world, origin + Vector2i(3, row), WorldState.STAGE_MATURE)
	set_tile(world, origin + Vector2i(4, row), WorldState.STAGE_MATURE)
	set_tile(world, origin + Vector2i(7, row), WorldState.STAGE_MATURE)
	set_tile(world, origin + Vector2i(8, row + 1), WorldState.STAGE_MATURE)
	for dy: int in 3:
		for dx: int in 3:
			set_tile(world, origin + Vector2i(11 + dx, row + dy), WorldState.STAGE_MATURE)
	for offset: Vector2i in [Vector2i(16, 0), Vector2i(16, 1), Vector2i(17, 1)]:
		set_tile(world, origin + Vector2i(0, row) + offset, WorldState.STAGE_MATURE)

static func set_tile(world: WorldState, tile: Vector2i, stage: int) -> void:
	if world.in_bounds(tile.x, tile.y):
		world.set_stage(world.index_of(tile.x, tile.y), stage)
