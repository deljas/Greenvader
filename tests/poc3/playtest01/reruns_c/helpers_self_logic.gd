extends SceneTree
const Session: GDScript=preload("res://scripts/poc2/poc2_session.gd")
const Save: GDScript=preload("res://scripts/poc2/save/poc2_save.gd")
const Coords: GDScript=preload("res://scripts/poc/poc_coords.gd")
const Equal: GDScript=preload("res://tests/poc2/view/equivalence.gd")
const OUT: String="res://evidence/poc3/playtest01/self/rerun_C_helpers/"
var checks: Array[Dictionary]=[]
var anchor: Vector2i=Vector2i.ZERO

func _init() -> void: call_deferred("run")
func check(label: String,ok: bool,detail: Variant="") -> void:
	checks.append({"name":label,"status":"PASS" if ok else "FAIL","detail":detail}); print(JSON.stringify(checks.back()))

func fresh() -> RefCounted:
	var s: RefCounted=Session.new()
	s.enemies.clear(); s.nests.clear(); s.fossils.clear(); s.known.fill(1); s.seeds=10000
	# A clear local fixture, identical for both sides of each comparison.
	anchor=Vector2i(112,112)
	for y: int in range(100,128):
		for x: int in range(100,128):
			var clear: bool=true
			for dy: int in range(-3,4):
				for dx: int in range(-3,4):
					var c: Vector2i=Vector2i(x+dx,y+dy)
					if not s.state.in_bounds(c.x,c.y) or not s.state.is_walkable(c.x,c.y) or s.state.target[s.state.index_of(c.x,c.y)]==0: clear=false
			if clear: anchor=Vector2i(x,y); break
		if anchor!=Vector2i(112,112): break
	s.state.debug_fill_stage(Rect2i(anchor-Vector2i(3,3),Vector2i(7,7)),WorldState.STAGE_MATURE)
	s.position=Coords.cell_center_logic(anchor)
	# Isolate helper contributions from natural spread in both comparison arms.
	s.spread.tuning.spread_progress_threshold=1000000000
	return s

func helper(s: RefCounted,kind: String,cell: Vector2i,ammo: int=0) -> Dictionary:
	s.unlocked[kind]=true
	var result: Dictionary=s.place_helper(kind,cell,ammo)
	if not result.ok: check("fixture_"+kind,false,result); return {}
	return s.helpers.back()

func flights() -> bool:
	var s: RefCounted=fresh()
	var h: Dictionary=helper(s,"gatlinger",anchor,2)
	if h.is_empty(): s.close(); return true
	var cell: Vector2i=anchor+Vector2i(2,0)
	var tile: int=s.state.index_of(cell.x,cell.y)
	s.state.set_stage(tile,0)
	var target: Vector2=Coords.cell_center_logic(cell)
	var before: int=s.seeds
	var launched: bool=s.combat_system.helper_seed(h,target)
	check("helper_flight_ammo_only_width1_reserve0",launched and h.ammo==1 and s.seeds==before and s.state.stage[tile]==0 and s.shots[0].sow_width==1 and s.shots[0].reserved_seed==0)
	check("flying_target_reserved_no_duplicate",not s.combat_system.helper_seed(h,target) and h.ammo==1)
	s.remove_helper(h.id)
	var snapshot: Dictionary=s.to_dict()
	var saved: Dictionary=Save.save_game(s)
	var loaded: Dictionary=Save.load_game()
	check("flight_save_after_source_removal",saved.ok and loaded.ok and Equal.same(snapshot,loaded.session.to_dict()) if loaded.ok else false,loaded.get("reason",""))
	if loaded.ok:
		var peer: RefCounted=loaded.session
		var balance: int=peer.seeds
		peer.combat_system._shots(0.25)
		check("source_gone_lands_no_shared_account_change",peer.state.stage[tile]==1 and peer.seeds==balance and peer.shots.is_empty())
		peer.close()
	var invalid: Dictionary=snapshot.duplicate(true)
	invalid.entities.shots[0].reserved_seed=1
	check("reject_mixed_helper_shared_reservation",not s.restore(invalid).ok and Equal.same(snapshot,s.to_dict()))
	# An obstruction introduced while the shot flies spends ammo, never refunds seeds.
	var block_before: int=s.placement.projectile[tile]
	s.placement.projectile[tile]=1
	before=s.seeds
	s.combat_system._shots(0.25)
	check("blocked_helper_flight_never_refunds_shared_seeds",s.seeds==before and s.shots.is_empty() and s.state.stage[tile]==0)
	s.placement.projectile[tile]=block_before
	# Existing player AREA reservation is still one, and settles only its budget.
	s.sow_width=3; s.shot_ready=0.0; s.seeds=2
	s.set_aim(target)
	s.fire(); s.combat_system._shots(0.25)
	check("player_area_reservation_retained_no_negative",s.shots.is_empty() and s.seeds>=0 and s.seeds<=2)
	s.close(); return true

func compare() -> bool:
	var gat_counts: Array[int]=[]
	var crop_ages: Array[float]=[]
	var watered: Array[int]=[]
	for enabled: bool in [false,true]:
		var s: RefCounted=fresh()
		for y: int in range(anchor.y-2,anchor.y+3):
			for x: int in range(anchor.x+1,anchor.x+4): s.state.set_stage(s.state.index_of(x,y),0)
		if enabled: helper(s,"gatlinger",anchor,3)
		s.advance_game(6.0)
		var count: int=0
		for y: int in range(anchor.y-2,anchor.y+3):
			for x: int in range(anchor.x+1,anchor.x+4):
				if s.state.stage[s.state.index_of(x,y)]>0: count+=1
		gat_counts.append(count); s.close()
		s=fresh()
		s.place_plant("clover",anchor+Vector2i(2,0))
		if enabled: helper(s,"sprinkler",anchor)
		s.advance_game(6.0)
		crop_ages.append(s.plants[0].age)
		watered.append(1 if s.plants[0].watered else 0)
		s.close()
	check("gat_same_world_with_without_contribution",gat_counts[1]>gat_counts[0],gat_counts)
	check("sprinkler_same_world_with_without_contribution",watered==[0,1] and crop_ages[1]>crop_ages[0],{"watered":watered,"ages":crop_ages})
	return true

func orders_idle() -> bool:
	var s: RefCounted=fresh()
	var h: Dictionary=helper(s,"gatlinger",anchor,2)
	if h.is_empty(): s.close(); return true
	# No free target in 6m makes the worker return and sleep after three seconds.
	for index: int in Landing.tiles_in_radius(s.state,4,h.home,60.0):
		if s.state.target[index]==1: s.state.set_stage(index,4)
	s.advance_game(3.5)
	check("real_home_idle_sleep_after3",h.status=="idle" and h.sleeping)
	var tile: int=s.state.index_of(anchor.x+2,anchor.y)
	s.state.set_stage(tile,0); h.search_at=0.0
	s.advance_game(0.25)
	check("new_work_clears_sleep_immediately",not h.sleeping and h.ammo==1)
	# A threat at home must not draw a remote empty worker toward it.
	h.ammo=0; h.pos=h.home+Vector2(40,0); h.status="working"
	var enemy: Dictionary={"id":888,"kind":"spider","pos":h.home,"hp":20.0,"phase":"idle"}
	s.enemies.append(enemy)
	var distance: float=h.pos.distance_to(enemy.pos)
	s.plant_system._helper(h,0.25)
	check("common_empty_return_rejects_unsafe_home",h.status=="fleeing" and h.pos.distance_to(enemy.pos)>=distance)
	s.enemies.clear(); s.close()
	if "--idle-followup" in OS.get_cmdline_user_args():
		s=fresh()
		h=helper(s,"sprinkler",anchor)
		for index: int in Landing.tiles_in_radius(s.state,4,h.home,60.0):
			if s.state.target[index]==1: s.state.set_stage(index,4)
		s.advance_game(3.5)
		check("sprinkler_empty_job_stays_idle_not_watering",h.status=="idle" and h.sleeping and h.water==100.0)
		var home: Vector2=h.home
		h.bank=s.nav.bank(h.pos); h.pos=h.bank; h.water=0.0; h.water_task="resupplying"; h.status="resupplying"
		s.advance_game(20.0)
		check("sprinkler_refill_returns_original_home",h.home==home and h.pos.distance_to(home)<=4.0 and h.water==100.0 and h.water_task=="",{"status":h.status,"distance":h.pos.distance_to(home)})
		s.close(); return true
	# Army protects real grass from the new locust AI; no nest invasion is required.
	var outcomes: Array[int]=[]
	for enabled: bool in [false,true]:
		s=fresh()
		var cell: Vector2i=anchor+Vector2i(1,0)
		var pos: Vector2=Coords.cell_center_logic(cell)
		var bug: Dictionary={"id":s.allocate_id(),"kind":"locust","pos":pos,"home":pos,"hp":5.0,"max_hp":5.0,"tier":0,"initial":false,"strong":false,"source":999,"phase":"eat","phase_until":0.0,"attack_at":0.0,"stun_until":0.0,"charge_dir":Vector2.ZERO,"hit_charge":false,"eat_tile":s.state.index_of(cell.x,cell.y),"eat_elapsed":0.0,"eat_search_at":0.0}
		s.enemies.append(bug)
		if enabled: helper(s,"army",anchor)
		s.advance_game(3.25)
		outcomes.append(s.state.stage[s.state.index_of(cell.x,cell.y)])
		s.close()
	check("army_comparison_preserves_eaten_grass",outcomes[0]==0 and outcomes[1]>=2,outcomes)
	return true

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/playtest01/self/rerun_C_helpers/profile/"): quit(1); return
	var idle_only: bool="--idle-followup" in OS.get_cmdline_user_args()
	var methods: Array[String]=[]
	methods.assign(["orders_idle"] if idle_only else ["flights","compare","orders_idle"])
	for method: String in methods:
		if call(method)!=true: check(method+"_completed",false,"runtime error")
	var failures: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+("idle_followup_results.json" if idle_only else "logic_results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  ")); file.close()
	quit(1 if failures else 0)
