extends SceneTree
## Prepared for town_03 connection. Do not run against the old live map.
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const EXPECTED_MAP: String = "res://data/poc3/maps/town_03.json"
const OUT: String = "res://evidence/poc3/world_layout/self/"
var checks: Array[Dictionary] = []
var observations: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"status":"PASS" if passed else "FAIL"})
	print(checks.back())

func isolated() -> bool:
	return OS.get_user_data_dir().contains("evidence/poc3/world_layout/self/profile/")

func digest(session: RefCounted) -> String:
	return JSON.stringify(session.to_dict(),"",false,true).sha256_text()

func route_m(route: Array[Vector2i]) -> float:
	var result: float = 0.0
	for index: int in range(1,route.size()): result+=Vector2(route[index]-route[index-1]).length()*0.4
	return result

func replay_route(session: RefCounted, route: Array[Vector2i]) -> bool:
	if route.is_empty(): return false
	var position_: Vector2 = Coords.cell_center_logic(route[0])
	for index: int in range(1,route.size()):
		var target: Vector2 = Coords.cell_center_logic(route[index])
		position_=Walker.move(session.state,4,position_,target-position_,Vector2(2,2))
		if position_.distance_to(target)>0.01: return false
	return true

func dormant(session: RefCounted) -> bool:
	for nest: Dictionary in session.nests:
		if bool(nest.active): return false
	return true

func run() -> void:
	check("isolated_profile_and_connected_map",isolated() and Session.MAP_PATH==EXPECTED_MAP)
	if checks.back().status=="FAIL":
		finish("logic_results.json")
		return
	var session: RefCounted = Session.new()
	var start: Vector2 = Coords.cell_center_logic(Vector2i(112,112))
	check("central_start_and_original_resources",session.position==start and session.seeds==60 and session.hp==100.0 and session.water==100.0 and session.state.width==224 and session.state.height==224)
	var mature: int = 0
	var circle_ok: bool = true
	for index: int in session.state.tile_count():
		if session.state.stage[index]!=WorldState.STAGE_MATURE: continue
		mature+=1
		var cell: Vector2i = Vector2i(index%224,index/224)
		if Vector2(cell-Vector2i(112,112)).length()*0.4>3.00001: circle_ok=false
	check("initial_177_circle_and_3_54_income",mature==177 and circle_ok and is_equal_approx(session.land_rate(),3.54))
	var zone_ok: bool = session.state.zone_count==1 and session.state.zone_state[0]==0
	for value: int in session.state.zone_of:
		if value!=0: zone_ok=false
	check("whole_map_one_unconquered_zone",zone_ok and not session.snapshot().stable)
	var min_enemy_m: float = INF
	var nest_distances: Array[float] = []
	var walkable: bool = true
	for category: String in ["enemies","nests"]:
		for item: Dictionary in session.get(category):
			var distance: float = Config.px_to_m(start.distance_to(item.pos))
			if category=="enemies": min_enemy_m=minf(min_enemy_m,distance)
			else: nest_distances.append(distance)
			if not session.is_walkable_logic(item.pos): walkable=false
	nest_distances.sort()
	observations.initial_distances_m={"nests":nest_distances,"nearest_enemy":min_enemy_m}
	check("actual_free_position_8m_clear_and_front_distances",walkable and not session.enemies.is_empty() and min_enemy_m>=8.0 and nest_distances.size()==5 and nest_distances[0]>=12.0 and nest_distances[0]<=16.0 and nest_distances[1]>=20.0)
	var reachable: bool = true
	var routes: Dictionary = {}
	for index: int in 4:
		var nest: Dictionary = session.nests[index]
		var route: Array[Vector2i] = session.nav.route(start,nest.pos)
		routes[str(index)]={"cells":route.size(),"length_m":route_m(route),"actual_target_logic":nest.pos}
		if not replay_route(session,route): reachable=false
	observations.routes=routes
	check("four_front_routes_replayed_with_player_collision",reachable)
	var bank: Vector2 = Coords.cell_center_logic(Vector2i(112,104))
	var bank_route: Array[Vector2i] = session.nav.route(start,bank)
	check("water_bank_3_2m_reachable",not bank_route.is_empty() and is_equal_approx(route_m(bank_route),3.2) and replay_route(session,bank_route) and session.state.terrain[session.state.index_of(112,103)]==3)
	session.position=bank
	session.water=0.0
	var seeds_before: int = session.seeds
	session.advance_game(0.25)
	check("bank_automatic_refill_without_seeds",session.water>0.0 and session.seeds==seeds_before)
	session.close()
	var idle: RefCounted = Session.new()
	var initial_count: int = idle.enemies.size()
	var initially_dormant: bool = dormant(idle)
	idle.advance_game(30.0)
	check("initial_and_30s_noncontact_dormant",initially_dormant and dormant(idle) and idle.enemies.size()==initial_count)
	idle.close()
	var approach: RefCounted = Session.new()
	var nearby: Dictionary = approach.nests[0]
	approach.position=approach.combat_system.free_position(nearby.pos+(start-nearby.pos).normalized()*80.0)
	approach.advance_game(0.25)
	check("player_approach_activates_nearest_front",nearby.active and nearby.pos.distance_to(approach.position)<=90.0 and not approach.nests[1].active)
	approach.close()
	var green: RefCounted = Session.new()
	var far_nest: Dictionary = green.nests[1]
	var cell: Vector2i = Coords.logic_to_cell(green.combat_system.free_position(far_nest.pos+Vector2(12,0)))
	green.state.set_stage(green.state.index_of(cell.x,cell.y),WorldState.STAGE_SPROUT1)
	green.advance_game(0.25)
	check("green_contact_activates_far_front_without_player",far_nest.active and far_nest.pos.distance_to(green.position)>90.0)
	green.close()
	var central: RefCounted = Session.new()
	var entering: Dictionary = central.enemies[0].duplicate(true)
	entering.pos=start+Vector2(12,0)
	entering.home=start
	entering.route_at=-1.0
	var before: float = entering.pos.distance_to(start)
	central.nav.move(entering,start,18.0,0.25,central.clock.elapsed,true)
	check("initial_green_has_no_hostile_immunity",not central.nav.hostile.is_point_solid(Vector2i(112,112)) and entering.pos.distance_to(start)<before)
	for enemy: Dictionary in central.enemies.duplicate(): central.combat_system.damage_enemy(enemy,100000.0)
	for nest: Dictionary in central.nests.duplicate(): central.combat_system.damage_nest(nest,100000.0)
	central.advance_game(0.25)
	check("all_enemies_nests_removed_stabilizes_zone",central.nests.is_empty() and central.enemies.is_empty() and central.state.zone_state[0]>=WorldState.ZONE_STABLE and central.snapshot().stable and central.nav.hostile.is_point_solid(Vector2i(112,112)))
	central.close()
	var saved: RefCounted = Session.new()
	var written: Dictionary = Save.save_game(saved,"user://world_layout_test")
	var loaded: Dictionary = Save.load_game("user://world_layout_test")
	check("new_map_save_restore",written.ok and loaded.ok and loaded.session.position==start and loaded.session.state.zone_count==1 and loaded.session.state.zone_state[0]==0 if loaded.ok else false)
	if loaded.ok: loaded.session.close()
	var old: Dictionary = saved.to_dict()
	old.map="res://data/poc2/maps/town_02.json"
	var unchanged: String = digest(saved)
	var rejected: Dictionary = saved.restore(old)
	check("old_working_map_rejected_session_unchanged",not rejected.ok and digest(saved)==unchanged)
	var broken: Dictionary = saved.to_dict()
	broken.world.zones.count=2
	broken.world.zones.state=[0,0]
	var rejected_zone: Dictionary = saved.restore(broken)
	check("new_map_wrong_zone_shape_rejected_unchanged",not rejected_zone.ok and digest(saved)==unchanged)
	saved.position=start+Vector2(12,0)
	saved.hp=0.0
	saved.respawn_at=saved.clock.elapsed+0.25
	saved.advance_game(0.25)
	check("respawn_uses_map_start",saved.position==start and saved.hp==100.0)
	saved.close()
	finish("logic_results.json")

func finish(filename: String) -> void:
	var failures: int = 0
	for result: Dictionary in checks:
		if result.status=="FAIL": failures+=1
	var file: FileAccess = FileAccess.open(OUT+filename,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"not_run":["whole_map_100_percent","long_term_balance","physical_input"]},"  "))
	file.close()
	quit(1 if failures>0 else 0)
