extends SceneTree
## Preparation only: run after the parent grants Godot ownership.
const Work: GDScript = preload("res://scripts/poc2/simulation/helper_work.gd")
const OUT: String = "res://evidence/poc3/playtest01/self/rerun_B_helpers/"
var checks: Array[Dictionary] = []

func _init() -> void: call_deferred("run")
func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"status":"PASS" if passed else "FAIL"})
	print(JSON.stringify(checks.back()))

func army() -> bool:
	var h: Dictionary={"kind":"army","pos":Vector2.ZERO,"home":Vector2.ZERO,"target_id":-1}
	var allies: Array[Dictionary]=[{"id":50,"pos":Vector2(20,0),"hp":30.0}]
	var enemies: Array[Dictionary]=[
		{"id":1,"kind":"boar","pos":Vector2(5,0),"hp":20.0,"phase":"chase"},
		{"id":2,"kind":"locust","pos":Vector2(15,0),"hp":20.0,"phase":"eat"},
		{"id":3,"kind":"spider","pos":Vector2(30,0),"hp":20.0,"phase":"attack","attack_target_type":"plants","attack_target_id":50}]
	check("army_protect_ally_before_eater_before_intruder",Work.army_target(h,enemies,allies)==3)
	enemies[2].phase="chase"
	check("army_eater_before_nearer_intruder",Work.army_target(h,enemies,allies)==2)
	enemies[1].phase="chase"
	h.target_id=2; enemies[1].pos=Vector2(6,0)
	check("army_same_priority_target_stable",Work.army_target(h,enemies,allies)==2)
	enemies[1].pos=Vector2(81,0)
	check("army_chase_cutoff_returns_home_before_retarget",Work.army_target(h,enemies,allies)==-1)
	h.target_id=-1
	var no_targets: Array[Dictionary]=[{"id":8,"kind":"mother","pos":Vector2(1,0),"hp":100.0,"category":"nests"},{"id":9,"kind":"boar","pos":Vector2(61,0),"hp":20.0}]
	check("army_no_nest_or_outside_work_acquisition",Work.army_target(h,no_targets,allies)==-1)
	return true

func work_targets() -> bool:
	var h: Dictionary={"pos":Vector2.ZERO,"home":Vector2.ZERO,"ammo":3}
	var candidates: Array[Dictionary]=[{"tile":1,"pos":Vector2(5,0),"plantable":true,"green_distance":20.0},{"tile":2,"pos":Vector2(20,0),"plantable":true,"green_distance":1.0},{"tile":3,"pos":Vector2(61,0),"plantable":true,"green_distance":0.0}]
	check("gat_clusters_near_green_inside_6m",Work.sow_target(h,candidates,PackedInt32Array()).tile==2)
	check("gat_skips_flying_shot_reservation",Work.sow_target(h,candidates,PackedInt32Array([2])).tile==1)
	h.ammo=0
	check("gat_empty_has_no_job",Work.sow_target(h,candidates,PackedInt32Array()).is_empty())
	var crops: Array[Dictionary]=[{"id":5,"pos":Vector2(40,0),"hp":30.0,"mature":false,"watered":false},{"id":6,"pos":Vector2(10,0),"hp":30.0,"mature":false,"watered":true}]
	var grass: Array[Dictionary]=[{"tile":7,"pos":Vector2(5,0),"growing":true,"watered":false}]
	check("sprinkler_dry_crop_before_near_grass_skip_wet",Work.sprinkler_target(h,crops,grass).id==5)
	h.job_kind="grass"; h.job_id=7
	check("sprinkler_finishes_existing_valid_task",Work.sprinkler_target(h,crops,grass).id==7)
	grass[0].watered=true
	check("sprinkler_reselects_after_first_water",Work.sprinkler_target(h,crops,grass).id==5)
	return true

func safety_idle() -> bool:
	var h: Dictionary={"kind":"sprinkler","pos":Vector2.ZERO,"home":Vector2(20,0),"status":"working","idle_since":-1.0}
	var enemies: Array[Dictionary]=[{"pos":Vector2(40,0),"hp":20.0}]
	check("danger_enter_threshold",Work.danger(h,enemies).is_empty())
	h.status="fleeing"
	check("danger_exit_hysteresis",not Work.danger(h,enemies).is_empty())
	var armies: Array[Dictionary]=[{"kind":"army","pos":Vector2(-10,0),"hp":80.0}]
	check("retreat_behind_near_army",Work.retreat_goal(h,Vector2(10,0),armies)==Vector2(-30,0))
	armies.clear()
	check("retreat_rejects_unsafe_home",Work.retreat_goal(h,Vector2(10,0),armies).x<0.0)
	h.home=Vector2(-20,0)
	check("retreat_safe_home_preferred_without_army",Work.retreat_goal(h,Vector2(10,0),armies)==h.home)
	h.pos=h.home; h.status="idle"; h.idle_since=10.0
	check("zzz_only_after_home_idle_3_seconds",not Work.idle_state(h,12.9,false).sleeping and Work.idle_state(h,13.0,false).sleeping)
	check("new_work_wakes_immediately",not Work.idle_state(h,14.0,true).sleeping)
	var suppressed: bool=true
	for status: String in ["empty","fleeing","resupplying","refilling","unreachable"]:
		h.status=status; suppressed=suppressed and not Work.idle_state(h,14.0,false).sleeping
	h.status="idle"; h.kind="army"
	check("zzz_suppressed_for_resources_danger_army",suppressed and not Work.idle_state(h,14.0,false).sleeping)
	return true

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/playtest01/self/rerun_B_helpers/profile/"):
		push_error("profile not isolated"); quit(1); return
	for method: String in ["army","work_targets","safety_idle"]:
		if call(method)!=true: check(method+"_completed",false)
	var failures: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+"pure_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	file.close()
	quit(1 if failures else 0)
