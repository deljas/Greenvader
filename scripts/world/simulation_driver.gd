class_name SimulationDriver
extends Node
## Feeds fixed physics steps into the SimClock. Lives under a pausable node, so the tree
## pause stops it; resuming adds no banked time. Tick logic connects to the clock signals.

var clock: SimClock = SimClock.new()
var world: WorldState
var tuning: SimTuning
## Growth ticks (P1-03): connected to the clock's growth tick in setup().
var growth: GrowthSim
## Natural spread (P1-04): connected to the clock's spread tick in setup().
var spread: SpreadSim
## Far seed spreading (P2-05): stable zones reach 100 % without input. Runs on the spread tick, after SpreadSim.
var far: FarSeedSim

func setup(world_state: WorldState, sim_tuning: SimTuning) -> void:
	world = world_state
	tuning = sim_tuning
	clock.configure(sim_tuning)
	growth = GrowthSim.new(world_state, sim_tuning)
	spread = SpreadSim.new(world_state, sim_tuning)
	far = FarSeedSim.new(world_state, sim_tuning)
	clock.growth_ticked.connect(_on_growth_ticked)
	clock.spread_ticked.connect(_on_spread_ticked)

func _on_growth_ticked(_tick_index: int) -> void:
	growth.tick()

func _on_spread_ticked(_tick_index: int) -> void:
	spread.tick()
	far.tick()

func _physics_process(delta: float) -> void:
	clock.advance(delta)
