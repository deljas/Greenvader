extends SceneTree
const Session = preload("res://scripts/greening_map/session.gd")
var rows: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func record(id: String, ok: bool, detail: String) -> void:
	rows.append({"id":id,"result":"PASS" if ok else "FAIL","detail":detail})
	if not ok:
		failures += 1
	print(rows[-1])

func run() -> void:
	var s: RefCounted = Session.new()
	s.position = Session.to_logic(Vector2(1.6,4.4))
	var home: Vector2 = s.position
	var distance_ok: bool = true
	for direction: Vector2 in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]:
		var old: Vector2 = Session.to_ground(s.position)
		s.walk(direction,0.125)
		distance_ok = distance_ok and absf(old.distance_to(Session.to_ground(s.position))-0.3)<0.001
	record("walk_free_closed_loop",distance_ok and s.position.distance_to(home)<0.002,"Four screen-cardinal steps each0.3m at2.4m/s; closed loop returns within0.002logical px.")
	var stops: Array[Dictionary] = []
	for fixture: Dictionary in [{"at":Vector2(6.4,-3.8),"direction":Vector2(-1,-1),"boundary":5.7},{"at":Vector2(-5.2,4.2),"direction":Vector2(-1,-1),"boundary":-5.5},{"at":Vector2(8.4,5.8),"direction":Vector2.ONE,"boundary":9.1}]:
		s.position = Session.to_logic(fixture["at"])
		s.walk(fixture["direction"],2.0)
		var actual: Vector2 = Session.to_ground(s.position)
		stops.append({"position":[actual.x,actual.y],"expected_east_edge":fixture["boundary"]})
		if absf(actual.x-float(fixture["boundary"]))>0.001 or absf(actual.y-Vector2(fixture["at"]).y)>0.001:
			distance_ok = false
	record("independent_obstacle_edges",distance_ok,JSON.stringify(stops))
	s.position = Session.to_logic(Vector2(2.2,4.2))
	var old_green: int = s.state.greened_count
	var seeded: bool = s.scatter(Vector2(2.6,4.2),false)
	var center: int = s.state.index_of(30,30)
	var watered: bool = s.scatter(Vector2(2.6,4.2),true)
	record("scatter_cost_and_seed_not_green",seeded and watered and s.play.seeds==19 and s.play.water==90 and s.state.stage[center]==1 and s.state.moisture[center]>0 and s.state.greened_count==old_green,"One seed/10water spent; fresh seed is not counted green before sprouting.")
	s.paused = true
	var clock_before: float = s.clock.elapsed
	var pause_seed: bool = s.scatter(Vector2(3.4,4.2),false)
	var moved: Vector2 = s.walk(Vector2.RIGHT,0.125)
	s.advance(0.1)
	record("pause_only_stops_growth",pause_seed and moved.length()>0 and s.clock.elapsed==clock_before,"During growth pause, scatter and walking remain active while simulation clock does not advance.")
	s.paused = false
	var dry_cell: int = s.state.index_of(32,30)
	s.advance_game(30)
	var intermediate: int = s.state.stage[dry_cell]
	s.advance_game(31)
	record("actual_growth_and_spread",intermediate>=2 and intermediate<4 and s.state.stage[dry_cell]==4 and s.spread.total_planted>0,"A separately planted dry cell sprouts by30game seconds and matures by61; real natural spread has planted cells.")
	s.play.seeds = 0
	s.play.water = 0
	var stage_before: PackedByteArray = s.state.stage.duplicate()
	var moisture_before: PackedByteArray = s.state.moisture.duplicate()
	var seed_refused: bool = not s.scatter(Vector2(3.8,4.2),false)
	var water_refused: bool = not s.scatter(Vector2(3.8,4.2),true)
	record("empty_resources_no_mutation",seed_refused and water_refused and stage_before==s.state.stage and moisture_before==s.state.moisture,"Both requests at a valid nearby location are rejected with no stage/moisture mutation.")
	var green: int = 0
	var mature: int = 0
	var valid: bool = true
	for i: int in s.state.tile_count():
		if s.state.target[i]!=0:
			green += 1 if s.state.stage[i]>=2 else 0
			mature += 1 if s.state.stage[i]==4 else 0
		elif s.state.stage[i]!=0 or s.state.growth[i]!=0:
			valid = false
	record("independent_counter_recount",valid and green==s.state.greened_count and mature==s.state.mature_count,"Direct array count, without WorldState.counters_consistent or display-derived totals.")
	var file: FileAccess = FileAccess.open("res://evidence/greening-map/independent/session-checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":rows,"failures":failures,"final":s.snapshot()},"\t"))
	file.close()
	s.close()
	quit(0 if failures==0 else 1)
