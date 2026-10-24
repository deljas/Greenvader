extends "res://tests/poc3/locust/self_unit.gd"
func run() -> void:
	var base: Dictionary=fixture()
	var state: WorldState=WorldState.new(15,3,base.world.terrain_defs,2468)
	for y: int in 3:
		for x: int in range(5,10): state.terrain[state.index_of(x,y)]=3
	state.apply_terrain_defs(); state.permanent_water=true
	var nav: RefCounted=Nav.new(); nav.setup(state)
	var ai: RefCounted=AI.new(); ai.setup(state,nav)
	state.set_stage(0,WorldState.STAGE_MATURE); state.moisture[0]=100
	var swarm: Array[Dictionary]=[actor(1,Vector2i.ZERO)]
	ai.advance(swarm,no_crops,3.0,3.0)
	var eaten: bool=state.stage[0]==0 and state.moisture[0]==0
	swarm[0].hp=0.0
	ai.advance(swarm,no_crops,0.25,3.25)
	state.set_stage(0,WorldState.STAGE_SEED)
	var dry: bool=state.moisture[0]==0
	var tuning: SimTuning=SimTuning.new()
	tuning.moisture_growth_min=0.5; tuning.moisture_growth_max=1.0; tuning.moisture_decay_per_tick=0
	tuning.far_sweep_start_delay_seconds=0.0
	var growth: GrowthSim=GrowthSim.new(state,tuning)
	var spread: SpreadSim=SpreadSim.new(state,tuning)
	var far: FarSeedSim=FarSeedSim.new(state,tuning)
	# Session constructs FarSeedSim before combat removal transitions a region.
	# Initially stable regions deliberately skip its fair sweep.
	state.set_zone_state(0,WorldState.ZONE_STABLE)
	var limit: int=ceili(far.completion_bound_seconds())
	var used: int=0
	for second: int in limit:
		growth.tick(); growth.tick(); spread.tick(); far.tick()
		used=second+1
		if state.is_fully_greened(): break
	check("eaten_replant_dry_then_stable_isolated_autonomous_complete",eaten and dry and state.is_fully_greened() and state.counters_consistent())
	var file: FileAccess=FileAccess.open(OUT+"regrowth_followup_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"eaten":eaten,"replant_dry":dry,"greened":state.greened_count,"targets":state.target_count,"seconds":used,"bound":limit,"completed":true},"  "))
	file.close(); state.tile_listener=Callable()
	quit(0 if checks[0].status=="PASS" else 1)
