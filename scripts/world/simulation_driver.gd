class_name SimulationDriver
extends Node
## Feeds fixed physics steps into the SimClock. Lives under a pausable node, so the tree
## pause stops it; resuming adds no banked time. Tick logic (P1-03 / P1-04) connects to the clock signals.

var clock: SimClock = SimClock.new()
var world: WorldState
var tuning: SimTuning

func setup(world_state: WorldState, sim_tuning: SimTuning) -> void:
	world = world_state
	tuning = sim_tuning
	clock.configure(sim_tuning)

func _physics_process(delta: float) -> void:
	clock.advance(delta)
