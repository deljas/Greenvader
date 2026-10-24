extends SceneTree
## Narrow correction to independent cultivated-shot cost expectations, no GPU repeat.
const Session: GDScript=preload("res://scripts/poc/poc_session.gd")
const Action: GDScript=preload("res://scripts/poc/poc_fire_action.gd")
const OUT: String="res://evidence/spr01/fire-integration/independent/selection-followup.json"
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var s: RefCounted=Session.new()
	var a: RefCounted=Action.new()
	s.play.select_index(1)
	var original: PlantDef=s.play.selected_def()
	var aim: Vector2=s.position+Vector2(25,0)
	var pouch: int=s.play.seeds
	a.start(s,false,aim)
	a.advance(0.065,s)
	s.play.select_index(2)
	s.set_aim(s.position+Vector2(-20,0))
	s.position+=Vector2(1,0)
	var result: Dictionary=a.advance(0.001,s)
	var shot: Dictionary=s.projectiles.shots.back()
	var first: bool=bool(result.ok) and s.projectiles.launched==1 and shot.kind==String(original.key) and Vector2(shot.target).is_equal_approx(aim) and Vector2(shot.origin).is_equal_approx(s.position) and s.play.selected_def().key!=original.key and s.play.seeds==pouch and s.play.reserved_seeds==original.seed_cost and s.play.available_seeds()==pouch-original.seed_cost
	var observed: Dictionary={"pouch_before":pouch,"pouch_at_release":s.play.seeds,"reserved_at_release":s.play.reserved_seeds,"available_at_release":s.play.available_seeds(),"selected_now":String(s.play.selected_def().key),"shot_kind":shot.kind,"shot_origin":shot.origin,"player_origin":s.position,"shot_target":shot.target,"snapshotted_aim":aim}
	a.advance(0.1,s)
	var second: bool=s.projectiles.launched==1 and s.play.seeds==pouch and s.play.reserved_seeds==original.seed_cost and s.play.available_seeds()==pouch-original.seed_cost
	var report: Dictionary={"checks":[{"name":"seed66_input_selection_aim_and_release_origin","status":"PASS" if first else "FAIL"},{"name":"logical_release_cost_once","status":"PASS" if second else "FAIL"}],"observed":observed,"basis":"Preserved PlayState.reserve_plant reserves cost at launch; land_plant spends pouch seeds only on placement success. These functions and the session reserve branch predate this change."}
	var file: FileAccess=FileAccess.open(OUT,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print(JSON.stringify(report))
	s.close()
	quit(0 if first and second else 1)
