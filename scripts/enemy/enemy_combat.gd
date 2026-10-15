class_name EnemyCombat
extends RefCounted
## Connects shots, enemies and drops (P2-02). Display-free.
##   hit_provider -> ProjectileField.enemy_hit_provider (first enemy shape on the shot's path; water passes through)
##   on_enemy_hit -> ProjectileField.enemy_hit (damage by shot kind)
## Defeat rewards: a defeated boar / nest drops seed fruits through PlayState.drop_enemy_fruits (as many as the pickup rules
## leave room for). The carcass of a boar is made by EnemyField itself.

var enemies: EnemyField
var play: PlayState
var tuning: EnemyTuning
## Observability for tests.
var hits: int = 0
var fruits_dropped: int = 0
var fruits_refused: int = 0

func _init(field: EnemyField, play_state: PlayState) -> void:
	enemies = field
	play = play_state
	tuning = field.tuning
	enemies.boar_defeated.connect(_on_boar_defeated)
	enemies.nest_defeated.connect(_on_nest_defeated)

## ProjectileField.enemy_hit_provider: (shot, from, to) -> {} or the EnemyField.hit_test result.
func hit_provider(shot: Dictionary, from: Vector2, to: Vector2) -> Dictionary:
	if String(shot.get("kind", "")) == ProjectileField.KIND_WATER and not tuning.water_hits_enemies:
		return {}
	return enemies.hit_test(from, to)

## ProjectileField.enemy_hit: damages the enemy the hit dictionary names.
func on_enemy_hit(kind: String, _point: Vector2, info: Dictionary) -> void:
	var damage: int = tuning.seed_damage if kind == ProjectileField.KIND_SEED else (tuning.plant_shot_damage if kind != ProjectileField.KIND_WATER else 0)
	hits += 1
	if damage <= 0:
		return
	var what: String = String(info.get("kind", ""))
	if what == "boar":
		enemies.damage_boar(info["boar"] as Boar, damage)
	elif what == "nest":
		enemies.damage_nest(info["nest"] as Nest, damage)

func _drop(center: Vector2, count: int, owner_id: int) -> void:
	var dropped: int = play.drop_enemy_fruits(center, count, owner_id, tuning.drop_radius_min_px, tuning.drop_radius_max_px, tuning.drop_fruit_lifetime_seconds)
	fruits_dropped += dropped
	fruits_refused += count - dropped

func _on_boar_defeated(position: Vector2, boar_id: int) -> void:
	_drop(position, tuning.boar_drop_fruits, GroundPickups.ENEMY_OWNER_BASE + boar_id)

func _on_nest_defeated(nest: Nest) -> void:
	_drop(nest.center_px(enemies.tile_px), tuning.nest_drop_fruits, GroundPickups.ENEMY_OWNER_BASE + 1000000 + nest.id)
