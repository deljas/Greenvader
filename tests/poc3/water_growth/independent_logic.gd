extends SceneTree
const Session = preload("res://scripts/poc2/poc2_session.gd")
const Plants = preload("res://scripts/poc2/simulation/plants.gd")
const Save = preload("res://scripts/poc2/save/poc2_save.gd")
const Equivalent = preload("res://tests/poc2/view/equivalence.gd")
const Coords = preload("res://scripts/poc/poc_coords.gd")
const OUT = "res://evidence/poc3/water_growth/independent/"
var rows: Array[Dictionary] = []
var defs: Array[TerrainDef] = []
var followup: bool = false

func _init() -> void:
	call_deferred("run")

func record(id: String, ok: bool, detail: Variant = "") -> void:
	if followup and id != "JSON_SAME_TICKS_CONTINUATION": return
	rows.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	print(JSON.stringify(rows.back()))

func small(permanent: bool = true) -> RefCounted:
	var s: RefCounted = Session.new(false)
	s.state = WorldState.new(24,24,defs,837)
	s.state.apply_terrain_defs()
	s.state.permanent_water = permanent
	s.sim_tuning = SimTuning.new()
	s.sim_tuning.sprout1_growth = 15000
	s.sim_tuning.sprout2_growth = 35000
	s.sim_tuning.mature_growth = 60000
	if permanent:
		s.sim_tuning.moisture_growth_min = 0.5
		s.sim_tuning.moisture_growth_max = 1.0
		s.sim_tuning.moisture_decay_per_tick = 0
	s.growth = GrowthSim.new(s.state,s.sim_tuning)
	s.plant_system = Plants.new(s)
	s.nav = Session.Navigation.new()
	s.nav.setup(s.state)
	s.seeds = 10000
	return s

func crop() -> void:
	var s: RefCounted = small()
	s.state.debug_fill_stage(Rect2i(0,0,24,24),4)
	s.unlocked.wheat = true
	var placed: Dictionary = s.plant_system.place("wheat",Vector2i(10,10),0,false)
	assert(placed.ok)
	# Wheat T=45: 18 dry seconds earn 9 seconds of progress. Water leaves 36 seconds.
	s.plant_system.advance(18.0)
	var first: int = s.plant_system._wet(s.plants[0].pos,1.0,99.0)
	var age_at_water: float = s.plants[0].age
	s.plant_system.advance(11.0)
	var repeat: int = s.plant_system._wet(s.plants[0].pos,1.0,99.0)
	s.plant_system.advance(24.5)
	var just_before: bool = not s.plants[0].mature and s.plants[0].age == 44.5
	s.plant_system.advance(0.5)
	record("CROP_PROGRESS_REPEAT",first == 1 and repeat == 0 and age_at_water == 9.0 and just_before and s.plants[0].mature,{"age_at_water":age_at_water,"final_age":s.plants[0].age,"first":first,"repeat":repeat})
	s.plant_system.remove(s.plants[0].id,false)
	s.plant_system.place("wheat",Vector2i(10,10),0,false)
	record("CROP_REPLANT_DRY",s.plants[0].age == 0.0 and s.plants[0].watered == false)
	s.close()

func grass() -> void:
	var s: RefCounted = small()
	s.sim_tuning.max_growth_tiles_per_tick = 1
	for index: int in 4:
		s.state.set_stage(index,1)
	for tick: int in 7:
		s.growth.tick()
	var lag: int = s.growth.ticks - s.state.last_growth_tick[3]
	s.plant_system._wet(Coords.cell_center_logic(Vector2i(3,0)),0.5,99.0)
	var at_water: int = s.state.growth[3]
	# Old dry grass takes 30 seconds; PoC3 dry takes 60. At 3.5 sec: 3500/60000.
	for tick: int in 4:
		s.growth.tick()
	var unrelated_last: int = s.state.last_growth_tick[2]
	var repeat: int = s.plant_system._wet(Coords.cell_center_logic(Vector2i(3,0)),0.5,99.0)
	var untouched: bool = s.state.last_growth_tick[2] == unrelated_last
	s.growth.catch_up()
	record("GRASS_PARTIAL_PENDING_LAG",lag == 3 and at_water == 3500 and s.state.growth[3] == 7500,{"lag_before":lag,"at_water":at_water,"after_2_wet_seconds":s.state.growth[3]})
	record("GRASS_REPEAT_NO_EXTRA_SWEEP",repeat == 0 and untouched and s.state.moisture[3] == 100)
	s.state.set_stage(3,0)
	var immediately_dry: bool = s.state.moisture[3] == 0 and s.state.active_flag[3] == 0
	s.state.set_stage(3,1)
	record("GRASS_EATEN_REGROW_DRY",immediately_dry and s.state.growth[3] == 0 and s.state.moisture[3] == 0)
	s.close()
	s = small(false)
	s.state.set_stage(0,1)
	s.state.set_moisture(1,100)
	s.growth.tick()
	record("LEGACY_OPT_IN_FALSE",not s.state.permanent_water and s.state.growth[0] == 1000 and s.state.moisture[1] == 99)
	s.close()

func sprinkler() -> void:
	var s: RefCounted = small()
	s.state.debug_fill_stage(Rect2i(0,0,24,24),4)
	s.plant_system.place("clover",Vector2i(11,12),0,false)
	s.plant_system.place("clover",Vector2i(7,12),0,false)
	s.plants[1].watered = true
	var i: int = s.state.index_of(8,12)
	s.state.set_stage(i,0)
	s.state.set_stage(i,1)
	var p: Vector2 = Coords.cell_center_logic(Vector2i(8,12))
	var h: Dictionary = {"home":p,"pos":p,"status":"working","water_task":"","water":6.0,"search_at":0.0,"target_pos":Vector2(-1,-1),"bank":Vector2(-1,-1)}
	var target: Vector2 = s.plant_system._work_target(h,true)
	record("SPRINKLER_CROP_FIRST_WET_SKIP",target == s.plants[0].pos,{"target":str(target),"dry_crop":str(s.plants[0].pos)})
	s.plant_system._sprinkler(h,0.75)
	var water_after: float = h.water
	var next: Vector2 = s.plant_system._work_target(h,true)
	s.plant_system._sprinkler(h,0.75)
	record("SPRINKLER_ONE_CHARGE_RESELECT",s.plants[0].watered and s.state.moisture[i] == 100 and water_after == 5.0 and h.water == 5.0 and next.x < 0.0,{"water_first":water_after,"water_second":h.water,"next":str(next)})
	s.close()

func save_boundary() -> void:
	var s: RefCounted = Session.new()
	s.enemies.clear()
	s.nests.clear()
	s.seeds = 10000
	var planted: Dictionary = s.plant_system.place("clover",Vector2i(190,186),0,false)
	assert(planted.ok)
	s.plant_system._wet(s.plants[0].pos,1.0,1.0)
	var indices: Array[int] = []
	for x: int in range(181,185):
		var index: int = s.state.index_of(x,184)
		indices.append(index)
		s.state.set_stage(index,0)
		s.state.set_stage(index,1)
	s.sim_tuning.max_growth_tiles_per_tick = 1
	s.advance_game(1.5)
	# Simulate the existing food damage stage transition; do not advance growth before save.
	s.state.set_stage(indices[0],0)
	s.state.set_moisture(indices[3],100)
	var before: Dictionary = s.to_dict()
	var saved: Dictionary = Save.save_game(s)
	var actual: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://poc3_saves/slot1.json"))
	var loaded: Dictionary = Save.load_game()
	var equal: bool = loaded.ok and Equivalent.same(before,loaded.session.to_dict())
	record("JSON_SAVE_IMMEDIATE_DAMAGE",saved.ok and actual is Dictionary and equal,{"saved":saved.ok,"loaded":loaded.ok,"full_state_equal":equal,"growth":before.growth})
	if loaded.ok:
		# Restored GrowthSim owns the disposable candidate's tuning resource.
		loaded.session.growth.tuning.max_growth_tiles_per_tick = 1
		s.advance_game(2.0)
		loaded.session.advance_game(2.0)
		record("JSON_SAME_TICKS_CONTINUATION",Equivalent.same(s.to_dict(),loaded.session.to_dict()))
		loaded.session.close()
	else:
		record("JSON_SAME_TICKS_CONTINUATION",false,"restore failed")
	var current: Dictionary = s.to_dict()
	var invalid: Dictionary = current.duplicate(true)
	invalid.entities.plants[0].watered = 1
	var rejected: Dictionary = s.restore(invalid)
	record("WATERED_NON_BOOL_ATOMIC_REJECT",not rejected.ok and Equivalent.same(current,s.to_dict()),rejected)
	# Missing watered with wet_until exactly at saved clock is dry; positive grass moisture migrates.
	var old: Dictionary = current.duplicate(true)
	old.entities.plants[0].erase("watered")
	old.entities.plants[0].wet_until = old.clock.elapsed
	var bytes: PackedByteArray = WorldState._unpack_bytes(old.world.moisture)
	bytes[indices[3]] = 1
	old.world.moisture = WorldState._pack_bytes(bytes)
	var migrated: Dictionary = s.restore(old)
	record("MIGRATION_EQUAL_CLOCK_DRY_GRASS_WET",migrated.ok and not s.plants[0].watered and s.state.moisture[indices[3]] == 100 and Equivalent.same(current.growth,s.growth.to_dict()),migrated)
	s.close()

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/water_growth/independent/profile/"):
		push_error("Independent profile isolation failed")
		quit(2)
		return
	var s: RefCounted = Session.new()
	defs = s.state.terrain_defs
	s.close()
	followup = "--continuation-followup" in OS.get_cmdline_user_args()
	if not followup:
		crop()
		grass()
		sprinkler()
	save_boundary()
	var fails: int = 0
	for row: Dictionary in rows:
		if row.status == "FAIL": fails += 1
	var file: FileAccess = FileAccess.open(OUT+("continuation_followup.json" if followup else "results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":rows,"failures":fails,"engine":Engine.get_version_info(),"user_dir":OS.get_user_data_dir()},"  "))
	file.close()
	quit(1 if fails else 0)
