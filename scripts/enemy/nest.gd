class_name Nest
extends RefCounted
## One enemy nest (P2-01). Display-free state; EnemyField owns and drives it.
## It occupies a size x size block of tiles (WorldState.occupy with owner id WorldState.OWNER_BAND_NEST + id) while alive.

var id: int = 0
var zone: int = 0
## Top-left tile of the block.
var tile: Vector2i = Vector2i.ZERO
var size: int = 4
var hp: int = 1
var hp_max: int = 1
var alive: bool = true
## Fixed steps the spawn timer has run (only counts while both boar limits have room).
var spawn_steps: int = 0
## Boars spawned so far (picks the spawn position and the boar's random sequence) and boars alive from this nest.
var spawned: int = 0
var boar_count: int = 0

func rect() -> Rect2i:
	return Rect2i(tile.x, tile.y, size, size)

func owner_id() -> int:
	return WorldState.OWNER_BAND_NEST + id

## Centre of the block in world pixels.
func center_px(tile_px: int) -> Vector2:
	return (Vector2(tile) + Vector2(size, size) * 0.5) * tile_px

func to_dict() -> Dictionary:
	return {"id": id, "zone": zone, "x": tile.x, "y": tile.y, "size": size, "hp": hp, "hp_max": hp_max, "alive": alive, "spawn_steps": spawn_steps, "spawned": spawned}
