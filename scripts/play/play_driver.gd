class_name PlayDriver
extends Node
## Feeds fixed physics steps into the PlayState (water refill, seed source timers, pickup lifetimes, auto collection).
## Lives under the pausable world node: a paused tree stops it, and resuming banks no stopped time.

var play: PlayState
var player: FlowerPlayer

func setup(play_state: PlayState, flower: FlowerPlayer) -> void:
	play = play_state
	player = flower

func _physics_process(delta: float) -> void:
	play.advance(delta, player.simulation_position)
