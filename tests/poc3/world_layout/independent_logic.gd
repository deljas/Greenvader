extends SceneTree
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const Equivalent: GDScript = preload("res://tests/poc2/view/equivalence.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/world_layout/independent/"
var checks: Array[Dictionary] = []

func _init() -> void:
	call_deferred("run")

func check(id: String, ok: bool, detail: Variant = "") -> void:
	checks.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	print(JSON.stringify(checks.back()))

func initial_and_save() -> bool:
	var s: RefCounted = Session.new()
	check("CENTRAL_INITIAL_RESOURCES",s.position == Vector2(450,450) and s.state.width == 224 and s.state.height == 224 and s.seeds == 60 and s.hp == 100.0 and s.water == 100.0)
	var mature_count: int = 0
	var circle: bool = true
	var one_zone: bool = s.state.zone_count == 1 and s.state.zone_state.size() == 1 and s.state.zone_state[0] == 0
	for index: int in s.state.tile_count():
		var cell: Vector2i = Vector2i(index % 224,index / 224)
		var inside: bool = (Vector2(cell) - Vector2(112,112)).length_squared() <= 56.25
		var mature: bool = s.state.stage[index] == WorldState.STAGE_MATURE
		if mature: mature_count += 1
		if mature != inside: circle = false
		if s.state.zone_of[index] != 0: one_zone = false
	check("EXACT_3M_CIRCLE_177_AND_INCOME",circle and mature_count == 177 and is_equal_approx(s.land_rate(),3.54),{"mature":mature_count,"land_rate_per_min":s.land_rate()})
	check("ONE_UNCONQUERED_REGION_NO_INITIAL_IMMUNITY",one_zone and not s.snapshot().stable and not s.nav.hostile.is_point_solid(Vector2i(112,112)))
	var nearest_enemy: float = INF
	var distances: Array[float] = []
	for enemy: Dictionary in s.enemies:
		nearest_enemy = minf(nearest_enemy,s.position.distance_to(enemy.pos)/10.0)
	for nest: Dictionary in s.nests:
		distances.append(s.position.distance_to(nest.pos)/10.0)
	distances.sort()
	check("INITIAL_ENEMY_NEST_DISTANCE_SPACING",not s.enemies.is_empty() and nearest_enemy >= 8.0 and distances.size() == 5 and distances[0] >= 12.0 and distances[0] <= 16.0 and distances[1] >= 20.0,{"enemy_min_m":nearest_enemy,"nest_m":distances})
	var original: Dictionary = s.to_dict()
	var saved: Dictionary = Save.save_game(s)
	var loaded: Dictionary = Save.load_game()
	check("TOWN03_ACTUAL_JSON_ROUNDTRIP",saved.ok and loaded.ok and Equivalent.same(original,loaded.session.to_dict()) if loaded.ok else false,{"saved":saved.ok,"loaded":loaded.ok})
	if loaded.ok: loaded.session.close()
	var old: Dictionary = original.duplicate(true)
	old.map = "res://data/poc2/maps/town_02.json"
	var rejected: Dictionary = s.restore(old)
	check("OLD_MAP_ATOMIC_REJECT",not rejected.ok and Equivalent.same(original,s.to_dict()),rejected)
	var malformed: Dictionary = original.duplicate(true)
	malformed.world.zones.state = [0.5]
	rejected = s.restore(malformed)
	check("REGION_FRACTIONAL_STATE_ATOMIC_REJECT",not rejected.ok and Equivalent.same(original,s.to_dict()),rejected)
	# Change only the isolated in-memory fixture's source field: restoration must read map data.
	s.map_data.player_start_cell = [113,112]
	s.position = Vector2(470,450)
	s.hp = 0.0
	s.respawn_at = s.clock.elapsed + 0.25
	s.advance_game(0.25)
	check("RESPAWN_READS_CANONICAL_MAP_FIELD",s.position == Vector2(454,450) and s.start_position() == Vector2(454,450) and s.hp == 100.0)
	s.close()
	return true

func activity() -> bool:
	var s: RefCounted = Session.new()
	var initial_count: int = s.enemies.size()
	s.advance_game(12.0)
	var dormant: bool = s.enemies.size() == initial_count
	for nest: Dictionary in s.nests:
		if nest.active: dormant = false
	check("REMOTE_IDLE_TIME_DOES_NOT_ACTIVATE",dormant)
	var near: Dictionary = s.nests[0]
	s.position = s.combat_system.free_position(near.pos + (s.start_position()-near.pos).normalized()*70.0)
	s.advance_game(0.25)
	var far_dormant: bool = true
	for index: int in range(1,s.nests.size()):
		if s.nests[index].active: far_dormant = false
	check("APPROACH_ACTIVATES_ONLY_NEAREST",near.active and far_dormant)
	s.close()
	return true

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/world_layout/independent/profile/"):
		quit(2)
		return
	for method: String in ["initial_and_save","activity"]:
		if call(method) != true: check(method+"_completed",false,"runtime abort")
	var failures: int = 0
	for result: Dictionary in checks:
		if result.status == "FAIL": failures += 1
	var file: FileAccess = FileAccess.open(OUT+"results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"engine":Engine.get_version_info(),"user_dir":OS.get_user_data_dir()},"  "))
	file.close()
	quit(1 if failures else 0)
