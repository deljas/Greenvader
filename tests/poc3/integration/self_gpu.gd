extends "res://tests/poc3/integration/self_core.gd"
var main: Node
var capture: SubViewport

func frames(count: int = 3) -> void:
	for index: int in count: await process_frame

func safe_window() -> bool:
	return root.unfocusable and root.mode==Window.MODE_MINIMIZED and ProjectSettings.get_setting("display/window/size/no_focus",false) and ProjectSettings.get_setting("display/window/size/mode",-1)==1

func tap(code: int) -> void:
	for pressed: bool in [true,false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode=code
		event.physical_keycode=code
		event.pressed=pressed
		root.push_input(event,true)
	await frames()

func picture(name_: String) -> bool:
	await frames()
	RenderingServer.force_draw(false)
	return capture.get_texture().get_image().save_png(OUT+name_+".png")==OK

func visual_route() -> bool:
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await frames()
	main=current_scene
	main.auto_process=false
	main._audio_changed(true,0.0)
	main._on_action("new")
	root.notify_mouse_entered()
	capture=SubViewport.new()
	capture.size=Vector2i(640,360)
	capture.disable_3d=true
	capture.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(capture)
	main.view_rect.reparent(capture)
	main.ui.reparent(capture)
	if OS.get_cmdline_user_args().has("--water-sequence-followup"):
		await water_sequence()
		main.free()
		capture.free()
		return true
	check("NORMAL_NEW_GAME_GPU",await picture("new_start"))
	check("NATIVE_NEAREST_INTEGER_VIEW",main.render_view.size==Vector2i(640,360) and main.view_rect.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST and root.content_scale_stretch==Window.CONTENT_SCALE_STRETCH_INTEGER)
	# Visual-only setup, explicitly not a gameplay unlocking/economy proof.
	var s: RefCounted = main.session
	s.seeds=500
	for kind: String in ["army","gatlinger","sprinkler"]: s.unlocked[kind]=true
	s.place_plant("clover",Vector2i(112,112))
	s.place_helper("army",Vector2i(113,113))
	s.place_helper("gatlinger",Vector2i(116,113),5)
	s.place_helper("sprinkler",Vector2i(111,114))
	s.advance_game(0.25)
	main.tick(0.0)
	await tap(KEY_TAB)
	var paused_at: float = s.clock.elapsed
	main.tick(0.25)
	check("MAP_STOPS_TIME_WITH_FINAL_HELPER_STATE",main.ui.map.expanded and s.paused and s.clock.elapsed==paused_at and s.helpers.size()==3)
	check("FINAL_MAP_GPU",await picture("map_helpers"))
	await tap(KEY_TAB)
	await tap(KEY_E)
	main.tick(0.25)
	check("E_PLANT_LIST_PAUSES_FINAL_SESSION",main.menu=="plants" and s.paused and s.clock.elapsed==paused_at)
	check("FINAL_LIST_GPU",await picture("plant_list"))
	await tap(KEY_E)
	# A held button originating in a UI must not begin shooting after closing it.
	await tap(KEY_TAB)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position=Vector2(320,180)
	event.global_position=event.position
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	root.push_input(event,true)
	await tap(KEY_TAB)
	var balance: int = s.seeds
	main.tick(0.25)
	check("MAP_CLOSE_DOES_NOT_LEAK_HELD_SHOT",not main._primary and s.seeds==balance)
	event.pressed=false
	root.push_input(event,true)
	await water_sequence()
	# Do not explicitly close: normal main exit ownership must release its session.
	main.free()
	capture.free()
	return true

func water_sequence() -> void:
	var s: RefCounted = main.session
	var followup: bool = OS.get_cmdline_user_args().has("--water-sequence-followup")
	# The first near bank projected the mirror onto land. The north bank used by
	# A west river bank has open water toward the reflected camera-facing side;
	# the earlier north bridge fixture was occluded by buildings/trees.
	s.position=Coords.cell_center_logic(Vector2i(108,98) if followup else Vector2i(112,104))
	observations.bank_fixture_cell=Coords.logic_to_cell(s.position)
	main.tick(0.0)
	check("FINAL_WATER_BANK_GPU",await picture("water_bank_followup" if followup else "water_bank"))
	check("FINAL_REFLECTION_NATIVE_VIEW",main.world.water.reflection_view.size==Vector2i(640,360))
	var sequence: Array[Dictionary] = []
	var captured: bool = true
	main.cursor_known=false
	for index: int in 6:
		var direction: Vector2 = (Vector2.DOWN if index<3 else Vector2.UP) if followup else (Vector2.RIGHT if index<3 else Vector2.LEFT)
		s.set_aim(s.position+direction*16.0)
		s.walk(Coords.ground_dir_to_screen(direction),0.08)
		main.tick(0.08)
		captured=(await picture(("water_followup_" if followup else "water_walk_")+str(index))) and captured
		captured=main.world.water.reflection_view.get_texture().get_image().save_png(OUT+("mirror_followup_" if followup else "reflection_walk_")+str(index)+".png")==OK and captured
		sequence.append({"game_time":s.clock.elapsed,"position":s.position,"direction":str(direction),"actor":main.world.actor.snapshot(),"walking":main.world.walking,"reflection_size":main.world.water.reflection_view.size})
	observations.water_walk_sequence=sequence
	check("CONTINUOUS_WALK_TURN_SEQUENCE_CAPTURED",captured and sequence.size()==6,sequence)

func run() -> void:
	var isolated: bool = OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/integration/self/profile/")
	check("GPU_START_SAFE_ISOLATED",safe_window() and isolated and OS.get_cmdline_user_args().has("--integration-authorized"))
	if not safe_window() or not isolated:
		finish("gpu_results.json")
		return
	if await visual_route()!=true: check("visual_route_completed",false,"runtime abort")
	check("GPU_END_STILL_UNFOCUSED_MINIMIZED",safe_window())
	finish("water_followup_results.json" if OS.get_cmdline_user_args().has("--water-sequence-followup") else "gpu_results.json")
