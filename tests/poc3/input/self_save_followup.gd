extends "res://tests/poc3/input/self_logic.gd"

func run() -> void:
	if not OS.get_user_data_dir().contains("evidence/poc3/input/self/profile/"):
		quit(1)
		return
	var session: RefCounted=Session.new()
	session.sow_width=5
	var saved: Dictionary=Save.save_game(session)
	var loaded: Dictionary=Save.load_game()
	check("width_json_roundtrip",saved.ok and loaded.ok and loaded.session.sow_width==5 if loaded.ok else false)
	if loaded.ok: loaded.session.close()
	var unchanged: String=JSON.stringify(session.to_dict(),"",false,true).sha256_text()
	for invalid: Variant in [2,3.5,"3",true]:
		var broken: Dictionary=session.to_dict()
		broken.values.sow_width=invalid
		var rejected: Dictionary=session.restore(broken)
		check("invalid_width_rejected_"+str(invalid),not rejected.ok and unchanged==JSON.stringify(session.to_dict(),"",false,true).sha256_text())
	session.close()
	var failures: int=0
	for result: Dictionary in checks:
		if result.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+"save_followup.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	file.close()
	quit(1 if failures>0 else 0)
