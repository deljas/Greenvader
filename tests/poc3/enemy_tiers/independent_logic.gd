extends SceneTree
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Tiers: GDScript = preload("res://scripts/poc2/simulation/enemy_tiers.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const Equivalent: GDScript = preload("res://tests/poc2/view/equivalence.gd")
const OUT: String = "res://evidence/poc3/enemy_tiers/independent/"
var rows: Array[Dictionary] = []

func _init() -> void:
	call_deferred("run")

func check(id: String, ok: bool, detail: Variant = "") -> void:
	rows.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	print(JSON.stringify(rows.back()))

func boundaries() -> bool:
	var start: Vector2 = Vector2(400,400)
	# 0.1m/logic pixel. Negative directions also use the fixed origin and distance.
	var near: int = Tiers.tier_for(start,Vector2(220.5,400))
	var middle: int = Tiers.tier_for(start,Vector2(220,400))
	var outer: int = Tiers.tier_for(start,Vector2(400,80))
	check("EXACT_18_32_METRE_BOUNDARIES",near == 0 and middle == 1 and outer == 2,{"17_95m":near,"18m":middle,"32m":outer})
	return true

func integration() -> bool:
	var s: RefCounted = Session.new()
	var parents: Dictionary = {}
	for nest: Dictionary in s.nests: parents[nest.id] = nest.tier
	var inherited: bool = not s.enemies.is_empty()
	for enemy: Dictionary in s.enemies:
		if enemy.tier != parents[enemy.source]: inherited = false
	check("INITIAL_OFFSPRING_PARENT_TIER",inherited and s.nests[0].tier == 0 and s.nests[0].max_hp == 40.0 and s.nests.back().tier == 2 and s.nests.back().max_hp == 408.0)
	var middle_strong: Dictionary = {}
	for enemy: Dictionary in s.enemies:
		if enemy.tier == 1 and enemy.strong:
			middle_strong = enemy
			break
	if middle_strong.is_empty():
		check("MIDDLE_STRONG_REWARD_FLOOR",false,"missing fixture")
	else:
		var before: int = s.seeds
		s.combat_system.damage_enemy(middle_strong,1000.0)
		check("MIDDLE_STRONG_REWARD_FLOOR",s.seeds-before == 22,s.seeds-before)
	var mother: Dictionary = s.nests.back()
	var mother_id: int = mother.id
	mother.pos = s.start_position()
	s.position = s.start_position()+Vector2(0,100)
	s.combat_system.spawn(mother,false)
	var child: Dictionary = s.enemies.back()
	var child_id: int = child.id
	check("MOVED_MOTHER_PRODUCES_FIXED_OUTER_TIER",mother.tier == 2 and child.tier == 2 and child.max_hp == 34.0 and not child.initial)
	var before: int = s.seeds
	s.combat_system.damage_nest(mother,1000.0)
	check("MOVED_MOTHER_REWARD_STAYS_400",s.seeds-before == 400 and child.source == mother_id,s.seeds-before)
	var original: Dictionary = s.to_dict()
	var saved: Dictionary = Save.save_game(s)
	var loaded: Dictionary = Save.load_game()
	var equal: bool = loaded.ok and Equivalent.same(original,loaded.session.to_dict())
	var orphan: bool = loaded.ok
	if loaded.ok:
		for nest: Dictionary in loaded.session.nests:
			if nest.id == mother_id: orphan = false
	check("JSON_FULL_STATE_WITH_MISSING_PARENT",saved.ok and equal and orphan,{"saved":saved.ok,"loaded":loaded.ok,"full_state_equal":equal})
	if loaded.ok:
		var restored_child: Dictionary = {}
		for enemy: Dictionary in loaded.session.enemies:
			if enemy.id == child_id: restored_child = enemy
		if restored_child.is_empty():
			check("RESTORED_ORPHAN_FIXED_TIER_ZERO_REWARD",false,"child absent")
		else:
			var fixed: bool = restored_child.tier == 2 and restored_child.max_hp == 34.0
			before = loaded.session.seeds
			loaded.session.combat_system.damage_enemy(restored_child,1000.0)
			check("RESTORED_ORPHAN_FIXED_TIER_ZERO_REWARD",fixed and loaded.session.seeds == before)
		loaded.session.close()
	else:
		check("RESTORED_ORPHAN_FIXED_TIER_ZERO_REWARD",false,"load failed")
	var bad: Dictionary = original.duplicate(true)
	bad.entities.enemies[0].tier = 0.25
	var rejected: Dictionary = s.restore(bad)
	check("FRACTIONAL_TIER_ATOMIC_REJECT",not rejected.ok and Equivalent.same(original,s.to_dict()),rejected)
	bad = original.duplicate(true)
	bad.entities.nests[0].tier = false
	rejected = s.restore(bad)
	check("BOOL_ZERO_TIER_ATOMIC_REJECT",not rejected.ok and Equivalent.same(original,s.to_dict()),rejected)
	s.close()
	return true

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/enemy_tiers/independent/profile/"):
		quit(2)
		return
	for method: String in ["boundaries","integration"]:
		if call(method) != true: check(method+"_completed",false,"runtime abort")
	var failures: int = 0
	for row: Dictionary in rows:
		if row.status == "FAIL": failures += 1
	var file: FileAccess = FileAccess.open(OUT+"results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":rows,"failures":failures,"engine":Engine.get_version_info(),"user_dir":OS.get_user_data_dir()},"  "))
	file.close()
	quit(1 if failures else 0)
