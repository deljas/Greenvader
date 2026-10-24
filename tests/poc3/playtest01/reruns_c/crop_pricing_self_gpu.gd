extends SceneTree
const OUT: String = "res://evidence/poc3/playtest01/self/rerun_C_crop_pricing/"
var main: Node
var checks: Array[Dictionary] = []

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks.append({"name":label,"status":"PASS" if passed else "FAIL","detail":detail})
	print(JSON.stringify(checks.back()))

func frames(count: int = 3) -> void:
	for index: int in count: await process_frame

func safe_window() -> bool:
	return root.unfocusable and root.mode==Window.MODE_MINIMIZED and ProjectSettings.get_setting("display/window/size/no_focus",false) and ProjectSettings.get_setting("display/window/size/mode",-1)==1

func finish() -> void:
	var failures: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+"gpu_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"not_run":["physical mouse/keyboard","balance and enjoyment","all lighting/resolutions"]},"  "))
	file.close()
	quit(1 if failures else 0)

func run() -> void:
	var isolated: bool=OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/playtest01/self/rerun_C_crop_pricing/profile/")
	check("startup_no_focus_minimized_isolated",safe_window() and isolated)
	if not safe_window() or not isolated:
		finish(); return
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await frames()
	main=current_scene
	main.auto_process=false; main._audio_changed(true,0.0)
	main._on_action("new")
	var s: RefCounted=main.session
	s.enemies.clear(); s.nests.clear(); s.fossils.clear()
	s.unlocked.watermelon=true; s.seeds=10000
	var success: bool=true
	# Sites inside the central green clearing (the older 180..192,184 sites are outside the explored start area).
	for cell: Vector2i in [Vector2i(106,108),Vector2i(110,108),Vector2i(114,108),Vector2i(108,112),Vector2i(112,112)]:
		success=bool(s.place_plant("watermelon",cell).ok) and success
	check("fixture_five_live_immature",success and s.plants.size()==5 and s.current_cost("watermelon")==194)
	if not success:
		s.close(); finish(); return
	s.set_favorite(1,"watermelon")
	main.ui.select_slot(1)
	main.tick(0.0)
	check("hud_displays_next_cost",main.ui.status.text.ends_with("194"),main.ui.status.text)
	# Normal 640x360 composition captured offscreen; the native window stays minimized.
	var capture: SubViewport=SubViewport.new()
	capture.size=Vector2i(640,360); capture.disable_3d=true
	capture.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(capture)
	main.view_rect.reparent(capture); main.ui.reparent(capture)
	await frames(); RenderingServer.force_draw(false)
	check("hud_640_gpu_capture",capture.get_texture().get_image().save_png(OUT+"hud_next_cost.png")==OK)
	main._on_action("plants")
	main.ui.refresh()
	await frames()
	var row: Control=main.ui.plant_list.rows.watermelon
	check("list_matches_count_and_next_price",row.columns[2].text=="5" and row.columns[4].text=="● 194",{"count":row.columns[2].text,"price":row.columns[4].text})
	RenderingServer.force_draw(false)
	check("list_640_gpu_capture",capture.get_texture().get_image().save_png(OUT+"list_next_cost.png")==OK)
	# Removal must immediately change both existing UI clients on refresh.
	s.remove_plant(s.plants[0].id)
	main.ui.refresh()
	check("removal_refreshes_list_and_hud",main.ui.status.text.ends_with("176") and row.columns[2].text=="4" and row.columns[4].text=="● 176")
	check("integer_nearest_unchanged",main.render_view.size==Vector2i(640,360) and main.view_rect.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST and root.content_scale_stretch==Window.CONTENT_SCALE_STRETCH_INTEGER)
	check("finished_no_focus_minimized",safe_window())
	s.close()
	finish()
