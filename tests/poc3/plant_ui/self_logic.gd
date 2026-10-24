extends SceneTree
const Session: GDScript=preload("res://scripts/poc2/poc2_session.gd")
const Save: GDScript=preload("res://scripts/poc2/save/poc2_save.gd")
const Row: GDScript=preload("res://scripts/poc2/ui/plant_list_row.gd")
const OUT: String="res://evidence/poc3/plant_ui/self/"
var checks: Array[Dictionary]=[]

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"status":"PASS" if passed else "FAIL"})
	print(checks.back())

func fingerprint(session: RefCounted) -> String:
	return JSON.stringify(session.to_dict(),"",false,true).sha256_text()

func run() -> void:
	if not OS.get_user_data_dir().contains("evidence/poc3/plant_ui/self/profile/"):
		quit(1)
		return
	var session: RefCounted=Session.new()
	check("default_five_favorites",session.favorites==["clover","","","",""])
	check("duplicate_registration_allowed",session.set_favorite(1,"clover").ok and session.favorites[0]==session.favorites[1])
	var before: Array[String]=session.favorites.duplicate()
	check("locked_unknown_and_bad_slot_rejected",not session.set_favorite(2,"wheat").ok and not session.set_favorite(2,"unknown").ok and not session.set_favorite(5,"clover").ok and session.favorites==before)
	# Only this unsaved metrics fixture uses minimal entities.
	session.plants.assign([{"kind":"clover","hp":30.0,"mature":false},{"kind":"clover","hp":30.0,"mature":true},{"kind":"clover","hp":0.0,"mature":true}])
	session.helpers.assign([{"kind":"army","hp":80.0}])
	var crop: Dictionary=session.plant_stats("clover")
	var helper: Dictionary=session.plant_stats("army")
	check("count_includes_immature_production_mature_alive_only",crop.count==2 and is_equal_approx(crop.rate_per_second,1.0/30.0) and helper.count==1 and helper.rate_per_second==0.0)
	check("base_price_api",session.current_cost("clover")==13 and session.current_cost("watermelon")==120 and session.current_cost("army")==25)
	check("production_precision_boundaries",Row.production_text(0.5)=="+0.500 ●/s" and Row.production_text(1.0)=="+1.00 ●/s" and Row.production_text(100.0)=="+100.0 ●/s" and Row.production_text(0.0,false)=="—")
	session.close()
	# Persistence checks use a separate, valid world.
	session=Session.new()
	session.unlocked.carrot=true
	session.set_favorite(0,"carrot")
	session.set_favorite(3,"clover")
	var state: Dictionary=session.to_dict()
	var saved: Dictionary=Save.save_game(session)
	var loaded: Dictionary=Save.load_game()
	check("favorites_save_restore",saved.ok and loaded.ok and loaded.session.favorites==session.favorites if loaded.ok else false)
	if loaded.ok: loaded.session.close()
	var earlier: Dictionary=state.duplicate(true)
	earlier.values.erase("favorites")
	var candidate: RefCounted=Session.new()
	var restored: Dictionary=candidate.restore(earlier)
	check("earlier_poc3_defaults_favorites",restored.ok and candidate.favorites==["clover","","","",""])
	candidate.close()
	var original: String=fingerprint(session)
	var invalids: Array[Array]=[["clover"],["clover","",1,"",""],["clover","unknown","","",""],["clover","wheat","","",""]]
	var labels: Array[String]=["length","type","unknown","locked"]
	for index: int in invalids.size():
		var invalid: Dictionary=state.duplicate(true)
		invalid.values.favorites=invalids[index]
		var rejected: Dictionary=session.restore(invalid)
		check("invalid_favorites_"+labels[index]+"_session_unchanged",not rejected.ok and original==fingerprint(session))
	session.close()
	var failures: int=0
	for result: Dictionary in checks:
		if result.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+"logic_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"not_run":["broad_regression","long_play"]},"  "))
	file.close()
	quit(1 if failures>0 else 0)
