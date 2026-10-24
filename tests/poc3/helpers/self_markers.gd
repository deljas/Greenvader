extends "res://tests/poc3/helpers/self_logic.gd"
const Map: GDScript=preload("res://scripts/poc2/ui/map_ui.gd")
func run() -> void:
	var s: RefCounted=fresh()
	var h: Dictionary=helper(s,"sprinkler",anchor)
	h.bank=s.nav.bank(h.pos); h.pos=h.bank; h.water=20.0; h.water_task="refilling"; h.status="refilling"
	s.plant_system._sprinkler(h,0.0)
	var bank_mark: bool=h.target_pos==h.bank
	h.water_task="returning_water"
	s.plant_system._sprinkler(h,0.0)
	check("refill_job_marker_tracks_bank_and_home",bank_mark and h.target_pos==h.home)
	s.close()
	var file: FileAccess=FileAccess.open(OUT+"marker_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":0 if checks[0].status=="PASS" else 1},"  ")); file.close()
	quit(0 if checks[0].status=="PASS" else 1)
