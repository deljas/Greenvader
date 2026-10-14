class_name ProjectileField
extends Node2D
## Seed and water shots in flight. Each shot flies in a straight line to its target point (the aim point,
## clipped to the range) and lands exactly there. Only time passed to advance() moves shots, so a paused
## parent (this node is PROCESS_MODE_PAUSABLE) freezes them and nothing is banked for later.
##
## Enemy hit entry (P2 fills it in): set `enemy_hit_provider` to a Callable
##   (shot: Dictionary, from: Vector2, to: Vector2) -> Dictionary
## returning {} for no hit, or {"point": Vector2, ...} for a hit; the shot then ends there and
## `enemy_hit(kind, point, info)` is emitted instead of `landed`. Unset (default) means no enemy is ever hit.

signal landed(kind: String, point: Vector2)
signal enemy_hit(kind: String, point: Vector2, info: Dictionary)
## A shot ended in the air without landing or hitting (safety lifetime). Owners of held-back costs release them here.
signal expired(kind: String, point: Vector2)

const KIND_SEED: String = "seed"
const KIND_WATER: String = "water"

var tuning: PlayTuning
var shots: Array[Dictionary] = []
var enemy_hit_provider: Callable = Callable()

func setup(play_tuning: PlayTuning) -> void:
	tuning = play_tuning
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func is_full() -> bool:
	return shots.size() >= tuning.max_projectiles

## Launches a shot from `origin` toward `aim_point`. Returns the landing point, or Vector2.INF when refused (full).
func launch(kind: String, origin: Vector2, aim_point: Vector2, fallback_direction: Vector2) -> Vector2:
	if is_full():
		return Vector2.INF
	var offset: Vector2 = aim_point - origin
	var direction: Vector2 = offset.normalized() if offset.length_squared() > 0.0001 else fallback_direction
	var distance: float = minf(offset.length(), tuning.projectile_range_px)
	var target: Vector2 = origin + direction * distance
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = PixelArt.water() if kind == KIND_WATER else PixelArt.seed()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = origin.round()
	add_child(sprite)
	shots.append({"kind": kind, "position": origin, "origin": origin, "target": target, "direction": direction, "total": distance, "traveled": 0.0, "age": 0.0, "sprite": sprite})
	return target

func query_enemy_hit(shot: Dictionary, from: Vector2, to: Vector2) -> Dictionary:
	if not enemy_hit_provider.is_valid():
		return {}
	return enemy_hit_provider.call(shot, from, to)

func _physics_process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	delta = minf(delta, tuning.max_step_seconds)
	for index: int in range(shots.size() - 1, -1, -1):
		var shot: Dictionary = shots[index]
		shot["age"] = float(shot["age"]) + delta
		var from: Vector2 = shot["position"]
		var remaining: float = float(shot["total"]) - float(shot["traveled"])
		var step: float = tuning.projectile_speed * delta
		var arrives: bool = step >= remaining
		var to: Vector2 = Vector2(shot["target"]) if arrives else from + Vector2(shot["direction"]) * step
		var hit: Dictionary = query_enemy_hit(shot, from, to)
		var sprite: Sprite2D = shot["sprite"]
		if not hit.is_empty():
			_finish(index)
			enemy_hit.emit(String(shot["kind"]), Vector2(hit.get("point", to)), hit)
			continue
		shot["traveled"] = float(shot["traveled"]) + (remaining if arrives else step)
		shot["position"] = to
		sprite.position = to.round()
		if arrives:
			_finish(index)
			landed.emit(String(shot["kind"]), to)
		elif float(shot["age"]) > tuning.projectile_max_age:
			_finish(index)
			expired.emit(String(shot["kind"]), to)

func _finish(index: int) -> void:
	var sprite: Sprite2D = shots[index]["sprite"]
	sprite.queue_free()
	shots.remove_at(index)
