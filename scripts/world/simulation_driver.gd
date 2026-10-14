class_name SimulationDriver
extends Node
## Feeds fixed physics steps into the SimClock. Lives under a pausable node, so the tree
## pause stops it; resuming adds no banked time. Tick logic (P1-03 / P1-04) connects to the clock signals.

var clock: SimClock = SimClock.new()
var world: WorldState
var tuning: SimTuning
## Growth ticks (P1-03): connected to the clock's growth tick in setup().
var growth: GrowthSim

func setup(world_state: WorldState, sim_tuning: SimTuning) -> void:
	world = world_state
	tuning = sim_tuning
	clock.configure(sim_tuning)
	growth = GrowthSim.new(world_state, sim_tuning)
	clock.growth_ticked.connect(_on_growth_ticked)

func _on_growth_ticked(_tick_index: int) -> void:
	growth.tick()

func _physics_process(delta: float) -> void:
	clock.advance(delta)
