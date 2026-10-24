extends SceneTree
## Observe real dispatch and real effects, rather than duplicate latch transition rules.
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/input/independent/results.json"
class ObservedSession extends "res://scripts/poc2/poc2_session.gd":
	var calls: Array[String] = []
	func fire() -> Dictionary:
		calls.append("normal_left")
		return super.fire()
	func water_at(logic: Vector2) -> Dictionary:
		calls.append("normal_right")
		return super.water_at(logic)
	func skill(slot: int) -> Dictionary:
		calls.append("skill_left" if slot == 0 else "skill_right")
		return super.skill(slot)

var checks: Array[Dictionary] = []
var main: Node
var shifted: bool = false
var pointer: Vector2 = Vector2.ZERO

func _init() -> void:
	call_deferred("_run")

func _check(name: String, ok: bool, observations: Dictionary = {}) -> void:
	checks.append({"name":name,"status":"PASS" if ok else "FAIL","observations":observations})
	print(JSON.stringify(checks.back()))

func _frames() -> void:
	await process_frame
	await process_frame

func _key(code: int, pressed: bool) -> void:
	if code == KEY_SHIFT: shifted = pressed
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.shift_pressed = shifted
	root.push_input(event,true)

func _tap(code: int) -> void:
	_key(code,true)
	_key(code,false)
	await _frames()

func _move(at: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = at-pointer
	pointer = at
	root.push_input(event,true)

func _button(which: int, pressed: bool, at: Vector2) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = which
	event.pressed = pressed
	event.shift_pressed = shifted
	root.push_input(event,true)

func _world_point() -> Vector2:
	main.world.sync(0.0)
	return main.world.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(main.session.position+Vector2(8,0))))

func _ready_resources() -> void:
	main.session.calls.clear()
	main.session.seeds = 100
	main.session.water = 100.0
	main.session.shot_ready = 0.0
	main.session.skill_ready.assign([0.0,0.0])
	main._shot_wait = 0.0
	main._water_wait = 0.0

func _wheel(up: bool, at: Vector2) -> void:
	_move(at)
	var which: int = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	_button(which,true,at)
	_button(which,false,at)
	await _frames()

func _run() -> void:
	var profile: String = OS.get_user_data_dir().replace("\\", "/")
	if DisplayServer.get_name() != "headless" or not profile.begins_with("C:/godot/greenvader/evidence/poc3/input/independent/profile/"):
		quit(2)
		return
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT))
	change_scene_to_file(str(ProjectSettings.get_setting("application/run/main_scene")))
	await _frames()
	await _frames()
	main = current_scene
	main.auto_process = false
	main._audio_changed(true,0.0)
	main._on_action("new")
	main.replace_session(ObservedSession.new())
	_ready_resources()
	var at: Vector2 = _world_point()
	_move(at)
	_key(KEY_SHIFT,true)
	_button(MOUSE_BUTTON_LEFT,true,at)
	_key(KEY_SHIFT,false)
	main.tick(0.25)
	main.tick(0.25)
	_check("shift_left_shift_first_release_is_single_skill", main.session.calls == ["skill_left"] and main.session.seeds == 100 and main.session.water == 100.0 and not main._primary, {"calls":main.session.calls.duplicate()})
	_button(MOUSE_BUTTON_LEFT,false,at)
	_ready_resources()
	at = _world_point()
	_move(at)
	_key(KEY_SHIFT,true)
	_button(MOUSE_BUTTON_RIGHT,true,at)
	_button(MOUSE_BUTTON_RIGHT,false,at)
	_key(KEY_SHIFT,false)
	main.tick(0.25)
	_check("shift_right_mouse_first_release_is_single_skill", main.session.calls == ["skill_right"] and main.session.seeds == 97 and main.session.water == 100.0 and not main._secondary, {"calls":main.session.calls.duplicate()})
	var stopped: bool = true
	var normal_observations: Array[Dictionary] = []
	for which: int in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		_ready_resources()
		at = _world_point()
		_move(at)
		_button(which,true,at)
		var initial: Array[String] = main.session.calls.duplicate()
		_key(KEY_SHIFT,true)
		main.tick(0.25)
		_key(KEY_SHIFT,false)
		main.tick(0.25)
		var no_extra: bool = main.session.calls == initial and not main._primary and not main._secondary
		_button(which,false,at)
		main.session.shot_ready = 0.0
		_button(which,true,_world_point())
		var fresh: bool = main.session.calls.size() == 2 and main.session.calls[0] == ("normal_left" if which == MOUSE_BUTTON_LEFT else "normal_right") and main.session.calls[1] == main.session.calls[0]
		stopped = stopped and no_extra and fresh
		normal_observations.append({"button":which,"no_extra_after_shift":no_extra,"new_click_resumes":fresh,"calls":main.session.calls.duplicate()})
		_button(which,false,pointer)
	_check("normal_holds_stop_on_shift_until_fresh_click",stopped,{"cases":normal_observations})
	_ready_resources()
	await _tap(KEY_1)
	var plant_at: Vector2 = main.world.camera.unproject_position(Coords.ground3(Coords.cell_center_ground(Vector2i(190,186))))
	_move(plant_at)
	_button(MOUSE_BUTTON_LEFT,true,plant_at)
	main.tick(0.25)
	main.tick(0.25)
	var one_plant: bool = main.session.plants.size() == 1 and main.ui.selected_slot == 0
	_button(MOUSE_BUTTON_LEFT,false,plant_at)
	_button(MOUSE_BUTTON_RIGHT,true,plant_at)
	main.tick(0.25)
	var cancel_clean: bool = main._placement_kind == "" and main.session.calls.is_empty() and main.session.water == 100.0
	_button(MOUSE_BUTTON_RIGHT,false,plant_at)
	await _tap(KEY_1)
	_key(KEY_SHIFT,true)
	_button(MOUSE_BUTTON_LEFT,true,_world_point())
	_key(KEY_SHIFT,false)
	_button(MOUSE_BUTTON_LEFT,false,pointer)
	_check("placement_one_press_cancel_and_shift_priority",one_plant and cancel_clean and main._placement_kind == "" and main.session.calls == ["skill_left"],{"plant_count":main.session.plants.size(),"cancel_without_water":cancel_clean,"calls":main.session.calls.duplicate()})
	_ready_resources()
	await _tap(KEY_E)
	var before_time: float = main.session.clock.elapsed
	main.tick(0.25)
	var list_paused: bool = main.menu == "plants" and main.session.clock.elapsed == before_time
	var row_at: Vector2 = main.ui.plant_list.rows.clover.get_global_rect().get_center()
	_key(KEY_SHIFT,true)
	_move(row_at)
	_button(MOUSE_BUTTON_LEFT,true,row_at)
	await _tap(KEY_E)
	_key(KEY_SHIFT,false)
	_move(_world_point())
	main.tick(0.25)
	_check("list_shift_hold_close_has_no_combat_leak",list_paused and main.menu == "" and main.session.calls.is_empty() and not main._primary and not main._secondary)
	_button(MOUSE_BUTTON_LEFT,false,pointer)
	_ready_resources()
	await _tap(KEY_TAB)
	main.tick(0.25)
	var map_paused: bool = main.ui.map.expanded and main.session.paused
	main.ui.map.selected_id = main.session.plants[0].id
	main.ui.map.selected_helper = false
	main.ui.map.open_popup("remove")
	await _frames()
	var popup_at: Vector2 = main.ui.map.popup.get_global_rect().get_center()
	_move(popup_at)
	_button(MOUSE_BUTTON_RIGHT,true,popup_at)
	await _frames()
	var canceled: bool = main.ui.map.selected_id == -1 and not main.ui.map.popup.visible
	await _tap(KEY_TAB)
	_move(_world_point())
	main.tick(0.25)
	_check("map_popup_right_cancel_and_closed_hold_do_not_leak",map_paused and canceled and not main.ui.map.expanded and main.session.calls.is_empty() and not main._secondary,{"popup_canceled":canceled})
	_button(MOUSE_BUTTON_RIGHT,false,pointer)
	_ready_resources()
	await _tap(KEY_ESCAPE)
	var paused_menu: bool = main.menu == "pause" and main.session.paused
	_key(KEY_SHIFT,true)
	_button(MOUSE_BUTTON_LEFT,true,main.ui.menu.position+Vector2(4,4))
	await _tap(KEY_ESCAPE)
	_key(KEY_SHIFT,false)
	_move(_world_point())
	main.tick(0.25)
	_check("menu_shift_hold_resume_does_not_leak",paused_menu and main.menu == "" and main.session.calls.is_empty() and not main._primary)
	_button(MOUSE_BUTTON_LEFT,false,pointer)
	main.session.sow_width = 1
	await _wheel(false,_world_point())
	var minimum: bool = main.session.sow_width == 1
	var widths: Array[int] = []
	for index: int in 4:
		await _wheel(true,_world_point())
		widths.append(main.session.sow_width)
	await _tap(KEY_TAB)
	var zoom_before: int = main.ui.map.zoom
	await _wheel(true,main.ui.map.map_rect.get_center())
	var map_only_zoom: bool = main.ui.map.zoom > zoom_before and main.session.sow_width == 7
	await _tap(KEY_TAB)
	await _tap(KEY_E)
	await _wheel(false,main.ui.plant_list.rows.clover.get_global_rect().get_center())
	var list_only: bool = main.menu == "plants" and main.session.sow_width == 7
	await _tap(KEY_E)
	_check("wheel_world_endpoints_map_zoom_list_isolation",minimum and widths == [3,5,7,7] and map_only_zoom and list_only,{"world_widths":widths,"map_only_zoom":map_only_zoom,"list_did_not_change_width":list_only})
	main.session.sow_width = 5
	var saved: Dictionary = Save.save_game(main.session,"user://independent_width")
	var loaded: Dictionary = Save.load_game("user://independent_width")
	var width_restored: bool = loaded.get("ok",false) and loaded.session.sow_width == 5
	if loaded.get("ok",false): loaded.session.close()
	var before: String = JSON.stringify(main.session.to_dict(),"",true,true)
	var all_rejected: bool = true
	for bad: Variant in [2,3.5,"5",true]:
		var data: Dictionary = main.session.to_dict().duplicate(true)
		data.values.sow_width = bad
		var result: Dictionary = main.session.restore(data)
		all_rejected = all_rejected and not result.get("ok",false) and before == JSON.stringify(main.session.to_dict(),"",true,true)
	var old: Dictionary = main.session.to_dict().duplicate(true)
	old.values.erase("sow_width")
	var candidate: RefCounted = Session.new()
	var compatibility: Dictionary = candidate.restore(old)
	var defaulted: bool = compatibility.get("ok",false) and candidate.sow_width == 1
	candidate.close()
	_check("json_width_roundtrip_invalid_rejection_and_default",saved.get("ok",false) and width_restored and all_rejected and defaulted,{"load_ok":loaded.get("ok",false),"width5_restored":width_restored,"invalids_rejected_active_unchanged":all_rejected,"missing_defaults1":defaulted})
	main.session.close()
	var failures: int = 0
	for item: Dictionary in checks:
		if item.status == "FAIL": failures += 1
	report["checks"] = checks
	report["failures"] = failures
	report["user_data"] = profile
	report["godot"] = Engine.get_version_info()
	report["not_run"] = ["independent_gpu_native_physical_input_audio", "wide_regression_and_long_play", "all_sizes_lighting_exported_build_area_seed_effect"]
	var file: FileAccess = FileAccess.open(OUT,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	quit(0 if failures == 0 else 1)
