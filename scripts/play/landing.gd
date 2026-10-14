class_name Landing
extends RefCounted
## What a landed projectile does to the world. Static, display-free, no hidden state.
## Both effects only ever touch target tiles; non-target tiles (water, buildings) are never changed.

## Tiles whose centre lies within `radius_px` of `point` (row-major order), clipped to the map.
static func tiles_in_radius(world: WorldState, tile_px: int, point: Vector2, radius_px: float) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	var min_x: int = maxi(floori((point.x - radius_px) / tile_px), 0)
	var max_x: int = mini(floori((point.x + radius_px) / tile_px), world.width - 1)
	var min_y: int = maxi(floori((point.y - radius_px) / tile_px), 0)
	var max_y: int = mini(floori((point.y + radius_px) / tile_px), world.height - 1)
	var radius_squared: float = radius_px * radius_px
	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			var center: Vector2 = Vector2((x + 0.5) * tile_px, (y + 0.5) * tile_px)
			if center.distance_squared_to(point) <= radius_squared:
				result.append(world.index_of(x, y))
	return result

## Turns up to `max_count` plantable free tiles near `point` into seeds, chosen by a generator seeded with
## `rng_seed` (same world + point + seed gives the same tiles). Returns the tile indices that became seeds;
## empty when nothing can be planted (the seed is simply lost).
static func scatter_seeds(world: WorldState, tile_px: int, point: Vector2, radius_px: float, max_count: int, rng_seed: int) -> PackedInt32Array:
	var candidates: PackedInt32Array = PackedInt32Array()
	for index: int in tiles_in_radius(world, tile_px, point, radius_px):
		if world.can_plant(index):
			candidates.append(index)
	var placed: PackedInt32Array = PackedInt32Array()
	if candidates.is_empty() or max_count <= 0:
		return placed
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = rng_seed
	var wanted: int = mini(max_count, candidates.size())
	# Partial Fisher-Yates: the first `wanted` entries are a uniform random subset.
	for i: int in wanted:
		var j: int = rng.randi_range(i, candidates.size() - 1)
		var swap: int = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap
		if world.set_stage(candidates[i], WorldState.STAGE_SEED):
			placed.append(candidates[i])
	return placed

## Adds `amount` moisture (capped at `moisture_max`) to every target tile near `point`.
## Returns the number of tiles whose moisture actually changed.
static func splash_water(world: WorldState, tile_px: int, point: Vector2, radius_px: float, amount: int, moisture_max: int) -> int:
	var changed: int = 0
	for index: int in tiles_in_radius(world, tile_px, point, radius_px):
		if world.target[index] == 0:
			continue
		var wet: int = mini(int(world.moisture[index]) + amount, moisture_max)
		if wet != world.moisture[index]:
			world.moisture[index] = wet
			changed += 1
	return changed
