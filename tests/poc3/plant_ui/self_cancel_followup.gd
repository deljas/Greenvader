extends "res://tests/poc3/plant_ui/self_ui.gd"
## Only the corrected right-cancel path and related held-input boundary.
func run() -> void:
	var safe: bool=ProjectSettings.get_setting("display/window/size/no_focus",false) and ProjectSettings.get_setting("display/window/size/mode",-1)==1 and root.unfocusable and root.mode==Window.MODE_MINIMIZED
	if not safe:
		quit(1)
		return
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await frames(3)
	main=current_scene
	main.auto_process=false
	main.muted=true
	root.notify_mouse_entered()
	main._on_action("new")
	main.session.unlocked.carrot=true
	main._on_action("plants")
	await frames(3)
	var list: Control=main.ui.plant_list
	var originals: Array[String]=main.session.favorites.duplicate()
	await click(list.rows.carrot.get_global_rect().get_center())
	var held: bool=list.held_kind=="carrot"
	button(pointer,true,MOUSE_BUTTON_RIGHT)
	await frames()
	check("right_click_on_row_cancels_and_keeps_slots",held and list.held_kind=="" and main.session.favorites==originals and list.visible)
	var water_before: float=main.session.water
	await key(KEY_E)
	motion(Vector2(340,270))
	main.tick(0.25)
	check("held_right_ui_click_does_not_leak_water",not main._secondary and not main._primary and main.session.water==water_before and main.session.shots.is_empty())
	button(pointer,false,MOUSE_BUTTON_RIGHT)
	var safe_after: bool=root.unfocusable and root.mode==Window.MODE_MINIMIZED
	var failures: int=0
	for result: Dictionary in checks:
		if result.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+"cancel_followup.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"startup_and_exit_minimized_no_focus":safe and safe_after,"not_run":["full_ui_regression","logic_regression","gpu_recapture","physical_input"]},"  "))
	file.close()
	main.session.close()
	quit(1 if failures>0 or not safe_after else 0)
