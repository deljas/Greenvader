extends RefCounted
## POC-03 logical shot list (no Node, no sprite). Same behaviour as the old ProjectileField: straight flight to the aim
## point clipped to the range, fixed speed, safety lifetime and a cap. Added for the 3D PoC:
##  - obstacle check per step: `blocker` is Callable(from_logic, to_logic) -> bool (segment crosses a cell that stops
##    shots). A shot that meets one ends just in front of it ("blocked"); nothing lands behind the wall.
##  - enemy hook for POC-04: `enemy_hit_provider` Callable(shot, from, to) -> Dictionary ({} = no hit, else {"point": Vector2, ...}).
## Only time passed to advance() moves shots (single game loop; a paused session never calls it).
## Positions are logical px (1 px = 0.1 m).

signal landed(kind: String, point: Vector2)
signal blocked(kind: String, point: Vector2)
signal enemy_hit(kind: String, point: Vector2, info: Dictionary)
signal expired(kind: String, point: Vector2)

const KIND_SEED: String = "seed"
const KIND_WATER: String = "water"
## Sampling distance when locating the last clear point in front of an obstacle.
const PROBE_PX: float = 0.5

var speed: float = 160.0
var range_px: float = 120.0
var max_count: int = 64
var max_age: float = 1.8
var max_step: float = 0.25
var shots: Array[Dictionary] = []
var next_id: int = 1
var blocker: Callable = Callable()
var enemy_hit_provider: Callable = Callable()
## Counters for observability.
var launched: int = 0
var landed_count: int = 0
var blocked_count: int = 0

func setup(tuning: PlayTuning) -> void:
	speed = tuning.projectile_speed
	range_px = tuning.projectile_range_px
	max_count = tuning.max_projectiles
	max_age = tuning.projectile_max_age
	max_step = tuning.max_step_seconds

func is_full() -> bool:
	return shots.size() >= max_count

## Launches a shot from `origin` toward `aim_point`. Returns the planned landing point, or Vector2.INF when refused (full).
func launch(kind: String, origin: Vector2, aim_point: Vector2, fallback_direction: Vector2 = Vector2.DOWN) -> Vector2:
	if is_full():
		return Vector2.INF
	var offset: Vector2 = aim_point - origin
	var direction: Vector2 = offset.normalized() if offset.length_squared() > 0.0001 else fallback_direction.normalized()
	var distance: float = minf(offset.length(), range_px)
	var target: Vector2 = origin + direction * distance
	shots.append({"id": next_id, "kind": kind, "position": origin, "origin": origin, "target": target, "direction": direction, "total": distance, "traveled": 0.0, "age": 0.0})
	next_id += 1
	launched += 1
	return target

func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	delta = minf(delta, max_step)
	for index: int in range(shots.size() - 1, -1, -1):
		var shot: Dictionary = shots[index]
		shot["age"] = float(shot["age"]) + delta
		var from: Vector2 = shot["position"]
		var remaining: float = float(shot["total"]) - float(shot["traveled"])
		var step: float = speed * delta
		var arrives: bool = step >= remaining
		var to: Vector2 = Vector2(shot["target"]) if arrives else from + Vector2(shot["direction"]) * step
		var kind: String = String(shot["kind"])
		# Order: obstacle first (a wall hides what is behind it), then enemies on the clear part of the segment.
		var stop: Vector2 = clear_end(from, to)
		var wall: bool = stop != to
		var hit: Dictionary = _query_enemy(shot, from, stop)
		if not hit.is_empty():
			shots.remove_at(index)
			enemy_hit.emit(kind, Vector2(hit.get("point", stop)), hit)
			continue
		if wall:
			shots.remove_at(index)
			blocked_count += 1
			blocked.emit(kind, stop)
			continue
		shot["traveled"] = float(shot["traveled"]) + (remaining if arrives else step)
		shot["position"] = to
		if arrives:
			shots.remove_at(index)
			landed_count += 1
			landed.emit(kind, to)
		elif float(shot["age"]) > max_age:
			shots.remove_at(index)
			expired.emit(kind, to)

## End of the part of from->to that is not cut by an obstacle: `to` itself when clear, otherwise the last clear sample.
func clear_end(from: Vector2, to: Vector2) -> Vector2:
	if not blocker.is_valid() or not blocker.call(from, to):
		return to
	var length: float = from.distance_to(to)
	var samples: int = maxi(ceili(length / PROBE_PX), 1)
	var last_clear: Vector2 = from
	for i: int in range(1, samples + 1):
		var point: Vector2 = from.lerp(to, float(i) / float(samples))
		if bool(blocker.call(point, point)):
			return last_clear
		last_clear = point
	# The segment test saw an obstacle but no sample did (grazing a cell corner): stop at the start of this step.
	return from

func _query_enemy(shot: Dictionary, from: Vector2, to: Vector2) -> Dictionary:
	if not enemy_hit_provider.is_valid():
		return {}
	return enemy_hit_provider.call(shot, from, to)

## Positions of the shots in flight (for the view).
func positions() -> Array[Vector2]:
	var list: Array[Vector2] = []
	for shot: Dictionary in shots:
		list.append(shot["position"])
	return list
