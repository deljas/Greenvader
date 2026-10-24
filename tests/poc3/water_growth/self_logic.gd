extends SceneTree
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Plants: GDScript = preload("res://scripts/poc2/simulation/plants.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const Equivalent: GDScript = preload("res://tests/poc2/view/equivalence.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/water_growth/self/"
var checks: Array[Dictionary] = []
var defs: Array[TerrainDef] = []

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks.append({"name":label,"status":"PASS" if passed else "FAIL","detail":detail})
	print(JSON.stringify(checks.back()))

func world(w: int = 12, h: int = 12, permanent: bool = true) -> WorldState:
	var state: WorldState = WorldState.new(w,h,defs,2468)
	state.apply_terrain_defs()
	state.permanent_water = permanent
	return state

func tuning(permanent: bool = true) -> SimTuning:
	var t: SimTuning = SimTuning.new()
	t.sprout1_growth=15000; t.sprout2_growth=35000; t.mature_growth=60000
	if permanent:
		t.moisture_growth_min=0.5; t.moisture_growth_max=1.0; t.moisture_decay_per_tick=0
	return t

func crop_fixture(kind: String = "watermelon") -> RefCounted:
	var s: RefCounted = Session.new(false)
	s.state=world()
	s.state.debug_fill_stage(Rect2i(0,0,12,12),WorldState.STAGE_MATURE)
	s.growth=GrowthSim.new(s.state,tuning())
	s.plant_system=Plants.new(s)
	s.unlocked[kind]=true; s.seeds=100000
	var placed: Dictionary=s.plant_system.place(kind,Vector2i(2,2),0,false)
	assert(placed.ok)
	return s

func crops() -> void:
	var s: RefCounted=crop_fixture()
	s.plant_system.advance(179.5)
	var before: bool=not s.plants[0].mature and is_equal_approx(s.plants[0].age,89.75)
	s.plant_system.advance(0.5)
	check("watermelon_dry_180",before and s.plants[0].mature and not s.plants[0].watered)
	s.close()
	s=crop_fixture()
	s.plant_system._wet(s.plants[0].pos,1.0,1.0)
	s.plant_system.advance(89.5)
	before=not s.plants[0].mature
	s.plant_system.advance(0.5)
	check("watermelon_wet_90_permanent",before and s.plants[0].mature and s.plants[0].watered)
	s.close()
	s=crop_fixture()
	s.plant_system.advance(60.0)
	s.plant_system._wet(s.plants[0].pos,1.0,1.0)
	var age_at_water: float=s.plants[0].age
	s.plant_system.advance(30.0)
	var repeat: int=s.plant_system._wet(s.plants[0].pos,1.0,1.0)
	s.plant_system.advance(29.5)
	before=not s.plants[0].mature
	s.plant_system.advance(0.5)
	check("watermelon_partial_60_dry_then_60_wet_no_stack",age_at_water==30.0 and repeat==0 and before and s.plants[0].mature)
	var old_id: int=s.plants[0].id
	s.plant_system.remove(old_id,false)
	s.plant_system.place("watermelon",Vector2i(2,2),0,false)
	check("removed_replanted_crop_starts_dry",not s.plants[0].watered and s.plants[0].age==0.0)
	s.plants[0].watered=true; s.plants[0].hp=0.0
	s.plant_system.cleanup_defeated()
	s.plant_system.place("watermelon",Vector2i(2,2),0,false)
	check("destroyed_replanted_crop_starts_dry",not s.plants[0].watered)
	s.close()
	var times: Dictionary={"clover":20.0,"carrot":15.0,"wheat":45.0,"rafflesia":30.0,"watermelon":90.0}
	var correct: bool=true
	for kind: String in times:
		correct=correct and Session.CATALOG[kind].maturity==times[kind]
	check("catalog_base_times",correct)

func grass() -> void:
	for wet: bool in [false,true]:
		var state: WorldState=world()
		state.set_stage(0,WorldState.STAGE_SEED)
		if wet: state.set_moisture(0,100)
		var g: GrowthSim=GrowthSim.new(state,tuning())
		var count: int=60 if wet else 120
		for tick: int in count-1: g.tick()
		var before: bool=state.stage[0]<WorldState.STAGE_MATURE
		g.tick()
		check("grass_wet_30" if wet else "grass_dry_60",before and state.stage[0]==4 and state.moisture[0]==0 and state.active_tiles.is_empty())
	var s: RefCounted=Session.new(false)
	s.state=world(); s.sim_tuning=tuning(); s.sim_tuning.max_growth_tiles_per_tick=1
	for i: int in 3: s.state.set_stage(i,WorldState.STAGE_SEED)
	s.growth=GrowthSim.new(s.state,s.sim_tuning)
	s.plant_system=Plants.new(s)
	for i: int in 20: s.growth.tick()
	var lag_before: int=s.growth.ticks-s.state.last_growth_tick[2]
	s.plant_system._wet(Coords.cell_center_logic(Vector2i(2,0)),1.0,1.0)
	var partial: int=s.state.growth[2]
	s.plant_system._wet(Coords.cell_center_logic(Vector2i(2,0)),1.0,1.0)
	for i: int in 49: s.growth.tick()
	s.growth.catch_up()
	var before_mature: bool=s.state.stage[2]<4
	s.growth.tick(); s.growth.catch_up()
	check("split_lag_partial_water_no_retroactive_boost",lag_before>0 and partial==10000 and before_mature and s.state.stage[2]==4 and s.state.moisture[2]==0,{"pending_before":lag_before,"at_water":partial})
	# External food damage is immediately saveable and leaves another tile's lag untouched.
	var last_other: int=s.state.last_growth_tick[1]
	s.state.set_moisture(0,100)
	s.state.set_stage(0,WorldState.STAGE_EMPTY)
	var snapshot: Dictionary=s.growth.to_dict()
	var restored: WorldState=WorldState.from_dict(s.state.to_dict(),defs)
	restored.permanent_water=true
	var restored_growth: GrowthSim=GrowthSim.new(restored,s.sim_tuning)
	check("food_damage_active_order_lag_immediate_restore",s.state.moisture[0]==0 and s.state.active_flag[0]==0 and s.state.last_growth_tick[1]==last_other and restored_growth.load_dict(snapshot))
	s.state.set_stage(0,WorldState.STAGE_SEED)
	check("food_damage_regrowth_starts_dry",s.state.moisture[0]==0 and s.state.growth[0]==0)
	var empty: int=10
	var mature: int=11
	s.state.set_stage(mature,WorldState.STAGE_MATURE)
	s.plant_system._wet(Coords.cell_center_logic(Vector2i(empty,0)),5.0,1.0)
	check("water_empty_mature_no_prewater",s.state.moisture[empty]==0 and s.state.stage[empty]==0 and s.state.moisture[mature]==0 and s.state.stage[mature]==4)
	s.close()
	# The default shared API still uses the original temporary-water simulation.
	var legacy: WorldState=world(2,1,false)
	legacy.set_moisture(0,100); legacy.set_stage(1,1)
	var legacy_g: GrowthSim=GrowthSim.new(legacy,tuning(false))
	legacy_g.tick()
	check("legacy_opt_in_defaults_unchanged",legacy.moisture[0]==99 and legacy.growth[1]==1000)

func sprinkler() -> void:
	var s: RefCounted=crop_fixture("clover")
	s.nav=Session.Navigation.new(); s.nav.setup(s.state)
	var dry_grass: int=s.state.index_of(1,2)
	s.state.set_stage(dry_grass,0); s.state.set_stage(dry_grass,1)
	var pos: Vector2=Coords.cell_center_logic(Vector2i(1,2))
	var h: Dictionary={"home":pos,"pos":pos,"status":"working","water_task":"","water":10.0,"search_at":0.0,"target_pos":Vector2(-1,-1),"bank":Vector2(-1,-1)}
	var first: Vector2=s.plant_system._work_target(h,true)
	check("sprinkler_crop_priority_over_nearer_grass",first==s.plants[0].pos)
	s.plant_system._sprinkler(h,0.25)
	var water_after: float=h.water
	var again: Vector2=s.plant_system._work_target(h,true)
	s.plant_system._sprinkler(h,0.25)
	check("sprinkler_one_water_then_reselect_no_wet_repeat",s.plants[0].watered and s.state.moisture[dry_grass]==100 and water_after==9.0 and h.water==9.0 and again.x<0.0)
	s.close()

func isolated() -> void:
	var state: WorldState=world(15,3)
	# A water band separates two plantable components.
	for y: int in 3:
		for x: int in range(5,10): state.terrain[state.index_of(x,y)]=3
	state.apply_terrain_defs()
	var t: SimTuning=tuning()
	t.far_sweep_start_delay_seconds=0.0
	var g: GrowthSim=GrowthSim.new(state,t)
	var spread: SpreadSim=SpreadSim.new(state,t)
	var far: FarSeedSim=FarSeedSim.new(state,t)
	state.set_zone_state(0,WorldState.ZONE_STABLE)
	state.set_stage(0,1); state.set_moisture(0,100)
	var noninherit: bool=false
	var limit: int=ceili(far.completion_bound_seconds())
	for second: int in limit:
		g.tick(); g.tick(); spread.tick(); far.tick()
		for index: int in state.tile_count():
			if state.natural[index]==1 and state.stage[index]>0 and state.stage[index]<4:
				noninherit=noninherit or state.moisture[index]==0
		if state.is_fully_greened(): break
	check("isolated_dry_autonomous_100_percent",state.is_fully_greened() and state.counters_consistent(),{"greened":state.greened_count,"targets":state.target_count,"bound_seconds":limit})
	check("natural_destination_does_not_inherit_water",noninherit)
	state.tile_listener=Callable()

func save_cases(s: RefCounted) -> void:
	s.enemies.clear(); s.nests.clear()
	s.seeds=10000; s.unlocked.watermelon=true
	s.plant_system.place("watermelon",Vector2i(185,185),0,false)
	s.plant_system._wet(s.plants[0].pos,1.0,1.0)
	var a: int=s.state.index_of(182,184)
	var b: int=s.state.index_of(183,184)
	s.state.set_stage(a,0); s.state.set_stage(a,1)
	s.state.set_stage(b,0); s.state.set_stage(b,1)
	s.sim_tuning.max_growth_tiles_per_tick=1
	s.advance_game(0.5)
	s.state.set_moisture(b,100)
	s.state.set_stage(a,WorldState.STAGE_EMPTY)
	var lag_before: Dictionary=s.growth.to_dict()
	var before: Dictionary=s.to_dict()
	var saved: Dictionary=Save.save_game(s)
	var loaded: Dictionary=Save.load_game()
	check("actual_session_json_save_restore_after_food_damage",saved.ok and loaded.ok and Equivalent.same(before,loaded.session.to_dict()) if loaded.ok else false,loaded.get("reason",""))
	if loaded.ok:
		print("save growth before/after: ",lag_before," / ",loaded.session.growth.to_dict())
		check("actual_restore_keeps_water_progress_and_lag",loaded.session.plants[0].watered and loaded.session.state.moisture[b]==100 and Equivalent.same(lag_before,loaded.session.growth.to_dict()))
		loaded.session.close()
	var invalid: Dictionary=before.duplicate(true)
	invalid.entities.plants[0].watered="yes"
	var rejected: Dictionary=s.restore(invalid)
	check("invalid_watered_rejected_atomically",not rejected.ok and Equivalent.same(before,s.to_dict()),rejected)
	# One representative older working save: crop temporary wet at save time;
	# growing grass positive moisture, mature grass and wasteland moisture normalize.
	var old: Dictionary=before.duplicate(true)
	old.entities.plants[0].erase("watered")
	old.entities.plants[0].wet_until=s.clock.elapsed+1.0
	var moisture: PackedByteArray=WorldState._unpack_bytes(old.world.moisture)
	moisture[b]=7
	var mature: int=s.state.index_of(184,184)
	var empty: int=s.state.index_of(181,181)
	moisture[mature]=9; moisture[empty]=11
	old.world.moisture=WorldState._pack_bytes(moisture)
	var order: PackedInt32Array=WorldState._unpack_bytes(old.growth.active).to_int32_array()
	var lags: PackedInt32Array=WorldState._unpack_bytes(old.growth.lag).to_int32_array()
	order.append(mature); order.append(empty); lags.append(0); lags.append(0)
	old.growth.active=WorldState._pack_bytes(order.to_byte_array()); old.growth.lag=WorldState._pack_bytes(lags.to_byte_array())
	var migrated: Dictionary=s.restore(old)
	print("migration growth before/after: ",lag_before," / ",s.growth.to_dict())
	check("working_save_water_migration_preserves_growing_lag",migrated.ok and s.plants[0].watered and s.state.moisture[b]==100 and s.state.moisture[mature]==0 and s.state.moisture[empty]==0 and Equivalent.same(lag_before,s.growth.to_dict()),migrated)

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/water_growth/self/profile/"):
		push_error("profile not isolated"); quit(1); return
	var s: RefCounted=Session.new()
	defs=s.state.terrain_defs
	var followup: bool="--save-followup" in OS.get_cmdline_user_args()
	if not followup:
		crops(); grass(); sprinkler(); isolated()
	save_cases(s)
	s.close()
	var failures: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+("save_followup_results.json" if followup else "logic_results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"not_run":["GPU rendering","native physical input","full regression reserved for integration"]},"  "))
	file.close()
	quit(1 if failures>0 else 0)
