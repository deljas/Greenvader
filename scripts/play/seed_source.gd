class_name SeedSource
extends RefCounted
## Indestructible seed supply in the safe zone. Drops a seed fruit around itself on a fixed interval
## while fewer than the cap of its own fruits lie on the ground. Nothing can damage it (no health, no damage API).

const INDESTRUCTIBLE: bool = true

var id: int = 1
var position: Vector2 = Vector2.ZERO
## Seconds counted toward the next drop. Only counts while the source has room for another fruit.
var timer: float = 0.0
## Drops so far; part of the fixed random sequence of drop positions.
var drops: int = 0

func _init(source_id: int = 1, source_position: Vector2 = Vector2.ZERO) -> void:
	id = source_id
	position = source_position

## Advances the drop timer. Returns the number of fruits dropped.
func advance(delta: float, pickups: GroundPickups, tuning: PlayTuning) -> int:
	if delta <= 0.0:
		return 0
	var dropped: int = 0
	if pickups.count_owned(id) >= tuning.source_fruit_cap:
		timer = 0.0
		return 0
	timer += delta
	while timer >= tuning.source_interval_seconds and pickups.count_owned(id) < tuning.source_fruit_cap:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = tuning.scatter_seed * 1000003 + id * 7919 + drops
		var angle: float = rng.randf() * TAU
		var radius: float = lerpf(tuning.source_drop_radius_min_px, tuning.source_drop_radius_max_px, rng.randf())
		if not pickups.spawn(GroundPickups.KIND_SEED_FRUIT, position + Vector2(cos(angle), sin(angle)) * radius, id):
			timer = tuning.source_interval_seconds
			break
		drops += 1
		dropped += 1
		timer -= tuning.source_interval_seconds
	if pickups.count_owned(id) >= tuning.source_fruit_cap:
		timer = 0.0
	return dropped

func to_dict() -> Dictionary:
	return {"id": id, "timer": timer, "drops": drops}

func load_dict(data: Dictionary) -> bool:
	if int(data.get("id", -1)) != id:
		return false
	timer = maxf(float(data.get("timer", 0.0)), 0.0)
	drops = maxi(int(data.get("drops", 0)), 0)
	return true
