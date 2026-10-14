class_name PlantProducer
extends RefCounted
## Seed fruit production of mature plants (P1-03). There is no timer per plant. Every production tick it
## counts the mature tiles around the player (per-chunk counts from WorldState, exact circle on tile centres),
## turns count * rate * interval into a whole number of fruits with a deterministic random draw, and drops
## each fruit on a random one of those mature tiles.
##
## State that must be saved: ticks (the position in the fixed random sequence).

var world: WorldState
var tuning: PlayTuning
var tile_px: int = 4
## Number of production ticks so far; part of the random sequence.
var ticks: int = 0
## Observability for tests.
var last_mature_count: int = 0
var last_expected: float = 0.0
var last_produced: int = 0
var total_produced: int = 0

# Scratch result of gather().
var _full_chunks: PackedInt32Array = PackedInt32Array()
var _edge_tiles: PackedInt32Array = PackedInt32Array()
var _full_total: int = 0

func _init(world_state: WorldState, play_tuning: PlayTuning, tile_size: int) -> void:
	world = world_state
	tuning = play_tuning
	tile_px = tile_size

## Collects the mature tiles whose centre is within `radius` px of `center`:
## chunks lying completely inside the circle are counted by their stored count only,
## chunks cut by the circle are scanned tile by tile. Returns the number of mature tiles.
func gather(center: Vector2, radius: float) -> int:
	_full_chunks = PackedInt32Array()
	_edge_tiles = PackedInt32Array()
	_full_total = 0
	if world.mature_count == 0:
		return 0
	var chunk_px: float = float(WorldState.CHUNK_TILES * tile_px)
	var r2: float = radius * radius
	var cx0: int = maxi(floori((center.x - radius) / chunk_px), 0)
	var cx1: int = mini(floori((center.x + radius) / chunk_px), world.chunks_x - 1)
	var cy0: int = maxi(floori((center.y - radius) / chunk_px), 0)
	var cy1: int = mini(floori((center.y + radius) / chunk_px), world.chunks_y - 1)
	var total: int = 0
	for cy: int in range(cy0, cy1 + 1):
		for cx: int in range(cx0, cx1 + 1):
			var chunk: int = cy * world.chunks_x + cx
			var in_chunk: int = world.mature_chunk_count[chunk]
			if in_chunk == 0:
				continue
			var left: float = cx * chunk_px
			var top: float = cy * chunk_px
			var right: float = left + chunk_px
			var bottom: float = top + chunk_px
			var near_x: float = maxf(maxf(left - center.x, center.x - right), 0.0)
			var near_y: float = maxf(maxf(top - center.y, center.y - bottom), 0.0)
			if near_x * near_x + near_y * near_y > r2:
				continue
			var far_x: float = maxf(absf(left - center.x), absf(right - center.x))
			var far_y: float = maxf(absf(top - center.y), absf(bottom - center.y))
			if far_x * far_x + far_y * far_y <= r2:
				_full_chunks.append(chunk)
				_full_total += in_chunk
				total += in_chunk
				continue
			total += _scan_chunk(cx, cy, center, r2, true)
	return total

## Scans one chunk's tiles. With `collect` the matching tile indices are appended to the edge list.
func _scan_chunk(cx: int, cy: int, center: Vector2, r2: float, collect: bool) -> int:
	var found: int = 0
	var x_start: int = cx * WorldState.CHUNK_TILES
	var y_start: int = cy * WorldState.CHUNK_TILES
	var x_end: int = mini(x_start + WorldState.CHUNK_TILES, world.width)
	var y_end: int = mini(y_start + WorldState.CHUNK_TILES, world.height)
	for y: int in range(y_start, y_end):
		var dy: float = (y + 0.5) * tile_px - center.y
		var dy2: float = dy * dy
		if dy2 > r2:
			continue
		var row: int = y * world.width
		for x: int in range(x_start, x_end):
			if world.stage[row + x] != WorldState.STAGE_MATURE:
				continue
			var dx: float = (x + 0.5) * tile_px - center.x
			if dx * dx + dy2 <= r2:
				found += 1
				if collect:
					_edge_tiles.append(row + x)
	return found

## k-th (0-based) mature tile of the latest gather(). Order: full chunks (row-major), then the scanned edge tiles.
func tile_at(k: int) -> int:
	if k >= _full_total:
		return _edge_tiles[k - _full_total]
	for chunk: int in _full_chunks:
		var in_chunk: int = world.mature_chunk_count[chunk]
		if k >= in_chunk:
			k -= in_chunk
			continue
		var x_start: int = (chunk % world.chunks_x) * WorldState.CHUNK_TILES
		var y_start: int = (chunk / world.chunks_x) * WorldState.CHUNK_TILES
		for y: int in range(y_start, mini(y_start + WorldState.CHUNK_TILES, world.height)):
			for x: int in range(x_start, mini(x_start + WorldState.CHUNK_TILES, world.width)):
				if world.stage[y * world.width + x] == WorldState.STAGE_MATURE:
					if k == 0:
						return y * world.width + x
					k -= 1
	return -1

## Brute-force-free helper for tests and the HUD: mature tiles within `radius` of `center`.
func count_near(center: Vector2, radius: float) -> int:
	return gather(center, radius)

## One production tick around `center` (player position, world px). Returns the number of fruits dropped.
func produce(pickups: GroundPickups, center: Vector2) -> int:
	ticks += 1
	last_produced = 0
	var count: int = gather(center, tuning.plant_production_radius_px)
	last_mature_count = count
	last_expected = float(count) * tuning.plant_fruit_rate_per_tile_second * tuning.plant_production_interval_seconds
	if count == 0:
		return 0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = tuning.scatter_seed * 1000003 + 77003 * 1000 + ticks
	# Whole part always, fractional part as a chance: the mean equals the expectation exactly.
	var drops: int = floori(last_expected)
	if rng.randf() < last_expected - float(drops):
		drops += 1
	drops = mini(drops, tuning.plant_fruit_max_per_tick)
	var dropped: int = 0
	for i: int in drops:
		var index: int = tile_at(rng.randi_range(0, count - 1))
		if index < 0:
			continue
		var owner_id: int = GroundPickups.PLANT_OWNER_BASE + index
		var jitter: float = tuning.plant_fruit_jitter_px
		var offset: Vector2 = Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
		if pickups.count_owned(owner_id) >= tuning.plant_fruit_per_tile_cap:
			continue
		var position: Vector2 = Vector2((index % world.width + 0.5) * tile_px, (index / world.width + 0.5) * tile_px) + offset
		if not pickups.spawn(GroundPickups.KIND_SEED_FRUIT, position, owner_id):
			break
		dropped += 1
	last_produced = dropped
	total_produced += dropped
	return dropped

func to_dict() -> Dictionary:
	return {"ticks": ticks, "total_produced": total_produced}

func load_dict(data: Dictionary) -> void:
	ticks = maxi(int(data.get("ticks", 0)), 0)
	total_produced = maxi(int(data.get("total_produced", 0)), 0)
