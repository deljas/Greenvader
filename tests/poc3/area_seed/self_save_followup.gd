extends "res://tests/poc3/area_seed/self_logic.gd"

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/area_seed/self/profile/"):
		quit(1); return
	s=Session.new()
	fixture(7,60)
	s.fire(); s.combat_system._shots(0.05)
	var saved: Dictionary=Save.save_game(s)
	var loaded: Dictionary=Save.load_game()
	print("real JSON save/load: ",saved," / ",loaded.get("reason",""))
	check("flying_shot_real_json_roundtrip",saved.ok and loaded.ok and Equivalent.same(s.to_dict(),loaded.session.to_dict()) if loaded.ok else false)
	if loaded.ok:
		s.close(); s=loaded.session
		s.sow_width=1
		s.combat_system._shots(0.25)
		check("restored_shot_keeps_width_and_reservation",seeded()==49 and s.seeds==11 and s.shots.is_empty())
	fixture(7,60); s.fire()
	var legacy: Dictionary=s.to_dict()
	legacy.entities.shots[0].erase("sow_width")
	legacy.entities.shots[0].erase("reserved_seed")
	var restored: Dictionary=s.restore(legacy)
	print("legacy restore: ",restored)
	check("legacy_shot_defaults",restored.ok and s.shots[0].sow_width==1 and s.shots[0].reserved_seed==1 and s.seeds==59)
	s.combat_system._shots(0.25)
	check("legacy_one_cell_no_extra_debit",seeded()==1 and s.seeds==59)
	var failures: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+"save_followup_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cause":"Initial suite reused synthetic zero-time fixture with stale active entries; rebuild_derived now resets that test fixture only. No product save condition relaxed."},"  "))
	file.close(); s.close()
	quit(1 if failures>0 else 0)
