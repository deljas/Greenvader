class_name PlayDriver
extends Node
## Feeds fixed physics steps into the PlayState (water refill, seed source timers, pickup lifetimes, auto collection, the damage
## state). Lives under the pausable world node: a paused tree stops it, and resuming banks no stopped time.
## It also applies what the damage state asks of the player: the push of a hit and the return to the start.

var play: PlayState
var player: FlowerPlayer

func setup(play_state: PlayState, flower: FlowerPlayer) -> void:
	play = play_state
	player = flower
	player.health = play.health
	play.health.respawn_position = player.simulation_position
	play.health.knocked.connect(_on_knocked)
	play.health.revived.connect(_on_revived)

func _on_knocked(motion: Vector2) -> void:
	player.step(motion)

func _on_revived(location: Vector2) -> void:
	player.teleport(location)

func _physics_process(delta: float) -> void:
	play.advance(delta, player.simulation_position)
