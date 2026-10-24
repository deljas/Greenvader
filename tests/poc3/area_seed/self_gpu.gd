extends SceneTree
const Coords: GDScript=preload("res://scripts/poc/poc_coords.gd")
const OUT: String="res://evidence/poc3/area_seed/self/"
var main: Node
var checks: Array[Dictionary]=[]

func _init() -> void: call_deferred("run")
func check(name_: String,ok: bool) -> void:
	checks.append({"name":name_,"status":"PASS" if ok else "FAIL"})
	print(checks.back())
func frames(n: int=3) -> void:
	for i: int in n: await process_frame
func motion(at: Vector2) -> void:
	var event: InputEventMouseMotion=InputEventMouseMotion.new()
	event.position=at; event.global_position=at
	root.push_input(event,true)
func button(at: Vector2,pressed: bool) -> void:
	var event: InputEventMouseButton=InputEventMouseButton.new()
	event.position=at; event.global_position=at
	event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
	root.push_input(event,true)

func run() -> void:
	var safe: bool=root.unfocusable and root.mode==Window.MODE_MINIMIZED and ProjectSettings.get_setting("display/window/size/no_focus",false)
	check("startup_no_focus_minimized",safe)
	if not safe or not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/area_seed/self/profile/"):
		quit(1); return
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await frames()
	main=current_scene
	main.auto_process=false
	main._audio_changed(true,0.0)
	main._on_action("new")
	root.notify_mouse_entered()
	var s: RefCounted=main.session
	s.enemies.clear(); s.nests.clear(); s.fossils.clear()
	for y: int in range(183,193):
		for x: int in range(180,205): s.state.set_stage(s.state.index_of(x,y),WorldState.STAGE_EMPTY)
	s.position=Coords.cell_center_logic(Vector2i(187,188))
	s.seeds=5; s.sow_width=7
	main.world.sync(0.0)
	var aim: Vector2=Coords.cell_center_logic(Vector2i(191,188))
	var at: Vector2=main.world.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(aim)))
	motion(at); await frames(1); main.tick(0.0)
	var plan: Dictionary=main.world.sow_plan
	var shown: int=0
	for node: MeshInstance3D in main.world.sow_cells:
		if node.visible: shown+=1
	check("preview_7_budget5_matches_hud",plan.center==Vector2i(191,188) and plan.cost==5 and plan.affordable.size()==5 and plan.unaffordable.size()==44 and shown==49 and main.ui.sow_notice.text.begins_with("5"))
	check("preview_on_ground_without_outlines",main.world.sow_range.position.y>0.0 and main.world.sow_range.scale==Vector3(2.8,1,2.8) and main.world.sow_materials[1].albedo_color!=main.world.sow_materials[2].albedo_color)
	# Composite capture remains offscreen while the native root stays minimized.
	var capture: SubViewport=SubViewport.new()
	capture.size=Vector2i(640,360); capture.disable_3d=true
	capture.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(capture)
	main.view_rect.reparent(capture); main.ui.reparent(capture)
	await frames(); RenderingServer.force_draw(false)
	check("gpu_7_insufficient_image",capture.get_texture().get_image().save_png(OUT+"preview_7_insufficient.png")==OK)
	s.sow_width=3; s.seeds=30; main.tick(0.0)
	check("width_change_keeps_aim_center",main.world.sow_plan.center==plan.center and main.world.sow_plan.cost==9)
	await frames(); RenderingServer.force_draw(false)
	check("gpu_3_affordable_image",capture.get_texture().get_image().save_png(OUT+"preview_3_affordable.png")==OK)
	# A distant cursor must show the same 8m-limited target the shot uses.
	s.set_aim(s.position+Vector2(200,0))
	var far_plan: Dictionary=s.sow_preview()
	check("range_limited_target_matches_launch",absf(s.position.distance_to(far_plan.target)-80.0)<0.001 and s.fire().ok and s.shots[0].target.is_equal_approx(far_plan.target))
	s.shots.clear(); s.shot_ready=0.0; s.set_aim(aim); s.seeds=1; s.sow_width=7
	s.enemies.append({"id":999,"pos":aim,"hp":20.0,"max_hp":20.0})
	main.tick(0.0)
	check("enemy_preview_one_no_area",main.world.sow_plan.attack and main.world.sow_plan.cost==1 and not main.world.sow_range.visible and main.ui.sow_notice.text.contains("攻撃"))
	await frames(); RenderingServer.force_draw(false)
	check("gpu_attack_image",capture.get_texture().get_image().save_png(OUT+"preview_attack.png")==OK)
	s.enemies.clear()
	# Direct engine-event routing, no native mouse/keyboard calls.
	var balance: int=s.seeds
	motion(Vector2(500,25)); button(Vector2(500,25),true); button(Vector2(500,25),false)
	await frames(1); main.tick(0.0)
	check("hud_click_does_not_fire_or_preview",s.seeds==balance and s.shots.is_empty() and main.world.sow_plan.is_empty() and not main.ui.sow_notice.visible)
	main.ui.map.set_expanded(true); main.tick(0.0)
	check("map_hides_preview",main.world.sow_plan.is_empty() and not main.ui.sow_notice.visible and s.paused)
	main.ui.map.set_expanded(false)
	main._on_action("help"); main.tick(0.0)
	check("help_has_real_area_instruction",not main.ui.help.get_child(0).get_child(0).text.contains("選択のみ") and not main.ui.status.tooltip_text.contains("後続") and main.world.sow_plan.is_empty())
	await frames(); RenderingServer.force_draw(false)
	check("gpu_help_image",capture.get_texture().get_image().save_png(OUT+"help.png")==OK)
	check("integer_nearest_rendering",main.render_view.size==Vector2i(640,360) and main.view_rect.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST and root.content_scale_stretch==Window.CONTENT_SCALE_STRETCH_INTEGER and main.render_view.msaa_3d==Viewport.MSAA_DISABLED)
	check("stayed_no_focus_minimized",root.unfocusable and root.mode==Window.MODE_MINIMIZED)
	var failures: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+"gpu_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"not_run":["physical input","full regression","all lighting and resolutions","future target movement prediction"]},"  "))
	file.close()
	s.close()
	quit(1 if failures>0 else 0)
