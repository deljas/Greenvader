extends SceneTree
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const Corrected: GDScript = preload("res://tests/poc3/enemy_tiers/corrected_combat.gd")
const Equivalent: GDScript = preload("res://tests/poc2/view/equivalence.gd")
const OUT: String = "res://evidence/poc3/enemy_tiers/self/"
var checks: Array[Dictionary] = []

func _init() -> void: call_deferred("run")
func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks.append({"name":label,"status":"PASS" if passed else "FAIL","detail":detail})
	print(JSON.stringify(checks.back()))

func creation() -> bool:
	var s: RefCounted=Session.new()
	var expected_tiers: Array[int]=[0,1,1,1,2]
	var expected_hp: Array[float]=[40.0,52.0,130.0,130.0,408.0]
	var parents: Dictionary={}
	var correct: bool=s.nests.size()==5
	var actual: Array=[]
	for index: int in s.nests.size():
		var nest: Dictionary=s.nests[index]
		correct=correct and nest.tier==expected_tiers[index] and nest.max_hp==expected_hp[index]
		parents[nest.id]=nest.tier; actual.append([nest.tier,nest.max_hp])
	check("world_nests_fixed_start_tiers_hp",correct,actual)
	correct=true
	var normal_hp: Array[float]=[20.0,26.0,34.0]
	var strong_hp: Array[float]=[40.0,52.0,68.0]
	for enemy: Dictionary in s.enemies:
		correct=correct and enemy.tier==parents[enemy.source] and enemy.max_hp==(strong_hp[enemy.tier] if enemy.strong else normal_hp[enemy.tier])
	check("all_initial_offspring_inherit_parent_tier",correct,{"initial_enemies":s.enemies.size()})
	var middle_strong: Dictionary={}
	for enemy: Dictionary in s.enemies:
		if enemy.tier==1 and enemy.strong: middle_strong=enemy; break
	var before: int=s.seeds
	s.combat_system.damage_enemy(middle_strong,1000.0)
	check("middle_strong_initial_reward_floor_22",s.seeds-before==22,s.seeds-before)
	var mother: Dictionary=s.nests.back()
	mother.pos=s.start_position()
	s.position=Vector2(850,850)
	s.combat_system.spawn(mother,false)
	var child: Dictionary=s.enemies.back()
	check("moved_mother_and_player_keep_outer_child_tier",mother.tier==2 and child.tier==2 and child.max_hp==34.0)
	before=s.seeds
	s.combat_system.damage_enemy(child,1000.0)
	check("produced_outer_child_reward_zero",s.seeds==before)
	before=s.seeds
	s.combat_system.damage_nest(mother,1000.0)
	check("outer_large_mother_reward_400",s.seeds-before==400,s.seeds-before)
	s.close()
	# The test double supplies the result of free_position. The production
	# add_nest method must use that corrected result, not the requested near cell.
	var fixture: RefCounted=Session.new(false)
	fixture.map_data={"player_start_cell":[112,112]}
	var combat: RefCounted=Corrected.new(fixture)
	combat.add_nest({"cell":[113,112],"scale":"small","kind":"boar"})
	check("tier_uses_post_correction_position",fixture.nests[0].tier==2 and fixture.nests[0].max_hp==68.0 and fixture.enemies[0].tier==2)
	combat.s=null
	return true

func attacks() -> bool:
	var s: RefCounted=Session.new()
	var center: Vector2=s.start_position()
	var enemy: Dictionary=s.enemies[2].duplicate(true)
	enemy.kind="spider"; enemy.tier=1; enemy.max_hp=26.0; enemy.hp=26.0
	enemy.pos=center+Vector2(4,0); enemy.home=center-Vector2(12,0)
	enemy.phase="idle"; enemy.stun_until=0.0; enemy.attack_at=0.0
	s.enemies.clear(); s.nests.clear(); s.plants.clear(); s.helpers.clear()
	s.hp=0.0
	var victim: Dictionary={"kind":"clover","pos":center,"hp":30.0,"mature":false,"last_combat":-100.0}
	s.plants.append(victim)
	s.combat_system._enemy(enemy,0.0)
	check("middle_normal_attack_crop_6",victim.hp==24.0,victim.hp)
	s.plants.clear(); s.helpers.append(victim)
	victim.hp=30.0; enemy.attack_at=0.0
	s.combat_system._enemy(enemy,0.0)
	check("middle_normal_attack_helper_6",victim.hp==24.0,victim.hp)
	s.helpers.clear(); s.position=center; s.hp=100.0
	enemy.tier=2; enemy.attack_at=0.0
	s.combat_system._enemy(enemy,0.0)
	check("outer_normal_attack_player_7",s.hp==93.0,s.hp)
	s.hp=100.0; enemy.kind="boar"; enemy.phase="charge"; enemy.phase_until=1.0; enemy.charge_dir=Vector2.LEFT; enemy.hit_charge=false
	s.combat_system._enemy(enemy,0.0)
	check("outer_boar_charge_player_16_8",is_equal_approx(s.hp,83.2),s.hp)
	var mother: Dictionary={"id":999,"kind":"mother","pos":center+Vector2(4,0),"home":center+Vector2(4,0),"tier":2,"scale":"large","mother":true,"spawn_due":100.0,"attack_at":0.0,"last_contact":0.0,"active":true,"status":"active"}
	s.nests.append(mother); s.hp=100.0
	s.combat_system.advance(0.0)
	check("outer_mother_contact_player_14",s.hp==86.0,s.hp)
	s.close()
	return true

func saves() -> bool:
	var s: RefCounted=Session.new()
	var mother: Dictionary=s.nests.back()
	mother.pos=s.start_position()
	mother.hp=390.0
	s.combat_system.spawn(mother,false)
	# Parent gone while its child survives: source need not resolve on restore.
	s.combat_system.damage_nest(mother,1000.0)
	var before: Dictionary=s.to_dict()
	var saved: Dictionary=Save.save_game(s)
	var loaded: Dictionary=Save.load_game()
	print("save wrapper results: ",saved," / ",loaded.get("reason",""))
	var parsed_save: Variant=JSON.parse_string(FileAccess.get_file_as_string(Save.DEFAULT_DIR.path_join(Save.FILE_NAME)))
	var parsed_tier: Variant=parsed_save.state.entities.enemies[0].tier
	print("JSON tier boundary: type=",type_string(typeof(parsed_tier))," value=",parsed_tier," int_membership=",parsed_tier in [0,1,2]," normalized_membership=",float(parsed_tier) in [0.0,1.0,2.0])
	if not loaded.ok:
		var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(Save.DEFAULT_DIR.path_join(Save.FILE_NAME)))
		var probe: RefCounted=Session.new()
		print("direct JSON restore diagnosis: ",probe.restore(parsed.state))
		probe.close()
	elif not Equivalent.same(before,loaded.session.to_dict()):
		for field: String in before:
			if not Equivalent.same(before[field],loaded.session.to_dict()[field]): print("roundtrip unequal field: ",field)
	check("actual_json_missing_parent_fixed_tier_roundtrip",saved.ok and loaded.ok and loaded.session.enemies.back().tier==2 and loaded.session.enemies.back().max_hp==34.0 and Equivalent.same(before,loaded.session.to_dict()) if loaded.ok else false)
	if loaded.ok: loaded.session.close()
	if "--save-followup" in OS.get_cmdline_user_args():
		s.close(); return true
	# A separately restored snapshot with a relocated live mother must keep tier2.
	var live: RefCounted=Session.new()
	live.nests.back().pos=live.start_position()
	var live_restore: Dictionary=live.restore(live.to_dict())
	check("live_mother_restore_not_recomputed_from_current_pos",live_restore.ok and live.nests.back().tier==2 and live.nests.back().max_hp==408.0)
	live.close()
	# Working-save compatibility: no tier means original unscaled abilities.
	var old: Dictionary=before.duplicate(true)
	for enemy: Dictionary in old.entities.enemies:
		enemy.erase("tier"); enemy.max_hp=40.0 if enemy.strong else 20.0; enemy.hp=enemy.max_hp
	for nest: Dictionary in old.entities.nests:
		nest.erase("tier"); nest.max_hp={"small":40.0,"medium":100.0,"large":240.0}[nest.scale]; nest.hp=nest.max_hp
	var accepted: Dictionary=s.restore(old)
	var correct: bool=accepted.ok
	for enemy: Dictionary in s.enemies: correct=correct and enemy.tier==0 and enemy.max_hp==(40.0 if enemy.strong else 20.0)
	for nest: Dictionary in s.nests: correct=correct and nest.tier==0
	check("missing_tier_defaults_zero_preserves_old_abilities",correct)
	before=s.to_dict()
	for example: Array in [["enemies",1.5],["enemies",3],["nests",-1],["nests","2"],["nests",true]]:
		var bad: Dictionary=before.duplicate(true)
		bad.entities[example[0]][0].tier=example[1]
		var rejected: Dictionary=s.restore(bad)
		check("invalid_tier_"+str(example[0])+"_"+str(example[1]),not rejected.ok and Equivalent.same(before,s.to_dict()),rejected)
	var bad: Dictionary=before.duplicate(true)
	bad.entities.enemies[0].max_hp=21.0
	check("reject_tier_hp_mismatch_atomically",not s.restore(bad).ok and Equivalent.same(before,s.to_dict()))
	s.close()
	return true

func validation_followup() -> bool:
	var s: RefCounted=Session.new()
	var before: Dictionary=s.to_dict()
	for example: Array in [["enemies",1.5],["enemies",3],["nests",-1],["nests","2"],["nests",true]]:
		var bad: Dictionary=before.duplicate(true)
		bad.entities[example[0]][0].tier=example[1]
		var rejected: Dictionary=s.restore(bad)
		check("invalid_tier_"+str(example[0])+"_"+str(example[1]),not rejected.ok and Equivalent.same(before,s.to_dict()),rejected)
	var bad: Dictionary=before.duplicate(true)
	bad.entities.enemies[0].max_hp=float(bad.entities.enemies[0].max_hp)+1.0
	check("reject_tier_hp_mismatch_atomically",not s.restore(bad).ok and Equivalent.same(before,s.to_dict()))
	s.close()
	return true

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/enemy_tiers/self/profile/"):
		push_error("profile not isolated"); quit(1); return
	var save_only: bool="--save-followup" in OS.get_cmdline_user_args()
	var validation_only: bool="--validation-followup" in OS.get_cmdline_user_args()
	var methods: Array[String]=[]
	if validation_only: methods.assign(["validation_followup"])
	else: methods.assign(["saves"] if save_only else ["creation","attacks","saves"])
	for method: String in methods:
		if call(method)!=true: check(method+"_completed",false,"runtime error")
	var failures: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	var output: String="validation_followup_results.json" if validation_only else ("save_followup_results.json" if save_only else "integration_results.json")
	var file: FileAccess=FileAccess.open(OUT+output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"not_run":["GPU rendering unchanged","physical input","full regression","difficulty balance"]},"  "))
	file.close()
	quit(1 if failures else 0)
