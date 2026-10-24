extends "res://tests/poc3/helpers/self_logic.gd"
var main: Node
var capture_view: SubViewport

func frames(count: int=3) -> void:
	for index: int in count: await process_frame

func safe() -> bool:
	return root.unfocusable and root.mode==Window.MODE_MINIMIZED and ProjectSettings.get_setting("display/window/size/no_focus",false) and ProjectSettings.get_setting("display/window/size/mode",-1)==1

func shot(label: String) -> bool:
	RenderingServer.force_draw(false)
	return capture_view.get_texture().get_image().save_png(OUT+label+".png")==OK

func finish() -> void:
	var failures: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+"gpu_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  ")); file.close()
	quit(1 if failures else 0)

func run() -> void:
	check("gpu_start_no_focus_minimized",safe())
	if not safe() or not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/playtest01/self/rerun_B_helpers/profile/"): finish(); return
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await frames()
	main=current_scene; main.auto_process=false; main._audio_changed(true,0.0); main._on_action("new")
	var s: RefCounted=fresh()
	var gat: Dictionary=helper(s,"gatlinger",anchor+Vector2i(-3,3),3)
	var empty: Dictionary=helper(s,"gatlinger",anchor+Vector2i(3,-3),0)
	var sprinkler: Dictionary=helper(s,"sprinkler",anchor+Vector2i(-3,-3))
	var army: Dictionary=helper(s,"army",anchor+Vector2i(3,3))
	for index: int in Landing.tiles_in_radius(s.state,4,gat.home,75.0):
		if s.state.target[index]==1: s.state.set_stage(index,4)
	s.advance_game(4.0)
	gat.hp=40.0
	# Exercise presentation of a partial refill store alongside actual idle/empty.
	sprinkler.water=50.0; sprinkler.water_task="refilling"; sprinkler.status="refilling"; sprinkler.sleeping=false
	main.replace_session(s)
	main.world.sync(0.0)
	capture_view=SubViewport.new(); capture_view.size=Vector2i(640,360); capture_view.disable_3d=true
	capture_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(capture_view)
	main.view_rect.reparent(capture_view); main.ui.reparent(capture_view)
	s.set_favorite(0,"army"); main.ui.select_slot(0)
	main.cursor_known=true
	main.cursor=main.world.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(Coords.cell_center_logic(anchor+Vector2i(3,0)))))
	main.tick(0.0)
	await frames()
	var effects: Node3D=main.world.helper_effects
	check("placement_6m_ring_and_worker_states",effects.ring.visible and gat.sleeping and empty.status=="empty" and effects.labels[gat.id].label.text=="Zzz")
	check("partial_bars_no_numbers_full_army_hidden",effects.labels[gat.id].bars[0].visible and effects.labels[gat.id].bars[1].visible and not effects.labels[army.id].bars[0].visible and not effects.labels[army.id].label.text.contains("HP"))
	check("range_and_states_capture",shot("range_states"))
	main.ui.clear_selection(); main.cursor_known=false
	var tile: Vector2i=anchor+Vector2i(3,1)
	s.state.set_stage(s.state.index_of(tile.x,tile.y),0)
	var target: Vector2=Coords.cell_center_logic(tile)
	s.combat_system.helper_seed(gat,target)
	gat.action_kind="sow"; gat.action_until=s.clock.elapsed+0.3; gat.sleeping=false
	gat.hp-=1.0
	sprinkler.action_kind="water"; sprinkler.action_until=s.clock.elapsed+0.3; sprinkler.status="watering"; sprinkler.water_task=""
	army.action_kind="attack"; army.action_until=s.clock.elapsed+0.22
	s.combat_system._shots(0.02)
	main.tick(0.0); await frames()
	check("flying_individual_seed_and_action_capture",s.shots.size()==1 and main.world.entities["helpers"+str(gat.id)].get_meta("visual_state")=="hit" and shot("flying_actions"))
	s.combat_system._shots(0.25)
	sprinkler.job_kind="grass"; sprinkler.job_id=s.state.index_of(tile.x,tile.y); sprinkler.target_pos=target
	main.ui.map.set_expanded(true); main.ui.map.selected_id=sprinkler.id; main.ui.map.selected_helper=true
	main.ui.map.zoom=4; main.ui.map.map_center=s.position; main.ui.map.refresh_terrain()
	main.tick(0.0); await frames()
	check("selected_map_home_range_job_capture",main.ui.map.expanded and shot("selected_map"))
	check("gpu_end_no_focus_minimized",safe())
	s.close(); finish()
