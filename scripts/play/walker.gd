class_name Walker
extends RefCounted
## Player walking against the map (P1-06). Display-free and static.
##
## The player's feet are a small axis-aligned rectangle of half-size `half` (px) around the position. A tile that is not
## walkable (water, buildings, outside the map) blocks the rectangle. Each axis is resolved on its own, X first, so the
## player slides along walls instead of sticking. A blocked axis move stops exactly at the tile edge (no gap that would
## depend on the step length), and long moves are cut into short parts (MAX_SUBSTEP), so the path does not depend on the
## frame rate. Free movement is just position + motion: a diagonal keeps its speed.

const EPS: float = 1.0e-4

## A move longer than this is split into equal parts of at most this length (px), so the path along walls and through
## openings differs by less than this between frame rates (a long frame cannot cut a corner a short frame would hit).
const MAX_SUBSTEP: float = 0.25

## Moves `position` by `motion` (px) and returns the new position.
static func move(world: WorldState, tile_px: int, position: Vector2, motion: Vector2, half: Vector2) -> Vector2:
	var distance: float = motion.length()
	if distance <= MAX_SUBSTEP:
		return _step(world, tile_px, position, motion, half)
	var parts: int = ceili(distance / MAX_SUBSTEP)
	var part: Vector2 = motion / float(parts)
	var result: Vector2 = position
	for i: int in parts:
		result = _step(world, tile_px, result, part, half)
	return result

## One short move: X first, then Y, each stopping exactly at the tile edge.
static func _step(world: WorldState, tile_px: int, position: Vector2, motion: Vector2, half: Vector2) -> Vector2:
	var result: Vector2 = position
	if motion.x != 0.0:
		result.x = _axis(world, tile_px, result, motion.x, half, true)
	if motion.y != 0.0:
		result.y = _axis(world, tile_px, result, motion.y, half, false)
	return result

## True when the feet rectangle at `position` touches no blocked tile.
static func is_clear(world: WorldState, tile_px: int, position: Vector2, half: Vector2) -> bool:
	var x0: int = floori((position.x - half.x + EPS) / tile_px)
	var x1: int = ceili((position.x + half.x - EPS) / tile_px) - 1
	var y0: int = floori((position.y - half.y + EPS) / tile_px)
	var y1: int = ceili((position.y + half.y - EPS) / tile_px) - 1
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			if not world.is_walkable(x, y):
				return false
	return true

## Resolves a move along one axis. Returns the new coordinate of that axis.
static func _axis(world: WorldState, tile_px: int, position: Vector2, delta: float, half: Vector2, horizontal: bool) -> float:
	var along: float = position.x if horizontal else position.y
	var reach: float = half.x if horizontal else half.y
	var across: float = position.y if horizontal else position.x
	var across_reach: float = half.y if horizontal else half.x
	var a0: int = floori((across - across_reach + EPS) / tile_px)
	var a1: int = ceili((across + across_reach - EPS) / tile_px) - 1
	var target: float = along + delta
	if delta > 0.0:
		var first: int = ceili((along + reach - EPS) / tile_px)
		var last: int = ceili((target + reach - EPS) / tile_px) - 1
		for line: int in range(first, last + 1):
			if _line_blocked(world, line, a0, a1, horizontal):
				return float(line * tile_px) - reach
	else:
		var first_down: int = floori((along - reach + EPS) / tile_px) - 1
		var last_down: int = floori((target - reach + EPS) / tile_px)
		for line: int in range(first_down, last_down - 1, -1):
			if _line_blocked(world, line, a0, a1, horizontal):
				return float((line + 1) * tile_px) + reach
	return target

## One tile column (horizontal) or row of the rectangle's cross range is blocked.
static func _line_blocked(world: WorldState, line: int, a0: int, a1: int, horizontal: bool) -> bool:
	for a: int in range(a0, a1 + 1):
		if horizontal:
			if not world.is_walkable(line, a):
				return true
		elif not world.is_walkable(a, line):
			return true
	return false
