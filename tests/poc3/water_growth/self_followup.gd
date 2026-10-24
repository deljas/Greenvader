extends "res://tests/poc3/water_growth/self_logic.gd"

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/water_growth/self/profile/"):
		quit(1); return
	var s: RefCounted=Session.new()
	defs=s.state.terrain_defs
	s.enemies.clear(); s.nests.clear()
	var a: int=s.state.index_of(182,184)
	var b: int=s.state.index_of(183,184)
	for index: int in [a,b]:
		s.state.set_stage(index,0); s.state.set_stage(index,1)
	s.sim_tuning.max_growth_tiles_per_tick=1
	s.advance_game(0.5)
	s.state.set_moisture(b,100)
	s.state.set_stage(a,0)
	var saved: Dictionary=Save.save_game(s)
	var loaded: Dictionary=Save.load_game()
	if loaded.ok:
		loaded.session.growth.tuning.max_growth_tiles_per_tick=1
		s.advance_game(1.0); loaded.session.advance_game(1.0)
		check("saved_food_damage_continues_same_ticks_full_state",saved.ok and Equivalent.same(s.to_dict(),loaded.session.to_dict()),{"ticks":s.growth.ticks,"growth":s.state.growth[b],"moisture":s.state.moisture[b]})
		loaded.session.close()
	else:
		check("saved_food_damage_continues_same_ticks_full_state",false,loaded)
	s.close()
	# Exercise the provider (non-detached) growth path and avoid global catch-up
	# when the splash contains only already-watered / mature / empty grass.
	s=Session.new(false)
	s.state=world(); s.sim_tuning=tuning(); s.sim_tuning.max_growth_tiles_per_tick=1
	s.growth=GrowthSim.new(s.state,s.sim_tuning)
	s.growth.sunlight_provider=func(_index: int) -> float: return 1.0
	s.plant_system=Plants.new(s)
	for index: int in 3: s.state.set_stage(index,1)
	s.state.set_moisture(0,100)
	for tick: int in 4: s.growth.tick()
	var pending: int=s.state.last_growth_tick[2]
	s.plant_system._wet(Coords.cell_center_logic(Vector2i(0,0)),1.0,1.0)
	check("repeat_water_does_not_sweep_unrelated_lag",s.state.last_growth_tick[2]==pending)
	for tick: int in 56: s.growth.tick()
	s.growth.catch_up()
	check("sunlight_provider_maturity_clears_water_and_active",s.state.stage[0]==4 and s.state.moisture[0]==0 and s.state.active_flag[0]==0 and s.state.growth[1]==30000)
	s.close()
	var failed: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failed+=1
	var file: FileAccess=FileAccess.open(OUT+"continuation_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failed},"  "))
	file.close()
	quit(1 if failed else 0)
