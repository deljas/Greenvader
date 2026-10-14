class_name CultivatedPlant
extends RefCounted
## One placed cultivated plant (2x2 tiles). Plain state; Cultivation owns the behaviour.

var uid: int = 0
var key: StringName = &""
## Top-left tile of the footprint.
var tile: Vector2i = Vector2i.ZERO
var size: int = 2
## Game seconds since planting, capped at the definition's grow_seconds once mature.
var age: float = 0.0
var mature: bool = false
## Seconds counted toward the next fruit (kiwi): only counts while mature and while the plant has room for a fruit.
var timer: float = 0.0
## Fruits dropped so far; part of the fixed random sequence of drop positions.
var drops: int = 0

func rect() -> Rect2i:
	return Rect2i(tile, Vector2i(size, size))

## Footprint centre in tile units (tile centres are at +0.5).
func center_tiles() -> Vector2:
	return Vector2(tile) + Vector2(size, size) * 0.5

func to_dict() -> Dictionary:
	return {"uid": uid, "key": String(key), "x": tile.x, "y": tile.y, "size": size, "age": age, "mature": mature, "timer": timer, "drops": drops}
