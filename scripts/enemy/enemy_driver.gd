class_name EnemyDriver
extends Node
## Feeds fixed physics steps into the EnemyField. Lives under the pausable world node: a paused tree stops it, and
## resuming banks no stopped time.

var enemies: EnemyField

func setup(field: EnemyField) -> void:
	enemies = field

func _physics_process(delta: float) -> void:
	enemies.advance(delta)
