extends "res://tests/poc3/world_layout/self_logic.gd"
var main: Node

func frames(count: int = 2) -> void:
	for index: int in count: await process_frame

func click(at: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position=at
	motion.global_position=at
	root.push_input(motion,true)
	for pressed: bool in [true,false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position=at
		event.global_position=at
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		root.push_input(event,true)
		await frames()

func run() -> void:
	check("startup_minimized_isolated_connected",isolated() and Session.MAP_PATH==EXPECTED_MAP and root.unfocusable and root.mode==Window.MODE_MINIMIZED and ProjectSettings.get_setting("display/window/size/no_focus",false))
	if checks.back().status=="FAIL":
		finish("gpu_results.json")
		return
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await frames(3)
	main=current_scene
	main.auto_process=false
	root.notify_mouse_entered()
	await click(main.ui.menu.get_child(0).get_child(1).get_global_rect().get_center())
	check("normal_new_game_opens_center",main.menu=="" and main.session.position==Coords.cell_center_logic(Vector2i(112,112)))
	var capture: SubViewport = SubViewport.new()
	capture.size=Vector2i(640,360)
	capture.disable_3d=true
	capture.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(capture)
	main.view_rect.reparent(capture)
	main.ui.reparent(capture)
	await frames(3)
	RenderingServer.force_draw(false)
	check("new_center_640_capture",capture.get_texture().get_image().save_png(OUT+"new_start.png")==OK)
	for pressed: bool in [true,false]:
		var key: InputEventKey = InputEventKey.new()
		key.keycode=KEY_TAB
		key.physical_keycode=KEY_TAB
		key.pressed=pressed
		root.push_input(key,true)
	await frames(3)
	RenderingServer.force_draw(false)
	check("new_map_640_capture",main.ui.map.expanded and main.session.paused and capture.get_texture().get_image().save_png(OUT+"new_map.png")==OK)
	check("stayed_minimized_no_focus",root.unfocusable and root.mode==Window.MODE_MINIMIZED)
	main.session.close()
	finish("gpu_results.json")
