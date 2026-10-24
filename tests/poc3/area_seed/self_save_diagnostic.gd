extends "res://tests/poc3/area_seed/self_logic.gd"

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/area_seed/self/profile/"):
		quit(1); return
	s=Session.new()
	var index: int=s.state.index_of(CENTER.x,CENTER.y)
	s.state.set_stage(index,WorldState.STAGE_EMPTY)
	s.state.set_stage(index,WorldState.STAGE_SEED)
	s.state.set_stage(index,WorldState.STAGE_EMPTY)
	var stale: Dictionary=s.restore(s.to_dict())
	print("Reproduced zero-time fixture stale-active failure: ",stale)
	check("synthetic_stale_active_cause_reproduced",not stale.ok and stale.reason=="invalid_growth")
	s.close()
	# A genuinely fresh normal session with its original enemies/map/active set.
	s=Session.new()
	s.sow_width=7; s.set_aim(s.position+Vector2(12,0))
	s.fire()
	var good: Dictionary=s.to_dict()
	var saved: Dictionary=Save.save_game(s,"user://area_normal_flight")
	var loaded: Dictionary=Save.load_game("user://area_normal_flight")
	check("fresh_session_flight_json_roundtrip",saved.ok and loaded.ok and Equivalent.same(good,loaded.session.to_dict()) if loaded.ok else false)
	if loaded.ok: loaded.session.close()
	var clean: Dictionary=s.restore(good)
	check("corruption_base_is_restorable",clean.ok)
	var reasons: Dictionary={"stale_fixture":stale.reason}
	for field: String in ["sow_width","reserved_seed"]:
		var bad: Dictionary=good.duplicate(true)
		bad.entities.shots[0][field]=2 if field=="sow_width" else 0
		var rejected: Dictionary=s.restore(bad)
		reasons[field]=rejected.reason
		check("invalid_"+field+"_rejects_entity_atomically",not rejected.ok and rejected.reason=="invalid_entity_shots" and Equivalent.same(good,s.to_dict()))
	var failures: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+"save_diagnostic_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"reasons":reasons,"failures":failures},"  "))
	file.close(); s.close()
	quit(1 if failures>0 else 0)
