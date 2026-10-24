extends "res://tests/poc3/plant_ui/self_ui.gd"
## Representative routing transitions only; all events stay inside Godot.
const Save: GDScript=preload("res://scripts/poc2/save/poc2_save.gd")
const INPUT_OUT: String="res://evidence/poc3/playtest01/self/rerun_B_input/"
var shifted: bool=false

func key_state(code: int, pressed: bool) -> void:
	if code==KEY_SHIFT: shifted=pressed
	var event: InputEventKey=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	event.shift_pressed=shifted
	root.push_input(event,true)

func tap(code: int) -> void:
	key_state(code,true)
	key_state(code,false)
	await frames()

func button(at: Vector2, pressed: bool, which: int=MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton=InputEventMouseButton.new()
	event.position=at
	event.global_position=at
	event.button_index=which
	event.pressed=pressed
	event.shift_pressed=shifted
	root.push_input(event,true)

func game_at() -> Vector2:
	main.world.sync(0.0)
	return main.world.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(main.session.position+Vector2(100,0))))

func fresh_resources() -> void:
	main.session.seeds=100
	main.session.water=100.0
	main.session.shot_ready=0.0
	main.session.skill_ready.assign([0.0,0.0])
	main.session.income_fraction=0.0
	main.session.shots.clear()
	main._shot_wait=0.0
	main._water_wait=0.0

func run() -> void:
	var safe: bool=ProjectSettings.get_setting("display/window/size/no_focus",false) and ProjectSettings.get_setting("display/window/size/mode",-1)==1 and root.unfocusable and root.mode==Window.MODE_MINIMIZED
	check("startup_minimized_no_focus",safe)
	if not safe:
		quit(1)
		return
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await frames(3)
	main=current_scene
	main.auto_process=false
	main._audio_changed(true,0.0)
	root.notify_mouse_entered()
	await click(main.ui.menu.get_child(0).get_child(1).get_global_rect().get_center())
	# Normal hold, then both buttons' Shift-after-press and release-order cases.
	fresh_resources()
	var at: Vector2=game_at()
	motion(at)
	button(at,true)
	for index: int in 4: main.tick(0.25)
	check("normal_left_hold_repeats",main.session.seeds<=98 and main._primary)
	button(at,false)
	for which: int in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		fresh_resources()
		at=game_at()
		# Fixture (work B): the shot lands at most 120px away and sowing/watering only act on cells that can take effect, so
		# prepare the real landing cells: empty plantable ground for the seed, an unwatered growing seed for the water.
		motion(at)
		main.tick(0.0)
		var landing: Vector2i=Coords.logic_to_cell(main.session.sow_preview().get("target",main.session.aim)) if which==MOUSE_BUTTON_LEFT else Vector2i(main.world.water_plan.get("center",Vector2i.ZERO))
		for dy: int in range(-1,2):
			for dx: int in range(-1,2):
				var cell_index: int=main.session.state.index_of(landing.x+dx,landing.y+dy)
				main.session.state.set_stage(cell_index,WorldState.STAGE_EMPTY if which==MOUSE_BUTTON_LEFT else WorldState.STAGE_SEED)
		main.tick(0.0)
		motion(at)
		button(at,true,which)
		var seed_after: int=main.session.seeds
		var water_after: float=main.session.water
		var skills_before: Array[float]=main.session.skill_ready.duplicate()
		key_state(KEY_SHIFT,true)
		main.tick(0.25)
		key_state(KEY_SHIFT,false)
		main.tick(0.25)
		check("shift_during_normal_hold_stops_no_skill_"+str(which),main.session.seeds==seed_after and main.session.water==(water_after if which==MOUSE_BUTTON_LEFT else water_after-1.0) and main.session.skill_ready==skills_before and not main._primary and not main._secondary)
		button(at,false,which)
		main.session.shot_ready=0.0
		# Work B: a water click already in progress spends at its 400ms release (so the Shift test above sees 1 spent) and the
		# next click waits for the animation; make the landing cells valid again and clear the wait so only routing is tested.
		main._water_wait=0.0
		if which==MOUSE_BUTTON_RIGHT:
			for step: int in 4: main.tick(0.25) # (max 0.25s per tick) let the 800ms water animation finish; clicks during it are ignored by design
			for dy: int in range(-1,2):
				for dx: int in range(-1,2):
					var wet_index: int=main.session.state.index_of(landing.x+dx,landing.y+dy)
					main.session.state.set_stage(wet_index,WorldState.STAGE_SEED)
					main.session.state.moisture[wet_index]=0
		button(game_at(),true,which)
		if which==MOUSE_BUTTON_RIGHT: main.tick(0.0) # a held right button starts the water on the next tick
		check("release_then_fresh_normal_click_"+str(which),main.session.seeds==seed_after-1 if which==MOUSE_BUTTON_LEFT else main._water_pending)
		button(pointer,false,which)
	# Shift+new left click consumes no seed/water, and Shift release cannot arm a normal hold.
	fresh_resources()
	at=game_at()
	motion(at)
	key_state(KEY_SHIFT,true)
	button(at,true)
	var tackle_ready: float=main.session.skill_ready[0]
	key_state(KEY_SHIFT,false)
	main.tick(0.25)
	check("shift_left_once_and_shift_release_no_normal",tackle_ready>main.session.clock.elapsed and main.session.seeds==100 and main.session.water==100.0 and not main._primary and main.session.shots.is_empty())
	button(at,false)
	fresh_resources()
	at=game_at()
	motion(at)
	key_state(KEY_SHIFT,true)
	button(at,true,MOUSE_BUTTON_RIGHT)
	var bazooka: bool=main.session.seeds==97 and main.session.shots.size()==1 and main.session.shots[0].kind=="bazooka"
	button(at,false,MOUSE_BUTTON_RIGHT)
	key_state(KEY_SHIFT,false)
	main.tick(0.25)
	check("shift_right_once_mouse_release_first_no_water",bazooka and main.session.seeds==97 and main.session.water==100.0 and not main._secondary)
	# Placement cancellation and Shift dispatch cannot inherit a water/placement hold.
	fresh_resources()
	await tap(KEY_1)
	at=game_at()
	button(at,true,MOUSE_BUTTON_RIGHT)
	main.tick(0.25)
	check("right_placement_cancel_never_waters",main._placement_kind=="" and main.session.water==100.0 and not main._secondary)
	button(at,false,MOUSE_BUTTON_RIGHT)
	await tap(KEY_1)
	key_state(KEY_SHIFT,true)
	button(game_at(),true)
	check("placement_shift_clears_and_uses_skill",main._placement_kind=="" and main.session.skill_ready[0]>main.session.clock.elapsed and main.session.plants.is_empty())
	button(pointer,false)
	key_state(KEY_SHIFT,false)
	await tap(KEY_1)
	await tap(KEY_ESCAPE)
	check("escape_placement_cancel_precedes_menu",main._placement_kind=="" and main.menu=="")
	# Wheel value selection is clamped and is separate from future AREA effects.
	at=game_at()
	for index: int in 4:
		button(at,true,MOUSE_BUTTON_WHEEL_UP)
		button(at,false,MOUSE_BUTTON_WHEEL_UP)
	check("world_wheel_sets_width_without_wrap",main.session.sow_width==7)
	var width: int=main.session.sow_width
	await tap(KEY_TAB)
	var map: Control=main.ui.map
	var elapsed: float=main.session.clock.elapsed
	main.tick(0.25)
	button(Vector2(320,176),true,MOUSE_BUTTON_WHEEL_UP)
	button(Vector2(320,176),false,MOUSE_BUTTON_WHEEL_UP)
	check("tab_map_pauses_and_wheel_only_zooms",map.expanded and main.session.clock.elapsed==elapsed and map.zoom==2 and main.session.sow_width==width)
	map.selected_id=123
	map.popup.show()
	await frames()
	button(map.close_button.get_global_rect().get_center(),true,MOUSE_BUTTON_RIGHT)
	main.tick(0.25)
	check("map_right_cancel_over_gui_blocks_combat",map.expanded and map.selected_id==-1 and not map.popup.visible and main.session.clock.elapsed==elapsed and not main._secondary)
	button(pointer,false,MOUSE_BUTTON_RIGHT)
	map.selected_id=123
	await tap(KEY_ESCAPE)
	var first_escape: bool=map.expanded and map.selected_id==-1
	await tap(KEY_ESCAPE)
	check("map_escape_cancel_then_close",first_escape and not map.expanded)
	await click(Vector2(60,60))
	await click(map.close_button.get_global_rect().get_center())
	check("minimap_open_and_close_button",not map.expanded and not main.session.paused)
	# List wheel/registration and held Shift-click stay in the UI.
	main.session.unlocked.carrot=true
	await tap(KEY_E)
	var list: Control=main.ui.plant_list
	button(list.get_global_rect().get_center(),true,MOUSE_BUTTON_WHEEL_DOWN)
	button(list.get_global_rect().get_center(),false,MOUSE_BUTTON_WHEEL_DOWN)
	await click(list.rows.carrot.get_global_rect().get_center())
	await click(list.slots[1].get_global_rect().get_center())
	check("list_registration_and_wheel_isolation",main.session.favorites[1]=="carrot" and main.session.sow_width==width and main.menu=="plants")
	fresh_resources()
	key_state(KEY_SHIFT,true)
	button(list.rows.carrot.get_global_rect().get_center(),true,MOUSE_BUTTON_RIGHT)
	await tap(KEY_E)
	motion(game_at())
	main.tick(0.25)
	check("ui_shift_hold_closing_does_not_leak",main.session.seeds==100 and main.session.water==100.0 and main.session.skill_ready==[0.0,0.0] and not main._primary and not main._secondary)
	button(pointer,false,MOUSE_BUTTON_RIGHT)
	key_state(KEY_SHIFT,false)
	var position_before: Vector2=main.session.position
	var muted_before: bool=main.muted
	for code: int in [KEY_Q,KEY_R,KEY_M,KEY_N]: await tap(code)
	check("old_q_r_m_n_assignments_removed",main.session.position==position_before and main.session.seeds==100 and main.session.skill_ready==[0.0,0.0] and not map.expanded and main.muted==muted_before)
	await tap(KEY_ESCAPE)
	await click(main.ui.mute_button.get_global_rect().get_center())
	await click(main.ui.volume_slider.get_global_rect().position+Vector2(35,8))
	check("menu_audio_controls",main.muted and main.audio_volume>0.0 and main.audio_volume<1.0 and main.menu=="pause")
	check("pause_menu_fits_640x360",Rect2(Vector2.ZERO,Vector2(640,360)).encloses(main.ui.menu.get_global_rect()))
	await tap(KEY_ESCAPE)
	await tap(KEY_F5)
	var loaded: Dictionary=Save.load_game()
	check("f5_saves_width_and_favorites",loaded.ok and loaded.session.sow_width==width and loaded.session.favorites[1]=="carrot" if loaded.ok else false)
	if loaded.ok: loaded.session.close()
	# Only representative visual captures; no foregrounding/restoration.
	var capture: SubViewport=SubViewport.new()
	capture.size=Vector2i(640,360)
	capture.disable_3d=true
	capture.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(capture)
	main.view_rect.reparent(capture)
	main.ui.reparent(capture)
	await tap(KEY_ESCAPE)
	await frames(3)
	RenderingServer.force_draw(false)
	check("menu_640_capture",capture.get_texture().get_image().save_png(INPUT_OUT+"menu.png")==OK)
	main._on_action("resume")
	main._on_action("help")
	await frames(3)
	RenderingServer.force_draw(false)
	check("updated_help_640_capture",capture.get_texture().get_image().save_png(INPUT_OUT+"help.png")==OK)
	main._on_action("close_help")
	map.set_expanded(true)
	await frames(3)
	RenderingServer.force_draw(false)
	check("map_close_640_capture",map.close_button.visible and capture.get_texture().get_image().save_png(INPUT_OUT+"map.png")==OK)
	check("stayed_minimized_no_focus",root.unfocusable and root.mode==Window.MODE_MINIMIZED)
	var failures: int=0
	for result: Dictionary in checks:
		if result.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(INPUT_OUT+"input_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"not_run":["physical_input","full_regression","area_seed_effect","all_sizes_lighting","map_helper_commands_regression"]},"  "))
	file.close()
	main.session.close()
	quit(1 if failures>0 else 0)
