extends SceneTree
const Session: GDScript=preload("res://scripts/poc2/poc2_session.gd")
const Coords: GDScript=preload("res://scripts/poc/poc_coords.gd")
const Area: GDScript=preload("res://scripts/poc2/simulation/seed_area.gd")
const Save: GDScript=preload("res://scripts/poc2/save/poc2_save.gd")
const Equivalent: GDScript=preload("res://tests/poc2/view/equivalence.gd")
const OUT: String="res://evidence/poc3/area_seed/self/"
const CENTER: Vector2i=Vector2i(191,188)
var s: RefCounted
var checks: Array[Dictionary]=[]

func _init() -> void: call_deferred("run")

func check(name_: String,ok: bool) -> void:
	checks.append({"name":name_,"status":"PASS" if ok else "FAIL"})
	print(checks.back())

func fixture(width: int=3,budget: int=60) -> void:
	s.paused=false
	s.enemies.clear(); s.nests.clear(); s.plants.clear(); s.helpers.clear(); s.shots.clear()
	for owner: int in s.state.occupancy_owners.keys(): s.state.release(owner)
	for y: int in range(183,193):
		for x: int in range(180,205): s.state.set_stage(s.state.index_of(x,y),WorldState.STAGE_EMPTY)
	# This synthetic reset does not advance the clock; remove old active entries
	# just as a fresh map does before testing a save, without changing save rules.
	s.state.rebuild_derived()
	s.position=Coords.cell_center_logic(Vector2i(182,188))
	s.set_aim(Coords.cell_center_logic(CENTER))
	s.sow_width=width
	s.seeds=budget
	s.shot_ready=0.0

func seeded() -> int:
	var count: int=0
	for y: int in range(185,192):
		for x: int in range(188,195):
			if s.state.stage[s.state.index_of(x,y)]==WorldState.STAGE_SEED: count+=1
	return count

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/area_seed/self/profile/"):
		push_error("profile not isolated"); quit(1); return
	s=Session.new()
	var baseline: Dictionary=s.to_dict()
	for width: int in [1,3,5,7]:
		fixture(width,100)
		var before: Dictionary=s.to_dict()
		var plan: Dictionary=s.sow_preview()
		check("center_width_readonly_"+str(width),plan.center==CENTER and plan.rect.size==Vector2i(width,width) and plan.cost==width*width and Equivalent.same(before,s.to_dict()))
		var fired: Dictionary=s.fire()
		check("launch_reserves_one_"+str(width),fired.ok and s.seeds==99 and s.shots.size()==1 and s.shots[0].sow_width==width and s.shots[0].reserved_seed==1)
		s.combat_system._shots(0.25)
		check("land_exact_square_"+str(width),seeded()==width*width and s.seeds==100-width*width and s.shots.is_empty())
	# Mixed terrain/occupancy, including an alive helper whose old owner is gone.
	fixture(3,2)
	var water: int=s.state.index_of(190,187)
	var wall: int=s.state.index_of(191,187)
	s.state.terrain[water]=3; s.state.target[water]=0
	s.state.terrain[wall]=4; s.state.target[wall]=0
	s.state.occupy(Rect2i(192,188,1,1),600001)
	s.state.set_stage(s.state.index_of(190,188),WorldState.STAGE_SEED)
	s.state.set_stage(s.state.index_of(190,189),WorldState.STAGE_MATURE)
	s.helpers.append({"hp":10.0,"pos":Coords.cell_center_logic(CENTER),"cell":Vector2i(180,183),"home":Vector2.ZERO})
	s.helpers.append({"hp":0.0,"pos":Coords.cell_center_logic(Vector2i(191,189))})
	var mixed: Dictionary=Area.plan(s.state,CENTER,3,2,s.helpers)
	check("mixed_ground_and_moved_helper",mixed.valid.size()==3 and mixed.affordable==[Vector2i(191,189),Vector2i(192,187)] and mixed.unaffordable==[Vector2i(192,189)] and s.state.occupant[s.state.index_of(CENTER.x,CENTER.y)]==0)
	check("invalid_width_rejected",not Area.plan(s.state,CENTER,2,10).ok)
	# Restore proper target accounting after the synthetic mixed fixture.
	check("restore_original_after_mixed",s.restore(baseline).ok)
	fixture(3,3)
	s.fire(); s.combat_system._shots(0.25)
	check("short_budget_uses_center_y_x_order",s.seeds==0 and seeded()==3 and s.state.stage[s.state.index_of(191,188)]==1 and s.state.stage[s.state.index_of(191,187)]==1 and s.state.stage[s.state.index_of(190,188)]==1)
	fixture(3,0)
	var empty: Dictionary=s.sow_preview()
	check("zero_budget_preview_and_no_fire",empty.valid.size()==9 and empty.affordable.is_empty() and empty.unaffordable.size()==9 and not s.fire().ok and s.seeds==0)
	# Current state wins over launch preview and current width.
	fixture(7,60)
	s.fire()
	s.sow_width=1; s.seeds=2
	s.state.set_stage(s.state.index_of(191,187),WorldState.STAGE_SEED)
	s.helpers.append({"hp":10.0,"pos":Coords.cell_center_logic(CENTER)})
	s.combat_system._shots(0.25)
	check("flight_terrain_budget_helper_changes",s.seeds==0 and seeded()==4 and s.state.stage[s.state.index_of(191,188)]==0 and s.state.stage[s.state.index_of(190,188)]==1 and s.state.stage[s.state.index_of(192,188)]==1 and s.state.stage[s.state.index_of(191,189)]==1)
	fixture(3,12)
	s.fire(); s.shot_ready=0.0; s.fire()
	s.combat_system._shots(0.25)
	var settled: int=s.seeds
	s.combat_system._shots(0.25)
	check("overlapping_shots_no_double_charge",seeded()==9 and settled==3 and s.seeds==settled and s.shots.is_empty())
	fixture(1,1)
	s.state.set_stage(s.state.index_of(CENTER.x,CENTER.y),WorldState.STAGE_MATURE)
	s.fire(); s.combat_system._shots(0.25)
	check("zero_valid_refunds_reservation",s.seeds==1 and s.shots.is_empty())
	fixture(7,1)
	var block: int=s.state.index_of(187,188)
	var old_block: int=s.placement.projectile[block]
	s.placement.projectile[block]=1
	var blocked: Dictionary=s.sow_preview()
	s.fire(); s.combat_system._shots(0.25)
	check("wall_blocks_preview_and_refunds",blocked.blocked and blocked.cost==0 and seeded()==0 and s.seeds==1 and s.shots.is_empty())
	s.placement.projectile[block]=old_block
	for nest: bool in [false,true]:
		fixture(7,1)
		var victim: Dictionary={"id":s.allocate_id(),"pos":s.aim,"hp":40.0,"max_hp":40.0,"initial":false,"strong":false,"stun_until":0.0}
		if nest: s.nests.append(victim)
		else: s.enemies.append(victim)
		var attack: Dictionary=s.sow_preview()
		s.fire(); s.combat_system._shots(0.25)
		check("one_seed_attack_"+("nest" if nest else "enemy"),attack.attack and attack.cost==1 and attack.affordable.is_empty() and victim.hp==35.0 and seeded()==0 and s.seeds==0 and s.shots.is_empty())
	fixture(7,60)
	s.fire(); s.combat_system._shots(0.05)
	var saved: Dictionary=Save.save_game(s)
	var loaded: Dictionary=Save.load_game()
	check("flying_shot_real_json_roundtrip",saved.ok and loaded.ok and Equivalent.same(s.to_dict(),loaded.session.to_dict()) if loaded.ok else false)
	if loaded.ok:
		s.close(); s=loaded.session
		s.sow_width=1
		s.combat_system._shots(0.25)
		check("restored_shot_keeps_width_and_reservation",seeded()==49 and s.seeds==11 and s.shots.is_empty())
	# Older PoC3 shots have already paid the launch cost; no second debit.
	fixture(7,60)
	s.fire()
	var legacy: Dictionary=s.to_dict()
	legacy.entities.shots[0].erase("sow_width")
	legacy.entities.shots[0].erase("reserved_seed")
	check("legacy_shot_defaults",s.restore(legacy).ok and s.shots[0].sow_width==1 and s.shots[0].reserved_seed==1 and s.seeds==59)
	s.combat_system._shots(0.25)
	check("legacy_one_cell_no_extra_debit",seeded()==1 and s.seeds==59)
	fixture(3,20); s.fire()
	var good: Dictionary=s.to_dict()
	var bad: Dictionary=good.duplicate(true)
	bad.entities.shots[0].sow_width=2
	check("invalid_saved_width_atomic",not s.restore(bad).ok and Equivalent.same(good,s.to_dict()))
	bad=good.duplicate(true); bad.entities.shots[0].reserved_seed=0
	check("invalid_saved_reservation_atomic",not s.restore(bad).ok and Equivalent.same(good,s.to_dict()))
	fixture(1,10)
	s.combat_system.fire(true)
	check("bazooka_cost_and_shape_unchanged",s.seeds==7 and s.shots.size()==1 and s.shots[0].damage==25.0 and not s.shots[0].has("reserved_seed"))
	var failures: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+"logic_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"user_data_dir":OS.get_user_data_dir()},"  "))
	file.close()
	s.close()
	quit(1 if failures>0 else 0)
