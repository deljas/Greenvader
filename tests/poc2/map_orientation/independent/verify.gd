extends SceneTree
## Independent bounded GPU checks. Expected directions come from the real Camera3D.
const Main: PackedScene = preload("res://scenes/poc2.tscn")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc2/map_orientation/independent/"
var main: Node
var checks: Array[Dictionary] = []

func _init() -> void:
	root.unfocusable = true
	call_deferred("run")

func frames() -> void:
	for index: int in 3: await process_frame
	await RenderingServer.frame_post_draw

func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks.append({"name":label,"status":"PASS" if passed else "FAIL","detail":detail})
	print(checks.back())

func key(code: int) -> void:
	for pressed: bool in [true,false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code; event.physical_keycode = code; event.pressed = pressed
		Input.parse_input_event(event)

func mouse(at: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	for pressed: bool in [true,false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = root.get_final_transform()*at
		event.button_index = button; event.pressed = pressed
		Input.parse_input_event(event)

func shot(label: String) -> Image:
	var image: Image = root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT+label+".png"))
	return image

func camera_point(logic: Vector2) -> Vector2:
	return main.world.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(logic)))

func terrain_color(s: RefCounted, cell: Vector2i) -> Color:
	if not s.state.in_bounds(cell.x,cell.y): return Color("0d1517")
	var index: int = s.state.index_of(cell.x,cell.y)
	if s.known[index] == 0: return Color("151e20")
	var terrain: int = s.state.terrain[index]
	if terrain == 3: return Color("4d8eab")
	if terrain == 4: return Color("a5a292")
	if s.state.stage[index] >= WorldState.GREENED_MIN_STAGE: return Color("558a50")
	if terrain == 6: return Color("777872")
	return Color("676856")

func projection_check(map: Control, label: String) -> void:
	var origin: Vector2 = map.map_center if map.expanded else main.session.position
	var anchor: Vector2 = map.point(origin)
	var actual_origin: Vector2 = camera_point(origin)
	var camera_axis: Vector2 = camera_point(origin+Vector2(160,0))-actual_origin
	var map_axis: Vector2 = map.point(origin+Vector2(160,0))-anchor
	var scale_: float = map_axis.dot(camera_axis)/camera_axis.length_squared()
	var worst: float = 0.0
	for delta: Vector2 in [Vector2(160,0),Vector2(0,160),Vector2(120,-120),Vector2(120,120)]:
		var expected: Vector2 = (camera_point(origin+delta)-actual_origin)*scale_
		worst = maxf(worst,(map.point(origin+delta)-anchor-expected).length())
	check(label,scale_>0 and worst<=1.5,{"worst_pixel_error":worst,"uniform_scale":scale_})

func terrain_check(map: Control, label: String) -> void:
	var image: Image = map.terrain_texture.get_image()
	var mismatch: int = 0
	var sampled: int = 0
	for y: int in range(12,image.get_height()-12,17):
		for x: int in range(12,image.get_width()-12,19):
			var pixel_center: Vector2 = Vector2(x,y)+Vector2(0.5,0.5)
			if not map.expanded and pixel_center.distance_to(map.map_rect.size*0.5)>54.0: continue
			var logic: Vector2 = map.logic_at(map.map_rect.position+pixel_center)
			var expected: Color = terrain_color(main.session,Coords.logic_to_cell(logic))
			if image.get_pixel(x,y).to_html(false)!=expected.to_html(false): mismatch+=1
			sampled+=1
	check(label,mismatch==0,{"sampled":sampled,"mismatches":mismatch})

func run() -> void:
	change_scene_to_packed(Main)
	await frames()
	main = current_scene
	main.auto_process = false
	main.save_dir = "user://poc2_map_orientation_independent_20261023"
	main._on_action("new")
	var s: RefCounted = main.session
	var map: Control = main.ui.map
	s.seeds = 1000; s.unlocked.gatlinger = true
	var placed: Dictionary = s.place_helper("gatlinger",Vector2i(196,188),37)
	check("isolated_fixture",placed.get("ok",false))
	if not placed.get("ok",false): finish(); return
	var h: Dictionary = s.helpers[0]
	var original_terrain: PackedByteArray = s.state.terrain.duplicate()
	var original_stage: PackedByteArray = s.state.stage.duplicate()
	main.world.sync(0.0)
	await frames()
	projection_check(map,"mini_matches_real_camera")
	shot("mini-fog")
	var elapsed: float = s.clock.elapsed
	key(KEY_M); await frames(); main.tick(0.25)
	check("engine_open_pauses_time",map.expanded and s.paused and s.clock.elapsed==elapsed)
	projection_check(map,"full_matches_real_camera")
	terrain_check(map,"full_terrain_agrees_with_pick")
	var worst_roundtrip: float = 0.0
	for p: Vector2 in [Vector2(448,448),Vector2(220,260),Vector2(750,400),Vector2(160,700)]:
		worst_roundtrip = maxf(worst_roundtrip,map.logic_at(map.point_exact(p)).distance_to(p))
	check("forward_inverse_roundtrip",worst_roundtrip<=0.001,worst_roundtrip)
	shot("full-fog")
	s.known.fill(1); s.visible.fill(1); map.refresh_terrain(); map.queue_redraw(); await frames()
	shot("full-revealed")
	# Centre-near zoom anchor avoids intentional edge clamping; all three zoom levels tested once.
	var cursor: Vector2 = map.map_rect.get_center()+Vector2(8,-5)
	var anchor: Vector2 = map.logic_at(cursor)
	mouse(cursor,MOUSE_BUTTON_WHEEL_UP); await frames()
	var error_two: float = map.point(anchor).distance_to(cursor)
	mouse(cursor,MOUSE_BUTTON_WHEEL_UP); await frames()
	var error_four: float = map.point(anchor).distance_to(cursor)
	check("zoom_1_2_4_preserves_pointer_anchor",map.zoom==4 and error_two<=1 and error_four<=1,{"2x":error_two,"4x":error_four})
	terrain_check(map,"zoom_terrain_agrees_with_pick")
	# Return to 1, then zoom around helper to keep commands visible in the viewport.
	map.set_expanded(true)
	await frames()
	var helper_anchor: Vector2 = map.point(h.pos)
	mouse(helper_anchor,MOUSE_BUTTON_WHEEL_UP); await frames()
	mouse(map.point(h.pos),MOUSE_BUTTON_WHEEL_UP); await frames()
	mouse(map.point(h.pos)); await frames()
	check("engine_icon_selection_upright_controls",map.selected_id==h.id and map.selected_helper and map.remove_button.visible and map.supply_button.visible and map.remove_button.rotation==0 and map.supply_button.rotation==0)
	h.hp = 35.0; h.ammo = 17; map.queue_redraw(); await frames()
	shot("selected-zoom4")
	var before: Vector2 = h.home
	var target_cell: Vector2i = Vector2i(174,172)
	var target: Vector2 = Coords.cell_center_logic(target_cell)
	var target_pixel: Vector2 = map.point(target)
	check("order_fixture_walkable_clear_of_buttons",s.is_walkable_logic(target) and map.map_rect.has_point(target_pixel) and not map.remove_button.get_global_rect().has_point(target_pixel) and not map.supply_button.get_global_rect().has_point(target_pixel),{"cell":str(target_cell),"pixel":str(target_pixel),"remove":str(map.remove_button.get_global_rect())})
	mouse(target_pixel); await frames()
	var expected_home: Vector2 = Coords.cell_center_logic(Coords.logic_to_cell(map.logic_at(target_pixel)))
	check("engine_order_hits_projected_destination",h.home.distance_to(expected_home)<0.1 and h.home!=before,{"actual":str(h.home),"expected_cell_center":str(expected_home)})
	map.open_popup("supply"); await frames()
	var popup_home: Vector2 = h.home
	mouse(target_pixel+Vector2(15,10)); await frames()
	mouse(cursor,MOUSE_BUTTON_WHEEL_DOWN); await frames()
	check("popup_owns_clicks_and_zoom",map.popup.visible and h.home==popup_home and map.zoom==4 and s.clock.elapsed==elapsed)
	shot("popup")
	map.popup.hide(); map.set_expanded(true); await frames()
	mouse(map.point(h.pos)); await frames()
	var padding_home: Vector2 = h.home
	mouse(map.map_rect.position+Vector2(4,4)); await frames()
	check("diamond_padding_does_not_order",h.home==padding_home)
	# Hidden enemy/fossil must contribute no pixels even when their terrain is remembered.
	map.deselect()
	s.visible.fill(0); map.refresh_terrain(); map.queue_redraw(); await frames()
	var hidden: Image = shot("remembered-hidden")
	var saved_enemies: Array[Dictionary] = s.enemies.duplicate()
	var saved_nests: Array[Dictionary] = s.nests.duplicate()
	var saved_fossils: Array[Dictionary] = s.fossils.duplicate()
	s.enemies.clear(); s.nests.clear(); s.fossils.clear(); map.queue_redraw(); await frames()
	var absent: Image = root.get_texture().get_image()
	check("unknown_entities_leave_no_map_pixels",hidden.get_region(Rect2i(map.map_rect)).get_data()==absent.get_region(Rect2i(map.map_rect)).get_data())
	s.enemies.assign(saved_enemies); s.nests.assign(saved_nests); s.fossils.assign(saved_fossils)
	# Last-cell centre is a legitimate in-world icon even if final pixel rounding crosses the boundary.
	var edge_helper: Dictionary = h.duplicate(true)
	edge_helper.id = 987654; edge_helper.pos = Vector2(894,894); edge_helper.home = edge_helper.pos
	s.helpers.append(edge_helper); map.queue_redraw(); await frames()
	var edge_pixel: Vector2 = map.point(edge_helper.pos)
	mouse(edge_pixel); await frames()
	check("last_cell_icon_remains_selectable",map.selected_id==edge_helper.id and map.selected_helper,{"logic":str(edge_helper.pos),"pixel":str(edge_pixel),"inverse":str(map.logic_at(edge_pixel)),"selected_id":map.selected_id})
	shot("last-cell-icon")
	s.helpers.erase(edge_helper); map.deselect()
	check("map_does_not_mutate_world_tiles",s.state.terrain==original_terrain and s.state.stage==original_stage)
	check("pixel_viewport_nearest_integer",main.render_view.size==Vector2i(640,360) and main.view_rect.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST and root.content_scale_stretch==Window.CONTENT_SCALE_STRETCH_INTEGER and root.content_scale_size==Vector2i(640,360),{"window":str(root.size),"final_transform":str(root.get_final_transform()),"map_texture_filter":map.texture_filter})
	key(KEY_M); await frames()
	# Move test session within one terrain refresh interval. Terrain and anchors must share centre.
	s.position+=Vector2(5.3,-3.1); main.world.sync(0); await frames()
	terrain_check(map,"moving_mini_terrain_agrees_with_pick")
	projection_check(map,"moving_mini_still_matches_camera")
	shot("mini-moved")
	finish()

func finish() -> void:
	var failures: int = 0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	var result: FileAccess = FileAccess.open(OUT+"results.json",FileAccess.WRITE)
	result.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"input":"Input.parse_input_event only; root.unfocusable=true","not_run":["physical keyboard/mouse path","exported build","broad balance/save/long-run regression"]}," "))
	result.close()
	main.session.close(); main.queue_free()
	quit(1 if failures else 0)
