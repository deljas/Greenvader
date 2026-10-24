extends SceneTree
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Work: GDScript = preload("res://scripts/poc2/simulation/helper_work.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const Equal: GDScript = preload("res://tests/poc2/view/equivalence.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/helpers/independent/"
var rows: Array[Dictionary] = []

func _init() -> void:
	call_deferred("run")

func check(id: String, ok: bool, detail: Variant = "") -> void:
	rows.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	print(JSON.stringify(rows.back()))

func fresh() -> RefCounted:
	var s: RefCounted = Session.new()
	s.enemies.clear()
	s.nests.clear()
	s.fossils.clear()
	s.known.fill(1)
	s.seeds = 1000
	s.unlocked.gatlinger = true
	s.unlocked.sprinkler = true
	return s

func decisions() -> bool:
	var h: Dictionary = {"kind":"army","pos":Vector2(100,100),"home":Vector2(100,100),"target_id":-1}
	var allies: Array[Dictionary] = [{"id":20,"pos":Vector2(120,100),"hp":30.0}]
	var enemies: Array[Dictionary] = [{"id":1,"pos":Vector2(101,100),"hp":20.0,"kind":"boar","phase":"chase"},{"id":2,"pos":Vector2(105,100),"hp":5.0,"kind":"locust","phase":"eat"},{"id":3,"pos":Vector2(130,100),"hp":20.0,"kind":"spider","phase":"attack","attack_target_type":"plants","attack_target_id":20}]
	var first: int = Work.army_target(h,enemies,allies)
	h.target_id = 3
	enemies[2].pos = Vector2(178,100)
	var retained: int = Work.army_target(h,enemies,allies)
	enemies[2].pos = Vector2(181,100)
	check("ARMY_PRIORITY_AND_8M_RELEASE",first == 3 and retained == 3 and Work.army_target(h,enemies,allies) == -1)
	var worker: Dictionary = {"kind":"gatlinger","pos":Vector2(100,100),"home":Vector2(120,100)}
	var armies: Array[Dictionary] = [{"kind":"army","pos":Vector2(90,100),"hp":80.0}]
	check("RETREAT_TO_ARMY_REAR_AWAY_FROM_UNSAFE_HOME",Work.retreat_goal(worker,Vector2(110,100),armies) == Vector2(70,100))
	return true

func flights() -> bool:
	var s: RefCounted = fresh()
	var a: Dictionary = s.place_helper("gatlinger",Vector2i(112,112),2)
	var b: Dictionary = s.place_helper("gatlinger",Vector2i(112,113),2)
	if not a.ok or not b.ok:
		check("FLIGHT_FIXTURE",false)
		s.close()
		return true
	var sender: Dictionary = s.helpers[0]
	var peer: Dictionary = s.helpers[1]
	var tile: int = s.state.index_of(114,112)
	s.state.set_stage(tile,0)
	var at: Vector2 = Coords.cell_center_logic(Vector2i(114,112))
	var balance: int = s.seeds
	var launched: bool = s.combat_system.helper_seed(sender,at)
	check("PERSONAL_AMMO_WIDTH1_RESERVE0",launched and sender.ammo == 1 and s.seeds == balance and s.shots[0].sow_width == 1 and s.shots[0].reserved_seed == 0 and s.state.stage[tile] == 0)
	check("SECOND_GAT_CANNOT_SHARE_FLIGHT_TARGET",not s.combat_system.helper_seed(peer,at) and peer.ammo == 2 and s.seeds == balance)
	s.remove_helper(sender.id)
	var original: Dictionary = s.to_dict()
	var saved: Dictionary = Save.save_game(s)
	var loaded: Dictionary = Save.load_game()
	check("SOURCE_GONE_FLIGHT_JSON_FULL_STATE",saved.ok and loaded.ok and Equal.same(original,loaded.session.to_dict()) if loaded.ok else false)
	if loaded.ok:
		var restored: RefCounted = loaded.session
		balance = restored.seeds
		var excluded: bool = not restored.combat_system.helper_seed(restored.helpers[0],at)
		restored.combat_system._shots(0.25)
		check("RESTORED_RESERVATION_THEN_SOURCELESS_LANDING",excluded and restored.state.stage[tile] == 1 and restored.seeds == balance and restored.helpers[0].ammo == 2 and restored.shots.is_empty())
		restored.close()
	else:
		check("RESTORED_RESERVATION_THEN_SOURCELESS_LANDING",false,"load failed")
	var invalid: Dictionary = original.duplicate(true)
	var duplicate: Dictionary = invalid.entities.shots[0].duplicate(true)
	duplicate.id = invalid.values.next_id
	invalid.values.next_id += 1
	invalid.entities.shots.append(duplicate)
	var rejected: Dictionary = s.restore(invalid)
	check("DUPLICATE_FLIGHT_TARGET_ATOMIC_REJECT",not rejected.ok and rejected.reason == "duplicate_helper_target" and Equal.same(original,s.to_dict()),rejected)
	s.close()
	return true

func idle_and_refill() -> bool:
	var s: RefCounted = fresh()
	var placed: Dictionary = s.place_helper("sprinkler",Vector2i(112,112))
	if not placed.ok:
		check("IDLE_FIXTURE",false,placed)
		s.close()
		return true
	var h: Dictionary = s.helpers[0]
	for index: int in Landing.tiles_in_radius(s.state,4,h.home,60.0):
		if s.state.target[index] == 1: s.state.set_stage(index,4)
	s.advance_game(3.5)
	check("REAL_EMPTY_JOB_RETURNS_AND_SLEEPS",h.status == "idle" and h.sleeping and h.water == 100.0 and h.job_kind == "")
	var tile: int = s.state.index_of(114,112)
	s.state.set_stage(tile,0)
	s.state.set_stage(tile,1)
	h.search_at = 0.0
	s.advance_game(0.25)
	check("NEW_GRASS_JOB_WAKES_AND_WATERS_ONCE",not h.sleeping and s.state.moisture[tile] == 100 and h.water == 99.0)
	var home: Vector2 = h.home
	h.bank = s.nav.bank(h.pos)
	h.pos = h.bank
	h.water = 0.0
	h.water_task = "refilling"
	h.status = "refilling"
	s.plant_system._sprinkler(h,4.75)
	var before_end: bool = h.water == 95.0 and h.target_pos == h.bank
	s.plant_system._sprinkler(h,0.25)
	check("FIVE_SECOND_REFILL_PRESERVES_HOME",before_end and h.water == 100.0 and h.water_task == "returning_water" and h.home == home and not Work.idle_state(h,s.clock.elapsed,false).sleeping)
	s.close()
	return true

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/helpers/independent/profile/"):
		quit(2)
		return
	for method: String in ["decisions","flights","idle_and_refill"]:
		if call(method) != true: check(method+"_completed",false,"runtime abort")
	var failures: int = 0
	for row: Dictionary in rows:
		if row.status == "FAIL": failures += 1
	var file: FileAccess = FileAccess.open(OUT+"results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":rows,"failures":failures,"engine":Engine.get_version_info(),"user_dir":OS.get_user_data_dir()},"  "))
	file.close()
	quit(1 if failures else 0)
