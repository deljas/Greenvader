extends SceneTree
const Session: GDScript = preload("res://scripts/greening_map/session.gd")
const OUT: String = "res://evidence/greening-map/self/"
var results: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, id: String, detail: String = "") -> void:
	results.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	if not ok:
		failures += 1
	print(results[-1])

func run() -> void:
	var model: RefCounted = Session.new()
	var spawn: Vector2 = model.position
	var axial: Vector2 = model.walk(Vector2.RIGHT,0.20)
	model.position = spawn
	var diagonal: Vector2 = model.walk(Vector2.ONE,0.20)
	check(absf(axial.length()-diagonal.length())<0.001 and axial.x>0 and axial.y<0,"movement.screen_axes_normalized","axial %.8f / diagonal %.8f logical px" % [axial.length(),diagonal.length()])
	# Long motion through each actual obstacle: use the game Walker, assert final foot rectangles are clear.
	model.position = Session.to_logic(Vector2(-3.2,2.0))
	model.position = Walker.move(model.state,Session.TILE_PX,model.position,Vector2(0,-60),Session.HALF)
	check(Walker.is_clear(model.state,Session.TILE_PX,model.position,Session.HALF) and Session.to_ground(model.position).y>=0.89,"collision.building_foundation")
	model.position = Session.to_logic(Vector2(-6.8,6.0))
	model.position = Walker.move(model.state,Session.TILE_PX,model.position,Vector2(0,-60),Session.HALF)
	check(Walker.is_clear(model.state,Session.TILE_PX,model.position,Session.HALF) and Session.to_ground(model.position).y>5.69,"collision.water")
	model.position = Walker.move(model.state,Session.TILE_PX,spawn,Vector2(400,400),Session.HALF)
	check(Walker.is_clear(model.state,Session.TILE_PX,model.position,Session.HALF),"collision.perimeter")
	model.position = spawn
	var target: Vector2 = Vector2(0.6,3.8)
	var seeds: int = model.play.seeds
	check(model.scatter(target,false) and model.play.seeds==seeds-1 and model.play.last_scatter.size()>0,"seed.real_landing_spending")
	var planted: int = model.play.last_scatter[0]
	var water: float = model.play.water
	check(model.state.stage[planted]==WorldState.STAGE_SEED and model.scatter(target,true) and model.play.water==water-10 and model.play.last_wet_count>0,"water.real_landing_spending")
	model.play.seeds = 0
	model.play.water = 0
	var stages: PackedByteArray = model.state.stage.duplicate()
	check(not model.scatter(target,false) and not model.scatter(target,true) and stages==model.state.stage,"resources.insufficient_no_mutation")
	model.refill()
	check(model.play.seeds==model.play_tuning.seed_max and model.play.water==model.play_tuning.water_max,"resources.debug_refill")
	model.play.water = 0
	model.position = Session.to_logic(Vector2(-6.8,5.8))
	model.advance_game(1)
	check(model.play.water>0,"water.existing_waterside_refill")
	model.position = spawn
	var before: float = model.clock.elapsed
	model.paused = true
	model.advance(0.1)
	check(model.clock.elapsed==before,"clock.growth_pause")
	model.paused = false
	model.advance_game(24)
	check(model.state.stage[planted]>=WorldState.STAGE_SPROUT1,"growth.seed_to_sprout")
	model.advance_game(90)
	check(model.state.stage[planted]==WorldState.STAGE_MATURE and model.spread.total_planted>0,"growth.mature_natural_spread")
	var outside: bool = true
	for i: int in model.state.tile_count():
		if model.state.target[i]==0:
			outside = outside and model.state.stage[i]==0 and model.state.growth[i]==0
	check(outside and model.state.counters_consistent(),"world.non_targets_counters")
	var f: FileAccess = FileAccess.open(OUT+"logic-results.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"results":results,"failures":failures},"\t"))
	model.close()
	quit(0 if failures==0 else 1)
