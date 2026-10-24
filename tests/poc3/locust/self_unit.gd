extends SceneTree
## Pure component runner; game integration is exercised in self_integration.gd.
const AI: GDScript = preload("res://scripts/poc2/simulation/locust_ai.gd")
const Nav: GDScript = preload("res://scripts/poc2/simulation/navigation.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/locust/self/"
var checks: Array[Dictionary]=[]
var no_crops: Array[Dictionary]=[]
var no_actors: Array[Dictionary]=[]

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"status":"PASS" if passed else "FAIL"})
	print(checks.back())

func fixture() -> Dictionary:
	var defs: Array[TerrainDef]=[]
	for name_: String in ["wasteland","safe","shore","water","building","shallows","paved"]:
		defs.append(load(("res://data/poc/terrain/" if name_=="paved" else "res://data/terrain/")+name_+".tres") as TerrainDef)
	var world: WorldState=WorldState.new(16,16,defs,20261021)
	world.apply_terrain_defs()
	world.permanent_water=true
	var ids: PackedByteArray=PackedByteArray()
	ids.resize(256)
	world.set_zones(ids,PackedByteArray([0]))
	var nav: RefCounted=Nav.new()
	nav.setup(world)
	var ai: RefCounted=AI.new()
	ai.setup(world,nav)
	return {"world":world,"nav":nav,"ai":ai}

func actor(id: int, cell: Vector2i) -> Dictionary:
	var pos: Vector2=Coords.cell_center_logic(cell)
	return {"id":id,"kind":"locust","pos":pos,"home":pos,"hp":5.0,"phase":"idle","stun_until":0.0}

func green(f: Dictionary, cell: Vector2i) -> int:
	var tile: int=f.world.index_of(cell.x,cell.y)
	f.world.set_stage(tile,WorldState.STAGE_MATURE)
	return tile

func run() -> void:
	var f: Dictionary=fixture()
	var swarm: Array[Dictionary]=[]
	for index: int in 6:
		green(f,Vector2i(5+index,8))
		swarm.append(actor(index+1,Vector2i(8,8)))
	green(f,Vector2i(8,9))
	f.world.occupy(Rect2i(8,9,1,1),123)
	f.ai.advance(swarm,no_crops,0.01,0.0)
	var claimed: Dictionary={}
	var unique: bool=true
	for member: Dictionary in swarm:
		var tile: int=int(member.get("eat_tile",-1))
		if tile<0 or claimed.has(tile) or tile==f.world.index_of(8,9): unique=false
		claimed[tile]=true
	check("six_targets_distributed_crop_excluded",unique and claimed.size()==6)
	f=fixture()
	var tile: int=green(f,Vector2i(8,8))
	f.world.moisture[tile]=100
	swarm.assign([actor(1,Vector2i(8,8))])
	f.ai.advance(swarm,no_crops,2.9,2.9)
	var before_end: bool=f.world.stage[tile]==WorldState.STAGE_MATURE and swarm[0].phase=="eat"
	f.ai.advance(swarm,no_crops,0.1,3.0)
	check("three_seconds_completion_counter_and_water_reset",before_end and f.world.stage[tile]==WorldState.STAGE_EMPTY and f.world.greened_count==0 and f.world.moisture[tile]==0)
	f=fixture()
	tile=green(f,Vector2i(8,8))
	swarm.assign([actor(1,Vector2i(8,8))])
	f.ai.advance(swarm,no_crops,2.0,2.0)
	swarm[0].hp=0.0
	f.ai.advance(swarm,no_crops,2.0,4.0)
	check("death_before_completion_keeps_grass_releases_target",f.world.stage[tile]==WorldState.STAGE_MATURE and f.ai.reservations.is_empty())
	f=fixture()
	tile=green(f,Vector2i(8,8))
	swarm.assign([actor(1,Vector2i(8,8))])
	f.ai.advance(swarm,no_crops,1.0,1.0)
	swarm[0].stun_until=2.0
	f.ai.advance(swarm,no_crops,1.0,1.5)
	var interrupted: bool=swarm[0].eat_elapsed==0.0 and f.world.stage[tile]==WorldState.STAGE_MATURE
	f.ai.advance(swarm,no_crops,2.9,2.0)
	var restarted: bool=f.world.stage[tile]==WorldState.STAGE_MATURE
	f.ai.advance(swarm,no_crops,0.1,4.9)
	check("stun_interrupts_and_restarts_continuous_eating",interrupted and restarted and f.world.stage[tile]==WorldState.STAGE_EMPTY)
	f=fixture()
	tile=green(f,Vector2i(8,8))
	swarm.assign([actor(1,Vector2i(8,8))])
	f.ai.advance(swarm,no_crops,1.0,1.0)
	var copied: Dictionary=swarm[0].duplicate(true)
	swarm.assign([copied])
	f.ai=AI.new()
	f.ai.setup(f.world,f.nav)
	f.ai.advance(swarm,no_crops,1.9,2.9)
	var resumed: bool=f.world.stage[tile]==WorldState.STAGE_MATURE and f.ai.reservations.has(tile)
	f.ai.advance(swarm,no_crops,0.1,3.0)
	check("recreated_ai_resumes_eating_and_rebuilds_reservation",resumed and f.world.stage[tile]==WorldState.STAGE_EMPTY)
	f=fixture()
	tile=green(f,Vector2i(8,8))
	var next_tile: int=green(f,Vector2i(9,8))
	swarm.assign([actor(1,Vector2i(8,8))])
	f.ai.advance(swarm,no_crops,0.5,0.0)
	f.world.occupy(Rect2i(8,8,1,1),123)
	f.ai.advance(swarm,no_crops,0.5,1.0)
	check("new_occupant_releases_old_claim",not f.ai.reservations.has(tile) and swarm[0].eat_tile==next_tile and f.world.stage[tile]==WorldState.STAGE_MATURE)
	f.ai.advance(no_actors,no_crops,0.25,1.25)
	check("removed_actor_releases_claim",f.ai.reservations.is_empty())
	f=fixture()
	tile=green(f,Vector2i(8,8))
	next_tile=green(f,Vector2i(9,8))
	swarm.assign([actor(1,Vector2i(8,8))])
	f.ai.advance(swarm,no_crops,0.5,0.0)
	f.world.set_stage(tile,WorldState.STAGE_EMPTY)
	f.ai.advance(swarm,no_crops,0.25,1.0)
	check("disappeared_grass_releases_claim",not f.ai.reservations.has(tile) and swarm[0].eat_tile==next_tile)
	f=fixture()
	green(f,Vector2i(7,8))
	var preferred: int=green(f,Vector2i(8,8))
	var crops: Array[Dictionary]=[{"kind":"rafflesia","pos":Coords.cell_center_logic(Vector2i(10,9)),"mature":true,"hp":30.0}]
	swarm.assign([actor(1,Vector2i(4,8))])
	f.ai.advance(swarm,crops,0.25,0.0)
	check("rafflesia_attracts_to_near_grass_not_crop",swarm[0].eat_tile==preferred and crops[0].hp==30.0)
	f=fixture()
	var ids: PackedByteArray=PackedByteArray()
	ids.resize(256)
	for y: int in 16: ids[f.world.index_of(8,y)]=1
	f.world.set_zones(ids,PackedByteArray([0,WorldState.ZONE_STABLE]))
	green(f,Vector2i(8,8))
	green(f,Vector2i(10,8))
	f.nav.setup(f.world)
	swarm.assign([actor(1,Vector2i(6,8))])
	var unchanged: Vector2=swarm[0].pos
	f.ai.advance(swarm,no_crops,0.25,0.0)
	check("stable_zone_excluded_from_target_and_path",int(swarm[0].get("eat_tile",-1))<0 and swarm[0].pos==unchanged)
	var failures: int=0
	for result: Dictionary in checks:
		if result.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+"unit_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"not_run":["game_spawn_cap_and_tier_rewards","combat_interception","save_restore","render_eating","green_map_detection","whole_map_100_percent"]},"  "))
	file.close()
	quit(1 if failures>0 else 0)
