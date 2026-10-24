extends SceneTree
## Preparation only: run once after the parent freezes all PoC3 dependencies.
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Equivalent: GDScript = preload("res://tests/poc2/view/equivalence.gd")
const OUT: String = "res://evidence/poc3/playtest01/self/rerun_B_integration/"
var rows: Array[Dictionary] = []
var observations: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func check(id: String, ok: bool, detail: Variant = "") -> void:
	rows.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	print(JSON.stringify(rows.back()))

func settle(s: RefCounted, seconds: float) -> void:
	# Normal gameplay path, including combat, income, reveals and fixed substeps.
	s.advance_game(seconds)

func opening_save() -> bool:
	var s: RefCounted = Session.new()
	check("NEW_CENTRAL_RESOURCES",s.state.width==224 and s.state.height==224 and s.position==s.start_position() and s.seeds==60 and s.hp==100.0 and s.water==100.0)
	var placed: Dictionary = s.place_plant("clover",Coords.logic_to_cell(s.position))
	check("OPENING_CROP_FROM_REAL_BALANCE",placed.ok and s.seeds==50 and s.plants.size()==1,placed)
	if not placed.ok:
		s.close()
		return true
	var paid: int = s.plants[0].cost
	var watered: Dictionary = s.water_at(s.plants[0].pos)
	s.adjust_sow_width(1)
	s.set_favorite(1,"clover")
	var sow_target: Vector2 = Vector2(-1,-1)
	for dy: int in range(-12,13):
		for dx: int in range(-12,13):
			var candidate: Vector2 = s.start_position()+Vector2(dx,dy)*4.0
			if candidate.distance_to(s.position)<36.0 or candidate.distance_to(s.position)>64.0: continue
			s.set_aim(candidate)
			var preview: Dictionary = s.sow_preview()
			if not preview.get("blocked",true) and not preview.get("attack",true) and int(preview.get("cost",0))>=3:
				sow_target=candidate
				break
		if sow_target.x>=0.0: break
	var seed_before: int = s.seeds
	var fired: Dictionary = s.fire() if sow_target.x>=0.0 else {"ok":false,"reason":"no_valid_preview"}
	settle(s,2.0)
	check("OPENING_GROWING_WATERED_CROP",watered.ok and s.plants[0].watered and not s.plants[0].mature and paid==10,watered)
	check("OPENING_WIDTH3_PROJECTILE_SETTLES",fired.ok and s.sow_width==3 and s.shots.is_empty() and s.seeds<=seed_before-3,{"shot":fired,"target":sow_target,"spent_net":seed_before-s.seeds})
	var before: Dictionary = s.to_dict()
	var saved: Dictionary = Save.save_game(s)
	var loaded: Dictionary = Save.load_game()
	check("COMPOSITE_REAL_JSON_ROUNDTRIP",saved.ok and loaded.ok and Equivalent.same(before,loaded.session.to_dict()) if loaded.ok else false,{"saved":saved.ok,"loaded":loaded.ok})
	if loaded.ok:
		# No time is supplied while the session is absent. Restore must not add wall time.
		check("RESTORE_HAS_NO_OFFLINE_PROGRESS",loaded.session.clock.elapsed==s.clock.elapsed and loaded.session.plants[0].age==s.plants[0].age and loaded.session.seeds==s.seeds)
		loaded.session.close()
	# Explicit depletion fixture; this is not a claim that the opening spent every resource.
	s.seeds=0
	s.water=0.0
	s.set_aim(s.position+Vector2(8,0))
	var denied: Dictionary = s.fire()
	var dry_water: Dictionary = s.water_at(s.position)
	settle(s,20.0)
	check("ZERO_SEED_RECOVERS_FROM_REAL_PRODUCTION",not denied.ok and s.seeds>0,{"fire":denied,"balance":s.seeds})
	check("ZERO_WATER_DOES_NOT_STOP_CROP_GROWTH",not dry_water.ok and s.plants[0].mature,{"water":dry_water,"age":s.plants[0].age})
	# Reachable bank is selected by the actual navigation API; relocation is a fixture.
	var bank: Vector2 = s.nav.bank(s.position)
	if bank.x>=0.0:
		s.position=bank
		settle(s,1.0)
	check("ZERO_WATER_BANK_REFILLS_WITHOUT_SEED_PAYMENT",bank.x>=0.0 and s.water>0.0,{"bank":bank,"water":s.water})
	s.close()
	return true

func movement_precision() -> bool:
	var s: RefCounted = Session.new()
	# Actual Session.walk path. Each adjacent-cell displacement is converted back
	# into the same screen direction used by the main input loop; no position snaps.
	for destination: Vector2i in [Vector2i(121,57),Vector2i(118,178)]:
		s.position=s.start_position()
		var route: Array[Vector2i] = s.nav.route(s.position,Coords.cell_center_logic(destination))
		var error: Dictionary = {}
		for index: int in range(1,route.size()):
			var target: Vector2 = Coords.cell_center_logic(route[index])
			var offset: Vector2 = target-s.position
			s.walk(Coords.ground_dir_to_screen(offset.normalized()),offset.length()/48.0)
			if s.position.distance_to(target)>0.01:
				error={"step":index,"target_cell":route[index],"actual":s.position,"target":target,"error_px":s.position.distance_to(target)}
				break
		check("PLAYER_WALK_DIAGONAL_AXIS_"+str(destination),not route.is_empty() and error.is_empty(),error)
	s.position=Coords.cell_center_logic(Vector2i(112,104))
	var bank: Vector2 = s.position
	s.walk(Coords.ground_dir_to_screen(Vector2.UP),0.25)
	check("WATER_EDGE_FEET_DO_NOT_TUNNEL",s.position==bank and Walker.is_clear(s.state,4,s.position,Vector2(2,2)),s.position)
	s.position=s.start_position()
	var start: Vector2 = s.position
	s.walk(Coords.ground_dir_to_screen(Vector2.RIGHT),0.125)
	check("OPEN_SPACE_MOVE_PRESERVES_DISTANCE",is_equal_approx(s.position.distance_to(start),6.0) and Walker.is_clear(s.state,4,s.position,Vector2(2,2)),s.position)
	s.close()
	return true

func stable_full_map() -> bool:
	var s: RefCounted = Session.new()
	# Deliberate combat setup: all hostiles are defeated through real damage APIs.
	# This verifies post-clear guarantees, not skillful player victory or difficulty.
	for nest: Dictionary in s.nests.duplicate():
		s.combat_system.damage_nest(nest,float(nest.hp)+1.0)
	for enemy: Dictionary in s.enemies.duplicate():
		s.combat_system.damage_enemy(enemy,float(enemy.hp)+1.0)
	settle(s,1.0)
	var stable: bool = s.nests.is_empty() and s.enemies.is_empty() and s.state.zone_state[0]>=WorldState.ZONE_STABLE
	check("DAMAGE_API_CLEAR_TRANSITIONS_TO_STABLE",stable,s.snapshot())
	if not stable:
		s.close()
		return true
	check("STABLE_HOSTILE_ROUTE_REJECTED",s.nav.route(s.position,s.start_position()+Vector2(8,0),true).is_empty())
	var island: Array[int] = []
	for y: int in range(146,150):
		for x: int in range(150,154):
			var index: int = s.state.index_of(x,y)
			if s.state.target[index]==1: island.append(index)
	var island_before: int = 0
	for index: int in island:
		if s.state.stage[index]>=WorldState.GREENED_MIN_STAGE: island_before+=1
	var start_green: int = s.state.greened_count
	var start_clock: float = s.clock.elapsed
	# POC3-PLAYTEST-01 item 13: the fair sweep is off in PoC3, so far.completion_bound_seconds() (derived from the sweep) no longer
	# applies. Natural spread plus the one-seed-per-isolated-component help must reach 100 % within this generous game-time cap.
	var bound: float = 21600.0
	var old_max: float = s.clock.max_advance
	# One approved acceleration policy: only skip repeated empty combat/income/reveal
	# work after every hostile is gone. Clock emits the unchanged growth/spread/far
	# signals in their normal chronological order and with their original budgets.
	s.clock.max_advance=120.0
	var advances: int = 0
	while not s.state.is_fully_greened() and s.clock.elapsed-start_clock<=bound+120.0:
		s.clock.advance(120.0)
		advances+=1
	s.clock.max_advance=old_max
	# Normal Session update performs the authoritative complete/cleared transition.
	settle(s,1.0)
	var island_green: int = 0
	for index: int in island:
		if s.state.stage[index]>=WorldState.GREENED_MIN_STAGE: island_green+=1
	observations.full_map={"game_seconds":s.clock.elapsed-start_clock,"far_bound_seconds":bound,"clock_step":120.0,"advances":advances,"start_green":start_green,"greened":s.state.greened_count,"targets":s.state.target_count,"island_before":island_before,"island_green":island_green,"island_targets":island.size(),"sweep_planted":s.far.total_sweep_planted,"island_planted":s.far.total_island_planted,"input_events":0,"direct_stage_writes":0,"tuning_changed":false,"omitted_during_acceleration":["combat after all hostiles dead","income","periodic reveal","helper/crop work (none placed)"]}
	check("FULL_224_MAP_AUTONOMOUS_EXACT_100",s.state.greened_count==s.state.target_count and s.state.is_fully_greened() and s.state.cleared and s.state.counters_consistent(),observations.full_map)
	check("NO_SWEEP_PLANTING_AT_ALL",s.far.total_sweep_planted==0,s.far.total_sweep_planted)
	check("ISOLATED_TARGETS_AUTONOMOUSLY_GREENED",island.size()>0 and island_before<island.size() and island_green==island.size(),{"before":island_before,"green":island_green,"targets":island.size()})
	check("STABLE_POST_CLEAR_NO_ENEMIES_REAPPEAR",s.enemies.is_empty() and s.nests.is_empty() and s.nav.route(s.position,s.start_position()+Vector2(8,0),true).is_empty())
	s.close()
	return true

func run() -> void:
	if not "--integration-authorized" in OS.get_cmdline_user_args() or not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/playtest01/self/rerun_B_integration/profile/"):
		push_error("Parent authorization flag and isolated profile are required")
		quit(2)
		return
	if OS.get_cmdline_user_args().has("--movement-followup"):
		if movement_precision()!=true: check("movement_precision_completed",false,"runtime abort")
		finish("movement_followup_results.json")
		return
	for method: String in ["opening_save","movement_precision","stable_full_map"]:
		if call(method)!=true: check(method+"_completed",false,"runtime abort")
	finish("core_results.json")

func finish(name_: String) -> void:
	var failures: int = 0
	for row: Dictionary in rows:
		if row.status=="FAIL": failures+=1
	var file: FileAccess = FileAccess.open(OUT+name_,FileAccess.WRITE)
	var not_run: Array[String] = ["physical input","gameplay enjoyment","whole-map unassisted player conquest"]
	if not (name_.begins_with("gpu") or name_.begins_with("water")): not_run.append("GPU rendering")
	file.store_string(JSON.stringify({"checks":rows,"failures":failures,"observations":observations,"not_run":not_run},"  "))
	file.close()
	quit(1 if failures else 0)
