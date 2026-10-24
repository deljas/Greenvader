extends SceneTree
## Refresh only the fixture's minimap terrain cache; no full GPU/logic regression.
const OUT: String = "res://evidence/poc3/map_info/self/"

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var safe: bool = ProjectSettings.get_setting("display/window/size/no_focus",false) and ProjectSettings.get_setting("display/window/size/mode",-1) == 1 and root.unfocusable and root.mode == Window.MODE_MINIMIZED
	if not safe:
		push_error("Minimized/no-focus startup required")
		quit(1)
		return
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for index: int in 3:
		await process_frame
	var main: Node = current_scene
	main.auto_process = false
	var session: RefCounted = main.session
	session.enemies.clear()
	session.nests.clear()
	session.fossils.clear()
	session.helpers.clear()
	session.state.stage.fill(0) # Display fixture only; never saved.
	session.known.fill(1)
	session.position = Vector2(448,448)
	session.enemies.append({"id":session.allocate_id(),"kind":"boar","pos":session.position+Vector2(30,-30),"hp":20.0})
	for definition: Dictionary in [{"delta":Vector2(-20,-20),"mother":false},{"delta":Vector2(-30,30),"mother":true},{"delta":Vector2(120,140),"mother":false}]:
		session.nests.append({"id":session.allocate_id(),"kind":"mother" if definition.mother else "boar","pos":session.position+definition.delta,"hp":40.0,"scale":"small","mother":definition.mother,"discovered":not definition.mother})
	for delta: Vector2 in [Vector2(50,50),Vector2(140,120)]:
		session.fossils.append({"id":session.allocate_id(),"kind":"fossil","pos":session.position+delta,"unlock":"carrot","found":false,"discovered":true,"nest_id":-1})
	session.reveal()
	main._on_action("resume")
	main.world.sync(0.0)
	var map: Control = main.ui.map
	# The initial capture changed known/position but kept the previous 0.5s cached terrain.
	map.refresh_terrain()
	var capture: SubViewport = SubViewport.new()
	capture.size = Vector2i(640,360)
	capture.disable_3d = true
	capture.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(capture)
	main.view_rect.reparent(capture)
	main.ui.reparent(capture)
	for index: int in 3:
		await process_frame
	RenderingServer.force_draw(false)
	var image: Image = capture.get_texture().get_image()
	var valid: bool = not image.is_empty() and image.get_size() == Vector2i(640,360)
	if valid:
		valid = image.save_png(OUT+"minimap_followup.png") == OK
	# Check cached source colors against authoritative known terrain at representative cells.
	var source_matches: bool = map._terrain_source.get_pixel(112,112) == Color("676856")
	var image_visible: bool = image.get_pixel(60,94).get_luminance() > 0.15 if valid else false
	var stayed_safe: bool = root.unfocusable and root.mode == Window.MODE_MINIMIZED
	var result: Dictionary = {"status":"PASS" if valid and source_matches and image_visible and stayed_safe else "FAIL","capture_640":valid,"cache_refreshed_after_fixture":true,"known_ground_source_matches":source_matches,"minimap_terrain_visible":image_visible,"root_unfocusable":root.unfocusable,"root_mode":root.mode,"not_run":["full_gpu_regression","logic_regression","native_window_visual","physical_input"]}
	var file: FileAccess = FileAccess.open(OUT+"minimap_followup.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	print(result)
	session.close()
	quit(0 if result.status == "PASS" else 1)
