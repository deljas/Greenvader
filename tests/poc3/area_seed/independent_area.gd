extends SceneTree
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Combat: GDScript = preload("res://scripts/poc2/simulation/combat.gd")
const Area: GDScript = preload("res://scripts/poc2/simulation/seed_area.gd")
const Placement: GDScript = preload("res://scripts/poc/assets/placement.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const OUT: String = "res://evidence/poc3/area_seed/independent/results.json"

class Arena extends RefCounted:
	var state: WorldState
	var placement: RefCounted
	var combat_system: RefCounted
	var position: Vector2 = Vector2(10,50) # cell2,12
	var aim: Vector2 = Vector2(50,50) # cell12,12
	var has_aim: bool = true
	var paused: bool = false
	var hp: float = 100.0
	var seeds: int = 20
	var sow_width: int = 3
	var shot_ready: float = 0.0
	var clock: SimClock = SimClock.new()
	var shots: Array[Dictionary] = []
	var enemies: Array[Dictionary] = []
	var nests: Array[Dictionary] = []
	var helpers: Array[Dictionary] = []
	var fossils: Array[Dictionary] = []
	var next_id: int = 1
	func _init() -> void:
		var defs: Array[TerrainDef] = []
		for key: String in ["wasteland","safe","shore","water","building","shallows","paved"]:
			defs.append(load(("res://data/poc/terrain/" if key == "paved" else "res://data/terrain/")+key+".tres") as TerrainDef)
		state = WorldState.new(24,24,defs,123)
		placement = Placement.new()
		placement.seal_enclosed = false
		placement.attach(state,state.terrain.duplicate())
		combat_system = Combat.new(self)
	func allocate_id() -> int:
		var id: int = next_id
		next_id += 1
		return id
	func result(ok: bool, reason: String = "") -> Dictionary:
		return {"ok":ok,"reason":reason}
	func close() -> void:
		combat_system.s = null

var checks: Array[Dictionary] = []
func _init() -> void: call_deferred("_run")
func _check(name: String, ok: bool, observed: Dictionary = {}) -> void:
	checks.append({"name":name,"status":"PASS" if ok else "FAIL","observed":observed})
	print(JSON.stringify(checks.back()))
func _seed_count(world: WorldState) -> int:
	var count: int = 0
	for stage: int in world.stage:
		if stage == WorldState.STAGE_SEED: count += 1
	return count

func _run() -> void:
	var profile: String = OS.get_user_data_dir().replace("\\","/")
	if DisplayServer.get_name() != "headless" or not profile.begins_with("C:/godot/greenvader/evidence/poc3/area_seed/independent/profile/"):
		quit(2)
		return
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT))
	var a: Arena = Arena.new()
	var fired: Dictionary = a.combat_system.fire(false)
	var one_reserved: bool = a.seeds == 19 and a.shots.size() == 1
	a.combat_system._shots(0.5)
	_check("representative_3_square_spends_nine",fired.ok and one_reserved and _seed_count(a.state) == 9 and a.seeds == 11 and a.shots.is_empty(),{"seeded":_seed_count(a.state),"balance":a.seeds})
	a.close()
	a = Arena.new()
	var edge: Dictionary = Area.plan(a.state,Vector2i(0,0),5,9)
	var edge_order: Array[Vector2i] = [Vector2i(0,0),Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(2,0),Vector2i(0,2),Vector2i(2,1),Vector2i(1,2),Vector2i(2,2)]
	_check("map_edge_clips_without_moving_center",edge.center == Vector2i(0,0) and edge.rect == Rect2i(-2,-2,5,5) and edge.affordable == edge_order and edge.cost == 9,{"cells":str(edge.affordable),"cost":edge.cost})
	a.close()
	a = Arena.new()
	a.seeds = 2
	a.state.terrain[a.state.index_of(12,11)] = 3 # north water
	a.state.terrain[a.state.index_of(11,11)] = 4 # northwest building
	a.placement.attach(a.state,a.state.terrain.duplicate())
	a.state.set_stage(a.state.index_of(11,12),WorldState.STAGE_SEED)
	a.state.set_stage(a.state.index_of(12,13),WorldState.STAGE_MATURE)
	a.state.occupy(Rect2i(13,12,1,1),9001)
	a.helpers.append({"hp":10.0,"pos":Vector2(46,54),"cell":Vector2i(0,0)}) # current cell11,13
	var mixed: Dictionary = Area.plan(a.state,Vector2i(12,12),3,2,a.helpers)
	var ordered: bool = mixed.valid == [Vector2i(12,12),Vector2i(13,11),Vector2i(13,13)] and mixed.affordable == [Vector2i(12,12),Vector2i(13,11)] and mixed.unaffordable == [Vector2i(13,13)]
	fired = a.combat_system.fire(false)
	a.combat_system._shots(0.5)
	_check("mixed_exclusions_manual_order_and_budget",ordered and fired.ok and a.seeds == 0 and _seed_count(a.state) == 3 and a.state.stage[a.state.index_of(12,12)] == 1 and a.state.stage[a.state.index_of(13,11)] == 1 and a.state.stage[a.state.index_of(13,13)] == 0,{"planned_order":str(mixed.valid),"balance":a.seeds,"existing_plus_new_seeds":_seed_count(a.state)})
	a.close()
	var hit_results: Array[Dictionary] = []
	var hits_ok: bool = true
	for category: String in ["enemy","nest"]:
		a = Arena.new()
		a.seeds = 1
		a.sow_width = 7
		var target: Dictionary = {"id":99,"kind":"boar","pos":Vector2(42,50),"hp":20.0,"max_hp":20.0,"initial":false,"strong":false}
		if category == "enemy": a.enemies.append(target)
		else: a.nests.append(target)
		fired = a.combat_system.fire(false)
		a.combat_system._shots(0.5)
		hits_ok = hits_ok and fired.ok and target.hp == 15.0 and a.seeds == 0 and _seed_count(a.state) == 0 and a.shots.is_empty()
		hit_results.append({"target":category,"hp":target.hp,"balance":a.seeds,"ground_seeds":_seed_count(a.state)})
		a.close()
	_check("width7_one_seed_hits_enemy_and_nest_for_five",hits_ok,{"cases":hit_results})
	a = Arena.new()
	a.seeds = 9
	a.combat_system.fire(false)
	a.seeds = 2 # Six available seeds spent by another action; reserve remains in flight.
	a.state.occupy(Rect2i(12,12,1,1),9002)
	a.sow_width = 1 # In-flight shot keeps its own width3.
	a.combat_system._shots(0.5)
	_check("flight_balance_occupancy_and_locked_width",a.seeds == 0 and _seed_count(a.state) == 3 and a.state.stage[a.state.index_of(12,12)] == 0 and a.state.stage[a.state.index_of(12,11)] == 1 and a.state.stage[a.state.index_of(11,12)] == 1 and a.state.stage[a.state.index_of(13,12)] == 1,{"balance":a.seeds,"seeded":_seed_count(a.state)})
	a.close()
	a = Arena.new()
	a.seeds = 10
	a.aim = Vector2(74,50) # 64 logic flight, longer than the 0.28s shot cooldown.
	a.combat_system.fire(false)
	a.clock.advance(0.25)
	a.combat_system._shots(0.25)
	a.clock.advance(0.05)
	a.combat_system._shots(0.05)
	var second: Dictionary = a.combat_system.fire(false)
	a.combat_system._shots(0.5)
	var overlap_ok: bool = second.ok and a.seeds == 1 and _seed_count(a.state) == 9 and a.shots.is_empty()
	a.combat_system._shots(0.5)
	_check("overlapping_shots_settle_once_without_negative_balance",overlap_ok and a.seeds == 1 and _seed_count(a.state) == 9,{"balance":a.seeds,"seeded":_seed_count(a.state)})
	a.close()
	a = Arena.new()
	a.seeds = 4
	a.sow_width = 7
	a.state.terrain[a.state.index_of(8,12)] = 4
	a.placement.attach(a.state,a.state.terrain.duplicate())
	a.combat_system.fire(false)
	a.combat_system._shots(0.5)
	a.combat_system._shots(0.5)
	_check("wall_returns_only_reserved_seed_once",a.seeds == 4 and _seed_count(a.state) == 0 and a.shots.is_empty(),{"balance":a.seeds,"ground_seeds":_seed_count(a.state)})
	a.close()
	# Persistence uses a genuinely normal Session: no stage resets or array fixture.
	var normal: RefCounted = Session.new()
	var baseline: RefCounted = Session.new()
	var baseline_result: Dictionary = baseline.restore(normal.to_dict())
	baseline.close()
	normal.sow_width = 7
	normal.set_aim(Coords.cell_center_logic(Vector2i(191,190)))
	var empty_row: bool = true
	for x: int in range(188,195): empty_row = empty_row and normal.state.can_plant(normal.state.index_of(x,193))
	fired = normal.fire()
	var saved: Dictionary = Save.save_game(normal,"user://independent_flight")
	var loaded: Dictionary = Save.load_game("user://independent_flight")
	var fixed_landing: bool = false
	var invalid_rejected: bool = false
	var reasons: Dictionary = {}
	if loaded.get("ok",false):
		var restored: RefCounted = loaded.session
		var flight_fields: bool = restored.shots.size() == 1 and restored.shots[0].sow_width == 7 and restored.shots[0].reserved_seed == 1 and restored.seeds == 59
		var snapshot: String = JSON.stringify(restored.to_dict(),"",true,true)
		invalid_rejected = true
		for field: String in ["sow_width","reserved_seed"]:
			var invalid: Dictionary = restored.to_dict().duplicate(true)
			invalid.entities.shots[0][field] = 2 if field == "sow_width" else 0
			var rejected: Dictionary = restored.restore(invalid)
			reasons[field] = rejected.reason
			invalid_rejected = invalid_rejected and not rejected.ok and rejected.reason == "invalid_entity_shots" and snapshot == JSON.stringify(restored.to_dict(),"",true,true)
		restored.sow_width = 1
		restored.combat_system._shots(0.1)
		var seven: bool = true
		for x: int in range(188,195): seven = seven and restored.state.stage[restored.state.index_of(x,193)] == WorldState.STAGE_SEED
		fixed_landing = flight_fields and seven and restored.seeds == 53 and restored.shots.is_empty()
		restored.close()
	_check("normal_flight_json_roundtrip_lands_fixed_width7",baseline_result.ok and empty_row and fired.ok and saved.ok and loaded.get("ok",false) and fixed_landing,{"normal_baseline_restorable":baseline_result.ok,"expected_empty_row":empty_row,"load_ok":loaded.get("ok",false),"fixed_width_landing":fixed_landing})
	_check("invalid_shot_fields_rejected_atomically_on_valid_base",loaded.get("ok",false) and invalid_rejected,{"reasons":reasons})
	normal.close()
	var failures: int = 0
	for item: Dictionary in checks:
		if item.status == "FAIL": failures += 1
	report["checks"] = checks
	report["failures"] = failures
	report["godot"] = Engine.get_version_info()
	report["user_data"] = profile
	report["not_run"] = ["independent_gpu_native_input", "wide_regression_long_play", "all_sizes_lighting_exported_build_future_target_prediction"]
	var file: FileAccess = FileAccess.open(OUT,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	quit(0 if failures == 0 else 1)
