extends SceneTree
const Coords: GDScript=preload("res://scripts/poc/poc_coords.gd")
const OUT: String="res://evidence/poc3/plant_ui/self/"
var checks: Array[Dictionary]=[]
var main: Node
var pointer: Vector2=Vector2.ZERO

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"status":"PASS" if passed else "FAIL"})
	print(checks.back())

func frames(count: int=2) -> void:
	for index: int in count: await process_frame

func motion(at: Vector2, held: bool=false) -> void:
	var event: InputEventMouseMotion=InputEventMouseMotion.new()
	event.position=at
	event.global_position=at
	event.relative=at-pointer
	event.button_mask=MOUSE_BUTTON_MASK_LEFT if held else 0
	pointer=at
	root.push_input(event,true)

func button(at: Vector2, pressed: bool, which: int=MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton=InputEventMouseButton.new()
	event.position=at
	event.global_position=at
	event.button_index=which
	event.pressed=pressed
	root.push_input(event,true)

func click(at: Vector2) -> void:
	motion(at)
	button(at,true)
	await frames(1)
	button(at,false)
	await frames()

func key(code: int) -> void:
	for pressed: bool in [true,false]:
		var event: InputEventKey=InputEventKey.new()
		event.keycode=code
		event.physical_keycode=code
		event.pressed=pressed
		root.push_input(event,true)
	await frames()

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
	main.muted=true
	root.notify_mouse_entered()
	var new_button: Button=main.ui.menu.get_child(0).get_child(1)
	await click(new_button.get_global_rect().get_center())
	check("new_game_engine_click",main.menu=="" and not main.session.paused)
	await key(KEY_1)
	var first_selected: bool=main.ui.selected_slot==0 and main._placement_kind=="clover"
	await key(KEY_1)
	check("same_favorite_key_toggles_off",first_selected and main.ui.selected_slot==-1 and main._placement_kind=="")
	main.session.set_favorite(1,"clover")
	await key(KEY_1)
	await key(KEY_2)
	check("duplicate_kind_switches_by_slot",main.ui.selected_slot==1 and main._placement_kind=="clover")
	await click(main.world.camera.unproject_position(Coords.ground3(Coords.cell_center_ground(Vector2i(182,184)))))
	await click(main.world.camera.unproject_position(Coords.ground3(Coords.cell_center_ground(Vector2i(184,184)))))
	check("repeat_placement_retains_selection",main.session.plants.size()==2 and main.ui.selected_slot==1 and main._placement_kind=="clover")
	for kind: String in main.ui.KEYS: main.session.unlocked[kind]=true
	await key(KEY_E)
	var list: Control=main.ui.plant_list
	main.tick(0.25)
	check("list_pauses_and_background_controls_hidden",main.menu=="plants" and main.session.paused and main.session.clock.elapsed==0.0 and not main.ui.map_button.visible and not main.ui.help_button.visible)
	var ordered: Array[String]=[]
	for row: Node in list.row_box.get_children(): ordered.append(String(row.kind))
	check("unlocked_rank_and_fixed_tie_order",ordered==["clover","carrot","army","wheat","gatlinger","sprinkler","rafflesia","watermelon"])
	await key(KEY_3)
	check("list_number_keys_do_not_change_placement",main.ui.selected_slot==1)
	await click(list.rows.wheat.get_global_rect().get_center())
	await click(list.slots[0].get_global_rect().get_center())
	check("click_hold_register_replaces_slot",main.session.favorites[0]=="wheat" and list.held_kind=="" and main.ui.selected_slot==1)
	await click(list.rows.army.get_global_rect().get_center())
	await click(list.slots[1].get_global_rect().get_center())
	check("overwriting_selected_slot_clears_stale_selection",main.session.favorites[1]=="army" and main.ui.selected_slot==-1 and main._placement_kind=="")
	var originals: Array[String]=main.session.favorites.duplicate()
	await click(list.rows.carrot.get_global_rect().get_center())
	await key(KEY_ESCAPE)
	check("escape_cancels_hold_keeps_original_slots",list.visible and list.held_kind=="" and main.session.favorites==originals)
	var row_at: Vector2=list.rows.clover.get_global_rect().get_center()
	var slot_at: Vector2=list.slots[4].get_global_rect().get_center()
	motion(row_at)
	button(row_at,true)
	motion(row_at+Vector2(12,1),true)
	await frames()
	motion(slot_at,true)
	await frames()
	var dragging: bool=root.gui_is_dragging()
	button(slot_at,false)
	await frames()
	check("engine_drag_drop_registers_favorite",dragging and main.session.favorites[4]=="clover")
	originals=main.session.favorites.duplicate()
	motion(row_at)
	button(row_at,true)
	motion(row_at+Vector2(12,1),true)
	await frames()
	await key(KEY_ESCAPE)
	button(pointer,false)
	await frames()
	check("drag_cancel_keeps_slots",not root.gui_is_dragging() and list.held_kind=="" and main.session.favorites==originals)
	# UI-origin held clicks must not arm world shooting after closing with E.
	motion(row_at)
	button(row_at,true)
	await key(KEY_E)
	motion(Vector2(340,270),true)
	main.tick(0.25)
	check("held_ui_click_does_not_leak_to_world",not main._primary and main.session.shots.is_empty())
	button(pointer,false)
	await frames()
	await key(KEY_E)
	await click(list.rows.carrot.get_global_rect().get_center())
	button(pointer,true,MOUSE_BUTTON_RIGHT)
	await frames()
	check("right_click_cancels_registration",list.held_kind=="" and main.session.favorites==originals)
	button(pointer,false,MOUSE_BUTTON_RIGHT)
	await key(KEY_E)
	await key(KEY_5)
	main.ui.refresh()
	check("hud_selection_price_seeds_player_bars",main.ui.selected_slot==4 and main.ui.status.text.contains("●10") and main.ui.economy.text.contains(str(main.session.seeds)) and main.ui.hp_bar.value==main.session.hp and main.ui.water_bar.value==main.session.water)
	# The actual canvas is captured off-screen while the OS window remains minimized.
	var capture: SubViewport=SubViewport.new()
	capture.size=Vector2i(640,360)
	capture.disable_3d=true
	capture.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(capture)
	main.view_rect.reparent(capture)
	main.ui.reparent(capture)
	await frames(3)
	RenderingServer.force_draw(false)
	check("hud_640_capture",capture.get_texture().get_image().save_png(OUT+"hud.png")==OK)
	main._on_action("plants")
	list.rows.clover.mouse_entered.emit()
	await frames(3)
	RenderingServer.force_draw(false)
	check("list_640_capture_and_hover",capture.get_texture().get_image().save_png(OUT+"plant_list.png")==OK and list.detail_label.text.contains("成熟1株") and list.detail_label.text.contains("+0.033"))
	check("stayed_minimized_no_focus",root.unfocusable and root.mode==Window.MODE_MINIMIZED)
	var failures: int=0
	for result: Dictionary in checks:
		if result.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+"ui_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"input":"Viewport.push_input only; no OS input or cursor control","not_run":["physical_input","wide_regression","all_sizes_lighting"]},"  "))
	file.close()
	main.session.close()
	quit(1 if failures>0 else 0)
