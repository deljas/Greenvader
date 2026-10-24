extends SceneTree
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const Equivalent: GDScript = preload("res://tests/poc2/view/equivalence.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/locust/independent/"
var rows: Array[Dictionary] = []

func _init() -> void:
	call_deferred("run")

func check(id: String, ok: bool, detail: Variant = "") -> void:
	rows.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	print(JSON.stringify(rows.back()))

func locust_nest(s: RefCounted) -> Dictionary:
	for n: Dictionary in s.nests:
		if n.kind == "locust": return n
	return {}

func food() -> bool:
	var s: RefCounted = Session.new()
	var members: Array[Dictionary] = []
	for e: Dictionary in s.enemies:
		if e.kind == "locust":
			e.pos = s.start_position()
			e.home = e.pos
			members.append(e)
	s.enemies.assign(members)
	s.nests.clear()
	var placed: Dictionary = s.place_plant("clover",Vector2i(112,112))
	if not placed.ok or members.size() != 6:
		check("FIXTURE",false,placed)
		s.close()
		return true
	s.combat_system.locust_ai.advance(s.enemies,s.plants,0.1,0.1)
	var claims: Dictionary = {}
	var unique: bool = true
	for e: Dictionary in s.enemies:
		if e.eat_tile < 0 or claims.has(e.eat_tile) or s.state.occupant[e.eat_tile] != 0: unique = false
		claims[e.eat_tile] = true
	check("SIX_DISTINCT_NONOCCUPIED_GRASS_TARGETS",unique and claims.size() == 6)
	var eater: Dictionary = members[0]
	var tile: int = eater.eat_tile
	eater.pos = Coords.cell_center_logic(Vector2i(tile%224,tile/224))
	eater.eat_elapsed = 0.0
	s.enemies.assign([eater])
	var player_hp: float = s.hp
	var plant_hp: float = s.plants[0].hp
	s.combat_system.locust_ai.advance(s.enemies,s.plants,1.5,1.5)
	eater.stun_until = 2.0
	s.combat_system.locust_ai.advance(s.enemies,s.plants,0.25,1.75)
	var reset: bool = eater.eat_elapsed == 0.0 and s.state.stage[tile] == 4
	s.combat_system.locust_ai.advance(s.enemies,s.plants,2.5,4.5)
	check("STUN_RESTARTS_CONTINUOUS_3_SECONDS",reset and eater.eat_elapsed == 2.5 and s.state.stage[tile] == 4)
	s.combat_system.locust_ai.advance(s.enemies,s.plants,0.5,5.0)
	check("THREE_SECONDS_EMPTY_AND_CLAIM_RELEASE",s.state.stage[tile] == 0 and eater.eat_tile == -1 and s.state.moisture[tile] == 0)
	check("GRASS_ONLY_NO_PLAYER_CROP_DAMAGE",s.hp == player_hp and s.plants[0].hp == plant_hp)
	s.state.set_stage(tile,WorldState.STAGE_SEED)
	check("EATEN_CELL_RESEEDED_DRY",s.state.moisture[tile] == 0 and s.state.growth[tile] == 0)
	var killed: Dictionary = members[1]
	var protected: int = killed.eat_tile
	killed.pos = Coords.cell_center_logic(Vector2i(protected%224,protected/224))
	killed.eat_elapsed = 0.0
	s.enemies.assign([killed])
	s.combat_system.locust_ai.advance(s.enemies,s.plants,2.75,8.0)
	s.combat_system.damage_enemy(killed,999.0)
	s.combat_system.locust_ai.advance(s.enemies,s.plants,1.0,9.0)
	check("DEATH_BEFORE_COMPLETION_PRESERVES_GRASS",s.state.stage[protected] == 4 and s.combat_system.locust_ai.reservations.is_empty())
	s.close()
	return true

func saves() -> bool:
	var s: RefCounted = Session.new()
	var nest: Dictionary = locust_nest(s)
	s.combat_system.spawn(nest,false)
	var child: Dictionary = s.enemies.back()
	child.pos = s.start_position()
	child.home = child.pos
	s.enemies.assign([child])
	s.combat_system.damage_nest(nest,9999.0)
	s.advance_game(1.25)
	var tile: int = child.eat_tile
	var original: Dictionary = s.to_dict()
	var saved: Dictionary = Save.save_game(s)
	var loaded: Dictionary = Save.load_game()
	var exact: bool = loaded.ok and Equivalent.same(original,loaded.session.to_dict())
	check("EATING_ORPHAN_JSON_FULL_STATE",saved.ok and exact and child.eat_elapsed == 1.25,{"saved":saved.ok,"loaded":loaded.ok,"full_state_equal":exact,"elapsed":child.eat_elapsed})
	if loaded.ok:
		var candidate: RefCounted = loaded.session
		var restored: Dictionary = candidate.enemies[0]
		var typed: bool = restored.id is int and restored.source is int and restored.eat_tile is int
		candidate.advance_game(1.5)
		var before_end: bool = candidate.state.stage[tile] >= WorldState.GREENED_MIN_STAGE and restored.eat_elapsed == 2.75
		candidate.advance_game(0.25)
		check("RESTORED_LAST_QUARTER_SECOND_COMPLETES",typed and before_end and candidate.state.stage[tile] == 0 and restored.eat_tile == -1)
		candidate.close()
	else:
		check("RESTORED_LAST_QUARTER_SECOND_COMPLETES",false,"load failed")
	var invalid: Dictionary = original.duplicate(true)
	invalid.entities.enemies[0].eat_elapsed = 3.0
	var rejected: Dictionary = s.restore(invalid)
	check("INVALID_COMPLETED_EATING_ATOMIC_REJECT",not rejected.ok and Equivalent.same(original,s.to_dict()),rejected)
	s.close()
	return true

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/locust/independent/profile/"):
		quit(2)
		return
	for method: String in ["food","saves"]:
		if call(method) != true: check(method+"_completed",false,"runtime abort")
	var failures: int = 0
	for row: Dictionary in rows:
		if row.status == "FAIL": failures += 1
	var file: FileAccess = FileAccess.open(OUT+"results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":rows,"failures":failures,"engine":Engine.get_version_info(),"user_dir":OS.get_user_data_dir()},"  "))
	file.close()
	quit(1 if failures else 0)
