extends SceneTree
## Focused SPR-01 action/controller checks; no rendering or OS input.
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const Action: GDScript = preload("res://scripts/poc/poc_fire_action.gd")
const OUT: String = "res://evidence/spr01/fire-integration/self/"
var checks: Array[Dictionary] = []
var failures: int = 0
var sessions: Array[RefCounted] = []
func _init() -> void:
	_run.call_deferred()
func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name": name, "ok": ok, "detail": detail})
	print("PASS " if ok else "FAIL ", name)
	if not ok:
		failures += 1
func session() -> RefCounted:
	var value: RefCounted = Session.new()
	sessions.append(value)
	return value
func _run() -> void:
	var s: RefCounted = session()
	var a: RefCounted = Action.new()
	var aim: Vector2 = s.position + Vector2(30, 0)
	var seeds: int = s.play.seeds
	check("seed_starts_immediate_pose0_no_cost", bool(a.start(s,false,aim).ok) and a.frame_index()==0 and s.play.seeds==seeds and s.projectiles.launched==0)
	a.advance(0.065,s)
	var phase: float = a.elapsed_ms
	check("seed_65ms_before_event_and_busy_does_not_restart", s.projectiles.launched==0 and a.start(s,true,aim).reason=="busy" and a.elapsed_ms==phase)
	# Aim and selection are snapshotted, while logical origin is the release-time position.
	s.set_aim(s.position + Vector2(-20,0))
	s.cycle_plant(1)
	s.position += Vector2(2,0)
	var result: Dictionary = a.advance(0.001,s)
	var shot: Dictionary = s.projectiles.shots.back()
	check("seed_66ms_event_selection_aim_origin_once", bool(result.ok) and s.play.seeds==seeds-1 and s.projectiles.launched==1 and shot.kind=="seed" and Vector2(shot.origin)==s.position and Vector2(shot.target)==aim and a.frame_index()==1)
	a.advance(0.1,s)
	check("event_not_repeated", s.projectiles.launched==1 and s.play.seeds==seeds-1)
	check("release_recovery_can_be_interrupted", bool(a.start(s,true,aim).ok) and a.kind==&"water" and a.elapsed_ms==0.0)
	var water: float = s.play.water
	a.advance(0.399,s)
	check("water_399ms_holds_formation", a.frame_index()==3 and s.play.water==water and s.projectiles.launched==1)
	s.paused=true
	a.advance(2.0,s)
	s.paused=false
	a.advance(1.0,s,true)
	check("pause_and_view_suspension_hold_clock", is_equal_approx(a.elapsed_ms,399.0) and s.projectiles.launched==1)
	result=a.advance(0.001,s)
	check("water_400ms_release_cost_once", bool(result.ok) and a.frame_index()==4 and s.projectiles.launched==2 and is_equal_approx(s.play.water,water-s.play.tuning.water_cost_per_shot))
	a.advance(0.4,s)
	check("water_800ms_returns_idle", not a.active and s.projectiles.launched==2)
	# A selected cultivated species stays selected for this shot even after a Tab change.
	s.play.select_index(1)
	var chosen: PlantDef=s.play.selected_def()
	a.start(s,false,aim)
	s.play.select_index(2)
	result=a.advance(0.066,s)
	check("cultivated_selection_snapshot", bool(result.ok) and s.projectiles.shots.back().kind==String(chosen.key) and int(s.play.inflight.get(chosen.key,0))==1)
	var z: RefCounted=session()
	var b: RefCounted=Action.new()
	z.play.seeds=0
	z.play.water=0.0
	check("zero_resources_refuse_without_start", not bool(b.start(z,false,aim).ok) and not bool(b.start(z,true,aim).ok) and not b.active and z.projectiles.launched==0)
	z.play.seeds=10
	b.start(z,false,aim)
	z.play.seeds=0
	result=b.advance(0.066,z)
	check("release_rechecks_resource_failure_no_cost_or_shot", not bool(result.ok) and z.projectiles.launched==0 and z.play.seeds==0 and not b.active)
	z.play.seeds=10
	z.projectiles.max_count=0
	check("full_refuses_preflight", not bool(b.start(z,false,aim).ok) and not b.active)
	z.projectiles.max_count=64
	b.start(z,false,aim)
	z.projectiles.max_count=0
	result=b.advance(0.066,z)
	check("release_rechecks_full_no_cost", not bool(result.ok) and z.play.seeds==10 and z.projectiles.launched==0)
	z.projectiles.max_count=64
	b.start(z,true,aim) # water is still empty; then replenish and start a real charge.
	z.play.water=100.0
	b.start(z,true,aim)
	z.play.health.downed=true
	b.advance(0.5,z)
	check("downed_cancels_pending", not b.active and z.projectiles.launched==0)
	z.play.health.downed=false
	var immediate: Dictionary=z.fire(false,aim)
	check("legacy_immediate_api_still_launches", bool(immediate.ok) and z.projectiles.launched==1 and z.play.seeds==9)
	for made: RefCounted in sessions:
		made.close()
	var file: FileAccess=FileAccess.open(OUT+"logic-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	file.close()
	quit(failures)
