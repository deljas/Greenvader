extends SceneTree
const Session: GDScript=preload("res://scripts/poc2/poc2_session.gd")
const Save: GDScript=preload("res://scripts/poc2/save/poc2_save.gd")
const Coords: GDScript=preload("res://scripts/poc/poc_coords.gd")
const Equivalent: GDScript=preload("res://tests/poc2/view/equivalence.gd")
const OUT: String="res://evidence/poc3/locust/self/"
var checks: Array[Dictionary]=[]
var details: Dictionary={}
func _init() -> void: call_deferred("run")
func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"status":"PASS" if passed else "FAIL"})
	print(JSON.stringify(checks.back()))
func cohort(s: RefCounted, source: int) -> Array[Dictionary]:
	var out: Array[Dictionary]=[]
	for e: Dictionary in s.enemies:
		if int(e.source)==source: out.append(e)
	return out
func fixture(tier: int=0) -> RefCounted:
	var s: RefCounted=Session.new()
	s.enemies.clear(); s.nests.clear(); s.fossils.clear()
	s.combat_system.add_nest({"cell":[112,112],"scale":"small","kind":"locust"})
	var n: Dictionary=s.nests[0]
	n.tier=tier; n.max_hp=40.0*(1.0 if tier==0 else 1.3); n.hp=n.max_hp
	s.enemies.clear()
	s.combat_system.spawn(n,true)
	s.enemies[0].pos=s.position+Vector2(8,0)
	s.enemies[0].home=s.enemies[0].pos
	return s
func finish() -> void:
	var failures: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+"integration_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"details":details,"failures":failures,"completed":true},"  "))
	file.close(); quit(1 if failures else 0)
func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/locust/self/profile/"):
		push_error("profile not isolated"); quit(1); return
	var s: RefCounted=Session.new()
	var n: Dictionary={}
	var minimum: float=INF
	var nest_distances: Array=[]
	for row: Dictionary in s.nests:
		var distance: float=row.pos.distance_to(s.start_position())/10.0
		nest_distances.append({"kind":row.kind,"metres":distance,"position":str(row.pos)})
		if row.kind=="locust": n=row
	for e: Dictionary in s.enemies: minimum=minf(minimum,e.pos.distance_to(s.start_position())/10.0)
	var group: Array[Dictionary]=cohort(s,n.id)
	var fixed: bool=group.size()==6
	for e: Dictionary in group: fixed=fixed and e.initial and e.tier==n.tier and is_equal_approx(e.max_hp,6.5)
	var cell: Vector2i=Coords.logic_to_cell(n.pos)
	check("new_map_six_tiered_locusts_safe_actual_placement",fixed and n.pos.distance_to(s.start_position())>=200.0 and minimum>=8.0 and s.state.is_walkable(cell.x,cell.y) and not s.nav.route(s.position,n.pos).is_empty())
	details.placement={"nests":nest_distances,"nearest_initial_enemy_m":minimum}
	s.advance_game(30.0)
	check("remote_nest_dormant_no_production",not n.active and cohort(s,n.id).size()==6)
	s.position=s.combat_system.free_position(n.pos+Vector2(0,40))
	n.spawn_due=s.clock.elapsed+20.0
	var hp_before: float=s.hp
	s.advance_game(19.75)
	var interval_before: bool=cohort(s,n.id).size()==6
	s.advance_game(0.25)
	var first_cap: bool=cohort(s,n.id).size()==12
	s.advance_game(20.0)
	check("active_twenty_second_group_cap_includes_initial_nonattack",interval_before and first_cap and cohort(s,n.id).size()==12 and s.hp==hp_before)
	group=cohort(s,n.id)
	var initial: Dictionary=group[0]
	var produced: Dictionary=group.back()
	var balance: int=s.seeds
	s.combat_system.damage_enemy(initial,999.0)
	var initial_reward: int=s.seeds-balance
	balance=s.seeds
	s.combat_system.damage_enemy(produced,999.0)
	var produced_reward: int=s.seeds-balance
	n.spawn_due=s.clock.elapsed+20.0
	s.advance_game(20.0)
	balance=s.seeds
	s.combat_system.damage_nest(n,9999.0)
	check("replacement_only_two_and_rewards_floor_initial_produced_nest",cohort(s,n.id).size()==12 and initial_reward==1 and produced_reward==0 and s.seeds-balance==45)
	s.close()
	s=fixture()
	s.nests.clear(); s.set_aim(s.enemies[0].pos)
	var fired: Dictionary=s.combat_system.fire(false)
	s.combat_system._shots(0.1)
	check("inner_tier_single_normal_shot",fired.ok and s.enemies.is_empty())
	s.close()
	s=fixture(1)
	n=s.nests[0]
	s.combat_system.spawn(n,false)
	s.enemies[1].pos=s.position+Vector2(8,4)
	s.nests.clear(); s.set_aim(s.enemies[0].pos)
	fired=s.combat_system.fire(true)
	s.combat_system._shots(0.1)
	check("bazooka_intercepts_group",fired.ok and s.enemies.is_empty())
	s.close()
	s=fixture(1)
	s.nests.clear(); s.unlocked.army=true; s.seeds=1000
	var placed: Dictionary=s.place_helper("army",Vector2i(113,112))
	if placed.ok:
		s.enemies[0].pos=s.helpers[0].pos+Vector2(4,0)
		s.plant_system._army(s.helpers[0],0.25)
	check("army_intercepts_locust",placed.ok and s.enemies.is_empty())
	s.close()
	s=fixture(1)
	s.nests.clear()
	var eater: Dictionary=s.enemies[0]
	var food: Vector2=Coords.cell_center_logic(Vector2i(170,70))
	eater.pos=food; eater.home=food
	var tile: int=s.state.index_of(170,70)
	s.state.set_stage(tile,WorldState.STAGE_MATURE)
	s.state.moisture[tile]=100
	var rate: float=s.land_rate()
	var detected_before: bool=s.detected(food)
	s.advance_game(3.0)
	var lost: bool=not s.detected(food)
	s.helpers.append({"hp":1.0,"pos":food})
	var alternate: bool=s.detected(food)
	s.helpers.clear()
	check("food_loss_updates_income_and_live_detection_other_source_retained",detected_before and lost and alternate and s.state.stage[tile]==0 and is_equal_approx(s.land_rate(),rate-0.02))
	s.state.set_stage(tile,WorldState.STAGE_SEED)
	check("eaten_tile_replanted_dry",s.state.moisture[tile]==0 and s.state.growth[tile]==0)
	s.close()
	s=fixture(1)
	n=s.nests[0]
	eater=s.enemies[0]
	eater.initial=false; eater.pos=s.position; eater.home=s.position
	s.combat_system.spawn(n,false)
	s.combat_system.damage_enemy(s.enemies[1],999.0)
	s.combat_system.damage_nest(n,9999.0)
	s.advance_game(1.0)
	var before: Dictionary=s.to_dict()
	var saved: Dictionary=Save.save_game(s,"user://locust_roundtrip")
	var loaded: Dictionary=Save.load_game("user://locust_roundtrip")
	var resumed: bool=false
	if loaded.ok:
		var candidate: RefCounted=loaded.session
		var child: Dictionary=candidate.enemies[0]
		resumed=candidate.enemies.size()==1 and candidate.nests.is_empty() and child.id is int and child.source is int and child.eat_tile is int and is_equal_approx(child.eat_elapsed,1.0)
		candidate.advance_game(1.75)
		resumed=resumed and candidate.state.stage[child.eat_tile]>=WorldState.GREENED_MIN_STAGE
		candidate.advance_game(0.25)
		resumed=resumed and child.eat_tile==-1
		candidate.close()
	check("json_roundtrip_eating_progress_dead_parent_child_integer_ids",saved.ok and loaded.ok and resumed)
	details.save={"save":saved,"load_ok":loaded.ok,"load_reason":loaded.get("reason","")}
	var invalids: Array[Dictionary]=[{"key":"eat_tile","value":-2},{"key":"eat_tile","value":0.5},{"key":"eat_tile","value":"1"},{"key":"eat_tile","value":true},{"key":"eat_elapsed","value":3.0},{"key":"phase","value":"attack"},{"key":"source","value":1.5}]
	var rejected: bool=true
	for entry: Dictionary in invalids:
		var bad: Dictionary=before.duplicate(true)
		bad.entities.enemies[0][entry.key]=entry.value
		rejected=rejected and not s.restore(bad).ok and Equivalent.same(before,s.to_dict())
	check("invalid_eating_state_rejected_session_unchanged",rejected)
	s.close()
	finish()
