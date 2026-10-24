extends "res://tests/poc2/map_orientation/independent/verify.gd"
## Final limited retry after the icon-hit/world-boundary branch ordering correction.
func run() -> void:
	change_scene_to_packed(Main); await frames()
	main=current_scene; main.auto_process=false
	main.save_dir="user://poc2_map_orientation_independent_final_20261023"
	main._on_action("new")
	var s: RefCounted=main.session
	var map: Control=main.ui.map
	s.seeds=1000; s.unlocked.gatlinger=true
	s.place_helper("gatlinger",Vector2i(196,188),37)
	var h: Dictionary=s.helpers[0]
	s.known.fill(1); s.visible.fill(1)
	key(KEY_M); await frames()
	var edge: Dictionary=h.duplicate(true)
	edge.id=987654; edge.pos=Vector2(894,894); edge.home=edge.pos
	s.helpers.append(edge); map.queue_redraw(); await frames()
	var edge_pixel: Vector2=map.point(edge.pos)
	mouse(edge_pixel); await frames()
	check("final_last_cell_icon_selectable",map.selected_id==edge.id and map.selected_helper,{"pixel":str(edge_pixel),"inverse":str(map.logic_at(edge_pixel)),"selected":map.selected_id})
	shot("final-last-cell-selected")
	var before: Vector2=edge.home
	mouse(map.map_rect.position+Vector2(4,4)); await frames()
	check("final_distant_world_exterior_rejects_order",edge.home==before and map.selected_id==-1)
	s.helpers.erase(edge); map.deselect(); map.queue_redraw(); await frames()
	mouse(map.point(h.pos),MOUSE_BUTTON_WHEEL_UP); await frames()
	mouse(map.point(h.pos),MOUSE_BUTTON_WHEEL_UP); await frames()
	mouse(map.point(h.pos)); await frames()
	check("final_normal_icon_selection",map.selected_id==h.id and map.selected_helper and map.remove_button.visible and map.supply_button.visible)
	var target: Vector2=Coords.cell_center_logic(Vector2i(174,172))
	var pixel: Vector2=map.point(target)
	var valid_fixture: bool=s.is_walkable_logic(target) and map.map_rect.has_point(pixel) and not map.remove_button.get_global_rect().has_point(pixel) and not map.supply_button.get_global_rect().has_point(pixel)
	before=h.home
	mouse(pixel); await frames()
	var expected: Vector2=Coords.cell_center_logic(Coords.logic_to_cell(map.logic_at(pixel)))
	check("final_normal_order_remains_correct",valid_fixture and h.home==expected and h.home!=before,{"fixture":valid_fixture,"actual":str(h.home),"expected":str(expected)})
	map.open_popup("supply"); await frames()
	before=h.home
	mouse(map.map_rect.position+Vector2(4,4)); await frames()
	check("final_popup_still_owns_click",map.popup.visible and h.home==before and map.selected_id==h.id)
	var failures: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	var f: FileAccess=FileAccess.open(OUT+"final-results.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"input":"Input.parse_input_event only; root.unfocusable=true"}," ")); f.close()
	main.session.close(); main.queue_free(); quit(1 if failures else 0)
