extends SceneTree
const Latch: GDScript=preload("res://scripts/poc2/input_latch.gd")
const Session: GDScript=preload("res://scripts/poc2/poc2_session.gd")
const Save: GDScript=preload("res://scripts/poc2/save/poc2_save.gd")
const OUT: String="res://evidence/poc3/playtest01/self/rerun_C_input/"
var checks: Array[Dictionary]=[]

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"status":"PASS" if passed else "FAIL"})
	print(checks.back())

func run() -> void:
	if not OS.get_user_data_dir().contains("evidence/poc3/playtest01/self/rerun_C_input/profile/"):
		quit(1)
		return
	for button: int in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		var latch: RefCounted=Latch.new()
		var normal: StringName=&"seed" if button==MOUSE_BUTTON_LEFT else &"water"
		var skill: StringName=&"skill1" if button==MOUSE_BUTTON_LEFT else &"skill2"
		var started: bool=latch.press(button,false)==normal and latch.held_action(button)==normal
		latch.set_shift(true)
		latch.set_shift(false)
		check("normal_hold_shift_stops_until_release_"+str(button),started and latch.held_action(button)==&"" and latch.press(button,false)==&"")
		latch.release(button)
		check("fresh_click_resumes_after_release_"+str(button),latch.press(button,false)==normal)
		latch.release(button)
		var shifted: bool=latch.press(button,true)==skill
		latch.set_shift(false)
		check("skill_shift_release_never_becomes_normal_"+str(button),shifted and latch.held_action(button)==&"" and latch.press(button,false)==&"")
		latch.release(button)
		latch.block_press(button)
		var ui_blocked: bool=latch.press(button,false)==&""
		latch.release(button)
		latch.press(button,false)
		latch.cancel_holds()
		check("ui_and_mode_holds_blocked_"+str(button),ui_blocked and latch.held_action(button)==&"" and latch.press(button,false)==&"")
	var placement: RefCounted=Latch.new()
	check("placement_single_press_and_right_cancel",placement.press(MOUSE_BUTTON_LEFT,false,true)==&"place" and placement.held_action(MOUSE_BUTTON_LEFT)==&"" and placement.press(MOUSE_BUTTON_LEFT,false,true)==&"" and placement.press(MOUSE_BUTTON_RIGHT,false,true)==&"cancel_placement" and placement.held_action(MOUSE_BUTTON_RIGHT)==&"")
	var session: RefCounted=Session.new()
	var widths: Array[int]=[session.sow_width]
	for index: int in 4: widths.append(session.adjust_sow_width(1))
	for index: int in 4: widths.append(session.adjust_sow_width(-1))
	check("width_selection_clamped_1_3_5_7",widths==[1,3,5,7,7,5,3,1,1])
	session.sow_width=5
	var saved: Dictionary=Save.save_game(session)
	var loaded: Dictionary=Save.load_game()
	check("width_save_restore",saved.ok and loaded.ok and loaded.session.sow_width==5 if loaded.ok else false)
	if loaded.ok: loaded.session.close()
	var state: Dictionary=session.to_dict()
	var earlier: Dictionary=state.duplicate(true)
	earlier.values.erase("sow_width")
	var candidate: RefCounted=Session.new()
	var fallback: Dictionary=candidate.restore(earlier)
	check("older_poc3_width_defaults_one",fallback.ok and candidate.sow_width==1)
	candidate.close()
	var unchanged: String=JSON.stringify(session.to_dict(),"",false,true).sha256_text()
	for invalid: Variant in [2,"3",true]:
		var broken: Dictionary=state.duplicate(true)
		broken.values.sow_width=invalid
		var rejected: Dictionary=session.restore(broken)
		check("invalid_width_rejected_"+type_string(typeof(invalid)),not rejected.ok and unchanged==JSON.stringify(session.to_dict(),"",false,true).sha256_text())
	session.close()
	var failures: int=0
	for result: Dictionary in checks:
		if result.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+"logic_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"not_run":["area_seed_effect","wide_regression"]},"  "))
	file.close()
	quit(1 if failures>0 else 0)
